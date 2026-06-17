# AGENTS.md

## Current State

- As of `2026-06-03`, the public `bridge.sh` flows were re-verified without
  sibling `../dolos` or `../uplc-turbo` checkouts present in the workspace:
  - the runtime now relies on:
    - installed `dolos 1.2.0`
    - repo-local `.tx3/dolos` scaffolding
    - local bridge helper crate:
      - `tools/patch_bridge_mint_tx/`
  - `fixed-bugs.md` now keeps only the still-relevant `cshell` fix
- As of `2026-06-03`, `./scripts/bridge.sh bootstrap --link` now pins the
  effective public runtime toolchain to:
  - `CSHELL_BIN=../cshell-0.14.0/target/debug/cshell`
  - `DOLOS_BIN=/home/lorenzo/.tx3/default/bin/dolos`
  through `.tools/env.sh`
- As of `2026-05-22`, the bridge no longer publishes a dedicated
  `publish_proof_receipt_reference_script` transaction.
- As of `2026-06-02`, `stake_distribution_genesis_tx` no longer relies on a
  placeholder genesis-certificate acceptance path:
  - `validators/stake_distribution.ak` still routes the bootstrap certificate
    through the Aiken mint validator, not through Halo2
  - `lib/mithril/verify_certificate.ak` now verifies the Mithril
    `GenesisSignature` with `aiken/crypto.verify_ed25519_signature`
  - `env/default.ak` now carries the decoded raw Ed25519 preview
    `genesis_verification_key` from Mithril's published
    `pre-release-preview/genesis.vkey`
- As of `2026-06-02`, `stake_distribution_genesis_tx` also no longer consumes
  a `proof_receipt` input:
  - the bootstrap lane is now authenticated only by the genesis-certificate
    Ed25519 verification path
  - `proof_receipt` remains required for
    `stake_distribution_standard_tx` and `bridge_mint_tx`
- As of `2026-06-02`, `phase12-all` no longer includes a genesis lane:
  - only `stake_distribution_standard` and `cardano_transactions` still run
    through `phase1_setup -> phase2_verify`
  - the single-case runner now rejects
    `PHASE12_PROOF_NAME=stake_distribution_genesis`
- As of `2026-06-02`, a dedicated Jubjub-on-Aiken feasibility spike was run:
  - file: `lib/mithril/jubjub_spike.ak`
  - scope: pure-Aiken field arithmetic, twisted-Edwards point checks, and
    scalar multiplication over Jubjub-like constants from Mithril upstream
  - outcome:
    - cheap curve-membership checks stayed small
    - scalar multiplication already exploded in cost before Poseidon or the
      full Schnorr transcript were added
  - practical conclusion:
    - `verify_jubjub_schnorr_signature` looks unsuitable as a near-term
      production path for `bridge-aiken`
- `ProofReceipt` UTxOs are still consumed as normal inputs where the
  downstream contract still depends on a Halo2-backed receipt. In the current
  bridge flow, the `ProofReceipt` validator is attached inline in:
  - `stake_distribution_standard_tx`
  - `bridge_mint_tx`
- `stake_distribution_genesis_tx` no longer consumes a `ProofReceipt` input;
  its trust anchor is the Mithril genesis certificate verified directly by the
  Aiken mint validator with the hardcoded Ed25519
  `genesis_verification_key`.
- The canonical current names for the bridge-side updater transactions are:
  - `publish_minting_txs_updater_spend_reference_script`
  - `minting_txs_updater_seed_tx`
- `./scripts/bridge.sh run --strict` was re-verified green after that
  simplification.
- As of `2026-06-02`, the sibling
  `circuit_jubjub_schnorr_verification/` project now exports a bridge-consumable
  Jubjub Schnorr fixture into `bridge-aiken`:
  - raw JSON:
    - `scripts/data/jubjub_schnorr_raw.json`
  - helper Aiken fixture:
    - `validators/tests/helpers/jubjub_schnorr_fixture.ak`
  - verifier key:
    - `lib/zk/jubjub_schnorr_verification_vk.ak`
  - local wrapper:
    - `lib/zk/jubjub_schnorr_verification.ak`
  - direct bridge-side verification test:
    - `validators/tests/jubjub_schnorr_fixture_test.ak`
- As of `2026-06-03`, `bridge-aiken` now also supports a dual genesis-certificate
  shape in Aiken:
  - `lib/mithril/certificate_signature.ak`
    - new variant:
      - `GenesisDualSignature { ed25519_signature, schnorr_signature }`
  - `validators/stake_distribution.ak`
    - when the certificate is dual, the mint validator now checks:
      - the legacy Ed25519 half through
        `lib/mithril/verify_certificate.ak`
      - a Groth16 Jubjub Schnorr proof through
        `lib/zk/jubjub_schnorr_verification.ak`
  - `validators/tests/stake_distribution_validator_test.ak`
    - now covers acceptance/rejection of the dual genesis path
  - `validators/tests/helpers/coherent_dual_genesis_fixture.ak`
    - now pins the honest test-only provenance of that dual path:
      - deterministic Mithril Ed25519 genesis signer
      - deterministic Mithril Schnorr genesis signer
      - Groth16 proof built from the same Schnorr witness
- As of `2026-06-03`, the dual-genesis Aiken path now transports the five
  Jubjub public inputs as ASCII-decimal bytes instead of direct Tx3 integers:
  - `validators/stake_distribution.ak`
    - `StakeDistributionMintRedeemer` now stores:
      - `jubjub_schnorr_message_base: ByteArray`
      - `jubjub_schnorr_verification_key_u: ByteArray`
      - `jubjub_schnorr_verification_key_v: ByteArray`
      - `jubjub_schnorr_signature_response: ByteArray`
      - `jubjub_schnorr_signature_challenge: ByteArray`
  - `lib/zk/jubjub_schnorr_verification.ak`
    - now parses those decimal ASCII bytes back into on-chain `Int` values
      immediately before `proof_verifies(...)`
  - the Aiken regression suite for:
    - `tests/jubjub_schnorr_fixture_test`
    - `tests/stake_distribution_validator_test`
    - `tests/verify_certificate_test`
    is green with that byte-based encoding
- As of `2026-06-03`, the experimental
  `./scripts/bridge.sh genesis_dual_signature` runtime flow is now green with
  the patched local `cshell` and the corrected Jubjub message-base modulus:
  - the old runtime error:
    - `value is not a valid number: number too large to fit in target type`
    was eliminated by moving the five dual Jubjub public inputs from runtime
    `Int` params to runtime `Bytes`
  - `scripts/lib/integration_common.sh`
    - `cshell_tx_invoke` now prefers the namespaced TII file generated by
      modern `trix build`:
      - `.tx3/tii/eryxcoop/zk-bridge/1.0.0/main.tii`
    - this avoids the stale compatibility file:
      - `.tx3/tii/main.tii`
  - the TII / `cshell` compatibility blocker is fixed locally in:
    - `../cshell-0.14.0/src/tx/common.rs`
  - with that patched binary:
    - `CSHELL_BIN=../cshell-0.14.0/target/debug/cshell`
    the runtime now completes end-to-end
  - the bridge-side Aiken fix that unblocked the mint path is:
    - `lib/zk/jubjub_schnorr_verification.ak`
    - `jubjub_base_field_modulus` corrected from
      `...84512` to `...84513`
  - the verified passing runtime tx hash is:
    - `72c1c486621b9c4fe9f306e55fc7c12296c67499b34889ea715f75f357a0c38f`
- As of `2026-06-03`, the local Tx3 toolchain versions directly verified here
  are:
  - `cshell 0.14.0`
  - `trix 0.25.1`
  - `tx3up 0.7.0`
  - `tx3c 0.21.0`
  - `dolos 1.2.0`
- As of `2026-06-03`, there is no newer official `cshell` release available
  than the one already installed here:
  - `tx3up check` on channel `stable` reports:
    - `You are up to date`
  - `https://api.github.com/repos/txpipe/cshell/releases/latest`
    reported:
    - `tag_name = v0.14.0`
    - `published_at = 2026-02-14T14:29:00Z`
  - no `cshell` upgrade was installed because no newer official release
    exists yet
- As of `2026-06-03`, `tx3up` channel `beta` is not currently usable on this
  machine for testing a newer `cshell`:
  - `TX3_CHANNEL=beta tx3up show`
    reports missing beta binaries
  - `TX3_CHANNEL=beta tx3up check`
    fails with:
    - `Error: parsing manifest file`
    - `EOF while parsing a value at line 1 column 0`
- As of `2026-06-03`, a minimal upstreamable fix for `cshell 0.14.0` was
  implemented locally in:
  - `../cshell-0.14.0/src/tx/common.rs`
  - it normalizes only these namespaced TII refs before `Protocol::from_json(...)`:
    - `tii#/$defs/Bytes`
    - `tii#/$defs/Address`
    - `tii#/$defs/UtxoRef`
  - into the legacy refs expected by the currently vendored `tx3-sdk`:
    - `core#Bytes`
    - `core#Address`
    - `core#UtxoRef`
  - the patch is covered there by unit tests:
    - `prepare_invocation_accepts_legacy_core_refs`
    - `prepare_invocation_accepts_namespaced_tii_refs`
    - `prepare_invocation_still_rejects_unknown_refs`
- As of `2026-06-03`, `./scripts/bridge.sh bootstrap --link` temporarily
  prioritizes that local patched `cshell` binary over any globally installed
  `cshell`:
  - file:
    - `scripts/bootstrap_dev_env.sh`
  - current fallback order for `cshell` is:
    1. `CSHELL_SOURCE_BIN`, if explicitly set
    2. `../cshell-0.14.0/target/debug/cshell`
    3. `command -v cshell`
  - this is intentionally temporary until the namespaced-TII fix is merged
    upstream in `txpipe/cshell` and a release newer than `v0.14.0` exists
- Historical notes below that mention
  `publish_proof_receipt_reference_script`,
  `proof_receipt_reference_script_utxo`, or the old Preview/Lace
  proof-receipt export flow are archival unless a newer note explicitly
  says otherwise. El repo ya no conserva
  `../zk-bridge-operator/preview_tx_artifacts/publish-proof-receipt-reference-script/`.

This file records only facts that were directly verified while working in
`bridge-aiken`. It intentionally avoids hypotheses.

`MITHRIL_POC_RUNBOOK.md` is the repo-local execution guide for the verified
`phase1` / `phase2`, stake-distribution, and bridge flows in Aiken and
`tx3/dolos`, including these integrated end-to-end scripts:
- `scripts/submit_phase1_phase2_transactions_single_case.sh`
- `scripts/mithril_stake_distribution.sh`
- `scripts/bridge_minting.sh`

## Latest Verified Facts

- `aiken check -m tests/jubjub_schnorr_fixture_test -m tests/stake_distribution_validator_test -m tests/verify_certificate_test`
  now passes with the dual Jubjub public inputs encoded as decimal ASCII bytes:
  - total:
    - `34 passed`
    - `0 failed`
- `scripts/python/prepare_genesis_dual_signature_args.py`
  now emits the five dual Jubjub public inputs as `0x...` hex wrappers around
  ASCII-decimal text, for example:
  - `dual_jubjub_schnorr_message_base`
    - `0x333833303338...`
- `scripts/python/prepare_mithril_stake_distribution_args.py`
  was updated the same way for consistency with the bridge-side dual genesis
  encoding.
- `aiken build` and `./.tools/bin/trix build -v` both succeed after that
  bridge-side encoding change.
- `./scripts/preflight_genesis_dual_signature.sh --output-dir ...`
  still passes after the byte-encoding migration.
- The local `cshell` patch now resolves the namespaced-TII param-typing bug:
  - `cargo test tx::common -- --nocapture`
  - `cargo test -- --nocapture`
    both pass in `../cshell-0.14.0`
- The dedicated repro in `../tx3_cshell_invalid_param_type_repro` no longer
  fails with:
  - `invalid param type`
  when run against:
  - `../cshell-0.14.0/target/debug/cshell`
- The direct runtime command
  `CSHELL_BIN=../cshell-0.14.0/target/debug/cshell ./scripts/bridge.sh genesis_dual_signature --output-dir artifacts/ci-local/genesis-dual-runtime-cshell-patched-3`
  now passes end-to-end:
  - it no longer fails on the i128-size error
  - it no longer fails on `invalid param type`
  - it no longer fails during mint validation
  - verified output:
    - `Genesis dual-signature flow passed.`
    - `stake_distribution_genesis_tx hash: 72c1c486621b9c4fe9f306e55fc7c12296c67499b34889ea715f75f357a0c38f`
- A new Aiken regression now mirrors the runtime preview bundle through the
  real mint validator:
  - `tests/helpers/preview_dual_genesis_fixture.ak`
  - `tests/helpers/certificates/stake_distribution_certificates.ak`
    - `preview_dual_genesis_certificate()`
  - `tests/helpers/stake_distribution_asset_redeemer.ak`
    - `preview_sd_asset_redeemer_for_dual_genesis_certificate()`
  - `tests/helpers/stake_distribution_tx.ak`
    - `preview_stake_distribution_tx_for_dual_genesis_certificate()`
  - `tests/stake_distribution_validator_test.ak`
    - `accepts_preview_dual_genesis_certificate_through_real_mint_entrypoint`

- The Mithril genesis-certificate verification path used by
  `stake_distribution_genesis_tx` is now a real Ed25519 check instead of a
  stub:
  - `lib/mithril/verify_certificate.ak`
    - `verify_with_genesis_vkey(...)` now decodes the ASCII-hex
      `GenesisSignature` payload back to raw 64-byte signature bytes and calls
      `aiken/crypto.verify_ed25519_signature`
  - `env/default.ak`
    - `genesis_verification_key` now stores the decoded raw 32-byte Ed25519
      preview key corresponding to Mithril's published
      `pre-release-preview/genesis.vkey`
- Direct Aiken verification checks now cover that path:
  - `aiken check -m tests/verify_certificate_test`
  - accepts the fixture genesis certificate with the real preview key
  - rejects the same certificate with a tampered genesis signature
  - rejects the same certificate with an incorrect genesis verification key
- The stake-distribution validator tests now also pin the runtime entrypoint
  behavior for a bad genesis signature:
  - `aiken check -m tests/stake_distribution_validator_test`
  - rejects `stake_distribution_genesis_tx` when the redeemer carries a
    tampered `GenesisSignature`
- `stake_distribution_genesis_tx` no longer requires the genesis `phase2`
  receipt:
  - `validators/stake_distribution.ak`
    - mint path no longer calls `proof_receipt.has_input(...)`
  - `main.tx3`
    - `stake_distribution_genesis_tx` no longer takes
      `sd_genesis_receipt_utxo`
    - the tx no longer spends a `ProofReceipt` input
    - the user change output is now computed from `source` alone
  - `scripts/python/prepare_mithril_stake_distribution_args.py`
    - genesis args no longer emit `sd_genesis_receipt_utxo`
  - `scripts/mithril_stake_distribution.sh`
    - no longer depends on any genesis-specific `phase2` manifest field
      to submit `stake_distribution_genesis_tx`
- The updated Aiken tests directly verified the new genesis contract:
  - `aiken check -m tests/stake_distribution_validator_test`
    - accepts genesis without any `phase2` receipt input
    - accepts genesis even when a `phase2` receipt exists only as
      `reference_input`
    - still rejects tampered genesis signatures and tampered genesis
      `signed_message`s
- The dual genesis-certificate path is now directly covered in Aiken tests:
  - `aiken check -m tests/stake_distribution_validator_test`
    - accepts the coherent test-only `GenesisDualSignature`
    - rejects a tampered embedded Schnorr signature
    - rejects a tampered Groth16 Schnorr public-input challenge
    - rejects a mismatched `signed_message -> message_base` binding
  - honest test provenance now lives in:
    - `validators/tests/helpers/coherent_dual_genesis_fixture.ak`
  - separation of concerns:
    - runtime mint validator still uses `env.genesis_verification_key`
      and the preview trust anchor
    - tests for the dual experiment now call
      `stake_distribution.experimental_dual_genesis_certificate_verifies(...)`
      with explicit Mithril test-only trust anchors
  - current bridge-side binding for the Schnorr half:
    - the Groth16 proof is now bound to:
      - the trusted Jubjub verification key coordinates
      - the response/challenge halves of `schnorr_signature`
      - the certificate `signed_message`, via `message_base`
- `main.tx3`
  - `stake_distribution_genesis_tx` now threads:
    - `certificate_ed25519_signature`
    - `certificate_schnorr_signature`
    - `jubjub_schnorr_proof_pi_a/pi_b/pi_c`
    - the five Jubjub proof public inputs
- `scripts/python/prepare_mithril_stake_distribution_args.py`
  - now emits those extra genesis dual/Groth16 fields
  - current provenance split is explicit:
    - Ed25519 half from `scripts/data/mithril_stake_distribution_genesis.json`
    - Schnorr/proof half from `scripts/data/jubjub_schnorr_raw.json`
- The follow-up runtime failure
  `stake_distribution_standard_tx -> tx was not accepted: script witness is missing`
  is now fixed:
  - root cause:
    - `scripts/python/sync_phase_scripts_to_tx3.py` could mis-target the
      `stake_distribution_standard_tx` witness replacement and leave the first
      `cardano::plutus_witness` out of sync with the actually applied
      `stake_distribution_validator_spend` blueprint
  - verified fix:
    - the sync replacement for the first
      `stake_distribution_standard_tx` witness now anchors correctly before the
      second `ProofReceipt` witness block
  - verified runtime consequence:
    - `./scripts/bridge.sh stake-distribution` passes again after the genesis
      no-receipt change
    - verified hashes:
      - `stake_distribution_genesis_tx`:
        `286f59785a7edf0ea76c59f242d0829a01436c444f4bec581c7462e64d5ebf3f`
      - `stake_distribution_standard_tx`:
        `b93c95f43df097c13108cac9e12c75764965ca31bef11fac1eb695b6cfff16e4`
  - run dir used for that verification:
    - `artifacts/repro-stake-standard-witness`
- The standalone Jubjub spike was measured with:
  - `aiken check -m mithril/jubjub_spike`
  - verified execution-unit samples:
    - `generator_is_on_curve`
      - `cpu = 6,372,003`
      - `mem = 23,194`
    - `scalar_mul_generator_small_benchmark`
      - `cpu = 5,500,224,653`
      - `mem = 17,580,993`
    - `scalar_mul_vk_response_benchmark`
      - `cpu = 145,166,383,906`
      - `mem = 463,499,623`
    - `subgroup_order_benchmark`
      - `cpu = 143,339,426,983`
      - `mem = 457,630,664`
  - interpretation:
    - even this incomplete prototype is already orders of magnitude above a
      reasonable on-chain direction, and it still omits Poseidon plus the full
      Mithril genesis Schnorr verification flow

- The current strict end-to-end wrapper now passes with the single shared
  `publish_phase1_reference_script` design all the way through the bridge
  minting lane:
  - `./scripts/bridge.sh run --strict`
  - verified final `bridge_mint_tx hash`:
    `a0d68fcdc6080d6001db82f681ee6790cc27f676977a39ca0722ef76f9ed7c32`
- In that verified strict run:
  - `publish_phase1_reference_script` was shared once across all three
    `phase12-all` domains
  - the stake-distribution and bridge-minting txs also completed on the same
    integrated wrapper path
  - the final `bridge-flow-summary.csv` contained exactly one
    `publish_phase1_reference_script` row
- The bridge-side post-`phase12-all` lane now requires two explicit UTxO
  rules that were directly verified in the latest passing strict run:
  - the synthetic `source_utxo`s used after `phase12-all` must be funded above
    the real `min_amount` queries; the verified local fix was to raise those
    dedicated source refs to `100_000_000` lovelace
  - the shared local Dolos lane is not a reliable place to chain freshly
    produced outputs directly into the next tx's `collateral`, so the current
    verified wrapper uses dedicated stable synthetic collateral UTxOs for:
    - `stake_distribution_standard_tx`
    - `locking_txs_updater_seed_tx`
    - `locking_txs_updater_genesis_tx`
    - `bridge_mint_tx`
- Rule for future operator-facing commands that consume bridge tx outputs:
  - do not encode one historical tx hash or UTxO ref directly into the command
    implementation
  - if a later step depends on a prior successful tx, expose that dependency as
    an explicit parameter or derive it from a persistent state artifact
  - this matters especially for Preview flows where `phase1_setup`,
    `phase2_verify`, and later bridge txs must be rerunnable against different
    successful prior txs over time

- The legacy single-proof `mithril_stm_artifact.json` has been retired
  as a wire-format output. The canonical bundle
  `bridge-compatible-mithril-stm-bundle.json` is the only artifact the
  builder writes and the only path the downstream flows consume. The
  Rust binary `export_mithril_stm_proof_export --check <path>` now validates
  the bundle (one virtual `MithrilStmProofExport` reconstructed per
  `proofs.<domain>` entry) via `validate_compatible_bundle_file`.
  Historical entries below may still mention the retired
  `mithril_stm_artifact.json` path as evidence of how the harness
  evolved.
- `bridge-aiken` is now integrated with the shared circuit/operator world where
  the canonical transaction identity is the real Cardano `transaction_hash`.
- Bridge-facing compatibility names are intentionally preserved for now:
  - `locking_tx_hash`
  - `locking_tx_hash_hex`
- Those names now carry the canonical Cardano tx hash, not a bridge-derived
  digest.
- `scripts/python/sync_bridge_zk_fixture.py` now regenerates the bridge zk
  fixture from:
  - `../circuit_transaction_snapshot`
  - `../circuit_inclusion_exclusion`
  using `bridge_mint_raw.locking_tx_hash_hex` as the canonical tx hash input
  for both circuits.
- `scripts/python/prepare_mithril_bridge_minting_args.py` no longer recomputes
  a bridge-derived locking hash; it now threads
  `bridge_mint_raw.locking_tx_hash_hex` through as the runtime source of truth.
- The old Python helper that recomputed a bridge-derived locking hash has been
  removed after its callers were migrated away from that model.
- `validators/tests/helpers/bridge_fixture.ak` was regenerated after the
  statement migration and now consumes packed snapshot-membership inputs named
  `cardano_tx_hash_*` in the source JSON while preserving legacy Aiken-facing
  compatibility names.
- The refreshed zk fixture checks now pass:
  - `python3 scripts/python/sync_bridge_zk_fixture.py --check --skip-test-fixture-alignment`
  - `python3 scripts/python/check_test_fixture_alignment.py`
- The refreshed Aiken test modules now pass:
  - `aiken check -m tests/snapshot_membership_test`
  - `aiken check -m tests/tx_set_update_test`
  - `aiken check -m tests/bridge_fixture_test`
  - `aiken check -m tests/minting_validator_test`
  - `aiken check -m tests/txs_updater_validator_test`
- A direct wrapper-level run now also passes with the canonical tx-hash model
  threaded through the bridge fixture refresh path:
  - `./scripts/bridge.sh run --proof-export-bundle run_outputs/mithril-poc/latest/bridge-compatible-mithril-stm-bundle.json --output-dir run_outputs/cardano-tx-hash-run-smoke --clean --skip-aiken-check --skip-preflight`
- That verified run advanced through:
  - bridge zk fixture refresh
  - runtime artifact rebuild after fixture refresh
  - `phase12-all`
  - stake distribution
  - bridge mint
- The verified final `bridge_mint_tx hash` from that run is:
  - `7a8317cfd3e2dad29e1d56db39085765c28e61d1524f159c0b1571f107b87b9a`
- Additional deterministic cache points now exist in the live `bridge.sh run`
  path:
  - `run_outputs/<run>/run-aiken-check.inputs.sha256`
  - `run_outputs/<run>/preflight.inputs.sha256`
  - `run_outputs/<run>/bridge-minting/bridge-zk-fixture.inputs.sha256`
- `scripts/run_mithril_poc.sh` now skips `aiken check` when the fingerprint of:
  - `aiken.toml`
  - `aiken.lock`
  - `plutus.json`
  - `lib/`
  - `validators/`
  - `env/`
  remains unchanged.
- `scripts/preflight_mithril_poc.sh` now skips all three deterministic
  preflight stages when the fingerprint of:
  - the runtime artifact
  - the canonical exported artifact when present
  - `scripts/data/bridge_mint_raw.json`
  - `scripts/data/mithril_poc_reference_snapshot.json`
  - `validators/tests/helpers/bridge_fixture.ak`
  - `env/default.ak`
  - the preflight Python scripts
  - `../plutus-halo2-verifier-gen/src`
  remains unchanged.
- `scripts/bridge_minting.sh` now skips:
  - initial bridge fixture verification
  - bridge fixture refresh
  - post-refresh bridge fixture verification
  when the bridge-zk fingerprint remains unchanged.
- Nested flow startup checks are no longer repeated inside the same parent run.
  The parent flow now passes:
  - `BRIDGE_SKIP_FLOW_CHECKS=1`
  into `preflight`, `bridge`, `stake-distribution`, `phase12-all`, and
  `phase12` child invocations.
- A sequential verification of preflight cache passed with:
  - `./scripts/bridge.sh preflight --proof-export-bundle run_outputs/default-run-smoke/bridge-compatible-mithril-stm-bundle.json --output-dir run_outputs/cache-preflight-smoke`
  and the second sequential run skipped all three preflight stages with
  `fingerprint unchanged`.
- A repeated integrated run passed with:
  - `./scripts/bridge.sh run --output-dir run_outputs/cache-run-smoke --skip-preflight --clean`
  - `./scripts/bridge.sh run --output-dir run_outputs/cache-run-smoke --skip-preflight`
- On that second repeated run, these skips were observed before runtime tx
  submission resumed:
  - canonical artifact build
  - `aiken check`
  - bridge zk fixture verify/refresh/re-verify
  - `SYNC_SCOPE=all` Tx3 sync
  - sibling Dolos build
  - nested workspace/tooling checks in child flows
- The live operator-facing docs were refreshed to match the current workflow:
  - `README.md`
  - `README_MITHRIL.md`
  - `MITHRIL_POC_RUNBOOK.md`
  - `scripts/README.md`
  - `BRIDGE_FLOW_DIAGRAM.md`
  - `validators/tests/README.md`
- Those docs now explicitly reflect:
  - three Mithril proof domains / three receipts
  - proof receipts consumed as normal inputs
  - tx snapshot root as a shared validated source of truth
  - stage traces and deterministic cache reuse in the main run path
- A later cleanup pass also reduced documentation overlap:
  - `README.md` remains the short operator-facing entrypoint
  - `MITHRIL_POC_RUNBOOK.md` now focuses on verified runtime behavior, outputs,
    drift checks, and key files
  - `README_MITHRIL.md` now focuses only on Mithril design decisions
  - `scripts/README.md` now declares itself a technical script reference, not a
    second runbook
- `bridge-flow-summary.csv` no longer emits `N/A,N/A` for the runtime script
  transactions that should have execution units.
- The fixes that removed those `N/A` values were:
  - `scripts/python/tx_publish_summary.py`
    - phase2 runtime probe fallback now also applies to namespaced labels for
      the remaining `phase12` domains
  - `scripts/bridge_minting.sh`
    - the generated CSV now keeps only the transactions that are still part of
      the runtime bridge flow
    - the removed genesis-specific `phase12` rows are no longer emitted
  - `scripts/mithril_stake_distribution.sh`
    - console summaries no longer include the removed proof-receipt
      reference-script publish artifact
- Verified outcome:
  - `bridge-flow-summary.csv` now has execution units for:
    - `phase2_verify_*`
    - `stake_distribution_genesis_tx`
    - `stake_distribution_standard_tx`
    - `locking_txs_updater_genesis_tx`
    - `bridge_mint_tx`
  - `0,0` remains only on publish / scriptless transactions, which is expected
    and currently accepted for this report
- Python-side Mithril artifact proof loaders are now resilient to callers
  passing the exported artifact path instead of the runtime bundle path:
  - `scripts/python/mithril_stm_proof_export_bundle_certificates.py`
    now resolves `mithril_stm_artifact.json` to its sibling
    `bridge-compatible-mithril-stm-bundle.json` when present
- Verified checks after that loader hardening:
  - `python3 scripts/python/sync_bridge_zk_fixture.py --check --proof-export-bundle run_outputs/default-run-smoke/mithril_stm_artifact.json`
  - `python3 scripts/python/sync_bridge_zk_fixture.py --check --proof-export-bundle run_outputs/default-run-smoke/bridge-compatible-mithril-stm-bundle.json`
  both pass
- `run_mithril_poc.sh`, `preflight_mithril_poc.sh`, and
  `build_bridge_compatible_mithril_stm_proof_export_bundle.sh` now also guard against
  stale cached runtime bundles from the old schema:
  - if `bridge-compatible-mithril-stm-bundle.json` exists but lacks `proofs.*`,
    the flow no longer reuses it silently
  - `run` / `preflight` now force a rebuild of the canonical artifact family in
    that case
  - the artifact builder itself now treats a bundle without `proofs.*` as an
    invalid cached output set
- Verified recovery path:
  - `run_outputs/mithril-poc/latest/bridge-compatible-mithril-stm-bundle.json`
    was observed in a stale no-`proofs` state
  - after the guard was added, `./scripts/bridge.sh run --skip-aiken-check`
    started by rebuilding the canonical artifact instead of reusing the stale
    bundle
  - after rebuild, `./scripts/bridge.sh preflight --proof-export-bundle run_outputs/mithril-poc/latest/bridge-compatible-mithril-stm-bundle.json --output-dir run_outputs/mithril-poc/latest`
    passed
- The default `run` path is now verified end-to-end with no skip flags:
  - `./scripts/bridge.sh run --output-dir run_outputs/default-run-smoke --clean`
  - exited with code `0`
- That default run completed these stages successfully:
  - canonical artifact build
  - `aiken check`
  - preflight
  - `phase12-all`
  - stake distribution
  - bridge mint
- The verified final `bridge_mint_tx hash` from that default run is:
  - `0b626e1d503f102be8180118f4a4ff6abbbb3e95d30bb3b5c1606e355eff7763`
- The last blocker for the default `run` path was stale test data in:
  - `validators/tests/helpers/certificates/cardano_transactions.ak`
- That file now uses this verified
  `CardanoTransactionsMerkleRoot` / signed-message-aligned root:
  - `0xadd9df32ad38901508e47043e836d8bb44d558900979426630ca0a2f9baa7366`
- After that fixture alignment, these checks both passed again:
  - `timeout 180 aiken check -m tests/snapshot_membership_test`
  - `timeout 300 aiken check`
- Shared script-side binary resolution now lives in:
  - `scripts/lib/tooling_common.sh`
- Dolos-specific runtime/source-tree separation now lives in:
  - `scripts/lib/dolos_common.sh`
- That helper currently separates:
  - `DOLOS_BIN` for the executable used to run the daemon
  - optional `DOLOS_CARGO_MANIFEST` only for explicit sibling-source builds
  - `DOLOS_DEVNET_DIR` for repo-local `.tx3/dolos` genesis bootstrap
- `scripts/submit_phase1_phase2_transactions_single_case.sh` now requires:
  - a resolved `DOLOS_BIN`
  - a resolved `DOLOS_DEVNET_DIR`
- `scripts/bridge_minting.sh` now requires:
  - a resolved `DOLOS_BIN`
  - the local helper crate `tools/patch_bridge_mint_tx/` for
    `patch_bridge_mint_tx`
    - when future flows need to patch `Spend`, `Mint`, or other redeemers,
      extend that same multi-redeemer entrypoint instead of cloning a new bin
    - hard rule: no scripted bridge tx may be submitted until that patch path
      has been fed measured ex-units for the exact tx body being submitted
