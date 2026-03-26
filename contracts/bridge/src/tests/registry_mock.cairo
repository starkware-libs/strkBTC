#[starknet::contract]
pub mod registry_mock {
    use starknet::ContractAddress;
    use strkbtc_registry::interface::IRegistry;
    #[storage]
    struct Storage {}

    #[constructor]
    fn constructor(ref self: ContractState) { // no-op
    }

    #[abi(embed_v0)]
    pub impl RegistryMockImpl of IRegistry<ContractState> {
        fn sign_withdraw(
            ref self: ContractState, raw_tx: ByteArray, signatures: Span<ByteArray>,
        ) { // no-op
        }

        fn has_signed_withdraw(
            self: @ContractState, raw_tx: ByteArray, btc_pubkey: ByteArray,
        ) -> bool {
            false
        }

        fn register_signer(
            ref self: ContractState, signer: ContractAddress, btc_pubkey: ByteArray,
        ) { // no-op
        }

        fn remove_signer(ref self: ContractState, signer: ContractAddress) { // no-op
        }

        fn revoke_signer(ref self: ContractState, signer: ContractAddress) { // no-op
        }

        fn is_signer(self: @ContractState, signer: ContractAddress) -> bool {
            false
        }
    }
}
