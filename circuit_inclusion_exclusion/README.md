# Transaction Set Update Circuit

This circuit proves that a Cardano transaction was not previously part of the set of used transactions, 
and that the set was then updated to include it. It is one of the two ZK proofs required by the bridge: 
without it, an unlocking validator on Cardano could be tricked into releasing funds twice for the same
burn transaction on the other chain, and a minting validator on the other chain could be tricked 
into minting twice for the same locking transaction on Cardano.

## How the Transaction Set Update Works

To prevent double spending, the bridge maintains a set of already-used
transactions. So that this set does not grow unboundedly on-chain, it is
represented as the root of a **sparse Merkle tree (SMT)** of fixed height `256`,
where the path of a transaction is determined by the bits of its `tx_id`:

- every empty leaf is `Fr(0)` and every present leaf is `Fr(1)`
- internal nodes are `Poseidon255(left, right)` over the BLS12-381 scalar field
- the path from root to leaf is read from the big-endian bits of `tx_id`

Because every possible `tx_id` corresponds to a unique fixed leaf position, the same Merkle path 
serves both to prove that a transaction is **absent** (the leaf at that position is `Fr(0)`) 
and that it is **present** (the leaf is `Fr(1)`). The sibling hashes along the path do not change
when only that leaf is flipped.

The circuit takes the `tx_id`, the old root `mt_root_in`, the new root `mt_root_out`, and the Merkle path 
(the sibling hashes at each of the `256` levels) as input, and enforces two statements at once using the same path:

- recomputing the root from the path with an empty leaf (`Fr(0)`) yields `mt_root_in` 
  (the transaction was **not** in the old set)
- recomputing the root from the same path with a present leaf (`Fr(1)`)
  yields `mt_root_out` (the transaction **is** in the new set)

Since both reconstructions share the same siblings, a valid proof also guarantees that `mt_root_out` is 
exactly the result of inserting `tx_id` into the set represented by `mt_root_in`, with no other leaves touched.
The three values `tx_id`, `mt_root_in`, and `mt_root_out` are exposed as public outputs so the bridge 
validators can check them against the transaction being processed and the state stored on-chain.

## Current Status

The circuit is implemented against the canonical Rust SMT model. Both Rust and
Circom use Poseidon255 over BLS12-381 Fr for internal tree nodes.

Current entrypoint:

```circom
component main = TxSetUpdate();
```

Semantic public statement:

```text
tx_id || mt_root_in || mt_root_out
```

Packed public inputs:

- `tx_id_hi`
- `tx_id_lo`
- `mt_root_in`
- `mt_root_out`

`tx_id` is a 32-byte digest packed into two 16-byte big-endian field elements.
For the shared Mithril flow, that `tx_id` is now intended to be the canonical
Cardano transaction hash, not a bridge-derived digest.

## SMT Model

- tree height: `256`
- internal hash: `Poseidon255(left: Fr, right: Fr) -> Fr`
- field: BLS12-381 scalar field
- empty leaf: `Fr(0)`
- present leaf: `Fr(1)`
- path bits: `tx_id` big-endian bits, root-to-leaf
- path values: `mt_path_values[0]` is the sibling nearest the root

## Local Testing Flow

These commands compile the circuit, generate a proof from a synthetic hardcoded witness,
and verify that it passes. No network access or real Mithril data is needed. If these commands run correctly, you can
confirm that the circuit compiles correctly and that the Groth16 proof verifies.

```bash
./scripts/build_groth16_artifacts.sh
./scripts/run_e2e_test.sh
cargo test --lib
cargo test --test groth16_offline -- --nocapture
```

If everything ran correctly, `groth16_artifacts/final_fixture/fixture_summary.json` should
contain the following fields, which confirm that the circuit compiled, the witness was
satisfiable, and the proof verified:

- `curve=bls12381`
- `protocol=groth16`
- `public_inputs=4`
- `verified=true`

The `tx_id_hex`, `mt_root_in_hex`, and `mt_root_out_hex` fields in that file contain
the transaction hash that was proven, the root of the set before the update, and the
root of the set after the update.

Stale historical `groth16_artifacts/test_runs/` directories were pruned after
the shared operator migration, so the kept canonical artifact is the regenerated `groth16_artifacts/final_fixture/`.

The shared operator path using real Mithril data was also revalidated end-to-end:
`zk-bridge-operator tx prove <transaction-hash>` now generates a `tx_set_update/fixture_summary.json` 
with `verified=true`.
