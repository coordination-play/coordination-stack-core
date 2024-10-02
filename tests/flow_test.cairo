use array::{Array, ArrayTrait, SpanTrait};
use result::ResultTrait;
use starknet::ContractAddress;
use starknet::ClassHash;
use traits::TryInto;
use option::OptionTrait;
use snforge_std::{
    declare, ContractClassTrait, start_prank, stop_prank, CheatTarget, spy_events,
    SpyOn, EventSpy, EventFetcher, Event, EventAssertions
};
use tests::utils::{ owner, user1, user2, user3, usdc, URI};
use core::debug::PrintTrait;
use coordination_stack_core::factory::{
    IFactoryDispatcher, IFactoryDispatcherTrait, Factory
};
use coordination_stack_core::organisation::{
    IOrganisationDispatcher, IOrganisationDispatcherTrait, Organisation
};
use coordination_stack_core::guild::{
    IGuildDispatcher, IGuildDispatcherTrait, Guild, MonthlyContribution
};
use coordination_stack_core::treasury::{
    ITreasuryDispatcher, ITreasuryDispatcherTrait, Treasury
};
use coordination_stack_core::salary_distributor::{
    ISalaryDistributorDispatcher, ISalaryDistributorDispatcherTrait, SalaryDistributor
};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};



fn setup_factory() -> (ContractAddress, ContractAddress) {
    let owner = owner();
    let organisation_class = declare("Organisation");
    let guild_class = declare("Guild");
    let salary_distributor_class = declare("SalaryDistributor");
    let treasury_class = declare("Treasury");
    'ff'.print();
    let factory_class = declare("Factory");
    let mut factory_constructor_calldata = Default::default();
    Serde::serialize(@organisation_class.class_hash, ref factory_constructor_calldata);
    'gg'.print();
    Serde::serialize(@guild_class.class_hash, ref factory_constructor_calldata);
    Serde::serialize(@treasury_class.class_hash, ref factory_constructor_calldata);
    Serde::serialize(@salary_distributor_class.class_hash, ref factory_constructor_calldata);
    Serde::serialize(@owner, ref factory_constructor_calldata);

    let factory_address = factory_class.deploy(@factory_constructor_calldata).unwrap();
    'hh'.print();
    (owner, factory_address)
}

fn create_organisation(factory_address: ContractAddress, name: felt252, metadata: Span<felt252>) -> ContractAddress {
    factory_address.print();
    let factory_dispatcher = IFactoryDispatcher { contract_address: factory_address };

    let org_address = factory_dispatcher.create_organisation(name, metadata);
    org_address
}

fn add_treasury(org_address: ContractAddress, owner: ContractAddress, usdc_address: ContractAddress) -> ContractAddress {
    let org_dispatcher = IOrganisationDispatcher { contract_address: org_address };
    org_dispatcher.add_treasury_contract(owner);

    let treasury_address = org_dispatcher.get_treasury();

    let usdc_dispatcher = IERC20Dispatcher {contract_address: usdc_address};
    start_prank(CheatTarget::One(usdc_address), owner());
    usdc_dispatcher.transfer(treasury_address, 100_000);
    stop_prank(CheatTarget::One(usdc_address));

    treasury_address
}

fn add_salary_distributor(org_address: ContractAddress, usdc_address: ContractAddress) -> ContractAddress {
    let org_dispatcher = IOrganisationDispatcher { contract_address: org_address };
    org_dispatcher.update_salary_distributor_contract(usdc_address);
    let salary_distributor_address = org_dispatcher.get_salary_distributor_contract();
    salary_distributor_address
}

fn create_guild(org_address: ContractAddress, name: felt252, owner: ContractAddress) -> ContractAddress {
    let org_dispatcher = IOrganisationDispatcher { contract_address: org_address };
    let guild_address = org_dispatcher.add_guild(name, owner);
    guild_address
}

fn update_contribution(guild_address: ContractAddress, month_id: u32) {
    let guild_dispatcher = IGuildDispatcher { contract_address: guild_address };

    let user1_contribution = MonthlyContribution{ contributor: user1(), point: 120};
    let user2_contribution = MonthlyContribution{ contributor: user2(), point: 200};
    let mut contributions: Array<MonthlyContribution> = ArrayTrait::new();
    contributions.append(user1_contribution);
    contributions.append(user2_contribution);
    start_prank(CheatTarget::One(guild_address), owner());
    guild_dispatcher.update_contributions(month_id, contributions);
    stop_prank(CheatTarget::One(guild_address));

}

#[test]
fn test_flow() {
    'aa'.print();
    let (owner, factory_address) = setup_factory();
    let usdc_address = usdc();
    'bb'.print();
    let org_address = create_organisation(factory_address,'JediSwap', URI());
    'cc'.print();
    // let org_dispatcher = IOrganisationDispatcher { contract_address: org_address };
    let guild_address = create_guild(org_address, 'dev', owner);
    let treasury_address = add_treasury(org_address, owner, usdc_address);
    let salary_distributor_address = add_salary_distributor(org_address, usdc_address);

    update_contribution(guild_address, 12024);

    let treasury_dispatcher = ITreasuryDispatcher { contract_address: treasury_address };
    let mut amounts: Array<u256> = ArrayTrait::new();
    amounts.append(1000);
    let mut guilds: Array<ContractAddress> = ArrayTrait::new();
    guilds.append(guild_address);

    start_prank(CheatTarget::One(treasury_address), owner());
    treasury_dispatcher.allocate_funds_for_salary(12024, amounts, guilds);
    stop_prank(CheatTarget::One(treasury_address));


    



    // assert(org_dispatcher.name() == "Jediswap", "Invalid name");
    

}