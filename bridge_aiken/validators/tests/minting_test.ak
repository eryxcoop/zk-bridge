use env
use minting
use tests/helpers/minting_redeemer.{
  minting_validator_redeemer_with_incorrect_locking_tx_hash,
  minting_validator_redeemer_with_invalid_merkle_proof,
  minting_validator_redeemer_with_invalid_mithril_proof,
  simple_minting_validator_redeemer,
}
use tests/helpers/minting_tx.{
  minting_tx_without_tx_updater_nft, simple_minting_tx,
  simple_minting_tx_with_many_inputs, simple_minting_tx_with_many_outputs,
  simple_minting_tx_with_many_reference_inputs,
}

test minting_validator_test() {
  minting.minting_validator.mint(
    simple_minting_validator_redeemer(),
    env.bridge_minting_policy_id,
    simple_minting_tx(),
  )
}

test minting_validator_test_with_many_inputs() {
  minting.minting_validator.mint(
    simple_minting_validator_redeemer(),
    env.bridge_minting_policy_id,
    simple_minting_tx_with_many_inputs(),
  )
}

test minting_validator_test_with_many_outputs() {
  minting.minting_validator.mint(
    simple_minting_validator_redeemer(),
    env.bridge_minting_policy_id,
    simple_minting_tx_with_many_outputs(),
  )
}

test minting_validator_test_with_many_reference_inputs() {
  minting.minting_validator.mint(
    simple_minting_validator_redeemer(),
    env.bridge_minting_policy_id,
    simple_minting_tx_with_many_reference_inputs(),
  )
}

test minting_validator_invalid_mithril_proof_test() fail {
  minting.minting_validator.mint(
    minting_validator_redeemer_with_invalid_mithril_proof(),
    env.bridge_minting_policy_id,
    simple_minting_tx(),
  )
}

test minting_validator_invalid_merkle_proof_test() fail {
  minting.minting_validator.mint(
    minting_validator_redeemer_with_invalid_merkle_proof(),
    env.bridge_minting_policy_id,
    simple_minting_tx(),
  )
}

test minting_validator_test_incorrect_locking_tx_hash() fail {
  minting.minting_validator.mint(
    minting_validator_redeemer_with_incorrect_locking_tx_hash(),
    env.bridge_minting_policy_id,
    simple_minting_tx(),
  )
}

test minting_validator_checks_that_one_input_has_tx_updater_nft() fail {
  minting.minting_validator.mint(
    simple_minting_validator_redeemer(),
    env.bridge_minting_policy_id,
    minting_tx_without_tx_updater_nft(),
  )
}
