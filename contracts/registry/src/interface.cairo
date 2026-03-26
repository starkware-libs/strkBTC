use starknet::ContractAddress;

#[starknet::interface]
pub trait IRegistry<TContractState> {
    fn sign_withdraw(ref self: TContractState, raw_tx: ByteArray, signatures: Span<ByteArray>);
    fn has_signed_withdraw(self: @TContractState, raw_tx: ByteArray, btc_pubkey: ByteArray) -> bool;
    fn register_signer(ref self: TContractState, signer: ContractAddress, btc_pubkey: ByteArray);
    fn remove_signer(ref self: TContractState, signer: ContractAddress);
    fn revoke_signer(ref self: TContractState, signer: ContractAddress);
    fn is_signer(self: @TContractState, signer: ContractAddress) -> bool;
}
