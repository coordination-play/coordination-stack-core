// @title Mesh Guild SBTs Cairo 2.2
// @author Mesh Finance
// @license MIT
// @notice SBT contract to give out to contributor

use starknet::ContractAddress;
use array::Array;


#[starknet::interface]
trait IOrganisation<T> {
    fn get_guild_points(self: @T, contributor: ContractAddress, guild: felt252) -> u32;
}

//
// Contract Interface
//
#[starknet::interface]
trait IGuildSBT<TContractState> {
    // view functions
    fn tokenURI(self: @TContractState, token_id: u256) -> Span<felt252>;
    fn tokenURI_from_contributor(self: @TContractState, contributor: ContractAddress) -> Span<felt252>;
    fn get_organisation(self: @TContractState) -> ContractAddress;
    fn get_next_token_id(self: @TContractState) -> u256;
    fn get_contribution_tier(self: @TContractState, contributor: ContractAddress) -> u32;
    fn get_contribution_levels(self: @TContractState) -> Array<u32>;
    fn get_number_of_levels(self: @TContractState) -> u32;
    fn baseURI(self: @TContractState) -> Span<felt252>;
    fn wallet_of_owner(self: @TContractState, account: ContractAddress) -> u256;

    // external functions
    fn update_baseURI(ref self: TContractState, new_baseURI: Span<felt252>);
    fn update_contribution_levels(ref self: TContractState, new_conribution_levels: Array<u32>);
    fn update_organisation(ref self: TContractState, new_organisation: ContractAddress);
    fn safe_mint(ref self: TContractState, token_type: u8);
    fn migrate_sbt(ref self: TContractState, old_address: ContractAddress, new_address: ContractAddress);

}

#[starknet::contract]
mod GuildSBT {

    use option::OptionTrait;
    // use traits::Into;
    use array::{SpanSerde, ArrayTrait};
    use clone::Clone;
    use array::SpanTrait;
    use box::BoxTrait;
    use ecdsa::check_ecdsa_signature;
    use zeroable::Zeroable;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc721::ERC721Component;
    use openzeppelin::access::ownable::OwnableComponent;

    component!(path: OwnableComponent, storage: ownable_storage, event: OwnableEvent);    
    component!(path: ERC721Component, storage: erc721_storage, event: ERC721Event);
    component!(path: SRC5Component, storage: src5_storage, event: SRC5Event);

    #[abi(embed_v0)]
    impl ERC721Impl = ERC721Component::ERC721Impl<ContractState>;
    impl ERC721MetadataImpl = ERC721Component::ERC721MetadataImpl<ContractState>;
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;

    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;


    use openzeppelin::introspection::interface::ISRC5;
    use openzeppelin::introspection::interface::ISRC5Camel;
    use openzeppelin::token::erc721::interface::{
        IERC721, IERC721CamelOnly, IERC721Metadata, IERC721MetadataCamelOnly
    };
    use coordination_stack_core::access::ownable::{Ownable, IOwnable};
    use coordination_stack_core::access::ownable::Ownable::{
        ModifierTrait as OwnableModifierTrait, InternalTrait as OwnableInternalTrait,
    };
    use starknet::ContractAddress;
    use starknet::get_caller_address;

    // use alexandria_storage::list::{List, ListTrait};
    use coordination_stack_core::span_storage::StoreSpanFelt252;
    use coordination_stack_core::array_storage::StoreU32Array;
    use super::{
        IOrganisationDispatcher, IOrganisationDispatcherTrait
    };


    #[storage]
    struct Storage {
        _organisation: ContractAddress,
        _contribution_levels: Array<u32>,
        _baseURI: Span<felt252>,
        _token_type: LegacyMap::<ContractAddress, u8>,
        _next_token_id: u256,
        _wallet_of_owner: LegacyMap::<ContractAddress, u256>,
        #[substorage(v0)]
        erc721_storage: ERC721Component::Storage,
        #[substorage(v0)]
        src5_storage: SRC5Component::Storage,
        #[substorage(v0)]
        ownable_storage: OwnableComponent::Storage
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event
    }

    //
    // Constructor
    //

    // @notice Contract constructor
    #[constructor]
    fn constructor(ref self: ContractState, name_: felt252, symbol_: felt252, baseURI_: Span<felt252>, owner_: ContractAddress, organisation_: ContractAddress, contribution_levels_: Array<u32>) {
        self.erc721_storage.initializer(name: name_, symbol: symbol_);
        self.ownable_storage.initializer(owner);

        self._baseURI.write(baseURI_);
        self._organisation.write(organisation_);
        self._next_token_id.write(1);
        InternalImpl::_update_contribution_levels(ref self, contribution_levels_);
    }

    #[external(v0)]
    impl GuildSBT of super::IGuildSBT<ContractState> {
        //
        // Getters
        //
        fn tokenURI(self: @ContractState, token_id: u256) -> Span<felt252> {
            let owner = self.erc721_storage.owner_of(:token_id);
            let organisation = self._organisation.read();
            let organisationDispatcher = IOrganisatioDispatcher { contract_address: organisation };
            // @notice this is a sample SBT contract for dev guild, update the next line before deploying other guild
            let points = organisationDispatcher.get_guild_points(owner, 'dev');
            let token_type = self._token_type.read(owner);

            let tier = InternalImpl::_get_contribution_tier(self, points);

            InternalImpl::_get_tokenURI(self, tier, token_type)

        }



