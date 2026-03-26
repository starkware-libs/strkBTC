#[starknet::contract]
pub mod bridge {
    use core::num::traits::Zero;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::storage::{
        Map, Mutable, StorageMapReadAccess, StorageMapWriteAccess, StoragePath, StoragePathEntry,
        StoragePathMutableConversion, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;
    use starkware_utils::interfaces::mintable_token::{
        IMintableTokenDispatcher, IMintableTokenDispatcherTrait,
    };
    use starkware_utils::storage::iterable_map::{
        IterableMap, IterableMapIntoIterImpl, IterableMapReadAccessImpl, IterableMapWriteAccessImpl,
    };
    use strkbtc_bridge::errors::{
        BRIDGE_ALREADY_INITIALIZED, BRIDGE_NOT_INITIALIZED, DUP_PUBLIC_KEY, INVALID_QUORUM,
        INVALID_WITHDRAW_AMOUNT, ONLY_SIGNER, ONLY_USER, SIGNER_BLACKLISTED, SIGNER_NOT_REGISTERED,
        USER_NOT_REGISTERED, ZERO_BTC_DESTINATION, ZERO_PUBLIC_KEY, ZERO_REGISTRY_ADDRESS,
        ZERO_SIGNER, ZERO_TOKEN_ADDRESS, ZERO_USER,
    };
    use strkbtc_bridge::events::{
        DepositMinted, DepositWitnessed, SignerRegistered, SignerRemoved, UserRegistered,
        UserRemoved, WithdrawRequested,
    };
    use strkbtc_bridge::interface::IBridge;
    use strkbtc_bridge::utils::compute_deposit_id;
    use strkbtc_registry::interface::{IRegistryDispatcher, IRegistryDispatcherTrait};
    use strkbtc_registry::utils::{ByteArrayZero, compute_hash};

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);

    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    pub const MIN_QUORUM: u64 = 2;

    type DepositId = felt252;
    type BtcPublicKeyHash = felt252;

    #[starknet::storage_node]
    struct DepositWitnesses {
        witnesses: IterableMap<ContractAddress, bool>,
        minted: bool,
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
        /// Contract state variables
        bridge_initialized: bool,
        mintable_token: IMintableTokenDispatcher, // Dispatcher of the token contract.
        registry: IRegistryDispatcher, // Dispatcher of the registry contract.
        quorum: u64, // Number of signers required to witness a deposit and withdraw
        min_withdraw_amount: u256, // Minimum amount of strkBTC that can be withdrawn.
        // Whether a given Starknet address is an authorized user.
        authorized_users: Map<ContractAddress, bool>,
        // For each Starknet address, the BTC public key of the signer.
        signer_to_public_key: Map<ContractAddress, ByteArray>,
        // For each deposit, the set of signers who have witnessed it.
        deposit_id_to_witnesses: Map<DepositId, DepositWitnesses>,
        // For each BTC public key, the Starknet address of the signer who registered it.
        public_key_hash_to_signer: Map<BtcPublicKeyHash, ContractAddress>,
        // For each Starknet address, a boolean indicating if it is blacklisted.
        signer_blacklist: Map<ContractAddress, bool>,
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
        WithdrawRequested: WithdrawRequested,
        DepositMinted: DepositMinted,
        DepositWitnessed: DepositWitnessed,
        SignerRegistered: SignerRegistered,
        SignerRemoved: SignerRemoved,
        UserRegistered: UserRegistered,
        UserRemoved: UserRemoved,
    }

    #[constructor]
    fn constructor(ref self: ContractState, governance_admin: ContractAddress, upgrade_delay: u64) {
        self.roles.initialize(:governance_admin);
        self.replaceability.initialize(:upgrade_delay);
        self.bridge_initialized.write(false);
    }

    #[abi(embed_v0)]
    pub impl BridgeImpl of IBridge<ContractState> {
        fn is_witnessed(
            self: @ContractState,
            btc_txid: ByteArray,
            vout: u32,
            amount: u256,
            destination_address: ContractAddress,
            signer: ContractAddress,
        ) -> bool {
            let deposit_id = compute_deposit_id(@btc_txid, vout, amount, destination_address);
            self.deposit_id_to_witnesses.entry(deposit_id).has_witnessed(signer)
        }

