use starknet:: { ContractAddress, contract_address_try_from_felt252, contract_address_const };
use snforge_std::{declare, start_prank, stop_prank, ContractClass, ContractClassTrait, CheatTarget};

use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};


fn owner() -> ContractAddress {
    contract_address_try_from_felt252('owner').unwrap()
}


fn zero_addr() -> ContractAddress {
    contract_address_const::<0>()
}

fn user1() -> ContractAddress {
    contract_address_try_from_felt252('user1').unwrap()
}

fn user2() -> ContractAddress {
    contract_address_try_from_felt252('user2').unwrap()
}

fn user3() -> ContractAddress {
    contract_address_try_from_felt252('user3').unwrap()
}

fn user4() -> ContractAddress {
    contract_address_try_from_felt252('user4').unwrap()
}

fn URI() -> Span<felt252> {
    let mut uri = ArrayTrait::new();

    uri.append('api.jediswap/');
    uri.append('guildSBT/');
    uri.append('dev/');

    uri.span()
}

fn usdc() -> ContractAddress {
    let erc20_class = declare("ERC20");
    let token_name:ByteArray = "usdc";
    let token_symbol:ByteArray = "USDC";
    let initial_supply: u256 = 200_000_000;

    let mut token0_constructor_calldata = Default::default();
    Serde::serialize(@token_name, ref token0_constructor_calldata);
    Serde::serialize(@token_symbol, ref token0_constructor_calldata);
    Serde::serialize(@initial_supply, ref token0_constructor_calldata);
    Serde::serialize(@owner(), ref token0_constructor_calldata);
    let usdc_address = erc20_class.deploy(@token0_constructor_calldata).unwrap();


    // start_prank(CheatTarget::One(usdc_address), owner());
    // let token_dispatcher = IERC20Dispatcher { contract_address: token0_address };
    // token_dispatcher.transfer(user2(), 100 * pow(10, 18) * pow(10, 18));
    // stop_prank(CheatTarget::One(token0_address));
    usdc_address
}

