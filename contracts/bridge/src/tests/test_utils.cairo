use core::traits::TryInto;
use openzeppelin::utils::serde::SerializedAppend;
use snforge_std::{ContractClass, ContractClassTrait, DeclareResult, declare};
use starknet::ContractAddress;
use starkware_utils::components::roles::interface::{IRolesDispatcher, IRolesDispatcherTrait};
use starkware_utils_testing::test_utils::cheat_caller_address_once;
use strkbtc_bridge::interface::{IBridgeDispatcher, IBridgeDispatcherTrait};

pub const MIN_WITHDRAW_AMOUNT: u256 = 10_000_000; // 0.1 BTC
pub const VOUT: u32 = 1;
pub const DEPOSIT_AMOUNT: u256 = 1_000_000_000; // 10 BTC
pub const WITHDRAW_AMOUNT: u256 = 100_000_000; // 1 BTC
pub const GOVERNANCE_ADMIN: ContractAddress = 0x999.try_into().unwrap();
pub const SIGNER_ONE: ContractAddress = 0x111.try_into().unwrap();
pub const SIGNER_TWO: ContractAddress = 0x222.try_into().unwrap();
pub const SIGNER_THREE: ContractAddress = 0x333.try_into().unwrap();
pub const NON_SIGNER: ContractAddress = 0x444.try_into().unwrap();
pub const USER_ADDRESS: ContractAddress = 0x555.try_into().unwrap();
pub const APP_GOVERNOR: ContractAddress = 0x666.try_into().unwrap();

pub fn btc_txid() -> ByteArray {
    "001122aabbcc"
}

pub fn btc_public_key_1() -> ByteArray {
    "btcpubkey1"
}

pub fn btc_public_key_2() -> ByteArray {
    "btcpubkey2"
}

pub fn btc_public_key_3() -> ByteArray {
    "btcpubkey3"
}


fn declare_class(name: ByteArray) -> ContractClass {
    match declare(name) {
        Result::Ok(declare_result) => match declare_result {
            DeclareResult::Success(class) => class,
            DeclareResult::AlreadyDeclared(class) => class,
        },
        Result::Err(_) => panic!("declare failed"),
    }
}

pub fn deploy_mock_token() -> ContractAddress {
    let class = declare_class("mintable_token_mock");
    let calldata = array![];
    match class.deploy(@calldata) {
        Result::Ok((addr, _)) => addr,
        Result::Err(_) => panic!("deploy token mock failed"),
    }
}

pub fn deploy_mock_registry() -> ContractAddress {
    let class = declare_class("registry_mock");
    let calldata = array![];
    match class.deploy(@calldata) {
        Result::Ok((addr, _)) => addr,
        Result::Err(_) => panic!("deploy registry mock failed"),
    }
}

pub fn deploy_bridge(
    token_address: ContractAddress, registry_address: ContractAddress, quorum: u64,
) -> ContractAddress {
    let class = declare_class("bridge");
    let mut calldata = array![];
    calldata.append_serde(GOVERNANCE_ADMIN);
    calldata.append_serde(0_u64);

    let bridge_address = match class.deploy(@calldata) {
        Result::Ok((addr, _)) => addr,
        Result::Err(_) => panic!("bridge deploy failed"),
    };
    grant_roles(bridge_address);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge
        .init_bridge(
            :token_address, :registry_address, :quorum, min_withdraw_amount: MIN_WITHDRAW_AMOUNT,
        );
    bridge_address
}

pub fn grant_roles(contract_address: ContractAddress) {
    let roles_dispatcher = IRolesDispatcher { contract_address };
    cheat_caller_address_once(contract_address, GOVERNANCE_ADMIN);
    roles_dispatcher.register_app_role_admin(GOVERNANCE_ADMIN);

    cheat_caller_address_once(contract_address, GOVERNANCE_ADMIN);
    roles_dispatcher.register_app_governor(APP_GOVERNOR);
}
