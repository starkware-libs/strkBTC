use starknet::ContractAddress;

#[derive(Drop, starknet::Event)]
pub struct WithdrawRequested {
    #[key]
    pub caller: ContractAddress,
    pub amount: u256,
    #[key]
    pub btc_destination: ByteArray,
}

#[derive(Drop, starknet::Event)]
pub struct DepositMinted {
    #[key]
    pub btc_txid: ByteArray,
    pub vout: u32,
    pub amount: u256,
    #[key]
    pub destination_address: ContractAddress,
}

#[derive(Drop, starknet::Event)]
pub struct DepositWitnessed {
    #[key]
    pub btc_txid: ByteArray,
    pub vout: u32,
    pub amount: u256,
    #[key]
    pub destination_address: ContractAddress,
    #[key]
    pub signer: ContractAddress,
}

#[derive(Drop, starknet::Event)]
pub struct SignerRegistered {
    #[key]
    pub signer: ContractAddress,
    #[key]
    pub btc_public_key: ByteArray,
}

#[derive(Drop, starknet::Event)]
pub struct SignerRemoved {
    #[key]
    pub signer: ContractAddress,
    #[key]
    pub btc_public_key: ByteArray,
    pub revoked: bool,
}


#[derive(Drop, starknet::Event)]
pub struct UserRegistered {
    #[key]
    pub user: ContractAddress,
}

#[derive(Drop, starknet::Event)]
pub struct UserRemoved {
    #[key]
    pub user: ContractAddress,
}
