#[derive(Drop, Serde, starknet::Event)]
pub struct SignerSignatures {
    pub btc_pubkey: ByteArray,
    pub signatures: Array<ByteArray>,
}

#[derive(Drop, Serde, starknet::Event)]
pub struct WithdrawSigned {
    pub withdraw_id: felt252,
    pub raw_tx: ByteArray,
    pub signatures: Array<SignerSignatures>,
}

