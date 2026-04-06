use starknet::ContractAddress;

#[starknet::interface]
pub trait IBridge<TContractState> {
    /// Returns true if the deposit has been witnessed by the given signer.
    fn is_witnessed(
        self: @TContractState,
        btc_txid: ByteArray,
        vout: u32,
        amount: u256,
        destination_address: ContractAddress,
        signer: ContractAddress,
    ) -> bool;
    /// Witnesses a deposit by the given signer.
    fn witness_deposit(
        ref self: TContractState,
        btc_txid: ByteArray,
        vout: u32,
        amount: u256,
        destination_address: ContractAddress,
    );
    /// Requests a withdrawal of the given amount to the given BTC destination.
    fn request_withdraw(ref self: TContractState, amount: u256, btc_destination: ByteArray);
    /// Registers a signer with the given BTC public key.
    fn register_signer(
        ref self: TContractState, signer: ContractAddress, btc_public_key: ByteArray,
    );
    /// Removes a signer from the bridge.
    fn remove_signer(ref self: TContractState, signer: ContractAddress);
    /// Revokes a signer from the bridge.
    fn revoke_signer(ref self: TContractState, signer: ContractAddress);
    /// Returns true if the given signer is registered.
    fn is_signer(self: @TContractState, signer: ContractAddress) -> bool;
    /// Registers a user with the bridge.
    fn register_user(ref self: TContractState, user: ContractAddress);
    /// Removes a user from the bridge.
    fn remove_user(ref self: TContractState, user: ContractAddress);
    /// Returns true if the given user is registered.
    fn is_user(self: @TContractState, user: ContractAddress) -> bool;
    /// Returns the minimum withdrawal amount.
    fn get_min_withdraw_amount(self: @TContractState) -> u256;
    /// Sets the minimum withdrawal amount.
    fn set_min_withdraw_amount(ref self: TContractState, min_withdraw_amount: u256);
    /// Returns the deposit quorum.
    fn get_quorum(self: @TContractState) -> u64;
    /// Sets the deposit quorum.
    fn set_quorum(ref self: TContractState, quorum: u64);
    /// Initializes the bridge.
    fn init_bridge(
        ref self: TContractState,
        token_address: ContractAddress,
        registry_address: ContractAddress,
        quorum: u64,
        min_withdraw_amount: u256,
    );
}
