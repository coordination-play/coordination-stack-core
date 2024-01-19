// @title Salary contract Cairo 2.4.1
// @author Yash (tg-@yashm001)
// @license MIT
// @notice Contract to disburse salary to contibutors

use starknet::ContractAddress;
use array::Array;

#[derive(Drop, Serde, starknet::Store)]
struct ContributorSalary {
    // @notice contributor salary earned so far
    cum_salary: u256,
    // @notice salary claimed so far
    claimed_salary: u256
}

//
// External Interfaces
//

#[starknet::interface]
trait IERC20<TContractState> {
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn balanceOf(self: @TContractState, account: ContractAddress) -> u256; // TODO Remove after regenesis
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn transferFrom(ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool; // TODO Remove after regenesis
}


#[starknet::interface]
trait IOrganisation<TContractState> {
    fn get_all_guilds(self: @TContractState) -> (u8, Array::<ContractAddress>);
    fn get_guild_monthly_total_contribution(self: @TContractState, month_id: u32, guild: ContractAddress) -> u32;
    fn get_guild_contributions_data(self: @TContractState, contributor: ContractAddress, guild: ContractAddress) -> Array<u32>;
    fn get_guild_points(self: @TContractState, contributor: ContractAddress, guild: ContractAddress) -> u32;
    fn get_treasury(self: @TContractState) -> ContractAddress;
}

//
// Contract Interface
//
#[starknet::interface]
trait ISalaryDistributor<TContractState> {
    // view functions
    fn token(self: @TContractState) -> ContractAddress;
    fn organisation(self: @TContractState) -> ContractAddress;
    fn get_cum_salary(self: @TContractState, contributor: ContractAddress) -> u256;
    fn get_claimed_salary(self: @TContractState, contributor: ContractAddress) -> u256;
    fn get_pool_amount(self: @TContractState, month_id: u32, guild: ContractAddress) -> u256;
    fn get_last_update_month_id(self: @TContractState) -> u32;

    // external functions
    fn add_fund_to_salary_pools(ref self: TContractState, month_id: u32, amounts: Array<u256>, guilds: Array<ContractAddress>);
    fn update_cum_salary(ref self: TContractState, contributor: ContractAddress);
    fn claim_salary(ref self: TContractState, recipient: ContractAddress);


}

#[starknet::contract]
mod SalaryDistributor {
    use traits::Into; // TODO remove intos when u256 inferred type is available
    use option::OptionTrait;
    use array::ArrayTrait;

    use starknet::{ContractAddress, ClassHash, SyscallResult, SyscallResultTrait, get_caller_address, get_contract_address, get_block_timestamp, contract_address_const};
    use starknet::syscalls::{replace_class_syscall, call_contract_syscall};
    use super::ContributorSalary;

    use super::{
        IERC20Dispatcher, IERC20DispatcherTrait, IOrganisationDispatcher, IOrganisationDispatcherTrait
    };
    // use openzeppelin::access::ownable::OwnableComponent;
    // component!(path: OwnableComponent, storage: ownable_storage, event: OwnableEvent);

    // #[abi(embed_v0)]
    // impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    
    // impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;


    // for debugging will remove after review
    use debug::PrintTrait;

    //
    // Storage Organisation
    //
    #[storage]
    struct Storage {
        _salary: LegacyMap::<ContractAddress, ContributorSalary>, // @dev salary for each contributor
        _token: ContractAddress, // @dev token to paid out salary in
        _salary_pool: LegacyMap::<(u32, ContractAddress), u256>, // @dev salary pool for specific month and guild
        _last_update_month_id_contributor: LegacyMap::<ContractAddress, u32>, // @dev to avoid unnecessary calculation of cum_salary
        _last_update_month_id: u32, // @dev to avoid unnecessary calculation of cum_salary
        _organisation: ContractAddress, // @dev organisation contract address
        // #[substorage(v0)]
        // ownable_storage: OwnableComponent::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        CumulativeSalaryUpdated: CumulativeSalaryUpdated,
        SalaryPoolAdded: SalaryPoolAdded,
        SalaryClaimed: SalaryClaimed,
        // #[flat]
        // OwnableEvent: OwnableComponent::Event
    }

    // @notice An event emitted whenever contributor cum salary is updated
    #[derive(Drop, starknet::Event)]
    struct CumulativeSalaryUpdated {
        month_id: u32,
        cum_salary: u256
    }

    // @notice An event emitted whenever funds are added to salary pool.
    #[derive(Drop, starknet::Event)]
    struct SalaryPoolAdded {
        month_id: u32, 
        guild: ContractAddress,
        pool_amount: u256
    }

    // @notice An event emitted whenever contribution claims salary
    #[derive(Drop, starknet::Event)]
    struct SalaryClaimed {
        amount: u256,
        recipient: ContractAddress
    }

    //
    // Constructor
    //

    // @notice Contract constructor
    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, token:ContractAddress, organisation: ContractAddress) {
        self._token.write(token);
        // self._token.write(contract_address_const::<0x005a643907b9a4bc6a55e9069c4fd5fd1f5c79a22470690f75556c4736e34426>()); // USDC
        self._organisation.write(organisation);

        // self.ownable_storage.initializer(owner)

    }

    #[external(v0)]
    impl SalaryDistributor of super::ISalaryDistributor<ContractState> {
        //
        // Getters
        //
        fn token(self: @ContractState) -> ContractAddress {
            self._token.read()
        }

