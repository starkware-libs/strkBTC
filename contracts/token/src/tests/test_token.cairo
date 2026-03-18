use openzeppelin::interfaces::erc20::{
    IERC20Dispatcher, IERC20DispatcherTrait, IERC20MetadataDispatcher,
    IERC20MetadataDispatcherTrait,
};
use starkware_utils::interfaces::mintable_token::{
    IMintableTokenDispatcher, IMintableTokenDispatcherTrait,
};
use starkware_utils_testing::test_utils::cheat_caller_address_once;
use strkbtc_token::tests::test_utils::{
    INITIAL_AMOUNT, NON_ADMIN, RECIPIENT, TOKEN_ADMIN, USER_ADDRESS, deploy_token,
};

#[test]
fn test_token_metadata() {
    let token_address = deploy_token();
    let metadata = IERC20MetadataDispatcher { contract_address: token_address };

    assert(metadata.name() == "strkBTC", 'BAD_NAME');
    assert(metadata.symbol() == "strkBTC", 'BAD_SYMBOL');
    assert(metadata.decimals() == 8, 'BAD_DECIMALS');
}

#[test]
fn test_token_admin_can_mint() {
    let token_address = deploy_token();
    let erc20 = IERC20Dispatcher { contract_address: token_address };
    let mintable = IMintableTokenDispatcher { contract_address: token_address };

    assert(erc20.total_supply() == 0, 'BAD_SUPPLY');
    assert(erc20.balance_of(USER_ADDRESS) == 0, 'BAD_BALANCE');

    cheat_caller_address_once(token_address, TOKEN_ADMIN);
    mintable.permissioned_mint(USER_ADDRESS, INITIAL_AMOUNT);

    assert(erc20.balance_of(USER_ADDRESS) == INITIAL_AMOUNT, 'MINT_BALANCE');
    assert(erc20.total_supply() == INITIAL_AMOUNT, 'MINT_SUPPLY');
}

#[test]
fn test_token_admin_can_burn() {
    let token_address = deploy_token();
    let erc20 = IERC20Dispatcher { contract_address: token_address };
    let mintable = IMintableTokenDispatcher { contract_address: token_address };

    cheat_caller_address_once(token_address, TOKEN_ADMIN);
    mintable.permissioned_mint(USER_ADDRESS, INITIAL_AMOUNT);
    assert(erc20.total_supply() == INITIAL_AMOUNT, 'MINT_FAILED');

    cheat_caller_address_once(token_address, TOKEN_ADMIN);
    mintable.permissioned_burn(USER_ADDRESS, INITIAL_AMOUNT);

    assert(erc20.balance_of(USER_ADDRESS) == 0, 'BURN_BALANCE');
    assert(erc20.total_supply() == 0, 'BURN_SUPPLY');
}

#[test]
fn test_is_permitted_minter() {
    let token_address = deploy_token();
    let mintable = IMintableTokenDispatcher { contract_address: token_address };

    assert(mintable.is_permitted_minter(TOKEN_ADMIN), 'TOKEN_ADMIN_NOT_ALLOWED');
    assert(!mintable.is_permitted_minter(USER_ADDRESS), 'USER_ADDRESS_ALLOWED');
}

#[test]
#[should_panic(expected: "ONLY_TOKEN_ADMIN")]
fn test_non_token_admin_cannot_mint() {
    let token_address = deploy_token();
    let mintable = IMintableTokenDispatcher { contract_address: token_address };
    mintable.permissioned_mint(USER_ADDRESS, INITIAL_AMOUNT);
}

#[test]
#[should_panic(expected: "ONLY_TOKEN_ADMIN")]
fn test_non_token_admin_cannot_burn() {
    let token_address = deploy_token();
    let mintable = IMintableTokenDispatcher { contract_address: token_address };

    cheat_caller_address_once(token_address, TOKEN_ADMIN);
    mintable.permissioned_mint(USER_ADDRESS, INITIAL_AMOUNT);
    mintable.permissioned_burn(USER_ADDRESS, INITIAL_AMOUNT);
}

#[test]
fn test_transfer() {
    let token_address = deploy_token();
    let erc20 = IERC20Dispatcher { contract_address: token_address };
    let mintable = IMintableTokenDispatcher { contract_address: token_address };

    cheat_caller_address_once(token_address, TOKEN_ADMIN);
    mintable.permissioned_mint(USER_ADDRESS, INITIAL_AMOUNT);

    let transfer_amount: u256 = 400;
    cheat_caller_address_once(token_address, USER_ADDRESS);
    erc20.transfer(RECIPIENT, transfer_amount);

    assert(erc20.balance_of(USER_ADDRESS) == INITIAL_AMOUNT - transfer_amount, 'SENDER_BAL');
    assert(erc20.balance_of(RECIPIENT) == transfer_amount, 'RECIPIENT_BAL');
    assert(erc20.total_supply() == INITIAL_AMOUNT, 'SUPPLY_CHANGED');
}

