// Auto-managed environment constants for the bridge contracts.
//
// Do not edit by hand. Every automated update to this file goes through a
// single writer:
//
//   scripts/python/sync_phase_scripts_to_tx3.py
//
// The writer reconciles policy ids, script hashes and a few related fields
// against the compiled Plutus blueprints and `main.tx3`. Which constants it
// touches depends on the `SYNC_SCOPE` env var it receives:
//
//   - phase12              → phase2_asset_policy_id
//   - stake_distribution   → stake_distribution_spending_script,
//                            stake_distribution_asset_policy_id
//   - bridge               → locking_txs_updater_policy_id,
//                            locking_txs_updater_spending_script,
//                            bridge_minting_policy_id,
//                            transferred_asset_policy_id
//   - all                  → every constant above
//
// All other constants in this file (the burning_txs_updater_* group,
// locking_txs_updater_asset_name, locking_txs_updater_unique_mint_utxo_ref,
// locking_txs_updater_initial_merkle_root, unlocked_funds_spending_script,
// genesis_verification_key, stake_distribution_asset_name,
// transferred_asset_name) are not touched by the writer and must be updated
// manually when the underlying parameters change.
//
// Flows that trigger the writer (always via scripts/sync_phase_scripts_to_tx3.sh,
// the shell wrapper around the Python writer):
//
//   - scripts/bridge.sh sync              → manual run, scope chosen by caller
//   - scripts/bridge.sh phase12           → submit_phase1_phase2_transactions_single_case.sh
//                                           (SYNC_SCOPE=phase12)
//   - scripts/bridge.sh stake-distribution → mithril_stake_distribution.sh
//                                            (SYNC_SCOPE=stake_distribution)
//   - scripts/bridge.sh bridge            → bridge_minting.sh
//                                           (SYNC_SCOPE=all, then SYNC_SCOPE=bridge)
//   - scripts/bridge.sh run               → runs the full PoC pipeline, which
//                                           transitively triggers all of the
//                                           above; each flow stage backs up
//                                           env/default.ak and restores it on
//                                           failure (smoke-tested by
//                                           scripts/tests/smoke_sync_restore.sh).
//
// The writer is idempotent: re-running with the same blueprints produces the
// same file, so `bridge.sh run` rewriting a constant several times in a single
// invocation is expected and not a bug.
//
// Read-only consumers (do not modify this file):
//   - scripts/python/prepare_mithril_bridge_minting_args.py
//   - scripts/python/sync_bridge_zk_fixture.py
//
// See AGENTS.md for the full sync/restore protocol.

use cardano/address.{Credential, Script}
use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference}
use mithril/mithril_certificate.{GenesisVerificationKey}

// txs_updater_unlocking (i.e., for burning transactions)
pub const burning_txs_updater_asset_name: ByteArray = "TxsUpdaterNFT"

pub const burning_txs_updater_policy_id: PolicyId =
  #"e3629e11a475df98bd7cf97661ae1e701ac27ffa3f8f7878da8a3c10"

pub const burning_txs_updater_spending_script: Credential =
  Script(#"87a50143f0a5f82a0b13a9e9d7ed3be91be4884f348f2701fdfaa3ef")

pub const burning_txs_updater_unique_mint_utxo_ref: OutputReference =
  OutputReference {
    transaction_id: #"e402f971a5143cb92f28fa7ca98450e641edcbd789458adc6555c227ad3468a5",
    output_index: 1,
  }

pub const burning_txs_updater_initial_merkle_root: ByteArray =
  #"836cc68931c2e4e3e838602eca1902591d216837bafddfe6f0c8cb07"

// txs_updater_minting (i.e., for locking transactions)
pub const locking_txs_updater_asset_name: ByteArray = "TxsUpdaterNFT"

pub const locking_txs_updater_policy_id: PolicyId =
  #"d6813158687efbae8199d9c35b6b9e5103079abb3daf376582fe25fd"

pub const locking_txs_updater_spending_script: Credential =
  Script(#"d0f200682744c8a10d6fb6c97c10e004c78ede2960869f4fe57be33b")

pub const locking_txs_updater_unique_mint_utxo_ref: OutputReference =
  OutputReference {
    transaction_id: #"99568a43e3ac8bf76b04863fe55a7d0043dd43496fc97c07b5e7ae31fe575057",
    output_index: 0,
  }

pub const locking_txs_updater_initial_merkle_root: ByteArray =
  #"1081218ce61ee106396796dc2b469a63b99a934125107c4cc30050966f39b130"

// unlocking validator
pub const unlocked_funds_spending_script: Credential =
  Script(#"6ff9b5e2926e9eb6601647b004bd8ea5c674e5ebab02549c876e55ae")

// stake distribution validator
// Source:
// https://raw.githubusercontent.com/input-output-hk/mithril/main/mithril-infra/configuration/pre-release-preview/genesis.vkey
// Decoded from Mithril's published JsonHex format into the raw 32-byte Ed25519 verification key.
pub const genesis_verification_key: GenesisVerificationKey =
  GenesisVerificationKey(
    #"7f497ca1068983d5cf75c655b0c7a2f1447b77910de8f331e502f9cdcd27eb2c",
  )

// Temporary trust anchor for the Groth16-backed Schnorr half of
// `GenesisDualSignature`.
//
// Provenance:
// - `input-output-hk/mithril`
// - branch `jpraynaud/3145-snark-friendly-genesis-certificate`
// - deterministic STM golden vector consumed by
//   `circuit_jubjub_schnorr_verification/fixtures/valid_deterministic_vector.json`
//
// This is not yet a production network dual bundle. It exists so the bridge
// can model and test the dual-signature path before Mithril publishes a stable
// Schnorr genesis verification key for runtime use.
pub const genesis_schnorr_verification_key_u: Int =
  28153324423867457666386337918486746564366670615804845649025564287389474821818

pub const genesis_schnorr_verification_key_v: Int =
  19834851423795617621281065444719196780261659977294753884839631378592271643792

/// Policy id of the phase-2 receipt NFT accepted as proof by downstream
/// validators.
///
/// We intentionally do not hardcode the asset name alongside this policy id:
/// phase 2 mints the receipt NFT using as token name the reduced redeemer hash
/// computed in phase 1, so the concrete name is pseudo-random and not known in
/// advance to validators like `stake_distribution` or `minting`.
pub const phase2_asset_policy_id: PolicyId =
  #"2694be01c9fefd6ce78b5664f7e31aca5c364e7abaa68a0ea640be63"

pub const stake_distribution_spending_script: Credential =
  Script(#"2c6c8e6aa7e119a48c80bdfbd6401c69e8e856e3adb57b82abc3e9a2")

pub const stake_distribution_asset_policy_id: PolicyId =
  #"a4b014681bd74955a6e2293f99189cb876c5c043757424edcc44152e"

pub const stake_distribution_asset_name: ByteArray = "stake_distribution_asset"

// transferred asset
pub const transferred_asset_policy_id: PolicyId =
  #"65c7985c26383748f65ed812cd6c9f0689962c89f95ba86c8bf8c759"

pub const transferred_asset_name: ByteArray = "token_asset_name"

// minting validator
pub const bridge_minting_policy_id: PolicyId =
  #"65c7985c26383748f65ed812cd6c9f0689962c89f95ba86c8bf8c759"
