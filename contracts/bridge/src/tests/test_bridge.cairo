use core::num::traits::Zero;
use snforge_std::{EventSpyAssertionsTrait, spy_events};
use starknet::ContractAddress;
use starkware_utils::interfaces::mintable_token::{
    IMintableTokenDispatcher, IMintableTokenDispatcherTrait,
};
use starkware_utils_testing::test_utils::cheat_caller_address_once;
use strkbtc_bridge::bridge::bridge::Event as BridgeEvent;
use strkbtc_bridge::events::{
    DepositMinted, DepositQuorumSet, DepositWitnessed, MinWithdrawAmountSet, SignerRegistered,
    SignerRemoved, UserRegistered, UserRemoved, WithdrawRequested,
};
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
                    BridgeEvent::DepositMinted(
                        DepositMinted {
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
#[should_panic(expected: 'MIN_WITHDRAW_AMOUNT_NOT_CHANGED')]
fn test_set_min_withdraw_amount_same_value_panics() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    let current_min = bridge.get_min_withdraw_amount();
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.set_min_withdraw_amount(current_min);
}

#[test]
fn test_set_min_withdraw_amount_emits_event() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    let mut spy = spy_events();
    let new_min: u256 = 50_000_000;
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.set_min_withdraw_amount(new_min);

    spy
        .assert_emitted(
            @array![
                (
                    bridge_address,
                    BridgeEvent::MinWithdrawAmountSet(
                        MinWithdrawAmountSet {
                            old_min_withdraw_amount: 10_000_000, new_min_withdraw_amount: new_min,
                        },
                    ),
                ),
            ],
        );
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
#[should_panic(expected: 'QUORUM_NOT_CHANGED')]
fn test_set_quorum_same_value_panics() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.set_quorum(2);
}

#[test]
fn test_set_quorum_emits_event() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    let mut spy = spy_events();
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.set_quorum(5);

    spy
        .assert_emitted(
            @array![
                (
                    bridge_address,
                    BridgeEvent::DepositQuorumSet(
                        DepositQuorumSet { old_deposit_quorum: 2, new_deposit_quorum: 5 },
                    ),
                ),
            ],
        );
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
fn test_increase_quorum_after_minted_deposit_does_not_affect_it() {
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

    // Deposit minted at quorum=2.
    cheat_caller_address_once(bridge_address, SIGNER_ONE);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);
    cheat_caller_address_once(bridge_address, SIGNER_TWO);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);
    assert(token_view.balance_of(USER_ADDRESS) == DEPOSIT_AMOUNT, 'MINT_MISSING');

    // Raise quorum to 3 — minted deposit should not be affected.
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.set_quorum(3);

    // Signer 3 witnesses the same deposit — should not mint again.
    cheat_caller_address_once(bridge_address, SIGNER_THREE);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);
    assert(token_view.balance_of(USER_ADDRESS) == DEPOSIT_AMOUNT, 'DOUBLE_MINT');
}

#[test]
fn test_revoke_signer_removes_and_blacklists() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_ONE, btc_public_key_1());
    assert(bridge.is_signer(SIGNER_ONE), 'REGISTER_FAIL');

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.revoke_signer(SIGNER_ONE);
    assert(!bridge.is_signer(SIGNER_ONE), 'REVOKE_DID_NOT_REMOVE');
}

#[test]
#[should_panic(expected: 'SIGNER_NOT_REGISTERED')]
fn test_revoke_signer_not_registered_panics() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.revoke_signer(SIGNER_ONE);
}

#[test]
#[should_panic(expected: "ONLY_APP_GOVERNOR")]
fn test_revoke_signer_non_governor_panics() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_ONE, btc_public_key_1());

    cheat_caller_address_once(bridge_address, NON_SIGNER);
    bridge.revoke_signer(SIGNER_ONE);
}

#[test]
#[should_panic(expected: 'SIGNER_BLACKLISTED')]
fn test_register_revoked_signer_panics() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_ONE, btc_public_key_1());

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.revoke_signer(SIGNER_ONE);

    // Attempt to re-register the revoked signer with a different pubkey.
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_ONE, btc_public_key_2());
}

#[test]
fn test_reregister_signer_with_new_pubkey_frees_old_pubkey() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_ONE, btc_public_key_1());

    // Re-register signer one with a new pubkey — old pubkey should be freed.
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_ONE, btc_public_key_2());

    // Another signer can now use the freed pubkey.
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_TWO, btc_public_key_1());
    assert(bridge.is_signer(SIGNER_TWO), 'FREED_KEY_NOT_REUSABLE');
}

#[test]
fn test_revoked_signer_witness_excluded_from_quorum() {
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

    // Signer one witnesses.
    cheat_caller_address_once(bridge_address, SIGNER_ONE);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);

    // Revoke signer one — their witness should no longer count.
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.revoke_signer(SIGNER_ONE);

    // Signer two witnesses — only 1 valid witness (signer two), not enough for quorum=2.
    cheat_caller_address_once(bridge_address, SIGNER_TWO);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);
    assert(token_view.balance_of(USER_ADDRESS) == 0, 'REVOKED_WITNESS_COUNTED');

    // Signer three witnesses — 2 valid witnesses, should mint.
    cheat_caller_address_once(bridge_address, SIGNER_THREE);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);
    assert(token_view.balance_of(USER_ADDRESS) == DEPOSIT_AMOUNT, 'MINT_MISSING');
}

