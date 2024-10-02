use sncast_std::{
    declare, deploy, invoke, call, DeclareResult, DeployResult, InvokeResult, CallResult, get_nonce
};
use starknet::{ ContractAddress, ClassHash, class_hash_const };
use debug::PrintTrait;
use deploy_scripts::utils::{owner};

fn main() {
    let max_fee = 9999999999999999;
    let salt = 0x6;
    let nonce = get_nonce('latest');
    nonce.print();

    let organisation_class_hash: ClassHash = class_hash_const::<0x2705b2a8a734c79b7399896bd071bbfe3103c874e3dce5c6604bd6ab0886c3a>();
    let guild_class_hash: ClassHash = class_hash_const::<0x27f887a53f92d83da1cd43259dc6436341f0fc445d7048604496f3d7d006219>();
    let factory_declare_result = declare('Factory', Option::Some(max_fee), Option::Some(nonce));
    let factory_class_hash = factory_declare_result.class_hash;
    let mut factory_constructor_data = Default::default();
    Serde::serialize(@owner(), ref factory_constructor_data);
    Serde::serialize(@organisation_class_hash, ref factory_constructor_data);
    Serde::serialize(@guild_class_hash, ref factory_constructor_data);

    let nonce2 = get_nonce('latest');
    nonce2.print();
    let factory_deploy_result = deploy(factory_class_hash, factory_constructor_data, Option::Some(salt), true, Option::Some(max_fee), Option::Some(nonce2));
    let factory_contract_address = factory_deploy_result.contract_address;

    'factory Deployed to '.print();
    factory_contract_address.print();
}