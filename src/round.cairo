// @title Round contract
// @author __________________
// @license MIT
// @notice Round contract to raise funds
// use std::time::{SystemTime, UNIX_EPOCH};
use starknet::ContractAddress;

#[derive(Drop, Serde, starknet::Store)]
struct Curve { // Curve eq = a * sqrt(x) + b
    a: u32,
    b: u32
}

//
// External Interfaces
//
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
trait IShare<T> {
    fn balance_of(self: @T, account: ContractAddress) -> u256;
    fn transfer(ref self: T, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(ref self: T, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn safe_mint(ref self: T, recipient: ContractAddress, amount: u256) -> bool;

}


#[starknet::interface]
trait IRound<TContractState> {

    // initiate the funding for the organization, the funding with upgrade to next round if called again
    fn initialize_round(ref self: TContractState, end_timestamp: u256, round_amount: u256, token: ContractAddress, total_shares: u256, final_price: u256,  initial_discount: u256);

    // the owner can withdraw the money with lockupd enabled.
    // fn withdraw(self: @TContractState, amount : u256) -> u256;

    // invent in the organization
    fn invest(ref self: TContractState, number_of_shares: u256) -> u256;
}

#[starknet::contract]
mod Round {
    use core::traits::TryInto;
use core::traits::Into;
use integer::u256_sqrt;
    use starknet::{ContractAddress, ClassHash, SyscallResult, SyscallResultTrait, get_caller_address, get_contract_address, get_block_timestamp, contract_address_const};
    use super::{
        IERC20Dispatcher, IERC20DispatcherTrait, IShareDispatcher, IShareDispatcherTrait
    };
    use coordination_stack_core::libraries::price_curve::PriceCurve::get_price;
    use coordination_stack_core::access::ownable::{Ownable, IOwnable};
    use coordination_stack_core::access::ownable::Ownable::{
        ModifierTrait as OwnableModifierTrait, InternalTrait as OwnableInternalTrait,
    };

    use super::Curve;

    #[derive(Drop, Serde, starknet::Store)]    
    enum RoundState {
        NOT_INITIALISED,
        ACTIVE,
        FINISHED,
        CANCELLED,
    }

    #[storage]
    struct Storage {        
        _shares_contract: ContractAddress, // erc20 token contract for organisation shares
        _round_amount : u256, // the amount of funding company need to invest for that round
        _token : ContractAddress, // address of ERC20 token to receive in fundind.
        _end_timestamp : u256, // end timestamp of the funding round in seconds 
        _amount_raised : u256, // the amount raised in the round so far
        _total_shares : u256, // total number of shares to be dilute
        _shares_diluted : u256, // number of shares left to be invested
        // current_valuation : u256, // current valuation of the company
        _owner : ContractAddress, // the address of the owner of the organization
        _initialised: bool, // @dev Flag to store initialisation state
        _is_rounnd_private: bool, // flag to store if round is private.
        _whitelist : LegacyMap::<ContractAddress, u256>, // mapping of the whitelisted investors and the amount they can invest
        _price_curve: Curve,

    }

    // /// @dev Event that gets emitted when a vote is cast
    //   #[event]
    //   #[derive(Drop, starknet::Event)]
    //   enum Event {
    //       FundingInitiated : FundingInitiated,
    //       Invested : Invested,
    //       Withdrawn : Withdrawn
    //   }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self._owner.write(owner);
        // self._shares_contract.write(shares_contract);
    }
 
    #[external(v0)]
    impl Round of super::IRound<ContractState> {
        
        // intialise the funding round
        fn initialize_round(ref self: ContractState, end_timestamp: u256, round_amount: u256, token: ContractAddress, total_shares: u256, final_price: u256, initial_discount: u256 ) {
            self._only_owner();
            let is_initialised = self._initialised.read();
            assert (is_initialised == false, 'ALREADY_INITIALISED');

            self._round_amount.write(round_amount);
            self._token.write(token);
            self._end_timestamp.write(end_timestamp);
            self._total_shares.write(total_shares);
            let b = final_price * initial_discount / 100;
            let a = final_price - b / u256_sqrt(total_shares).into();
            let price_curve = Curve{a:a.try_into().unwrap(), b:b.try_into().unwrap()};
            self._price_curve.write(price_curve);
        }


        fn invest(ref self: ContractState, number_of_shares : u256) -> u256 {
            let caller = get_caller_address();
            let contract_address = get_contract_address();
            let state = InternalImpl::_get_round_state(@self);
            if (state != 1) {
                return u256{ low:0, high :0};
                // panic("Round is not Active");
            }
            let total_shares = self._total_shares.read();
            let shares_diluted = self._shares_diluted.read();

            let mut shares = number_of_shares;
            if( shares_diluted + number_of_shares > total_shares) {
                shares = total_shares - shares_diluted;
            }

            let price_curve = self._price_curve.read();

            let avg_buying_price = get_price(price_curve.a, price_curve.b, shares_diluted, shares);

            let amount_to_transfer = (avg_buying_price * shares) / 10000; // Price has a PRECISION 10000

            // transfer token to contract
            let token = self._token.read();
            let tokenDispatcher = IERC20Dispatcher { contract_address: token };
            tokenDispatcher.transfer_from(caller, contract_address, amount_to_transfer);

            let amount_raised = self._amount_raised.read();
            self._amount_raised.write(amount_raised + amount_to_transfer);

            self._shares_diluted.write(shares_diluted + shares);

            // mint shares to investors
            let share_contract = self._shares_contract.read();
            let shareDispatcher = IShareDispatcher { contract_address: share_contract };
            shareDispatcher.safe_mint(caller, shares);

            amount_to_transfer
            
        }

    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {

        // fn _get_round_state(self: @ContractState) -> RoundState {
        //     let block_timestamp = get_block_timestamp();
        //     let end_timestamp = self._end_timestamp.read();
        //     let round_amount = self._round_amount.read();
        //     let amount_raised = self._amount_raised.read();
        //     if (self._initialised.read() == false) {
        //         RoundState.NOT_INITIALISED
        //     } else if (block_timestamp < end_timestamp.try_into().unwrap()) {
        //         RoundState.ACTIVE
        //     }else if(amount_raised < (round_amount * 80) / 100) {
        //         RoundState.CANCELLED
        //     }else {
        //         RoundState.FINISHED
        //     }
        // }
        fn _get_round_state(self: @ContractState) -> u32 {
            let block_timestamp = get_block_timestamp();
            let end_timestamp = self._end_timestamp.read();
            let round_amount = self._round_amount.read();
            let amount_raised = self._amount_raised.read();
            if (self._initialised.read() == false) {
                0 //NOT_INITIALISED
            } else if (block_timestamp < end_timestamp.try_into().unwrap()) {
                1 // ACTIVE
            }else if(amount_raised < (round_amount * 80) / 100) {
                2 // CANCELLED
            }else {
                3 // FINISHED
            }
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