// @title Coordination-stack Guild in Cairo 2.4.1
// @author Yash (tg-@yashm001)
// @license MIT
// @notice Guild, to store guilds contribution points;

use starknet::ContractAddress;
use array::Array;


#[derive(Copy, Drop, Serde, starknet::Store)]
struct MonthlyContribution {
    // @notice Contributor Address, used in update_contribution function
    contributor: ContractAddress,
    // @notice Contribution for guilds
    point: u32,
}

#[starknet::interface]
trait IOrganisation<TContractState> {
    fn is_granted(self: @TContractState, where: ContractAddress, who: ContractAddress, permission_id: felt252) -> bool;
}



//
// Contract Interface
//
#[starknet::interface]
trait IGuild<TContractState> {
    // view functions
    fn name(self: @TContractState) -> felt252;
    fn get_cum_contributions_points(self: @TContractState, contributor: ContractAddress) -> u32;
    fn get_monthly_total_contribution(self: @TContractState, month_id: u32) -> u32;
    fn get_contributions_data(self: @TContractState, contributor: ContractAddress) -> Array<u32>;
    fn get_monthly_contribution_points(self: @TContractState, contributor: ContractAddress, month_id: u32) -> u32;


    // external functions
    fn update_contributions(ref self: TContractState, month_id: u32, contributions: Array::<MonthlyContribution>);
    fn migrate_points(ref self: TContractState, old_address: ContractAddress, new_address: ContractAddress);

}


#[starknet::contract]
mod Guild {
    use core::array::ArrayTrait;
use starknet::{ContractAddress, ClassHash, get_caller_address, get_contract_address, get_block_timestamp, contract_address_const};
    use starknet::syscalls::{replace_class_syscall, call_contract_syscall};
    use coordination_stack_core::utils::array_storage::StoreU32Array;

    use super::{MonthlyContribution, IOrganisationDispatcher, IOrganisationDispatcherTrait};

    const ROOT_PERMISSION_ID: felt252 = 'ROOT_PERMISSION';
    const POINTS_ALLOCATOR_ID: felt252 = 'POINTS_ALLOCATOR';

    //
    // Storage Guild
    //
    #[storage]
    struct Storage {
        _name: felt252, // @dev name of the guild
        _organisation: ContractAddress, // @dev oragnisation contract address
        _contributions: LegacyMap::<ContractAddress, u32>, // @dev cum contributions points for each contributor 
        // @reviewer - another way to store _contributions_data is LegacyMap::<(ContractAddress, u32), u32>, 
        // it will save gas cost will fetching contribution for a specfic month id
        // but will be expensive and difficult to get all the contribution on-chain (by another contract), 
        // PS: off-chain can fetched from indexeer 
        _contributions_data: LegacyMap::<ContractAddress, Array<u32>>, // @dev contributions data for specific contributor 
        _total_montly_contribution: LegacyMap::<u32, u32>, // @dev total contribution points allocated each month [month_id => points]
        _last_update_id: u32, // @dev contribution update id
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ContributionUpdated: ContributionUpdated,
        Migrated: Migrated,
    }

    // @notice An event emitted whenever contribution is updated
    #[derive(Drop, starknet::Event)]
    struct ContributionUpdated {
        contributor: ContractAddress,
        month_id: u32,
        points_earned: u32
    }

    // @notice An event emitted whenever points are migrated
    #[derive(Drop, starknet::Event)]
    struct Migrated {
        old_address: ContractAddress, 
        new_address: ContractAddress
    }


    //
    // Constructor
    //

    // @notice Contract constructor
    #[constructor]
    fn constructor(ref self: ContractState, name: felt252, organisation: ContractAddress) {
        self._name.write(name);
        self._organisation.write(organisation);
    }

    #[abi(embed_v0)]
    impl Guild of super::IGuild<ContractState> {
        //
        // Getters
        //
        fn name(self: @ContractState) -> felt252 {
            self._name.read()
        }

        fn get_cum_contributions_points(self: @ContractState, contributor: ContractAddress) -> u32 {
            self._contributions.read(contributor)
        }

