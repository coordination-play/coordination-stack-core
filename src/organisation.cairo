// @title Coordination-stack Organisation in Cairo 2.4.1
// @author Mesh Finance
// @license MIT
// @notice Organisation, main contract for each org and to store contribution points

use starknet::ContractAddress;
use array::Array;
use starknet::ClassHash;

//
// External Interfaces
//

#[starknet::interface]
trait IGuild<TContractState> {
    fn get_cum_contributions_points(self: @TContractState, contributor: ContractAddress) -> u32;
    fn get_monthly_total_contribution(self: @TContractState, month_id: u32) -> u32;
    fn get_contributions_data(self: @TContractState, contributor: ContractAddress) -> Array<u32>;
    fn get_monthly_contribution_points(self: @TContractState, contributor: ContractAddress, month_id: u32) -> u32;

    fn migrate_points(ref self: TContractState, old_address: ContractAddress, new_address: ContractAddress);
}

#[starknet::interface]
trait IFactory<TContractState> {
    fn get_guild_contract_class_hash(self: @TContractState) -> ClassHash;
}


//
// Contract Interface
//
#[starknet::interface]
trait IOrganisation<TContractState> {
    // view functions
    fn get_cum_contributions_points(self: @TContractState, contributor: ContractAddress) -> Array<u32>;
    fn get_all_guilds(self: @TContractState) -> (u8, Array::<ContractAddress>);
    fn get_guild_monthly_total_contribution(self: @TContractState, month_id: u32, guild: ContractAddress) -> u32;
    fn get_guild_contributions_data(self: @TContractState, contributor: ContractAddress, guild: ContractAddress) -> Array<u32>;
    fn get_guild_points(self: @TContractState, contributor: ContractAddress, guild: ContractAddress) -> u32;
    fn get_guild_contribution_for_month(self: @TContractState, contributor: ContractAddress, month_id: u32, guild: ContractAddress) -> u32;
    fn get_migartion_queued_state(self: @TContractState, hash: felt252 ) -> bool;
    fn get_salary_contract_class_hash(self: @TContractState) -> ClassHash;
    fn get_salary_contract(self: @TContractState) -> ContractAddress;

    // external functions
    fn add_guild(ref self: TContractState, guild_name: felt252, owner: ContractAddress) -> ContractAddress;
    fn update_organisation_name(ref self: TContractState, new_name: felt252);
    fn update_salary_contract(ref self: TContractState, owner: ContractAddress, token: ContractAddress);
    fn migrate_points_initiated_by_holder(ref self: TContractState, new_address: ContractAddress);
    fn execute_migrate_points_initiated_by_holder(ref self: TContractState, old_address: ContractAddress, new_address: ContractAddress);
    fn replace_salary_contract_hash(ref self: TContractState, new_salary_contract_class: ClassHash);

}


#[starknet::contract]
mod Organisation {
    use traits::Into; // TODO remove intos when u256 inferred type is available
    use option::OptionTrait;
    use array::{ArrayTrait, SpanTrait};
    use result::ResultTrait;
    use zeroable::Zeroable;
    use hash::LegacyHash;
    use starknet::{ContractAddress, ClassHash, SyscallResult, SyscallResultTrait, get_caller_address, get_contract_address, get_block_timestamp, contract_address_const};
    use integer::{u128_try_from_felt252, u256_sqrt, u256_from_felt252};
    use starknet::syscalls::{replace_class_syscall, deploy_syscall};
    use coordination_stack_core::array_storage::StoreFelt252Array;
    use coordination_stack_core::array_storage::StoreU32Array;

    use super::{//Guild, Contribution, MonthlyContribution, 
    IGuildDispatcher, IGuildDispatcherTrait, IFactoryDispatcher, IFactoryDispatcherTrait};

    use openzeppelin::access::ownable::OwnableComponent;

