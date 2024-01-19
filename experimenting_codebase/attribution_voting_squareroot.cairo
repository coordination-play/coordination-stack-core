// @title Cordination-stack Attribution voting model - squareroot Cairo 2.2
// @author Yash (tg: @yashm001)
// @license MIT
// @notice voting contract to assign Attribution points.
use starknet::ContractAddress;
use array::Array;
use coordination_stack_core::attribution::MonthlyContribution;

#[starknet::interface]
trait IAttribution<T> {
    fn update_contibutions(ref self: TContractState, month_id: u32, guild: felt252, contributions: Array::<MonthlyContribution>);

}

//
// Contract Interface
//
#[starknet::interface]
trait IAttributionVoting<TContractState> {
    // view functions
    fn get_total_voting_power(self: @TContractState, account: ContractAddress) -> u256;
    fn vote_casted(self: @TContractState, account: ContractAddress) -> u256; 
    fn epoch(self: @TContractState) -> u32; 

    // external functions
    fn initialise(ref self: TContractState, month_id: u32, guild: felt252, initial_vote: u32, max_epoch: u32, epoch_length: u256);
    fn add_participants(ref self: TContractState, accounts: Array::<ContractAddress>) -> bool;
    fn start_voting(ref self: TContractState) -> bool;
    fn vote(ref self: TContractState, accounts: Array::<ContractAddress>, votes: Array::<u256>, tags: Array::<felt252>, reasons:Array::<felt252>) -> bool;
    fn update_contribution(ref self: TContractState);

}

#[starknet::contract]
mod AttributionVoting {
    use traits::Into; // TODO remove intos when u256 inferred type is available
    use array::{ArrayTrait, SpanTrait};
    use integer::u32_sqrt;
    use coordination_stack_core::access::ownable::{Ownable, IOwnable};
    use coordination_stack_core::access::ownable::Ownable::{
        ModifierTrait as OwnableModifierTrait, InternalTrait as OwnableInternalTrait,
    };
    use super::{
        IAttributionDispatcher, IAttributionDispatcherTrait
    };

    //
    // Storage AttributionVoting
    //
    #[storage]
    struct Storage {
        // @notice cumulative is also a tag to store the total votes.
        _voted: LegacyMap::<(ContractAddress,felt252), u32>, // @dev to store the votes for each participants for each tag. 
        _vote_casted: LegacyMap::<ContractAddress, u32>, // @dev to store the votecasted for each voter. 
        _participants: Array<ContractAddress>, // @dev to store the list of all the participants. 
        _initial_vote: u32,
        _epoch: u32, // current epoch
        _vote_end_timestamp: u128, // unix timestamp for when current epoch started
        _initialised: bool, // @dev Flag to store initialisation state

    }

    //
    // Constructor
    //

    // @notice Contract constructor
    #[constructor]
    fn constructor(ref self: ContractState, owner_: ContractAddress,) {
        // @notice not sure if default is already zero or need to initialise.
        self._epoch_start_timestamp.write(0_u256);
        self._initialised.write(false);

        let mut ownable_self = Ownable::unsafe_new_contract_state();
        ownable_self._transfer_ownership(new_owner: owner_);

    }

     #[external(v0)]
    impl AttributionVoting of super::IAttributionVoting<ContractState> {
        //
        // Getters
        //
        fn get_total_voting_power(self: @ContractState, account: ContractAddress) -> u32 {
            let voted = self._voted.read((account, 'cumulative'));
            initial_vote + u32_sqrt(voted).into()
        }

        fn initialise(ref self: ContractState, month_id: u32, guild: felt252, initial_vote: u32, vote_duration: u128) {
            self._only_owner();
            let is_initialised = self._initialised.read();
            assert (is_initialised == false, 'ALREADY_INITIALISED');

            self._month_id.write(month_id);
            self._guild.write(guild);
            self._initial_vote.write(initial_vote);

            let block_timestamp = get_block_timestamp();
            self._vote_end_timestamp.write(block_timestamp + _vote_duration);

            self._initialised.write(true);

        }
        // todo add reasons to emit in events only(not store)
        fn vote(ref self: ContractState, accounts: Array::<ContractAddress>, votes: Array::<u32>, tags: Array::<felt252>) {
            let state = InternalImpl::_get_state(@self);
            assert (state == 1, 'VOTING_NOT_ACTIVE');
            assert (accounts.len() == votes.len(), 'LENGTH_MISMATCH');
            assert (accounts.len() == tags.len(), 'LENGTH_MISMATCH');
            // TODO only participants can vote
            let caller = get_caller_address();
            let voting_power = self.get_total_voting_power(caller);
            let mut vote_casted = self._vote_casted.read(caller);
            let mut current_index = 0;
            loop {
                if (current_index == accounts.len()) {
                    break;
                }
                vote_casted += *votes[current_index];
                assert (vote_casted <= voting_power, 'INSUFFICIENT_VOTING_POWER');

                InternalImpl::_update_vote(@self, *accounts[current_index], *votes[current_index], *tags[current_index]);
                current_index += 1;
            };
            self._vote_casted.write(vote_casted);

        }

        fn update_contribution(ref self: ContractState) {
            let state = InternalImpl::_get_state(@self);
            assert (state == 2, 'VOTING_NOT_ENDED');



        }

        

    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {

        fn _update_vote(self: @ContractState, account: ContractAddress, vote: u32, tag: felt252) {
            let cum_votes = self._voted.read((*accounts[current_index], 'cumulative'));
            self._voted.write((accounts[current_index], 'cumulative'), cum_votes + vote);

            let votes = self._voted.read((*accounts[current_index], tag));
            self._voted.write((accounts[current_index], tag), cum_votes + vote);
        }

        fn _get_state(self: @ContractState) -> u32 {
            let block_timestamp = get_block_timestamp();
            let end_timestamp = self._vote_end_timestamp.read();
            if (self._initialised.read() == false) {
                0 //NOT_INITIALISED
            } else if (block_timestamp < end_timestamp) {
                1 // ACTIVE
            }else {
                2 // Finished
            }
        }

    }


}

