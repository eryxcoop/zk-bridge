use cardano/transaction.{InlineDatum, OutputReference, Transaction}
use env
use stake_distribution.{StakeDistributionAssetDatum}
use tests/helpers/stake_distribution_asset_redeemer.{
  sd_asset_redeemer_with_incorrect_aggregate_verification_key,
  sd_asset_redeemer_with_incorrect_epoch_chaining,
  sd_asset_redeemer_with_incorrect_parent_hash,
  sd_asset_redeemer_with_incorrect_protocol_parameters,
  sd_asset_redeemer_with_incorrect_signed_entity_type,
  sd_asset_redeemer_with_invalid_mithril_proof, simple_sd_asset_redeemer,
  simple_sd_asset_redeemer_for_genesis_certificate,
}
use tests/helpers/stake_distribution_tx.{
  simple_stake_distribution_tx,
  simple_stake_distribution_tx_for_genesis_certificate,
  stake_distribution_transaction_without_parent_certificate_hash,
  stake_distribution_tx_for_certificate_with_incorrect_epoch_chaining,
  stake_distribution_tx_for_certificate_with_incorrect_parent_certificate_hash,
  stake_distribution_tx_for_genesis_certificate_with_different_utxo_ref,
  stake_distribution_tx_for_genesis_certificate_with_parent_certificate,
  stake_distribution_tx_for_sd_certificate_with_incorrect_aggregate_verification_key,
  stake_distribution_tx_for_sd_certificate_with_incorrect_protocol_parameters,
  stake_distribution_tx_for_sd_certificate_with_incorrect_signed_entity_type,
  stake_distribution_tx_new_certificate_with_different_spending_script,
}

fn utxo_ref_and_datum_from_stake_distribution_tx(
  tx: Transaction,
) -> (OutputReference, StakeDistributionAssetDatum) {
  expect [input] = tx.inputs
  expect InlineDatum(raw) = input.output.datum
  expect stake_distribution_asset_datum: StakeDistributionAssetDatum = raw
  (input.output_reference, stake_distribution_asset_datum)
}

test stake_distribution_validator_genesis_certificate_test() {
  stake_distribution.stake_distribution_validator_mint.mint(
    env.stake_distribution_asset_unique_mint_utxo_ref,
    simple_sd_asset_redeemer_for_genesis_certificate(),
    env.stake_distribution_asset_policy_id,
    simple_stake_distribution_tx_for_genesis_certificate(),
  )
}

test stake_distribution_validator_genesis_certificate_without_parent_certificate_test() fail {
  stake_distribution.stake_distribution_validator_mint.mint(
    env.stake_distribution_asset_unique_mint_utxo_ref,
    simple_sd_asset_redeemer_for_genesis_certificate(),
    env.stake_distribution_asset_policy_id,
    stake_distribution_tx_for_genesis_certificate_with_parent_certificate(),
  )
}

test stake_distribution_validator_genesis_certificate_with_a_different_utxo_test() fail {
  stake_distribution.stake_distribution_validator_mint.mint(
    env.stake_distribution_asset_unique_mint_utxo_ref,
    simple_sd_asset_redeemer_for_genesis_certificate(),
    env.stake_distribution_asset_policy_id,
    stake_distribution_tx_for_genesis_certificate_with_different_utxo_ref(),
  )
}

test stake_distribution_validator_sd_certificate_test() {
  let stake_distribution_tx = simple_stake_distribution_tx()
  let (utxo_ref, datum) =
    utxo_ref_and_datum_from_stake_distribution_tx(stake_distribution_tx)
  stake_distribution.stake_distribution_validator_spend.spend(
    Some(datum),
    simple_sd_asset_redeemer(),
    utxo_ref,
    stake_distribution_tx,
  )
}

test stake_distribution_validator_invalid_mithril_proof_test() fail {
  let stake_distribution_tx = simple_stake_distribution_tx()
  let (utxo_ref, datum) =
    utxo_ref_and_datum_from_stake_distribution_tx(stake_distribution_tx)
  stake_distribution.stake_distribution_validator_spend.spend(
    Some(datum),
    sd_asset_redeemer_with_invalid_mithril_proof(),
    utxo_ref,
    stake_distribution_tx,
  )
}

