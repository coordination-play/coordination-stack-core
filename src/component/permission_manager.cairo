// @title Coordination-stack PermissionManager in Cairo 2.4.1
// @author Yash (tg- yashm001)
// @license MIT
// @notice Pemission Manager, to manage the permissions within organisation

use starknet::ContractAddress;



#[derive(Copy, Drop, Serde, starknet::Store)]
enum Operation {
    Grant,
    Revoke
}

#[derive(Copy, Drop, Serde, starknet::Store)]
struct SingleTargetPermission {
    operation: Operation,
    who: ContractAddress,
    permission_id: felt252
}

#[derive(Copy, Drop, Serde, starknet::Store)]
struct MultiTargetPermission {
    operation: Operation,
    who: ContractAddress,
    where: ContractAddress,
    permission_id: felt252
}

//
// Contract Interface
//
#[starknet::interface]
trait IPermissionManager<TContractState> {
    // view functions
    fn is_granted(self: @TContractState, where: ContractAddress, who: ContractAddress, permission_id: felt252) -> bool;

    // write functions
    fn grant(ref self: TContractState, where: ContractAddress, who: ContractAddress, permission_id: felt252);
    fn revoke(ref self: TContractState, where: ContractAddress, who: ContractAddress, permission_id: felt252);
    fn apply_single_target_permission(ref self: TContractState, where: ContractAddress, permissions: Array::<SingleTargetPermission>);
    fn apply_multiple_target_permission(ref self: TContractState, permissions: Array::<MultiTargetPermission>);

}

#[starknet::component]
mod PermissionManagerComponent {
    use poseidon::poseidon_hash_span;
    use starknet::{ContractAddress, get_caller_address, get_contract_address, contract_address_const};

    use super::{SingleTargetPermission, MultiTargetPermission, Operation};

    // A special address encoding permissions that are valid for any address `where`.
    // const ANY_ADDR: ContractAddress = contract_address_const::<0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF>(); // Not supported for now (only literal const supported)
    // const ANY_ADDR: ContractAddress = '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF'; 
    // is it possible to hash while keeping it const, or need to initilaise in constructor as storage.
    const ROOT_PERMISSION_ID: felt252 = 'ROOT_PERMISSION';

    //
    // Storage PermissionManager
    //
    #[storage]
    struct Storage {
        _permissions_hashed: LegacyMap::<felt252, bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Granted: Granted,
        Revoked: Revoked,
    }


    // @notice An event emitted whenever a premission is granted via grant
    #[derive(Drop, starknet::Event)]
    struct Granted {
        who: ContractAddress, 
        where: ContractAddress,
        permission_id: felt252
    }

    // @notice An event emitted whenever a premission is revoked via revoke
    #[derive(Drop, starknet::Event)]
    struct Revoked {
        who: ContractAddress, 
        where: ContractAddress,
        permission_id: felt252
    }
    //
    // Constructor
    //

    // // @notice Contract constructor
    // #[constructor]
    // fn constructor(ref self: ContractState, owner: ContractAddress) {
    //     let current_contract = get_contract_address();
    //     let caller = get_caller_address();
    //     InternalImpl::_grant(ref self, current_contract, owner, ROOT_PERMISSION_ID);
    //     InternalImpl::_grant(ref self, current_contract, caller, ROOT_PERMISSION_ID);

    // }


