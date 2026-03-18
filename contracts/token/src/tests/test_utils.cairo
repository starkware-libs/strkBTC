use core::traits::TryInto;
use openzeppelin::utils::serde::SerializedAppend;
use snforge_std::{ContractClassTrait, DeclareResult, declare};
use starknet::ContractAddress;
use starkware_utils::components::roles::interface::{IRolesDispatcher, IRolesDispatcherTrait};
use starkware_utils_testing::test_utils::cheat_caller_address_once;

pub const INITIAL_AMOUNT: u256 = 1000;

pub const TOKEN_ADMIN: ContractAddress = 0x111.try_into().unwrap();
pub const USER_ADDRESS: ContractAddress = 0x222.try_into().unwrap();
pub const GOVERNANCE_ADMIN: ContractAddress = 0x333.try_into().unwrap();
pub const RECIPIENT: ContractAddress = 0x444.try_into().unwrap();
pub const NON_ADMIN: ContractAddress = 0x555.try_into().unwrap();

pub fn deploy_token() -> ContractAddress {
    let contract_class = match declare("token") {
        Result::Ok(declare_result) => match declare_result {
            DeclareResult::Success(class) => class,
            DeclareResult::AlreadyDeclared(class) => class,
        },
        Result::Err(_) => panic!("declare failed"),
    };

    let mut calldata = array![];
    calldata.append_serde(GOVERNANCE_ADMIN);
    calldata.append_serde(0_u64);

    let contract_address: ContractAddress = match contract_class.deploy(@calldata) {
        Result::Ok((contract_address, _)) => contract_address,
        Result::Err(_) => panic!("deploy failed"),
    };
    grant_roles(contract_address);
    contract_address
}

pub fn grant_roles(contract_address: ContractAddress) {
    let roles_dispatcher = IRolesDispatcher { contract_address };
    cheat_caller_address_once(contract_address, GOVERNANCE_ADMIN);
    roles_dispatcher.register_app_role_admin(GOVERNANCE_ADMIN);

    cheat_caller_address_once(contract_address, GOVERNANCE_ADMIN);
    roles_dispatcher.register_token_admin(TOKEN_ADMIN);
}
