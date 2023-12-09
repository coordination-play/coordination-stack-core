// @title Round contract
// @author __________________
// @license MIT
// @notice Round contract to raise funds
// use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Drop, Serde, starknet::Store)]
struct Curve { // Curve eq = a * sqrt(x) + b
    a: u32,
    b: u32
}

#[starknet::interface]
trait IRound<TContractState> {

    // initiate the funding for the organization, the funding with upgrade to next round if called again
    fn initialize_round(ref self: TContractState, end_timestamp: u128, round_amount: u128, token: ContractAddress, total_shares: u128, final_price: u128,  initial_discount: u128);

    // the owner can withdraw the money with lockupd enabled.
    fn withdraw(self: @TContractState, amount : u128) -> u128;

    // invent in the organization
    fn invest(self: @TContractState, number_of_shares: u128) -> u128;
}

#[starknet::contract]
mod Round {
    use starknet::get_caller_address;
    use starknet::ContractAddress;
    use integer::u256_sqrt;
    use coordination_stack_core::libraries::price_curve::PriceCurve::get_price;

    use super::Curve;

    #[derive(Drop)]
    enum RoundState {
        NOT_INITIALISED,
        ACTIVE,
        FINISHED,
        CANCELLED,
    }

    #[storage]
    struct Storage {        
        _round_amount : u128, // the amount of funding company need to invest for that round
        _token : ContractAddress, // address of ERC20 token to receive in fundind.
        _end_timestamp : u128, // end timestamp of the funding round in seconds 
        _amount_raised : u128, // the amount raised in the round so far
        _total_shares : u128, // total number of shares to be dilute
        _shares_diluted : u128, // number of shares left to be invested
        // current_valuation : u128, // current valuation of the company
        _owner : ContractAddress, // the address of the owner of the organization
        _initialised: bool, // @dev Flag to store initialisation state
        _is_rounnd_private: bool, // flag to store if round is private.
        _whitelist : LegacyMap::<ContractAddress, u128>, // mapping of the whitelisted investors and the amount they can invest
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
        self.owner.write(owner);
    }
 
    #[external(v0)]
    impl Round of super::IRound<ContractState> {
        
        // invoke/start the funding round
        fn initialize_round(end_timestamp: u128, round_amount: u128, token: ContractAddress, total_shares: u128, final_price: u128, initial_discount: u128 ) {
            self._only_owner();
            let is_initialised = self._initialised.read();
            assert (is_initialised == false, 'ALREADY_INITIALISED');

            self._round_amount.write(round_amount);
            self._token.write(token);
            self._end_timestamp.write(end_timestamp);
            self._total_shares.write(total_shares);
            let b = final_price * initial_discount / 100;
            let a = final_price - b / u256_sqrt(total_shares);
            let price_curve = Curve{a:a, b:b};
            self._price_curve.write(price_curve);
        }


       fn invest(ref self : @ContractState, number_of_shares : u128) -> u256 {

        let state = InternalImpl::_get_round_state();
        if (state != RoundState.Active) {
            panic("Round is not Active");
        }
        let total_shares = self._total_shares.read();
        let shares_diluted = self._shares_diluted.read();

        let shares = number_of_shares;
        if( shares_diluted + number_of_shares > total_shares) {
            shares = total_shares - shares_diluted;
        }

        let price_curve = self._price_curve.read();

        let avg_buying_price = get_price(price_curve.a, price_curve.b, shares_diluted, shares);

        let amount_to_transfer = avg_buying_price * shares;

        // Todo transfer token to contract

        let amount_raised = self._amount_raised.read();
        self._amount_raised.write(amount_raised + amount_to_transfer);

        self._shares_diluted.write(shares_diluted + shares);

        // TODO: mint shares to investors


        }

    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {

        fn _get_round_state(ref self: ContractState) -> RoundState {
            let block_timestamp = get_block_timestamp();
            let end_timestamp = self._end_timestamp;
            let round_amount = self._round_amount;
            let amount_raised = self._amount_raised;
            if (self._initialised == false) {
                RoundState.NOT_INITIALISED
            } else if (block_timestamp < end_timestamp) {
                RoundState.ACTIVE
            }else if(amount_raised < (round_amount * 80) / 100) {
                RoundState.CANCELLED
            }else {
                RoundState.FINISHED
            }
        }

    }


}