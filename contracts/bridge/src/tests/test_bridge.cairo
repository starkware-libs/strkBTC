use core::num::traits::Zero;
use snforge_std::{EventSpyAssertionsTrait, spy_events};
use starknet::ContractAddress;
use starkware_utils::interfaces::mintable_token::{
    IMintableTokenDispatcher, IMintableTokenDispatcherTrait,
};
use starkware_utils_testing::test_utils::cheat_caller_address_once;
use strkbtc_bridge::bridge::bridge::Event as BridgeEvent;
use strkbtc_bridge::events::{DepositConfirmed, WithdrawRequested};
use strkbtc_bridge::interface::{IBridgeDispatcher, IBridgeDispatcherTrait};
use strkbtc_bridge::tests::mintable_token_mock::{
    IMintableTokenMockDispatcher, IMintableTokenMockDispatcherTrait,
};
use strkbtc_bridge::tests::test_utils::{
    APP_GOVERNOR, DEPOSIT_AMOUNT, NON_SIGNER, SIGNER_ONE, SIGNER_THREE, SIGNER_TWO, USER_ADDRESS,
    VOUT, WITHDRAW_AMOUNT, btc_public_key_1, btc_public_key_2, btc_public_key_3, btc_txid,
    deploy_bridge, deploy_mock_registry, deploy_mock_token,
};

#[test]
fn test_is_witnessed_flow() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_ONE, btc_public_key_1());

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_TWO, btc_public_key_2());
    assert(
        !bridge.is_witnessed(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS, SIGNER_ONE),
        'WITNESS_FALSE',
    );

    cheat_caller_address_once(bridge_address, SIGNER_ONE);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);

    assert(
        bridge.is_witnessed(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS, SIGNER_ONE),
        'WITNESS_MISS',
    );

    assert(
        !bridge.is_witnessed(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS, SIGNER_TWO),
        'WITNESS_OTHER',
    );
}

#[test]
#[should_panic(expected: 'ONLY_SIGNER')]
fn test_non_signer_cannot_witness() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, NON_SIGNER);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);
}

#[test]
fn test_duplicate_witness_is_ignored() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };
    let token_view = IMintableTokenMockDispatcher { contract_address: token };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_ONE, btc_public_key_1());

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_TWO, btc_public_key_2());

    cheat_caller_address_once(bridge_address, SIGNER_ONE);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);

    cheat_caller_address_once(bridge_address, SIGNER_ONE);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);

    assert(token_view.balance_of(USER_ADDRESS) == 0, 'DUP_COUNTED');

    cheat_caller_address_once(bridge_address, SIGNER_TWO);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);

    assert(token_view.balance_of(USER_ADDRESS) == DEPOSIT_AMOUNT, 'MINT_THRESH');
}

#[test]
fn test_mints_once_on_threshold() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };
    let token_view = IMintableTokenMockDispatcher { contract_address: token };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_ONE, btc_public_key_1());

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_TWO, btc_public_key_2());

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_THREE, btc_public_key_3());

    cheat_caller_address_once(bridge_address, SIGNER_ONE);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);
    assert(token_view.balance_of(USER_ADDRESS) == 0, 'MINTED_TOO_EARLY');

    cheat_caller_address_once(bridge_address, SIGNER_TWO);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);
    assert(token_view.balance_of(USER_ADDRESS) == DEPOSIT_AMOUNT, 'MINT_MISSING');

    cheat_caller_address_once(bridge_address, SIGNER_THREE);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);
    assert(token_view.balance_of(USER_ADDRESS) == DEPOSIT_AMOUNT, 'MINTED_TWICE');
}

#[test]
fn test_request_withdraw_burns_caller_balance_and_emits_event() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };
    let token_mintable = IMintableTokenDispatcher { contract_address: token };
    let token_view = IMintableTokenMockDispatcher { contract_address: token };

    token_mintable.permissioned_mint(USER_ADDRESS, DEPOSIT_AMOUNT);
    assert(token_view.balance_of(USER_ADDRESS) == DEPOSIT_AMOUNT, 'PREMINT_FAIL');

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_user(USER_ADDRESS);

    let mut spy = spy_events();
    cheat_caller_address_once(bridge_address, USER_ADDRESS);
    bridge.request_withdraw(WITHDRAW_AMOUNT, "0014deadbeef");

    spy
        .assert_emitted(
            @array![
                (
                    bridge_address,
                    BridgeEvent::WithdrawRequested(
                        WithdrawRequested {
                            caller: USER_ADDRESS,
                            amount: WITHDRAW_AMOUNT,
                            btc_destination: "0014deadbeef",
                        },
                    ),
                ),
            ],
        );

    assert(token_view.balance_of(USER_ADDRESS) == DEPOSIT_AMOUNT - WITHDRAW_AMOUNT, 'BURN_FAILED');
}