- `scripts/python/bootstrap_tx3_scaffolding.py` now honors:
  - `DOLOS_DEVNET_DIR`
  and defaults to repo-local `.tx3/dolos`.
- Repo-local tooling bootstrap now lives in:
  - `scripts/bootstrap_dev_env.sh`
- Supported sibling-workspace validation now lives in:
  - `scripts/check_workspace_layout.sh`
- Local command / Python dependency validation now lives in:
  - `scripts/check_local_tooling.sh`
- Repo-local Python dependency metadata now lives in:
  - `pyproject.toml`
- Repo-local uv lockfile now lives in:
  - `uv.lock`
- Repo-local uv virtual environment now lives in:
  - `.venv/`
- En una sesión posterior, `.tx3/cshell/cshell.toml` quedó con estado
  Preview-only:
  - `wallets = []`
  - provider `trix-preview`
  y eso rompió `./scripts/bridge.sh run --strict` con:
  - `Provider not found`
  al llegar a `Submitting publish_phase1_reference_script`
- La causa verificada fue que `scripts/python/prepare_tx3_dolos_env.py`
  copiaba el store mutable de `.tx3/cshell/cshell.toml` al tmp runtime y luego
  `integration_common.sh` seguía invocando:
  - `--provider trix-local`
  - `--signers bob`
  que ya no existían en ese store Preview-only
- Fix aplicado:
  - `prepare_tx3_dolos_env.py` ahora sintetiza siempre un `cshell.toml`
    temporal desde la plantilla local checked-in (`CSHELL_TOML` de
    `bootstrap_tx3_scaffolding.py`) en vez de depender del contenido actual de
    `.tx3/cshell/cshell.toml`
- Verificación puntual corrida:
  - el `cshell.toml` temporal regenerado vuelve a contener:
    - wallet `bob`
    - wallet `charlie`
    - wallet `alice`
    - provider `trix-local`
    con los puertos runtime reescritos
- Regla operativa vigente:
  - el lane local (`bridge.sh run/phase12/...`) debe ser inmune al estado
    Preview/manual de `.tx3/cshell/`
  - `.tx3/cshell/cshell.toml` puede usarse para trabajo interactivo Preview,
    pero no debe considerarse fuente de verdad del tmp store local
- `pyproject.toml` currently declares:
  - `cbor2`
- `scripts/check_local_tooling.sh` now also validates minimum versions for:
  - `aiken >= 1.1.21`
  - `uv >= 0.11.0`
- `scripts/check_local_tooling.sh` currently supports these flows:
  - `all`
  - `check`
  - `run`
  - `preflight`
  - `artifact`
  - `phase12`
  - `stake-distribution`
  - `bridge`
  - `bootstrap`
- That tooling checker currently validates combinations of:
  - `aiken`
  - `python3`
  - `cargo`
  - `curl`
  - `lsof`
  - `trix`
  - `cshell`
  - `uv`
  - Python module `cbor2`
- The public runner scripts now call `check_local_tooling.sh` early for their
  corresponding flows, so missing commands or Python packages fail fast before
  the main flow starts.
- `uv --version` now succeeds in this workspace and reports:
  - `uv 0.11.7 (Homebrew 2026-04-15 aarch64-apple-darwin)`
- Running `uv lock` in `bridge-aiken/` succeeded and generated:
  - `uv.lock`
- Running `uv sync` in `bridge-aiken/` succeeded and created:
  - `.venv/`
- Running `.venv/bin/python --version` in `bridge-aiken/` succeeded and
  reports:
  - `Python 3.14.4`
- Running `/usr/bin/python3 --version` in this workspace succeeded and reports:
  - `Python 3.9.6`
- The script-side `PYTHON_BIN` resolution now prefers:
  - `PYTHON_BIN`
  - `bridge-aiken/.venv/bin/python`
  - `PATH`
- That workspace checker currently supports these flows:
  - `all`
  - `check`
  - `run`
  - `preflight`
  - `artifact`
  - `phase12`
  - `stake-distribution`
  - `bridge`
  - `bootstrap-tx3`
- That checker currently validates:
  - sibling repo presence for `../plutus-halo2-verifier-gen` when required by
    the selected flow
  - repo-local Dolos devnet genesis templates under `.tx3/dolos/` when
    required
  - absence of personal absolute paths in the checked operational scripts/docs
- Running `scripts/check_workspace_layout.sh` succeeded in this workspace for:
  - `--flow phase12`
  - `--flow proof-export-bundle`
  - `--flow check`
- That bootstrap currently creates:
  - `.tools/bin/trix`
  - `.tools/bin/cshell`
  - `.tools/env.sh`
- The bootstrap currently supports:
  - `--check`
  - `--link`
  - `--copy`
  - `--force`
- The bootstrap currently resolves source binaries in this order:
  - `TRIX_SOURCE_BIN` / `CSHELL_SOURCE_BIN`
  - `PATH`
- The bootstrap currently exports `DOLOS_BIN` in `.tools/env.sh` using:
  - `DOLOS_SOURCE_BIN`, if explicitly set
  - otherwise `PATH`
- Sourcing `.tools/env.sh` after bootstrap is optional convenience for the
  current shell; the public scripts already prefer `.tools/bin/*` directly.
- That helper currently resolves tools in this order:
  - explicit environment variable such as `AIKEN_BIN`, `PYTHON_BIN`,
    `CARGO_BIN`, `TRIX_BIN`, `CSHELL_BIN`, or `DOLOS_BIN`
  - conventional repo-local or sibling locations when configured by the caller
  - `PATH`
- `scripts/submit_phase1_phase2_transactions_single_case.sh`,
  `scripts/sync_phase_scripts_to_tx3.sh`,
  `scripts/bridge_minting.sh`,
  `scripts/mithril_stake_distribution.sh`,
  `scripts/run_mithril_poc.sh`,
  `scripts/preflight_mithril_poc.sh`, and
  `scripts/build_bridge_compatible_mithril_stm_proof_export_bundle.sh`
  now source `scripts/lib/tooling_common.sh`.
- `scripts/run_mithril_poc.sh`,
  `scripts/preflight_mithril_poc.sh`,
  `scripts/build_bridge_compatible_mithril_stm_proof_export_bundle.sh`,
  `scripts/submit_phase1_phase2_transactions_single_case.sh`,
  `scripts/mithril_stake_distribution.sh`, and
  `scripts/bridge_minting.sh`
  now fail early through `scripts/check_workspace_layout.sh` when the expected
  runtime workspace contract is missing.
- Those scripts now resolve `aiken`, `python3`, `cargo`, `trix`, `cshell`,
  and/or `dolos` once near startup instead of mixing hardcoded paths with
  direct command calls throughout the flow.
- `scripts/lib/integration_common.sh` now respects `PYTHON_BIN` for its Python
  helper invocations instead of hardcoding `python3`.
- The recommended automated runbook check is now `./scripts/bridge.sh run --strict`
  (preflight pinned at the front of the pipeline, before `aiken check`).
- Unified operator entrypoint now lives at:
  - `scripts/bridge.sh`
- Short top-level onboarding now lives at:
  - `README.md`
- `scripts/bridge.sh` currently supports these subcommands:
  - `bootstrap`
  - `workspace`
  - `tooling`
  - `doctor`
  - `run` (accepts `--strict` for the recommended CI-like validation)
  - `artifact`
  - `preflight`
  - `phase12`
  - `stake-distribution`
  - `bridge`
  - `sync`
- The intended short operator path is now:
  - `./scripts/bridge.sh bootstrap --link`
  - `uv sync`
  - `./scripts/bridge.sh doctor check`
  - `./scripts/bridge.sh run --strict`
- `README.md` now documents the clean-checkout onboarding path in 3 commands:
  - `./scripts/bridge.sh bootstrap --link`
  - `uv sync`
  - `./scripts/bridge.sh run --strict`
- `README.md` currently defines the short stable interface as:
  - `bootstrap`
  - `run --strict`
  - `run`
- `MITHRIL_POC_RUNBOOK.md` now starts with a clean-checkout "Getting Started"
  section that aligns with the wrapper workflow:
  - `./scripts/bridge.sh bootstrap --link`
  - `uv sync`
  - `./scripts/bridge.sh doctor check`
  - `./scripts/bridge.sh run --strict`
- `README_MILESTONE_5.md` is no longer needed once its useful execution/state
  details are folded into `README.md` and `MITHRIL_POC_RUNBOOK.md`.
- `MITHRIL_POC_RUNBOOK.md` now keeps the install section intentionally compact:
  - one minimal dependency list
  - one `command -v ...` quick check
  - one short list of install commands for `uv`, `aiken`, Rust/Cargo,
    and `tx3up`
- CI reproducibility workflow now lives at:
  - `../.github/workflows/bridge-aiken-repro.yml`
- That workflow currently validates:
  - the sibling-workspace contract through `scripts/check_workspace_layout.sh`
  - guardrails against personal paths and `~/.tx3/stable/bin` regressions
  - shell-script syntax with `bash -n`
  - clean-checkout bootstrap using repo-local `trix` / `cshell` shims
  - `./scripts/bridge.sh bootstrap --check`
  - `uv sync`
  - `./scripts/tests/smoke_script_helpers.sh`
  - `./scripts/tests/smoke_sync_restore.sh`
  - `./scripts/bridge.sh doctor check` as a main-flow readiness smoke test
  - artifact-flow readiness checks
  - canonical artifact build plus `./scripts/bridge.sh preflight`
- Stage E of that second-pass plan is now partially reflected in CI:
  - fast guardrails are separated from heavier smoke tests
  - CI now has a dedicated `bootstrap` + `doctor check` smoke path
  - CI now has a dedicated `artifact` + `preflight` smoke path
- Stage F of that second-pass plan is now partially reflected in the script
  surface:
  - `bridge.sh` is now the explicit primary public entrypoint
  - direct operational scripts now warn that they are compatibility/debug
    entrypoints and print the preferred `bridge.sh` command
- The Mithril workflow still models proof receipts as normal spending inputs,
  but it no longer publishes a dedicated `ProofReceipt` reference script.
- `main.tx3` no longer defines `publish_proof_receipt_reference_script`.
- `stake_distribution_genesis_tx`, `stake_distribution_standard_tx` and
  `bridge_mint_tx` now attach the `ProofReceipt` validator inline through a
  regular `cardano::plutus_witness`.
- `scripts/python/sync_phase_scripts_to_tx3.py` now syncs the compiled
  `ProofReceipt` code into those inline witnesses.
- `scripts/mithril_stake_distribution.sh` and
  `scripts/bridge_minting.sh` no longer thread
  `PROOF_RECEIPT_REFERENCE_SCRIPT_UTXO` through `session.env`.
- `scripts/python/prepare_mithril_stake_distribution_args.py` and
  `scripts/python/prepare_mithril_bridge_minting_args.py` no longer require
  `proof_receipt_reference_script_utxo`.
- `scripts/python/prepare_mithril_bridge_minting_args.py` also now sources:
  - `tx_snapshot_certificate_protocol_message_cardano_transactions_merkle_root`
    from refreshed `bridge_mint_raw.json`
  instead of the raw Mithril artifact certificate root, while keeping the
  certificate signed message sourced from the artifact path.
- `validators/proof_receipt.ak` now has an Aiken-valid spend arity:
  - `spend(_datum: Option<ProofReceiptDatum>, _redeemer: Int, _own_ref: OutputReference, _tx: Transaction)`
- Running `aiken build` in `bridge-aiken/` succeeded after that validator-arity
  fix.
- Running `timeout 240 aiken check` in `bridge-aiken/` succeeded with:
  - all tests passing at that time
- Running `./scripts/bridge.sh bridge` in `bridge-aiken/` succeeded using the
  generated multi-proof Mithril artifact and completed the full bridge flow,
  including:
  - three separate `phase1/phase2` receipt generations
  - both stake-distribution transactions
  - locking-txs updater setup
  - final `bridge_mint_tx`
- Running
  `./scripts/bridge.sh run --output-dir run_outputs/phase6-smoke --skip-aiken-check --skip-preflight --clean`
  in `bridge-aiken/` succeeded end-to-end and produced:
  - `run_outputs/phase6-smoke/bridge-compatible-mithril-stm-bundle.json`
  - `run_outputs/phase6-smoke/mithril_stm_artifact.json`
- `PLAN_WORKFLOW_MITHRIL_REALISTA.md` no longer tracks the implementation
  stages; it now serves as a short backlog of remaining quality/robustness work
  for the Mithril workflow.
- A conservative dead-code cleanup was applied to the Mithril Python helpers:
  - removed `build_genesis_args_from_artifact(...)`
  - removed `build_standard_args_from_artifact(...)`
  - removed legacy artifact helpers:
    - `artifact_statement(...)`
    - `validate_legacy_statement_alignment(...)`
    - `load_artifact_certificates(...)`
- `scripts/python/check_mithril_poc_preflight.py` now reads legacy
  `artifact.certificates.parent/child` directly when needed and uses the
  domain-specific builders/loaders for the live multi-proof checks.
- Verification after that cleanup:
  - `python3 -m py_compile` passed on the touched Python files
  - `scripts/python/check_mithril_poc_preflight.py` passed against the current
    artifact when run with a temporary snapshot
  - `./scripts/bridge.sh preflight --proof-export-bundle ...` still reports snapshot drift
    against the checked-in canonical snapshot, which is a data drift issue and
    not a broken import or removed-helper regression
- Quality/robustness debt 2 ("reduce unnecessary recomputation") is now
  addressed by live caches:
  - `scripts/build_bridge_compatible_mithril_stm_proof_export_bundle.sh`
    - caches the generated artifact family behind
      `bridge-compatible-mithril-stm-artifact.inputs.sha256`
    - skips the heavy Rust export pipeline when the relevant fixture/Rust inputs
      did not change and all expected outputs already exist
  - `scripts/sync_phase_scripts_to_tx3.sh`
    - caches sync state per `SYNC_SCOPE` under `.tx3/cache/sync-<scope>.sha256`
    - skips the full Aiken/sync round when inputs for that scope are unchanged
      and the TII surface is already fresh
  - `scripts/lib/dolos_common.sh`
    - caches sibling Dolos builds behind
      `../dolos/target/bridge-aiken-dolos-build.sha256`
    - skips `cargo build -p dolos` when the tracked Rust/Cargo inputs are
      unchanged
- Quality/robustness debt 3 ("improve stage observability") is now addressed by
  a shared stage-trace mechanism:
  - new helper:
    - `scripts/lib/flow_observability.sh`
  - flows now persist `stage-trace.log` in their run dirs, recording:
    - `start`
    - `done`
    - `skip`
    - `failed`
    - `flow-success`
    - `flow-failure`
  - `print_failure_context(...)` now also reports the stage-trace path
- Verified cache behavior:
  - running `./scripts/bridge.sh proof-export-bundle run_outputs/cache-smoke/mithril_stm_artifact.json`
    twice caused the second run to print:
    - `Skipping Building bridge-compatible Mithril STM artifact (fingerprint unchanged)`
  - running `SYNC_SCOPE=phase12 ./scripts/bridge.sh sync` twice caused the
    second run to print:
    - `Skipping Syncing Aiken scripts into main.tx3 (fingerprint unchanged for scope phase12)`
- Verified observability behavior:
  - `run_outputs/obs-smoke/stage-trace.log` was created by
    `./scripts/bridge.sh run --output-dir run_outputs/obs-smoke --skip-aiken-check --skip-preflight`
  - that trace recorded the artifact stage, skip decisions for `aiken check`
    and preflight, and later bridge-flow progress/failure/success transitions
- After these quality/robustness changes, the integrated flow still succeeded:
  - `./scripts/bridge.sh run --output-dir run_outputs/obs-smoke --skip-aiken-check --skip-preflight`
  - final `bridge_mint_tx hash` from that verification:
    - `ffb3b4de9c569c44da43a316e5cdca734ab74a7a505e14ddf94aa3ceca3b58b5`
- A second aggressive cleanup pass was applied to stale public docs:
  - `BRIDGE_FLOW_DIAGRAM.md`
    - replaced the old diagram that still described a single receipt and
      `proof_receipt` as a reference input
    - now documents the live model with:
      - three proof domains
      - three receipts
      - proof receipts consumed as normal inputs
      - `stake_distribution_standard` state still used as a reference input by
        `bridge_mint_tx`
  - `README_MITHRIL.md`
    - removed the stale Tx3 workaround note that described the old
      `stake_distribution_standard_tx` miswiring around a reused receipt
    - replaced it with the live multi-domain receipt model
  - `MITHRIL_POC_RUNBOOK.md`
    - removed the stale claim about a single shared `statement_hash`
    - updated default persisted outputs to include:
      - runtime bundle
      - `stage-trace.log`
      - `phase12-all/session.env`
    - updated drift checks to reflect the multi-proof artifact schema
  - `scripts/README.md`
    - now lists `lib/flow_observability.sh` among the internal shell helpers
- Verification after the documentation cleanup:
  - `bash -n` still passed for the touched public scripts
  - `./scripts/bridge.sh proof-export-bundle run_outputs/cache-smoke/mithril_stm_artifact.json`
    still succeeded and reused the cached artifact outputs
- Quality/robustness debt 4 ("consolidate the tx snapshot root source of truth")
  is now addressed by a shared validator/helper module:
  - `scripts/python/tx_snapshot_root.py`
- That helper now centralizes:
  - normalization of the tx snapshot root
  - validation that the tx-snapshot certificate signed message equals the
    protocol-message root
  - validation that `bridge_mint_raw.json` matches the artifact
    `proofs.cardano_transactions` root when an artifact is provided
- `scripts/python/prepare_mithril_bridge_minting_args.py` now resolves the
  canonical tx snapshot root through that helper instead of reading the bridge
  fixture field ad hoc.
- `scripts/python/sync_bridge_zk_fixture.py` now accepts:
  - `--proof-export-bundle`
  and, when present, fails early if the regenerated or checked bridge fixture
  root diverges from the artifact root.
- `scripts/python/build_bridge_compatible_mithril_stm_bundle.py` now validates
  that the tx-snapshot bundle statement root matches the bridge fixture root
  before emitting the combined artifact.
- `scripts/python/check_mithril_poc_preflight.py` now:
  - validates the bridge tx-snapshot root against the shared helper
  - records both roots in the canonical snapshot under:
    - `tx_snapshot_root.artifact_hex`
    - `tx_snapshot_root.bridge_fixture_hex`
- The canonical snapshot file
  `scripts/data/mithril_poc_reference_snapshot.json` was refreshed to the live
  consistent state that uses tx snapshot root:
  - `0xadd9df32ad38901508e47043e836d8bb44d558900979426630ca0a2f9baa7366`
- Verification after the tx-snapshot-root consolidation:
  - `python3 -m py_compile` passed on the touched Python files
  - `python3 scripts/python/check_mithril_poc_preflight.py ... --write-snapshot`
    succeeded
  - `python3 scripts/python/check_mithril_poc_preflight.py ...` succeeded
  - `python3 scripts/python/sync_bridge_zk_fixture.py --check --proof-export-bundle ...`
    succeeded
  - `./scripts/bridge.sh preflight --proof-export-bundle run_outputs/obs-smoke/bridge-compatible-mithril-stm-bundle.json`
    succeeded
  - `./scripts/bridge.sh run --output-dir run_outputs/obs-smoke --skip-aiken-check --skip-preflight`
    still succeeded end-to-end after the new validation
  - `scripts/README.md` is now a secondary technical reference instead of a
    second onboarding document
- Stage H of the v3 plan is now partially reflected in live entrypoint
  behavior:
  - direct operational scripts now hand off to `bridge.sh` instead of behaving
    like standalone public entrypoints
  - `sync_phase_scripts_to_tx3.sh` now supports `--help`
- Stage G of that second-pass plan is now partially reflected in `README.md`:
  - a short troubleshooting section now points first to:
    - `./scripts/bridge.sh doctor check`
    - `./scripts/bridge.sh proof-export-bundle ...`
    - `./scripts/bridge.sh preflight ...`
    - `BRIDGE_FLOW_VERBOSE=1 ./scripts/bridge.sh run --strict`
- Repo-local tooling resolution no longer references:
  - `~/.tx3/stable/bin`
- `./scripts/bridge.sh run --strict` currently:
  - exports or reuses the canonical bridge-compatible Mithril STM artifact
  - runs the Mithril PoC preflight pinned at the front of the pipeline
  - runs `aiken check`
  - runs the full Mithril PoC bridge flow (via `scripts/bridge_minting.sh`)
- Bridge-fixture drift handling is now centralized in:
  - `scripts/python/sync_bridge_zk_fixture.py`
- That script currently supports:
  - `--check` to fail on drift
  - `--fix-drift` to regenerate only when drift is detected
  - `--regenerate` to rebuild the fixture unconditionally
- That regeneration flow currently:
  - reexports the snapshot-membership final fixture from
    `circuit_transaction_snapshot`
  - reexports the tx-set-update final fixture from
    `circuit_inclusion_exclusion`
  - rewrites `scripts/data/bridge_mint_raw.json`
  - regenerates `validators/tests/helpers/bridge_fixture.ak`
- While wiring that automated check, these runner fixes were directly applied:
  - `scripts/bridge_minting.sh` now sets its own `TMP_DIR` to the stable
    bridge run directory instead of assuming a transient inherited variable
  - `scripts/bridge_minting.sh` now sets the same default `USER_ADDRESS` used
  by the phase1/phase2 runner
  - `scripts/mithril_stake_distribution.sh` no longer truncates the inherited
    phase12 session manifest when the source and destination manifest paths are
    the same file
- `scripts/bridge_minting.sh` now auto-runs
  `python3 scripts/python/sync_bridge_zk_fixture.py --fix-drift` after
  bridge-policy sync and before bridge submission prep.
- `scripts/bridge_minting.sh` now also backs up and restores:
  - `scripts/data/bridge_mint_raw.json`
  - `validators/tests/helpers/bridge_fixture.ak`
  so the runtime auto-refresh does not leave the repo in a mismatched state if
  the script later restores `env/default.ak` and `main.tx3`.
- A direct `scripts/check_mithril_poc.sh --resume --skip-aiken-check --output-dir /tmp/bridge-aiken-check8`
  passed end-to-end at the time after regenerating the bridge fixture and adding
  that auto-refresh path. (`scripts/check_mithril_poc.sh` has since been
  consolidated into `./scripts/bridge.sh run --strict`.)
- That verified automated-check run produced:
  - `publish_phase1_reference_script = e3a658b11e94aa61f6a6969e3a7332857a4660232c0a8f7d0ab7fecceacf78c0`
  - `phase1_setup = 8540e7de208f303c1d6efa41a79c6f072b50fb542ff741d202565c21b3638c58`
  - `phase2_verify = 5a17a8d5169cf3684bf20be0b122d69e2b27233445a426bbfcba5912438d8c90`
  - `stake_distribution_genesis_tx = 0a69c430b92b8b7133e7e7a9d9c53f499e420b68fcf1506458faf9c3270d1c69`
  - `stake_distribution_standard_tx = 9df9324ee2e52f576c825181a02297a8bdc1cb0767e778ecfce49c497ec589c4`
  - `locking_txs_updater_seed_tx = f603a37cac9442e1a66f414590ae57522489a5c8facdec143e520013c595d3b9`
  - `publish_locking_txs_updater_spend_reference_script = 4c917d55c8a427f6a512f07678c7d04722bd77e13d9c870bef479cb66d999209`
  - `publish_bridge_minting_reference_script = 06f1f0af104949a6748e6eda4c562efeab70d86f5fda97ba4a0017e3333e8cd5`
  - `locking_txs_updater_genesis_tx = 82b10f96051ff90e8f995aebe47166b3708c3f02ea31256a19ecdfae7df5f525`
  - `bridge_mint_tx = 37f7fdc099803da5663d583ac691bc93539ed1d9db1efa5ddc59735e09c2738d`
- A stage-7 integrated runner now exists at:
  - `scripts/run_mithril_poc.sh`
- That runner currently:
  - generates the canonical bridge-compatible Mithril STM artifact when
    `--proof-export-bundle` is omitted
  - uses `run_outputs/mithril-poc/latest/` as its default stable run directory
  - reuses the existing `mithril_stm_artifact.json` in that run directory
    instead of rebuilding it on every rerun
  - supports `--resume` to require and reuse that persisted artifact
  - supports `--clean` to wipe the run directory before starting
  - runs `aiken check`
  - runs `scripts/preflight_mithril_poc.sh`
  - executes the full bridge flow through `scripts/bridge_minting.sh`
- `scripts/run_mithril_poc.sh` now also supports:
  - `--skip-preflight`
  to avoid rerunning the standalone preflight when a wrapper already did it.
- `scripts/preflight_mithril_poc.sh` now also uses
  `run_outputs/mithril-poc/latest/` by default and writes captured logs under
  `run_outputs/mithril-poc/latest/logs/`.
- `scripts/preflight_mithril_poc.sh` also supports the same explicit
  `--resume` and `--clean` flags for its run directory.
- The canonical reference snapshot used by that preflight now lives at:
  - `scripts/data/mithril_poc_reference_snapshot.json`
- The integrated flow scripts now default to stable repo-local run directories:
  - `scripts/submit_phase1_phase2_transactions_single_case.sh` ->
    `run_outputs/phase12/latest/`
  - `scripts/mithril_stake_distribution.sh` ->
    `run_outputs/stake-distribution/latest/`
  - `scripts/bridge_minting.sh` ->
    `run_outputs/bridge-minting/latest/`
- Those scripts now persist their session manifests at stable paths by default:
  - `run_outputs/phase12/latest/session.env`
  - `run_outputs/stake-distribution/latest/session.env`
  - `run_outputs/bridge-minting/latest/session.env`
- The nested integrated flow now also nests reusable sub-run state below the
  parent run directory:
  - `bridge-minting/stake-distribution/`
  - `bridge-minting/stake-distribution/phase12/`
- A short operator runbook for that flow now exists at:
  - `MITHRIL_POC_RUNBOOK.md`
- A short post-PoC improvements backlog now exists at:
  - `MITHRIL_POC_NEXT_IMPROVEMENTS.md`
- Bridge zk fixture handling is now centralized in:
  - `scripts/python/bridge_zk_fixture.py`
  - `scripts/python/sync_bridge_zk_fixture.py`
- `scripts/data/bridge_mint_raw.json` remains the single runtime-side source of
  truth for the bridge zk fixture, but it is now loaded and validated through
  that shared module instead of ad-hoc consumers.
- `validators/tests/helpers/bridge_fixture.ak` is now synchronized through
  `sync_bridge_zk_fixture.py`.
- `prepare_mithril_bridge_minting_args.py` now consumes the shared validated
  bridge zk fixture loader instead of reading `bridge_mint_raw.json` directly.
- The canonical debugging fixture for the PoC is now defined operationally as:
  - the artifact produced by
    `scripts/build_bridge_compatible_mithril_stm_proof_export_bundle.sh`
  - not a hand-edited JSON committed in the repo
- The current PoC runner documentation now explicitly lists these local
  dependencies for a fresh checkout:
  - `aiken`
  - `python3`
  - `cargo`
  - `curl`
  - `lsof`
  - `trix`
  - `cshell`
  - sibling repos `../dolos`, `../plutus-halo2-verifier-gen`, and
    `../uplc-turbo`
  - Python package `cbor2`
- `scripts/run_mithril_poc.sh` now also supports `--skip-aiken-check` for fast
  reruns while iterating on the integrated bridge flow.
- The repeated Aiken/Tx3 recompilations in the full bridge flow were reduced by
  introducing reuse flags across scripts:
  - `PHASE12_SKIP_SYNC`
  - `STAKE_DISTRIBUTION_SKIP_SYNC`
  - `BRIDGE_MINTING_REUSE_SYNCED_TX3`
- `scripts/bridge_minting.sh` now prepares shared Aiken/Tx3 artifacts once with
  `SYNC_SCOPE=all` and then reuses that synced state for:
  - `phase1/phase2`
  - `stake_distribution`
  - `bridge`
- `scripts/submit_phase1_phase2_transactions_single_case.sh` and
  `scripts/mithril_stake_distribution.sh` now honor those reuse flags and skip
  nested sync/build work when the caller already prepared the full flow.
- A direct rerun with
  - `scripts/run_mithril_poc.sh --skip-aiken-check`
  still passes end-to-end after that optimization.
- Observability of the integrated bridge flow was improved in:
  - `scripts/submit_phase1_phase2_transactions_single_case.sh`
  - `scripts/mithril_stake_distribution.sh`
  - `scripts/bridge_minting.sh`
  - `scripts/lib/integration_common.sh`
- Those flows now report:
  - the Mithril STM artifact path
  - artifact `source_id`
  - artifact `statement_hash`
  - child certificate `signed_message`
  - the last named stage reached by the script
  - session manifest paths
  - temp directory and Dolos log path on failure
- `scripts/python/read_json_field.py` now supports dotted paths, which is used
  by the new observability output.
- The bridge flow scripts are now quiet by default for noisy tool output from:
  - `cargo`
  - `aiken`
  - `trix`
- High-level stage messages are still printed, but command-level logs are
  suppressed unless `BRIDGE_FLOW_VERBOSE=1` is set.
- When one of those quiet commands fails, the scripts now print:
  - the failed subcommand label
  - the command itself
  - the captured log path inside the run directory when available
  - the tail of the captured log
- In `scripts/python/prepare_mithril_bridge_minting_args.py`, the
  `locking_tx_hash_hex` coming from `scripts/data/bridge_mint_raw.json` is now
  treated as the runtime source of truth for the canonical Cardano tx hash.
- A direct stage-7 rerun with:
  - `scripts/run_mithril_poc.sh --skip-aiken-check`
  now passes end-to-end.
- That verified stage-7 run produced:
  - `publish_phase1_reference_script = e3a658b11e94aa61f6a6969e3a7332857a4660232c0a8f7d0ab7fecceacf78c0`
  - `phase1_setup = f50dc98b73a506179be9734de908b92372d4d3a315318cf1de0866eec6597d05`
  - `phase2_verify = ce76a8a9e10871e747eb8f848aeef38583ef1b67e25fa85cf5788c9cd422100a`
  - `stake_distribution_genesis_tx = 66fea910571283e738adde0833e511a791a4ded69c40babf7995ae290a2ac705`
  - `stake_distribution_standard_tx = 572a8ba57c1dccc809af03de69c030f64e59a52e647461bfd0ef600919496330`
  - `locking_txs_updater_seed_tx = 34daa7a204bb41b9b19f0b09048c2642952c9ac5b4833410373aca76714fde00`
  - `publish_locking_txs_updater_spend_reference_script = edbaca11cf4a7c187ae3418044e4cfa14e69dacb6349548ca0ca80585c5dc764`
  - `publish_bridge_minting_reference_script = 952d0fb62f779479a4c984d14fd8432e7b571a1df1bfc579da8a7f7e6c7d9fb2`
  - `locking_txs_updater_genesis_tx = 24ca92012f7fe5d4b4828d4b9c6516052363573c6ac5a45952a45f74597b3021`
  - `bridge_mint_tx = 8940942bf724213ba58e6841e2ce74c110f188f868e6e18033f7129886026ff2`
- That same verified run used the canonical bridge-compatible STM artifact at:
  - `run_outputs/mithril-poc/latest/mithril_stm_artifact.json`

