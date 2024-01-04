use sncast_std::{
    declare, deploy, invoke, call, DeclareResult, DeployResult, InvokeResult, CallResult, get_nonce
};
use starknet::{ ContractAddress, ClassHash };
use debug::PrintTrait;
use scripts::utils::{owner};

fn main() {
    let max_fee = 9999999;
    let salt = 0x6;
    let nonce = get_nonce('latest');
    nonce.print();

    let simple_declare_result = declare('Simple', Option::Some(max_fee), Option::None);
    let simple_class_hash = simple_declare_result.class_hash;
    let mut simple_constructor_data = Default::default();

    let simple_deploy_result = deploy(simple_class_hash, simple_constructor_data, Option::Some(salt), true, Option::Some(max_fee), Option::Some(nonce));
    let simple_contract_address = simple_deploy_result.contract_address;

    'simple Deployed to '.print();
    simple_contract_address.print();
}