#[test]
#[should_panic(expected: 'ONLY_USER')]
fn test_non_user_cannot_request_withdraw() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };
    let token_mintable = IMintableTokenDispatcher { contract_address: token };
    let token_view = IMintableTokenMockDispatcher { contract_address: token };

    token_mintable.permissioned_mint(USER_ADDRESS, DEPOSIT_AMOUNT);
    assert(token_view.balance_of(USER_ADDRESS) == DEPOSIT_AMOUNT, 'PREMINT_FAIL');

    cheat_caller_address_once(bridge_address, USER_ADDRESS);
    bridge.request_withdraw(WITHDRAW_AMOUNT, "0014deadbeef");
}

#[test]
fn test_register_user_and_remove_user() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_user(USER_ADDRESS);
    assert(bridge.is_user(USER_ADDRESS), 'REGISTER_FAIL');

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.remove_user(USER_ADDRESS);
    assert(!bridge.is_user(USER_ADDRESS), 'REMOVE_FAIL');
}

#[test]
fn test_register_signer_and_remove_signer() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_ONE, btc_public_key_1());
    assert(bridge.is_signer(SIGNER_ONE), 'REGISTER_FAIL');

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.remove_signer(SIGNER_ONE);
    assert(!bridge.is_signer(SIGNER_ONE), 'REMOVE_FAIL');
}

#[test]
#[should_panic(expected: 'DUP_PUBLIC_KEY')]
fn test_register_signer_rejects_duplicate_pubkeys() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_ONE, btc_public_key_1());
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_TWO, btc_public_key_1());
}

#[test]
fn test_deposit_witnessed_event_emitted_on_quorum() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_ONE, btc_public_key_1());
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_TWO, btc_public_key_2());

    cheat_caller_address_once(bridge_address, SIGNER_ONE);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);

    let mut spy = spy_events();
    cheat_caller_address_once(bridge_address, SIGNER_TWO);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);

    spy
        .assert_emitted(
            @array![
                (
                    bridge_address,
                    BridgeEvent::DepositConfirmed(
                        DepositConfirmed {
                            btc_txid: btc_txid(),
                            vout: VOUT,
                            amount: DEPOSIT_AMOUNT,
                            destination_address: USER_ADDRESS,
                        },
                    ),
                ),
            ],
        );
}

#[test]
fn test_get_min_withdraw_amount_returns_default() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    assert(bridge.get_min_withdraw_amount() == 10_000_000, 'BAD_DEFAULT_MIN');
}

#[test]
fn test_set_min_withdraw_amount_updates_value() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    let new_min: u256 = 50_000_000;
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.set_min_withdraw_amount(new_min);

    assert(bridge.get_min_withdraw_amount() == new_min, 'MIN_NOT_UPDATED');
}

#[test]
#[should_panic(expected: 'ZERO_MIN_WITHDRAW_AMOUNT')]
fn test_set_min_withdraw_amount_zero_panics() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.set_min_withdraw_amount(0);
}

#[test]
#[should_panic(expected: "ONLY_APP_GOVERNOR")]
fn test_set_min_withdraw_amount_non_governor_panics() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, NON_SIGNER);
    bridge.set_min_withdraw_amount(50_000_000);
}

#[test]
#[should_panic(expected: 'INVALID_WITHDRAW_AMOUNT')]
fn test_request_withdraw_below_min_amount_panics() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };
    let token_mintable = IMintableTokenDispatcher { contract_address: token };

    token_mintable.permissioned_mint(USER_ADDRESS, DEPOSIT_AMOUNT);

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_user(USER_ADDRESS);

    cheat_caller_address_once(bridge_address, USER_ADDRESS);
    bridge.request_withdraw(1_000, "0014deadbeef");
}

#[test]
#[should_panic(expected: 'ZERO_BTC_DESTINATION')]
fn test_request_withdraw_zero_btc_destination_panics() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };
    let token_mintable = IMintableTokenDispatcher { contract_address: token };

    token_mintable.permissioned_mint(USER_ADDRESS, DEPOSIT_AMOUNT);

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_user(USER_ADDRESS);

    cheat_caller_address_once(bridge_address, USER_ADDRESS);
    bridge.request_withdraw(WITHDRAW_AMOUNT, "");
}

#[test]
#[should_panic(expected: 'INVALID_WITHDRAW_AMOUNT')]
fn test_request_withdraw_respects_updated_min_amount() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };
    let token_mintable = IMintableTokenDispatcher { contract_address: token };

    token_mintable.permissioned_mint(USER_ADDRESS, DEPOSIT_AMOUNT);

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_user(USER_ADDRESS);

    let raised_min: u256 = 200_000_000;
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.set_min_withdraw_amount(raised_min);

    cheat_caller_address_once(bridge_address, USER_ADDRESS);
    bridge.request_withdraw(WITHDRAW_AMOUNT, "0014deadbeef");
}

#[test]
#[should_panic(expected: 'ZERO_USER')]
fn test_register_user_zero_address_panics() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_user(Zero::<ContractAddress>::zero());
}

#[test]
#[should_panic(expected: 'USER_NOT_REGISTERED')]
fn test_remove_user_not_registered_panics() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.remove_user(USER_ADDRESS);
}

