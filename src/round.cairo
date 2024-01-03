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
    fn issue_new_shares(ref self: T, recipient: ContractAddress, amount: u256, lock_duration: u64);

}


#[starknet::interface]
trait IRound<TContractState> {

    fn amount_raised(self: @TContractState) -> u256;
    fn shares_committed(self: @TContractState) -> u256;
    fn get_round_state(self: @TContractState) -> u32;
    fn get_avg_price(self: @TContractState, total_shares_committed: u256, shares:u256 ) -> u256;
    fn is_round_whitelisted(self: @TContractState) -> bool;
    // initiate the funding for the organization, the funding with upgrade to next round if called again
    fn initialize_round(ref self: TContractState, end_timestamp: u256, round_amount: u256, token: ContractAddress, shares_contract:ContractAddress, total_shares: u256, final_price: u256, initial_discount: u256, threshold: u256, is_whitelisted: bool, whitelist_addresses: Array::<ContractAddress>, whitelist_amounts: Array::<u256>, lock_duration: u64, treasury: ContractAddress);

    // invent in the organization
    fn invest(ref self: TContractState, number_of_shares: u256) -> u256;
    fn finalise_round(ref self: TContractState);
    fn discard_round(ref self: TContractState);


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
    use coordination_stack_core::array_storage::StoreContractAddressArray;
    use coordination_stack_core::libraries::price_curve::PriceCurve::get_price;
    use coordination_stack_core::access::ownable::{Ownable, IOwnable};
    use coordination_stack_core::access::ownable::Ownable::{
        ModifierTrait as OwnableModifierTrait, InternalTrait as OwnableInternalTrait,
    };

    use super::Curve;