        fn witness_deposit(
            ref self: ContractState,
            btc_txid: ByteArray,
            vout: u32,
            amount: u256,
            destination_address: ContractAddress,
        ) {
            self.assert_signer();
            self.assert_initialized();
            let caller = get_caller_address();
            let deposit_id = compute_deposit_id(@btc_txid, vout, amount, destination_address);

            let mut deposit_witnesses_mutable = self.deposit_id_to_witnesses.entry(deposit_id);
            deposit_witnesses_mutable.mark_witnessed(signer: caller);
            self
                .emit(
                    DepositWitnessed {
                        btc_txid: btc_txid.clone(),
                        vout,
                        amount,
                        destination_address,
                        signer: caller,
                    },
                );

            let deposit_witnesses = deposit_witnesses_mutable.as_non_mut();
            let validated_witness_count = deposit_witnesses
                .get_validated_witness_count(self.signer_blacklist.as_non_mut());
            let quorum = self.quorum.read();

            if validated_witness_count >= quorum && !deposit_witnesses.is_minted() {
                deposit_witnesses_mutable.mark_minted(true);
                let mintable_token = self.mintable_token.read();
                mintable_token.permissioned_mint(destination_address, amount);
                self.emit(DepositMinted { btc_txid, vout, amount, destination_address });
            }
        }

        fn request_withdraw(ref self: ContractState, amount: u256, btc_destination: ByteArray) {
            self.assert_user();
            self.assert_initialized();
            assert(amount >= self.min_withdraw_amount.read(), INVALID_WITHDRAW_AMOUNT);
            assert(btc_destination.is_non_zero(), ZERO_BTC_DESTINATION);

            let caller = get_caller_address();
            let mintable_token = self.mintable_token.read();
            mintable_token.permissioned_burn(caller, amount);
            self.emit(WithdrawRequested { caller, amount, btc_destination });
        }

        fn register_signer(
            ref self: ContractState, signer: ContractAddress, btc_public_key: ByteArray,
        ) {
            self.roles.only_app_governor();
            self.assert_initialized();
            assert(signer.is_non_zero(), ZERO_SIGNER);
            assert(btc_public_key.is_non_zero(), ZERO_PUBLIC_KEY);

            let btc_public_key_hash: BtcPublicKeyHash = compute_hash(@btc_public_key);
            assert(
                self.public_key_hash_to_signer.read(btc_public_key_hash).is_zero(), DUP_PUBLIC_KEY,
            );
            assert(!self.signer_blacklist.read(signer), SIGNER_BLACKLISTED);

            let old_btc_public_key = self.signer_to_public_key.read(signer);
            if old_btc_public_key.is_non_zero() {
                let old_btc_public_key_hash: BtcPublicKeyHash = compute_hash(@old_btc_public_key);
                self.public_key_hash_to_signer.write(old_btc_public_key_hash, Zero::zero());
            }
            self.signer_to_public_key.write(signer, btc_public_key.clone());
            self.public_key_hash_to_signer.write(btc_public_key_hash, signer);

            let registry = self.registry.read();
            registry.register_signer(signer, btc_public_key.clone());
            self.emit(SignerRegistered { signer, btc_public_key });
        }

        fn remove_signer(ref self: ContractState, signer: ContractAddress) {
            self.roles.only_app_governor();
            self.assert_initialized();
            self.internal_remove_signer(:signer, revoked: false);
        }

        fn revoke_signer(ref self: ContractState, signer: ContractAddress) {
            self.roles.only_app_governor();
            self.assert_initialized();
            self.internal_remove_signer(:signer, revoked: true);
        }

        fn is_signer(self: @ContractState, signer: ContractAddress) -> bool {
            self.signer_to_public_key.read(signer).is_non_zero()
        }

        fn register_user(ref self: ContractState, user: ContractAddress) {
            self.roles.only_app_governor();
            self.assert_initialized();
            assert(user.is_non_zero(), ZERO_USER);
            self.authorized_users.write(user, true);
            self.emit(UserRegistered { user });
        }

        fn remove_user(ref self: ContractState, user: ContractAddress) {
            self.roles.only_app_governor();
            self.assert_initialized();
            assert(self.authorized_users.read(user), USER_NOT_REGISTERED);
            self.authorized_users.write(user, false);
            self.emit(UserRemoved { user });
        }

        fn is_user(self: @ContractState, user: ContractAddress) -> bool {
            self.authorized_users.read(user)
        }

