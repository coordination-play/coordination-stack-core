// @title Coordination-stack Treasury in Cairo 2.4.1
// @author yash (tg-yashm001)
// @license MIT
// @notice Treasury to manage organisation funds.

use starknet::ContractAddress;
use starknet::ClassHash;

#[starknet::interface]
trait ISalaryDistributor<TContractState> {
    fn add_fund_to_salary_pools(ref self: TContractState, month_id: u32, amounts: Array<u256>, guilds: Array<ContractAddress>);
}

#[starknet::interface]
trait IOrganisation<TContractState> {
    fn get_salary_contract(self: @TContractState) -> ContractAddress;
}

//
// Contract Interface
//
#[starknet::interface]
trait ITreasury<TContractState> {
    // view functions

    // external functions
    fn allocate_funds_for_salary(ref self: TContractState, month_id: u32, amounts: Array<u256>, guilds: Array<ContractAddress>);
    fn execute_transaction(ref self: TContractState, target: ContractAddress, entry_point_selector: felt252, calldata: Span<felt252>);
}

#[starknet::contract]
mod Treasury {
    use traits::Into; // TODO remove intos when u256 inferred type is available
    use option::OptionTrait;
    use array::ArrayTrait;

    use starknet::{ContractAddress, ClassHash, SyscallResult, SyscallResultTrait, get_caller_address, get_contract_address, get_block_timestamp, contract_address_const};
    use starknet::syscalls::{replace_class_syscall, call_contract_syscall};

    use super::{
       IOrganisationDispatcher, IOrganisationDispatcherTrait, ISalaryDistributorDispatcher, ISalaryDistributorDispatcherTrait
    };
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
       _organisation: ContractAddress, // @dev organiation contact address
        #[substorage(v0)]
        ownable_storage: OwnableComponent::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event
    }

    //
    // Constructor
    //

    // @notice Contract constructor
    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, token:ContractAddress, organisation: ContractAddress) {
        self._organisation.write(organisation);
        self.ownable_storage.initializer(owner)

    }

     #[external(v0)]
    impl Treasury of super::ITreasury<ContractState> {

        //
        // Setters
        //

        fn allocate_funds_for_salary(ref self: ContractState, month_id: u32, amounts: Array<u256>, guilds: Array<ContractAddress>) {
            self.ownable_storage.assert_only_owner();
            let organisation = self._organisation.read();
            let organisation_dispatcher = IOrganisationDispatcher {contract_address: organisation};
            let salary_distributor = organisation_dispatcher.get_salary_contract();
            let salary_distributor_dispatcher = ISalaryDistributorDispatcher {contract_address: salary_distributor};
            salary_distributor_dispatcher.add_fund_to_salary_pools(month_id, amounts, guilds);
        }

        fn execute_transaction(ref self: ContractState, target: ContractAddress, entry_point_selector: felt252, calldata: Span<felt252>) {
            self.ownable_storage.assert_only_owner();
            let mut result = call_contract_syscall(target, entry_point_selector, calldata);
            result.unwrap_syscall(); 
        }


    }
}
