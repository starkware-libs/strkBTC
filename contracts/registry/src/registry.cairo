#[starknet::contract]
pub mod registry {
    use core::clone::Clone;
    use core::num::traits::Zero;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::storage::{
        Map, Mutable, MutableVecTrait, StorageMapReadAccess, StorageMapWriteAccess, StoragePath,
        StoragePathEntry, StoragePathMutableConversion, StoragePointerReadAccess, Vec, VecTrait,
    };
    use starknet::{ContractAddress, get_caller_address};
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;
    use strkbtc_registry::errors::{EMPTY_RAW_TX, EMPTY_SIGS, ONLY_SIGNER, PUBLIC_KEY_BLACKLISTED};
    use strkbtc_registry::events::{SignerSignatures, WithdrawSigned};
    use strkbtc_registry::interface::IRegistry;
    use strkbtc_registry::utils::{ByteArrayZero, compute_hash, compute_withdraw_id, vec_to_array};

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);

    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    type WithdrawId = felt252;
    type BtcPublicKeyHash = felt252;

    #[starknet::storage_node]
    struct WithdrawSignaturesState {
        withdraw_id_to_signers: Map<WithdrawId, Vec<ByteArray>>,
        withdraw_id_to_signatures: Map<(WithdrawId, BtcPublicKeyHash), Vec<ByteArray>>,
    }

    #[storage]
    struct Storage {
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        roles: RolesComponent::Storage,
        #[substorage(v0)]
        replaceability: ReplaceabilityComponent::Storage,
        /// Registry state variables
        /// Maps signer address to their BTC public key
        signers_to_pubkey: Map<ContractAddress, ByteArray>,
        /// Maps BTC public key hash to a boolean indicating if it is blacklisted
        btc_public_key_blacklist: Map<BtcPublicKeyHash, bool>,
        /// Withdrawal signature state, grouped in a storage node.
        withdraw_signatures: WithdrawSignaturesState,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        RolesEvent: RolesComponent::Event,
        #[flat]
        ReplaceabilityEvent: ReplaceabilityComponent::Event,
        WithdrawSigned: WithdrawSigned,
    }

    #[constructor]
    fn constructor(ref self: ContractState, governance_admin: ContractAddress, upgrade_delay: u64) {
        self.roles.initialize(:governance_admin);
        self.replaceability.initialize(:upgrade_delay);
    }

    #[abi(embed_v0)]
    pub impl RegistryImpl of IRegistry<ContractState> {
        fn sign_withdraw(ref self: ContractState, raw_tx: ByteArray, signatures: Span<ByteArray>) {
            self.assert_signer();
            assert(raw_tx.is_non_zero(), EMPTY_RAW_TX);
            assert(signatures.len() > 0, EMPTY_SIGS);

            let btc_pubkey: ByteArray = self.signers_to_pubkey.read(get_caller_address());
            let withdraw_id: WithdrawId = compute_withdraw_id(@raw_tx);

            self.withdraw_signatures.write_signatures(:withdraw_id, :btc_pubkey, :signatures);

            let all_signatures = self
                .withdraw_signatures
                .as_non_mut()
                .aggregate_signatures(
                    :withdraw_id, btc_pubkey_blacklist: self.btc_public_key_blacklist.as_non_mut(),
                );
            self.emit(WithdrawSigned { withdraw_id, raw_tx, signatures: all_signatures });
        }

        fn has_signed_withdraw(
            self: @ContractState, raw_tx: ByteArray, btc_pubkey: ByteArray,
        ) -> bool {
            let withdraw_id: WithdrawId = compute_withdraw_id(@raw_tx);
            let btc_pubkey_hash: felt252 = compute_hash(@btc_pubkey);
            self.withdraw_signatures.has_signed(:withdraw_id, :btc_pubkey_hash)
        }

        fn register_signer(
            ref self: ContractState, signer: ContractAddress, btc_pubkey: ByteArray,
        ) {
            self.roles.only_app_governor();
            let btc_pubkey_hash: BtcPublicKeyHash = compute_hash(@btc_pubkey);
            assert(!self.btc_public_key_blacklist.read(btc_pubkey_hash), PUBLIC_KEY_BLACKLISTED);
            self.signers_to_pubkey.write(signer, btc_pubkey.clone());
        }

        fn remove_signer(ref self: ContractState, signer: ContractAddress) {
            self.roles.only_app_governor();
            self.signers_to_pubkey.write(signer, Default::default());
        }

        fn revoke_signer(ref self: ContractState, signer: ContractAddress) {
            self.roles.only_app_governor();
            let btc_pubkey: ByteArray = self.signers_to_pubkey.read(signer);
            let btc_pubkey_hash: BtcPublicKeyHash = compute_hash(@btc_pubkey);

            self.btc_public_key_blacklist.write(btc_pubkey_hash, true);
            self.remove_signer(signer);
        }

        fn is_signer(self: @ContractState, signer: ContractAddress) -> bool {
            self.signers_to_pubkey.read(signer).is_non_zero()
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn assert_signer(self: @ContractState) {
            let caller = get_caller_address();
            assert(self.signers_to_pubkey.read(caller).is_non_zero(), ONLY_SIGNER);
        }
    }

    #[generate_trait]
    impl WithdrawSignaturesStateImpl of WithdrawSignaturesStateTrait {
        fn has_signed(
            self: StoragePath<WithdrawSignaturesState>,
            withdraw_id: WithdrawId,
            btc_pubkey_hash: BtcPublicKeyHash,
        ) -> bool {
            self.withdraw_id_to_signatures.entry((withdraw_id, btc_pubkey_hash)).len() > 0
        }

        fn aggregate_signatures(
            self: StoragePath<WithdrawSignaturesState>,
            withdraw_id: WithdrawId,
            btc_pubkey_blacklist: StoragePath<Map<BtcPublicKeyHash, bool>>,
        ) -> Array<SignerSignatures> {
            let btc_pubkeys = self.withdraw_id_to_signers.entry(withdraw_id);
            let mut all_signatures: Array<SignerSignatures> = array![];

            for i in 0..btc_pubkeys.len() {
                let btc_pubkey: ByteArray = btc_pubkeys.at(i).read();
                let btc_pubkey_hash: BtcPublicKeyHash = compute_hash(@btc_pubkey);
                if btc_pubkey_blacklist.read(btc_pubkey_hash) {
                    continue;
                }
                let signer_sigs = self
                    .withdraw_id_to_signatures
                    .entry((withdraw_id, btc_pubkey_hash));
                let signatures = vec_to_array(signer_sigs);
                all_signatures.append(SignerSignatures { btc_pubkey, signatures });
            }

            all_signatures
        }
    }

    #[generate_trait]
    impl WithdrawSignaturesStateMutableImpl of WithdrawSignaturesStateMutableTrait {
        fn write_signatures(
            self: StoragePath<Mutable<WithdrawSignaturesState>>,
            withdraw_id: WithdrawId,
            btc_pubkey: ByteArray,
            signatures: Span<ByteArray>,
        ) {
            let btc_pubkey_hash: BtcPublicKeyHash = compute_hash(@btc_pubkey);
            if !self.as_non_mut().has_signed(:withdraw_id, :btc_pubkey_hash) {
                self.withdraw_id_to_signers.entry(withdraw_id).push(btc_pubkey.clone());
            }

            let mut signatures_vec = self
                .withdraw_id_to_signatures
                .entry((withdraw_id, btc_pubkey_hash));

            while signatures_vec.len() > 0 {
                let _ = signatures_vec.pop();
            }

            for signature in signatures {
                signatures_vec.push(signature.clone());
            }
        }
    }
}