    const PRECISION: u256 = 1000;


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
        _investors : Array<ContractAddress>, // list of all the investors address
        _token : ContractAddress, // address of ERC20 token to receive in funding.
        _end_timestamp : u256, // end timestamp of the funding round in seconds 
        _amount_raised : u256, // the total amount raised in the round so far
        _amount_invested : LegacyMap::<ContractAddress, u256>, // the amount of funds by each investor.
        _total_shares : u256, // maximum number of shares to be minted
        _shares_committed : LegacyMap::<ContractAddress, u256>, // number of shares committed by each investors
        _total_shares_committed : u256, // total number of shares committed
        _threshold: u256, // minimum %(percent) to raise for the round to be completed.
        _initialised: bool, // @dev Flag to store initialisation state
        _is_round_whitelisted: bool, // flag to store if round is whitelisted.
        _whitelist : LegacyMap::<ContractAddress, u256>, // mapping of the whitelisted investors and the amount they can invest
        _price_curve: Curve,
        _is_finalised: bool, // flag to store finanlised state.
        _is_discarded: bool, // flag to store discarded state.
        _treasury: ContractAddress, // address to transfer funds to 
        _lock_duration: u64, // time in seconds for which new shares allocated are locked

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
        let mut ownable_self = Ownable::unsafe_new_contract_state();
        ownable_self._transfer_ownership(new_owner: owner);
        
    }
 
    #[external(v0)]
    impl Round of super::IRound<ContractState> {

        fn amount_raised(self: @ContractState) -> u256 {
            self._amount_raised.read()
        }

        fn shares_committed(self: @ContractState) -> u256 {
            self._total_shares_committed.read()
        }

        fn get_round_state(self: @ContractState) -> u32 {
            InternalImpl::_get_round_state(self)
        }

        fn get_avg_price(self: @ContractState, total_shares_committed: u256, shares:u256 ) -> u256 {
            let price_curve = self._price_curve.read();

            get_price(price_curve.a, price_curve.b, total_shares_committed, shares)

        }

        fn is_round_whitelisted(self: @ContractState) -> bool {
            self._is_round_whitelisted.read()
        }
        
        // intialise the funding round
        fn initialize_round(ref self: ContractState, end_timestamp: u256, round_amount: u256, token: ContractAddress, shares_contract:ContractAddress, total_shares: u256, final_price: u256, initial_discount: u256, threshold: u256, is_whitelisted: bool, whitelist_addresses: Array::<ContractAddress>, whitelist_amounts: Array::<u256>, lock_duration: u64, treasury: ContractAddress ) {
            self._only_owner();
            let is_initialised = self._initialised.read();
            assert (is_initialised == false, 'ALREADY_INITIALISED');

            assert(whitelist_addresses.len() == whitelist_amounts.len(), 'LENGTH_MISMATCH');

            self._round_amount.write(round_amount);
            self._token.write(token);
            self._shares_contract.write(shares_contract);
            self._end_timestamp.write(end_timestamp);
            self._total_shares.write(total_shares);
            self._threshold.write(threshold);
            self._lock_duration.write(lock_duration);
            self._treasury.write(treasury);
            self._is_round_whitelisted.write(is_whitelisted);
            // TODO: if whitelisted, loop through whitelist array and update amount.
            if (is_whitelisted) {
                let mut current_index = 0;
                loop {
                    if (current_index == whitelist_addresses.len()) {
                    break;
                    }
                    self._whitelist.write(*whitelist_addresses[current_index], *whitelist_amounts[current_index]);
                    current_index += 1;
                };
            }
            let b = (final_price * initial_discount * PRECISION) / 100;
            let a = ((final_price * PRECISION) - b) / u256_sqrt(total_shares).into();
            let price_curve = Curve{a:a.try_into().unwrap(), b:b.try_into().unwrap()};
            self._price_curve.write(price_curve);

            self._initialised.write(true);
        }


        fn invest(ref self: ContractState, number_of_shares : u256) -> u256 {
            let state = InternalImpl::_get_round_state(@self);
            assert (state == 1, 'ROUND_NOT_ACTIVE');

            let caller = get_caller_address();

            let is_round_whitelisted = self._is_round_whitelisted.read();
            if (is_round_whitelisted) {
                let whitelisted_amount = self._whitelist.read(caller);
                assert(number_of_shares <= whitelisted_amount, 'ABOVE_PERMISSIBLE_AMOUNT');
            }
            let contract_address = get_contract_address();

            let total_shares = self._total_shares.read();
            let total_shares_committed = self._total_shares_committed.read();

            let mut shares = number_of_shares;
            if( total_shares_committed + number_of_shares > total_shares) {
                shares = total_shares - total_shares_committed;
            }

            let price_curve = self._price_curve.read();

            let avg_buying_price = get_price(price_curve.a, price_curve.b, total_shares_committed, shares);

            let amount_to_transfer = (avg_buying_price * shares * 1000000000000000000)  / 10000000; // Price has a PRECISION 10000000

            // transfer token to contract
            let token = self._token.read();
            let tokenDispatcher = IERC20Dispatcher { contract_address: token };
            tokenDispatcher.transfer_from(caller, contract_address, amount_to_transfer);

            let amount_invested = self._amount_invested.read(caller);
            self._amount_invested.write(caller, amount_invested + amount_to_transfer);
            let amount_raised = self._amount_raised.read();
            self._amount_raised.write(amount_raised + amount_to_transfer);

            // adding new investor to the investment array
            if(amount_invested == 0) { 
                let mut investors = self._investors.read();
                investors.append(caller);
                self._investors.write(investors);
            }

            // storing shares committment
            let shares_committed = self._shares_committed.read(caller);
            self._shares_committed.write(caller, shares_committed + shares);
            self._total_shares_committed.write(total_shares_committed + shares);

            // mint shares to investors
            // let share_contract = self._shares_contract.read();
            // let shareDispatcher = IShareDispatcher { contract_address: share_contract };
            // shareDispatcher.safe_mint(caller, shares);

            amount_to_transfer
            
        }

        fn finalise_round(ref self: ContractState){
            let state = InternalImpl::_get_round_state(@self);
            assert (state == 2 || state == 3, 'INVALID_STATE');
            let is_finalised = self._is_finalised.read();
            assert (is_finalised == false, 'ALREADY_FINANLISED');
            let investors = self._investors.read();
            let token = self._token.read();
            let tokenDispatcher = IERC20Dispatcher { contract_address: token };
            let mut current_index = 0;
            if (state == 2) { // revert the funds back to the investors
                loop {
                    if (current_index == investors.len()) {
                    break;
                    }
                    let amount_invested = self._amount_invested.read(*investors[current_index]);
                    let token = self._token.read();
                    let tokenDispatcher = IERC20Dispatcher { contract_address: token };
                    tokenDispatcher.transfer(*investors[current_index], amount_invested);
                    current_index += 1;
                };

            } else { // mint the shares 
                loop {
                    if (current_index == investors.len()) {
                    break;
                    }
                    let shares_committed = self._shares_committed.read(*investors[current_index]);
                    let share_contract = self._shares_contract.read();
                    let lock_duration = self._lock_duration.read();
                    let shareDispatcher = IShareDispatcher { contract_address: share_contract };
                    shareDispatcher.issue_new_shares(*investors[current_index], shares_committed * 1000000000000000000, lock_duration);
                    current_index += 1;
                };

                // tranfering the amount raised to _____name TBD_____ contract
                let amount_raised = self._amount_raised.read();
                let treasury = self._treasury.read();
                tokenDispatcher.transfer(treasury, amount_raised);
            }
            self._is_finalised.write(true);

        }

        fn discard_round(ref self: ContractState) {
            self._only_owner();
            let amount_raised = self._amount_raised.read();

            assert(amount_raised == 0, 'INVESTMENT_ALREADY_STARTED');
            self._is_discarded.write(true);


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
            let threshold = self._threshold.read();
            let is_discarded = self._is_discarded.read();
            let is_finalised = self._is_finalised.read();
            if (self._initialised.read() == false) {
                0 //NOT_INITIALISED
            } else if (block_timestamp < end_timestamp.try_into().unwrap()) {
                1 // ACTIVE
            }else if(is_discarded) {
                4 // Discarded
            }
            else if(amount_raised < (round_amount * threshold) / 100) {
                2 // CANCELLED
            }else {
                3 // Passed
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