- `scripts/python/prepare_mithril_stake_distribution_args.py` now accepts
  `--mithril-stm-artifact <path>`.
- `scripts/python/prepare_mithril_bridge_minting_args.py` now also accepts
  `--proof-export-bundle <path>`.
- `scripts/mithril_stake_distribution.sh` now forwards
  `PROOF_EXPORT_BUNDLE_PATH` to the stake-distribution arg builder.
- `scripts/bridge_minting.sh` now forwards `PROOF_EXPORT_BUNDLE_PATH` to the
  bridge-mint arg builder.
- In integrated mode, `bridge-aiken` now reads certificate parent/child
  material from `artifact.certificates` instead of directly from
  `scripts/data/mithril_stake_distribution_*.json`.
- `scripts/python/mithril_stm_proof_export_bundle_certificates.py` is now the local helper
  that loads `artifact.certificates` and normalizes:
  - raw hex bytes
  - ASCII-encoded certificate text fields
  - `prev_hash` for reduced certificates
- The current adapter explicitly enforces this invariant before building
  stake-distribution or bridge args:
  - `artifact.certificates.child.signed_message == statement.public_input_2 == statement.statement_hash`
- A direct `python3 -m py_compile` check currently passes for:
  - `scripts/python/mithril_stm_proof_export_bundle_certificates.py`
  - `scripts/python/prepare_mithril_stake_distribution_args.py`
  - `scripts/python/prepare_mithril_bridge_minting_args.py`
- The currently available STM artifacts under `/tmp/tmp.*/mithril_stm_artifact.json`
  still identify themselves as:
  - `source_id = synthetic-test-fixture`
  - parent metadata `network = poc`
  - parent epoch `0`
  - child epoch `1`
- Those currently available synthetic STM artifacts are sufficient to validate
  `phase1/phase2`, but not to demonstrate the full `stake_distribution ->
  bridge` chain with Mithril-compatible certificate fixtures.
- A direct run of `scripts/mithril_stake_distribution.sh` with one of those
  synthetic artifacts reached the integrated certificate path and then failed
  after phase 2, not during phase proof verification.
- A direct run of `scripts/bridge_minting.sh` with one of those synthetic
  artifacts also reached the integrated certificate path and failed while
  submitting `stake_distribution_genesis_tx`.
- A repo-local reproducible builder for the bridge-compatible stage-5 artifact
  now exists at:
  - `scripts/build_bridge_compatible_mithril_stm_proof_export_bundle.sh`
- That script currently composes:
  - a deterministic STM witness bundle exported from `plutus-halo2-verifier-gen`
  - `scripts/data/mithril_stake_distribution_genesis.json`
  - `scripts/data/mithril_stake_distribution_standard.json`
  into a single `mithril_stm_artifact.json` with:
  - `source_id = bridge-aiken-compatible-fixture`
  - parent certificate metadata `network = preview`, epoch `1129`
  - child certificate epoch `1130`
  - child `signed_message = statement_hash = 0x0707...0707`
- A repo-local bundle transformer for that flow now exists at:
  - `scripts/python/build_bridge_compatible_mithril_stm_bundle.py`
- The resulting bridge-compatible artifact has been directly verified at:
  - `/tmp/mithril-stage5-final/mithril_stm_artifact.json`
- `prepare_mithril_bridge_minting_args.py` was directly verified against that
  artifact and currently pulls these parent-certificate fields from it:
  - `parent_certificate_hash = 0x062028d9a71eb9178dabe0018d161d5bc6773a331c3759f8f05661718296387f`
  - `parent_certificate_epoch = 1130`
  - `parent_certificate_next_aggregate_verification_key_snark = 0x736e61726b2d61766b2d31313331`
  - `parent_certificate_aggregate_verification_key_snark = 0x736e61726b2d61766b2d31313330`
- A new Aiken fixture helper now exists for the stage-5 certificate shape:
  - `tests/helpers/certificates/stake_distribution_certificates.proof_export_compatible_sd_certificate`
- That helper keeps the standard stake-distribution certificate chaining fields
  but rebases `signed_message` to the STM PoC statement hash `0x0707...0707`.
- The stake-distribution validator test suite now includes:
  - `accepts_proof_export_compatible_standard_certificate`
- A targeted check currently passes:
  - command: `aiken check -m tests/stake_distribution_validator_test`
  - latest verified summary: `16 tests, 0 failures`
- The current `scripts/mithril_stake_distribution.sh` flow still sometimes
  fails at `stake_distribution_genesis_tx` with:
  - `Transaction script execution failed`
- That same failure was directly reproduced again without
  `PROOF_EXPORT_BUNDLE_PATH`, so it is not currently attributed to the stage-5
  artifact integration itself.
- Later, after the user's follow-up fix, the stage-5 integrated flow was
  rerun successfully with:
  - `PROOF_EXPORT_BUNDLE_PATH=/tmp/mithril-stage5-final/mithril_stm_artifact.json scripts/mithril_stake_distribution.sh`
- That verified run produced these hashes:
  - `publish_phase1_reference_script = e3a658b11e94aa61f6a6969e3a7332857a4660232c0a8f7d0ab7fecceacf78c0`
  - `phase1_setup = 733ec8c5f3981beff2ccf4d397d5a3c78a9c3c71ce26a3844ead00ddc78f2b58`
  - `phase2_verify = 33f73314da6430b2f9907326d794e5c5ded50a96d4116523d69c9ca4d6bd2428`
  - `stake_distribution_genesis_tx = 6bd28b9bbf76652c974aa20b4bc0480f4bdf04ec6421a7d9de1d1682c4ad46ad`
  - `stake_distribution_standard_tx = b3d7853a663e33c6fcdba578e646a1f34776db4b42f8fb4a34fea97f9de1ca88`
- Therefore stage 5 is now verified end-to-end for the PoC with a single
  bridge-compatible Mithril STM artifact.
- Stage 6 was then rechecked directly:
  - `find plutus-halo2-verifier-gen -type f -name '*.ak'` returned `0`
  - `git ls-files 'plutus-halo2-verifier-gen/**/*.ak'` returned `0`
- That means `plutus-halo2-verifier-gen` currently ships no versioned `.ak`
  files by default, while `bridge-aiken` remains the only source of truth for
  the on-chain Aiken of the PoC.
- That `stake_distribution_genesis_tx` failure was later directly reproduced
  inside `scripts/bridge_minting.sh` and traced to stale constants in
  `env/default.ak`, not to the certificate artifact path itself.
- `scripts/python/sync_phase_scripts_to_tx3.py` now also updates downstream
  policy/script constants in `env/default.ak` during sync, including:
  - `phase2_asset_policy_id`
  - `stake_distribution_spending_script`
  - `stake_distribution_asset_policy_id`
  - `locking_txs_updater_policy_id`
  - `locking_txs_updater_spending_script`
  - `bridge_minting_policy_id`
  - `transferred_asset_policy_id`
- Before that fix, `stake_distribution` was being rebuilt against an outdated
  `env.phase2_asset_policy_id`, so the live phase-2 receipt reference input was
  rejected even though the UTxO existed and `phase2` itself had succeeded.
- After that sync fix, a direct rerun of `scripts/bridge_minting.sh` advanced
  past the previous `stake_distribution_genesis_tx` failure and completed both:
  - `stake_distribution_genesis_tx`
  - `stake_distribution_standard_tx`
- In that later rerun, the next blocker moved downstream to
  `scripts/python/prepare_mithril_bridge_minting_args.py` with a distinct
  fixture mismatch:
  - `locking_tx_hash_hex fixture does not match computed locking_tx_hash`
  - fixture: `aba2057996571cb3c6bbdbd6c7afd3eeff12edfd4b393924943b8d139b068412`
  - computed: `166f57d8b2ae93641452ca4c8068fdc685969220b4e2da9fb7217be177317ab7`

## Verified Repo Facts

- `validators/phase1.ak` and `validators/phase2.ak` currently contain no `test`
  declarations.
- The phase-specific tests currently live in:
  - `validators/tests/phase1_test.ak`
  - `validators/tests/phase2_test.ak`
- `trix check` currently passes in this repo.
- `aiken check` currently passes when run outside the Codex sandbox.
- The latest verified `aiken check` result was:
  - total tests: `115`
  - passed: `115`
  - failed: `0`
- A targeted snapshot-membership fixture check currently passes:
  - command: `aiken check -m tests/snapshot_membership_test`
  - latest verified summary: `8 tests, 0 failures`
- A targeted minting-validator check currently passes:
  - command: `aiken check -m tests/minting_validator_test`
  - latest verified summary: `14 tests, 0 failures`
- `lib/protocol_message.ak` currently defines a
  `NextSnarkAggregateVerificationKey` protocol-message part key.
- `lib/protocol_message.ak` currently also defines a
  `CardanoTransactionsMerkleRoot` protocol-message part key.
- `lib/mithril_certificate.ak` currently defines
  `aggregate_verification_key_snark` on `MithrilCertificate`.
- `lib/reduced_mithril_certificate.ak` currently defines
  `protocol_message_cardano_transactions_merkle_root` on
  `ReducedMithrilCertificate`.
- In `reduced_mithril_certificate_from_certificate(...)`, the reduced
  certificate currently:
  - decodes `CardanoTransactionsMerkleRoot` from the Mithril hex string into
    raw bytes when that protocol-message part is present
  - falls back to the empty byte string when that protocol-message part is
    absent
- In `validators/phase1.ak`, `hash_public_inputs(i_1, i_2)` currently returns
  `i_2`.
- The current `validators/tests/phase1_test.ak` suite verifies that
  `hash_public_inputs(i_1, i_2)`:
  - is stable for identical inputs
  - equals `i_2`
  - ignores `i_1`
  - changes when `i_2` changes
- `validators/stake_distribution.ak` currently defines distinct redeemer types:
  - `StakeDistributionMintRedeemer`
  - `StakeDistributionSpendRedeemer`
- `validators/stake_distribution.ak` currently defines a reduced
  `StakeDistributionCertificateState` that includes:
  - `next_aggregate_verification_key_snark`
  - `aggregate_verification_key_snark`
- `validators/minting.ak` currently defines
  `tx_snapshot_certificate_protocol_message_cardano_transactions_merkle_root`
  on `MintingValidatorRedeemer`.
- `validators/minting.ak` currently also defines
  `locking_tx_merkle_proof_public_sub_root` on `MintingValidatorRedeemer`.
- In `validators/minting.ak`, the snapshot-membership Groth16 proof check is
  now active again through `verify_transaction_is_present_in_snapshot(...)`.
- In later step-12 size debugging with the mint validator body reduced to
  boolean checkpoints, the user reported these concrete transaction sizes:
  - validator body returning only `True`: about `8973 bytes`
  - enabling only `certificate_is_valid_for(...)`: about `11700 bytes`
  - enabling only `verify_transaction_is_present_in_snapshot(...)`: more than
    `30000 bytes`
- In that same step-12 debugging session, the user verified that:
  - `certificate_is_valid_for(...)` does find the `stake_distribution`
    reference input
  - `certificate_is_valid_for(...)` also finds the `statement_hash`
  - the remaining failing predicate inside
    `verify_reduced_mithril_certificate_against_parent_state(...)` was:
    `certificate.prev_hash == digest_to_bytes_of_string(parent_hash)`
  - `verify_transaction_is_present_in_snapshot(...)` fails specifically in the
    final `groth16` verifier path
  - enabling that zk predicate pushes the minting transaction to almost
    `40 KB`
- Additional step-12 facts verified afterwards while debugging the remaining
  zk failure:
  - after setting `TX3_DOLOS_MAX_TX_SIZE=65536`, the bridge-mint flow no
    longer fails for `maxTxSize`; the latest real user run reached phase 2 and
    was rejected by the minting policy
  - decoding `/tmp/bridge-phase12.q6P7Ip/bridge-mint-skip.tx` showed that the
    mint redeemer actually carried the expected final-fixture zk values:
    - `locking_tx_hash = aba2057996571cb3c6bbdbd6c7afd3eeff12edfd4b393924943b8d139b068412`
    - `locking_tx_merkle_proof_public_sub_root = 15359653a3a15cf8b49ec4dceddc685add56fbfde1429dc7bbe2a60652cfb2eb`
    - `tx_snapshot_certificate_protocol_message_cardano_transactions_merkle_root = 4e2d573652dc8b27f7753d8ba62a10061fc9cba80cbc56c717ab86e9820484b0`
    - `locking_tx_merkle_proof_pi_a/pi_b/pi_c` exactly matched the exported
      final proof bytes
  - decoding that same tx also showed that the live transaction used the
    current bridge minting script, not a stale inline script:
    - the inline minting witness extracted from the tx was `30294 bytes`
    - the current parameter-applied `minting.minting_validator.mint` blueprint
      compiled to the same `30294-byte` script
    - the extracted tx script and the current applied blueprint were byte-for-
      byte equal
  - the same tx also carried the current locking-txs-updater spending script as
    an inline witness of about `6162 bytes`
  - therefore, these previously suspected root causes are now ruled out by
    direct inspection:
    - stale `main.tx3` minting script bytes
    - wrong final-fixture public inputs in the live mint redeemer
    - wrong final-fixture proof bytes in the live mint redeemer
- the intermediate debugging build of `lib/zk/verification.ak` had explicit
    `trace` calls for:
    - flattened zk public inputs
    - `piA`
    - `piB`
    - `piC`
    - `vk.nPublic`
    - final `groth_verify` boolean
  - those traces were later removed again before the next end-to-end run so
    the live mint path would measure only the actual `groth_verify` cost and
    not extra trace overhead
- The verified contract for that parent-certificate comparison is:
  - `certificate.prev_hash` is stored as lowercase ASCII hex bytes
  - `parent_certificate_hash` must therefore be threaded as raw digest bytes
  - `verify_reduced_mithril_certificate_against_parent_state(...)` itself
    applies `digest_to_bytes_of_string(parent_hash)` before comparing
- In `validators/minting.ak`, the old redundant
  `locking_tx_hash_is_correct(...)` gate has now been removed.
- The current minting path therefore no longer recalculates
  `locking_tx_hash` on the Aiken side and relies on the zk proof instead.
- In `validators/minting.ak`, the snapshot-membership public input shape is now
 :
  - raw `locking_tx_hash` bytes first
  - raw `locking_tx_merkle_proof_public_sub_root` bytes second
  - raw `CardanoTransactionsMerkleRoot` bytes third
- That current Aiken shape therefore flattens to `6` public inputs.
- `validators/minting.ak` no longer decodes the certificate merkle root from
  ASCII hex while building Groth16 public inputs.
- A repo-local snapshot-membership VK module now exists at:
  - `lib/zk/snapshot_membership_vk.ak`
- The sibling circuit repo currently exports a deterministic final fixture at:
  - `../circuit_transaction_snapshot/circuit_build/groth16_sample_proof`
- That exported final fixture was verified with:
  - `curve=bls12381`
  - `protocol=groth16`
  - `public_inputs=6`
  - `verified=true`
- That exported fixture currently also defines these canonical packed public
  inputs:
  - `locking_tx_hash_hi = 228139250415487002388767140015013614574`
  - `locking_tx_hash_lo = 339051427267688910400524746267809973266`
  - `sub_root_hi = 28192028633004748333156889136081954906`
  - `sub_root_lo = 294211035597550697175824458099985461995`
  - `snapshot_root_hi = 103915205903458190427242814277782474758`
  - `snapshot_root_lo = 42253850181320244066926319426846622896`
- `scripts/data/bridge_mint_raw.json` currently uses that final fixture's real:
  - `CardanoTransactionsMerkleRoot`
  - `locking_tx_merkle_proof_public_sub_root`
  - `minting_merkle_proof.piA/piB/piC`
- A repo-local canonical bridge fixture helper now exists at:
  - `validators/tests/helpers/bridge_fixture.ak`
- That helper is currently generated from:
  - `scripts/data/bridge_mint_raw.json`
- The synchronizer for that helper currently lives at:
  - `scripts/python/sync_bridge_zk_fixture.py`
- A direct drift check for that generated helper currently passes:
  - command: `python3 scripts/python/sync_bridge_zk_fixture.py --check`
- The generated helper currently centralizes these bridge-fixture values for
  Aiken-side tests:
  - final snapshot-membership `snapshot_root`
  - final snapshot-membership `sub_root`
  - deterministic `locking_tx_hash`
  - canonical packed snapshot-membership public inputs
  - final snapshot-membership proof bytes
  - final tx-set-update proof bytes
  - actual bridge locking-tx fixture fields reused by the actual-bridge
    redeemer helper
- `validators/tests/helpers/minting_redeemer.ak`,
  `validators/tests/helpers/actual_bridge_redeemers.ak`, and
  `validators/tests/helpers/txs_updater_redeemer.ak` currently source their
  canonical bridge-fixture bytes from the generated
  `tests/helpers/bridge_fixture`.
- A repo-local shared test helper for bridge locking transaction serialization
  now exists at:
  - `validators/tests/helpers/bridge_locking_tx.ak`
- That helper currently centralizes:
  - `PaymentCredential` to raw bytes conversion
  - `Datum` to raw bytes conversion for `NoDatum`, `InlineDatum`, and
    `DatumHash`
- `validators/tests/helpers/minting_redeemer.ak` and
  `validators/tests/helpers/actual_bridge_redeemers.ak` currently use
  `tests/helpers/bridge_locking_tx` for the shared byte-serialization helpers.
- `validators/tests/helpers/minting_redeemer.ak` currently builds its minting
  redeemer in two stages:
  - derive `LockingTxRedeemerFields` from the locking transaction
  - expand already-reduced child and parent Mithril certificates inside
    `minting_redeemer_from_certificates(...)`
- That current `minting_redeemer_from_certificates(...)` helper is the single
  local place in `minting_redeemer.ak` that maps
  `ReducedMithrilCertificate` fields into the flattened
  `MintingValidatorRedeemer` certificate fields.
- `validators/tests/helpers/minting_tx.ak` currently centralizes the canonical
  bridge mint test transaction shape in:
  - `simple_minting_inputs()`
  - `simple_minting_outputs()`
  - `simple_reference_inputs()`
- The current minting transaction variants in
  `validators/tests/helpers/minting_tx.ak` build from those helpers and override
  only the inputs, outputs, reference inputs, or mint policy needed by each
  negative or ordering case.
- The previous monolithic certificate fixture helper at
  `validators/tests/helpers/certificates.ak` has been split by responsibility
  into:
  - `validators/tests/helpers/certificates/common.ak`
  - `validators/tests/helpers/certificates/cardano_transactions.ak`
  - `validators/tests/helpers/certificates/stake_distribution_certificates.ak`
  - `validators/tests/helpers/certificates/stake_distribution_negative_certificates.ak`
  - `validators/tests/helpers/certificates/certificate_hash_fixtures.ak`
- Current certificate-fixture imports use the responsibility-specific modules
  instead of `tests/helpers/certificates`.
- The current `stake_distribution_certificates.ak` module keeps the base valid
  genesis/standard stake-distribution certificates, while
  `stake_distribution_negative_certificates.ak` owns the
  `standard_sd_certificate_with_incorrect_*` negative fixtures.
- The former ambiguous certificate fixture module name `hash_test.ak` has been
  replaced by `certificate_hash_fixtures.ak` because it contains hash-test
  fixtures, not executable tests.
- `validators/tests/helpers/unlocking_tx.ak` currently centralizes repeated
  unlocking transaction outputs in:
  - `unlocked_funds_output(...)`
  - `used_txs_output(...)`
- The current stake-distribution transaction helper already routes its
  variants through `generate_stake_distribution_tx(...)`, with separate
  genesis and standard certificate builders.
- The current helper/test naming cleanup includes:
  - `asset_ammount` renamed to `asset_amount` in
    `validators/tests/helpers/unlocking_tx.ak`
  - `mk_root` renamed to `merkle_root` in
    `validators/tests/helpers/unlocking_tx.ak`
  - Spanish helper comments in `minting_tx.ak` and
    `certificates/stake_distribution_certificates.ak` rewritten in English
- The current bridge-side fixture proof and VK are serialized in the compressed
  BLS12-381 encoding expected by `ak-381`.
- Discarded bug causes that were directly ruled out while debugging the bridge
  mint Groth16 path now include:
  - stale minting script bytes in the built tx
  - wrong proof bytes in the live mint redeemer
  - wrong final public inputs in the live mint redeemer
  - `maxTxSize` being the remaining blocker after raising it to `65536`
  - broken collateral selection for the bridge mint tx after adding the
    dedicated collateral output
  - extra debug `trace` calls inside `lib/zk/verification.ak` once those were
    removed for the next runtime measurement
- The remaining Groth16 mint failure was finally reproduced with the exact
  built bridge tx under the local vendored evaluator:
  - the mint probe read the patched redeemer ex-units as
    `mem = 50000000`, `steps = 50000000000`
  - but the underlying `pallas-uplc` runtime still started evaluation with its
    hardcoded default machine budget:
    - `mem = 14000000`
    - `cpu = 10000000000`
  - that mismatch produced the verified failure signature:
    - `term_err = OutOfExError(...)`
    - remaining CPU went negative a little past `10_000_000_000`
  - the same exact mint script / proof / public inputs then evaluated
    successfully once the vendored local `pallas-uplc` runtime stopped using
    the fixed `10_000_000_000` CPU start budget for `Program::eval(...)`
  - the corresponding successful mint-probe result was:
    - `term_ok = Constant(Unit)`
    - `success_unit = true`
    - `consumed_budget.mem = 3025797`
    - `consumed_budget.cpu = 15258365406`
- After rebuilding vendored Dolos against that local `pallas-uplc` evaluator
  change, the repo-local end-to-end command:
  - `KEEP_MITHRIL_BRIDGE_MINTING_TMP=1 ./scripts/bridge_minting.sh`
  finished successfully again
  - verified final tx hash:
    - `bridge_mint_tx = 0841e3bbe2d8d4f9378be133aa4cc50a923d2c1e8e4719ecd3060ad291ba18ec`
- The current deterministic locking hash shared with that fixture is:
  - `aba2057996571cb3c6bbdbd6c7afd3eeff12edfd4b393924943b8d139b068412`
- `env/default.ak` currently still sets `bridge_minting_policy_id` and
  `transferred_asset_policy_id` to:
  - `a09cfbce6aac558596bf47d4b8a8beb46240ccf5e737009ead98477e`
- The current bridge flow therefore treats `main.tx3` as the source of truth
  for active `BridgeMinting` policy usage instead of relying on those
  `env/default.ak` constants.
- The current bridge-scoped policy ids in `main.tx3` are:
  - `BridgeMinting = 99ed532bd74df90f997e319a5e15051a3e1653845cde65c33d4ab0ef`
  - `LockingTxsUpdaterMint = 892c4f0aa2091a6758ddaa52bf5eb9b71613aa4e2fe02e7b4a5ff5dc`
  - `LockingTxsUpdaterSpend = f5d5abacf2756ae6501c5d4e8e2ec7232abd00c60a1594da08108412`
- `validators/tests/snapshot_membership_test.ak` currently includes explicit
  coverage that:
  - the reduced certificate keeps `CardanoTransactionsMerkleRoot`
  - the minting redeemer helper threads that value through unchanged
  - the minting redeemer helper threads the final fixture `sub_root`
  - the minting redeemer helper threads the final fixture `pi_a/pi_b/pi_c`
  - the digest packing helper maps the fixture `locking_tx_hash` to the two
    expected packed field elements
  - the digest packing helper maps the fixture `snapshot_root` to the two
    expected packed field elements
  - `snapshot_membership_vk().nPublic == 6`
  - the current `snapshot_membership_public_inputs(...)` order matches Aiken's
    current packed `6`-public final order
- `validators/tests/minting_validator_test.ak` currently includes explicit
  coverage that:
  - the validator accepts the valid snapshot-membership fixture
  - the validator rejects an incorrect parent certificate
  - incorrect `locking_tx_hash` fails under the active Groth16 verifier
  - invalid merkle proof fails under the active Groth16 verifier
  - invalid `snapshot_root` fails under the active Groth16 verifier
  - invalid `sub_root` fails under the active Groth16 verifier
  - the canonical transaction still works with extra inputs, outputs, and
    reference inputs
  - the validator rejects an incorrect phase-2 statement hash
  - the validator requires the phase-2 receipt reference input
  - the validator only requires the stake-distribution NFT reference input
  - the validator does not directly require the txs-updater NFT input
- The current minting-validator behavior coverage now lives in:
  - `validators/tests/snapshot_membership_test.ak`
  - `validators/tests/minting_validator_test.ak`
  - `validators/tests/bridge_fixture_test.ak`
- `lib/zk/snapshot_membership_vk.ak` currently carries the packed verifier key
  exported from the sibling circuit with:
  - `nPublic = 6`
- A repo-local tx-set-update VK module now exists at:
  - `lib/zk/tx_set_update_vk.ak`
- That tx-set-update VK was copied from:
  - `../circuit_inclusion_exclusion/circuit_build/groth16_sample_proof/tx_set_update_vk.ak`
- That tx-set-update final fixture was verified with:
  - `curve=bls12381`
  - `protocol=groth16`
  - `public_inputs=4`
  - `verified=true`
- A repo-local tx-set-update bridge helper now exists at:
  - `lib/zk/tx_set_update.ak`
- That helper currently packs tx-set-update public inputs as:
  - `tx_id_hi`
  - `tx_id_lo`
  - `mt_root_in`
  - `mt_root_out`
- `validators/tests/tx_set_update_test.ak` currently verifies:
  - `tx_set_update_vk().nPublic == 4`
  - the helper public inputs match the exported final fixture values
- `scripts/data/bridge_mint_raw.json` now uses the tx-set-update final
  fixture's:
  - `new_merkle_root_hex = 057e71b8fc29c1aed0c1b357d74ebbf0d28fc25e0897279d8f11f8ab892f8dad`
  - `tx_set_update_old_merkle_root_hex = 1081218ce61ee106396796dc2b469a63b99a934125107c4cc30050966f39b130`
  - `tx_set_update_proof.piA/piB/piC`
  - `tx_set_update_packed_public_inputs`
- `scripts/python/prepare_mithril_bridge_minting_args.py` now emits the bridge
  mint `new_merkle_root` from `new_merkle_root_hex` when that field is present.
- `scripts/python/sync_phase_scripts_to_tx3.py` now also syncs
  `locking_txs_updater_genesis_tx`'s local `empty_merkle_root` from
  `env.locking_txs_updater_initial_merkle_root`.
- `validators/tests/helpers/actual_bridge_redeemers.ak` now consumes the
  tx-set-update final fixture proof through the generated
  `tests/helpers/bridge_fixture` helper for the actual bridge spend redeemer.
- `validators/tests/bridge_fixture_test.ak` now directly verifies that actual
  bridge tx-set-update proof against the fixture roots.
- `env/default.ak` now sets `locking_txs_updater_initial_merkle_root` to the
  tx-set-update fixture input root:
  - `1081218ce61ee106396796dc2b469a63b99a934125107c4cc30050966f39b130`
- `validators/txs_updater_common.ak` now verifies tx-set-update proofs through
  `zk/tx_set_update.proof_verifies(...)`.
- The current repo-local shared zk module surface now lives under:
  - `lib/zk/`
- That current `lib/zk/` surface includes:
  - `public_input_packing.ak`
  - `verification.ak`
  - `snapshot_membership.ak`
  - `snapshot_membership_vk.ak`
  - `tx_set_update.ak`
  - `tx_set_update_vk.ak`
- The current Circom fixture/build shared pipeline now lives at:
  - `../zk-circuits-common/`
- That shared pipeline currently centralizes:
  - `circom_pipeline.sh`
  - `rust_witness_build_helper.rs`
- The shared `ark-circom` patch now lives specifically at:
  - `../zk-circuits-common/ark-circom`
- The current shared Rust export/build surfaces for the Circom sibling crates
  now all live under:
  - `../zk-circuits-common/`
- That shared repo-level circuit surface currently includes:
  - `circom_pipeline.sh`
  - `rust_witness_build_helper.rs`
  - `arkworks_fixture_export_helper.rs`
  - `ark-circom/`
- The current Python-side shared zk contract surface now lives at:
  - `scripts/python/zk_contract.py`
- That module currently centralizes:
  - packed digest halves for snapshot-membership / tx-set-update bridge fixtures
  - `statement_hash == public_input_2`
  - `certificate.signed_message == statement_hash`
  - `tx snapshot certificate.signed_message == protocol_message.cardano_transactions_merkle_root_hex`
  - bridge fixture packed-public-input contract checks
- `scripts/python/bridge_zk_fixture.py`,
  `scripts/python/tx_snapshot_root.py`,
  `scripts/python/stm_statement_digest.py`, and
  `scripts/python/mithril_stm_proof_export_bundle_certificates.py`
  now consume that shared Python contract layer instead of re-encoding those
  invariants independently.
- Verified direct checks after that Python contract extraction:
  - loading `scripts/data/bridge_mint_raw.json` through
    `validate_bridge_zk_fixture_contract(...)` succeeds
  - loading proof certificates from
    `run_outputs/ci/bridge-compatible-mithril-stm-bundle.json` succeeds for:
    - `stake_distribution_genesis`
    - `stake_distribution_standard`
    - `cardano_transactions`
- The largest remaining cross-repo duplication at this point is the STM
  artifact contract itself, which still exists in:
  - Rust producer logic in
    `../plutus-halo2-verifier-gen/src/plutus_gen/mithril_stm_proof_export.rs`
  - Python consumer validation in `scripts/python/zk_contract.py`
- `validators/txs_updater_common.ak` no longer defines a hardcoded
  placeholder `tx_set_update_verification_circuit_vk()`.
- `env/default.ak` no longer defines `txs_updater_placeholder_proof_tx_id`.
- The updater unit-test fixture now uses the tx-set-update final fixture:
  - `tx_id = aba2057996571cb3c6bbdbd6c7afd3eeff12edfd4b393924943b8d139b068412`
  - `mt_root_in = 1081218ce61ee106396796dc2b469a63b99a934125107c4cc30050966f39b130`
  - `mt_root_out = 057e71b8fc29c1aed0c1b357d74ebbf0d28fc25e0897279d8f11f8ab892f8dad`
- The latest targeted txs-updater validator check currently passes:
  - command: `aiken check -m tests/txs_updater_validator_test`
  - latest verified summary: `14 tests, 0 failures`
- The latest targeted unlocking-validator check currently passes:
  - command: `aiken check -m tests/unlocking_validator_test`
  - latest verified summary: `9 tests, 0 failures`
- The latest targeted bridge-fixture check currently passes:
  - command: `aiken check -m tests/bridge_fixture_test`
  - latest verified summary: `7 tests, 0 failures`
- In `validators/stake_distribution.ak`, standard certificate chaining is
  currently checked against the reduced parent state instead of calling
  `verify_mithril_standard_certificate`.
- In that current standard certificate chaining logic:
  - if child and parent epochs are equal, the checked SNARK AVKs are
    `certificate.aggregate_verification_key_snark` and
    `parent_certificate.aggregate_verification_key_snark`
  - if the child epoch is exactly one more than the parent epoch, the checked
    SNARK AVKs are `certificate.aggregate_verification_key_snark` and
    `parent_certificate.next_aggregate_verification_key_snark`
- The current `validators/tests/stake_distribution_test.ak` negative tests were
  verified to fail with these specific traces:
  - incorrect aggregate verification key:
    - `parent_certificate.next_aggregate_verification_key_snark == certificate.aggregate_verification_key_snark ? False`
  - incorrect protocol parameters:
    - `certificate.protocol_message_next_protocol_parameters == protocol_parameters_hash ? False`
  - incorrect signed entity type:
    - `new_certificate.signed_entity_is_stake_distribution ? False`
