// @title Factory in cairo 2.4.1
// @author Yash (tg-@yashm001)
// @license MIT
// @notice Factory to deploy new Organisation and Guilds and maintain a registry of all organisations

use starknet::ContractAddress;
use array::Array;
use starknet::ClassHash;
use coordination_stack_core::utils::span_storage::StoreSpanFelt252;

#[derive(Copy, Drop, Serde, starknet::Store)]
struct Organisation {
    // @notice name of the organisation
    name: felt252,
    // @notice organisation metadata
    metadata: Span<felt252>,
    // @notice organisation contract address
    organisation: ContractAddress
}


#[starknet::interface]
trait IERC20<T> {
    fn balance_of(self: @T, account: ContractAddress) -> u256;
    fn balanceOf(self: @T, account: ContractAddress) -> u256; // TODO Remove after regenesis
    fn transfer(ref self: T, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(ref self: T, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn transferFrom(ref self: T, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool; // TODO Remove after regenesis
}

#[starknet::interface]
trait IOrganisation<TContractState> {
    fn owner(self: @TContractState) -> ContractAddress;
    fn name(self: @TContractState) -> felt252;
    fn metadata(self: @TContractState) -> Span<felt252>;
}

#[starknet::interface]
trait IFactory<TContractState> {
    // view functions
    fn get_creation_fee(self: @TContractState) -> u256;
    fn get_all_organisations(self: @TContractState) -> (u32, Array::<ContractAddress>);
    fn get_all_organisations_details(self: @TContractState) -> (u32, Array::<Organisation>);
    fn get_num_of_organisations(self: @TContractState) -> u32;
    fn get_organisation_contract_class_hash(self: @TContractState) -> ClassHash;
    fn get_guild_contract_class_hash(self: @TContractState) -> ClassHash;
    fn get_salary_contract_class_hash(self: @TContractState) -> ClassHash;
    fn get_treasury_contract_class_hash(self: @TContractState) -> ClassHash;
    // external functions
    fn update_creation_fee(ref self: TContractState, new_fee: u256);
    fn create_organisation(ref self: TContractState, name: felt252, metadata: Span<felt252> ) -> ContractAddress;
    fn withdraw_fee(ref self: TContractState, receipent: ContractAddress);
    fn replace_organisation_contract_hash(ref self: TContractState, new_organisation_contract_class: ClassHash);
    fn replace_guild_contract_hash(ref self: TContractState, new_guild_contract_class: ClassHash);
    fn replace_implementation_class(ref self: TContractState, new_implementation_class: ClassHash);
    fn replace_salary_contract_hash(ref self: TContractState, new_salary_contract_class: ClassHash);
    fn replace_treasury_contract_hash(ref self: TContractState, new_treasury_contract_class: ClassHash);

}

#[starknet::contract]
mod Factory {
    use traits::Into; // TODO remove intos when u256 inferred type is available
    use option::OptionTrait;
    use array::{ArrayTrait, SpanTrait};
    use result::ResultTrait;
    use zeroable::Zeroable;
    use hash::LegacyHash;
    use poseidon::poseidon_hash_span;
    use starknet::{ContractAddress, ClassHash, SyscallResult, SyscallResultTrait, get_caller_address, get_contract_address, get_block_timestamp, contract_address_const};
    use integer::{u128_try_from_felt252, u256_sqrt, u256_from_felt252};
    use starknet::syscalls::{replace_class_syscall, deploy_syscall};
    use super::{Organisation, IERC20Dispatcher, IERC20DispatcherTrait, IOrganisationDispatcher, IOrganisationDispatcherTrait};
    use coordination_stack_core::utils::span_storage::StoreSpanFelt252;
    use openzeppelin::access::ownable::OwnableComponent;
    component!(path: OwnableComponent, storage: ownable_storage, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;


    //
    // Storage Factory
    //
    #[storage]
    struct Storage {
        _creation_fee: u256, // @dev a samll fee to pay for creating org to avoid spamming. 
        _fee_token: ContractAddress, // @dev, token contract contract to pay fee in.
        _all_organisations: LegacyMap::<u32, ContractAddress>, // @dev registry of all organisations
        _num_of_organisations: u32,
        _organisation_contract_class_hash: ClassHash,
        _guild_contract_class_hash: ClassHash,
        _salary_contract_class_hash: ClassHash,
        _treasury_contract_class_hash: ClassHash,
        #[substorage(v0)]
        ownable_storage: OwnableComponent::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OrganisationCreated: OrganisationCreated,
        CreationFeeUpdated: CreationFeeUpdated,
        #[flat]
        OwnableEvent: OwnableComponent::Event
    }

    // @dev Emitted each time an organisation is created via create_organisation
    #[derive(Drop, starknet::Event)]
    struct OrganisationCreated {
        name: felt252, 
        organisation: ContractAddress,
        id: u32
    }

    // @dev Emitted each time CreationFee is update via update_creation_fee
    #[derive(Drop, starknet::Event)]
    struct CreationFeeUpdated {
        new_fee: u256
    }


    //
    // Constructor
    //

    // @notice Contract constructor
    #[constructor]
    fn constructor(ref self: ContractState, organisation_contract_class_hash: ClassHash, guild_contract_class_hash: ClassHash, treasury_contract_class_hash: ClassHash, salary_contract_class_hash: ClassHash, owner: ContractAddress) {
        assert(!organisation_contract_class_hash.is_zero(), 'can not be zero');
        assert(!guild_contract_class_hash.is_zero(), 'can not be zero');
        assert(!treasury_contract_class_hash.is_zero(), 'can not be zero');
        assert(!salary_contract_class_hash.is_zero(), 'can not be zero');

        self._organisation_contract_class_hash.write(organisation_contract_class_hash);
        self._guild_contract_class_hash.write(guild_contract_class_hash);
        self._treasury_contract_class_hash.write(treasury_contract_class_hash);
        self._salary_contract_class_hash.write(salary_contract_class_hash);
        self._num_of_organisations.write(0);
        self._creation_fee.write(100000000000000000); // 0.1 ETH -> this fee will go for the development of coordination-stack
        self._fee_token.write(0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7.try_into().unwrap()); // 3 months

        self.ownable_storage.initializer(owner);
    }

    #[external(v0)]
    impl Factory of super::IFactory<ContractState> {
        //
        // Getters
        //

        fn get_creation_fee(self: @ContractState) -> u256 {
            self._creation_fee.read()
        }

        // @notice Get all the organisations registered
        // @return all_organisations_len Length of `all_organisations` array
        // @return all_organisations Array of contract addresses of the registered organisations
        fn get_all_organisations(self: @ContractState) -> (u32, Array::<ContractAddress>) { 
            let mut all_organisations_array = ArrayTrait::<ContractAddress>::new();
            let num_organisations = self._num_of_organisations.read();
            let mut current_index = 1; // organisation index starts from 1, instead of zero
            loop {
                if current_index == num_organisations + 1 {
                    break true;
                }
                all_organisations_array.append(self._all_organisations.read(current_index));
                current_index += 1;
            };
            (num_organisations, all_organisations_array)
        }

        // @notice Get all the organisations registered
        // @return all_organisations_len Length of `all_organisations` array
        // @return all_organisations Array of Organisations of the registered organisations
        // @Notice This function is required for frontend until indexer is live
        fn get_all_organisations_details(self: @ContractState) -> (u32, Array::<Organisation>) { 
            let mut all_organisations_array = ArrayTrait::<Organisation>::new();
            let num_organisations = self._num_of_organisations.read();
            let mut current_index = 1; // organisation index starts from 1, instead of zero
            loop {
                if current_index == num_organisations + 1 {
                    break true;
                }
                let organisation = self._all_organisations.read(current_index);
                let organisation_dispatcher = IOrganisationDispatcher {contract_address: organisation};
                let name = organisation_dispatcher.name();
                let metadata = organisation_dispatcher.metadata();
                let org = Organisation {name: name, metadata: metadata, organisation: organisation};
                all_organisations_array.append(org);
                current_index += 1;
            };
            (num_organisations, all_organisations_array)
        }

        // @notice Get the number of organisations
        // @return num_of_organisations
        fn get_num_of_organisations(self: @ContractState) -> u32 {
           self._num_of_organisations.read()
        }

        // @notice Get the class hash of the organisation contract which is deployed for each organisation.
        // @return class_hash
        fn get_organisation_contract_class_hash(self: @ContractState) -> ClassHash {
            self._organisation_contract_class_hash.read()
        }

        // @notice Get the class hash of the Guild contract which is deployed for each guild.
        // @return class_hash
        fn get_guild_contract_class_hash(self: @ContractState) -> ClassHash {
            self._guild_contract_class_hash.read()
        }

        // @notice Get the class hash of the Treasury contract which is deployed for each treasury.
        // @return class_hash
        fn get_treasury_contract_class_hash(self: @ContractState) -> ClassHash {
            self._treasury_contract_class_hash.read()
        }

        // @notice Get the class hash of the Salary contract which is deployed for each salary distributor.
        // @return class_hash
        fn get_salary_contract_class_hash(self: @ContractState) -> ClassHash {
            self._salary_contract_class_hash.read()
        }


        //
        // Setters
        //

        fn update_creation_fee(ref self: ContractState, new_fee: u256) {
            self.ownable_storage.assert_only_owner();
            self._creation_fee.write(new_fee);

            self.emit(CreationFeeUpdated {new_fee: new_fee});

        }
        fn create_organisation(ref self: ContractState, name: felt252, metadata: Span<felt252> ) -> ContractAddress {
            assert(!name.is_zero(), 'NAME_NOT_DEFINED');
            let caller = get_caller_address();
            let factory = get_contract_address();
            let block_timestamp = get_block_timestamp();

            let token = self._fee_token.read();
            let fee_amount = self._creation_fee.read();
            let token_dispatcher = IERC20Dispatcher {contract_address: token};
            token_dispatcher.transfer_from(caller, factory, fee_amount);
            
            let organisation_contract_class_hash = self._organisation_contract_class_hash.read();

            let mut constructor_calldata = Default::default();
            Serde::serialize(@name, ref constructor_calldata);
            Serde::serialize(@metadata, ref constructor_calldata);
            Serde::serialize(@caller, ref constructor_calldata);
            Serde::serialize(@factory, ref constructor_calldata);

            let syscall_result = deploy_syscall(
                organisation_contract_class_hash, 0, constructor_calldata.span(), false
            );
            let (organisation, _) = syscall_result.unwrap_syscall();

            let num_organisations = self._num_of_organisations.read();
            self._all_organisations.write(num_organisations + 1, organisation);
            self._num_of_organisations.write(num_organisations + 1);

            self.emit(OrganisationCreated {name: name, organisation: organisation, id: num_organisations + 1});

            organisation

        }

        fn withdraw_fee(ref self: ContractState, receipent: ContractAddress) {
            self.ownable_storage.assert_only_owner();
            let current_contract = get_contract_address();

            let token = self._fee_token.read();
            let token_dispatcher = IERC20Dispatcher {contract_address: token};
            // TODO: whether to call balanceOf or balance_of
            let balance = token_dispatcher.balanceOf(current_contract);
            token_dispatcher.transfer(receipent, balance);

        }

        

        // @notice This replaces _organisation_contract_class_hash used to deploy new organisations
        // @dev Only owner can call
        // @param new_organisation_contract_class New _organisation_contract_class_hash
        fn replace_organisation_contract_hash(ref self: ContractState, new_organisation_contract_class: ClassHash) {
            self.ownable_storage.assert_only_owner();
            assert(!new_organisation_contract_class.is_zero(), 'must be non zero');
            self._organisation_contract_class_hash.write(new_organisation_contract_class);
        }

        // @notice This replaces _guild_contract_class_hash used to deploy new guilds
        // @dev Only owner can call
        // @param new_guild_contract_class New _guild_contract_class_hash
        fn replace_guild_contract_hash(ref self: ContractState, new_guild_contract_class: ClassHash) {
            self.ownable_storage.assert_only_owner();
            assert(!new_guild_contract_class.is_zero(), 'must be non zero');
            self._guild_contract_class_hash.write(new_guild_contract_class);
        }

        // @notice This replaces _treasury_contract_class_hash used to deploy new treasurys
        // @dev Only owner can call
        // @param new_treasury_contract_class New _treasury_contract_class_hash
        fn replace_treasury_contract_hash(ref self: ContractState, new_treasury_contract_class: ClassHash) {
            self.ownable_storage.assert_only_owner();
            assert(!new_treasury_contract_class.is_zero(), 'must be non zero');
            self._treasury_contract_class_hash.write(new_treasury_contract_class);
        }

        // @notice This replaces _salary_contract_class_hash used to deploy new salarys
        // @dev Only owner can call
        // @param new_salary_contract_class New _salary_contract_class_hash
        fn replace_salary_contract_hash(ref self: ContractState, new_salary_contract_class: ClassHash) {
            self.ownable_storage.assert_only_owner();
            assert(!new_salary_contract_class.is_zero(), 'must be non zero');
            self._salary_contract_class_hash.write(new_salary_contract_class);
        }

        // @notice This is used upgrade (Will push a upgrade without this to finalize)
        // @dev Only owner can call
        // @param new_implementation_class New implementation hash
        fn replace_implementation_class(ref self: ContractState, new_implementation_class: ClassHash) {
            self.ownable_storage.assert_only_owner();
            assert(!new_implementation_class.is_zero(), 'must be non zero');
            replace_class_syscall(new_implementation_class);
        }

    }
    
}
