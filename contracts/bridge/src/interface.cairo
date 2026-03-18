use starknet::ContractAddress;

#[starknet::interface]
pub trait IBridge<TContractState> {
    fn is_witnessed(
        self: @TContractState,
        btc_txid: ByteArray,
        vout: u32,
        amount: u256,
        destination_address: ContractAddress,
        signer: ContractAddress,
    ) -> bool;
    fn witness_deposit(
        ref self: TContractState,
        btc_txid: ByteArray,
        vout: u32,
        amount: u256,
        destination_address: ContractAddress,
    );
    fn request_withdraw(ref self: TContractState, amount: u256, btc_destination: ByteArray);
    fn register_signer(
        ref self: TContractState, signer: ContractAddress, btc_public_key: ByteArray,
    );
    fn remove_signer(ref self: TContractState, signer: ContractAddress);
    fn is_signer(self: @TContractState, signer: ContractAddress) -> bool;
    fn register_user(ref self: TContractState, user: ContractAddress);
    fn remove_user(ref self: TContractState, user: ContractAddress);
    fn is_user(self: @TContractState, user: ContractAddress) -> bool;
    fn get_min_withdraw_amount(self: @TContractState) -> u256;
    fn set_min_withdraw_amount(ref self: TContractState, min_withdraw_amount: u256);
    fn get_quorum(self: @TContractState) -> u64;
    fn set_quorum(ref self: TContractState, quorum: u64);
}