#[test]
#[should_panic(expected: 'ONLY_SIGNER')]
fn test_revoked_signer_cannot_witness() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_ONE, btc_public_key_1());

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.revoke_signer(SIGNER_ONE);

    cheat_caller_address_once(bridge_address, SIGNER_ONE);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);
}

#[test]
fn test_revoked_signer_witness_not_counted_for_quorum() {
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

    // Signer 1 witnesses.
    cheat_caller_address_once(bridge_address, SIGNER_ONE);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);
    assert(token_view.balance_of(USER_ADDRESS) == 0, 'MINTED_TOO_EARLY');

    // Revoke signer 1 — their witness should no longer count.
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.revoke_signer(SIGNER_ONE);

    // Signer 2 witnesses — only 1 valid witness now (signer 2), not enough for quorum=2.
    cheat_caller_address_once(bridge_address, SIGNER_TWO);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);
    assert(token_view.balance_of(USER_ADDRESS) == 0, 'MINTED_WITH_REVOKED_WITNESS');

    // Signer 3 witnesses — now 2 valid witnesses (signer 2 + signer 3), meets quorum.
    cheat_caller_address_once(bridge_address, SIGNER_THREE);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);
    assert(token_view.balance_of(USER_ADDRESS) == DEPOSIT_AMOUNT, 'MINT_MISSING');
}

#[test]
fn test_register_signer_allows_updating_public_key() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_ONE, btc_public_key_1());
    assert(bridge.is_signer(SIGNER_ONE), 'REGISTER_FAIL');

    // Re-register signer 1 with a different public key — should not panic.
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_ONE, btc_public_key_2());
    assert(bridge.is_signer(SIGNER_ONE), 'REREGISTER_FAIL');
}

#[test]
fn test_set_min_withdraw_amount_zero_allowed() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.set_min_withdraw_amount(0);
    assert(bridge.get_min_withdraw_amount() == 0, 'ZERO_NOT_ALLOWED');
}

#[test]
fn test_deposit_witnessed_event_emitted_per_witness() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_ONE, btc_public_key_1());

    let mut spy = spy_events();
    cheat_caller_address_once(bridge_address, SIGNER_ONE);
    bridge.witness_deposit(btc_txid(), VOUT, DEPOSIT_AMOUNT, USER_ADDRESS);

    spy
        .assert_emitted(
            @array![
                (
                    bridge_address,
                    BridgeEvent::DepositWitnessed(
                        DepositWitnessed {
                            btc_txid: btc_txid(),
                            vout: VOUT,
                            amount: DEPOSIT_AMOUNT,
                            destination_address: USER_ADDRESS,
                            signer: SIGNER_ONE,
                        },
                    ),
                ),
            ],
        );
}

#[test]
fn test_signer_registered_event_emitted() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    let mut spy = spy_events();
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_ONE, btc_public_key_1());

    spy
        .assert_emitted(
            @array![
                (
                    bridge_address,
                    BridgeEvent::SignerRegistered(
                        SignerRegistered { signer: SIGNER_ONE, btc_public_key: btc_public_key_1() },
                    ),
                ),
            ],
        );
}

#[test]
fn test_user_registered_event_emitted() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    let mut spy = spy_events();
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_user(USER_ADDRESS);

    spy
        .assert_emitted(
            @array![
                (
                    bridge_address,
                    BridgeEvent::UserRegistered(UserRegistered { user: USER_ADDRESS }),
                ),
            ],
        );
}

#[test]
fn test_user_removed_event_emitted() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_user(USER_ADDRESS);

    let mut spy = spy_events();
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.remove_user(USER_ADDRESS);

    spy
        .assert_emitted(
            @array![(bridge_address, BridgeEvent::UserRemoved(UserRemoved { user: USER_ADDRESS }))],
        );
}

#[test]
fn test_signer_removed_event_emitted() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_ONE, btc_public_key_1());

    let mut spy = spy_events();
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.remove_signer(SIGNER_ONE);

    spy
        .assert_emitted(
            @array![
                (
                    bridge_address,
                    BridgeEvent::SignerRemoved(
                        SignerRemoved {
                            signer: SIGNER_ONE, btc_public_key: btc_public_key_1(), revoked: false,
                        },
                    ),
                ),
            ],
        );
}

#[test]
fn test_signer_revoked_event_emitted() {
    let token = deploy_mock_token();
    let registry = deploy_mock_registry();
    let bridge_address = deploy_bridge(token, registry, 2);
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.register_signer(SIGNER_ONE, btc_public_key_1());

    let mut spy = spy_events();
    cheat_caller_address_once(bridge_address, APP_GOVERNOR);
    bridge.revoke_signer(SIGNER_ONE);

    spy
        .assert_emitted(
            @array![
                (
                    bridge_address,
                    BridgeEvent::SignerRemoved(
                        SignerRemoved {
                            signer: SIGNER_ONE, btc_public_key: btc_public_key_1(), revoked: true,
                        },
                    ),
                ),
            ],
        );
}
