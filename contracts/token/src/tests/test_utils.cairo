use core::traits::TryInto;
use openzeppelin::utils::serde::SerializedAppend;
use snforge_std::{ContractClass, ContractClassTrait, DeclareResult, declare};
use starknet::ContractAddress;
use starkware_utils::components::roles::interface::{IRolesDispatcher, IRolesDispatcherTrait};
use starkware_utils_testing::test_utils::cheat_caller_address_once;

pub const INITIAL_AMOUNT: u256 = 1000;

pub const PERMITTED_MINTER: ContractAddress = 0x111.try_into().unwrap();
pub const USER_ADDRESS: ContractAddress = 0x222.try_into().unwrap();
pub const GOVERNANCE_ADMIN: ContractAddress = 0x333.try_into().unwrap();
pub const RECIPIENT: ContractAddress = 0x444.try_into().unwrap();
pub const NON_ADMIN: ContractAddress = 0x555.try_into().unwrap();
pub const DEFAULT_UPGRADE_DELAY: u64 = 0;
pub const DECIMALS: u8 = 8;

pub fn deploy_token() -> ContractAddress {
    let contract_class = declare_token();
    let name: ByteArray = "strkBTC";
    let symbol: ByteArray = "strkBTC";
    let decimals: u8 = 8;
    let initial_supply: u256 = 0;

    let mut calldata = array![];
    calldata.append_serde(name);
    calldata.append_serde(symbol);
    calldata.append_serde(decimals);
    calldata.append_serde(initial_supply);
    calldata.append_serde(RECIPIENT);
    calldata.append_serde(PERMITTED_MINTER);
    calldata.append_serde(GOVERNANCE_ADMIN);
    calldata.append_serde(DEFAULT_UPGRADE_DELAY);

    let contract_address: ContractAddress = match contract_class.deploy(@calldata) {
        Result::Ok((contract_address, _)) => contract_address,
        Result::Err(_) => panic!("deploy failed"),
    };
    grant_roles(contract_address);
    contract_address
}

pub fn declare_token() -> ContractClass {
    match declare("token") {
        Result::Ok(declare_result) => match declare_result {
            DeclareResult::Success(class) => class,
            DeclareResult::AlreadyDeclared(class) => class,
        },
        Result::Err(_) => panic!("declare failed"),
    }
}

pub fn grant_roles(contract_address: ContractAddress) {
    let roles_dispatcher = IRolesDispatcher { contract_address };
    cheat_caller_address_once(contract_address, GOVERNANCE_ADMIN);
    roles_dispatcher.register_app_role_admin(GOVERNANCE_ADMIN);

    cheat_caller_address_once(contract_address, GOVERNANCE_ADMIN);
    roles_dispatcher.register_token_admin(PERMITTED_MINTER);
}

pub fn get_deployment_calldata(
    initial_owner: ContractAddress,
    permitted_minter: ContractAddress,
    governance_admin: ContractAddress,
    initial_supply: u256,
) -> Array<felt252> {
    let mut calldata: Array<felt252> = array![];
    let name: ByteArray = "TestToken";
    let symbol: ByteArray = "TT";

    name.serialize(ref calldata);
    symbol.serialize(ref calldata);
    DECIMALS.serialize(ref calldata);
    initial_supply.serialize(ref calldata);
    initial_owner.serialize(ref calldata);
    permitted_minter.serialize(ref calldata);
    governance_admin.serialize(ref calldata);
    DEFAULT_UPGRADE_DELAY.serialize(ref calldata);
    calldata
}