    #[embeddable_as(PermissionManagerImpl)]
    impl PermissionManager<
        TContractState, +HasComponent<TContractState>
    > of super::IPermissionManager<ComponentState<TContractState>> {
        //
        // Getters
        //
        fn is_granted(self: @ComponentState<TContractState>, where: ContractAddress, who: ContractAddress, permission_id: felt252) -> bool {
            let perm_hash: felt252 = InternalImpl::_permission_hash(self, where, who, permission_id);
            if (self._permissions_hashed.read(perm_hash)) {
                return true;
            }
            // check is caller have Root Priviledges
            if (permission_id != ROOT_PERMISSION_ID) {
                let root_perm_hash: felt252 = InternalImpl::_permission_hash(self, where, who, ROOT_PERMISSION_ID);
                if (self._permissions_hashed.read(root_perm_hash)) {
                    return true;
                }
            }

            // Generic target (`_where: ANY_ADDR`) condition check
            // let generic_target_perm_hash: felt252 = InternalImpl::_permission_hash(self, ANY_ADDR, who, permission_id);
            // if (self._permissions_hashed.read(generic_target_perm_hash)) {
            //     return true;
            // }
            
            false
        }

        //
        // Setters
        //

        fn grant(ref self: ComponentState<TContractState>, where: ContractAddress, who: ContractAddress, permission_id: felt252) {
            let has_root_permission = self._root_auth(where);
            assert (has_root_permission, 'UNAUTHORISED');

            InternalImpl::_grant(ref self, where, who, permission_id);
        }

        fn revoke(ref self: ComponentState<TContractState>, where: ContractAddress, who: ContractAddress, permission_id: felt252) {
            let has_root_permission = self._root_auth(where);
            assert (has_root_permission, 'UNAUTHORISED');

            InternalImpl::_revoke(ref self, where, who, permission_id);
        }

        fn apply_single_target_permission(ref self: ComponentState<TContractState>, where: ContractAddress, permissions: Array::<SingleTargetPermission>) {
            let has_root_permission = self._root_auth(where);
            assert (has_root_permission, 'UNAUTHORISED');

            let mut current_index = 0;
            loop {
                if (current_index == permissions.len()) {
                    break;
                }
                let permission = *permissions.at(current_index);
                match permission.operation {
                    Operation::Grant => {
                        InternalImpl::_grant(ref self, where, permission.who, permission.permission_id);
                    },
                    Operation::Revoke => {
                        InternalImpl::_revoke(ref self, where, permission.who, permission.permission_id);
                    }
                }
                current_index += 1;
            };

        }

        fn apply_multiple_target_permission(ref self: ComponentState<TContractState>, permissions: Array::<MultiTargetPermission>){

        }
    }

    #[generate_trait]
    impl InternalImpl<
        TContractState, +HasComponent<TContractState>
    > of InternalTrait<TContractState> {
        //
        // Internals
        //

        /// This function should be called at construction time.
        fn initializer(ref self: ComponentState<TContractState>, owner: ContractAddress) {
            let current_contract = get_contract_address();
            self._grant(current_contract, owner, ROOT_PERMISSION_ID);
        }

        fn _root_auth(ref self: ComponentState<TContractState>, where: ContractAddress) -> bool {
            let caller = get_caller_address();
            let current_contract = get_contract_address();
            
            // check if caller have ROOT PERMISSION in target contract
            if(self.is_granted(caller, where, ROOT_PERMISSION_ID)) {
                return true;
            }

            // check if caller have ROOT PERMISSION in permission manager contract
            if(self.is_granted(caller, current_contract, ROOT_PERMISSION_ID)) {
                return true;
            }

            return false;
        }

        fn _grant(ref self: ComponentState<TContractState>, where: ContractAddress, who: ContractAddress, permission_id: felt252) {
            // if (permission_id == ROOT_PERMISSION_ID && where == ANY_ADDR) {
            //     assert(false, 'ROOT_ANY_ADDR_DISALLOWED');
            // }
            let perm_hash: felt252 = InternalImpl::_permission_hash(@self, where, who, permission_id);
            let current_flag = self._permissions_hashed.read(perm_hash);
 
            if (current_flag == false) {
                self._permissions_hashed.write(perm_hash, true);

                self.emit(Granted {who: who, where: where, permission_id: permission_id});
            }
            
        }

        fn _revoke(ref self: ComponentState<TContractState>, where: ContractAddress, who: ContractAddress, permission_id: felt252) {
            let perm_hash: felt252 = InternalImpl::_permission_hash(@self, where, who, permission_id);
            let current_flag = self._permissions_hashed.read(perm_hash);
 
            if (current_flag == true) {
                self._permissions_hashed.write(perm_hash, false);

                self.emit(Revoked {who: who, where: where, permission_id: permission_id});
            }
            
        }

        fn _permission_hash(self: @ComponentState<TContractState>, where: ContractAddress, who: ContractAddress, permission_id: felt252) -> felt252 {
            let mut hash_data = array![];
            Serde::serialize(@where, ref hash_data);
            Serde::serialize(@who, ref hash_data);
            Serde::serialize(@permission_id, ref hash_data);

            poseidon_hash_span(hash_data.span())
        }

    } 
}