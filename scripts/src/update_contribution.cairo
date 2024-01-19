use sncast_std::{
    declare, deploy, invoke, call, DeclareResult, DeployResult, InvokeResult, CallResult, get_nonce
};
use starknet::{ ContractAddress, ClassHash };
use debug::PrintTrait;
use deploy_scripts::utils::{owner, user1};
use coordination_stack_core::guildSBT::{MonthlyContribution};


fn main() {

    let max_fee = 999999999999999;
    let contract_address: ContractAddress = 0x0522ee5ec7ed95fde8bff3cdcc015a5445b79291f75e074b599302b58cbd94ea
        .try_into()
        .expect('Invalid contract address value');

    let month_id = 092023;
    let user1_contribution = MonthlyContribution{ contributor: user1(), point: 135};
    // let user2_contribution = MonthlyContribution{ contributor: user2(), point: 200};

    let mut contributions: Array<MonthlyContribution> = ArrayTrait::new();
    contributions.append(user1_contribution);
    // contributions.append(user2_contribution);

    let mut invoke_data = Default::default();
    Serde::serialize(@month_id, ref invoke_data);
    Serde::serialize(@contributions, ref invoke_data);

    let invoke_result = invoke(
        contract_address, 'update_contibutions', invoke_data, Option::Some(max_fee), Option::None
    );

    'Invoke tx hash is'.print();
    invoke_result.transaction_hash.print();

}