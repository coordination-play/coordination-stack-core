// @title Coordination-stack Guild in Cairo 2.4.1
// @author Yash (tg-@yashm001)
// @license MIT
// @notice Guild Periphery, to temporary store guilds contribution points for challenge period;

use starknet::ContractAddress;
use array::Array;


#[derive(Copy, Drop, Serde, starknet::Store)]
struct MonthlyContribution {
    // @notice Contributor Address, used in update_contribution function
    contributor: ContractAddress,
    // @notice Contribution for guilds
    point: u32,
}

#[starknet::interface]
trait IOrganisation<TContractState> {
    fn is_granted(self: @TContractState, where: ContractAddress, who: ContractAddress, permission_id: felt252) -> bool;
}

#[starknet::interface]
trait IGuild<TContractState> {
    fn update_contributions(ref self: TContractState, month_id: u32, contributions: Array::<MonthlyContribution>);
}

#[starknet::contract]
mod GuildPeriphery {
    use starknet::{ContractAddress, ClassHash, get_caller_address, get_contract_address, get_block_timestamp, contract_address_const};
    use starknet::syscalls::{replace_class_syscall, call_contract_syscall};
    use coordination_stack_core::utils::array_storage::StoreU32Array;

    use super::{MonthlyContribution, IOrganisationDispatcher, IOrganisationDispatcherTrait, IGuildDispatcher, IGuildDispatcherTrait};

    const ROOT_PERMISSION_ID: felt252 = 'ROOT_PERMISSION';
    const GUARDIAN_ID: felt252 = 'GUARDIAN';

    //
    // Storage Guild Periphery
    //
    #[storage]
    struct Storage {
        _guild: ContractAddress, // @dev guild contract address
        _organisation: ContractAddress, // @dev oragnisation contract address
        _contributions: LegacyMap::< (u32, ContractAddress), u32>, // @dev monthly contributions points for each contributor [(month_id, contributor) => points]
        _total_montly_contribution: LegacyMap::<u32, u32>, // @dev total contribution points allocated each month [month_id => points]
        _last_update_month_id: u32, // @dev contribution update month id
    }

    //
    // Constructor
    //

    // @notice Contract constructor
    #[constructor]
    fn constructor(ref self: ContractState, guild: ContractAddress, organisation: ContractAddress) {
        self._guild.write(guild);
        self._organisation.write(organisation);
    }

    #[external(v0)]
    impl GuildPeriphery of super::IGuildPeriphery<ContractState> {
        
    }
}