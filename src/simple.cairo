use starknet::ContractAddress;
use array::Array;


#[starknet::interface]
trait ISimple<TContractState> {
    fn get_value(self: @TContractState) -> u64;

    fn set_value(ref self: TContractState, new_value: u256);
}

#[starknet::contract]
mod Simple {

    use starknet::{ClassHash, SyscallResult, SyscallResultTrait, get_caller_address, get_contract_address, get_block_timestamp, contract_address_const};


    #[storage]
    struct Storage {
        _value : u256,
    }

     // @notice Contract constructor
    #[constructor]
    fn constructor(ref self: ContractState) {

    }

    #[external(v0)]
    impl Simple of super::ISimple<ContractState> {
        fn get_value(self: @ContractState) -> u64 {
            let block_timestamp = get_block_timestamp();
            block_timestamp
        }

        fn set_value(ref self: ContractState, new_value: u256) {
            self._value.write(new_value);
        }
        
    }


}