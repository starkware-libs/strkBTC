#[starknet::contract]
pub mod bridge {
    use core::num::traits::Zero;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry,
        StoragePointerReadAccess, StoragePointerWriteAccess,
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
        IterableMap, IterableMapReadAccessImpl, IterableMapTrait, IterableMapWriteAccessImpl,
    };
    use strkbtc_bridge::errors::{
        DUP_PUBLIC_KEY, DUP_SIGNER, INVALID_QUORUM, INVALID_WITHDRAW_AMOUNT, ONLY_SIGNER, ONLY_USER,
        SIGNER_NOT_REGISTERED, USER_NOT_REGISTERED, ZERO_BTC_DESTINATION, ZERO_MIN_WITHDRAW_AMOUNT,
        ZERO_PUBLIC_KEY, ZERO_REGISTRY_ADDRESS, ZERO_SIGNER, ZERO_TOKEN_ADDRESS, ZERO_USER,
    };
    use strkbtc_bridge::events::{DepositConfirmed, WithdrawRequested};
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

    pub const MIN_WITHDRAW_AMOUNT: u256 = 10_000_000; // 0.1 BTC
    pub const MIN_QUORUM: u64 = 2;

    type DepositId = felt252;

    #[starknet::storage_node]
    struct DepositWitnesses {
        witnesses: IterableMap<ContractAddress, bool>,
        confirmed: bool,
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
        mintable_token: IMintableTokenDispatcher, // Dispatcher of the token contract.
        registry: IRegistryDispatcher, // Dispatcher of the registry contract.
        quorum: u64, // Number of signers required to witness a deposit and withdraw
        min_withdraw_amount: u256, // Minimum amount of strkBTC that can be withdrawn.
        authorized_users: Map<
            ContractAddress, bool,
        >, // Whether a given Starknet address is an authorized user.
        signer_to_public_key: Map<
            ContractAddress, felt252,
        >, // For each Starknet address, the hash of the BTC public key of the signer.
        deposit_id_to_witnesses: Map<
            DepositId, DepositWitnesses,
        >, // For each deposit, the set of signers who have witnessed it.
        public_key_to_signer: Map<felt252, ContractAddress>,
        // For each BTC public key, the Starknet address of the signer who registered it.
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
        DepositConfirmed: DepositConfirmed,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        governance_admin: ContractAddress,
        upgrade_delay: u64,
        token_address: ContractAddress,
        registry_address: ContractAddress,
        quorum: u64,
    ) {
        self.roles.initialize(:governance_admin);
        self.replaceability.initialize(:upgrade_delay);

        assert(token_address.is_non_zero(), ZERO_TOKEN_ADDRESS);
        assert(registry_address.is_non_zero(), ZERO_REGISTRY_ADDRESS);
        assert(quorum >= MIN_QUORUM, INVALID_QUORUM);

        let mintable_token = IMintableTokenDispatcher { contract_address: token_address };
        let registry = IRegistryDispatcher { contract_address: registry_address };
        self.mintable_token.write(mintable_token);
        self.registry.write(registry);
        self.quorum.write(quorum);
        self.min_withdraw_amount.write(MIN_WITHDRAW_AMOUNT);
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
            self.has_witness(@deposit_id, signer)
        }

        fn witness_deposit(
            ref self: ContractState,
            btc_txid: ByteArray,
            vout: u32,
            amount: u256,
            destination_address: ContractAddress,
        ) {
            self.assert_signer();
            let caller = get_caller_address();
            let deposit_id = compute_deposit_id(@btc_txid, vout, amount, destination_address);
            if self.has_witness(@deposit_id, caller) {
                return;
            }

            let deposit_witnesses = self.deposit_id_to_witnesses.entry(deposit_id);
            deposit_witnesses.witnesses.write(caller, true);

            let witness_count = deposit_witnesses.witnesses.len();
            let quorum = self.quorum.read();

            if witness_count >= quorum && !self.is_confirmed(@deposit_id) {
                deposit_witnesses.confirmed.write(true);
                let mintable_token = self.mintable_token.read();
                mintable_token.permissioned_mint(destination_address, amount);
                self.emit(DepositConfirmed { btc_txid, vout, amount, destination_address });
            }
        }

        fn request_withdraw(ref self: ContractState, amount: u256, btc_destination: ByteArray) {
            self.assert_user();
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
            assert(signer.is_non_zero(), ZERO_SIGNER);
            assert(btc_public_key.is_non_zero(), ZERO_PUBLIC_KEY);
            assert(self.signer_to_public_key.read(signer).is_zero(), DUP_SIGNER);

            let btc_public_key_hash = compute_hash(@btc_public_key);
            assert(self.public_key_to_signer.read(btc_public_key_hash).is_zero(), DUP_PUBLIC_KEY);

            self.signer_to_public_key.write(signer, btc_public_key_hash);
            self.public_key_to_signer.write(btc_public_key_hash, signer);

            let registry = self.registry.read();
            registry.register_signer(signer, btc_public_key);
        }

        fn remove_signer(ref self: ContractState, signer: ContractAddress) {
            self.roles.only_app_governor();
            let btc_public_key_hash = self.signer_to_public_key.read(signer);
            assert(btc_public_key_hash.is_non_zero(), SIGNER_NOT_REGISTERED);

            self.signer_to_public_key.write(signer, Zero::zero());
            self.public_key_to_signer.write(btc_public_key_hash, Zero::zero());

            let registry = self.registry.read();
            registry.remove_signer(signer);
        }

        fn is_signer(self: @ContractState, signer: ContractAddress) -> bool {
            self.signer_to_public_key.read(signer).is_non_zero()
        }

        fn register_user(ref self: ContractState, user: ContractAddress) {
            self.roles.only_app_governor();
            assert(user.is_non_zero(), ZERO_USER);
            self.authorized_users.write(user, true);
        }

        fn remove_user(ref self: ContractState, user: ContractAddress) {
            self.roles.only_app_governor();
            assert(self.authorized_users.read(user), USER_NOT_REGISTERED);
            self.authorized_users.write(user, false);
        }

        fn is_user(self: @ContractState, user: ContractAddress) -> bool {
            self.authorized_users.read(user)
        }

        fn get_min_withdraw_amount(self: @ContractState) -> u256 {
            self.min_withdraw_amount.read()
        }

        fn set_min_withdraw_amount(ref self: ContractState, min_withdraw_amount: u256) {
            self.roles.only_app_governor();
            assert(min_withdraw_amount > Zero::zero(), ZERO_MIN_WITHDRAW_AMOUNT);
            self.min_withdraw_amount.write(min_withdraw_amount);
        }

        fn get_quorum(self: @ContractState) -> u64 {
            self.quorum.read()
        }

        fn set_quorum(ref self: ContractState, quorum: u64) {
            self.roles.only_app_governor();
            assert(quorum >= MIN_QUORUM, INVALID_QUORUM);
            self.quorum.write(quorum);
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

        fn has_witness(
            self: @ContractState, deposit_id: @DepositId, signer: ContractAddress,
        ) -> bool {
            self.deposit_id_to_witnesses.entry(*deposit_id).witnesses.read(signer).is_some()
        }

        fn is_confirmed(self: @ContractState, deposit_id: @DepositId) -> bool {
            self.deposit_id_to_witnesses.entry(*deposit_id).confirmed.read()
        }
    }
}
