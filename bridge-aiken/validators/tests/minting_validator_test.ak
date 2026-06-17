use env
use minting
use tests/helpers/minting_redeemer.{
  minting_validator_redeemer_with_incorrect_locking_tx_hash,
  minting_validator_redeemer_with_incorrect_parent_certificate,
  minting_validator_redeemer_with_invalid_merkle_proof,
  minting_validator_redeemer_with_invalid_snapshot_root,
  minting_validator_redeemer_with_invalid_sub_root,
  simple_minting_validator_redeemer, valid_snapshot_membership_minting_redeemer,
}
use tests/helpers/minting_tx.{
  minting_tx_with_incorrect_parent_certificate,
  minting_tx_with_incorrect_phase2_statement_hash,
  minting_tx_with_phase2_receipt_as_reference_input,
  minting_tx_without_phase2_receipt, minting_tx_without_tx_updater_nft,
  simple_minting_tx, simple_minting_tx_with_many_inputs,
  simple_minting_tx_with_many_outputs,
  simple_minting_tx_with_many_reference_inputs,
  simple_minting_tx_with_mismatched_txs_updater_tx_id,
}
use tests/helpers/proof_receipt

fn run_minting_validator(redeemer, tx) {
  minting.minting_validator.mint(
    proof_receipt.proof_receipt_spending_script,
    env.phase2_asset_policy_id,
    env.stake_distribution_asset_policy_id,
    redeemer,
    env.bridge_minting_policy_id,
    tx,
  )
}

test minting_validator_accepts_valid_snapshot_membership_fixture() {
  run_minting_validator(
    valid_snapshot_membership_minting_redeemer(),
    simple_minting_tx(),
  )
}

test minting_validator_rejects_incorrect_parent_certificate() fail {
  run_minting_validator(
    minting_validator_redeemer_with_incorrect_parent_certificate(),
    simple_minting_tx(),
  )
}

test minting_validator_rejects_incorrect_locking_tx_hash() fail {
  run_minting_validator(
    minting_validator_redeemer_with_incorrect_locking_tx_hash(),
    simple_minting_tx(),
  )
}

test minting_validator_rejects_invalid_merkle_proof() fail {
  run_minting_validator(
    minting_validator_redeemer_with_invalid_merkle_proof(),
    simple_minting_tx(),
  )
}

test minting_validator_rejects_invalid_snapshot_root() fail {
  run_minting_validator(
    minting_validator_redeemer_with_invalid_snapshot_root(),
    simple_minting_tx(),
  )
}

test minting_validator_rejects_invalid_sub_root() fail {
  run_minting_validator(
    minting_validator_redeemer_with_invalid_sub_root(),
    simple_minting_tx(),
  )
}

test minting_validator_accepts_canonical_transaction() {
  run_minting_validator(
    valid_snapshot_membership_minting_redeemer(),
    simple_minting_tx(),
  )
}

test minting_validator_accepts_canonical_transaction_with_extra_inputs() {
  run_minting_validator(
    valid_snapshot_membership_minting_redeemer(),
    simple_minting_tx_with_many_inputs(),
  )
}

test minting_validator_accepts_canonical_transaction_with_extra_outputs() {
  run_minting_validator(
    valid_snapshot_membership_minting_redeemer(),
    simple_minting_tx_with_many_outputs(),
  )
}

test minting_validator_accepts_canonical_transaction_with_extra_reference_inputs() {
  run_minting_validator(
    valid_snapshot_membership_minting_redeemer(),
    simple_minting_tx_with_many_reference_inputs(),
  )
}

test minting_validator_rejects_incorrect_phase2_statement_hash() fail {
  run_minting_validator(
    simple_minting_validator_redeemer(),
    minting_tx_with_incorrect_phase2_statement_hash(),
  )
}

test minting_validator_requires_phase2_receipt_input() fail {
  run_minting_validator(
    simple_minting_validator_redeemer(),
    minting_tx_without_phase2_receipt(),
  )
}

test minting_validator_rejects_phase2_receipt_when_it_is_only_a_reference_input() fail {
  run_minting_validator(
    simple_minting_validator_redeemer(),
    minting_tx_with_phase2_receipt_as_reference_input(),
  )
}

test minting_validator_only_requires_the_stake_distribution_nft_reference_input() {
  run_minting_validator(
    valid_snapshot_membership_minting_redeemer(),
    minting_tx_with_incorrect_parent_certificate(),
  )
}

test minting_validator_requires_txs_updater_input() fail {
  run_minting_validator(
    valid_snapshot_membership_minting_redeemer(),
    minting_tx_without_tx_updater_nft(),
  )
}

test minting_validator_requires_matching_txs_updater_tx_id() fail {
  run_minting_validator(
    valid_snapshot_membership_minting_redeemer(),
    simple_minting_tx_with_mismatched_txs_updater_tx_id(),
  )
}
