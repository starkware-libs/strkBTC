use core::poseidon::poseidon_hash_span;
use core::serde::Serde;
use core::traits::TryInto;
use openzeppelin::utils::serde::SerializedAppend;
use snforge_std::{ContractClass, ContractClassTrait, DeclareResult, declare};
use starknet::ContractAddress;
use starkware_utils::components::roles::interface::{IRolesDispatcher, IRolesDispatcherTrait};
use starkware_utils_testing::test_utils::cheat_caller_address_once;

pub const GOVERNANCE_ADMIN: ContractAddress = 0x999.try_into().unwrap();
pub const APP_GOVERNOR: ContractAddress = 0x888.try_into().unwrap();
pub const SIGNER_ONE: ContractAddress = 0x111.try_into().unwrap();
pub const SIGNER_TWO: ContractAddress = 0x222.try_into().unwrap();
pub const NON_SIGNER: ContractAddress = 0x333.try_into().unwrap();

pub fn declare_class(name: ByteArray) -> ContractClass {
    match declare(name) {
        Result::Ok(declare_result) => match declare_result {
            DeclareResult::Success(class) => class,
            DeclareResult::AlreadyDeclared(class) => class,
        },
        Result::Err(_) => panic!("declare failed"),
    }
}

pub fn deploy_registry() -> ContractAddress {
    let class = declare_class("registry");
    let mut calldata = array![];
    calldata.append_serde(GOVERNANCE_ADMIN);
    calldata.append_serde(0_u64);

    // calldata.append_serde(2_u32);
    // calldata.append_serde(signer_one());
    // calldata.append_serde(pubkey_one());
    // calldata.append_serde(signer_two());
    // calldata.append_serde(pubkey_two());

    let registry_address = match class.deploy(@calldata) {
        Result::Ok((addr, _)) => addr,
        Result::Err(_) => panic!("registry deploy failed"),
    };
    grant_roles(registry_address);
    registry_address
}

pub fn grant_roles(contract_address: ContractAddress) {
    let roles_dispatcher = IRolesDispatcher { contract_address };
    cheat_caller_address_once(contract_address, GOVERNANCE_ADMIN);
    roles_dispatcher.register_app_role_admin(GOVERNANCE_ADMIN);

    cheat_caller_address_once(contract_address, GOVERNANCE_ADMIN);
    roles_dispatcher.register_app_governor(APP_GOVERNOR);
}

pub fn compute_withdraw_id(raw_tx: @ByteArray) -> felt252 {
    let mut serialized: Array<felt252> = array![];
    raw_tx.serialize(ref serialized);
    poseidon_hash_span(serialized.span())
}

pub fn pubkey_one() -> ByteArray {
    "02aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
}

pub fn pubkey_two() -> ByteArray {
    "03bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
}

pub fn raw_tx_a() -> ByteArray {
    "deadbeef"
}

pub fn raw_tx_b() -> ByteArray {
    "cafebabe"
}

pub fn raw_tx_c() -> ByteArray {
    "0011223344"
}
