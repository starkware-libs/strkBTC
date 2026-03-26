use core::serde::Serde;
use snforge_std::{EventSpyAssertionsTrait, spy_events};
use starkware_utils_testing::test_utils::cheat_caller_address_once;
use strkbtc_registry::events::{SignerSignatures, WithdrawSigned};
use strkbtc_registry::interface::{IRegistryDispatcher, IRegistryDispatcherTrait};
use strkbtc_registry::registry::registry::Event as RegistryEvent;
use strkbtc_registry::tests::test_utils::{
    APP_GOVERNOR, NON_SIGNER, SIGNER_ONE, SIGNER_THREE, SIGNER_TWO, compute_withdraw_id,
    deploy_registry, pubkey_one, pubkey_two, raw_tx_a, raw_tx_b, raw_tx_c,
};
#[test]
fn test_has_signed_withdraw_flow() {
    let registry_address = deploy_registry();
    let registry = IRegistryDispatcher { contract_address: registry_address };

    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.register_signer(SIGNER_ONE, pubkey_one());

    assert(!registry.has_signed_withdraw(raw_tx_a(), pubkey_one()), 'SIGNED_TOO_EARLY');

    let signatures = array!["3044aa", "3044bb"];
    cheat_caller_address_once(registry_address, SIGNER_ONE);
    registry.sign_withdraw(raw_tx_a(), signatures.span());

    assert(registry.has_signed_withdraw(raw_tx_a(), pubkey_one()), 'SIGNED_MISSING');
}

#[test]
#[should_panic(expected: 'ONLY_SIGNER')]
fn test_non_signer_cannot_sign_withdraw() {
    let registry_address = deploy_registry();
    let registry = IRegistryDispatcher { contract_address: registry_address };

    let signatures = array!["3044aa"];
    cheat_caller_address_once(registry_address, NON_SIGNER);
    registry.sign_withdraw("deadbeef", signatures.span());
}

#[test]
fn test_resubmission_overwrites_previous_signatures() {
    let registry_address = deploy_registry();
    let registry = IRegistryDispatcher { contract_address: registry_address };

    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.register_signer(SIGNER_ONE, pubkey_one());

    let first_signatures = array!["sig_a", "sig_b"];
    cheat_caller_address_once(registry_address, SIGNER_ONE);
    registry.sign_withdraw(raw_tx_b(), first_signatures.span());

    let second_signatures = array!["sig_overwrite"];
    let mut spy = spy_events();
    cheat_caller_address_once(registry_address, SIGNER_ONE);
    registry.sign_withdraw(raw_tx_b(), second_signatures.span());

    let tx = raw_tx_b();
    let withdraw_id = compute_withdraw_id(@tx);
    spy
        .assert_emitted(
            @array![
                (
                    registry_address,
                    RegistryEvent::WithdrawSigned(
                        WithdrawSigned {
                            withdraw_id,
                            raw_tx: raw_tx_b(),
                            signatures: array![
                                SignerSignatures {
                                    btc_pubkey: pubkey_one(), signatures: array!["sig_overwrite"],
                                },
                            ],
                        },
                    ),
                ),
            ],
        );
}

#[test]
fn test_event_contains_aggregate_signatures_for_all_signers() {
    let registry_address = deploy_registry();
    let registry = IRegistryDispatcher { contract_address: registry_address };

    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.register_signer(SIGNER_ONE, pubkey_one());
    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.register_signer(SIGNER_TWO, pubkey_two());

    let signer_one_sigs = array!["s1_i0", "s1_i1"];
    cheat_caller_address_once(registry_address, SIGNER_ONE);
    registry.sign_withdraw(raw_tx_c(), signer_one_sigs.span());

    let signer_two_sigs = array!["s2_i0", "s2_i1"];
    let mut spy = spy_events();
    cheat_caller_address_once(registry_address, SIGNER_TWO);
    registry.sign_withdraw(raw_tx_c(), signer_two_sigs.span());

    let tx = raw_tx_c();
    let withdraw_id = compute_withdraw_id(@tx);
    spy
        .assert_emitted(
            @array![
                (
                    registry_address,
                    RegistryEvent::WithdrawSigned(
                        WithdrawSigned {
                            withdraw_id,
                            raw_tx: raw_tx_c(),
                            signatures: array![
                                SignerSignatures {
                                    btc_pubkey: pubkey_one(), signatures: array!["s1_i0", "s1_i1"],
                                },
                                SignerSignatures {
                                    btc_pubkey: pubkey_two(), signatures: array!["s2_i0", "s2_i1"],
                                },
                            ],
                        },
                    ),
                ),
            ],
        );
}

