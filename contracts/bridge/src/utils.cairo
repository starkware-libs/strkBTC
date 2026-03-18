use core::poseidon::poseidon_hash_span;
use core::serde::Serde;
use starknet::ContractAddress;

pub fn compute_deposit_id(
    btc_txid: @ByteArray, vout: u32, amount: u256, destination_address: ContractAddress,
) -> felt252 {
    let mut serialized: Array<felt252> = array![];
    btc_txid.serialize(ref serialized);
    vout.serialize(ref serialized);
    amount.serialize(ref serialized);
    destination_address.serialize(ref serialized);
    poseidon_hash_span(serialized.span())
}
