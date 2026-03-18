use core::num::traits::Zero;
use core::poseidon::poseidon_hash_span;
use starknet::storage::{StoragePath, StoragePointerReadAccess, Vec, VecTrait};

pub fn compute_withdraw_id(raw_tx: @ByteArray) -> felt252 {
    compute_hash(raw_tx)
}

pub fn compute_hash(data: @ByteArray) -> felt252 {
    let mut serialized: Array<felt252> = array![];
    data.serialize(ref serialized);
    poseidon_hash_span(serialized.span())
}

pub impl ByteArrayZero of Zero<ByteArray> {
    fn zero() -> ByteArray {
        Default::default()
    }
    fn is_zero(self: @ByteArray) -> bool {
        self.len() == 0
    }
    fn is_non_zero(self: @ByteArray) -> bool {
        !self.is_zero()
    }
}

pub fn vec_to_array(signer_sigs: StoragePath<Vec<ByteArray>>) -> Array<ByteArray> {
    let mut signatures: Array<ByteArray> = array![];
    for i in 0..signer_sigs.len() {
        signatures.append(signer_sigs.at(i).read());
    }
    signatures
}
