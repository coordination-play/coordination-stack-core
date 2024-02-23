// @title Coordination-stack Treasury in Cairo 2.4.1
// @author Yash (tg-yashm001)
// @license MIT
// @notice Treasury to manage organisation funds.

use starknet::ContractAddress;
use starknet::ClassHash;

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
trait ISalaryDistributor<TContractState> {
    fn token(self: @TContractState) -> ContractAddress;
    fn add_fund_to_salary_pools(ref self: TContractState, month_id: u32, amounts: Array<u256>, guilds: Array<ContractAddress>);
}

#[starknet::interface]
trait IOrganisation<TContractState> {
    fn get_salary_distributor_contract(self: @TContractState) -> ContractAddress;
    fn is_granted(self: @TContractState, where: ContractAddress, who: ContractAddress, permission_id: felt252) -> bool;
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
    use starknet::{ContractAddress, ClassHash, SyscallResult, SyscallResultTrait, get_caller_address, get_contract_address, get_block_timestamp, contract_address_const};
    use starknet::syscalls::{replace_class_syscall, call_contract_syscall};

    use super::{
       IERC20Dispatcher, IERC20DispatcherTrait, IOrganisationDispatcher, IOrganisationDispatcherTrait, ISalaryDistributorDispatcher, ISalaryDistributorDispatcherTrait
    };

    const ROOT_PERMISSION_ID: felt252 = 'ROOT_PERMISSION';
    const SALARY_FUNDS_ALLOCATOR_ID: felt252 = 'SALARY_FUNDS_ALLOCATOR';

    //
    // Storage Organisation
    //
    #[storage]
    struct Storage {
       _organisation: ContractAddress, // @dev organiation contact address

    }

    // #[event]
    // #[derive(Drop, starknet::Event)]
    // enum Event {

    // }

    //
    // Constructor
    //

    // @notice Contract constructor
    #[constructor]
    fn constructor(ref self: ContractState, organisation: ContractAddress) {
        self._organisation.write(organisation);

    }

     #[external(v0)]
    impl Treasury of super::ITreasury<ContractState> {

        //
        // Setters
        //

        fn allocate_funds_for_salary(ref self: ContractState, month_id: u32, amounts: Array<u256>, guilds: Array<ContractAddress>) {
            InternalImpl::_auth(ref self, SALARY_FUNDS_ALLOCATOR_ID);
            let mut amount_to_transfer = 0;
            let mut current_index = 0;
            assert(guilds.len() == amounts.len(), 'INVALID_INPUT');
            let guilds_copy = guilds.clone();
            let amounts_copy = amounts.clone();
            loop {
                if (current_index == guilds_copy.len()) {
                    break;
                }
                amount_to_transfer += *amounts_copy[current_index];
                current_index += 1;
            };
            let organisation = self._organisation.read();
            let organisation_dispatcher = IOrganisationDispatcher {contract_address: organisation};
            let salary_distributor = organisation_dispatcher.get_salary_distributor_contract();
            let salary_distributor_dispatcher = ISalaryDistributorDispatcher {contract_address: salary_distributor};
            

            let token = salary_distributor_dispatcher.token();
            let tokenDispatcher = IERC20Dispatcher { contract_address: token };
            tokenDispatcher.transfer(salary_distributor, amount_to_transfer);

            salary_distributor_dispatcher.add_fund_to_salary_pools(month_id, amounts, guilds);
        }

        fn execute_transaction(ref self: ContractState, target: ContractAddress, entry_point_selector: felt252, calldata: Span<felt252>) {
            InternalImpl::_auth(ref self, ROOT_PERMISSION_ID);
            let mut result = call_contract_syscall(target, entry_point_selector, calldata);
            result.unwrap_syscall(); 
        }


    }
     #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _auth(ref self: ContractState, permission_id: felt252) {
            let caller = get_caller_address();
            let current_contract = get_contract_address();

            let organisation_dispatcher = IOrganisationDispatcher {contract_address: self._organisation.read()};
            assert(organisation_dispatcher.is_granted(current_contract, caller, permission_id), 'UNAUTHORISED');
        }
    }
}
