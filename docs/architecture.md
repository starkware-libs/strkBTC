# Architecture

## System Context

The strkBTC bridge consists of three Starknet contracts and a set of independent off-chain signer nodes:

**Starknet contracts:**

- **strkBTC ERC20** — standard ERC20 with mint/burn permissions
- **Bridge contract** — tracks deposit witnesses and triggers minting when the k-th signer confirms
- **Registry contract** — stores withdrawal Bitcoin transactions and collects signer signatures

**Off-chain components:**

- **Signer nodes** — each signer independently watches both chains, witnesses deposits, signs withdrawals, and broadcasts fully-signed Bitcoin transactions. No signer coordinates with another.

## Deposit Flow

1. An authorized LP sends BTC to the k-of-n multisig address with an `OP_RETURN` output containing the destination Starknet address.
2. Each signer scans Bitcoin blocks for transactions matching the multisig. When a deposit is found with 6+ confirmations, the signer validates it (valid Starknet address, authorized LP).
3. The signer checks `is_witnessed(txid, vout, amount, destination_address, sn_signer_address)` on the bridge contract. If not yet witnessed, it calls `witness_deposit(txid, vout, amount, destination_address)`.
4. Once the k-th signer witnesses the same deposit, the bridge contract mints strkBTC to the destination address.

```
LP sends BTC to multisig (with OP_RETURN containing Starknet address)
    │
    ▼
Each signer scans & validates (6 confirmations, valid address, authorized LP)
    │
    ▼
witness_deposit() on Bridge contract
    │
    ▼
k-th witness triggers mint ──► strkBTC minted to destination
```

## Withdrawal Flow

1. A user burns strkBTC on the bridge contract, which emits a `WithdrawRequestedEvent`.
2. Each signer polls for these events and waits for L1 finality (block status `ACCEPTED_ON_L1`).
3. The signer deterministically builds an unsigned Bitcoin transaction (PSBT) from the multisig UTXOs. All signers build the same transaction because UTXO selection is deterministic.
4. The signer checks `has_signed_withdraw(btc_transaction, btc_pubkey)` on the registry contract. If not yet signed, it signs the PSBT and calls `sign_withdraw(btc_transaction, btc_signatures)`.
5. Once k signatures are collected, each signer's broadcaster independently attempts to finalize and broadcast the transaction. Each signer uses its own fee UTXOs (P2WPKH outputs) to pay for transaction fees — signatures use `SIGHASH_ALL | SIGHASH_ANYONECANPAY` so fee inputs can be added without invalidating the multisig signatures.

```
User burns strkBTC ──► WithdrawRequestedEvent
    │
    ▼
Each signer waits for L1 finality
    │
    ▼
Deterministically builds same PSBT ──► sign_withdraw() on Registry
    │
    ▼
k signatures collected ──► Each signer tries to broadcast (with own fee UTXOs)
    │
    ▼
First successful broadcast settles the withdrawal on Bitcoin
```

## Authorization

- Only pre-authorized LPs (Liquidity provider) can deposit and withdraw
- **Deposits** — authorization enforced at the signer level; unauthorized deposits are simply not witnessed
- **Withdrawals** — authorization enforced at the Starknet contract level with fast-fail
- **Signer set changes** — adding/removing signers requires the specific role inthe starknet contracts
