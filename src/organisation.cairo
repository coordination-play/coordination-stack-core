// @title Coordination-stack Organisation in Cairo 2.4.1
// @author Yash (tg - @yashm001)
// @license MIT
// @notice Organisation, main contract for each org and to store contribution points

use starknet::ContractAddress;
use starknet::ClassHash;

#[derive(Copy, Drop, Serde, starknet::Store)]
struct Guild {
    // @notice name of the guild
    name: felt252,
    // @notice guild contract address
    guild: ContractAddress
}

//
// External Interfaces
//

#[starknet::interface]
trait IGuild<TContractState> {
    fn name(self: @TContractState) -> felt252;
    fn get_cum_contributions_points(self: @TContractState, contributor: ContractAddress) -> u32;
    fn get_monthly_total_contribution(self: @TContractState, month_id: u32) -> u32;
    fn get_contributions_data(self: @TContractState, contributor: ContractAddress) -> Array<u32>;
    fn get_monthly_contribution_points(self: @TContractState, contributor: ContractAddress, month_id: u32) -> u32;

    fn migrate_points(ref self: TContractState, old_address: ContractAddress, new_address: ContractAddress);
}

#[starknet::interface]
trait IFactory<TContractState> {
    fn get_guild_contract_class_hash(self: @TContractState) -> ClassHash;
    fn get_salary_contract_class_hash(self: @TContractState) -> ClassHash;
    fn get_treasury_contract_class_hash(self: @TContractState) -> ClassHash;
}



//
// Contract Interface
//
#[starknet::interface]
trait IOrganisation<TContractState> {
    // view functions
    fn name(self: @TContractState) -> felt252;
    fn metadata(self: @TContractState) -> Span<felt252>;
    fn get_cum_contributions_points(self: @TContractState, contributor: ContractAddress) -> Array<u32>;
    fn get_all_guilds(self: @TContractState) -> (u8, Array::<ContractAddress>);
    fn get_all_guilds_details(self: @TContractState) -> (u8, Array::<Guild>);
    fn get_guild_monthly_total_contribution(self: @TContractState, month_id: u32, guild: ContractAddress) -> u32;
    fn get_guild_contributions_data(self: @TContractState, contributor: ContractAddress, guild: ContractAddress) -> Array<u32>;
    fn get_guild_points(self: @TContractState, contributor: ContractAddress, guild: ContractAddress) -> u32;
    fn get_guild_contribution_for_month(self: @TContractState, contributor: ContractAddress, month_id: u32, guild: ContractAddress) -> u32;
    fn get_migartion_queued_state(self: @TContractState, hash: felt252 ) -> bool;
    fn get_salary_distributor_contract(self: @TContractState) -> ContractAddress;
    fn get_treasury(self: @TContractState) -> ContractAddress;

    // external functions
    fn add_guild(ref self: TContractState, guild_name: felt252, owner: ContractAddress) -> ContractAddress;
    fn update_organisation_name(ref self: TContractState, new_name: felt252);
    fn update_organisation_metadata(ref self: TContractState, new_metadata: Span<felt252>);
    fn update_salary_distributor_contract(ref self: TContractState, token: ContractAddress);
    fn add_treasury_contract(ref self: TContractState, owner: ContractAddress);
    fn migrate_points_initiated_by_holder(ref self: TContractState, new_address: ContractAddress);
    fn execute_migrate_points_initiated_by_holder(ref self: TContractState, old_address: ContractAddress, new_address: ContractAddress);

}


#[starknet::contract]
mod Organisation {
    use hash::LegacyHash;
    use starknet::{ContractAddress, ClassHash, SyscallResult, SyscallResultTrait, get_caller_address, get_contract_address, get_block_timestamp, contract_address_const};
    use starknet::syscalls::{replace_class_syscall, deploy_syscall};
    use coordination_stack_core::utils::span_storage::StoreSpanFelt252;

    use super::{Guild, IGuildDispatcher, IGuildDispatcherTrait, IFactoryDispatcher, IFactoryDispatcherTrait};

    use coordination_stack_core::component::permission_manager::PermissionManagerComponent;