#[test]
fn register_and_remove_signer() {
    let registry_address = deploy_registry();
    let registry = IRegistryDispatcher { contract_address: registry_address };

    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.register_signer(SIGNER_ONE, pubkey_one());
    assert(registry.is_signer(SIGNER_ONE), 'SIGNER_NOT_REGISTERED');
    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.remove_signer(SIGNER_ONE);
    assert(!registry.is_signer(SIGNER_ONE), 'SIGNER_NOT_REMOVED');
}

#[test]
#[should_panic(expected: 'EMPTY_RAW_TX')]
fn test_sign_withdraw_empty_raw_tx_panics() {
    let registry_address = deploy_registry();
    let registry = IRegistryDispatcher { contract_address: registry_address };

    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.register_signer(SIGNER_ONE, pubkey_one());

    let signatures = array!["3044aa"];
    cheat_caller_address_once(registry_address, SIGNER_ONE);
    registry.sign_withdraw("", signatures.span());
}

#[test]
#[should_panic(expected: 'EMPTY_SIGS')]
fn test_sign_withdraw_empty_signatures_panics() {
    let registry_address = deploy_registry();
    let registry = IRegistryDispatcher { contract_address: registry_address };

    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.register_signer(SIGNER_ONE, pubkey_one());

    let signatures: Array<ByteArray> = array![];
    cheat_caller_address_once(registry_address, SIGNER_ONE);
    registry.sign_withdraw(raw_tx_a(), signatures.span());
}

#[test]
#[should_panic(expected: "ONLY_APP_GOVERNOR")]
fn test_register_signer_non_governor_panics() {
    let registry_address = deploy_registry();
    let registry = IRegistryDispatcher { contract_address: registry_address };

    cheat_caller_address_once(registry_address, NON_SIGNER);
    registry.register_signer(SIGNER_ONE, pubkey_one());
}

#[test]
#[should_panic(expected: "ONLY_APP_GOVERNOR")]
fn test_remove_signer_non_governor_panics() {
    let registry_address = deploy_registry();
    let registry = IRegistryDispatcher { contract_address: registry_address };

    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.register_signer(SIGNER_ONE, pubkey_one());

    cheat_caller_address_once(registry_address, NON_SIGNER);
    registry.remove_signer(SIGNER_ONE);
}

#[test]
fn test_has_signed_withdraw_false_for_different_signer() {
    let registry_address = deploy_registry();
    let registry = IRegistryDispatcher { contract_address: registry_address };

    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.register_signer(SIGNER_ONE, pubkey_one());
    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.register_signer(SIGNER_TWO, pubkey_two());

    let signatures = array!["3044aa"];
    cheat_caller_address_once(registry_address, SIGNER_ONE);
    registry.sign_withdraw(raw_tx_a(), signatures.span());

    assert(!registry.has_signed_withdraw(raw_tx_a(), pubkey_two()), 'OTHER_SIGNER_SIGNED');
}

#[test]
fn test_has_signed_withdraw_false_for_different_tx() {
    let registry_address = deploy_registry();
    let registry = IRegistryDispatcher { contract_address: registry_address };

    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.register_signer(SIGNER_ONE, pubkey_one());

    let signatures = array!["3044aa"];
    cheat_caller_address_once(registry_address, SIGNER_ONE);
    registry.sign_withdraw(raw_tx_a(), signatures.span());

    assert(!registry.has_signed_withdraw(raw_tx_b(), pubkey_one()), 'WRONG_TX_SIGNED');
}

#[test]
#[should_panic(expected: 'ONLY_SIGNER')]
fn test_removed_signer_cannot_sign() {
    let registry_address = deploy_registry();
    let registry = IRegistryDispatcher { contract_address: registry_address };

    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.register_signer(SIGNER_ONE, pubkey_one());
    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.remove_signer(SIGNER_ONE);

    let signatures = array!["3044aa"];
    cheat_caller_address_once(registry_address, SIGNER_ONE);
    registry.sign_withdraw(raw_tx_a(), signatures.span());
}

#[test]
fn test_is_signer_false_for_unknown_address() {
    let registry_address = deploy_registry();
    let registry = IRegistryDispatcher { contract_address: registry_address };

    assert(!registry.is_signer(NON_SIGNER), 'UNKNOWN_IS_SIGNER');
}