        fn tokenURI_from_contributor(self: @ContractState, contributor: ContractAddress) -> Span<felt252> {
            let organisation = self._organisation.read();
            let organisationDispatcher = IOrganisationDispatcher { contract_address: organisation };
            // @notice this is a sample SBT contract for dev guild, update the next line before deploying other guild
            let points = organisationDispatcher.get_guild_points(contributor, 'dev');
            let token_type = self._token_type.read(contributor);

            let tier = InternalImpl::_get_contribution_tier(self, points);

            InternalImpl::_get_tokenURI(self, tier, token_type)

        }


        fn get_organisation(self: @ContractState) -> ContractAddress {
            self._organisation.read()
        }

        fn get_next_token_id(self: @ContractState) -> u256 {
            self._next_token_id.read()
        }


        fn get_contribution_tier(self: @ContractState, contributor: ContractAddress) -> u32 {
            let organisation = self._organisation.read();
            let organisationDispatcher = IOrganisationDispatcher { contract_address: organisation };
            let points = organisationDispatcher.get_guild_points(contributor, 'dev');
            InternalImpl::_get_contribution_tier(self, points)
        }


        fn get_contribution_levels(self: @ContractState) -> Array<u32> {
            self._contribution_levels.read()
        }

        fn get_number_of_levels(self: @ContractState) -> u32 {
            self._contribution_levels.read().len()
        }

        fn baseURI(self: @ContractState) -> Span<felt252> {
            self._baseURI.read()
        }

        fn wallet_of_owner(self: @ContractState, account: ContractAddress) -> u256 {
            self._wallet_of_owner.read(account)
        }


        //
        // Setters
        //

        fn update_baseURI(ref self: ContractState, new_baseURI: Span<felt252>) {
            self.ownable_storage.assert_only_owner();
            self._baseURI.write(new_baseURI);
        }

        fn update_contribution_levels(ref self: ContractState, new_conribution_levels: Array<u32>) {
            self.ownable_storage.assert_only_owner();
            InternalImpl::_update_contribution_levels(ref self, new_conribution_levels);

        }
        fn update_organisation(ref self: ContractState, new_organisation: ContractAddress) {
            self.ownable_storage.assert_only_owner();
            self._organisation.write(new_organisation);
        }

        fn safe_mint(ref self: ContractState, token_type: u8) {
            let account = get_caller_address();

            let balance = self.erc721_storage.balance_of(:account);
            assert (balance == 0, 'ALREADY_MINTED');

            let organisation = self._organisation.read();
            let organisationDispatcher = IOrganisationDispatcher { contract_address: organisation };
            let points = organisationDispatcher.get_guild_points(account, 'dev');
            let tier = InternalImpl::_get_contribution_tier(@self, points);

            assert (tier != 0, 'NOT_ENOUGH_POINTS');
            self._token_type.write(account, token_type);
            let token_id = self._next_token_id.read();
            self.erc721_storage._mint(to: account, token_id: token_id.into());
            self._wallet_of_owner.write(account, token_id);
            self._next_token_id.write(token_id + 1);

        }

        fn migrate_sbt(ref self: ContractState, old_address: ContractAddress, new_address: ContractAddress) {
            self._only_organisation();

            let old_address_balance = self.erc721_storage.balance_of(account: old_address);
            if (old_address_balance == 0) {
                return ();
            }

            let new_address_balance = self.erc721_storage.balance_of(account: new_address);
            assert (new_address_balance == 0, 'SBT_ALREADY_FOUND');

            let token_id = self._wallet_of_owner.read(old_address);
            let token_type = self._token_type.read(old_address);

            self.erc721_storage._transfer(from: old_address, to: new_address, :token_id);

            self._wallet_of_owner.write(old_address, 0);
            self._wallet_of_owner.write(new_address, token_id);
            self._token_type.write(new_address, token_type);

        }

    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {

        fn _update_contribution_levels(ref self: ContractState, new_contribution_levels: Array<u32>) {
            self._contribution_levels.write(new_contribution_levels);
        }

        fn _get_contribution_tier(self: @ContractState, points: u32) -> u32 {
            let mut current_index = 0;
            let contribution_levels = self._contribution_levels.read();
            loop {
                if (current_index == contribution_levels.len()) {
                    break;
                }

                if (points < *contribution_levels[current_index]) {
                    break;
                }

                current_index += 1;
            };
            current_index
        }

        fn _get_tokenURI(self: @ContractState, tier: u32, token_type: u8) -> Span<felt252> {
            let baseURI = self._baseURI.read();
            let new_base_uri: Array<felt252> = baseURI.snapshot.clone();
            let mut tmp: Array<felt252> = InternalImpl::append_number_ascii(new_base_uri, tier.into());
            tmp = InternalImpl::append_number_ascii(tmp, token_type.into());
            tmp.append('.json');
            return tmp.span();
        }



        fn append_number_ascii(mut uri: Array<felt252>, mut number_in: u256) -> Array<felt252> {
            // TODO: replace with u256 divide once it's implemented on network
            let mut number: u128 = number_in.try_into().unwrap();
            let mut tmpArray: Array<felt252> = ArrayTrait::new();
            loop {
                if (number == 0.try_into().unwrap()) {
                    break;
                }
                let digit: u128 = number % 10;
                number /= 10;
                tmpArray.append(digit.into() + 48);
            };
            let mut i: u32 = tmpArray.len();
            if (i == 0.try_into().unwrap()) { // deal with 0 case
                uri.append(48);
            }
            loop {
                if i == 0.try_into().unwrap() {
                    break;
                }
                i -= 1;
                uri.append(*tmpArray.get(i.into()).unwrap().unbox());
            };
            return uri;
        }
    }

}