    component!(path: OwnableComponent, storage: ownable_storage, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;


    //
    // Storage Organisation
    //
    #[storage]
    struct Storage {
        _name: felt252, // @dev name of the Organisation
        _factory: ContractAddress, // @dev factory contract to deploy new guilds
        _all_guilds: LegacyMap::<u8, ContractAddress>, // @dev array to store all the guilds
        _num_of_guilds: u8, // @dev to store total number of guilds
        _guilds_id: LegacyMap::<ContractAddress, u8>, // @dev  mapping to store (Guild address => Id)
        _queued_migrations: LegacyMap::<felt252, bool>, // @dev flag to store queued migration requests.
        _salary_contract_class_hash: ClassHash,
        _salary: ContractAddress, // @dev salary contract to payot salary.
        #[substorage(v0)]
        ownable_storage: OwnableComponent::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        MigrationQueued: MigrationQueued,
        Migrated: Migrated,
        GuildAdded: GuildAdded,
        NameChanged: NameChanged,
        #[flat]
        OwnableEvent: OwnableComponent::Event
    }


    // @notice An event emitted whenever migration is queued via migrate_points_initiated_by_holder
    #[derive(Drop, starknet::Event)]
    struct MigrationQueued {
        old_address: ContractAddress, 
        new_address: ContractAddress
    }

    // @notice An event emitted whenever SBT is migrated
    #[derive(Drop, starknet::Event)]
    struct Migrated {
        old_address: ContractAddress, 
        new_address: ContractAddress
    }

    // @notice An event emitted whenever a new guild is added via add_guild
    #[derive(Drop, starknet::Event)]
    struct GuildAdded {
        name: felt252, 
        id: u8,
        guild: ContractAddress
    }

    // @notice An event emitted whenever organisation name is updated via update_organisation_name
    #[derive(Drop, starknet::Event)]
    struct NameChanged {
        old_name: felt252, 
        new_name: felt252
    }


    //
    // Constructor
    //

    // @notice Contract constructor
    #[constructor]
    fn constructor(ref self: ContractState, name: felt252, owner: ContractAddress, factory: ContractAddress) {
        self._name.write(name);
        self._factory.write(factory);

        self.ownable_storage.initializer(owner)

    }

    #[external(v0)]
    impl Organisation of super::IOrganisation<ContractState> {
        //
        // Getters
        //
        // @notice Get all the guilds registered
        // @return all_guilds_len Length of `all_guilds` array
        // @return all_guilds Array of addresses of all guilds
        fn get_all_guilds(self: @ContractState) -> (u8, Array::<ContractAddress>) { 
            let mut all_guilds_array = ArrayTrait::<ContractAddress>::new();
            let num_guilds = self._num_of_guilds.read();
            let mut current_index = 1; // guild id starts from 1, 0 is reserve for not exists
            loop {
                if current_index == num_guilds + 1 {
                    break true;
                }
                all_guilds_array.append(self._all_guilds.read(current_index));
                current_index += 1;
            };
            (num_guilds, all_guilds_array)
        }

        fn get_cum_contributions_points(self: @ContractState, contributor: ContractAddress) -> Array<u32> {
            let num_guilds = self._num_of_guilds.read();
            let mut contributions = ArrayTrait::<u32>::new();
            let mut current_index = 1; // guild id starts from 1, 0 is reserve for not exists
            loop {
                if (current_index == num_guilds + 1) {
                    break;
                }
                let guild = self._all_guilds.read(current_index);
                let guild_dispatcher = IGuildDispatcher {contract_address: guild};
                let guild_cum_points = guild_dispatcher.get_cum_contributions_points(contributor);
                
                contributions.append(guild_cum_points);
                current_index += 1;
            };
            contributions
        }

        fn get_guild_monthly_total_contribution(self: @ContractState, month_id: u32, guild: ContractAddress) -> u32 {
            let guild_dispatcher = IGuildDispatcher {contract_address: guild};
            guild_dispatcher.get_monthly_total_contribution(month_id)
        }

        fn get_guild_contributions_data(self: @ContractState, contributor: ContractAddress, guild: ContractAddress) -> Array<u32> {
            let guild_dispatcher = IGuildDispatcher {contract_address: guild};
            guild_dispatcher.get_contributions_data(contributor)
        }

        fn get_guild_points(self: @ContractState, contributor: ContractAddress, guild: ContractAddress) -> u32 {
            let guild_dispatcher = IGuildDispatcher {contract_address: guild};
            guild_dispatcher.get_cum_contributions_points(contributor)  
        }

        fn get_guild_contribution_for_month(self: @ContractState, contributor: ContractAddress, month_id: u32, guild: ContractAddress) -> u32 {
            let guild_dispatcher = IGuildDispatcher {contract_address: guild};
            guild_dispatcher.get_monthly_contribution_points(contributor, month_id)
        }

        fn get_migartion_queued_state(self: @ContractState, hash: felt252 ) -> bool {
            self._queued_migrations.read(hash)
        }

        // @notice Get the class hash of the Salary contract.
        // @return class_hash
        fn get_salary_contract_class_hash(self: @ContractState) -> ClassHash {
            self._salary_contract_class_hash.read()
        }

        fn get_salary_contract(self: @ContractState) -> ContractAddress {
            self._salary.read()
        }

        //
        // Setters
        //

        fn add_guild(ref self: ContractState, guild_name: felt252, owner: ContractAddress) -> ContractAddress {
            self.ownable_storage.assert_only_owner();
            let current_contract = get_contract_address();
            let factory = self._factory.read();
            let factory_dispatcher = IFactoryDispatcher {contract_address: factory};
            let guild_contract_class_hash = factory_dispatcher.get_guild_contract_class_hash();

            let mut constructor_calldata = Default::default();
            Serde::serialize(@guild_name, ref constructor_calldata);
            Serde::serialize(@current_contract, ref constructor_calldata);
            Serde::serialize(@owner, ref constructor_calldata);

            let syscall_result = deploy_syscall(
                guild_contract_class_hash, 0, constructor_calldata.span(), false
            );
            let (guild, _) = syscall_result.unwrap_syscall();

            let num_guilds = self._num_of_guilds.read();
            // self._guilds.write(guild_name, num_guilds + 1);
            // let guild = Guild {name: guild_name, guild: guild_address};
            self._all_guilds.write(num_guilds + 1, guild);
            self._num_of_guilds.write(num_guilds + 1);

            self.emit(GuildAdded {name: guild_name, id: num_guilds + 1, guild: guild});

            guild
        }

        fn update_organisation_name(ref self: ContractState, new_name: felt252) {
            self.ownable_storage.assert_only_owner();
            let current_name = self._name.read();
            self._name.write(new_name);

            self.emit(NameChanged {old_name: current_name, new_name: new_name});
        }

        fn update_salary_contract(ref self: ContractState, owner: ContractAddress, token: ContractAddress) {
            self.ownable_storage.assert_only_owner();
            let current_contract = get_contract_address();
            let salary_contract_class_hash = self._salary_contract_class_hash.read();

            let mut constructor_calldata = Default::default();
            Serde::serialize(@owner, ref constructor_calldata);
            Serde::serialize(@token, ref constructor_calldata);
            Serde::serialize(@current_contract, ref constructor_calldata);

            let syscall_result = deploy_syscall(
                salary_contract_class_hash, 0, constructor_calldata.span(), false
            );
            let (salary, _) = syscall_result.unwrap_syscall();
            self._salary.write(salary);
        }

        fn migrate_points_initiated_by_holder(ref self: ContractState, new_address: ContractAddress) {
            // TODO: if new address already have any contribution points, if yes return. 
            let caller = get_caller_address();
            let migration_hash: felt252 = LegacyHash::hash(caller.into(), new_address);

            self._queued_migrations.write(migration_hash, true);

            self.emit(MigrationQueued { old_address: caller, new_address: new_address});

        }

        // @Notice the function has only_owner modifier to prevent user to use this function to tranfer SBT anytime.
        fn execute_migrate_points_initiated_by_holder(ref self: ContractState, old_address: ContractAddress, new_address: ContractAddress) {
            self.ownable_storage.assert_only_owner();
            let migration_hash: felt252 = LegacyHash::hash(old_address.into(), new_address);
            let is_queued = self._queued_migrations.read(migration_hash);

            assert(is_queued == true, 'NOT_QUEUED');

            InternalImpl::_migrate_points(ref self, old_address, new_address);
            self._queued_migrations.write(migration_hash, false);

        }
        // @notice This replaces _salary_contract_class_hash used to deploy new salary
        // @dev Only owner can call
        // @param new_salary_contract_class New _salary_contract_class_hash
        fn replace_salary_contract_hash(ref self: ContractState, new_salary_contract_class: ClassHash) {
            self.ownable_storage.assert_only_owner();
            assert(!new_salary_contract_class.is_zero(), 'must be non zero');
            self._salary_contract_class_hash.write(new_salary_contract_class);
        }

    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        //
        // Internals
        //

        fn _migrate_points(ref self: ContractState, old_address: ContractAddress, new_address: ContractAddress) {

            let num_guilds = self._num_of_guilds.read();
            
            let mut current_index = 1; // guild index starts from 1, instead of zero
            loop {
                if (current_index == num_guilds + 1) {
                    break;
                }
                let guild = self._all_guilds.read(current_index);
                let guild_dispatcher = IGuildDispatcher {contract_address: guild};
                guild_dispatcher.migrate_points(old_address, new_address);
            };

            self.emit(Migrated{old_address: old_address, new_address: new_address});

        }

    } 

}

