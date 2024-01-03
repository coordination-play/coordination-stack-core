// @title Shares
// @author ____________
// @license MIT
// @notice ERC20 contract for organisation shares

use starknet::ContractAddress;
use array::Array;


//
// Contract Interface
//
#[starknet::interface]
trait IUSDC<TContractState> {
    // view functions
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn total_supply(self: @TContractState) -> u256;
    fn decimals(self: @TContractState) -> u8;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    
    // external functions
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn increase_allowance(ref self: TContractState, spender: ContractAddress, added_value: u256) -> bool;
    fn decrease_allowance(ref self: TContractState, spender: ContractAddress, subtracted_value: u256) -> bool;
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
    fn burn(ref self: TContractState, amount: u256);
}

#[starknet::contract]
mod USDC {
    use coordination_stack_core::utils::erc20::ERC20;
    use starknet::{ContractAddress, ClassHash, SyscallResult, SyscallResultTrait, get_caller_address, get_contract_address, get_block_timestamp, contract_address_const};
    use coordination_stack_core::access::ownable::{Ownable, IOwnable};
    use coordination_stack_core::access::ownable::Ownable::{
        ModifierTrait as OwnableModifierTrait, InternalTrait as OwnableInternalTrait,
    };
    use debug::PrintTrait;

    //
    // Storage Shares
    //
    #[storage]
    struct Storage {
       
    }

    //
    // Constructor
    //

    // @notice Contract constructor
    #[constructor]
    fn constructor(ref self: ContractState, owner_: ContractAddress,) {
        let mut erc20_state = ERC20::unsafe_new_contract_state();
        ERC20::InternalImpl::initializer(ref erc20_state, 'USDC', 'USDC');

        let mut ownable_self = Ownable::unsafe_new_contract_state();
        ownable_self._transfer_ownership(new_owner: owner_);

    }

    #[external(v0)]
    impl USDC of super::IUSDC<ContractState> {

        //
        // Getters ERC20
        //

        // @notice Name of the token
        // @return name
        fn name(self: @ContractState) -> felt252 {
            let erc20_state = ERC20::unsafe_new_contract_state();
            ERC20::ERC20::name(@erc20_state)
        }

        // @notice Symbol of the token
        // @return symbol
        fn symbol(self: @ContractState) -> felt252 {
            let erc20_state = ERC20::unsafe_new_contract_state();
            ERC20::ERC20::symbol(@erc20_state)
        }

        // @notice Total Supply of the token
        // @return total supply
        fn total_supply(self: @ContractState) -> u256 {
            let erc20_state = ERC20::unsafe_new_contract_state();
            ERC20::ERC20::total_supply(@erc20_state)
        }

        // @notice Decimals of the token
        // @return decimals
        fn decimals(self: @ContractState) -> u8 {
            let erc20_state = ERC20::unsafe_new_contract_state();
            ERC20::ERC20::decimals(@erc20_state)
        }

        // @notice Balance of `account`
        // @param account Account address whose balance is fetched
        // @return balance Balance of `account`
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            let erc20_state = ERC20::unsafe_new_contract_state();
            // ERC20::ERC20::balance_of(@erc20_state, account).print();
            ERC20::ERC20::balance_of(@erc20_state, account)
        }

        // @notice Allowance which `spender` can spend on behalf of `owner`
        // @param owner Account address whose tokens are spent
        // @param spender Account address which can spend the tokens
        // @return remaining
        fn allowance(self: @ContractState, owner: ContractAddress, spender: ContractAddress) -> u256 {
            let erc20_state = ERC20::unsafe_new_contract_state();
            ERC20::ERC20::allowance(@erc20_state, owner, spender)
        }


        //
        // Externals ERC20
        //

        // @notice Transfer `amount` tokens from `caller` to `recipient`
        // @param recipient Account address to which tokens are transferred
        // @param amount Amount of tokens to transfer
        // @return success 0 or 1
        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {          
            let mut erc20_state = ERC20::unsafe_new_contract_state();
            ERC20::ERC20::transfer(ref erc20_state, recipient, amount);
            true
        }

        // @notice Transfer `amount` tokens from `sender` to `recipient`
        // @dev Checks for allowance.
        // @param sender Account address from which tokens are transferred
        // @param recipient Account address to which tokens are transferred
        // @param amount Amount of tokens to transfer
        // @return success 0 or 1
        fn transfer_from(ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool {
            let mut erc20_state = ERC20::unsafe_new_contract_state();
            ERC20::ERC20::transfer_from(ref erc20_state, sender, recipient, amount);
            true
        }

        // @notice Approve `spender` to transfer `amount` tokens on behalf of `caller`
        // @param spender The address which will spend the funds
        // @param amount The amount of tokens to be spent
        // @return success 0 or 1
        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            let mut erc20_state = ERC20::unsafe_new_contract_state();
            ERC20::ERC20::approve(ref erc20_state, spender, amount);
            true
        }

        // @notice Increase allowance of `spender` to transfer `added_value` more tokens on behalf of `caller`
        // @param spender The address which will spend the funds
        // @param added_value The increased amount of tokens to be spent
        // @return success 0 or 1
        fn increase_allowance(ref self: ContractState, spender: ContractAddress, added_value: u256) -> bool {
            let mut erc20_state = ERC20::unsafe_new_contract_state();
            ERC20::ERC20::increase_allowance(ref erc20_state, spender, added_value);
            true
        }

        // @notice Decrease allowance of `spender` to transfer `subtracted_value` less tokens on behalf of `caller`
        // @param spender The address which will spend the funds
        // @param subtracted_value The decreased amount of tokens to be spent
        // @return success 0 or 1
        fn decrease_allowance(ref self: ContractState, spender: ContractAddress, subtracted_value: u256) -> bool {
            let mut erc20_state = ERC20::unsafe_new_contract_state();
            ERC20::ERC20::decrease_allowance(ref erc20_state, spender, subtracted_value);
            true
        }

        //
        // Externals USDC
        //


        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {         
            let mut erc20_state = ERC20::unsafe_new_contract_state();
            ERC20::InternalImpl::_mint(ref erc20_state, to, amount);

        }

        fn burn(ref self: ContractState, amount: u256) {
            let caller = get_caller_address();
            let mut erc20_state = ERC20::unsafe_new_contract_state();
            ERC20::InternalImpl::_burn(ref erc20_state, caller, amount);

        }

    }
    #[generate_trait]
    impl ModifierImpl of ModifierTrait {
        fn _only_owner(self: @ContractState) {
            let mut ownable_self = Ownable::unsafe_new_contract_state();

            ownable_self.assert_only_owner();
        }
    }

     #[external(v0)]
    impl IOwnableImpl of IOwnable<ContractState> {
        fn owner(self: @ContractState) -> ContractAddress {
            let ownable_self = Ownable::unsafe_new_contract_state();

            ownable_self.owner()
        }

        fn transfer_ownership(ref self: ContractState, new_owner: ContractAddress) {
            let mut ownable_self = Ownable::unsafe_new_contract_state();

            ownable_self.transfer_ownership(:new_owner);
        }

        fn renounce_ownership(ref self: ContractState) {
            let mut ownable_self = Ownable::unsafe_new_contract_state();

            ownable_self.renounce_ownership();
        }
    }


}
