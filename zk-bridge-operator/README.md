# ZK Bridge Operator

Shared operator binary for the repo.

It covers two areas:

- Mithril-facing proof generation for `tx prove <transaction-hash>`
- Preview operator flows for reference scripts, phase1/phase2, stake distribution, seed txs, and bridge minting

## Commands

- `relayer sync-certificates`
- `tx prove <transaction-hash>`
- `preview check-status`
- `preview list-address-utxos`
- `preview submit-signed-artifact`
- `preview invoke-cli-publish-phase1-reference-script`
- `preview invoke-cli-publish-minting-txs-updater-spend-reference-script`
- `preview invoke-cli-publish-bridge-minting-reference-script`
- `preview invoke-cli-locking-txs-updater-seed-tx`
- `preview invoke-cli-minting-txs-updater-seed-tx`
- `preview invoke-cli-bridge-mint-tx`
- `preview invoke-cli-bridge-mint-flow`
- `preview invoke-cli-phase1-setup`
- `preview invoke-cli-phase2-verify`
- `preview invoke-cli-stake-distribution-genesis-tx`
- `preview invoke-cli-stake-distribution-genesis-flow`
- `preview invoke-cli-stake-distribution-standard-tx`
- `preview invoke-cli-stake-distribution-standard-flow`
- `preview export-unsigned-phase1-setup`
- `preview export-unsigned-phase2-verify`

## Mithril Compatibility

Checked on `2026-06-09` for `zk-bridge-operator`:

- `mithril-client = 0.14.5`
- `mithril-aggregator-client = 0.1.10`
- `mithril-aggregator-discovery = 0.1.4`
- `mithril-common = 0.6.67`
- `mithril-stm = 0.10.5`
- `mithril-cardano-node-internal-database = 0.1.11`

Default aggregator:

- endpoint: `https://aggregator.pre-release-preview.api.mithril.network/aggregator`
- reported `open_api_version`: `0.1.61`

The crate versions above come from `cargo tree -p zk-circuit-operator`.
The aggregator OpenAPI version comes from `GET /` on the default aggregator endpoint.

## Mithril 0.1.65 Notes

Reviewed on `2026-06-09` against Mithril mainline `openapi.yaml` with `info.version: 0.1.65`.

Implemented in the current bridge tooling:

- Preflight validates `GET /protocol-configuration/{epoch}` for the target bundle epoch, or the live aggregator epoch when no bundle is provided.
- Aggregator fingerprints now persist richer `/status` fields such as protocol parameters and signer totals.
- Stake-distribution live resolution now prefers `/artifact/cardano-stake-distribution/epoch/{epoch}` when the epoch is known, and otherwise uses the epoch-aware `latest` endpoint before falling back to the legacy list endpoint.

Known aggregator limitation observed on `2026-06-09`:

- `GET /protocol-configuration/{epoch}` is not reliably available for older epochs on `https://aggregator.pre-release-preview.api.mithril.network/aggregator`.
- Example: `/protocol-configuration/1130` and even `/protocol-configuration/1300` returned `404`, while recent epochs still resolved (current epoch was `1323`).
- Because the bridge-compatible Mithril STM bundle is a synthetic fixture with historical epoch values, bridge preflight now treats `source_kind=fixture` bundles as "validate against the live aggregator epoch" instead of assuming that the embedded historical epoch is queryable on the current aggregator.

Implementation note for this repo:

- `zk-bridge-operator/src/mithril_api.rs` currently parses only a minimal subset of `/status`.
- That is still fine for compatibility because the extra `0.1.65` fields are additive.
- Extending the stored status and fingerprint is recommended for observability, not because deserialization is currently broken.

## Outputs

Persistent operator outputs:

- `certificates/`
- `tx_artifacts/`

Preview CLI runs write under:

- `.omx/tmp/preview-operator-cli/`
- `preview_phase12/`

Current retention rule for `preview_phase12/`:

- keep only `successful-onchain-txs.json`
- regenerate reproducible artifacts on demand

Useful proof outputs:

- `tx_artifacts/<tx>/manifest.json`
- `tx_artifacts/<tx>/snapshot_membership/fixture_summary.json`
- `tx_artifacts/<tx>/tx_set_update/fixture_summary.json`

## Preview Layout

Preview code is split by responsibility:

- `src/preview/phase12.rs`
  - phase1/phase2 publish/setup/submit helpers
- `src/preview/stake_distribution.rs`
  - stake distribution txs and unified stake distribution flows
- `src/preview/bridge_minting.rs`
  - bridge mint tx and unified bridge mint flow
- `src/preview/phase12_budget.rs`
  - ex-unit and fee patching
- `src/preview/phase12_state.rs`
  - persisted source/collateral state
- `src/preview/phase12_validation.rs`
  - exact simulation and post-submit validation

If a new Preview responsibility is not just command wiring, add or extend a helper module instead of growing `phase12.rs`.

## Current Preview Rules

- The old proof-receipt publish flow is retired.
- The maintained Preview lane starts from `publish_phase1_reference_script` or later.
- Commands must not hardcode historical tx hashes or UTxOs.
- Values that change run to run must come from:
  - CLI args
  - current Mithril bundle contents
  - persisted operator state under `preview_phase12/`
  - live chain lookups

## Bridge Reference Scripts

Bridge reference-script publish defaults:

- `publish_minting_txs_updater_spend_reference_script`
  - `--reference-script-lovelace 40000000`
