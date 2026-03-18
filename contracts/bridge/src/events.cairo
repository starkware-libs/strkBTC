use starknet::ContractAddress;

#[derive(Drop, starknet::Event)]
pub struct WithdrawRequested {
    pub caller: ContractAddress,
    pub amount: u256,
    pub btc_destination: ByteArray,
}

#[derive(Drop, starknet::Event)]
pub struct DepositConfirmed {
    pub btc_txid: ByteArray,
    pub vout: u32,
    pub amount: u256,
    pub destination_address: ContractAddress,
}