- Repo-local script data fixtures currently live in:
  - `scripts/data/phase1_args_raw.json`
  - `scripts/data/phase2_args_raw.json`
  - `scripts/data/mithril_stake_distribution_genesis.json`
  - `scripts/data/mithril_stake_distribution_standard.json`
- Repo-local Python helpers currently live in:
  - `scripts/python/`
- The phase1/phase2 Tx3 prep step now has an artifact-driven path:
  - `scripts/python/build_phase12_args_from_mithril_artifact.py`
  - `scripts/python/prepare_tx3_dolos_env.py --mithril-stm-artifact <path>`
- The repo-local note dedicated to the `stake_distribution_standard_tx`
  Tx3 / CShell bug currently lives at:
  - `tx3_cshell_bug.md`

## Verified Tx3 Facts

- `main.tx3` currently defines at least these transaction templates:
  - `phase1_setup`
  - `phase2_verify`
  - `stake_distribution_genesis_tx`
  - `stake_distribution_standard_tx`
- `main.tx3` currently mirrors the
  `protocol_message_cardano_transactions_merkle_root` field in:
  - `ReducedMithrilCertificate`
  - `MintingValidatorRedeemer`
  - `StakeDistributionSpendRedeemer`
- A repo-local phase-2 fixture file now exists at:
  - `lib/phase2_fixture.ak`
- A repo-local phase-2 runtime-probe test now exists at:
  - `validators/tests/phase2_runtime_probe_test.ak`
- A repo-local non-interactive phase-2 args file now exists at:
  - `scripts/data/phase2_args_raw.json`
- The current phase1/phase2 PoC flow can now consume a Mithril STM artifact via:
  - `PROOF_EXPORT_BUNDLE_PATH=/path/to/mithril_stm_artifact.json scripts/submit_phase1_phase2_transactions_single_case.sh`
- The repo-local raw phase fixtures currently use the future-snark statement
  representation directly:
  - `scripts/data/phase1_args_raw.json -> statement_hash_value = public_input_2`
  - `scripts/data/phase2_args_raw.json -> proof_receipt_statement_hash = public_input_2`
- When an artifact is provided, `bridge-aiken` now overlays only proof-derived
  fields from that artifact on top of the raw templates and preserves
  operational fields owned by this repo, such as:
  - `phase1_signer_vkh`
  - `reclaim_after_ms`
  - `phase2_output_lovelace`
  - `locked_lovelace`
  - `receipt_lovelace`
  - `collateral_lovelace`
- The integrated 4-transaction repo-local flow is currently driven by:
  - `scripts/mithril_stake_distribution.sh`
- The integrated bridge extension flow is currently driven by:
  - `scripts/bridge_minting.sh`
- That integrated script currently delegates the first two transactions to:
  - `scripts/submit_phase1_phase2_transactions_single_case.sh`
- The stake-distribution argument files generated by that integrated flow are:
  - `stake-distribution-genesis-args.json`
  - `stake-distribution-standard-args.json`
- In the current integrated flow, the standard certificate args file is patched
  after genesis submit to set:
  - `parent_certificate_utxo = <stake_distribution_genesis_tx hash>#0`
- `scripts/python/prepare_mithril_stake_distribution_args.py` currently emits:
  - `certificate_protocol_message_cardano_transactions_merkle_root = "0x"`
  for the standard stake-distribution flow.
- `scripts/python/prepare_mithril_bridge_minting_args.py` currently emits:
  - `tx_snapshot_certificate_protocol_message_cardano_transactions_merkle_root`
  - `locking_tx_merkle_proof_public_sub_root`
- When run against the current repo fixtures, that bridge-mint args script also
  emits the final deterministic zk values:
  - `locking_tx_hash = 0xaba2057996571cb3c6bbdbd6c7afd3eeff12edfd4b393924943b8d139b068412`
  - `locking_tx_merkle_proof_public_sub_root = 0x15359653a3a15cf8b49ec4dceddc685add56fbfde1429dc7bbe2a60652cfb2eb`
  - `tx_snapshot_certificate_protocol_message_cardano_transactions_merkle_root = 0x4e2d573652dc8b27f7753d8ba62a10061fc9cba80cbc56c717ab86e9820484b0`
  - `locking_tx_merkle_proof_pi_a/pi_b/pi_c` equal the exported final fixture
    proof from the sibling circuit repo
- For the current deterministic bridge fixture flow, the bridge-mint args
  script now pins `locking_tx_hash` to the exported final fixture value from
  `scripts/data/bridge_mint_raw.json` instead of relying on a dynamic
  recomputation at submit time.
- In that bridge-mint args script, the transaction snapshot merkle root is now
  emitted as raw bytes rather than ASCII-hex bytes.
- The current `scripts/mithril_stake_distribution.sh` derives the phase-2
  receipt statement hash from:
  - `scripts/data/phase1_args_raw.json -> public_input_2`
- In that current integrated flow:
  - `PHASE1_STATEMENT_HASH_VALUE = PHASE1_PUBLIC_INPUT_2`
  - `PHASE2_PROOF_RECEIPT_STATEMENT_HASH = PHASE1_STATEMENT_HASH_VALUE`
- `scripts/mithril_stake_distribution.sh` now also passes through
  `PROOF_EXPORT_BUNDLE_PATH` to the delegated phase1/phase2 flow, instead of
  forcing the old raw-fixture override path when an artifact is available.
- `main.tx3` was changed so that the runtime arguments used by Tx3 are flattened
  into primitive fields instead of passing custom record objects directly for:
  - the phase-1 state
  - the phase-2 state inputs used by `phase2_verify`
  - the reduced redeemer used by `phase2_verify`
- Before that flattening, `trix invoke` / `trix test` failed with:
  - `invalid param type`
- After that flattening, the `invalid param type` failure no longer occurred.
- After that flattening, `trix invoke` progressed far enough to prompt for:
  - which transaction to build
  - the `user` party binding
- A currently verified remaining failure for `phase1_setup` is:
  - `Input not resolved`
  - input: `source`
  - queried address: `600dd172b9b1866fd9513b96fcbe378a2d5adc7fb499949e8865d53edf`
  - queried min amount: `3000000`
- That `Input not resolved` failure was observed from:
  - `trix invoke`
  - `trix test tests/phase1.toml -v`
- For direct non-interactive `cshell tx invoke` of `phase2_verify`, the args
  file must still bind the `User` party explicitly:
  - `"user": "@bob"`
- Without that explicit `user` binding in the args file, the verified failure
  mode was:
  - `The input device is not a TTY`
- `scripts/bridge_minting.sh` was re-verified locally after threading
  `CardanoTransactionsMerkleRoot` through the reduced certificate and Tx3
  types.
- In an earlier verified rerun after a PC reboot, `scripts/bridge_minting.sh`
  completed successfully end-to-end and printed:
  - `Mithril bridge minting flow passed.`
- That earlier verified bridge flow produced these transaction hashes:
  - `publish_phase1_reference_script = e3a658b11e94aa61f6a6969e3a7332857a4660232c0a8f7d0ab7fecceacf78c0`
  - `phase1_setup = 5f1b2b78904370af3bb6e7e36e36b94489a9099373ccfcc3d0c41d5523b5c630`
  - `phase2_verify = 525df7390c918cf1ac1b410292ac1412c9d4dfcfe6eb8e3de73641133e87c196`
  - `stake_distribution_genesis_tx = 81db662e867c3c5f9c6ab4f3c29a7506c49b8a1676e08a34a898d1429a830b38`
  - `stake_distribution_standard_tx = f6a2f909cc3ea58da474b1e87b7aeb3364464507546e570dd464e5994f81e97e`
  - `locking_txs_updater_seed_tx = b273ba1e816eaeb60123b34ebb8843806a7c6f293ccaf10365fcf765689c3428`
  - `locking_txs_updater_genesis_tx = 2474b9c9f38132985a165a1dc9221fa76c56e6d539e54a87489a4f182a9b5988`
  - `bridge_mint_tx = 0101d8fc60f4efaedcaf24ed344c065b6527889956c1e3f8b195dd3206a2106c`
- The verified bridge flow also wrote:
  - `bridge-flow-summary.csv`
- In later re-runs while validating the raw-bytes snapshot root path,
  `scripts/bridge_minting.sh` failed before transaction submission because the
  temporary Dolos instance never became ready.
- Stage 4 of the Mithril STM PoC was verified with:
  - `aiken check`
  - `scripts/submit_phase1_phase2_transactions_single_case.sh` using `PROOF_EXPORT_BUNDLE_PATH`
- In that stage-4 verification run, the artifact-driven phase flow still
  produced the known deterministic tx hashes:
  - `publish_phase1_reference_script = e3a658b11e94aa61f6a6969e3a7332857a4660232c0a8f7d0ab7fecceacf78c0`
  - `phase1_setup = 5f1b2b78904370af3bb6e7e36e36b94489a9099373ccfcc3d0c41d5523b5c630`
  - `phase2_verify = 525df7390c918cf1ac1b410292ac1412c9d4dfcfe6eb8e3de73641133e87c196`
- In the kept Dolos logs for those failed re-runs, the verified startup error
  was:
  - `driver error: failed to bind listener`
- After rebooting the PC, that Dolos bind-listener startup failure was no
  longer reproduced in the latest verified rerun of
  `scripts/bridge_minting.sh`.

## Tx3 Ecosystem Notes

### Command map verified from `trix --help`

- `trix` is the main CLI entrypoint for the Tx3 workflow.
- Verified top-level commands include:
  - `init`
  - `invoke`
  - `devnet`
  - `explore`
  - `codegen`
  - `check`
  - `inspect`
  - `test`
  - `build`
  - `identities`
  - `profile`
- `trix invoke` accepts:
  - `--args-json`
  - `--args-json-path`
  - `--skip-submit`
- `trix test` runs a TOML test file.
- `trix devnet` starts a local development network powered by Dolos.

### Supporting tools verified from help output

- `cshell` is a separate CLI used by the Tx3 toolchain.
- Verified `cshell` top-level areas include:
  - `provider`
  - `tx`
  - `wallet`
  - `explorer`
  - `search`
- `trix identities` exposes these subcommands:
  - `address-testnet`
  - `address-mainnet`
  - `public-key`
  - `public-key-hash`

### File responsibilities verified in this repo

- `main.tx3` is the transaction protocol description consumed by Tx3.
- `trix.toml` is the Tx3 project config file for this repo.
- `devnet.toml` is the local funding / initial-UTxO file used by `trix devnet`.
- `tests/*.toml` are scenario files for `trix test`.
- `trix.toml` currently points the protocol `main` field at `main.tx3`.

### Runtime behavior verified while working on this repo

- `trix check` validates the Tx3 package and currently succeeds here.
- `trix build -v` currently succeeds here.
- `trix invoke` recompiles `main.tx3` before prompting for transaction
  selection.
- `trix test` recompiles `main.tx3`, then starts a Dolos daemon, then runs the
  listed transaction scenario(s).
- After the runtime-parameter flattening, `trix invoke` reached the interactive
  prompts for:
  - transaction selection
  - party binding for `user`
- `trix test` avoided the earlier `invalid param type` crash after the same
  flattening change.
- `cshell tx submit` accepts a CBOR transaction directly as its positional
  argument.
- `cshell tx sign` signs a CBOR transaction and can be used repo-locally to
  re-sign a patched prebuilt transaction.
- `scripts/submit_phase1_phase2_transactions_single_case.sh` now resolves `CSHELL_BIN` in this
  order:
  - explicit `CSHELL_BIN`
  - `bridge-aiken/.tools/bin/cshell`
  - `PATH`
- `scripts/submit_phase1_phase2_transactions_single_case.sh` now resolves `TRIX_BIN` in this
  order:
  - explicit `TRIX_BIN`
  - `bridge-aiken/.tools/bin/trix`
  - `PATH`
- `scripts/submit_phase1_phase2_transactions_single_case.sh` and `scripts/bridge_minting.sh`
  now resolve `DOLOS_BIN` from:
  - explicit `DOLOS_BIN`
  - sibling `../dolos/target/debug/dolos`
  - `PATH`

### Identity behavior verified with this installed `trix`

- `trix profile show local` reports the `local` profile identities as built-in:
  - `alice`
  - `bob`
  - `charlie`
- In a scratch Tx3 project, adding:
  - `[[wallets]]`
  - `name = "phase1user"`
  - `random_key = true`
  to `trix.toml` did **not** make `trix identities phase1user address-testnet`
  succeed.
- Therefore, in this installed `trix` version, `trix identities` was **not**
  observed to resolve arbitrary names from `[[wallets]]` in `trix.toml`.
- A project-local CShell store exists at:
  - `.tx3/cshell/cshell.toml`
- In this repo, `.tx3/cshell/cshell.toml` contains wallets named:
  - `alice`
  - `bob`
  - `charlie`
- Those project-local wallets are sufficient for `cshell wallet info -s
  .tx3/cshell/cshell.toml --name <wallet>` style inspection.
- However, simply creating or expecting `phase1user` at the Tx3 project level
  was **not** enough to make `trix identities phase1user ...` work.

### Important Tx3 / runtime quirks verified here

- Passing custom record-shaped runtime params directly to Tx3 caused:
  - `invalid param type`
- Reconstructing those records inside `locals` from primitive runtime args
  removed that specific failure.
- For the unresolved `source` input in `phase1_setup`, the runtime queried the
  address as a serialized hex credential/address string:
  - `600dd172b9b1866fd9513b96fcbe378a2d5adc7fb499949e8865d53edf`
- That means Tx3 runtime error messages for input resolution may show hex
  address data instead of bech32.
- `trix invoke` with `custom address` still ended up resolving the `source`
  input against the same hex address shown above.
- A previous attempt to put a raw hex address in `devnet.toml` caused `trix
  devnet` to reject it with a bech32 parse error, so the accepted format there
  was not raw hex in that attempt.
- For `phase1_setup`, funding `bob` with only one UTxO was not enough to get
  past input resolution.
- After funding `bob` with two UTxOs in `devnet.toml`, `phase1_setup` advanced
  past the `source` / `collateral` resolution stage.
- After editing `main.tx3`, `trix check` alone did **not** refresh
  `.tx3/tii/main.tii` in one verified case.
- In that verified case, the stale `.tx3/tii/main.tii` still exposed the old
  runtime parameter `phase1_token_name` even though `main.tx3` no longer
  declared it.
- Running `trix build` refreshed `.tx3/tii/main.tii` and removed that stale
  parameter.
- Therefore, when `cshell tx invoke` is driven directly from
  `.tx3/tii/main.tii`, `trix build` is the reliable step that refreshes the
  invoke interface after `main.tx3` edits.
- A `signers` block with this exact syntax compiles in `main.tx3`:
  - `signers {`
  - `  User,`
  - `}`
- With `User` bound to `bob`, that `signers` block produced a Cardano tx body
  that included `required_signers`.
- With the rebuilt TII and that `signers` block in place, the phase-1 tx body
  also minted the asset name equal to `phase1_state_reduced_hash`.
- Building `phase1_setup` with `phase2_output_lovelace = 0` produced a tx body
  whose script output carried:
  - lovelace: `0`
  - the phase-1 NFT
- Submitting that zero-lovelace variant failed before script success with:
  - `tx was not accepted: minimum lovelace requirement was not met`
- Therefore, the currently verified condition in `validators/phase1.ak`:
  - `assets.match(value, transaction.mint, ==)`
  is incompatible with a real accepted output that carries the minted NFT,
  because the accepted output must contain lovelace while `transaction.mint`
  does not.
- With the normal ADA-bearing phase-1 output and the `signers` block present,
  submitting the transaction caused Dolos to log a UPLC runtime panic:
  - `invalid number: InvalidDigit`
- In the same situation, `cshell tx invoke` returned:
  - `error sending request for url (http://localhost:8164/)`
- Therefore, after fixing the stale TII and required signer issues, there
  remained a separately verified runtime crash during script evaluation.
- The `phase1.phase1.mint` script hash currently present in `plutus.json` is:
  - `471502189ebd79c2b71c49f9f5e48b87584a81daf613ea1cdb9f9726`
- The hash printed by `aiken tx simulate`, for example:
  - `Simulating ecc651a5c8fefeb7559022b851301e5026ee697c7c31be30abc40822871211fc`
  is the hash of the transaction being simulated, **not** the hash of the
  script.
- The working file shapes for `aiken tx simulate` are:
  - tx file: CBOR hex for the full transaction
  - raw inputs file: CBOR hex for `List<TransactionInput>`
  - raw outputs file: CBOR hex for `List<TransactionOutput>`
- Passing resolved UTxOs directly as the "raw inputs" file caused Aiken to fail
  during parsing with:
  - `expected array`
- For the current `phase1_setup` transaction, `aiken tx simulate` succeeds in
  parsing the full context and then fails at script evaluation with:
  - `Mint[0] execution went over budget`
  - `Mem -463`
  - `CPU 2741492529`
- Increasing the redeemer ex-units inside the simulated transaction to values
  such as:
  - memory: `40_000_000`
  - cpu: `20_000_000_000`
  did **not** change that result.
- Therefore, in this setup, the current `phase1_setup` is not only a Tx3/Dolos
  issue; the same transaction also fails under `aiken tx simulate` by going
  over budget.
- A local runtime-probe test exists at:
  - `validators/tests/phase1_runtime_probe_test.ak`
- That runtime probe executes the real phase-1 mint validator path with the
  full proof fixture inside Aiken tests, and it currently passes.
- However, that runtime probe computes `phase1_verifier(...)` once to assemble
  the expected datum and then invokes the validator, which computes
  `phase1_verifier(...)` again internally.
- Therefore, `validators/tests/phase1_runtime_probe_test.ak` is useful for
  functional reproduction of the validator path, but its reported resource
  usage is not a direct one-to-one proxy for the real on-chain transaction.
- A small optimization attempt was tried in `proof_verifier_phase1.ak`:
  calculating `reduced_hash` directly from the 15 reduced-redeemer fields
  without first serializing through the `ReducedRedeemer` record.
- After rebuilding, the `phase1.phase1.mint` script hash remained:
  - `471502189ebd79c2b71c49f9f5e48b87584a81daf613ea1cdb9f9726`

## Verified Phase-2 Facts

- `validators/tests/phase2_runtime_probe_test.ak` executes the real
  `phase2.phase2.spend` path against a fixture derived from the phase-1 output
  state, and it currently passes under `aiken check`.
- The phase-2 runtime-probe uses:
  - the real `Phase2State`
  - the real `ReducedRedeemer`
  - the reduced-hash as token name
  - a receipt output that carries both lovelace and the phase-2 NFT
- `scripts/data/phase2_args_raw.json` contains the verified primitive runtime arguments for
  `phase2_verify`:
  - token name
  - locked lovelace
  - receipt lovelace
  - statement hash
  - the 15 reduced-redeemer fields
  - the explicit `user` binding
- With the patched local Dolos / `pallas-uplc` stack and a raised local
  `maxTxSize`, the verified end-to-end sequence was:
  - submit `phase1_setup`
  - then submit `phase2_verify`
  - then submit `stake_distribution_genesis_tx`
  - then submit `stake_distribution_standard_tx`
- The latest verified successful `phase1_setup` submit returned tx hash:
  - `1f9b3655ec717cb014f4276f1ee56e346f085a26213b6f7fc36b7749e7104afb`
- The latest verified successful `phase2_verify` submit returned tx hash:
  - `af1af54b306f25f49ca8892296b80e87c0353843912b38b4282f53e548e7d848`
- The latest verified successful `stake_distribution_genesis_tx` submit
  returned tx hash:
  - `e314dd68353544358a2d37e58f214d4d50f439675a5375c9b9f673ce27a04d5a`
- The latest verified successful `stake_distribution_standard_tx` submit
  returned tx hash:
  - `f337399704b100d7c3a2273237ca33874cda803406bfa4c411ec9c5e17889a97`
- The current stake-distribution design keeps:
  - the reduced full certificate in the standard spend redeemer
  - only the reduced chaining state in the stake-distribution datum
- In the current stake-distribution design, the reduced persisted state
  includes:
  - `hash`
  - `epoch`
  - `protocol_parameters`
  - `next_aggregate_verification_key`
  - `aggregate_verification_key`
  - `next_aggregate_verification_key_snark`
  - `aggregate_verification_key_snark`
- In the current standard spend path, the full reduced certificate remains in
  the redeemer and is **not** emitted in the recreated datum.
- After introducing that reduced design, `aiken check` was verified at that
  point with:
  - total tests: `95`
  - passed: `95`
  - failed: `0`
- In `stake_distribution_standard_tx`, using:
  - `amount: parent_certificate_input - fees`
  was verified to produce the wrong NFT in the recreated output.
- Replacing that output amount with an explicit reconstruction:
  - `Ada(parent_certificate_lovelace) + StakeDistributionNFT(1) - fees`
  was verified to restore the correct asset in the output and make the
  four-transaction script pass again.
- The latest verified end-to-end run of:
  - `KEEP_MITHRIL_STAKE_DISTRIBUTION_TMP=1 scripts/mithril_stake_distribution.sh`
  succeeded and printed:
  - `stake_distribution_genesis_tx` hash:
    - `4674e2e9883f5aa2a2d0c0b7b40495a0e77c30f30fa53304493ea1cf04e222d3`
  - `stake_distribution_standard_tx` hash:
    - `504903666eb4c9b5210180f419633a42ecc28c7124ac98b03e07e8e299f182a8`
  - `stake_distribution_genesis_tx` size:
    - `5847` bytes
  - `stake_distribution_standard_tx` size:
    - `5660` bytes
- The latest verified successful `stake_distribution_genesis_tx` submit
  returned tx hash:
  - `c46cf84a42f52a1227254b4dea052ce3f8b510874e49509157af2d7023418919`
- The latest verified successful `stake_distribution_standard_tx` submit
  returned tx hash:
  - `1f07025a768e15c3e66b179906e55ef625ec7dd5ca2392db4a3d87aa7ae01fa4`
- Reconstructing that same `phase2_verify` transaction with direct
  `cshell tx invoke --skip-submit` and then running `aiken tx simulate` was
  later verified to succeed for the current transaction hash:
  - `a2b9c4a8280c6b8ffe52a1aab54e4abff1d9eeb51a2b3e0ef1382cf37415e5a4`
- For the current phase-2 simulation, the working Aiken file shapes were
  verified to be:
  - tx file:
    - the full signed transaction CBOR hex
  - second file:
    - CBOR hex for `List<[TransactionId, OutputIndex]>`
    - for Conway transactions, this had to be normalized from the tx body's
      `Set<TransactionInput>` into a plain list of `[txid, index]` arrays
  - third file:
    - CBOR hex for the resolved consumed outputs
    - for the current `phase2_verify`, this was the output list from the
      phase-1 transaction with hash
      `5587565f03446b152deb0133310b697a2fb314fbeb17cb40ba82e7527483ccc9`
- Passing the wrong shapes to `aiken tx simulate` reproduced two distinct
  Aiken parser crashes:
  - when the second file was the raw Conway `Set<TransactionInput>` from the
    tx body:
    - `TypeMismatch(Tag)`
    - `expected array`
  - when the second file was the resolved consumed outputs instead of the
    normalized tx-input list:
    - `TypeMismatch(Map)`
    - `expected array`
- With the corrected file shapes, `aiken tx simulate` evaluated both current
  phase-2 scripts successfully and reported these exact budgets:
  - `Spend[0]`:
    - `mem: 722_076`
    - `cpu: 6_917_068_932`
  - `Mint[0]`:
    - `mem: 46_316`
    - `cpu: 219_412_354`
- Therefore, the current `phase2_verify` transaction is now independently
  verified to pass under `aiken tx simulate`; the remaining work for phase 2
  is in the Tx3 / Dolos submit path rather than in Aiken simulation.
- With the current future-snark `statement_hash = i_2` representation, the
  verified published transaction summaries are:
  - `phase1_setup`
    - `txSize = 21593`
    - `aiken cpu = 7213234545`
    - `aiken memory = 13719004`
  - `phase2_verify`
    - `txSize = 6603`
    - `aiken cpu = 7146163843`
    - `aiken memory = 789697`
  - `stake_distribution_genesis_tx`
    - `txSize = 6059`
    - `aiken cpu = 144367492`
    - `aiken memory = 289275`
  - `stake_distribution_standard_tx`
    - `txSize = 5855`
    - `aiken cpu = 463811561`
    - `aiken memory = 1530245`
- A later fresh verified passing run of
  `KEEP_MITHRIL_STAKE_DISTRIBUTION_TMP=1 scripts/mithril_stake_distribution.sh`
  returned these hashes:
  - `phase1_setup`
    - `ab0ff253a166805f949ea73d04caa585415cd8a3f912f3d8d46009b4f31c0cdb`
  - `phase2_verify`
    - `2ff308d523cbe572c0b0215d7dac860e21921d86426a2e2055dc9a319e8fc83c`
  - `stake_distribution_genesis_tx`
    - `a3c2917021ecafc71e0db903702074e195cc27639ceaf023462addac596603de`
  - `stake_distribution_standard_tx`
    - `a8124d5f70d0e82b7d8d60f78867fd0d3a44b8a6feb53417bf5ffbd1cb46a9d8`
- For the current toolchain, `stake_distribution_standard_tx` was verified to
  prebuild with the wrong normal input: it used the phase-2 receipt UTxO as
  both the spent input and the reference input.
- The current working repo-local workaround is implemented in
  `scripts/mithril_stake_distribution.sh`:
  - prebuild the standard tx with `--skip-submit`
  - patch body input `0` to the actual genesis stake-distribution UTxO
  - re-sign the patched CBOR with `cshell tx sign`
  - submit the patched CBOR with `cshell tx submit`
- Reordering the `UtxoRef` parameters in `main.tx3` for
  `stake_distribution_standard_tx` was **not** sufficient as a stable fix by
  itself; in a later fresh end-to-end run, the standard prebuild still used
  the phase-2 receipt UTxO as both normal input and reference input.
- For the current `stake_distribution_standard_tx`, keeping a separate user
  `source` input for fees caused CShell to build a tx body where the
  certificate script input was not the first spend input, and submit then
  failed with:
  - `tx was not accepted: script witness is missing`
- The currently verified working standard-certificate shape in `main.tx3`
  instead:
  - has no extra user `source` input
  - spends only `parent_certificate_utxo` as a regular input
  - keeps `phase2_receipt_utxo` only in `reference_inputs`
  - recreates the stake-distribution UTxO with:
    - `amount: parent_certificate_input - fees`
- `locking_txs_updater_genesis_tx` no longer references
  `phase2_receipt_utxo`; the phase-2 receipt is still part of
  `stake_distribution_*` and `bridge_mint_tx`, but not the updater genesis
  mint.
- In a fresh local emulator run, directly submitting that standard tx with
  `cshell tx invoke` still failed with:
  - `tx was not accepted: script witness is missing`
- Therefore, the currently verified working flow in:
  - `scripts/mithril_stake_distribution.sh`
  is:
  - prebuild `stake_distribution_standard_tx` with `--skip-submit`
  - patch body input `0` to the actual genesis stake-distribution UTxO
  - re-sign the patched CBOR with `cshell tx sign`
  - submit the patched CBOR with `cshell tx submit`
- Re-running `aiken tx simulate` after that optimization produced the exact
  same over-budget result:
  - `Mem -463`
  - `CPU 2741492529`
- Therefore, that field-direct `reduced_hash` micro-optimization did **not**
  change the compiled script hash and did **not** fix the runtime budget
  failure.
- Running `aiken check --plain-numbers` against the isolated tests produced
  these exact verified budgets:
  - `integration_test.{tx1_phase1_only}`:
    - `mem: 13_974_699`
    - `cpu: 7_247_448_026`
  - `phase1_runtime_probe_test.{phase1_validator_accepts_real_fixture_with_precomputed_state}`:
    - before the wrapper optimization:
      - `mem: 14_134_799`
      - `cpu: 7_307_350_528`
    - after the wrapper optimization in `validators/phase1.ak`:
      - `mem: 14_132_719`
      - `cpu: 7_306_952_112`
  - `phase1_runtime_probe_test.{phase1_validator_accepts_real_fixture_with_minimal_tx_context}`:
    - `mem: 28_097_330`
    - `cpu: 14_502_268_725`
- Therefore, replacing `find_script_outputs(...)` in `validators/phase1.ak`
  with a single-pass recursive scan over `transaction.outputs` reduced the
  precomputed-state runtime probe by:
  - `2080` memory
  - `398_416` cpu
- When manually syncing a compiled phase-1 script into `main.tx3`, the
  `cardano::plutus_witness` block for `phase1_setup` must keep a trailing comma
  after the `script:` field.
- Removing that trailing comma caused `trix check` to fail with:
  - `Parsing error: expected [data_add, data_sub, data_property, data_index]`
- The second `cardano::plutus_witness` block in the same file retained the
  working shape:
  - `script: 0x...,`
- Invoking `cshell tx invoke` directly against `.tx3/tii/main.tii` with the
  current flat JSON args and `user = "@bob"` failed before transaction
  construction with:
  - `invalid hex: Invalid character '@' at position 0`
- Replacing that `user` value with the concrete bech32 address of `bob`
  allowed the same direct `cshell tx invoke` command to succeed with
  `--skip-submit`.
- The successful direct `cshell tx invoke --skip-submit` run returned:
  - full transaction CBOR
  - transaction hash `847ae74321cb7ff25421dba1a735f885ec1e7334c3e977f7d6508be99d194913`
- Therefore, direct CShell invocation was verified to resolve inputs, build,
  and sign `phase1_setup` successfully once the `user` argument was already
  materialized as an address.
- Re-running `aiken tx simulate` on that rebuilt current transaction
  (`847ae74321cb7ff25421dba1a735f885ec1e7334c3e977f7d6508be99d194913`)
  with the existing raw input/output files still failed with the same verified
  budget error:
  - `Mint[0] execution went over budget`
  - `Mem -463`
  - `CPU 2741492529`
- Therefore, even after the later wrapper optimization, the currently rebuilt
  `phase1_setup` transaction was still independently failing under
  `aiken tx simulate`; fixing the Dolos panic alone would not be sufficient to
  make the transaction acceptable on-chain.
- After replacing the prefix G1 accumulation with a recursive helper that
  avoids allocating `take(...)` / `zip(...)` slices, the verified budgets
  became:
  - `integration_test.{tx1_phase1_only}`:
    - `mem: 13_791_229`
    - `cpu: 7_189_052_911`
  - `phase1_runtime_probe_test.{phase1_validator_accepts_real_fixture_with_precomputed_state}`:
    - `mem: 13_949_549`
    - `cpu: 7_248_604_997`
  - `phase1_runtime_probe_test.{phase1_validator_accepts_real_fixture_with_minimal_tx_context}`:
    - `mem: 27_728_910`
    - `cpu: 14_385_176_079`
- After additionally rewriting `compute_q_eval_for_set(...)` and
  `compute_v(...)` in `lib/halo2_kzg.ak` to avoid `zip` / `map` / `map2` /
  `concat` intermediate lists, the verified budgets became:
  - `integration_test.{tx1_phase1_only}`:
    - `mem: 13_617_656`
    - `cpu: 7_169_654_011`
  - `phase1_runtime_probe_test.{phase1_validator_accepts_real_fixture_with_precomputed_state}`:
    - `mem: 13_775_976`
    - `cpu: 7_229_206_097`
  - `phase1_runtime_probe_test.{phase1_validator_accepts_real_fixture_with_minimal_tx_context}`:
    - `mem: 27_381_564`
    - `cpu: 14_346_346_279`