#[test]
fn test_get_quorum_returns_initial_value() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    assert(bridge.get_quorum() == 2, 'BAD_INITIAL_QUORUM');
}

#[test]
fn test_set_quorum_updates_value() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.set_quorum(5);

    assert(bridge.get_quorum() == 5, 'QUORUM_NOT_UPDATED');
}

#[test]
#[should_panic(expected: 'INVALID_QUORUM')]
fn test_set_quorum_below_min_panics() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.set_quorum(1);
}

#[test]
#[should_panic(expected: "ONLY_APP_GOVERNOR")]
fn test_set_quorum_non_governor_panics() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, NON_SIGNER);
    bridge.set_quorum(3);
}

#[test]
fn test_increase_quorum_mid_deposit_requires_more_witnesses() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };
    let token_view = IMintableTokenMockDispatcher { contract_address: token };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_ONE, btc_public_key_1());
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_TWO, btc_public_key_2());
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_THREE, btc_public_key_3());

    // Signer 1 witnesses with quorum=2.
    cheat_caller_address_once(bridge_address, SIGNER_ONE);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);
    assert(token_view.balance_of(USER_ADDRESS) == 0, 'MINTED_BEFORE_QUORUM');

    // Increase quorum to 3.
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.set_quorum(3);

    // Signer 2 witnesses — would have been enough before, not anymore.
    cheat_caller_address_once(bridge_address, SIGNER_TWO);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);
    assert(token_view.balance_of(USER_ADDRESS) == 0, 'MINTED_BELOW_NEW_QUORUM');

    // Signer 3 meets the raised quorum — should mint.
    cheat_caller_address_once(bridge_address, SIGNER_THREE);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);
    assert(token_view.balance_of(USER_ADDRESS) == DEPOSIT_AMOUNT, 'MINT_MISSING');
}

#[test]
fn test_decrease_quorum_mid_deposit_mints_with_fewer_witnesses() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 3);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };
    let token_view = IMintableTokenMockDispatcher { contract_address: token };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_ONE, btc_public_key_1());
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_TWO, btc_public_key_2());

    // Signer 1 witnesses with quorum=3.
    cheat_caller_address_once(bridge_address, SIGNER_ONE);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);
    assert(token_view.balance_of(USER_ADDRESS) == 0, 'MINTED_BEFORE_QUORUM');

    // Decrease quorum to 2 — still only 1 witness, no mint yet.
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.set_quorum(2);
    assert(token_view.balance_of(USER_ADDRESS) == 0, 'MINTED_ON_QUORUM_CHANGE');

    // Signer 2 meets the lowered quorum — should mint.
    cheat_caller_address_once(bridge_address, SIGNER_TWO);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);
    assert(token_view.balance_of(USER_ADDRESS) == DEPOSIT_AMOUNT, 'MINT_MISSING');
}

#[test]
fn test_decrease_quorum_below_existing_witness_count_mints_on_next_witness() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 3);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };
    let token_view = IMintableTokenMockDispatcher { contract_address: token };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_ONE, btc_public_key_1());
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_TWO, btc_public_key_2());
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_THREE, btc_public_key_3());

    // 2 signers witness with quorum=3 — not enough.
    cheat_caller_address_once(bridge_address, SIGNER_ONE);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);
    cheat_caller_address_once(bridge_address, SIGNER_TWO);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);
    assert(token_view.balance_of(USER_ADDRESS) == 0, 'MINTED_BEFORE_QUORUM');

    // Decrease quorum to 2 — already have 2 witnesses, but no retroactive mint.
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.set_quorum(2);
    assert(token_view.balance_of(USER_ADDRESS) == 0, 'RETROACTIVE_MINT');

    // Signer 3 triggers the check — 3 >= 2, should mint.
    cheat_caller_address_once(bridge_address, SIGNER_THREE);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);
    assert(token_view.balance_of(USER_ADDRESS) == DEPOSIT_AMOUNT, 'MINT_MISSING');
}

#[test]
fn test_increase_quorum_after_confirmed_deposit_does_not_affect_it() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };
    let token_view = IMintableTokenMockDispatcher { contract_address: token };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_ONE, btc_public_key_1());
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_TWO, btc_public_key_2());
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_THREE, btc_public_key_3());

    // Deposit confirmed at quorum=2.
    cheat_caller_address_once(bridge_address, SIGNER_ONE);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);
    cheat_caller_address_once(bridge_address, SIGNER_TWO);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);
    assert(token_view.balance_of(USER_ADDRESS) == DEPOSIT_AMOUNT, 'MINT_MISSING');

    // Raise quorum to 3 — confirmed deposit should not be affected.
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.set_quorum(3);

    // Signer 3 witnesses the same deposit — should not mint again.
    cheat_caller_address_once(bridge_address, SIGNER_THREE);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);
    assert(token_view.balance_of(USER_ADDRESS) == DEPOSIT_AMOUNT, 'DOUBLE_MINT');
}