#[test]
fn test_revoke_signer_excludes_from_aggregation() {
    let registry_address = deploy_registry();
    let registry = IRegistryDispatcher { contract_address: registry_address };

    // Register two signers and have both sign the same tx.
    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.register_signer(SIGNER_ONE, pubkey_one());
    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.register_signer(SIGNER_TWO, pubkey_two());

    let signer_one_sigs = array!["s1_sig"];
    cheat_caller_address_once(registry_address, SIGNER_ONE);
    registry.sign_withdraw(raw_tx_a(), signer_one_sigs.span());

    let signer_two_sigs = array!["s2_sig"];
    cheat_caller_address_once(registry_address, SIGNER_TWO);
    registry.sign_withdraw(raw_tx_a(), signer_two_sigs.span());

    // Revoke signer one.
    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.revoke_signer(SIGNER_ONE);

    // Have signer two re-sign so we get a fresh event with updated aggregation.
    let mut spy = spy_events();
    cheat_caller_address_once(registry_address, SIGNER_TWO);
    registry.sign_withdraw(raw_tx_a(), signer_two_sigs.span());

    let tx = raw_tx_a();
    let withdraw_id = compute_withdraw_id(@tx);
    spy
        .assert_emitted(
            @array![
                (
                    registry_address,
                    RegistryEvent::WithdrawSigned(
                        WithdrawSigned {
                            withdraw_id,
                            raw_tx: raw_tx_a(),
                            signatures: array![
                                SignerSignatures {
                                    btc_pubkey: pubkey_two(), signatures: array!["s2_sig"],
                                },
                            ],
                        },
                    ),
                ),
            ],
        );
}

#[test]
#[should_panic(expected: "ONLY_APP_GOVERNOR")]
fn test_revoke_signer_non_governor_panics() {
    let registry_address = deploy_registry();
    let registry = IRegistryDispatcher { contract_address: registry_address };

    cheat_caller_address_once(registry_address, NON_SIGNER);
    registry.revoke_signer(SIGNER_ONE);
}

#[test]
fn test_revoke_signer_has_signed_still_true() {
    let registry_address = deploy_registry();
    let registry = IRegistryDispatcher { contract_address: registry_address };

    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.register_signer(SIGNER_ONE, pubkey_one());

    let signatures = array!["3044aa"];
    cheat_caller_address_once(registry_address, SIGNER_ONE);
    registry.sign_withdraw(raw_tx_a(), signatures.span());

    // Revoke the signer — has_signed should still return true (it's a historical fact).
    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.revoke_signer(SIGNER_ONE);

    assert(registry.has_signed_withdraw(raw_tx_a(), pubkey_one()), 'REVOKE_ERASED_HISTORY');
}

#[test]
fn test_revoke_signer_removes_signer() {
    let registry_address = deploy_registry();
    let registry = IRegistryDispatcher { contract_address: registry_address };

    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.register_signer(SIGNER_ONE, pubkey_one());
    assert(registry.is_signer(SIGNER_ONE), 'SIGNER_NOT_REGISTERED');

    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.revoke_signer(SIGNER_ONE);

    assert(!registry.is_signer(SIGNER_ONE), 'SIGNER_NOT_REMOVED');
}

#[test]
#[should_panic(expected: 'ONLY_SIGNER')]
fn test_revoked_signer_cannot_sign() {
    let registry_address = deploy_registry();
    let registry = IRegistryDispatcher { contract_address: registry_address };

    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.register_signer(SIGNER_ONE, pubkey_one());

    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.revoke_signer(SIGNER_ONE);

    // Revoked signer is also removed, so sign_withdraw should panic.
    let signatures = array!["sig_after_revoke"];
    cheat_caller_address_once(registry_address, SIGNER_ONE);
    registry.sign_withdraw(raw_tx_a(), signatures.span());
}

#[test]
#[should_panic(expected: 'PUBLIC_KEY_BLACKLISTED')]
fn test_register_signer_with_blacklisted_pubkey_panics() {
    let registry_address = deploy_registry();
    let registry = IRegistryDispatcher { contract_address: registry_address };

    // Register and then revoke signer one — this blacklists pubkey_one.
    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.register_signer(SIGNER_ONE, pubkey_one());
    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.revoke_signer(SIGNER_ONE);

    // Attempt to register a different signer with the same blacklisted pubkey.
    cheat_caller_address_once(registry_address, APP_GOVERNOR);
    registry.register_signer(SIGNER_THREE, pubkey_one());
}