- After syncing the newly compiled `phase1.phase1.mint` script into
  `main.tx3`, rebuilding `plutus.json`, and rebuilding `.tx3/tii/main.tii`,
  a fresh direct `cshell tx invoke --skip-submit` run produced:
  - transaction hash `5587565f03446b152deb0133310b697a2fb314fbeb17cb40ba82e7527483ccc9`
  - full transaction size `21639` bytes
- Running `aiken tx simulate` on that rebuilt current transaction then
  succeeded and reported:
  - `mem: 13_719_037`
  - `cpu: 7_215_063_523`
- Therefore, the current rebuilt `phase1_setup` transaction no longer goes
  over budget under `aiken tx simulate`; the remaining failure is no longer a
  script-budget failure in Aiken's simulator.
- The current compiled `phase1.phase1.mint` script hash in `plutus.json` is:
  - `9be3afcd78fd8dd698b627a2137c358dd8767f4fb99d44d34ab29a29`
- After that budget fix, submitting the same rebuilt transaction through
  direct `cshell tx invoke` still failed with:
  - `error sending request for url (http://localhost:8164/)`
- Re-running `trix test tests/phase1.toml -v` after the budget fix still
  failed at submit time with the same generic CShell / Dolos transport error.
- Running that same direct `cshell tx invoke` command without `--skip-submit`
  failed with:
  - `error sending request for url (http://localhost:8164/)`
- While reproducing that direct-submit failure, Dolos was run manually from
  `.tx3/dolos/` with:
  - `RUST_LOG=debug`
  - `RUST_BACKTRACE=1`
  - a user-local Dolos binary plus `daemon -c dolos.toml`
- In that captured-log setup, Dolos remained reachable on `http://localhost:8164/`;
  an HTTP `GET /` returned:
  - status `405 Method Not Allowed`
  - body `Used HTTP Method is not allowed. POST is required`
- During the direct-submit attempt, Dolos logged a panic from `pallas-uplc`:
  - `invalid number: InvalidDigit`
- The captured backtrace for that panic included:
  - `pallas_uplc::machine::runtime::<impl ...>::call`
  - `pallas_validate::phase2::tx::execute_script`
  - `pallas_validate::phase2::tx::eval_tx`
  - `dolos_cardano::validate::validate_tx`
- Therefore, the currently verified `phase1_setup` failure in the Tx3 runtime
  stack occurs after successful tx construction/signing, specifically during
  Dolos / Pallas script evaluation while handling the submit request.
- The current installed tool versions in this environment are:
  - `Dolos 1.0.2`
  - `trix 0.21.1`
  - `cshell 0.14.0`
- The `Cargo.lock` published for Dolos `v1.0.2` resolves these Pallas crates:
  - `pallas 1.0.0-alpha.4`
  - `pallas-validate 1.0.0-alpha.4`
  - `pallas-uplc 0.1.0`
- On crates.io, the latest verified `pallas` release visible during this work
  was:
  - `1.0.0-alpha.6`
  - updated at `2026-03-30T12:24:05.544646Z`
- In the current compiled `phase1.phase1.mint` script, `aiken uplc decode`
  revealed usage of these builtins among others:
  - `byteStringToInteger`
  - `integerToByteString`
  - `bls12_381_G1_uncompress`
  - `bls12_381_G1_compress`
  - `bls12_381_G1_add`
  - `bls12_381_G1_scalarMul`
  - `blake2b_256`
- Public TxPipe issue / PR data fetched during this investigation showed:
  - `txpipe/pallas#731` is open and reports a Conway validation bug in
    `pallas-validate`
  - `txpipe/pallas#733` is closed and fixes a Conway validation bug in
    `pallas-validate`
  - `txpipe/dolos#386` is a closed PR titled:
    `fix: temporarily hardcode ada_per_utxo_byte and PlutusV3 cost model protocol parameters`
  - `txpipe/dolos#737` is a merged PR titled:
    `fix(minibf): Handle cost models updates from proposals`
- The fetched patch for `txpipe/dolos#386` showed that Dolos had previously
  hardcoded Conway / Plutus V3 cost model values in its ledger parameter
  transition logic.
- The fetched patch for `txpipe/pallas#733` showed that a Conway validation bug
  in `pallas-validate` was fixed after `1.0.0-alpha.4`.
- No public GitHub issue was found during this investigation for the exact
  panic string:
  - `invalid number: InvalidDigit`
- No public GitHub issue was found during this investigation for these exact
  search terms against `txpipe/pallas` and `txpipe/dolos`:
  - `integerToByteString`
  - `byteStringToInteger`
  - `invalid number: InvalidDigit`

### Repo-local documented Tx3 workflow

- The sibling file `../tx3-protocol/README.md` documents the intended division
  of responsibilities for the Tx3 workflow in this broader project.
- That README explicitly describes these files as relevant to the Tx3 flow:
  - `main.tx3`
  - `trix.toml`
  - `devnet.toml`
  - compiled `plutus*.json`
  - `workflow.sh`
- That README also states that `workflow.sh` exists to orchestrate repetitive
  updates between compiled Aiken artifacts and the corresponding script hashes /
  witnesses that must be kept in sync in `main.tx3`.

### Practical working rule verified in this repo

- When changing Tx3 transaction parameters in `main.tx3`, the fastest feedback
  loop that worked in practice was:
  - edit `main.tx3`
  - run `trix check`
  - run `trix build -v` if needed
  - then re-run `trix invoke` or `trix test`
- For runtime debugging, `trix test` was useful because it automatically starts
  Dolos and runs a scripted scenario, while `trix invoke` was useful for seeing
  party-binding prompts and interactive resolution behavior.

## Verified Wallet / Tooling Facts

- `trix identities bob address-testnet` returned:
  - `addr_test1vqxazu4ekxrxlk238wt0e03h3gk44hrlkjvef85gvh2nahcgnmpfc`
- Running `cshell wallet list -o json` outside the sandbox returned `[]`.
- Running `cshell provider list -o json` outside the sandbox returned `[]`.

## Verified Current File State

- `tests/phase1.toml` currently exists.
- `tests/phase1.toml` currently targets the `phase1_setup` transaction and uses
  the integration-style fixture values inline.
- `trix.toml` currently contains:
  - `[protocol]`
  - `[ledger]`
  - `[[codegen]]`
- `trix.toml` currently does **not** declare project-local wallets.
- `devnet.toml` currently funds:
  - `@bob` with `100000000000`
  - `@bob` with `10000000`

## Verified Environment Behavior

- In this Codex environment, `aiken check` inside the sandbox previously
  crashed in the compiler/runtime path with:
  - `Attempted to create a NULL object`
- Running `aiken check` outside the sandbox succeeded.
- A later verified `aiken check` failure was caused by stale repo-local
  artifacts under:
  - `build/`
- Removing `build/` and re-running `aiken check` cleared that later failure.
- Removing `.tx3/` and re-running the flow did **not** recreate all required
  scaffolding through `trix build` alone.
- In that verified state, `trix build -v` recreated:
  - `.tx3/tii/main.tii`
- But it did **not** recreate:
  - `.tx3/cshell/cshell.toml`
  - `.tx3/dolos/dolos.toml`
  - `.tx3/dolos/byron.json`
  - `.tx3/dolos/shelley.json`
  - `.tx3/dolos/alonzo.json`
  - `.tx3/dolos/conway.json`
- Therefore, the repo now uses a repo-local bootstrap helper:
  - `scripts/python/bootstrap_tx3_scaffolding.py`
- That helper currently:
  - writes `.tx3/cshell/cshell.toml`
  - writes `.tx3/dolos/dolos.toml`
  - copies the four Dolos devnet genesis JSON files from:
    - `../dolos/crates/cardano/src/include/devnet/`
- That bootstrap was directly verified to let both:
  - `scripts/mithril_stake_distribution.sh`
  - `scripts/bridge_minting.sh`
  pass again starting from a missing `.tx3/`
- This was verified as a repo-local operability workaround, not as a native
  `trix` / Tx3 bootstrap feature.

## Recent Verified Flow Facts

- Un nuevo test Python repo-local ahora fija el diagnóstico del publish del
  phase-1 reference script en:
  - `scripts/tests/test_phase1_reference_script_publish.py`
- Ese test verifica tres cosas:
  - `main.tx3` embebe byte a byte el mismo `compiledCode` que
    `plutus.json` para `phase1.phase1.mint`
  - `trix inspect tir --tx publish_phase1_reference_script` conserva ese
    mismo `compiledCode` crudo dentro de `adhoc.cardano_publish.script`
  - el artifact checked-in de
    `../zk-bridge-operator/preview_phase12/publish-phase1-reference-script/tx-envelope.json`
    publica un payload de reference script con doble envoltura CBOR
  - el artifact checked-in de Preview queda detectado como stale respecto del
    hash `Phase1` actual esperado por `plutus.json`
- Diagnóstico operativo refinado:
  - el desalineamiento `68e2...` vs `5bdf...` que bloqueaba `phase1_setup`
    no nace en el sync `plutus.json -> main.tx3`
  - tampoco nace en el TIR emitido por `trix inspect tir`
  - la evidencia verificada hoy es que el blocker real en el lane Preview era
    un artifact checked-in stale del publish `phase1`, no el source actual del
    bridge
- Forma concreta observada en el artifact checked-in:
  - el payload del reference script se decodifica como un CBOR array:
    - `[3, <bytes>]`
  - y ese segundo elemento vuelve a decodificar como otro `bytes`
  - ese shape quedó útil para reconocer artifacts viejos, pero no fue el
    blocker del source actual una vez que se regeneró un publish fresco
- Verificación decisiva posterior:
  - un publish fresco generado con:
    - `preview invoke-cli-publish-phase1-reference-script --skip-submit`
  - y luego reusado por:
    - `preview invoke-cli-phase1-setup --validate`
    pasó con:
    - `validators_true = true`
    - `cpu = 7072877216`
    - `mem = 13251108`
- Conclusión operativa actual:
  - el flujo source actual de `publish_phase1_reference_script` / `trix inspect tir`
    está bien para el hash `Phase1` vigente
  - el problema real era reusar el artifact checked-in viejo del operador
- Hardening posterior del operador Preview:
  - una tx real de `phase1_setup --submit --validate`
    (`c725126c4f6f15d1410f7c36d9bacc96c93d5a831ff9ad70c22100697455caeb`)
    mostró que la primera versión de `--validate` todavía podía devolver un
    falso positivo local
  - Blockfrost la observó luego con:
    - `valid_contract = false`
    - `fees = 7000000`
    - `outputs = []`
  - a partir de eso, el operador endureció `--validate` en dos capas:
    - reconstrucción exacta de contexto desde CBOR de cadena
    - veredicto post-submit de Blockfrost cuando se usa `--submit`
  - además, tras un reintento con collateral chico confirmado, se verificó un
    lag adicional de Demeter/TRP para refs frescas:
    - Blockfrost ya mostraba confirmado
    - pero TRP seguía devolviendo `input not resolved: collateral`
  - por eso el operador ahora también espera una ventana mínima antes de
    reusar refs recién confirmadas contra Demeter/TRP
- Regla reusable para futuras txs Preview del mismo patrón:
  - no compartir el mismo plain-ADA UTxO entre `source_utxo` y
    `collateral_utxo`
  - persistir ambos refs entre corridas
  - rotar sólo el `source_utxo` al change output de la última tx exitosa
  - mantener el `collateral_utxo` si la tx fue válida y no lo consumió
  - considerar Blockfrost `valid_contract = true` como señal final de éxito por
    encima de `trp.checkStatus`

- `main.tx3` currently also defines:
  - `publish_phase1_reference_script`
- The current repo-local `phase1` flow is now a 3-transaction sequence:
  - `publish_phase1_reference_script`
  - `phase1_setup`
  - `phase2_verify`
- A repo-local non-interactive publish fixture file now exists at:
  - `scripts/data/publish_phase1_reference_script_args_raw.json`
- `main.tx3` now publishes the phase-1 minting script through a separate
  `publish_phase1_reference_script` transaction.
- In the current `main.tx3`, `phase1_setup` now consumes the phase-1 script as
  a `reference` script input instead of embedding the phase-1 compiled code as
  an inline Plutus witness.
- The current `scripts/submit_phase1_phase2_transactions_single_case.sh` asserts that each of
  these three transactions stays below:
  - `16384` bytes
- With the current reference-script flow and local `maxTxSize = 16384`, the
  latest verified transaction sizes are:
  - `publish_phase1_reference_script`
    - `16374`
  - `phase1_setup`
    - `4677`
  - `phase2_verify`
    - `6560`
- The current repo-local `phase2_verify` no longer emits a separate normal
  collateral output; it now relies only on the real `collateral { ... }`
  transaction field.
- Before that fix, `phase2_verify` could underflow the user change output and
  make Dolos / pallas panic with:
  - `attempt to add with overflow`
- The current repo-local `scripts/mithril_stake_distribution.sh` no longer
  re-parameterizes the stake-distribution unique-mint source in `env/default.ak`.
- That script restores the original `env/default.ak` and `main.tx3` on exit.
- In the current verified repo-local flow,
  `scripts/mithril_stake_distribution.sh` uses the phase-2 receipt UTxO as the
  default `stake_distribution` unique-mint source:
  - `${PHASE2_HASH}#0`
- Using the `publish_phase1_reference_script` UTxO as that default
  `stake_distribution` unique-mint source was directly verified to make
  `stake_distribution_genesis_tx` fail with:
  - `reference input is not present in the UTxO set`
- The latest verified successful run of
  `KEEP_MITHRIL_STAKE_DISTRIBUTION_TMP=1 scripts/mithril_stake_distribution.sh`
  reported:
  - `stake_distribution_genesis_tx`
    - `txSize = 6130`
    - `hash = e92c568c8a15e4404c385b8fdbca274567acc3d4c01fbf028222ebabb0864fc8`
  - `stake_distribution_standard_tx`
    - `txSize = 5821`
    - `hash = 528edb0a77d776151747b4731984aac9259cdf5bdfd356b68ec3b0c2e030dfb4`
- The current repo-local `scripts/bridge_minting.sh` now also prints the hash
  of `publish_phase1_reference_script` in its final summary.
- That script also restores the original `env/default.ak` and `main.tx3` on
  exit.
- The old patch path for `locking_txs_updater_genesis_tx` assumed a fixed wrong
  input UTxO and was directly verified to fail after the reference-script
  refactor with:
  - `wrong input utxo not present in tx body`
- A later verified state removed the final flow's CBOR post-build patching for:
  - `locking_txs_updater_genesis_tx`
  - `bridge_mint_tx`
- In that later verified state, both transactions submit directly with
  `cshell tx invoke`.
- The old patch path for `bridge_mint_tx` assumed a fixed wrong input UTxO and
  was directly verified to fail with:
  - `wrong input 9cc79ff0ca641b1de66417cf10a57200892d9c2f0cc1a29aa504660fa596625c#0 not found`
- A later verified state also removed the final flow's CBOR post-build
  patching for:
  - `stake_distribution_standard_tx`
- In that later verified state, `scripts/mithril_stake_distribution.sh`
  submits `stake_distribution_standard_tx` directly with `cshell tx invoke`.
- The repo-local helper
  `scripts/python/patch_tx_input_and_sign.py`
  was removed after that direct-submit path was verified.
- A repo-local regression check was later verified directly through:
  - `./scripts/bridge.sh bridge`
  with vendored Dolos and the standard installed `cshell`
- The latest verified successful direct bridge run in that lane reported:
  - `stake_distribution_standard_tx`
    - `hash = 528edb0a77d776151747b4731984aac9259cdf5bdfd356b68ec3b0c2e030dfb4`
  - `bridge_mint_tx`
    - `hash = 40d074822c28a4c4b88e580d64e1eaea517953f08af58956c2057ca1dfaa9f43`
- In the current verified bridge flow, the remaining Tx3 / CShell runtime
  limitation is that direct runtime params of type `Custom(...)` still fail
  with:
  - `invalid param type`
- Therefore, the current verified bridge flow keeps redeemer/runtime args
  flattened to primitive fields instead of passing custom records directly.
- `scripts/sync_phase_scripts_to_tx3.sh` no longer uses three hardcoded sync
  rounds.
- It now runs a convergence loop of:
  - `aiken build`
  - `aiken blueprint apply`
  - `python sync_phase_scripts_to_tx3.py`
  until `main.tx3` and `env/default.ak` stop changing.
- In a direct verified run with unchanged parameters,
  `scripts/sync_phase_scripts_to_tx3.sh` finished after:
  - `1` round
- In a direct verified run from `scripts/bridge_minting.sh` after changing both
  the stake-distribution and locking-txs-updater parameters, that same sync
  process finished after:
  - `3` rounds
- The latest verified successful run of
  `KEEP_MITHRIL_BRIDGE_MINTING_TMP=1 scripts/bridge_minting.sh` reported:
  - `publish_phase1_reference_script`
    - `hash = e3a658b11e94aa61f6a6969e3a7332857a4660232c0a8f7d0ab7fecceacf78c0`
  - `phase1_setup`
    - `hash = 5f1b2b78904370af3bb6e7e36e36b94489a9099373ccfcc3d0c41d5523b5c630`
  - `phase2_verify`
    - `hash = 525df7390c918cf1ac1b410292ac1412c9d4dfcfe6eb8e3de73641133e87c196`
  - `stake_distribution_genesis_tx`
    - `hash = bd0975e263b4561ffc2ef6bcd8a86e2a096bf927910434373d8d56dbe606c58f`
  - `stake_distribution_standard_tx`
    - `hash = 187d6bf08d930647193cac6ce7e4dc9d3180871cc3d9e6538c22459626467f03`
  - `locking_txs_updater_seed_tx`
    - `hash = 1b34931802b72ce40e9acc4e0241adfdfa71f348811740989203244e1f4c9b40`
  - `publish_locking_txs_updater_spend_reference_script`
    - `hash = 39332f92a9a237a32ea87cfa2ab2b9152b2b754eccfa17759f9db6e6b8ed5f0e`
  - `publish_bridge_minting_reference_script`
    - `hash = a033f64ac380b8da6340daeddd06000023b139e9d69bdc84425abbf4a1dc1ffd`
  - `locking_txs_updater_genesis_tx`
    - `hash = 024a27922f367ce9889533c0eac1c0d02bfe64e1dd4e896dc379d841e63ebff6`
  - `bridge_mint_tx`
    - `hash = 084a25b2d2dc6f08d554d6bf4ea4f2f3cb950c14b8d0b231136c583d728da417`
- In the current verified bridge flow, `bridge_parent_certificate_reference_tx`
  is no longer part of the end-to-end path.
- `main.tx3` now also defines:
  - `publish_locking_txs_updater_spend_reference_script`
  - `publish_bridge_minting_reference_script`
- The current `bridge_mint_tx` template no longer carries inline
  `cardano::plutus_witness` blocks for:
  - the locking-txs-updater spending script
  - the bridge minting policy
- The current `bridge_mint_tx` instead takes and references:
  - `locking_txs_updater_spend_reference_script_utxo`
  - `bridge_minting_reference_script_utxo`
- `scripts/python/sync_phase_scripts_to_tx3.py` now syncs the compiled bridge
  scripts into those two new `cardano::publish` transactions in `main.tx3`.
- `scripts/python/prepare_mithril_bridge_minting_args.py` now emits placeholder
  fields for:
  - `locking_txs_updater_spend_reference_script_utxo`
  - `bridge_minting_reference_script_utxo`
- `scripts/bridge_minting.sh` now publishes both bridge reference scripts
  before `locking_txs_updater_genesis_tx` and threads their resulting UTxOs
  into `bridge_mint_tx`.
- `scripts/bridge_minting.sh` now also verifies the generated Aiken bridge
  fixture is in sync before starting the vendored bridge flow by running:
  - `python3 scripts/python/sync_bridge_zk_fixture.py --check`
- A repo-local Python args helper now exists at:
  - `scripts/python/arg_builder_common.py`
- That helper currently centralizes:
  - `as_bytes_hex(...)`
  - `ascii_bytes_hex(...)`
  - `read_json(...)`
  - `write_json(...)`
  - `parse_env_text_const(...)`
  - `parse_env_policy_const(...)`
- `scripts/python/prepare_mithril_stake_distribution_args.py` and
  `scripts/python/prepare_mithril_bridge_minting_args.py` currently use that
  shared helper for JSON IO and Tx3 byte-hex argument formatting.
- `scripts/python/prepare_mithril_bridge_minting_args.py` now keeps CLI/IO
  orchestration in `main()` and separates bridge-args data transformation into:
  - `load_bridge_minting_inputs(...)`
  - `bridge_locking_tx_args(...)`
  - `build_genesis_args(...)`
  - `build_bridge_args(...)`
- The bech32 payment-key-hash helper used by
  `scripts/python/prepare_mithril_bridge_minting_args.py` now lives in:
  - `scripts/python/bech32.py`
- The refactor of `scripts/python/prepare_mithril_bridge_minting_args.py` was
  checked against pre-change generated JSON snapshots with byte-identical
  outputs for:
  - `locking-txs-updater-genesis-args.json`
  - `bridge-mint-args.json`
- `scripts/python/prepare_mithril_bridge_minting_args.py` now treats
  `locking_tx_hash_hex` in `scripts/data/bridge_mint_raw.json` as the checked
  fixture value for the canonical Cardano tx hash.
- `validators/tests/bridge_fixture_test.ak` now verifies that the generated
  bridge redeemers thread `bridge_fixture.final_locking_tx_hash` through
  consistently as the canonical transaction id.
- The previously present local `scripts/rust/compute_script_data_hash` tree was
  removed after verifying no repo references to `scripts/rust`,
  `compute_script_data_hash`, or script-data-hash tooling outside that removed
  tree.
- `scripts/lib/integration_common.sh` now also centralizes the common CShell
  wrappers used by integrated flows:
  - `cshell_tx_invoke(...)`
  - `cshell_tx_submit(...)`
  - `cshell_tx_sign(...)`
- `scripts/submit_phase1_phase2_transactions_single_case.sh`,
  `scripts/mithril_stake_distribution.sh`, and `scripts/bridge_minting.sh`
  now call those wrapper functions instead of repeating the common
  `cshell tx invoke/submit/sign` flag blocks inline.
- `scripts/sync_phase_scripts_to_tx3.sh` now separates the sync pipeline into
  named phases:
  - `validate_inputs`
  - `build_aiken_artifacts`
  - `sync_tx3_once`
  - `sync_round_converged`
  - `run_sync_rounds`
  - `refresh_tx3_interface_if_needed`
- `scripts/python/sync_phase_scripts_to_tx3.py` now represents its scoped Tx3
  replacements declaratively through `Replacement` entries consumed by
  `apply_replacements(...)`.
- `scripts/python/sync_phase_scripts_to_tx3.py` now also represents its bridge
  post-sync checks declaratively through `MatchCheck` entries consumed by
  `require_matches(...)`.
- After that declarative sync-script refactor, a direct phase1/phase2 sync-only
  check passed with:
  - `SYNC_BUILD_TX3=0 SYNC_SCOPE=phase12 ./scripts/sync_phase_scripts_to_tx3.sh`
- A repo-local integration bash helper now exists at:
  - `scripts/lib/integration_common.sh`
- That helper currently centralizes:
  - `print_tx_publish_summary(...)`
  - `reference_script_output_index(...)`
  - `cshell_tx_invoke(...)`
  - `cshell_tx_submit(...)`
  - `cshell_tx_sign(...)`
- The current integrated bash flows source that shared helper:
  - `scripts/submit_phase1_phase2_transactions_single_case.sh`
  - `scripts/mithril_stake_distribution.sh`
  - `scripts/bridge_minting.sh`
- The current integrated bash flows now call those `cshell_*` wrappers instead
  of repeating direct `"$CSHELL_BIN" tx invoke`, `tx submit`, and `tx sign`
  flag blocks at each call site.
- After extracting that shared helper, the smallest integrated flow covering
  the phase1/phase2 route was re-verified via:
  - `./scripts/submit_phase1_phase2_transactions_single_case.sh`
- That latest direct phase1/phase2 rerun produced:
  - `publish_phase1_reference_script = e3a658b11e94aa61f6a6969e3a7332857a4660232c0a8f7d0ab7fecceacf78c0`
  - `phase1_setup = 5f1b2b78904370af3bb6e7e36e36b94489a9099373ccfcc3d0c41d5523b5c630`
  - `phase2_verify = 525df7390c918cf1ac1b410292ac1412c9d4dfcfe6eb8e3de73641133e87c196`
- A later verified full bridge flow with those published bridge reference
  scripts succeeded end to end via:
  - `./scripts/bridge_minting.sh`
- The latest verified full bridge flow with those published bridge reference
  scripts produced these transaction hashes:
  - `publish_phase1_reference_script = e3a658b11e94aa61f6a6969e3a7332857a4660232c0a8f7d0ab7fecceacf78c0`
  - `phase1_setup = 5f1b2b78904370af3bb6e7e36e36b94489a9099373ccfcc3d0c41d5523b5c630`
  - `phase2_verify = 525df7390c918cf1ac1b410292ac1412c9d4dfcfe6eb8e3de73641133e87c196`
  - `stake_distribution_genesis_tx = bd0975e263b4561ffc2ef6bcd8a86e2a096bf927910434373d8d56dbe606c58f`
  - `stake_distribution_standard_tx = 187d6bf08d930647193cac6ce7e4dc9d3180871cc3d9e6538c22459626467f03`
  - `locking_txs_updater_seed_tx = 1b34931802b72ce40e9acc4e0241adfdfa71f348811740989203244e1f4c9b40`
  - `publish_locking_txs_updater_spend_reference_script = 39332f92a9a237a32ea87cfa2ab2b9152b2b754eccfa17759f9db6e6b8ed5f0e`
  - `publish_bridge_minting_reference_script = a033f64ac380b8da6340daeddd06000023b139e9d69bdc84425abbf4a1dc1ffd`
  - `locking_txs_updater_genesis_tx = 024a27922f367ce9889533c0eac1c0d02bfe64e1dd4e896dc379d841e63ebff6`
  - `bridge_mint_tx = 084a25b2d2dc6f08d554d6bf4ea4f2f3cb950c14b8d0b231136c583d728da417`
- The latest verified `bridge-flow-summary.csv` for that run recorded these
  sizes:
  - `publish_locking_txs_updater_spend_reference_script = 6841 bytes`
  - `publish_bridge_minting_reference_script = 8033 bytes`
  - `locking_txs_updater_genesis_tx = 1566 bytes`
  - `bridge_mint_tx = 2220 bytes`
- In that later verified flow, `bridge_mint_tx` reported:
  - `cpu_units = 5782728942`
  - `memory_units = 2435480`

## Handoff Notes

This section is a practical handoff for future conversations. It is not a
claim that the proposed next steps have already been executed.

- The previously blocking script-budget problem for `phase1_setup` is now
  solved under `aiken tx simulate`.
- The submit-time failure in the Tx3 / CShell / Dolos stack was successfully
  driven past multiple runtime crashes by patching local copies of
  `pallas-uplc` and Dolos. Those fixes were applied only in `/tmp` clones
  during investigation; they are not yet committed anywhere in this repo.
- The most recent verified successful budget result for the rebuilt real
  `phase1_setup` transaction is:
  - transaction hash `5587565f03446b152deb0133310b697a2fb314fbeb17cb40ba82e7527483ccc9`
  - `mem: 13_719_037`
  - `cpu: 7_215_063_523`
- The original unpatched Dolos failure chain for direct submit of that same tx
  was verified as:
  - first, `transaction size exceeds the maximum allowed` with
    `maxTxSize = 16384`
  - after temporarily raising `maxTxSize` to `32768`, Dolos / Pallas panicked
    with:
    - `invalid number: InvalidDigit`
- The current locally verified patch sequence that drove the tx past those
  crashes was:
  - in local `pallas-uplc` (`../uplc-turbo/crates/uplc/src/machine/runtime.rs`):
    - replace
      `ibig!(INTEGER_TO_BYTE_STRING_MAXIMUM_OUTPUT_LENGTH)` with
      `Integer::from(INTEGER_TO_BYTE_STRING_MAXIMUM_OUTPUT_LENGTH)` in
      `IntegerToByteString`
    - result: the original `invalid number: InvalidDigit` panic disappeared
  - in local `pallas-uplc` (`../uplc-turbo/crates/uplc/src/flat/decode/decoder.rs`):
    - change `big_word()` to shift a `UBig` with `usize` instead of shifting a
      `u32`
    - result: the next crash changed from stack transport failure to a new
      panic:
      - `attempt to shift left with overflow`
    - after this patch, that overflow disappeared
  - in local Dolos (`../dolos/src/bin/dolos/daemon.rs`):
    - replace `#[tokio::main]` with an explicit Tokio runtime builder using:
      - `thread_stack_size = 32 * 1024 * 1024`
    - result: the next crash changed from:
      - `thread 'tokio-runtime-worker' has overflowed its stack`
      to a later runtime panic, proving the stack-overflow blocker itself was
      bypassed
  - in local `pallas-uplc` (`../uplc-turbo/crates/uplc/src/machine/runtime.rs`):
    - for both `Bls12_381_G1_ScalarMul` and `Bls12_381_G2_ScalarMul`, stop
      forcing the reduced scalar through `i32`
    - instead, serialize the reduced big integer with `ubig_to_bytes(...,
      Endianness::Big)` before feeding `blst_scalar_from_bendian`
    - result: the next panic disappeared:
      - `called Result::unwrap() on an Err value: OutOfBoundsError`
- With all of those local patches active, direct submit behavior was verified
  as:
  - with the repo's normal `shelley.json` still at `maxTxSize = 16384`:
    - `cshell tx invoke ...` returned a normal ledger/runtime error:
      - `tx was not accepted: transaction size exceeds the maximum allowed`
  - with a temporary external copy `/tmp/shelley-phase1.json` using
    `maxTxSize = 32768` and a temporary Dolos config
    `/tmp/dolos-phase1-large.toml` pointing at that file:
    - `cshell tx invoke ...` exited successfully
    - it returned the tx hash:
      - `5587565f03446b152deb0133310b697a2fb314fbeb17cb40ba82e7527483ccc9`
    - no `pallas-uplc` panic was observed in that successful run
- Therefore, the previously blocking submit-time failure was not a single bug.
  It was at least this chain of issues:
  - `maxTxSize` too small for the built tx in local Dolos
  - `IntegerToByteString` comparison bug in `pallas-uplc`
  - `big_word()` left-shift overflow in `pallas-uplc` flat decoder
  - insufficient Tokio worker stack in Dolos for this decode/eval path
  - invalid `i32` narrowing in BLS scalar multiplication inside `pallas-uplc`
- The `bridge-aiken` worktree was restored after those experiments:
  - `.tx3/dolos/shelley.json` was returned to `maxTxSize = 16384`
  - the only remaining repo-local dirty file observed afterward was:
    - `.gitignore`
- In the sibling workspace `../uplc-turbo`, the current
  `crates/uplc/src/machine/runtime.rs` implementation for:
  - `Bls12_381_G1_ScalarMul`
  - `Bls12_381_G2_ScalarMul`
  was observed to left-pad the scalar byte array by calling:
  - `BumpVec::with_capacity_in(diff, self.arena)`
  - `set_len(diff)`
  before `append(...)`
