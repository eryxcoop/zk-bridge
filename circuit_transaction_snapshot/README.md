# Mithril Legacy Transaction Membership Operator Guide

This circuit proves that a given Cardano transaction is included in a Mithril snapshot.
It is one of the two ZK proofs required by the bridge: without it, a minting validator
on the destination chain cannot verify that the locked transaction actually occurred on
Cardano.

## How the Mithril Legacy Algorithm Works

Mithril organizes certified transactions into a two-level Merkle tree structure:

- **Sub-tree**: a group of consecutive transactions. Each leaf is the 64-byte
  lowercase ASCII hex encoding of a transaction hash. Internal nodes are computed
  as `Blake2s256(left || right)`.

- **Master tree**: each leaf commits to one sub-tree via
  `Blake2s256(range_ascii || sub_root)`, where `range_ascii` is an ASCII string
  identifying the range of transaction hashes covered by that sub-tree. Internal
  nodes are also `Blake2s256(left || right)`.

The root of the master tree is included in a Mithril certificate, which is signed
by a quorum of Mithril signers. To prove that a transaction belongs to a certified
snapshot, the prover supplies the full Merkle path from the transaction leaf up
through the sub-tree and then through the master tree to the certificate root.
The circuit verifies that path and exposes the transaction hash and the roots as
public outputs so they can be checked on-chain against the certificate.

## Compilation Settings

The currently compiled entrypoint is:

```circom
component main = MithrilLegacyTxMembership(10, 32, 32, 1, 32);
```

Fixed live sizes:

- `MAX_SUB_PREFIX_LEN = 10`
- `MAX_SUB_UPPER_HEIGHT = 32`
- `MAX_RANGE_ASCII_BYTES = 32`
- `MAX_MASTER_PREFIX_LEN = 1`
- `MAX_MASTER_UPPER_HEIGHT = 32`

## Circuit Inputs

To generate a proof, the prover must supply the following private inputs. These are the
values that describe the specific Merkle path for the transaction being proven. They come
from the Mithril aggregator API and are normalized into this shape by the operator before
being passed to the circuit.

The Merkle path is split into four segments (see the circuit comment for a full
explanation of the two-level tree structure):

**Sub-tree prefix** — the bottom-most steps of the sub-tree path, where
siblings can be either raw 64-byte transaction hashes or already-hashed 32-byte
values. Up to 10 steps are supported; unused slots must be zeroed.

In the concrete Circom contract, byte-array inputs use the `_b` suffix.

- `cardano_tx_hash[32]` — the transaction being proven, as raw bytes
- `sub_prefix_kinds[10]` — 0 = raw sibling, 1 = hash sibling
- `sub_prefix_raw_siblings[10][64]`
- `sub_prefix_hash_siblings[10][32]`
- `sub_prefix_sibling_on_left[10]`
- `sub_prefix_enabled[10]` — 1 for active steps, 0 for unused slots

**Sub-tree upper** — remaining steps to the sub-tree root; all siblings are
32-byte hashes.

- `sub_upper_siblings[32][32]`
- `sub_upper_sibling_on_left[32]`
- `sub_upper_enabled[32]`

**Master-tree prefix** — steps from the sub-tree root up through the master
tree leaf. Siblings are always 32-byte hashes.

- `range_ascii[32]` — ASCII encoding of the transaction range covered by the sub-tree
- `master_prefix_kinds[1]`
- `master_prefix_raw_siblings[1][64]`
- `master_prefix_hash_siblings[1][32]`
- `master_prefix_sibling_on_left[1]`
- `master_prefix_enabled[1]`

**Master-tree upper** — remaining steps to the master root.

- `master_upper_siblings[32][32]`
- `master_upper_sibling_on_left[32]`
- `master_upper_enabled[32]`
- `expected_root[32]` — the Merkle root from the Mithril certificate, used to verify the path

The exact Circom signal names are:

- `cardano_tx_hash_b`
- `sub_prefix_raw_siblings_b`
- `sub_prefix_hash_siblings_b`
- `sub_upper_siblings_b`
- `range_ascii_b`
- `master_prefix_raw_siblings_b`
- `master_prefix_hash_siblings_b`
- `master_upper_siblings_b`
- `expected_root_b`

## Circuit Outputs

The circuit has `6` public output signals. Each of the three 32-byte digests is
split into two 16-byte halves, each encoded as a big-endian field element, because
a BLS12-381 field element fits 128 bits but not 256.

- `cardano_tx_hash_hi` — high 16 bytes of the transaction hash
- `cardano_tx_hash_lo` — low 16 bytes of the transaction hash
- `sub_root_hi` — high 16 bytes of the sub-tree root
- `sub_root_lo` — low 16 bytes of the sub-tree root
- `master_root_hi` — high 16 bytes of the master Merkle root
- `master_root_lo` — low 16 bytes of the master Merkle root

Output ordering (as exported in `public.json`):

- index 0: `cardano_tx_hash_hi`
- index 1: `cardano_tx_hash_lo`
- index 2: `sub_root_hi`
- index 3: `sub_root_lo`
- index 4: `master_root_hi`
- index 5: `master_root_lo`

## Mithril API Response Format

To generate a proof for a given transaction, the operator queries the Mithril aggregator API `/proof/cardano-transaction`
endpoint to get the Merkle proof for that transaction. The API response has the following shape:

- `certificate_hash`
- `certified_transactions`
- `non_certified_transactions`
- `latest_block_number`

Each certified item contains:

- `transactions_hashes`
- `proof`

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
- `public_inputs=6`
- `verified=true`

The `cardano_tx_hash_hex` field in that file contains the transaction hash that was proven.

Stale historical `groth16_artifacts/test_runs/` directories were pruned after
the statement migration to `cardano_tx_hash`, so the kept canonical artifact is
the regenerated `groth16_artifacts/final_fixture/`.

The shared operator path using real Mithril data was also revalidated end-to-end:
`zk-bridge-operator tx prove <transaction-hash>` now generates a
`snapshot_membership/fixture_summary.json` with `verified=true`.

# Experimental Lagrange Circuit

Along with the circuit described above, we made another circuit that will addapt to the new Mithril scheme, that will
replace the current two-level Blake2s Merkle tree with a simpler single-level Merkle tree using a Poseidon hash
function optimized for BLS12-381 (the Midnight Poseidon variant). This change is not yet in production but is 
actively being developed. Once it lands, the legacy circuit above will no longer be compatible with the proofs 
produced by Mithril, and this new circuit will replace it.

In the new scheme, all transactions are organized into a single flat Merkle tree instead of
the two-level structure used today. To prove that a transaction is in the tree, the prover
supplies its position in the tree (the leaf index) and the list of sibling nodes along the
path from that leaf up to the root (one sibling per level of the tree). The
circuit exposes the same public outputs as the legacy circuit so the bridge validators
require no changes.

The implementation of this circuit can be found in `mithril_lagrange_tx_membership_experimental.circom`.

It is not yet connected to the operator or compatible with `tx prove` for two reasons:

- the Midnight Poseidon hash is currently mocked with a Poseidon255 placeholder,
  since the real implementation is not yet finalized by Mithril.
- the witness format does not yet match the proof shape produced by the Mithril
  aggregator API.

It should be treated as a work in progress, not as an alternative to the above circuit.