        fn organisation(self: @ContractState) -> ContractAddress {
            self._organisation.read()
        }

        fn get_cum_salary(self: @ContractState, contributor: ContractAddress) -> u256 {
            InternalImpl::_calculate_cum_salary(self, contributor)
        }

        fn get_claimed_salary(self: @ContractState, contributor: ContractAddress) -> u256 {
            self._salary.read(contributor).claimed_salary
        }

        fn get_pool_amount(self: @ContractState, month_id: u32, guild: ContractAddress) -> u256 {
            self._salary_pool.read((month_id, guild))
        }

        fn get_last_update_month_id(self: @ContractState) -> u32 {
            self._last_update_month_id.read()
        }

        //
        // Setters
        //

        fn add_fund_to_salary_pools(ref self: ContractState, month_id: u32, amounts: Array<u256>, guilds: Array<ContractAddress>) {
            self._only_treasury();
            let caller = get_caller_address();
            let contract_address = get_contract_address();
            let mut amount_to_transfer = 0;
            let mut current_index = 0;
            assert(guilds.len() == amounts.len(), 'INVALID_INPUT');
            loop {
                if (current_index == guilds.len()) {
                    break;
                }
                let pool_amount = self._salary_pool.read((month_id, *guilds[current_index]));
                assert (pool_amount == 0, 'ALREADY_SET');
                amount_to_transfer += *amounts[current_index];
                self._salary_pool.write((month_id, *guilds[current_index]), *amounts[current_index]);

                self.emit(SalaryPoolAdded{month_id: month_id, guild: *guilds[current_index], pool_amount: *amounts[current_index]});
                current_index += 1;
            };
            let token = self._token.read();
            let tokenDispatcher = IERC20Dispatcher { contract_address: token };
            // tokenDispatcher.transfer_from(caller, contract_address, amount_to_transfer);
            tokenDispatcher.transferFrom(caller, contract_address, amount_to_transfer);
            self._last_update_month_id.write(month_id);
        }

        fn update_cum_salary(ref self: ContractState, contributor: ContractAddress) {
            let last_update_month_id_contributor = self._last_update_month_id_contributor.read(contributor);
            let last_update_month_id = self._last_update_month_id.read();
            if (last_update_month_id_contributor == last_update_month_id) {
                return; // cum_salary already up to date
            }

            let cum_salary = InternalImpl::_calculate_cum_salary(@self, contributor);
            let old_salary = self._salary.read(contributor);
            self._salary.write(contributor, ContributorSalary{cum_salary: cum_salary, claimed_salary: old_salary.claimed_salary });
            self.emit(CumulativeSalaryUpdated{month_id: last_update_month_id_contributor, cum_salary: cum_salary});
            self._last_update_month_id_contributor.write(contributor, last_update_month_id);
        }

        fn claim_salary(ref self: ContractState, recipient: ContractAddress) {
            let contributor = get_caller_address();
            self.update_cum_salary(contributor);
            let salary = self._salary.read(contributor);
            let claimable_amount = salary.cum_salary - salary.claimed_salary;
            assert(claimable_amount > 0, 'ZERO_CLAIMABLE_AMOUNT');

            let token = self._token.read();
            let tokenDispatcher = IERC20Dispatcher { contract_address: token };
            // update claimed salary
            self._salary.write(contributor, ContributorSalary{cum_salary: salary.cum_salary, claimed_salary: salary.claimed_salary + claimable_amount});
            tokenDispatcher.transfer(recipient, claimable_amount);
            self.emit(SalaryClaimed{amount: claimable_amount, recipient: recipient});

        }

    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {

        fn _calculate_cum_salary(self: @ContractState, contributor: ContractAddress) -> u256 {
            let mut cum_salary = 0;
            let organisation = self._organisation.read();
            let organisation_dispatcher = IOrganisationDispatcher { contract_address: organisation };
            let (num_guilds, guilds) =  organisation_dispatcher.get_all_guilds();
            let mut current_index = 0;
            loop {
                if current_index == num_guilds.into() {
                    break true;
                }
                cum_salary += InternalImpl::_calculate_guild_cum_salary(self, contributor, *guilds[current_index], organisation_dispatcher);
                current_index += 1;
            };
            cum_salary
        }

        fn _calculate_guild_cum_salary(self: @ContractState, contributor: ContractAddress, guild: ContractAddress, organisation_dispatcher: IOrganisationDispatcher) -> u256 {
            
            let contribution_data = organisation_dispatcher.get_guild_contributions_data(contributor, guild);

            let mut cum_salary = 0;
            let mut current_index = 0;
            loop {
                if (current_index == contribution_data.len()) {
                    break;
                }

                let pool_amount = self._salary_pool.read((*contribution_data[current_index], guild));
                let total_contribution: u256 = organisation_dispatcher.get_guild_monthly_total_contribution(*contribution_data[current_index], guild).into();
                let contributor_point_earned: u256 = (*contribution_data[current_index + 1]).into();
                cum_salary += (pool_amount * contributor_point_earned) / total_contribution;
                current_index += 2;

            };
            cum_salary
        }

        fn _only_treasury(ref self: ContractState) {
            let caller = get_caller_address();
            let organisation = self._organisation.read();
            let organisation_dispatcher = IOrganisationDispatcher {contract_address: organisation};
            let treasury = organisation_dispatcher.get_treasury();
            assert(caller == treasury, 'NOT_TREASURY');
        }

    }


}