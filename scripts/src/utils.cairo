use option::OptionTrait;
use starknet:: { ContractAddress, ClassHash, contract_address_const};



fn owner() -> ContractAddress {
    contract_address_const::<0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8>()
}
fn user1() -> ContractAddress {
    contract_address_const::<0x077693Ab83817cafC057BcF899cAC39ED24DB5984b9e890BDD91E9c10c20f4cC>()
}