        fn get_min_withdraw_amount(self: @ContractState) -> u256 {
            self.assert_initialized();
            self.min_withdraw_amount.read()
        }

        fn set_min_withdraw_amount(ref self: ContractState, min_withdraw_amount: u256) {
            self.roles.only_app_governor();
            self.assert_initialized();
            self.min_withdraw_amount.write(min_withdraw_amount);
        }

        fn get_quorum(self: @ContractState) -> u64 {
            self.assert_initialized();
            self.quorum.read()
        }

        fn set_quorum(ref self: ContractState, quorum: u64) {
            self.roles.only_app_governor();
            self.assert_initialized();
            assert(quorum >= MIN_QUORUM, INVALID_QUORUM);
            self.quorum.write(quorum);
        }
        fn init_bridge(
            ref self: ContractState,
            token_address: ContractAddress,
            registry_address: ContractAddress,
            quorum: u64,
            min_withdraw_amount: u256,
        ) {
            self.roles.only_app_governor();
            assert(!self.bridge_initialized.read(), BRIDGE_ALREADY_INITIALIZED);
            assert(token_address.is_non_zero(), ZERO_TOKEN_ADDRESS);
            assert(registry_address.is_non_zero(), ZERO_REGISTRY_ADDRESS);
            assert(quorum >= MIN_QUORUM, INVALID_QUORUM);

            let mintable_token = IMintableTokenDispatcher { contract_address: token_address };
            let registry = IRegistryDispatcher { contract_address: registry_address };

            self.mintable_token.write(mintable_token);
            self.registry.write(registry);
            self.quorum.write(quorum);
            self.min_withdraw_amount.write(min_withdraw_amount);
            self.bridge_initialized.write(true);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn assert_signer(self: @ContractState) {
            let caller = get_caller_address();
            assert(self.signer_to_public_key.read(caller).is_non_zero(), ONLY_SIGNER);
        }

        fn assert_user(self: @ContractState) {
            let caller = get_caller_address();
            assert(self.authorized_users.read(caller), ONLY_USER);
        }

        fn assert_initialized(self: @ContractState) {
            assert(self.bridge_initialized.read(), BRIDGE_NOT_INITIALIZED);
        }

        fn internal_remove_signer(ref self: ContractState, signer: ContractAddress, revoked: bool) {
            let btc_public_key = self.signer_to_public_key.read(signer);
            assert(btc_public_key.is_non_zero(), SIGNER_NOT_REGISTERED);

            let btc_public_key_hash: BtcPublicKeyHash = compute_hash(@btc_public_key);
            self.signer_to_public_key.write(signer, Zero::zero());
            self.public_key_hash_to_signer.write(btc_public_key_hash, Zero::zero());
            let registry = self.registry.read();

            if revoked {
                self.signer_blacklist.write(signer, true);
                // revoke signer in registry == remove signer + blacklist signer in registry
                registry.revoke_signer(signer);
            } else {
                registry.remove_signer(signer);
            }
            self.emit(SignerRemoved { signer, btc_public_key, revoked });
        }
    }

    #[generate_trait]
    impl DepositWitnessesImpl of DepositWitnessesTrait {
        fn has_witnessed(self: StoragePath<DepositWitnesses>, signer: ContractAddress) -> bool {
            let witnessed = self.witnesses.read(signer);
            witnessed.is_some() && witnessed.unwrap()
        }

        fn is_minted(self: StoragePath<DepositWitnesses>) -> bool {
            self.minted.read()
        }

        fn get_validated_witness_count(
            self: StoragePath<DepositWitnesses>,
            signer_blacklist: StoragePath<Map<ContractAddress, bool>>,
        ) -> u64 {
            let mut count = 0;
            for (signer, witnessed) in self.witnesses {
                if witnessed && !signer_blacklist.read(signer) {
                    count += 1;
                }
            }
            count
        }
    }

    #[generate_trait]
    impl DepositWitnessesMutableImpl of DepositWitnessesMutableTrait {
        fn mark_witnessed(
            ref self: StoragePath<Mutable<DepositWitnesses>>, signer: ContractAddress,
        ) {
            self.witnesses.write(signer, true);
        }

        fn mark_minted(ref self: StoragePath<Mutable<DepositWitnesses>>, minted: bool) {
            self.minted.write(minted);
        }
    }
}