- `publish_bridge_minting_reference_script`
  - `--reference-script-lovelace 40000000`

Reason:

- `10000000` was below the current Conway min-UTxO for these heavy scripts on Preview

Verified Preview publishes from `2026-05-22`:

- `publish_minting_txs_updater_spend_reference_script`
  - `66147eb8db6233c5dab80f7ac841d69ded3877031fc59b9590154295ca4c9514`
- `publish_bridge_minting_reference_script`
  - `681e3886faa891060831eb01c871246c38b111f460d418fa0eaf800c250094a0`

Both were observed with `valid_contract=true`.

## Bridge Seed Txs

Defaults aligned with the current bridge shell flow:

- `locking_txs_updater_seed_tx`
  - `seed_output_lovelace = 10000000`
- `minting_txs_updater_seed_tx`
  - `locking_txs_updater_output_lovelace = 3000000`
  - `bridge_collateral_lovelace = 20000000`

`minting_txs_updater_seed_tx` accepts either:

- `--unique-mint-source-utxo`
- `--locking-seed-tx-hash`

When `--locking-seed-tx-hash` is used, the operator derives `<hash>#1`.

Verified Preview submits from `2026-05-22`:

- `locking_txs_updater_seed_tx`
  - `6a33f2c4ea7f19c70d39ad9a1c7382614b67be7255f226871c18cb7f02354b10`
- `minting_txs_updater_seed_tx`
  - `3f5a468f5955f40dbf421b22ba05cf35a0a6f201c555c0409a53e9c3fd816603`

Both were observed with `valid_contract=true`.

## Bridge Minting

Two operator entrypoints exist:

- `preview invoke-cli-bridge-mint-flow`
- `preview invoke-cli-bridge-mint-tx`

### `invoke-cli-bridge-mint-flow`

Supported modes:

- From scratch:
  - with `--submit`
  - runs:
    - `phase1_setup cardano_transactions`
    - `phase2_verify cardano_transactions`
    - `bridge_mint_tx`
- Reuse mode:
  - pass `--tx-snapshot-phase2-tx-hash` or `--tx-snapshot-receipt-utxo`
  - skips phase1/phase2 and builds only `bridge_mint_tx`

`--skip-submit` is only valid in reuse mode because `bridge_mint_tx` needs an on-chain receipt.

Verified chain from `2026-05-22`:

- `phase1_setup_cardano_transactions`
  - `a77266e76856ccca06c66fa4cd94f431a83c740795aa993f26cca5440a2fc59a`
- `phase2_verify_cardano_transactions`
  - `7d189d5850e58a04322284f68da39518671a27dac4034118ab9cb6d072c05d85`
- `bridge_mint_tx`
  - `fb1f0159ed0870b6b0b86b9db1e661942a2179381f157c7a5a432c3db89d5e23`

All were observed with `valid_contract=true`.

Validated reuse-mode anchors:

- `stake_distribution_utxo`
  - `def4e678b30df75b850555d9982382e5ecf8d7ee370ba16084eb4d7d02c2a7a8#0`
- `locking_txs_updater_utxo`
  - `3f5a468f5955f40dbf421b22ba05cf35a0a6f201c555c0409a53e9c3fd816603#0`
- `locking_txs_updater_spend_reference_script_utxo`
  - `66147eb8db6233c5dab80f7ac841d69ded3877031fc59b9590154295ca4c9514#1`
- `bridge_minting_reference_script_utxo`
  - `681e3886faa891060831eb01c871246c38b111f460d418fa0eaf800c250094a0#1`

Validated artifact dir:

- `preview_phase12/bridge_minting/flow-cli-reuse-phase2/`

### `invoke-cli-bridge-mint-tx`

Standalone bridge tx command.

Requirements:

- on-chain `cardano_transactions` phase2 receipt
- on-chain `stake_distribution` UTxO
- on-chain `locking_txs_updater` UTxO
- on-chain locking-updater reference script UTxO
- on-chain bridge-minting reference script UTxO

Supported modes:

- `--skip-submit`
- `--submit`

Verified standalone `--skip-submit` run from `2026-05-22`:

- signed tx hash
  - `cccdf32a60e0e9929ca419729ddf397046a0371f5fc45a53c5b44b2d44b8fd08`
- artifact dir
  - `preview_phase12/bridge_minting/standalone-bridge-skip/`

Canonical on-chain tx inventory:

- `preview_phase12/successful-onchain-txs.json`

## Mithril / Proof Commands

`relayer sync-certificates` writes:

- `certificates/index.json`
- `certificates/aggregator_features.json`
- `certificates/aggregator_status.json`
- `certificates/<certificate-hash>.json`

`tx prove <transaction-hash>` writes:

- `proven_transactions/<transaction-hash>/aggregator_features.json`
- `proven_transactions/<transaction-hash>/aggregator_status.json`
- `proven_transactions/<transaction-hash>/proof_response.json`
- `proven_transactions/<transaction-hash>/certificate.json`
- `proven_transactions/<transaction-hash>/snapshot.json` when present
- `proven_transactions/<transaction-hash>/manifest.json`
- `proven_transactions/<transaction-hash>/snapshot_membership/`
- `proven_transactions/<transaction-hash>/tx_set_update/`

## Verification

Recent operator-side validation confirmed:

- `cargo test` passes
- Preview bridge and stake-distribution paths can resolve, patch, sign, and submit with current chain state

Cardanoscan Preview:

- `https://preview.cardanoscan.io/`
