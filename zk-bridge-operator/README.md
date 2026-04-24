# ZK Bridge Operator

This is the operator for the ZK bridge. It connects to the Mithril aggregator API,
fetches real Mithril certificates, and generates the ZK proofs required by the bridge for a
given Cardano transaction hash. It orchestrates both circuits in the repository:

- `../circuit_transaction_snapshot` — proves that the transaction is included in a Mithril snapshot
- `../circuit_inclusion_exclusion` — proves that the transaction was not previously used (double-spend prevention)

This crate is a standalone binary; it is not imported as a library by any other crate in the repo.

---

This crate owns the shared Mithril-facing operator workflow for the repo.

It provides:

- `relayer sync-certificates`
- `tx prove <transaction-hash>`

Default target:

- `https://aggregator.pre-release-preview.api.mithril.network/aggregator`

All relative output paths below are resolved from `zk-bridge-operator/`
unless overridden with `--certificate-dir` or `--tx-artifacts-dir`.

## Current behavior

Default persistent outputs from this crate live under:

- `certificates/`
- `tx_artifacts/`

## Command Output Contract

Commands:

- `relayer sync-certificates`
- `tx prove <transaction-hash>`

`relayer sync-certificates` writes:

- `certificates/index.json`
- `certificates/aggregator_features.json`
- `certificates/aggregator_status.json`
- `certificates/<certificate-hash>.json`

`index.json` is the compact sync manifest:

- `aggregator_url`
- `genesis_hash`
- `latest_recent_hashes`
- `stored_hashes`

For a canonical Cardano transaction hash, `tx prove`:

- fetches the Mithril transaction proof
- fetches the associated certificate
- verifies the Mithril proof and certificate chain
- generates a snapshot-membership proof in `../../circuit_transaction_snapshot`
- generates a tx-set-update proof in `../../circuit_inclusion_exclusion`

`tx prove` writes top-level metadata under:

- `tx_artifacts/<transaction-hash>/aggregator_features.json`
- `tx_artifacts/<transaction-hash>/aggregator_status.json`
- `tx_artifacts/<transaction-hash>/proof_response.json`
- `tx_artifacts/<transaction-hash>/certificate.json`
- `tx_artifacts/<transaction-hash>/snapshot.json` when the certificate resolves
  to a snapshot
- `tx_artifacts/<transaction-hash>/manifest.json`

`manifest.json` is the compact run summary:

- `aggregator_url`
- `transaction_hash`
- `proof_certificate_hash`
- `latest_block_number`
- `verified`
- `snapshot_hash`

Per-circuit proof bundles are written under:

- `tx_artifacts/<transaction-hash>/snapshot_membership/`
- `tx_artifacts/<transaction-hash>/tx_set_update/`

Each per-circuit directory contains the same shape:

- `input.json`
- `proof.json`
- `public.json`
- `packed_public_inputs.json`
- `verify.log`
- `fixture_summary.json`
- `<circuit>_vk.ak`

VK filenames:

- `snapshot_membership/snapshot_membership_vk.ak`
- `tx_set_update/tx_set_update_vk.ak`

The most useful files to inspect first are:

- `manifest.json` for the operator-level run summary
- `packed_public_inputs.json` for the public statement exported by each circuit
- `fixture_summary.json` for the compact proof bundle plus decoded public values

The runtime smoke used by `bridge-aiken/scripts/tests/run_ci_jobs_locally.sh`
checks that `tx prove` materializes:

- `manifest.json`
- `snapshot_membership/fixture_summary.json`
- `tx_set_update/fixture_summary.json`

In the validated happy path, both per-circuit `verify.log` files and both
`fixture_summary.json` files report `verified=true`.

## Important scope note

This operator is now aligned to the real Cardano `transaction_hash`.

It no longer tries to prove membership for a bridge-derived
`locking_tx_hash` inside Mithril. If downstream bridge code still expects that
older statement, that downstream integration must be updated separately.