test stake_distribution_validator_sd_certificate_must_have_parent_certificate_test() fail {
  let stake_distribution_tx =
    stake_distribution_transaction_without_parent_certificate_hash()
  let (utxo_ref, datum) =
    utxo_ref_and_datum_from_stake_distribution_tx(stake_distribution_tx)
  stake_distribution.stake_distribution_validator_spend.spend(
    Some(datum),
    simple_sd_asset_redeemer(),
    utxo_ref,
    stake_distribution_tx,
  )
}

test stake_distribution_validator_new_certificate_must_have_same_spending_script_test() fail {
  let stake_distribution_tx =
    stake_distribution_tx_new_certificate_with_different_spending_script()
  let (utxo_ref, datum) =
    utxo_ref_and_datum_from_stake_distribution_tx(stake_distribution_tx)
  stake_distribution.stake_distribution_validator_spend.spend(
    Some(datum),
    simple_sd_asset_redeemer(),
    utxo_ref,
    stake_distribution_tx,
  )
}

test stake_distribution_validator_incorrect_parent_certificate_hash_test() fail {
  let stake_distribution_tx =
    stake_distribution_tx_for_certificate_with_incorrect_parent_certificate_hash()
  let (utxo_ref, datum) =
    utxo_ref_and_datum_from_stake_distribution_tx(stake_distribution_tx)
  stake_distribution.stake_distribution_validator_spend.spend(
    Some(datum),
    sd_asset_redeemer_with_incorrect_parent_hash(),
    utxo_ref,
    stake_distribution_tx,
  )
}

test stake_distribution_validator_sd_certificate_has_not_one_epoch_more_than_parent_certificate_test() fail {
  let stake_distribution_tx =
    stake_distribution_tx_for_certificate_with_incorrect_epoch_chaining()
  let (utxo_ref, datum) =
    utxo_ref_and_datum_from_stake_distribution_tx(stake_distribution_tx)
  stake_distribution.stake_distribution_validator_spend.spend(
    Some(datum),
    sd_asset_redeemer_with_incorrect_epoch_chaining(),
    utxo_ref,
    stake_distribution_tx,
  )
}

test stake_distribution_validator_sd_certificate_with_incorrect_aggregate_verification_key_test() fail {
  let stake_distribution_tx =
    stake_distribution_tx_for_sd_certificate_with_incorrect_aggregate_verification_key()
  let (utxo_ref, datum) =
    utxo_ref_and_datum_from_stake_distribution_tx(stake_distribution_tx)
  stake_distribution.stake_distribution_validator_spend.spend(
    Some(datum),
    sd_asset_redeemer_with_incorrect_aggregate_verification_key(),
    utxo_ref,
    stake_distribution_tx,
  )
}

test stake_distribution_validator_sd_certificate_with_incorrect_protocol_parameters_test() fail {
  let stake_distribution_tx =
    stake_distribution_tx_for_sd_certificate_with_incorrect_protocol_parameters()
  let (utxo_ref, datum) =
    utxo_ref_and_datum_from_stake_distribution_tx(stake_distribution_tx)
  stake_distribution.stake_distribution_validator_spend.spend(
    Some(datum),
    sd_asset_redeemer_with_incorrect_protocol_parameters(),
    utxo_ref,
    stake_distribution_tx,
  )
}

test stake_distribution_validator_with_incorrect_signed_entity_type_test() fail {
  let stake_distribution_tx =
    stake_distribution_tx_for_sd_certificate_with_incorrect_signed_entity_type()
  let (utxo_ref, datum) =
    utxo_ref_and_datum_from_stake_distribution_tx(stake_distribution_tx)
  stake_distribution.stake_distribution_validator_spend.spend(
    Some(datum),
    sd_asset_redeemer_with_incorrect_signed_entity_type(),
    utxo_ref,
    stake_distribution_tx,
  )
}