- That pattern leaves the leading padding bytes uninitialized instead of
  explicitly zeroed.
- Replacing that padding logic so the leading `diff` bytes are actual `0x00`
  values made the previously intermittent local `phase2_verify` submit result
  stable in this environment.
- After rebuilding sibling `../dolos` against that `uplc-turbo` fix, running
  `scripts/submit_phase1_phase2_transactions_single_case.sh` from this repo succeeded in
  repeated consecutive runs with the same tx hashes:
  - `phase1_setup`:
    - `21ef923dd0b1ff3a3416d01512ce2461cdaa61cbdfb45c0f4985e22a53dbbf0b`
  - `phase2_verify`:
    - `c1e9bd4a5191811ffddb645fb61460e1acae5abee38d36abfbf8fa892ca25fa0`

### Suggested Next Steps

- Upstream or permanently vendor the three `pallas-uplc` fixes verified in the
  `/tmp` clone:
  - `IntegerToByteString` maximum-length comparison
  - `flat::decode::Decoder::big_word()`
  - BLS scalar multiplication integer-to-bytes conversion
- Decide whether the larger Tokio worker stack belongs in Dolos itself or
  whether the real long-term fix should instead be an iterative / less-recursive
  UPLC decode path.
- If local phase-1 submit should keep working in this repo's default test flow,
  choose one of these paths explicitly:
  - keep `.tx3/dolos/shelley.json` at `16384` and accept that current
    `phase1_setup` is too large for the local emulator default
  - or raise local `maxTxSize` in the Dolos fixture used for this project
- After promoting the verified patches out of `/tmp`, re-run:
  - `cshell tx invoke ...` without `--skip-submit`
  - `trix test tests/phase1.toml -v`
  to confirm the normal project workflow now survives submit-time evaluation.

## Mithril STM PoC debugging notes

- During the post-stage-4 PoC validation with a real `mithril_stm_artifact.json`
  exported from `plutus-halo2-verifier-gen`, the current status became:
  - `phase1` in `bridge-aiken` accepts the artifact-derived proof/state path
  - `phase2` still rejects the same artifact in Aiken and in the Dolos tx flow
- A dedicated probe was added locally in:
  - `validators/tests/phase2_exported_artifact_probe_test.ak`
  - `lib/two_phase/phase2_exported_artifact_fixture.ak`
- Those probes established a very important fact:
  - `phase1_verifier(...)` reconstructs exactly the exported artifact's
    `Phase1State`
  - `phase1_verifier(...)` also reconstructs exactly the exported artifact's
    `ReducedRedeemer`
  - but `phase2_verifier(state, reduced_redeemer)` still fails for that same
    real proof
- Therefore the current blocker is not:
  - JSON plumbing
  - `build_phase12_args_from_mithril_artifact.py`
  - `prepare_tx3_dolos_env.py`
  - `ReducedRedeemer` field mapping
  - `Phase1State` field mapping
- The blocker is narrowed to the Aiken-side `phase2` execution path itself, or
  to something `phase2` depends on at runtime.
- A first high-probability hypothesis was stale verifier constants only used by
  `phase2`, especially `g2_const`.
- That specific hypothesis was checked and rejected:
  - `bridge-aiken/lib/halo2/verifier_key.ak`
  - `plutus-halo2-verifier-gen/aiken-verifier/aiken_halo2/lib/verifier_key.ak`
  currently match for:
    - `g2_const`
    - `neg_g1_generator`
    - `omega`
    - `transcript_rep`
- Practical implication for future conversations:
  - if someone says "the real artifact still fails in phase2", do not spend
    time re-debugging the artifact JSON contract first
  - the evidence already points deeper into the Aiken `phase2` verifier path
    than the artifact/export wiring
## 2026-04-13 - Mithril STM real artifact follow-up

- El fixture real de `bridge-aiken/lib/two_phase/phase2_exported_artifact_fixture.ak`
  corresponde al artifact real en `/tmp/tmp.9GSO8FfnAT/mithril_stm_artifact.json`
  y su bundle `/tmp/tmp.9GSO8FfnAT/mithril_stm_bundle.json`.
- `phase1_verifier(...)` sobre ese proof real reconstruye exactamente el
  `Phase1State` y el `ReducedRedeemer` exportados por
  `plutus-halo2-verifier-gen`.
- El acumulador derecho de `phase2` ya quedó confirmado para el artifact real:
  `phase2_right_accumulator_bytes(state, redeemer)` produce
  `0x8d2a34bfe1445c7afa4260f248b32e697fc26678ac99f413f5d7ec81794a81f61f37399a771dfe63a193541b5094eba7`.
- Ese mismo valor coincide con Rust usando el helper nuevo
  `cargo run --bin debug_mithril_stm_split -- --bundle <bundle.json> --artifact <artifact.json>`.
- Con eso, el problema ya no está en el split `Phase1State + ReducedRedeemer`
  ni en el cableado JSON del artifact real.
- El bloqueo actual del PoC está acotado al paso final de pairing en
  `lib/two_phase/proof_verifier_phase2.ak`: `phase2_verifier(...)` falla para el
  artifact real aun cuando el `right accumulator` ya coincide con Rust.
- Estado actual de `aiken check` después de corregir el expected accumulator:
  118 tests pasan y sólo fallan:
  `phase2_verifier_accepts_phase1_output_for_exported_artifact` y
  `phase2_runtime_probe_accepts_exported_artifact_fixture`.
## 2026-04-13 - Pairing follow-up after native_right check

- Se reforzó el probe de Rust para que también reporte `native_right`, no sólo
  `native_left`, `full_right` y `split_right`.
- Para el artifact real de `/tmp/tmp.9GSO8FfnAT` quedó confirmado ya sin
  ambigüedad:
  - `native_left == parsed_pi_term`
  - `native_right == full_right == split_right`
  - `s_g2` del circuito recompuesto coincide con `g2_const` versionado en
    `bridge-aiken/lib/halo2/verifier_key.ak`
- Se probaron variantes simples del pairing/signo para el artifact real
  (`current`, negando `right` en G1, negando `left` en G1, negando `right` en
  G2) y ninguna cerró.
- También se probó regenerar el mismo artifact real con varios
  `proving_seed` (`0..7`) y el probe de pairing en Rust siguió dando falso para
  las variantes simples en todos los casos.
- Implicación práctica:
  - el bloqueo ya no apunta al split TX1/TX2 ni al artifact/export
  - tampoco parece resolverse con un cambio trivial de signo o con cambiar el
    randomness de la prueba
  - lo que queda por investigar es una discrepancia más profunda entre la capa
    de pairing usada por `bridge-aiken`/`blstrs` y la verificación nativa de
    Midnight para este proof real
## 2026-04-13 - Generated full verifier comparison

- Para comparar la opción "verificador full generado" contra el camino
  `phase1 + phase2`, se montó en `bridge-aiken` una copia del verifier generado:
  `lib/two_phase/generated_full_verifier.ak`.
- Ese módulo se obtuvo desde
  `plutus-halo2-verifier-gen/aiken-verifier/aiken_halo2/lib/proof_verifier.ak`
  ajustando sólo los paths de imports para reutilizar las librerías de
  `bridge-aiken`.
- También se agregó el probe
  `validators/tests/generated_full_verifier_probe_test.ak`.
- Resultado clave:
  - con el artifact real exportado, el verifier full generado y el camino
    `phase1_verifier(...) -> phase2_verifier(...)` devuelven lo mismo
  - y ese resultado es rechazo para el artifact real actual
- Consecuencia práctica:
  - el problema ya no es específico del split TX1/TX2
  - también afecta al verifier Aiken full generado desde `verifier-gen`
  - por lo tanto el siguiente foco ya no debe ser "cómo se partió el MSM",
    sino la discrepancia entre el verifier Aiken/Plutus y la verificación
    nativa de Midnight para este proof real
## 2026-04-13 - Exact failure point inside Aiken

- Se expuso el último paso de `phase2` como helper reutilizable en
  `lib/two_phase/proof_verifier_phase2.ak`:
  `phase2_final_pairing_check_bytes(pi_term, right_accumulator)`.
- Se agregaron probes en
  `validators/tests/phase2_exported_artifact_probe_test.ak` para medir por
  separado:
  - que `phase2_right_accumulator_bytes(state, redeemer)` siga coincidiendo con
    el valor exportado desde Rust
  - y que el chequeo final de pairing sobre esos mismos bytes dé el mismo
    resultado que `phase2_verifier(...)`
- Resultado exacto sobre el artifact real:
  - `right_matches_exported = true`
  - `pairing_ok = false`
  - `phase2_verifier(state, redeemer) ==
    phase2_final_pairing_check_bytes(redeemer.pi_term, right_accumulator)`
- Con esto quedó demostrado dentro de Aiken, sin comparar contra Plinth ni
  Haskell, que el desvío aparece exactamente en el chequeo final:
  `final_exponentiation(miller_loop(el, g2_const), miller_loop(er, generatorG2))`
- Estado de `aiken check` después de instrumentar ese probe:
  `127` tests totales, `125` pasan y siguen fallando sólo:
  `phase2_verifier_accepts_phase1_output_for_exported_artifact` y
  `phase2_runtime_probe_accepts_exported_artifact_fixture`
## 2026-04-13 - Exported artifact fixed after transcript diagnosis

- El diagnóstico final del PoC fue que el artifact real no estaba mal por
  curvas ni por la lógica de `phase2`, sino por un mismatch de transcript entre
  la generación del proof y el verifier Aiken:
  - `plutus-halo2-verifier-gen/src/circuits/mithril_stm/runtime.rs` generaba
    proofs con `PoseidonState<CircuitBase>`
  - `bridge-aiken` y el verifier Aiken generado reconstruyen el transcript con
    `CardanoFriendlyBlake2b`
- Eso hacía que los desafíos Fiat-Shamir del proof exportado fueran distintos a
  los que esperaba Aiken, así que el pairing final fallaba aunque:
  - `phase1_verifier(...)` reconstruyera bien el `Phase1State`
  - `phase1_verifier(...)` reconstruyera bien el `ReducedRedeemer`
  - y el `right accumulator` coincidiera con la reconstrucción Aiken del mismo
    transcript
- Después del fix en `plutus-halo2-verifier-gen`:
  - se regeneró el artifact real a partir del bundle
    `/tmp/tmp.9GSO8FfnAT/mithril_stm_bundle.json`
  - el fixture
    `lib/two_phase/phase2_exported_artifact_fixture.ak` fue actualizado con ese
    artifact nuevo compatible con Blake2b
  - el `right accumulator` correcto pasó a ser:
    `0x869695df274bd7bb391d2bd8e0dcc6f6da4341103618aa17c9ea133b3a07f20f14e2f8977ec193cf0413845b0ec58690`
- También se actualizó el probe
  `validators/tests/phase2_exported_artifact_probe_test.ak`:
  - el test viejo que antes verificaba “right_matches && !pairing_ok” quedó
    invertido porque ahora el comportamiento correcto es aceptación
  - el nombre nuevo es
    `phase2_final_pairing_accepts_exported_artifact`
- Estado verificado después del fix:
  - `aiken check` en `bridge-aiken` quedó completamente verde en esa pasada
  - el verifier full generado y el camino split siguen coincidiendo
  - `phase2_runtime_probe_accepts_exported_artifact_fixture` ahora pasa con el
    artifact real
- Implicación práctica para futuras conversaciones:
  - si aparece otra falla parecida con artifacts STM nuevos, lo primero es
    confirmar con qué transcript fueron generados
  - el verifier Aiken del PoC espera proofs compatibles con
    `CardanoFriendlyBlake2b`
## 2026-04-13 - Cleanup after successful PoC

- Se dejó documentación humana del bug resuelto en:
  - `MITHRIL_STM_TRANSCRIPT_BUG.md`
- Se conservaron archivos que siguen siendo útiles como regresión del PoC:
  - `lib/two_phase/phase2_exported_artifact_fixture.ak`
  - `validators/tests/phase2_exported_artifact_probe_test.ak`
- Se eliminaron artefactos de exploración que ya no son necesarios:
  - `lib/two_phase/generated_full_verifier.ak`
  - `validators/tests/generated_full_verifier_probe_test.ak`
- Motivo:
  - el fixture/exported probe siguen demostrando que `bridge-aiken` verifica un
    proof real del circuito Mithril
  - el verifier full copiado sólo se usó para aislar si el problema venía del
    split TX1/TX2, y esa duda ya quedó resuelta
## 2026-04-14 - Phase 1 multi-proof artifact schema introduced

- Se inició la migración del artifact Mithril hacia un schema multi-prueba en:
  - `scripts/python/build_bridge_compatible_mithril_stm_bundle.py`
  - `scripts/python/mithril_stm_proof_export_bundle_certificates.py`
- El builder del bundle ahora sigue emitiendo compat legacy:
  - `certificates.parent`
  - `certificates.child`
- Además, ahora escribe una nueva sección explícita:
  - `proofs.stake_distribution_genesis`
  - `proofs.stake_distribution_standard`
  - `proofs.cardano_transactions`
- En esta primera fase, la nueva sección `proofs` todavía reutiliza el
  block legacy `statement` del bundle base para compatibilidad, pero ya no
  reutiliza ese statement dentro de `proofs.*`
- Los tres dominios nuevos ahora tienen statements propios dentro de
  `proofs.*`, alineados con su certificado:
  - `proofs.stake_distribution_genesis.statement.statement_hash =
    genesis_certificate.signed_message`
  - `proofs.stake_distribution_standard.statement.statement_hash =
    standard_certificate.signed_message`
  - `proofs.cardano_transactions.statement.statement_hash =
    tx_snapshot_certificate.protocol_message_cardano_transactions_merkle_root`
- Los bloques `proofs.*.bridge_aiken.phase1` y `proofs.*.bridge_aiken.phase2`
  también se clonan con overrides del statement específico de cada dominio
- El certificado de `cardano_transactions` ahora ya existe en el artifact como
  objeto explícito dentro de `proofs.cardano_transactions.certificate`, armado
  con:
  - hash y next AVKs desde `scripts/data/bridge_mint_raw.json`
  - parent/chaining desde el certificado standard de stake distribution
- Se agregaron loaders nuevos para el schema multi-prueba:
  - `load_proof_export_bundle_proofs(...)`
  - `load_sd_genesis_proof(...)`
  - `load_sd_standard_proof(...)`
  - `load_tx_snapshot_proof(...)`
- Verificación manual realizada:
  - el builder genera las tres keys nuevas en `proofs`
  - los tres `proofs.*.statement.statement_hash` son distintos entre sí
  - cada `proofs.*.certificate.signed_message` coincide con su statement propio
  - los loaders nuevos pueden leerlas
- El plan operativo en `PLAN_WORKFLOW_MITHRIL_REALISTA.md` fue endurecido para
  que cada etapa/fase tenga:
  - criterio de salida
  - chequeos explícitos de correctitud
- Para futuros cambios del workflow Mithril, no alcanza con describir el diseño:
  cada etapa debe dejar también cómo verificarla con artefactos, prebuilds,
  manifests, `aiken check` o preflight según corresponda
## 2026-04-14 - Phase 2 builder split by proof domain

- Se avanzó la Fase 2 del plan en:
  - `scripts/python/prepare_mithril_stake_distribution_args.py`
  - `scripts/python/prepare_mithril_bridge_minting_args.py`
- `prepare_mithril_stake_distribution_args.py` ahora separa internamente:
  - `build_sd_genesis_args_from_certificate(...)`
  - `build_sd_standard_args_from_certificate(...)`
- El path con artifact ya usa sólo loaders por dominio de prueba para stake
  distribution:
  - `load_sd_genesis_proof(...)`
  - `load_sd_standard_proof(...)`
- Aunque la CLI todavía conserva nombres legacy para no romper scripts
  existentes, la semántica interna ya quedó separada:
  - el args de genesis usa el certificado genesis real
  - el args de standard usa el certificado standard real
  - el chequeo de `certificate_signed_message` del standard ya se compara contra
    el statement del dominio standard
- `prepare_mithril_bridge_minting_args.py` ahora separa explícitamente:
  - `stake_distribution_standard_certificate` como parent real del chaining
  - `tx_snapshot_certificate` como certificado principal del bridge
- En el path con artifact, el bridge ya toma su certificado principal desde:
  - `load_sd_standard_proof(...)`
  - `load_tx_snapshot_proof(...)`
- En el path sin artifact, se preservó compatibilidad construyendo un fallback
  `tx_snapshot_certificate` a partir de:
  - `scripts/data/bridge_mint_raw.json`
  - el certificado standard fixtureado de stake distribution
- Cambio semántico importante:
  - `tx_snapshot_certificate_signed_message` del bridge ahora se deriva del
    certificado de `cardano_transactions`
  - `parent_certificate_hash` sigue apuntando al standard de
    stake distribution
- Verificación manual realizada:
  - smoke test de `prepare_mithril_stake_distribution_args.py` con artifact:
    genesis y standard emiten `certificate_signed_message` distintos y correctos
  - smoke test de `prepare_mithril_bridge_minting_args.py` con artifact:
    `tx_snapshot_certificate_signed_message ==
    tx_snapshot_certificate_protocol_message_cardano_transactions_merkle_root`
  - `parent_certificate_hash` del bridge sigue siendo el hash del certificado
    standard de stake distribution
  - `python3 -m py_compile` pasa sobre los scripts Python modificados
## 2026-04-14 - Phase 3 phase12 selection by proof domain

- Se avanzó la Fase 3 del plan en:
  - `scripts/python/build_phase12_args_from_mithril_artifact.py`
  - `scripts/python/prepare_tx3_dolos_env.py`
  - `scripts/submit_phase1_phase2_transactions_single_case.sh`
  - `scripts/python/check_mithril_poc_preflight.py`
- `build_phase12_args_from_mithril_artifact.py` ahora acepta selección
  opcional de dominio:
  - `proof_name=None` mantiene compat legacy usando `artifact.statement` y
    `artifact.bridge_aiken`
  - `proof_name=<dominio>` usa:
    - `proofs.<dominio>.statement`
    - `proofs.<dominio>.bridge_aiken`
- Esto permite construir args de `phase1/phase2` distintos para:
  - `stake_distribution_genesis`
  - `stake_distribution_standard`
  - `cardano_transactions`
- `prepare_tx3_dolos_env.py` ahora acepta:
  - `--proof-name <dominio>`
  y propaga esa selección a la generación de `phase1-args.json` y
  `phase2-args.json`
- `submit_phase1_phase2_transactions_single_case.sh` ahora acepta por entorno:
  - `PHASE12_PROOF_NAME=<dominio>`
- Cuando ese valor está presente:
  - el summary del artifact lee `proofs.<dominio>.statement.statement_hash`
  - `prepare_tx3_dolos_env.py` se invoca con `--proof-name`
  - el `session.env` exporta además variables namespaced:
    - `PHASE1_HASH_<DOMINIO>`
    - `PHASE2_HASH_<DOMINIO>`
    - `PHASE2_RECEIPT_UTXO_<DOMINIO>`
    - `STATEMENT_HASH_<DOMINIO>`
- El formato del sufijo namespaced usa:
  - uppercase
  - `-` convertido a `_`
  - ejemplo:
    `stake_distribution_standard -> STAKE_DISTRIBUTION_STANDARD`
- `check_mithril_poc_preflight.py` ahora también valida:
  - que `phase12` pueda materializarse para cada `proof_name`
  - que cada `proofs.<dominio>.phase1/phase2` quede alineado a su statement
  - que los tres `proof_statement_hashes` sean únicos
- Verificación manual realizada:
  - smoke test de `build_phase12_args_from_mithril_artifact.py` con
    `proof_name=stake_distribution_standard` devuelve
    `statement_hash_value == proof_receipt_statement_hash ==
    proofs.stake_distribution_standard.statement.statement_hash`
  - `validate_artifact_usage(...)` del preflight ya pasa sobre un artifact con
    schema multi-prueba
  - `python3 -m py_compile` pasa sobre:
    - `build_phase12_args_from_mithril_artifact.py`
    - `prepare_tx3_dolos_env.py`
    - `check_mithril_poc_preflight.py`
  - `bash -n scripts/submit_phase1_phase2_transactions_single_case.sh` pasa
- Estado resultante:
  - ya existe infraestructura para invocar `phase12` por dominio y persistir
    receipts separados en el manifest
## 2026-04-14 - Phase 3 phase12 multi-case orchestration closed

- Se cerró la parte operativa de la Fase 3 agregando:
  - `scripts/submit_phase1_phase2_transactions.sh`
  - subcomando `./scripts/bridge.sh phase12-all`
- `phase12-all` ejecuta secuencialmente los tres dominios:
  - `stake_distribution_genesis`
  - `stake_distribution_standard`
  - `cardano_transactions`
- Requisitos actuales del orquestador:
  - necesita artifact multi-prueba
  - acepta `--proof-export-bundle <path>` o `PROOF_EXPORT_BUNDLE_PATH`
  - acepta `--output-dir <dir>`
- Salida principal:
  - manifiesto combinado en `run_outputs/phase12-all/latest/session.env` o en el
    `output-dir` elegido
- Ese manifiesto combinado incluye, por dominio:
  - `PHASE1_HASH_<DOMINIO>`
  - `PHASE2_HASH_<DOMINIO>`
  - `PHASE2_RECEIPT_UTXO_<DOMINIO>`
  - `STATEMENT_HASH_<DOMINIO>`
- También se actualizó:
  - `scripts/bridge.sh`
  - `scripts/README.md`
  para exponer `phase12-all` como entrypoint público
- Verificación realizada:
  - `bash -n scripts/submit_phase1_phase2_transactions.sh`
  - `bash -n scripts/bridge.sh`
  - smoke test del builder `phase12` por los tres dominios con artifact
    multi-prueba, confirmando statements distintos y correctos
- Estado de cierre de Fase 3:
  - el repo ya puede preparar args de `phase1/phase2` por dominio
  - el repo ya puede correr la secuencia conceptual de tres casos desde un
    entrypoint público
  - la integración final de esos receipts con el resto del workflow queda para
    fases posteriores

## 2026-04-14 - Phase 4 on-chain receipts migrated from reference inputs to inputs

- Se migró la lectura on-chain del `proof receipt` para que deje de depender de
  `tx.reference_inputs` y pase a requerirlo en `tx.inputs`.
- Nota posterior:
  - esto quedó superseded sólo para `stake_distribution_genesis_tx`
  - el receipt sigue siendo un `tx.input` para
    `stake_distribution_standard_tx` y `bridge_mint_tx`
  - pero el mint genesis ya no depende del `proof_receipt`
- Archivos on-chain ajustados:
  - `lib/two_phase/proof_receipt.ak`
    - `find_reference_input(...) -> find_input(...)`
    - `has_reference_input(...) -> has_input(...)`
    - `statement_hash(...)` ahora busca el receipt en `tx.inputs`
  - `validators/stake_distribution.ak`
    - histórico: en ese momento el mint de genesis pasó a exigir
      `proof_receipt.has_input(...)`
  - `validators/minting.ak`
    - la documentación del redeemer ya indica que el receipt va en
      transaction inputs
- Fixtures/tests actualizados para modelar la nueva semántica:
  - `validators/tests/helpers/stake_distribution_tx.ak`
    - genesis consume el receipt desde `inputs`
    - standard consume el receipt desde `inputs` junto al parent certificate
    - se agregaron casos explícitos donde el receipt existe sólo como
      `reference_input`
  - `validators/tests/helpers/minting_tx.ak`
    - el fixture canónico de bridge ahora lleva el phase-2 receipt en
      `inputs`
    - el stake-distribution certificate sigue en `reference_inputs`
    - se agregó un fixture explícito con receipt sólo en `reference_inputs`
  - `validators/tests/stake_distribution_validator_test.ak`
    - helper actualizado para localizar el input con NFT de
      stake-distribution dentro de una lista de inputs no singleton
    - el flujo repetido de standard-certificate spend ahora vive en el helper
      local `run_standard_certificate_spend(...)`
    - nuevos tests de regresión para rechazar receipt sólo en
      `reference_inputs`
  - `validators/tests/minting_validator_test.ak`
    - nuevo test de regresión para rechazar receipt sólo en
      `reference_inputs`
- También se actualizó `plutus.json` para reflejar la documentación nueva del
  minting redeemer.
- Verificación realizada:
  - `timeout 240 aiken check`
  - resultado de la migración Phase 4:
    - `tests/minting_validator_test` pasa completo
    - `tests/stake_distribution_validator_test` pasa completo
    - los nuevos tests que aseguran que un receipt presente sólo como
      `reference_input` falle, pasan
  - residual actual del repo:
    - durante el cierre inicial de Fase 4 todavía fallaban 3 tests en
      `tests/snapshot_membership_test`
    - esos fallos no venían del cambio `reference_inputs -> inputs`, sino de un
      fixture viejo de `cardano_transactions`

## 2026-04-14 - Pre-Phase 5 cleanup left aiken check fully green

- Antes de avanzar a Fase 5 se alineó el fixture base de
  `validators/tests/helpers/certificates/cardano_transactions.ak` con el root
  real de `cardano_transactions` ya usado por el resto del bridge fixture:
  - root viejo: `4e2d573652dc8b27f7753d8ba62a10061fc9cba80cbc56c717ab86e9820484b0`
  - root actualizado: `644a96fc060ad588aed2878523252c547f3eccf7d275a240d321c2a2e5a06181`
- Esto cerró la desalineación entre:
  - `simple_cardano_transactions_certificate()`
  - `bridge_fixture.final_snapshot_root`
  - `minting_redeemer` y `snapshot_membership` tests
- Verificaciones corridas:
  - `timeout 180 aiken check -m tests/snapshot_membership_test`
  - `timeout 240 aiken check`
- Resultado:
  - `tests/snapshot_membership_test` pasa completo
  - `aiken check` pasa completo: `125 passed / 0 failed`
- Conclusión operativa:
  - el repo quedó sin fallos residuales internos antes de entrar en Fase 5
  - lo que estaba rojo era un fixture stale, no una dependencia externa ni un
    problema abierto del cambio on-chain

## 2026-04-14 - Phase 5 rewired main.tx3 to domain-specific receipt inputs

- Se cerró el rewiring de `main.tx3` para dejar de expresar un único
  `phase2_receipt_utxo` compartido.
- Nota posterior:
  - esta fase quedó superseded sólo en el bootstrap
    `stake_distribution_genesis_tx`
  - hoy `stake_distribution_standard_tx` y `bridge_mint_tx` siguen usando
    receipts por dominio consumidos como inputs normales
  - pero `stake_distribution_genesis_tx` ya no conserva
    `sd_genesis_receipt_utxo`
- Cambios en `main.tx3`:
  - `stake_distribution_genesis_tx`
    - histórico: `phase2_receipt_utxo -> sd_genesis_receipt_utxo`
    - histórico: `reference phase2_receipt { ... } -> input sd_genesis_receipt { ... }`
  - `stake_distribution_standard_tx`
    - `phase2_receipt_utxo -> sd_standard_receipt_utxo`
    - `reference phase2_receipt { ... } -> input sd_standard_receipt { ... }`
  - `bridge_mint_tx`
    - `phase2_receipt_utxo -> tx_snapshot_receipt_utxo`
    - `reference phase2_receipt { ... } -> input tx_snapshot_receipt { ... }`
- También se alinearon los builders JSON que alimentan esas transacciones:
  - `scripts/python/prepare_mithril_stake_distribution_args.py`
    - histórico: en esa fase pasó a emitir `sd_genesis_receipt_utxo`
    - ahora emite `sd_standard_receipt_utxo`
  - `scripts/python/prepare_mithril_bridge_minting_args.py`
    - ahora emite `tx_snapshot_receipt_utxo`
- Importante:
  - en esta fase se cambió la interfaz Tx3 y el wiring interno
  - la orquestación shell que decide qué receipt concreto inyectar por dominio
    queda para Fase 6
  - por eso los CLIs Python todavía aceptan parámetros posicionales legacy del
    estilo `phase2_hash` / `phase2_receipt_statement_hash`, aunque ya produzcan
    claves JSON específicas por dominio
- Verificaciones corridas:
  - `trix build -v`
  - `python3 -m py_compile scripts/python/prepare_mithril_stake_distribution_args.py scripts/python/prepare_mithril_bridge_minting_args.py`
  - búsqueda en repo:
    - `main.tx3` ya no contiene `reference phase2_receipt`
    - `main.tx3` sí contiene:
      - `sd_genesis_receipt_utxo`
      - `sd_standard_receipt_utxo`
      - `tx_snapshot_receipt_utxo`
- Estado de cierre de Fase 5:
  - la interfaz Tx3 ya refleja tres receipts distintos y consumidos como
    inputs normales
  - falta únicamente reconectar los scripts runtime para usar
    `PHASE2_RECEIPT_UTXO_<DOMINIO>` en la corrida integrada

## 2026-04-14 - Phase 6 runtime scripts rewired to the three proof domains

- Se reconectó la capa runtime para dejar de depender del `phase2` genérico.
- `scripts/mithril_stake_distribution.sh`:
  - ahora invoca `submit_phase1_phase2_transactions.sh`
  - requiere artifact multi-prueba para materializar los tres dominios
  - histórico: en esa fase consumía del manifest combinado:
    - hash / receipt del viejo lane genesis de `phase12`
    - `PHASE2_HASH_STAKE_DISTRIBUTION_STANDARD`
    - `PHASE2_RECEIPT_UTXO_STAKE_DISTRIBUTION_STANDARD`
    - `STATEMENT_HASH_STAKE_DISTRIBUTION_STANDARD`
  - estado actual:
    - ya no requiere ningún campo genesis-específico de `phase2`
    - sigue requiriendo `PHASE2_RECEIPT_UTXO_STAKE_DISTRIBUTION_STANDARD`
      y `STATEMENT_HASH_STAKE_DISTRIBUTION_STANDARD`
  - prepara args separados para:
    - histórico: `sd_genesis_receipt_utxo`
    - `sd_standard_receipt_utxo`
- `scripts/bridge_minting.sh`:
  - sigue reutilizando el flow de stake distribution, pero ahora espera en el
    manifest compartido:
    - `PHASE2_HASH_CARDANO_TRANSACTIONS`
    - `STATEMENT_HASH_CARDANO_TRANSACTIONS`
  - el builder de bridge minting ya se invoca con el dominio
    `cardano_transactions`
  - el flow csv ahora registra por separado los tres `phase1/phase2`
    dominios cuando esas rutas están disponibles en el manifest combinado
- `scripts/submit_phase1_phase2_transactions_single_case.sh` ahora exporta también por dominio:
  - `PUBLISH_PHASE1_REFERENCE_SCRIPT_RESULT_PATH_<DOMINIO>`
  - `PHASE1_RESULT_PATH_<DOMINIO>`
  - `PHASE2_RESULT_PATH_<DOMINIO>`
- `scripts/submit_phase1_phase2_transactions.sh` agrega esas rutas namespaced al
  manifest combinado
- Builders Python actualizados:
  - `scripts/python/prepare_mithril_stake_distribution_args.py`
    - CLI separada para:
      - `sd_genesis_phase2_hash`
      - `sd_standard_receipt_statement_hash`
      - `sd_genesis_receipt_utxo`
      - `sd_standard_receipt_utxo`
  - `scripts/python/prepare_mithril_bridge_minting_args.py`
    - CLI separada para:
      - `tx_snapshot_phase2_hash`
      - `tx_snapshot_receipt_statement_hash`
    - emite `tx_snapshot_receipt_utxo`