    component!(path: PermissionManagerComponent, storage: permission_manager_storage, event: PermissionManagerEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = PermissionManagerComponent::PermissionManagerImpl<ContractState>;
    
    impl OwnableInternalImpl = PermissionManagerComponent::InternalImpl<ContractState>;


    const MODERATOR_ID: felt252 = 'MODERATOR';
    const MIGRATION_AUTHORISER_ID: felt252 = 'MIGRATION_AUTHORISER';
    const ROOT_PERMISSION_ID: felt252 = 'ROOT_PERMISSION';
    //
    // Storage Organisation
    //
    #[storage]
    struct Storage {
        _name: felt252, // @dev name of the Organisation
        _metadata: Span<felt252>, // @dev metadata of the Organisation
        _factory: ContractAddress, // @dev factory contract to deploy new guilds
        _all_guilds: LegacyMap::<u8, ContractAddress>, // @dev array to store all the guilds
        _num_of_guilds: u8, // @dev to store total number of guilds
        _guilds_id: LegacyMap::<ContractAddress, u8>, // @dev  mapping to store (Guild address => Id)
        _queued_migrations: LegacyMap::<felt252, bool>, // @dev flag to store queued migration requests.
        _salary_contract_class_hash: ClassHash,
        _salary_distributor: ContractAddress, // @dev salary contract to payout salary.
        _treasury: ContractAddress, // @dev Treasury contract to manage org funds.
        #[substorage(v0)]
        permission_manager_storage: PermissionManagerComponent::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        MigrationQueued: MigrationQueued,
        Migrated: Migrated,
        GuildAdded: GuildAdded,
        NameChanged: NameChanged,
        MetadataUpdated: MetadataUpdated,
        #[flat]
        PermissionManagerEvent: PermissionManagerComponent::Event
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

    // @notice An event emitted whenever organisation metadata is updated via update_organisation_metadata
    #[derive(Drop, starknet::Event)]
    struct MetadataUpdated {
        old_metadata: Span<felt252>, 
        new_metadata: Span<felt252>
    }


    //
    // Constructor
    //

    // @notice Contract constructor
    #[constructor]
    fn constructor(ref self: ContractState, name: felt252, metadata: Span<felt252>, owner: ContractAddress, factory: ContractAddress) {
        self._name.write(name);
        self._metadata.write(metadata);
        self._factory.write(factory);

        self.permission_manager_storage.initializer(owner);

    }

    #[external(v0)]
    impl Organisation of super::IOrganisation<ContractState> {
        //
        // Getters
        //
        fn name(self: @ContractState) -> felt252 {
            self._name.read()
        }

        fn metadata(self: @ContractState) -> Span<felt252> {
            self._metadata.read()
        }

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

        // @notice Get all the guilds registered
        // @return all_guilds_len Length of `all_guilds` array
        // @return all_guilds Array of Guild of all guilds
        // @Notice This function is required for frontend until indexer is live
        fn get_all_guilds_details(self: @ContractState) -> (u8, Array::<Guild>) { 
            let mut all_guilds_array = ArrayTrait::<Guild>::new();
            let num_guilds = self._num_of_guilds.read();
            let mut current_index = 1; // guild id starts from 1, 0 is reserve for not exists
            loop {
                if current_index == num_guilds + 1 {
                    break true;
                }
                let guild_address = self._all_guilds.read(current_index);
                let guild_dispatcher = IGuildDispatcher {contract_address: guild_address};
                let name = guild_dispatcher.name();
                let guild = Guild {name: name, guild: guild_address};
                all_guilds_array.append(guild);
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


        fn get_salary_distributor_contract(self: @ContractState) -> ContractAddress {
            self._salary_distributor.read()
        }

        fn get_treasury(self: @ContractState) -> ContractAddress {
            self._treasury.read()
        }

        //
        // Setters
        //

        fn add_guild(ref self: ContractState, guild_name: felt252, owner: ContractAddress) -> ContractAddress {
            // self.ownable_storage.assert_only_owner();
            InternalImpl::_auth(ref self, ROOT_PERMISSION_ID);
            let current_contract = get_contract_address();
            let factory = self._factory.read();
            let factory_dispatcher = IFactoryDispatcher {contract_address: factory};
            let guild_contract_class_hash = factory_dispatcher.get_guild_contract_class_hash();

            let mut constructor_calldata = Default::default();
            Serde::serialize(@guild_name, ref constructor_calldata);
            Serde::serialize(@current_contract, ref constructor_calldata);
            // Serde::serialize(@owner, ref constructor_calldata);

            let syscall_result = deploy_syscall(
                guild_contract_class_hash, 0, constructor_calldata.span(), false
            );
            let (guild, _) = syscall_result.unwrap_syscall();

            // Giving guild root priviledges to owner of Guild
            self.permission_manager_storage.grant(guild, owner, ROOT_PERMISSION_ID);

            let num_guilds = self._num_of_guilds.read();
            // self._guilds.write(guild_name, num_guilds + 1);
            // let guild = Guild {name: guild_name, guild: guild_address};
            self._all_guilds.write(num_guilds + 1, guild);
            self._num_of_guilds.write(num_guilds + 1);

            self.emit(GuildAdded {name: guild_name, id: num_guilds + 1, guild: guild});

            guild
        }

        fn update_organisation_name(ref self: ContractState, new_name: felt252) {
            // self.ownable_storage.assert_only_owner();
            InternalImpl::_auth(ref self, MODERATOR_ID);
            let current_name = self._name.read();
            self._name.write(new_name);

            self.emit(NameChanged {old_name: current_name, new_name: new_name});
        }

        fn update_organisation_metadata(ref self: ContractState, new_metadata: Span<felt252>) {
            // self.ownable_storage.assert_only_owner();
            InternalImpl::_auth(ref self, MODERATOR_ID);
            let current_metadata = self._metadata.read();
            self._metadata.write(new_metadata);

            self.emit(MetadataUpdated {old_metadata: current_metadata, new_metadata: new_metadata});
        }


        fn update_salary_distributor_contract(ref self: ContractState, token: ContractAddress) {
            InternalImpl::_auth(ref self, ROOT_PERMISSION_ID);
            let current_contract = get_contract_address();
            let factory = self._factory.read();
            let factory_dispatcher = IFactoryDispatcher {contract_address: factory};
            let salary_contract_class_hash = factory_dispatcher.get_salary_contract_class_hash();

            let mut constructor_calldata = Default::default();
            Serde::serialize(@token, ref constructor_calldata);
            Serde::serialize(@current_contract, ref constructor_calldata);

            let syscall_result = deploy_syscall(
                salary_contract_class_hash, 0, constructor_calldata.span(), false
            );
            let (salary, _) = syscall_result.unwrap_syscall();
            self._salary_distributor.write(salary);
        }

        fn add_treasury_contract(ref self: ContractState, owner: ContractAddress) {
            InternalImpl::_auth(ref self, ROOT_PERMISSION_ID);
            (assert(self._treasury.read().is_zero(), 'ALREADY_EXISTS'));
            
            let current_contract = get_contract_address();
            let factory = self._factory.read();
            let factory_dispatcher = IFactoryDispatcher {contract_address: factory};
            let treasury_contract_class_hash = factory_dispatcher.get_treasury_contract_class_hash();

            let mut constructor_calldata = Default::default();
            Serde::serialize(@current_contract, ref constructor_calldata);

            let syscall_result = deploy_syscall(
                treasury_contract_class_hash, 0, constructor_calldata.span(), false
            );
            let (treasury, _) = syscall_result.unwrap_syscall();
            self._treasury.write(treasury);

            // Giving root priviledges to owner of treasury 
            self.permission_manager_storage.grant(treasury, owner, ROOT_PERMISSION_ID);
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
            InternalImpl::_auth(ref self, MIGRATION_AUTHORISER_ID);
            let migration_hash: felt252 = LegacyHash::hash(old_address.into(), new_address);
            let is_queued = self._queued_migrations.read(migration_hash);

            assert(is_queued == true, 'NOT_QUEUED');

            InternalImpl::_migrate_points(ref self, old_address, new_address);
            self._queued_migrations.write(migration_hash, false);

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

        fn _auth(ref self: ContractState, permission_id: felt252) {
            let caller = get_caller_address();
            let current_contract = get_contract_address();
            
            assert(self.permission_manager_storage.is_granted(caller, current_contract, permission_id), 'UNAUTHORISED');
        }

    } 

}