#[test]
fn test_approve_and_transfer_from() {
    let token_address = deploy_token();
    let erc20 = IERC20Dispatcher { contract_address: token_address };
    let mintable = IMintableTokenDispatcher { contract_address: token_address };

    cheat_caller_address_once(token_address, TOKEN_ADMIN);
    mintable.permissioned_mint(USER_ADDRESS, INITIAL_AMOUNT);

    let approve_amount: u256 = 600;
    let transfer_amount: u256 = 400;
    cheat_caller_address_once(token_address, USER_ADDRESS);
    erc20.approve(NON_ADMIN, approve_amount);

    cheat_caller_address_once(token_address, NON_ADMIN);
    erc20.transfer_from(USER_ADDRESS, RECIPIENT, transfer_amount);

    assert(erc20.balance_of(USER_ADDRESS) == INITIAL_AMOUNT - transfer_amount, 'SENDER_BAL');
    assert(erc20.balance_of(RECIPIENT) == transfer_amount, 'RECIPIENT_BAL');
    assert(
        erc20.allowance(USER_ADDRESS, NON_ADMIN) == approve_amount - transfer_amount, 'ALLOWANCE',
    );
}

#[test]
fn test_partial_burn() {
    let token_address = deploy_token();
    let erc20 = IERC20Dispatcher { contract_address: token_address };
    let mintable = IMintableTokenDispatcher { contract_address: token_address };

    cheat_caller_address_once(token_address, TOKEN_ADMIN);
    mintable.permissioned_mint(USER_ADDRESS, INITIAL_AMOUNT);

    let burn_amount: u256 = 300;
    cheat_caller_address_once(token_address, TOKEN_ADMIN);
    mintable.permissioned_burn(USER_ADDRESS, burn_amount);

    assert(erc20.balance_of(USER_ADDRESS) == INITIAL_AMOUNT - burn_amount, 'PARTIAL_BAL');
    assert(erc20.total_supply() == INITIAL_AMOUNT - burn_amount, 'PARTIAL_SUPPLY');
}

#[test]
fn test_mint_to_multiple_accounts() {
    let token_address = deploy_token();
    let erc20 = IERC20Dispatcher { contract_address: token_address };
    let mintable = IMintableTokenDispatcher { contract_address: token_address };

    let amount_a: u256 = 500;
    let amount_b: u256 = 700;

    cheat_caller_address_once(token_address, TOKEN_ADMIN);
    mintable.permissioned_mint(USER_ADDRESS, amount_a);
    cheat_caller_address_once(token_address, TOKEN_ADMIN);
    mintable.permissioned_mint(RECIPIENT, amount_b);

    assert(erc20.balance_of(USER_ADDRESS) == amount_a, 'BALANCE_A');
    assert(erc20.balance_of(RECIPIENT) == amount_b, 'BALANCE_B');
    assert(erc20.total_supply() == amount_a + amount_b, 'TOTAL_SUPPLY');
}

#[test]
#[should_panic(expected: 'ERC20: insufficient balance')]
fn test_transfer_insufficient_balance_panics() {
    let token_address = deploy_token();
    let erc20 = IERC20Dispatcher { contract_address: token_address };
    let mintable = IMintableTokenDispatcher { contract_address: token_address };

    cheat_caller_address_once(token_address, TOKEN_ADMIN);
    mintable.permissioned_mint(USER_ADDRESS, INITIAL_AMOUNT);

    cheat_caller_address_once(token_address, USER_ADDRESS);
    erc20.transfer(RECIPIENT, INITIAL_AMOUNT + 1);
}

#[test]
#[should_panic(expected: 'ERC20: insufficient allowance')]
fn test_transfer_from_insufficient_allowance_panics() {
    let token_address = deploy_token();
    let erc20 = IERC20Dispatcher { contract_address: token_address };
    let mintable = IMintableTokenDispatcher { contract_address: token_address };

    cheat_caller_address_once(token_address, TOKEN_ADMIN);
    mintable.permissioned_mint(USER_ADDRESS, INITIAL_AMOUNT);

    cheat_caller_address_once(token_address, NON_ADMIN);
    erc20.transfer_from(USER_ADDRESS, RECIPIENT, 1);
}