- Fixes de soporte encontrados mientras se verificaba la corrida integrada:
  - `scripts/python/build_bridge_compatible_mithril_stm_bundle.py`
    - ya no asume `bridge_aiken` dentro del bundle base exportado por Rust
    - si falta, sintetiza templates desde:
      - `scripts/data/phase1_args_raw.json`
      - `scripts/data/phase2_args_raw.json`
  - `scripts/python/sync_bridge_zk_fixture.py`
    - ahora usa paths absolutos para los exportadores de fixtures
    - corrige fallos por `cwd` al regenerar `snapshot/input.json`
- Verificaciones corridas:
  - `bash -n` sobre:
    - `scripts/submit_phase1_phase2_transactions_single_case.sh`
    - `scripts/submit_phase1_phase2_transactions.sh`
    - `scripts/mithril_stake_distribution.sh`
    - `scripts/bridge_minting.sh`
    - `scripts/run_mithril_poc.sh`
  - `python3 -m py_compile` sobre:
    - `prepare_mithril_stake_distribution_args.py`
    - `prepare_mithril_bridge_minting_args.py`
    - `sync_bridge_zk_fixture.py`
  - `trix build -v`
  - smoke de `./scripts/bridge.sh run --output-dir run_outputs/phase6-smoke --skip-aiken-check --skip-preflight --clean`
- Estado actual de esa verificación integrada:
  - se corrigieron dos bloqueantes reales detectados por la smoke run:
    - schema drift del builder del artifact
    - paths relativos inválidos en `sync_bridge_zk_fixture.py`
  - la corrida integrada ya avanzó más allá de la preparación del artifact, el
    sync de Tx3 y la regeneración del bridge zk fixture
  - no quedó registrada todavía una finalización limpia completa dentro de esta
    nota; cualquier seguimiento debe partir de `run_outputs/phase6-smoke`

## 2026-04-14 - Portable Mithril STM dependency for sibling Rust exporter

- Se eliminó una fuga de entorno en `../plutus-halo2-verifier-gen/Cargo.toml`:
  - antes: `mithril-stm = { path = "/home/lorenzo/Desktop/mithril/mithril-stm", ... }`
  - ahora:
    - `mithril-stm = { git = "https://github.com/input-output-hk/mithril.git", rev = "c0641158f7807e298b1815576502047f8fdf8d93", package = "mithril-stm", features = ["future_snark"] }`
- Motivo:
  - en otras máquinas el exportador de artifacts fallaba durante
    `cargo run export_mithril_stm_fixture_bundle`
    porque intentaba resolver un checkout local inexistente de Mithril.
- Verificaciones corridas:
  - `cargo check --manifest-path ../plutus-halo2-verifier-gen/Cargo.toml`
  - `cargo run --manifest-path ../plutus-halo2-verifier-gen/Cargo.toml --bin export_mithril_stm_fixture_bundle -- --output /tmp/bridge-compatible-mithril-stm-base-bundle.json`
  - `./scripts/bridge.sh proof-export-bundle run_outputs/portable-smoke/mithril_stm_artifact.json`
- Conclusión:
  - el flujo ya no depende de rutas personales tipo `/home/lorenzo/...`
    para exportar bundles/artifacts Mithril desde el crate hermano.
  - además quedó revalidado el camino completo:
    - `./scripts/bridge.sh run --skip-aiken-check`
    - terminó con `flow-success`
    - `bridge_mint_tx hash: 284b6f1e1f39c666b7175bdcd2d14b4e1f360aef8a6d59bea13660a6cc055826`

## 2026-04-14 - Cargo lock enforced for reproducible sibling builds

- Se detectó drift entre máquinas al compilar `mithril-stm`:
  - sin lock, otra compu resolvía `midnight-circuits 6.1.0`
  - el código de `mithril-stm 0.10.1` usado por este flujo fue validado con
    `midnight-circuits 6.0.0`
  - el síntoma era `error[E0061]` en `ForeignEccChip::new(...)`
- Se endurecieron los scripts para usar `--locked` cuando existe `Cargo.lock`:
  - `scripts/build_bridge_compatible_mithril_stm_proof_export_bundle.sh`
  - `scripts/preflight_mithril_poc.sh`
  - `scripts/lib/dolos_common.sh`
  - `scripts/bridge_minting.sh`
- Verificaciones corridas:
  - `bash -n` sobre los scripts tocados
  - `./scripts/bridge.sh proof-export-bundle run_outputs/locked-smoke/mithril_stm_artifact.json`
- Conclusión:
  - el workflow ya no depende de la resolución variable de crates al correr en
    otra máquina; si el repo hermano tiene `Cargo.lock`, el flow lo respeta.

## 2026-04-14 - Exact midnight versions and versioned Cargo.lock for verifier-gen

- Se detectó una segunda causa para el mismo error cross-machine:
  - el repo ignoraba `plutus-halo2-verifier-gen/Cargo.lock`
  - entonces en otra máquina `--locked` no ayudaba, porque el lock ni viajaba
  - además `plutus-halo2-verifier-gen/Cargo.toml` declaraba la familia
    `midnight-*` con rangos semver abiertos (`"6.0.0"` => `^6.0.0`)
- Fix aplicado:
  - `plutus-halo2-verifier-gen/Cargo.toml`
    - `midnight-circuits = "=6.0.0"`
    - `midnight-curves = "=0.2.0"`
    - `midnight-proofs = "=0.7.0"`
    - `midnight-zk-stdlib = "=1.0.0"`
  - `.gitignore`
    - ya no ignora `plutus-halo2-verifier-gen/Cargo.lock`
  - `plutus-halo2-verifier-gen/.gitignore`
    - ya no ignora `Cargo.lock`
- Verificaciones corridas:
  - copia temporal del crate sin `Cargo.lock`:
    - `cargo generate-lockfile`
    - `cargo tree -i midnight-circuits`
    - siguió resolviendo `midnight-circuits v6.0.0`
  - `cargo check --manifest-path ../plutus-halo2-verifier-gen/Cargo.toml`
  - `./scripts/bridge.sh proof-export-bundle run_outputs/repro-smoke/mithril_stm_artifact.json`

## 2026-04-14 - Monorepo Cargo.lock scan for runtime-adjacent crates

- Se hizo una pasada por el monorepo para detectar otros crates ejecutados por
  los flows de `bridge-aiken` donde convenía versionar `Cargo.lock`.
- Resultado:
  - sí conviene para:
    - `dolos/Cargo.lock`
    - `circuit_transaction_snapshot/Cargo.lock`
    - `circuit_inclusion_exclusion/Cargo.lock`
  - motivo:
    - `bridge-aiken` recompila Dolos
    - `sync_bridge_zk_fixture.py` y los scripts de fixture de los circuitos
      ejecutan `cargo run` sobre esos crates
- Fixes aplicados:
  - `.gitignore`
    - ya no ignora:
      - `dolos/Cargo.lock`
      - `circuit_transaction_snapshot/Cargo.lock`
      - `circuit_inclusion_exclusion/Cargo.lock`
  - `scripts/python/sync_bridge_zk_fixture.py`
    - usa `cargo run --locked` cuando existe `Cargo.lock` en los crates de
      snapshot y tx-set-update
  - `../circuit_transaction_snapshot/scripts/run_e2e_test.sh`
    - usa `--locked` cuando existe `Cargo.lock`
  - `../circuit_inclusion_exclusion/scripts/run_e2e_test.sh`
    - usa `--locked` cuando existe `Cargo.lock`
- Verificaciones corridas:
  - `bash -n` sobre los scripts shell tocados
  - `python3 -m py_compile scripts/python/sync_bridge_zk_fixture.py`
- Estado del repo tras esta pasada:
  - quedaron visibles como untracked y deberían versionarse:
    - `dolos/Cargo.lock`
    - `circuit_transaction_snapshot/Cargo.lock`
    - `circuit_inclusion_exclusion/Cargo.lock`

## 2026-04-16 - Script robustness hardening and sibling-toolchain enforcement

- El blocker `invalid number: InvalidDigit` durante `phase1_setup` volvió a
  aparecer cuando `bridge-aiken` resolvía `dolos` desde `PATH` en vez de usar
  el sibling `../dolos`.
- Verificación directa:
  - `command -v dolos` resolvía:
    - `/Users/lorenzord/.tx3/default/bin/dolos`
  - el workspace sibling build verificado está en:
    - `../dolos/target/debug/dolos`
- Fixes aplicados en la superficie de scripts:
  - `scripts/lib/dolos_common.sh`
    - `resolve_dolos_binary()` ahora prioriza el sibling
      `../dolos/target/debug/dolos` cuando existe el workspace soportado y no
      se fijó `DOLOS_BIN` explícitamente
  - `scripts/submit_phase1_phase2_transactions_single_case.sh`
    - ahora resuelve `CARGO_BIN`
    - ahora llama `maybe_build_sibling_dolos`
    - ahora serializa la toolchain efectiva en `session.env`
- Repro verificada después del fix:
  - `RUST_BACKTRACE=1 ... ./scripts/bridge.sh phase12`
    con `PHASE12_PROOF_NAME=stake_distribution_genesis`
    pasó completa usando el sibling `dolos`
- Verificaciones end-to-end de esta ronda:
  - `./scripts/bridge.sh stake-distribution`
    pasó completa
  - `./scripts/bridge.sh bridge`
    pasó completa
  - hash final verificado del rerun de `bridge`:
    - `8ae58f602b99d9933869d253f12575b41f1b677da1372180e002d826acb1a42a`
- Los flows persistidos ahora también escriben:
  - `debug-context.log`
    con:
    - binarios resueltos
    - manifests/paths operativos clave
    - backups/restores relevantes
    - último comando fallido y su log, si aplica
- `scripts/lib/flow_observability.sh` ahora crea:
  - `stage-trace.log`
  - `debug-context.log`
- `scripts/lib/integration_common.sh` ahora agrega al contexto de error:
  - `Failed command label`
  - `Failed command`
  - `Failed command log`
  - `Debug context`
- `scripts/lib/tooling_common.sh` ahora centraliza:
  - impresión contextual de toolchain resuelta
  - hashing SHA-256 portable
  - export de toolchain resuelta al entorno hijo
  - serialización canónica de toolchain en `session.env`
- El `session.env` runtime ahora serializa explícitamente:
  - `PYTHON_BIN`
  - `AIKEN_BIN`
  - `CARGO_BIN`
  - `UV_BIN`
  - `TRIX_BIN`
  - `CSHELL_BIN`
  - `DOLOS_BIN`
  - `DOLOS_CARGO_MANIFEST`
  - `DOLOS_DEVNET_DIR`
- Esa metadata de toolchain ahora queda con una sola sección canónica por
  manifest, sin duplicarse entre `phase12`, `phase12-all`,
  `stake-distribution` y `bridge`.
- `scripts/lib/guardrails_common.sh` ahora concentra la capa repetida de:
  - workspace guardrails
  - tooling guardrails
  - semántica de skip vía `BRIDGE_SKIP_FLOW_CHECKS`
- `scripts/build_bridge_compatible_mithril_stm_proof_export_bundle.sh` ahora también
  sourcea `scripts/lib/run_outputs_common.sh`; el bug:
  - `mktemp_in_dir: command not found`
  quedó corregido.
- `scripts/python/check_mithril_artifact_contract.py` ahora permite validar el
  contrato del bundle Mithril compatible como etapa explícita de `artifact`.
- `scripts/check_session_manifest.sh` ahora valida `session.env` por capa:
  - `phase12-case`
  - `phase12-all`
  - `stake-distribution`
  - `bridge`
- `artifact`, `phase12-all`, `stake-distribution` y `bridge` ahora fallan
  antes cuando el contrato de artifact o de manifest está incompleto.
- `scripts/lib/run_outputs_common.sh` ahora centraliza:
  - `backup_file_to_path`
  - `restore_file_from_backup`
- `scripts/sync_phase_scripts_to_tx3.sh` ahora:
  - respalda `main.tx3` y `env/default.ak`
  - restaura ambos automáticamente si falla después de mutarlos
  - registra esos backups/restores en `.tx3/cache/sync/debug-context.log`
- Verificación destructiva local del restore automático de `sync`:
  - usando `BRIDGE_SYNC_FAIL_AFTER_SYNC_ON_ROUND=1`
  - el comando salió con:
    - `exit=91`
  - y los hashes antes/después de:
    - `main.tx3`
    - `env/default.ak`
    permanecieron idénticos
- Smoke tests shell nuevos:
  - `scripts/tests/smoke_script_helpers.sh`
    cubre:
    - `mktemp_in_dir`
    - preferencia de candidatos repo-locales sobre env genérico
    - preferencia del sibling `dolos`
    - `check_session_manifest.sh`
    - backups/restores con `debug-context.log`
  - `scripts/tests/smoke_sync_restore.sh`
    cubre:
    - fallo inyectado de `sync`
    - restore automático de `main.tx3` y `env/default.ak`
- CI:
  - `../.github/workflows/bridge-aiken-repro.yml`
    ahora ejecuta:
    - `./scripts/tests/smoke_script_helpers.sh`
    - `./scripts/tests/smoke_sync_restore.sh`

## 2026-04-16 - Aiken fixture / VK realignment and local CI runner

- `aiken check` vuelve a pasar completo en `bridge-aiken` con:
  - `126 passed / 0 failed`
- Los fallos que lo rompían en esta sesión estaban concentrados en:
  - `tests/bridge_fixture_test`
  - `tests/minting_validator_test`
  - `tests/snapshot_membership_test`
  - `tests/txs_updater_validator_test`
- La causa verificada fue una desalineación entre:
  - `validators/tests/helpers/bridge_fixture.ak`
  - `validators/tests/helpers/certificates/cardano_transactions.ak`
  - `lib/zk/snapshot_membership_vk.ak`
  - `lib/zk/tx_set_update_vk.ak`
  y los artefactos Groth16 canónicos recién generados en:
  - `../circuit_transaction_snapshot/circuit_build/groth16_sample_proof/`
  - `../circuit_inclusion_exclusion/circuit_build/groth16_sample_proof/`
- Fixes aplicados:
  - `lib/zk/snapshot_membership_vk.ak`
    se volvió a copiar desde:
    `../circuit_transaction_snapshot/circuit_build/groth16_sample_proof/snapshot_membership_vk.ak`
  - `lib/zk/tx_set_update_vk.ak`
    se volvió a copiar desde:
    `../circuit_inclusion_exclusion/circuit_build/groth16_sample_proof/tx_set_update_vk.ak`
  - `validators/tests/helpers/certificates/cardano_transactions.ak`
    ahora usa como `CardanoTransactionsMerkleRoot`:
    - `3fbd6a6dc852637c090154c9faa6337c4078f26ae3a57876b692ba67c445a69b`
- Verificaciones corridas después de ese realineamiento:
  - `aiken check -m tests/bridge_fixture_test`
  - `aiken check -m tests/minting_validator_test`
  - `aiken check -m tests/snapshot_membership_test`
  - `aiken check -m tests/txs_updater_validator_test`
  - `aiken check`
  todas pasaron
- El repo ahora también tiene un runner local de jobs CI en:
  - `scripts/tests/run_ci_jobs_locally.sh`
- Ese runner actualmente soporta:
  - `guardrails`
  - `bootstrap-doctor-smoke`
  - `artifact-preflight-smoke`
  - `phase12-runtime-smoke`
  - `stake-distribution-runtime-smoke`
  - `bridge-runtime-smoke`
  - `all`
- Comportamiento verificado de ese runner:
  - si el árbol Git está limpio, usa un `git worktree` temporal limpio
  - si el árbol está sucio, usa una copia temporal del workspace actual
  - en ambos casos evita mutar el checkout principal del usuario
- `scripts/tests/smoke_wrapper_entrypoints.sh` ya no dispara flows reales al
  validar wrappers; ahora verifica estáticamente el handoff esperado a
  `bridge.sh`
- `../.github/workflows/bridge-aiken-repro.yml` ahora:
  - separa jobs baratos de runtime smokes más caros
  - corre siempre en PR:
    - `guardrails`
    - `bootstrap-doctor-smoke`
    - `artifact-preflight-smoke`
      - incluye verificación liviana del operador compartido
        (`cargo test` + `cargo run -- --help`)
  - corre smokes runtime más pesados sólo en:
    - `push` a ramas principales
    - `workflow_dispatch`
    - `schedule`
  - el smoke real de `zk_circuit_operator tx prove ...` ahora vive en:
    - `operator-runtime-smoke`
- En `run` / `bridge` hay dos estados distintos que no conviene mezclar:
  - el estado versionado de fixtures de test (`bridge_fixture.ak`,
    `cardano_transactions.ak`)
  - el estado efímero post-`sync` que usa el runtime bridge flow
- Regla actual:
  - `preflight` sigue validando alineación completa de fixtures versionadas
  - `bridge_minting.sh` omite sólo el chequeo de
    `cardano_transactions.ak` durante el refresh runtime post-`sync`,
    para no bloquear el flow con un helper de test que no participa en la
    ejecución real
- `preflight` ahora auto-refresca
  `scripts/data/mithril_poc_reference_snapshot.json` cuando detecta que el
  snapshot canónico quedó viejo respecto del estado actual del repo y del
  artifact verificado; ya no falla por ese drift derivado.
- Los artefactos derivados del runtime ahora se tratan como outputs
  regenerables:
  - `bridge_fixture.ak` se re-renderiza desde `bridge_mint_raw.json`
    durante los checks runtime
  - `mithril_stm_artifact.json` y
    `bridge-compatible-mithril-stm-bundle.json` se "aseguran" mediante el
    builder cuando `check` / `preflight` / `run` los necesitan
  - `bridge` reconstruye su variante post-`sync` en
    `run_outputs/.../bridge-minting/runtime-artifact/` para no pisar el
    artifact canónico usado por `run`/`preflight`
  - `bridge_minting.sh` hace primero un check barato del bridge fixture; si el
    estado post-`sync` ya coincide con el artifact runtime, se saltea tanto el
    refresh del fixture como el rebuild del artifact runtime
  - `preflight` intenta recuperar bundles stale sin `proofs` desde los
    intermedios ya exportados en el mismo directorio antes de rerunear el
    builder completo
  - el builder canónico del artifact ya no usa `cargo run` repetido para cada
    export; hace un único `cargo build --release --bins` y luego ejecuta los
    binarios compilados desde `target/release`
  - las fingerprints de runtime/preflight ya no saltean verificaciones
    críticas por sí solas
- Los entrypoints runtime (`run`, `preflight`, `artifact`, `bridge`) exportan
  `RUSTFLAGS=-Awarnings` y `sync_bridge_zk_fixture.py` también lo inyecta en
  sus subprocess de Cargo para evitar spam de warnings de `ark-circom` en
  consola.
- Portabilidad Ubuntu/macOS endurecida en esta sesión:
  - el flujo ya no depende de `sort -z` para fingerprints críticos
  - la liberación/inspección de puertos acepta `lsof` o `ss`, así que no queda
    acoplada a una sola utilidad del sistema

## 2026-05-20 - Preview public operator reference and versioned Tx3 Rust client

- `bridge-aiken/trix.toml` ahora declara explícitamente:
  - `[[codegen]]`
  - `plugin = "rust-client"`
  - `output_dir = "./gen/rust-client"`
- `trix codegen` ahora genera un cliente Rust versionable en:
  - `gen/rust-client/Cargo.toml`
  - `gen/rust-client/lib.rs`
- `cargo check --manifest-path bridge-aiken/gen/rust-client/Cargo.toml` pasó.
- `trix check` sigue pasando en `bridge-aiken`.
- `trix build -v` sigue pasando en `bridge-aiken`.
- Existe una dirección pública Preview versionada en:
  - `preview-operator.addr`
- El valor actual verificado de esa dirección es:
  - `addr_test1qqvmxat338q2wj8lrnyk6nvr8x0u5tk6mrtvgscgz52pd2x37xu9m3gdts9dwm3pr0dnrd5vktnkfxvhhw95dhqgkr5smp0lnw`
- El hash de funding público guardado como referencia operativa es:
  - `de5c8bb1146f92131cf8e1ddeebf1f4e1b480588e728041d506dc3a2a3697387`
- La configuración pública Preview/Lace ahora vive en:
  - `config/preview/operator-reference.toml`
  - `config/preview/cshell-provider.template.toml`
  - `config/preview/LACE_INTEGRATION.md`
- Ahora existe un helper local preferido para derivar una payment signing key
  de Preview usando el mismo stack de derivación conceptual que Lace:
  - `scripts/node/derive_preview_payment_skey.mjs`
- Dependencia operativa de ese helper:
  - `scripts/node/package.json`
  - correr `npm install` dentro de `scripts/node/`
- Uso operativo documentado:
  - `node scripts/node/derive_preview_payment_skey.mjs --mnemonic-file ../.secrets/preview-seed.txt`
  - normaliza espacios variables y saltos de línea del archivo
  - auto-descubre el path de la address target
  - escribe en `../.secrets/`:
    - `preview-operator.payment.skey`
    - `preview-operator.payment.extended.vkey`
    - `preview-operator.payment.hash`
    - `preview-operator.payment.derivation.json`
- Verificación corrida en este repo:
  - el helper resolvió:
    - `account=0`
    - `type=External`
    - `payment-index=0`
    - `stake-index=0`
  - la `preview-operator.payment.skey` resultante fue validada con
    `cardano-cli` y matcheó el payment credential de `preview-operator.addr`
- Verificación adicional corrida para firma CLI:
  - `cshell wallet restore` con la misma mnemonic **no** reprodujo la cuenta
    de Lace; devolvió una address testnet distinta
  - en cambio, inyectando una wallet temporal de `cshell` con:
    - `public_key = <extended xpub de 64 bytes>`
    - `private_key = <raw private key de 64 bytes>`
    derivados desde el helper Node, `cshell wallet info` sí resolvió una
    enterprise address con el mismo payment credential del operador
  - `cshell tx sign` usando ese signer temporal sí pudo firmar una unsigned
    real de Preview del repo:
    - input unsigned:
      `zk-bridge-operator/preview_phase12/stake_distribution_genesis/phase1-setup/unsigned.tx.cborhex`
    - output firmado guardado en:
      `.omx/tmp/preview-cli-sign-demo/signed-phase1-setup.json`
  - esa prueba demuestra firma CLI exitosa con el key material derivado
- Regla operativa explícita para txs CLI en Preview:
  - entrypoint recomendado:
    - `scripts/preview_cli_sign.sh`
  - ese wrapper hace automáticamente:
    - derivación con `scripts/node/derive_preview_payment_skey.mjs`
    - store temporal `cshell.toml`
    - inyección del signer temporal `previewop-cli`
    - `cshell tx sign`
    - cleanup del store efímero
  - no usar `cshell wallet restore` como signer principal para esta cuenta
  - detalle interno relevante:
    - el signer temporal carga:
      - `public_key` = payload de `preview-operator.payment.extended.vkey`
        sin `5840`
      - `private_key` = raw private key de 64 bytes derivada desde el mismo path
    - `--store-path` apunta al archivo `cshell.toml`, no a un directorio
- Intento adicional de self-transfer trivial vía `trix/cshell`:
  - se construyó una tx3 mínima `swap(quantity)`
  - se resolvieron `sender` y `receiver` como `custom address` usando
    `preview-operator.addr`
  - el flujo alcanzó al provider Preview pero quedó bloqueado por:
    - `401 Unauthorized`
    desde `https://preview.utxorpc-v0.demeter.run`
  - por lo tanto, el blocker del self-transfer no fue la firma sino la
    autorización del provider remoto
- Reintento posterior usando Dolos local del propio repo:
  - provider remoto reemplazado por:
    - `./dolos`
    - `u5c` local en `localhost:55164`
    - `trp` local en `localhost:58164`
  - se inyectó un UTxO custom plain-ADA para `preview-operator.addr`
  - se recompiló una tx3 mínima `swap(quantity)` con parties fijas al operador
  - `cshell tx invoke --skip-submit` resolvió correctamente la self-transfer
  - output guardado en:
    - `.omx/tmp/dolos-selfsend-invoke.json`
  - hash devuelto:
    - `098806a4a4ef3e8a5e94fad724fa3166be3edc0f017bd902dc27597ccf240696`
- Conclusión operativa actualizada:
  - Demeter no es obligatorio para el flujo CLI
  - Dolos local es una alternativa válida para resolve/sign testing
- Wrapper local empaquetado:
  - `scripts/preview_cli_invoke_local.sh`
  - resultado verificado:
    - `.omx/tmp/preview-cli-invoke-local/result.json`
- Verificación posterior de wrapper remoto con Demeter:
  - wrapper:
    - `scripts/preview_cli_invoke_remote.sh`
  - secrets requeridos:
    - `.secrets/dmtr-utxorpc-api-key.txt`
    - `.secrets/dmtr-trp-api-key.txt`
  - hallazgo clave:
    - una key genérica de proyecto no bastó
    - el setup que funcionó usó las keys específicas del `UtxoRpcPort` y del
      `TrpPort`
  - resultado verificado:
    - `.omx/tmp/preview-cli-invoke-remote/result.json`
- Wrapper de submit remoto verificado:
  - `scripts/preview_cli_submit_remote.sh`
  - output verificado:
    - `.omx/tmp/preview-cli-submit-remote/result.json`
  - hash Preview verificado:
    - `4499d2a667bee119860f60cb79066cedb31cb36637e17d83db081b8dfd6a61e6`
  - confirmación on-chain verificada vía Blockfrost Preview:
    - `block_height = 4303175`
- Generalización posterior de wrappers:
  - `preview_cli_invoke_local.sh`
  - `preview_cli_invoke_remote.sh`
  - `preview_cli_submit_remote.sh`
  ahora aceptan:
    - `--tii-file`
    - `--tx-template`
    - `--args-file` / `--args-json`
    - `--party-map-file` / `--party-map-json`
    - `--profile`
- Verificación real contra una tx del bridge:
  - template:
    - `publish_phase1_reference_script`
  - `.tii`:
    - `bridge-aiken/.tx3/tii/main.tii`
  - invoke remoto verificado:
    - `.omx/tmp/preview-publish-phase1-invoke/result.json`
  - submit remoto verificado:
    - `.omx/tmp/preview-publish-phase1-submit/result.json`
  - hash Preview verificado:
    - `336402bcb9f74b3c2a84a878559fe1a6faed62e30a2a84ccfe649b2678cca07d`
  - confirmación on-chain vía Blockfrost Preview:
    - `block_height = 4303191`
- Entry point operator-side agregado:
  - `zk-bridge-operator preview invoke-cli-publish-phase1-reference-script`
  - corre en `skip-submit` por default
  - está pensado como setup one-time del reference script por bridge/script
  - prueba verificada en esta sesión:
    - output:
      `.omx/tmp/preview-operator-cli/publish-phase1-reference-script.json`
    - hash resuelto:
      `0172277fee24a11b2f0a05b126281b767effbd62cffbb1f749521eca4fc60579`
- Estado actualizado:
  - la preparación local de la signing key Preview por CLI ya quedó
    destrabada
  - el flujo de submit hoy validado en el repo sigue siendo Lace
    `signTx(...)` + witness export + fallback CLI hasta cerrar la parte de
    signer CLI
- Helper legacy/experimental:
  - `scripts/python/derive_preview_payment_skey.py`
  - el camino con `bip_utils` no reprodujo correctamente esta wallet Lace y ya
    no debe considerarse el camino principal
- El estado documentado ahí separa explícitamente:
  - material público versionable (`.addr`, metadata TOML, provider template)
  - material no listo todavía para versionar o automatizar (firma/submisión con Lace)
- En el flujo histórico retirado, el primer handoff con Lace exportaba:
  - `../zk-bridge-operator/preview_tx_artifacts/publish-proof-receipt-reference-script/unsigned.tx.cborhex`
  - ese directorio ya no existe en el repo actual
- El mecanismo esperado de firma con Lace para ese artifact es el DApp
  connector web-wallet (`window.cardano.lace.enable()` + `signTx(...)`), no el
  pipeline shell actual de `cshell tx sign`.
- Lace también puede enviar una tx desde el bridge web-wallet mediante
  `submitTx(...)` una vez que la app ya tiene la tx firmada; eso es distinto de
  la UI manual del wallet.
- En ese flujo histórico, el camino validado era:
  - firma en Lace desde `config/preview/lace_signer.html`
  - submit posterior desde CLI con `preview submit-signed-publish-proof-receipt`
- Un futuro paso razonable sería mover también ese submit al lado browser para
  cerrar un flujo 100% Lace/CIP-30.
- Ahora existe una página local mínima para ese handoff en:
  - `config/preview/lace_signer.html`
- Ahora también existe una página local de inspección para depurar ownership y
  addresses expuestas por Lace:
  - `config/preview/lace_inspect.html`
- El uso documentado de esa página es:
  - servir `config/preview/` por `python3 -m http.server`
  - abrir `http://127.0.0.1:<puerto>/lace_signer.html`
  - pegar el contenido de `unsigned.tx.cborhex`
  - conectar Lace
  - usar el botón único `Sign & Submit`
  - internamente firmar con `api.signTx(unsignedTxCborHex, false)`
  - recomponer la tx firmada preservando el body CBOR exacto y sustituyendo
    sólo el witness set
  - intentar `api.submitTx(signedTxCborHex)` directo desde Lace
- Esa página ahora también permite descargar el witness-set como:
  - `lace-witness-set.cborhex`
- La página actual todavía conserva el download del witness-set para mantener
  un fallback CLI si el submit directo del browser wallet falla.
- La página `lace_inspect.html` está pensada para responder una pregunta
  puntual:
  - si la cuenta actualmente conectada en Lace controla de verdad
    `preview-operator.addr`
- Esa página:
  - conecta por CIP-30
  - consulta `getChangeAddress`, `getUsedAddresses`, `getUnusedAddresses`,
    `getRewardAddresses`
  - intenta extensiones opcionales como `cip142`, `cip104` y `cip95` si están
    disponibles
  - prueba `signData()` sobre `preview-operator.addr`
  - interpreta éxito de `signData()` como evidencia de ownership de la payment
    key de esa address
- En una prueba real posterior, el `submitTx(...)` directo desde
  `config/preview/lace_signer.html` falló con un error provider-side que
  incluyó:
  - `InvalidWitnessesUTXOW`
- En contraste, el fallback CLI histórico con:
  - `preview submit-signed-publish-proof-receipt`
  sí aceptó y confirmó la tx correspondiente.
- Regla operativa actualizada:
  - el submit directo desde `lace_signer.html` quedó validado en la práctica
    para esta shape de tx Preview
  - el fallback `Download Witness` + submit CLI sigue siendo útil como camino
    alternativo y para persistencia repo-local del witness set
- La página ahora también intenta restaurar una sesión ya autorizada de Lace al
  cargar, y el botón `Connect Lace` se volvió idempotente para no romper el
  estado si la wallet ya estaba conectada de antes.
- `config/preview/lace_signer.html` ya no depende de reserializar la tx
  completa con CSL; ahora preserva byte a byte el body original y reemplaza
  sólo el witness set antes del `submitTx(...)`.
- En ese estado histórico, el operador también exponía:
  - `preview submit-signed-publish-proof-receipt`
- Ese comando consumía:
  - `../zk-bridge-operator/preview_tx_artifacts/publish-proof-receipt-reference-script/lace-handoff.json`
  - un witness-set descargado desde Lace como `lace-witness-set.cborhex`
