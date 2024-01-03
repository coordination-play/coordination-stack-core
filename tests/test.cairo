use array::{Array, ArrayTrait, SpanTrait};
use result::ResultTrait;
use starknet::ContractAddress;
use starknet::ClassHash;
use traits::TryInto;
use option::OptionTrait;
use snforge_std::{ declare, ContractClassTrait, ContractClass, start_warp, start_prank, stop_prank,
                   spy_events, SpyOn, EventSpy, EventFetcher, Event, EventAssertions };
use tests::utils::{ deployer_addr, user1, user2, user3, user4, URI};
use debug::PrintTrait;



#[starknet::interface]
trait IRound<TContractState> {
   fn initialize_round(ref self: TContractState, end_timestamp: u256, round_amount: u256, token: ContractAddress, shares_contract:ContractAddress, total_shares: u256, final_price: u256, initial_discount: u256, threshold: u256, is_whitelisted: bool, whitelist_addresses: Array::<ContractAddress>, whitelist_amounts: Array::<u256>, lock_duration: u64, treasury: ContractAddress);

    // invent in the organization
    fn invest(ref self: TContractState, number_of_shares: u256) -> u256;
    fn finalise_round(ref self: TContractState);
    fn get_avg_price(self: @TContractState, total_shares_committed: u256, shares:u256 ) -> u256;

///////

}

#[starknet::interface]
trait IUSDC<TContractState> {
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;

    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
}

#[starknet::interface]
trait IShares<TContractState> {
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn locked_balance(self: @TContractState, account: ContractAddress) -> u256;
    fn unlocked_balance(self: @TContractState, account: ContractAddress) -> u256;
    fn add_minter(ref self: TContractState, new_minter: ContractAddress);

}




fn deploy_contracts_and_initialise() -> (ContractAddress, ContractAddress, ContractAddress) {
    let mut round_constructor_calldata = Default::default();
    Serde::serialize(@deployer_addr(), ref round_constructor_calldata);
    let round_class = declare('Round');
    let round_address = round_class.deploy(@round_constructor_calldata).unwrap();

    let mut share_constructor_calldata = Default::default();
    Serde::serialize(@deployer_addr(), ref share_constructor_calldata);
    let share_class = declare('Shares');
    let share_address = share_class.deploy(@share_constructor_calldata).unwrap();

    let mut usdc_constructor_calldata = Default::default();
    Serde::serialize(@deployer_addr(), ref usdc_constructor_calldata);
    let usdc_class = declare('USDC');
    let usdc_address = usdc_class.deploy(@usdc_constructor_calldata).unwrap();

    let round_dispatcher = IRoundDispatcher { contract_address: round_address };

    let end_time = 22222222222;
    let round_amount = 300000000000000000000;
    let total_share = 100;
    let final_price = 4;
    let initial_discount = 50;
    let threshold = 50;
    let is_whitelisted = false;
    let lock_duration = 600;

    let mut whitelisted_addresses: Array<ContractAddress> = ArrayTrait::new();
    let mut whitelisted_amounts: Array<u256> = ArrayTrait::new();
  


    start_prank(round_address, deployer_addr());
    round_dispatcher.initialize_round(end_time, round_amount, usdc_address, share_address, total_share, final_price, initial_discount, threshold, is_whitelisted, whitelisted_addresses, whitelisted_amounts,lock_duration, usdc_address );
    stop_prank(round_address);
    (round_address, share_address, usdc_address)
}

#[test]
fn test_update_contribution_points() { 
    let (round_address, share_address, usdc_address) = deploy_contracts_and_initialise();

    let usdc_dispatcher = IUSDCDispatcher { contract_address: usdc_address };
    start_prank(usdc_address, deployer_addr());
    usdc_dispatcher.mint(user1(), 1000000000000000000000);
    stop_prank(usdc_address);

    start_prank(usdc_address, user1());
    usdc_dispatcher.approve(round_address, 1000000000000000000000);
    stop_prank(usdc_address);

    let balance_after1 = usdc_dispatcher.balance_of(user1());
    balance_after1.print();

    let round_dispatcher = IRoundDispatcher { contract_address: round_address };
    // let mut price = round_dispatcher.get_avg_price(0,10);
    // price.print();
    // price = round_dispatcher.get_avg_price(10,10);
    // price.print();
    start_prank(round_address, user1());
    round_dispatcher.invest(10);
    stop_prank(round_address);

    let balance_after2 = usdc_dispatcher.balance_of(user1());
    (balance_after1 - balance_after2).print();

    let round_dispatcher = IRoundDispatcher { contract_address: round_address };
    start_prank(round_address, user1());
    round_dispatcher.invest(60);
    stop_prank(round_address);

    let balance_after3 = usdc_dispatcher.balance_of(user1());
    (balance_after2 - balance_after3).print();

    let share_dispatcher = ISharesDispatcher { contract_address: share_address };

    start_prank(share_address, deployer_addr());
    share_dispatcher.add_minter(round_address);
    stop_prank(share_address);

    start_warp(round_address, 22222222233);
    start_prank(round_address, user1());
    round_dispatcher.finalise_round();
    stop_prank(round_address);

    let balance = share_dispatcher.balance_of(user1());
    balance.print();

    let locked_balance = share_dispatcher.locked_balance(user1());
    locked_balance.print();

    let unlocked_balance = share_dispatcher.unlocked_balance(user1());
    unlocked_balance.print();

    let balance_after = usdc_dispatcher.balance_of(user1());
    balance_after.print();

    start_warp(share_address, 22222232233);
    let balance = share_dispatcher.balance_of(user1());
    balance.print();

    let locked_balance = share_dispatcher.locked_balance(user1());
    locked_balance.print();

    let unlocked_balance = share_dispatcher.unlocked_balance(user1());
    unlocked_balance.print();


}
