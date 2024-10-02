use sncast_std::{
    declare, deploy, invoke, call, DeclareResult, DeployResult, InvokeResult, CallResult
};
use starknet::{ ContractAddress, ClassHash };
use debug::PrintTrait;
use deploy_scripts::utils::{owner};

fn main() {
    let max_fee = 99999999999999999;
    let salt = 0x6;

    let organisation_declare_result = declare('Organisation', Option::Some(max_fee), Option::None);
    let organisation_class_hash = organisation_declare_result.class_hash;
    organisation_class_hash.print();
    
    // let mut organisation_constructor_data = Default::default();
    // Serde::serialize(@owner(), ref organisation_constructor_data);
    // let organisation_deploy_result = deploy(organisation_class_hash, organisation_constructor_data, Option::Some(salt), true, Option::Some(max_fee), Option::None);
    // let organisation_contract_address = organisation_deploy_result.contract_address;

    'Organisation Deployed to '.print();
    organisation_contract_address.print();


    let guild_declare_result = declare('GuildSBT', Option::Some(max_fee), Option::None);
    let guild_class_hash = guild_declare_result.class_hash;
    guild_class_hash.print();
    
    // let dev_guld_name = 'Development';
    // let dev_guld_symbol = 'Jedi-Dev';
    // let dev_guld_URI = 'app.jediswap.xyz/dev';
    // let mut contribution_levels: Array<u32> = ArrayTrait::new();
    // contribution_levels.append(100);
    // contribution_levels.append(200);
    // contribution_levels.append(500);
    // contribution_levels.append(1000);

    // let mut guild_dev_constructor_data = Default::default();
    // Serde::serialize(@dev_guld_name, ref guild_dev_constructor_data);
    // Serde::serialize(@dev_guld_symbol, ref guild_dev_constructor_data);
    // Serde::serialize(@dev_guld_URI, ref guild_dev_constructor_data);
    // Serde::serialize(@owner(), ref guild_dev_constructor_data);
    // Serde::serialize(@organisation_contract_address, ref guild_dev_constructor_data);
    // Serde::serialize(@contribution_levels, ref guild_dev_constructor_data);
    // let guild_dev_deploy_result = deploy(guild_class_hash, guild_dev_constructor_data, Option::Some(salt), true, Option::Some(max_fee), Option::None);
    // let guild_dev_contract_address = guild_dev_deploy_result.contract_address;
    
    // 'Dev guild Deployed to '.print();
    // guild_dev_contract_address.print();

    // let design_guld_name = 'Design';
    // let design_guld_symbol = 'Jedi-Design';
    // let design_guld_URI = 'app.jediswap.xyz/design';

    // let mut guild_design_constructor_data = Default::default();
    // Serde::serialize(@design_guld_name, ref guild_design_constructor_data);
    // Serde::serialize(@design_guld_symbol, ref guild_design_constructor_data);
    // Serde::serialize(@design_guld_URI, ref guild_design_constructor_data);
    // Serde::serialize(@owner(), ref guild_design_constructor_data);
    // Serde::serialize(@organisation_contract_address, ref guild_design_constructor_data);
    // Serde::serialize(@contribution_levels, ref guild_design_constructor_data);
    // let guild_design_deploy_result = deploy(guild_class_hash, guild_design_constructor_data, Option::Some(salt), true, Option::Some(max_fee), Option::None);
    // let guild_design_contract_address = guild_design_deploy_result.contract_address;
    
    // 'Design guild Deployed to '.print();
    // guild_design_contract_address.print();

    // let marcom_guld_name = 'Marcom';
    // let marcom_guld_symbol = 'Jedi-Marcom';
    // let marcom_guld_URI = 'app.jediswap.xyz/marcom';

    // let mut guild_marcom_constructor_data = Default::default();
    // Serde::serialize(@marcom_guld_name, ref guild_marcom_constructor_data);
    // Serde::serialize(@marcom_guld_symbol, ref guild_marcom_constructor_data);
    // Serde::serialize(@marcom_guld_URI, ref guild_marcom_constructor_data);
    // Serde::serialize(@owner(), ref guild_marcom_constructor_data);
    // Serde::serialize(@organisation_contract_address, ref guild_marcom_constructor_data);
    // Serde::serialize(@contribution_levels, ref guild_marcom_constructor_data);
    // let guild_marcom_deploy_result = deploy(guild_class_hash, guild_marcom_constructor_data, Option::Some(salt), true, Option::Some(max_fee), Option::None);
    // let guild_marcom_contract_address = guild_marcom_deploy_result.contract_address;
    
    // 'Marcom guild Deployed to '.print();
    // guild_marcom_contract_address.print();
}