        fn get_monthly_total_contribution(self: @ContractState, month_id: u32) -> u32 {
            self._total_montly_contribution.read(month_id)
        }

        fn get_contributions_data(self: @ContractState, contributor: ContractAddress) -> Array<u32> {
            self._contributions_data.read(contributor)      
        }  

        fn get_monthly_contribution_points(self: @ContractState, contributor: ContractAddress, month_id: u32) -> u32 {
            let contribution_data = self._contributions_data.read(contributor);
            let mut current_index = contribution_data.len();
            let point = loop {
                if (current_index == 0) {
                    break 0;
                }
                if(month_id == *contribution_data[current_index - 2]) {
                    break *contribution_data[current_index - 1];
                }

                current_index -= 2;
            };
            point
        }


        //
        // Setters
        //
        fn update_contributions(ref self: ContractState, month_id: u32, contributions: Array::<MonthlyContribution>) {
            InternalImpl::_auth(ref self, POINTS_ALLOCATOR_ID);
            let mut current_index = 0;

            // for keeping track of cummulative guild points for that month.
            let mut total_cum = 0_u32;

            loop {
                if (current_index == contributions.len()) {
                    break;
                }
                let new_contributions: MonthlyContribution = *contributions[current_index];
                let contributor: ContractAddress = new_contributions.contributor;
                let old_contribution = self._contributions.read(contributor);

                let new_cum_point = InternalImpl::_update_contribution_data(ref self, old_contribution, new_contributions.point, month_id, contributor);
                
                total_cum += new_contributions.point;
                self._contributions.write(contributor, new_cum_point);

                current_index += 1;

                self.emit(ContributionUpdated{contributor: contributor, month_id: month_id, points_earned: new_contributions.point});

            };
            self._total_montly_contribution.write(month_id, total_cum);

        }



        fn migrate_points(ref self: ContractState, old_address: ContractAddress, new_address: ContractAddress ) {
            self._only_organisation();
            let existing_contribution = self._contributions.read(new_address);
            assert(existing_contribution.is_zero(), 'CONTRIBUTION_ALREADY_EXISTS');

            let contribution = self._contributions.read(old_address);
            self._contributions.write(old_address, 0);
            self._contributions.write(new_address, contribution);

            let contributions_data = self._contributions_data.read(old_address);

            self._contributions_data.write(new_address, contributions_data);
            self._contributions_data.write(old_address, ArrayTrait::new());
            

            self.emit(Migrated{old_address: old_address, new_address: new_address});
        }

    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        //
        // Internals
        //

        fn _update_contribution_data(ref self: ContractState, old_guild_score: u32, new_contribution_score: u32, month_id: u32, contributor: ContractAddress) -> u32 {
            let new_guild_score = old_guild_score + new_contribution_score;
            if(new_contribution_score != 0) {
                let mut contribution_data = self._contributions_data.read(contributor);
                // check if contibution already exists for month id
                // if yes, skip (TODO: add a challenge window in newer version)
                // @reviwer checking only the last month_id, assuming months are uploaded forward monthwise only
                let last_contributed_month_id = *contribution_data.at(contribution_data.len() - 2);
                if last_contributed_month_id == month_id {
                    return (old_guild_score);
                }
                contribution_data.append(month_id);
                contribution_data.append(new_contribution_score);

                self._contributions_data.write(contributor, contribution_data);
            }
            (new_guild_score)
        }

        fn _only_organisation(ref self: ContractState) {
            let caller = get_caller_address();
            let organisation = self._organisation.read();
            assert(caller == organisation, 'NOT_ORGANISATION');
        }

        fn _auth(ref self: ContractState, permission_id: felt252) {
            let caller = get_caller_address();
            let current_contract = get_contract_address();

            let organisation_dispatcher = IOrganisationDispatcher {contract_address: self._organisation.read()};            
            assert(organisation_dispatcher.is_granted(current_contract, caller, permission_id), 'UNAUTHORISED');
        }

    } 

}