- El submit actual hacia Preview usa `trp.submit` con `RawWitness(BytesEnvelope)`
  en vez del pipeline shell de `cshell tx sign`.
- Para Hito C, el flujo `phase12` Preview ahora queda modelado en tres pasos
  reanudables:
  - `preview_phase12/stake_distribution_genesis/publish-phase1-reference-script`
  - `preview_phase12/stake_distribution_genesis/phase1-setup`
  - `preview_phase12/stake_distribution_genesis/phase2-verify`
- El operador compartido ya expone comandos para cada uno de esos pasos:
  - `preview export-unsigned-publish-phase1-reference-script`
  - `preview export-unsigned-phase1-setup`
  - `preview export-unsigned-phase2-verify`
  - `preview check-status`
- El primer export real de ese flujo ya se verificó en:
  - `../zk-bridge-operator/preview_phase12/stake_distribution_genesis/publish-phase1-reference-script/`
- Esa unsigned inicial de `publish_phase1_reference_script` salió con hash:
  - `43b66370c48a253f75aaccab146e4329302c3244b8a426658a83b74a528c0625`
- Un intento inmediato de exportar `phase1_setup` contra ese artifact todavía
  no confirmado falló con:
  - `TRP resolve error -32002: input not resolved: collateral`
  porque el resolver buscó refs derivados de `43b66370...#0` que aún no
  existen on-chain.
- Regla operativa vigente para Hito C:
  - no exportar `phase1_setup` hasta confirmar `publish_phase1_reference_script`
  - no exportar `phase2_verify` hasta confirmar `phase1_setup`
- Al intentar enviar esa tx real a Preview, la red devolvió:
  - `ConwayUtxowFailure (UtxoFailure (MaxTxSizeUTxO Mismatch (RelLTEQ) {supplied: 16426, expected: 16384}))`
- Conclusión operativa verificada:
  - el primer tx de Hito C (`publish_phase1_reference_script`) hoy excede el
    límite real de tamaño de tx en Preview
  - este blocker es de red / tamaño de tx, no de Lace
  - cambiar sólo el signer no destraba Hito C
- Matiz importante verificado:
  - la unsigned exportada actual de `publish_phase1_reference_script` mide
    `16324` bytes
  - el nodo rechazó la versión final firmada con `supplied = 16426`
  - la diferencia es `102` bytes, consistente con overhead del witness-set
- Por eso puede pasar que `bridge-flow-summary.csv` o mediciones locales
  parezcan “entrar” mientras la tx final firmada ya no entra en Preview.
- Regla de interpretación vigente:
  - para blockers de `MaxTxSizeUTxO`, confiar en el tamaño reportado por la red
    para la tx final firmada por encima del tamaño de una unsigned/local summary
  - no asumir que una fila del CSV local corresponde byte a byte al CBOR final
    firmado por Lace
- Regla operativa nueva para exports Preview:
  - antes de confiar en cualquier export desde `zk-bridge-operator` que consuma
    el cliente Rust generado de Tx3, re-ejecutar:
    - `SYNC_SCOPE=phase12 ./scripts/bridge.sh sync` cuando el cambio afecte la
      superficie `phase12`
    - `trix codegen`
  - si no se hace eso, el export Preview puede estar usando IR generado stale
    aunque `main.tx3` ya haya cambiado
- Re-verificación concreta corrida en esta sesión:
  - en una corrida intermedia, el export Preview seguía dando:
    - hash `43b66370c48a253f75aaccab146e4329302c3244b8a426658a83b74a528c0625`
    - tamaño unsigned `16324`
  - luego se forzó un refresh más agresivo:
    - borrar `bridge-aiken/gen/rust-client/`
    - correr `trix build -v`
    - correr `trix codegen`
    - recompilar `zk-bridge-operator`
  - después de ese refresh completo, el mismo export Preview pasó a dar:
    - hash `84d66a356ae7030266076335655d1d96892d0f7b3f93c2f48c69d22b567eb913`
    - tamaño unsigned `16135`
  - conclusión verificada:
    - el cliente Rust generado sí puede quedar stale aunque `main.tx3` ya haya
      sido sincronizado
    - para validar realmente un cambio de tamaño en exports Preview, el
      refresh completo del cliente generado no es opcional
  - al intentar enviar esa versión regenerada a Preview, el rechazo pasó a:
    - `BabbageOutputTooSmallUTxO`
    - salida actual `Coin 3000000`
    - mínimo requerido `Coin 69701320`
  - conclusión operativa actualizada:
    - después de destrabar el tamaño de tx, el siguiente blocker real es el
      min-UTxO para publicar el reference script on-chain
    - esos `Coin 69701320` equivalen a `69.701320 ADA`
    - esa cifra corresponde al ADA mínimo inmovilizado dentro de la salida con
      reference script; no es fee ni collateral quemado por defecto
    - para no seguir exportando un publish claramente insuficiente, el default
      Preview de ese paso se subió a `75000000` lovelace
  - con ese nuevo default, el publish del phase-1 reference script quedó
    validado on-chain en Preview con hash:
    - `7ed3c8339c7eea7f3929f96a8c2ce3a253207b8f25b798da7252d2538e372db3`
  - significado operativo actualizado:
    - este publish es un setup one-time para el phase-1 script
    - una vez confirmado, el mismo reference-script UTxO puede reutilizarse
      para los flujos `phase1_setup` / `phase2_verify` posteriores
- Ya existe una corrida Preview/Lace real para la tx:
  - `publish_proof_receipt_reference_script`
- El hash verificado de esa tx es:
  - `d0052eaaf716ff6b65cb8c93cf66af2e0484747eef5e130e2b8b878f8ebf56f1`
- Los artifacts de esa corrida histórica quedaron en:
  - `../zk-bridge-operator/preview_tx_artifacts/publish-proof-receipt-reference-script/`
  - esa carpeta ya fue eliminada del repo actual
- El estado de esa tx se verificó luego con `trp.checkStatus` y resultó:
  - `confirmed`
  - `4 confirmations`
- Después de esa confirmación, la unsigned exportada previa quedó stale para un
  segundo intento de firma con Lace porque seguía referenciando el input del
  faucet original:
  - `de5c8bb1146f92131cf8e1ddeebf1f4e1b480588e728041d506dc3a2a3697387#0`
- Al re-exportar el handoff Preview después de esa primera confirmación, el
  nuevo hash unsigned verificado pasó a ser:
  - `11d8041932886ff479fe258161e6ed9e34cd2e28d1f4802647a1635d840d7bbc`
- Esa nueva unsigned ya referencia como input base el cambio proveniente de la
  tx confirmada anterior:
  - `d0052eaaf716ff6b65cb8c93cf66af2e0484747eef5e130e2b8b878f8ebf56f1#0`
- Lace devolvió luego ese mismo hash `11d804...` al intentar el submit
  browser-side desde `lace_signer.html`.
- Sin embargo, un `trp.checkStatus` posterior contra el endpoint Preview siguió
  devolviendo:
  - `stage = unknown`
  - `confirmations = 0`
  - `nonConfirmations = 0`
- Además, `preview.cardanoscan.io` no es scrapeable desde este entorno por
  bloqueo de Cloudflare, así que esa verificación externa no puede
  automatizarse acá.
- El usuario aportó luego evidencia manual directa de Cardanoscan para ese hash
  `11d804...`, mostrando:
  - timestamp confirmado
  - 5 confirmations
- Con esa evidencia humana, el submit browser-side queda considerado validado
  en la práctica aunque no totalmente automatizable desde este entorno.
- En una corrida Preview/Lace posterior para `phase1_setup`, el unsigned
  exportado inicialmente tuvo hash:
  - `65d77748251b81f124ff5623343aaca2d55568776d879084130ffa0332b9a6ab`
- Ese artifact fue firmado por Lace y Preview lo rechazó con:
  - `ValidationTagMismatch (IsValid True)`
  - `PlutusFailure`
  - overspend en el minting script `5bdfc1d95a49c060b2ca42b6946becc809f4a5d43ccad1728cb50579`
  - delta reportado:
    - `cpu = 1277419888`
    - `mem = 5862`
- `aiken check --plain-numbers` volvió a confirmar en este árbol que el
  runtime actual de `phase1_setup` está en el orden de:
  - `phase1_runtime_probe_test.{phase1_validator_accepts_real_fixture_with_precomputed_state}`
    - `mem: 13693605`
    - `cpu: 7195971804`
  - `two_phase/integration_test.{tx1_phase1_only}`
    - `mem: 13554311`
    - `cpu: 7141889643`
- Eso encaja con la lectura operativa:
  - el problema no fue la firma de Lace
  - el problema fue que el artifact unsigned salió con ex-units subestimadas
- El operador compartido ahora post-patchea el export de
  `preview export-unsigned-phase1-setup` antes del handoff a Lace:
  - sube ex-units del redeemer Mint
  - recompone fee, `script_data_hash` y body hash
  - usa defaults:
    - `mint_mem = 14000000`
    - `mint_steps = 7500000000`
    - `fee_buffer = 500000`
- Después de ese patch operator-side, el re-export vigente de
  `preview_phase12/stake_distribution_genesis/phase1-setup/` pasó a hash:
  - `f3ad9f7d968e4755063579fac868c63c979f70fbce231fa0f3970e526b7fd7e1`
- Regla operativa actualizada:
  - no volver a firmar el unsigned viejo `65d777...`
  - el próximo intento con Lace para `phase1_setup` debe usar `f3ad9f...`
- Un intento browser-side posterior con ese nuevo unsigned `f3ad9f...`
  devolvió:
  - `ScriptIntegrityHashMismatch`
  - supplied hash `68d5907352935b96e6ab34f8f7934c4394d102411095c118bbd46ab8068ea603`
  - expected hash `197eb19e4e0d9ee07ddb5fad94939c4e85c7b821622ba40d8a1851b463d66794`
- Causa aislada:
  - `config/preview/lace_signer.html` estaba reemplazando el witness set
    completo de la tx por el witness set devuelto por Lace
  - en `phase1_setup`, el witness set original ya contiene redeemers
  - Lace aporta principalmente `vkeywitness`, así que ese replace total
    descartaba redeemers y rompía el `script_data_hash`
- Fix aplicado:
  - `lace_signer.html` ahora hace merge top-level del witness map:
    - preserva los entries originales del witness set
    - sobreescribe/agrega sólo los entries que devuelve Lace
    - en la práctica conserva redeemers/datums y suma las firmas
- Lectura operativa actualizada:
  - el fallback CLI ya estaba alineado con este modelo porque `trp.submit`
    fusiona el raw witness dentro de la tx original del lado servidor
  - para txs scripted como `phase1_setup`, el submit browser-side ahora queda
    deshabilitado deliberadamente en la signer page después de firmar
  - la página firma, expone el witness set, y obliga al camino:
    - `Download Witness`
    - `preview submit-signed-artifact`
  - eso evita reintroducir `ScriptIntegrityHashMismatch` por un submit
    browser-side que no preserve exactamente el witness set original
- Para reducir riesgo operativo sobre Preview, el usuario verificó además que
  Lace sí permite fragmentar manualmente UTxOs del wallet:
  - separó un UTxO de `5 ADA` dedicado a collateral
- Lectura operativa:
  - ya no hace falta depender del UTxO grande de `~9800 ADA` como candidato
    principal de collateral
  - eso debería ayudar a que Lace seleccione collateral de forma más estable en
    los próximos intentos
- Re-verificación posterior vía Blockfrost contra `preview-operator.addr`:
  - UTxO chico de collateral:
    - `d73ef6bd43152b81a3c75ace2c1ef5c4248ea9e05800e87ecb323c01fd66599a#0`
    - `5000000` lovelace
  - cambio principal restante:
    - `d73ef6bd43152b81a3c75ace2c1ef5c4248ea9e05800e87ecb323c01fd66599a#1`
    - `9894128980` lovelace
- Cambio operativo posterior en el operador compartido:
  - para exports Preview scripted que requieren `collateral_utxo` explícito,
    el operador ahora consulta los UTxOs de `preview-operator.addr` por
    Blockfrost y elige automáticamente el candidato plain-ADA más chico
  - si el candidato más chico supera `10 ADA`, el export falla explícitamente
    en vez de agarrar un UTxO grande por accidente
- Re-export verificado después de ese cambio:
  - una primera iteración usó:
    - `collateral_utxo = d73ef6bd43152b81a3c75ace2c1ef5c4248ea9e05800e87ecb323c01fd66599a#0`
    - unsigned hash `8ccb099eee495249c44411f7cab47d60d6d232ae843281fffb0430615cfcefd8`
  - ese estado seguía corto de collateral real para Preview
  - el operador fue luego extendido para seleccionar también un `source`
    distinto del collateral, sin exponer todavía un `source_utxo` manual en la
    superficie de usuario
  - el estado verificado actual quedó:
    - `source input = f503961f5a12194a3ff1ad65ea884f4daa18434c983d2a5514c39f2268e57508#1`
    - `collateral_utxo = f503961f5a12194a3ff1ad65ea884f4daa18434c983d2a5514c39f2268e57508#0`
    - `fee = 3446687`
    - unsigned hash `c59341504a6d4f49ec2b6b1064429e00fd5f369fc143db8489a18bd4e6f43b71`
    - `script_data_hash = 197eb19e4e0d9ee07ddb5fad94939c4e85c7b821622ba40d8a1851b463d66794`
- Cierre operativo importante:
  - ese `script_data_hash` actual coincide exactamente con el valor que Preview
    antes devolvía como “expected” cuando rechazaba el artifact viejo
  - por lo tanto, el bug de integridad de script quedó aislado y corregido en
    el artifact unsigned actual
- Se corrió luego el submit por CLI fallback con el witness descargado desde
  Lace:
  - `preview submit-signed-artifact`
  - artifact `preview_phase12/stake_distribution_genesis/phase1-setup`
  - witness `lace-witness-set.cborhex`
- Ese submit ya no falló por witness merge ni por script integrity hash
- El rechazo actual pasó a ser:
  - `TRP submit error -32003: tx script returned failure`
  - `data={"logs":[]}`
- Lectura actualizada:
  - el problema de Lace / armado del witness set quedó destrabado
  - el blocker remanente ahora es el presupuesto real del script en red
- Diagnóstico low-level corrido después de ese submit:
  - `aiken tx simulate` sobre el artifact actual de `phase1_setup` falla en:
    - `Mint[0]`
    - policy hash `5bdfc1d95a49c060b2ca42b6946becc809f4a5d43ccad1728cb50579`
  - el modo de falla exacto es:
    - `execution went over budget`
    - `Mem -2127`
    - `CPU 2716840977`
  - interpretación posteriormente verificada:
    - el `Mem -2127` indica faltante de memoria bajo `aiken tx simulate`
    - el `CPU 2716840977` es CPU remanente, no déficit
  - subir artificialmente los ex-units declarados de esa misma tx a:
    - `mem = 50000000`
    - `steps = 50000000000`
    no cambió el resultado de `aiken tx simulate`, que siguió dando:
    - `Mem -2127`
    - `CPU 2716840977`
  - lectura operativa actualizada:
    - el bloqueo que Aiken expone hoy para `phase1_setup` es memoria
    - no alcanza con subir los ex-units declarados de la tx
- El usuario aportó luego un `bridge-flow-summary.csv` actualizado de
  `bridge.sh`, con estos puntos relevantes:
  - `phase1_setup_stake_distribution_standard`
    - `cpu_units = 7291687737`
    - `memory_units = 13994796`
  - `phase2_verify_*`
    - `cpu_units = 6985533222`
    - `memory_units = 768293`
  - `bridge_mint_tx`
    - `cpu_units = 5817641767`
    - `memory_units = 2529098`
- Lectura refinada:
  - el lane local / `bridge.sh` sí muestra una corrida donde
    `phase1_setup_stake_distribution_standard` entra con ~`7.29B` CPU
  - eso sigue siendo consistente con que Preview falle hoy para el artifact
    actual del lane genesis histórico de `phase1_setup`, porque:
    - no es el mismo dominio de proof (`genesis` vs `standard`)
    - no es necesariamente el mismo script efectivo / script hash
    - no es el mismo contexto final de tx que se está enviando en Preview
  - el dato nuevo más fuerte es que el lane local actualizado no contradice el
    diagnóstico de Preview; sólo demuestra que existe al menos un
    `phase1_setup` de otro dominio que sí queda por debajo de `10B` CPU
- Experimento posterior verificado y luego revertido:
  - se probó mover a `phase2` todo el prefijo restante de la MSM `set_0`
    que todavía ejecutaba `phase1`
  - con ese cambio, los probes aislados quedaron aproximadamente en:
    - `tx1_phase1_only`:
      - `cpu = 4917424995`
      - `mem = 13498343`
    - `phase1_runtime_probe_test.{phase1_validator_accepts_real_fixture_with_precomputed_state}`:
      - `cpu = 4971459156`
      - `mem = 13637337`
    - `phase2_runtime_probe_test.{phase2_validator_accepts_real_fixture_with_minimal_tx_context}`:
      - `cpu = 9267984304`
      - `mem = 939629`
  - sin embargo, al reconstruir una `phase1_setup` real de
    `stake_distribution_genesis` con los `phase1_state_*` recalculados para ese
    split, `aiken tx simulate` siguió fallando en:
    - tx hash `cbf8a1d31cf788c79c0b3dc3b66cdb0795dfd2e69b38005442befa59ea929bf6`
    - `Mint[0] execution went over budget`
    - `Mem -4690`
    - `CPU 4923033210`
  - sobre esa misma tx real, el probe low-level
    `cargo run --manifest-path ../dolos/Cargo.toml --bin phase2_mint_probe -- ...`
    devolvió:
    - `mint_redeemer_ex_units = { mem: 2000000, steps: 2000000000 }`
    - `consumed_budget = { mem: 14261409, cpu: 5128367412 }`
    - `success_unit = true`
  - lectura operativa:
    - el experimento sí movió costo desde `phase1` hacia `phase2`
    - no alcanzó para hacer que una `phase1_setup` real deje de fallar bajo
      `aiken tx simulate`
    - quedó expuesta una divergencia entre `aiken tx simulate` y el evaluador
      usado por `phase2_mint_probe` para la misma tx reconstruida
  - decisión tomada:
    - el cambio se revirtió
    - el split operativo vigente sigue siendo el anterior, donde `phase1`
      conserva el prefijo parcial de `set_0`
- Optimización verificada actualmente vigente para `phase1_setup`:
  - `validators/phase1.ak` consume:
    - `phase1_verifier_state_only(...)`
    en lugar del verifier completo que también construía `ReducedRedeemer`
  - `lib/halo2/halo2_kzg_split.ak` ahora serializa el material del
    `reduced_hash` con un helper por campos:
    - `serialize_reduced_redeemer_fields(...)`
    usando concatenación más balanceada
  - `lib/two_phase/proof_verifier_phase1.ak` en el camino
    `phase1_verifier_state_only(...)` evita rearmar `commitment_data` para
    los `q_eval` de TX1 y usa:
    - `set_0` / `set_1` / `set_2` / `set_3` separados
    - `compute_q_eval_for_entries(...)`
  - estado verificado más favorable de una `phase1_setup` real reconstruida:
    - tx hash `e71db3d76b38dd514309b476588e833f5214ba4be630411f6aca7887adbc7eb9`
    - `aiken tx simulate`:
      - `Mem -127`
      - `CPU 2722228651`
  - interpretación:
    - el gap de memoria local mejoró desde `-1998` hasta `-127`
    - el árbol sigue sin pasar `aiken tx simulate`, pero quedó mucho más cerca
- Optimizaciones adicionales probadas y descartadas después de ese estado:
  - reintroducir el single-pass recursive scan en `validators/phase1.ak`
    empeoró la tx real a:
    - `Mem -2392`
  - evitar construir `Phase2State` esperado completo antes de comparar mejoró
    algo, pero no superó el mejor estado:
    - mejor resultado medido: `Mem -1661`
  - fusionar chequeos redundantes de assets en `has_expected_phase2_output`
    no movió el resultado real:
    - `Mem -1661`
  - combinar `phase1_verifier_state_only(...)` con compare campo por campo del
    datum real dio:
    - `Mem -255`
    y siguió peor que `-127`
  - cambiar el transcript para acumular chunks y aplanar recién en
    `squeeze_challenge` empeoró fuerte la tx real a:
    - `Mem -5129`
  - esas variantes fueron descartadas / revertidas
- Se verificó luego que una `phase1_setup` regenerada con el script local
  actualizado sí entra bajo `aiken tx simulate` cuando se reconstruyen también
  sus artifacts auxiliares (`publish_phase1_reference_script` + `.tx` /
  `.sim_inputs` / `.resolved_inputs`) en el mismo run dir:
  - run dir:
    - `.omx/tmp/live-phase1-sim-nocommitment`
  - `publish_phase1_reference_script` regenerada:
    - hash `e2a15864d8c0c3c9701cd0272e35aff53b056fc94645dbd741b7f0707f5e59dd`
  - `phase1_setup` regenerada:
    - hash `4dd04ee25a8ca849f6d4083857a030dd8b2dfa220b6a6046acaa0df74373a37b`
  - `aiken tx simulate` sobre esa tx regenerada devolvió:
    - `mem = 13532901`
    - `cpu = 7160162501`
    - sin traces
- Quedó también verificado que el drift de `snapshot_membership` que rompía:
  - `tests/bridge_fixture_test`
  - `tests/minting_validator_test`
  no era sólo el proof exportado, sino una desalineación entre:
  - `scripts/data/bridge_mint_raw.json`
  - `validators/tests/helpers/bridge_fixture.ak`
  - `lib/zk/snapshot_membership_vk.ak`
- Hecho verificado:
  - regenerar el fixture con
    `python scripts/python/sync_bridge_zk_fixture.py --regenerate`
    produce un `minting_merkle_proof` que verifica off-chain
  - pero `aiken` sólo vuelve a aceptar ese proof si
    `lib/zk/snapshot_membership_vk.ak` se mantiene alineado con el VK de
    fixture actualmente usado por el árbol local
  - después de realinear ese verifier key, estos módulos volvieron a pasar:
    - `aiken check -m tests/bridge_fixture_test --plain-numbers`
    - `aiken check -m tests/minting_validator_test --plain-numbers`
- Se evaluó explícitamente reducir `phase12-all` a una sola
  `publish_phase1_reference_script` compartida entre:
  - `stake_distribution_genesis`
  - `stake_distribution_standard`
  - `cardano_transactions`
- Hechos verificados sobre esa investigación:
  - `main.tx3` define una única template `publish_phase1_reference_script`
    parametrizada sólo por `reference_script_lovelace`; no depende del dominio
  - `scripts/submit_phase1_phase2_transactions.sh` ya reutiliza un mismo Dolos
    entre los tres casos de `phase12-all`
  - por semántica on-chain, el mismo `PHASE1_REFERENCE_SCRIPT_UTXO` podría ser
    leído como `reference input` por múltiples `phase1_setup` si siguiera
    presente en el UTxO set
- Sin embargo, el experimento real mostró que hoy el runtime no preserva ese
  UTxO como reference-only:
  - al hacer que el segundo y tercer caso reutilizaran el
    `PHASE1_REFERENCE_SCRIPT_UTXO` del primer caso, el segundo `phase1_setup`
    falló con:
    - `reference input is not present in the UTxO set`
  - inspeccionando los CBORs del primer caso se verificó que:
    - `phase1_setup` usó el publish `#1` como `reference input`
    - `phase2_verify` del mismo dominio usó ese mismo publish `#1` como input
      normal
  - por eso el UTxO ya no estaba disponible para los dominios siguientes
- Se intentó luego fijar coin selection manual vía `source_utxo` explícito:
  - se agregó `source_utxo: UtxoRef` a `phase2_verify`
  - se inyectó en `phase2_args.json` el cambio `User` del `phase1_setup`
    inmediatamente anterior
  - `.tx3/tii/main.tii` expuso correctamente el parámetro `source_utxo`
  - el `phase2_args.json` regenerado contenía el `source_utxo` esperado
- La causa inmediata del comportamiento quedó aislada a la toolchain del
  resolver:
  - `../dolos/vendor/tx3-resolver/src/inputs/select/mod.rs`
  - el `ref` explícito hoy actúa como preferencia y no como constraint duro
  - si el `preferred` path no selecciona el UTxO referenciado, el selector cae
    al fallback general sobre candidatos disponibles
- Ese bug del resolver quedó luego corregido en el árbol local de `../dolos`:
  - `../dolos/vendor/tx3-resolver/src/inputs/select/mod.rs`
  - ahora, para queries single-input con `refs`, el selector devuelve
    directamente la selección sobre el subconjunto referido y no cae al
    fallback general
  - se agregó además el regression test:
    - `test_single_ref_does_not_fallback_when_preferred_ref_is_already_used`
    - `test_explicit_ref_query_beats_competing_generic_source_query`
      en `../dolos/vendor/tx3-resolver/src/inputs/select/tests.rs`
  - verificación local corrida en workspace temporal del crate vendorizado:
    - `cargo test --manifest-path <temp>/tx3-resolver/Cargo.toml --lib`
    - resultado final verificado: `39 passed`
- También quedó aislado y corregido el siguiente bloqueo visible del shared
  Dolos lane:
  - la publish compartida estaba consumiendo uno de los UTxOs sintéticos que
    dominios posteriores querían usar como `source_utxo`
  - además, `phase1_setup` y `phase2_verify` seguían necesitando partición
    explícita de source/collateral entre dominios
- El diseño operativo final verificado para `phase12-all` quedó así:
  - una sola `publish_phase1_reference_script` compartida por los tres dominios
  - un `source_utxo` dedicado para esa publish única
  - un `source_utxo` dedicado por dominio para `phase1_setup`
  - un `collateral_utxo` dedicado por dominio para
    `phase1_setup` / `phase2_verify`
  - `phase2_verify` consume `source_utxo` y `collateral_utxo` explícitos
  - el wrapper espera unos segundos entre dominios, pero la corrección fuerte
    viene de la partición explícita de UTxOs, no del timing
- Regla de seguridad que no se debe romper en futuros flujos:
  - nunca submittear una tx scriptada con ex-units placeholder, guessed, o no
    recompuestos después del resolve real
  - secuencia obligatoria:
    1. build/resolve de la tx exacta
    2. medición de ex-units reales para esa tx exacta
    3. agregar headroom explícito si la fase lo necesita
      - `phase2_verify` en Preview ya mostró un caso real donde el budget
        parchado al consumo exacto local seguía fallando on-chain
      - tx fallida: `f1037c0b0bb28b9a7f60c918b17698114ac2d264db0a1ae18de59412ab354b74`
      - `Spend[0]` y `Mint[0]` daban `success_unit=true` en probes locales,
        pero con márgenes minúsculos respecto del consumo
      - el operador quedó endurecido para aplicar headroom antes del patch
    4. patch de esos redeemers en el body
    5. recomputación de fee, change y hashes desde el body parchado
    6. firma del body parchado
    7. submit de esa misma tx firmada
  - motivo:
    saltarse esa secuencia ya demostró ser una forma concreta de perder el
    `collateral_utxo` con `valid_contract = false`
- Estado verificado después del fix de headroom:
  - tx exitosa de `phase2_verify`:
    - `0746b12e3337b04b0524099120150fa8a03e97cfabb1ea04deb3984ec14e925d`
  - Blockfrost:
    - `valid_contract = true`
    - `block_height = 4306104`
- Estado verificado posterior para `stake_distribution_genesis_tx` desde el
  operador Preview:
  - la primera corrida con `3000000 lovelace` en la salida script no entró y
    Blockfrost `tx/submit` devolvió:
    - `BabbageOutputTooSmallUTxO`
  - el operador quedó endurecido para fallar temprano si el valor pedido para
    esa salida queda por debajo del piso seguro actual, en vez de enterarse
    recién en submit
  - con `6000000 lovelace` de salida y submit directo del signed CBOR vía
    Blockfrost, sí pasó:
    - `4c8ef0d11e19a2744321283fd4099db4354ba526308e519d3ca86afaeeae8c33`
    - `valid_contract = true`
    - `block_height = 4306204`
- Estado verificado posterior para `stake_distribution_standard_tx`:
  - el template fue corregido para que tome un `source_utxo` explícito
  - los fees ya no salen del `parent_certificate_utxo`
  - eso garantiza que el UTxO del nuevo certificado conserve sus
    `6000000 lovelace`
  - chain previa usada:
    - `phase1_setup stake_distribution_standard`
      - `ac1c54d7b9abe1a63d5ee8f87d9d4f4361765226e9d21e27d2bf618e36d551f5`
    - `phase2_verify stake_distribution_standard`
      - `920a368c33445b8a146d66a31dab956f89b71995d8afeca258ce5f0abad9c902`
  - tx final verificada:
    - `def4e678b30df75b850555d9982382e5ecf8d7ee370ba16084eb4d7d02c2a7a8`
    - `valid_contract = true`
    - `block_height = 4306318`
- El operador Preview ahora también expone un flow unificado:
  - `preview invoke-cli-stake-distribution-genesis-flow`
  - mantiene los subcomandos separados por compatibilidad, pero el flow nuevo
    ya orquesta:
    - `phase1_setup`
    - `phase2_verify`
    - `stake_distribution_genesis_tx`
  - con `--skip-submit`, ese flow sólo puede verificarse contra anchors on-chain
    explícitos de las fases posteriores; no puede fingir que consume outputs
    todavía no submitteados
- El operador Preview ahora también expone:
  - `preview invoke-cli-stake-distribution-standard-flow`
  - mantiene el mismo objetivo de orquestar:
    - `phase1_setup`
    - `phase2_verify`
    - `stake_distribution_standard_tx`
  - en la verificación actual con `--skip-submit`, el wiring del comando quedó
    montado pero el resolve remoto de `phase2_verify` todavía puede fallar en:
    - `input not resolved: phase2_locked`
    aun cuando el ref explícito aparezca en la search space de Demeter/TRP
- Nota operativa adicional para el lane Preview:
  - después de un submit real, un `404` temprano de Blockfrost no debe tomarse
    como prueba de fracaso
  - el operador ahora reconsulta:
    - cada `15s`
    - durante hasta `2 minutos`
  - esto evita diagnosticar como “fallida” una tx que simplemente todavía no
    fue indexada y evita reprovisionar collateral innecesariamente
- Estado final verificado:
  - `./scripts/bridge.sh phase12-all --artifact artifacts/mithril-poc/latest/bridge-compatible-mithril-stm-bundle.json --output-dir artifacts/phase12-all/shared-phase1-publish-smoke-v11`
  - completó:
    - `stake_distribution_genesis`
    - `stake_distribution_standard`
    - `cardano_transactions`
  - cerró con:
    - `Session manifest check passed for mode: phase12-all`
    - `Combined phase12 session manifest written to: artifacts/phase12-all/shared-phase1-publish-smoke-v11/session.env`
  - hash verificado de la publish única compartida:
    - `fddfc205a4c76af9011766fcfde94d77d4fb2f940eb2eabf20df26d220f4a73b`
- También quedó verificado un hardening útil del wrapper local:
  - `scripts/sync_phase_scripts_to_tx3.sh` ahora fuerza mejor el rebuild de
    `.tx3/tii/main.tii` cuando cambia el fingerprint de inputs del sync
    aunque `main.tx3` y `env/default.ak` ya lleguen editados desde antes
  - ese cambio fue necesario para evitar experiments con TII stale durante la
    investigación de `source_utxo`
