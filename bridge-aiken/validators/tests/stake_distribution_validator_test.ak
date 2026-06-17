use aiken/collection/list
use cardano/assets
use cardano/transaction.{InlineDatum, OutputReference, Transaction}
use env
use stake_distribution.{StakeDistributionAssetDatum}
use tests/helpers/certificates/stake_distribution_certificates.{
  simple_dual_genesis_certificate,
}
use tests/helpers/certificates/stake_distribution_negative_certificates.{
  dual_genesis_certificate_with_incorrect_ed25519_signature,
  dual_genesis_certificate_with_incorrect_schnorr_signature,
  dual_genesis_certificate_with_incorrect_signed_message,
}
use tests/helpers/coherent_dual_genesis_fixture
use tests/helpers/proof_receipt
use tests/helpers/stake_distribution_asset_redeemer.{
  preview_sd_asset_redeemer_for_dual_genesis_certificate,
  proof_export_compatible_sd_asset_redeemer,
  sd_asset_redeemer_for_dual_genesis_certificate_with_incorrect_ed25519_signature,
  sd_asset_redeemer_for_dual_genesis_certificate_with_incorrect_public_input_challenge,
  sd_asset_redeemer_for_dual_genesis_certificate_with_incorrect_schnorr_signature,
  sd_asset_redeemer_for_dual_genesis_certificate_with_incorrect_signed_message,
  sd_asset_redeemer_for_genesis_certificate_with_incorrect_signature,
  sd_asset_redeemer_for_genesis_certificate_with_incorrect_signed_message,
  sd_asset_redeemer_with_incorrect_aggregate_verification_key,
  sd_asset_redeemer_with_incorrect_epoch_chaining,
  sd_asset_redeemer_with_incorrect_parent_hash,
  sd_asset_redeemer_with_incorrect_protocol_parameters,
  sd_asset_redeemer_with_incorrect_signed_entity_type, simple_sd_asset_redeemer,
  simple_sd_asset_redeemer_for_dual_genesis_certificate,
  simple_sd_asset_redeemer_for_genesis_certificate,
}
use tests/helpers/stake_distribution_tx.{
  preview_stake_distribution_tx_for_dual_genesis_certificate,
  proof_export_compatible_stake_distribution_tx, simple_stake_distribution_tx,
  simple_stake_distribution_tx_for_genesis_certificate,
  stake_distribution_transaction_without_parent_certificate_hash,
  stake_distribution_tx_for_certificate_with_incorrect_epoch_chaining,
  stake_distribution_tx_for_certificate_with_incorrect_parent_certificate_hash,
  stake_distribution_tx_for_genesis_certificate_with_parent_certificate,
  stake_distribution_tx_for_genesis_certificate_with_phase2_receipt_as_reference_input,
  stake_distribution_tx_for_genesis_certificate_without_phase2_receipt,
  stake_distribution_tx_for_sd_certificate_with_incorrect_aggregate_verification_key,
  stake_distribution_tx_for_sd_certificate_with_incorrect_protocol_parameters,
  stake_distribution_tx_for_sd_certificate_with_incorrect_signed_entity_type,
  stake_distribution_tx_new_certificate_with_different_spending_script,
  stake_distribution_tx_with_incorrect_phase2_statement_hash,
  stake_distribution_tx_with_phase2_receipt_as_reference_input,
  stake_distribution_tx_without_phase2_receipt,
}

fn run_stake_distribution_genesis_mint(redeemer, tx) {
  stake_distribution.stake_distribution_validator_mint.mint(
    redeemer,
    env.stake_distribution_asset_policy_id,
    tx,
  )
}

fn utxo_ref_and_datum_from_stake_distribution_tx(
  tx: Transaction,
) -> (OutputReference, StakeDistributionAssetDatum) {
  expect Some(input) =
    list.find(
      tx.inputs,
      fn(input) {
        assets.has_nft_strict(
          input.output.value,
          env.stake_distribution_asset_policy_id,
          env.stake_distribution_asset_name,
        )
      },
    )
  expect InlineDatum(raw) = input.output.datum
  expect stake_distribution_asset_datum: StakeDistributionAssetDatum = raw
  (input.output_reference, stake_distribution_asset_datum)
}

fn run_stake_distribution_spend(datum, redeemer, utxo_ref, tx) {
  stake_distribution.stake_distribution_validator_spend.spend(
    proof_receipt.proof_receipt_spending_script,
    env.phase2_asset_policy_id,
    env.stake_distribution_asset_policy_id,
    datum,
    redeemer,
    utxo_ref,
    tx,
  )
}

fn run_standard_certificate_spend(redeemer, tx: Transaction) {
  let (utxo_ref, datum) = utxo_ref_and_datum_from_stake_distribution_tx(tx)
  run_stake_distribution_spend(Some(datum), redeemer, utxo_ref, tx)
}

test accepts_legacy_genesis_certificate() {
  run_stake_distribution_genesis_mint(
    simple_sd_asset_redeemer_for_genesis_certificate(),
    simple_stake_distribution_tx_for_genesis_certificate(),
  )
}

test rejects_legacy_genesis_certificate_with_parent_certificate() fail {
  run_stake_distribution_genesis_mint(
    simple_sd_asset_redeemer_for_genesis_certificate(),
    stake_distribution_tx_for_genesis_certificate_with_parent_certificate(),
  )
}

test accepts_legacy_genesis_certificate_without_phase2_receipt_input() {
  run_stake_distribution_genesis_mint(
    simple_sd_asset_redeemer_for_genesis_certificate(),
    stake_distribution_tx_for_genesis_certificate_without_phase2_receipt(),
  )
}

test accepts_legacy_genesis_certificate_when_phase2_receipt_is_only_a_reference_input() {
  run_stake_distribution_genesis_mint(
    simple_sd_asset_redeemer_for_genesis_certificate(),
    stake_distribution_tx_for_genesis_certificate_with_phase2_receipt_as_reference_input(),
  )
}

test rejects_legacy_genesis_certificate_with_incorrect_signature() fail {
  run_stake_distribution_genesis_mint(
    sd_asset_redeemer_for_genesis_certificate_with_incorrect_signature(),
    simple_stake_distribution_tx_for_genesis_certificate(),
  )
}

test rejects_legacy_genesis_certificate_with_incorrect_signed_message() fail {
  run_stake_distribution_genesis_mint(
    sd_asset_redeemer_for_genesis_certificate_with_incorrect_signed_message(),
    simple_stake_distribution_tx_for_genesis_certificate(),
  )
}

test accepts_preview_dual_genesis_certificate_through_real_mint_entrypoint() {
  run_stake_distribution_genesis_mint(
    preview_sd_asset_redeemer_for_dual_genesis_certificate(),
    preview_stake_distribution_tx_for_dual_genesis_certificate(),
  )
}

test accepts_dual_genesis_certificate_with_valid_proof() {
  stake_distribution.experimental_dual_genesis_certificate_verifies(
    simple_sd_asset_redeemer_for_dual_genesis_certificate(),
    simple_dual_genesis_certificate(),
    coherent_dual_genesis_fixture.genesis_verification_key(),
    coherent_dual_genesis_fixture.verification_key_u,
    coherent_dual_genesis_fixture.verification_key_v,
  )
}

test rejects_dual_genesis_certificate_with_altered_schnorr_signature() fail {
  stake_distribution.experimental_dual_genesis_certificate_verifies(
    sd_asset_redeemer_for_dual_genesis_certificate_with_incorrect_schnorr_signature(),
    dual_genesis_certificate_with_incorrect_schnorr_signature(),
    coherent_dual_genesis_fixture.genesis_verification_key(),
    coherent_dual_genesis_fixture.verification_key_u,
    coherent_dual_genesis_fixture.verification_key_v,
  )
}

test rejects_dual_genesis_certificate_with_invalid_proof() fail {
  stake_distribution.experimental_dual_genesis_certificate_verifies(
    sd_asset_redeemer_for_dual_genesis_certificate_with_incorrect_public_input_challenge(),
    simple_dual_genesis_certificate(),
    coherent_dual_genesis_fixture.genesis_verification_key(),
    coherent_dual_genesis_fixture.verification_key_u,
    coherent_dual_genesis_fixture.verification_key_v,
  )
}

test rejects_dual_genesis_certificate_with_signed_message_not_matching_public_input() fail {
  stake_distribution.experimental_dual_genesis_certificate_verifies(
    sd_asset_redeemer_for_dual_genesis_certificate_with_incorrect_signed_message(),
    dual_genesis_certificate_with_incorrect_signed_message(),
    coherent_dual_genesis_fixture.genesis_verification_key(),
    coherent_dual_genesis_fixture.verification_key_u,
    coherent_dual_genesis_fixture.verification_key_v,
  )
}

test rejects_dual_genesis_certificate_with_altered_ed25519_half() fail {
  stake_distribution.experimental_dual_genesis_certificate_verifies(
    sd_asset_redeemer_for_dual_genesis_certificate_with_incorrect_ed25519_signature(),
    dual_genesis_certificate_with_incorrect_ed25519_signature(),
    coherent_dual_genesis_fixture.genesis_verification_key(),
    coherent_dual_genesis_fixture.verification_key_u,
    coherent_dual_genesis_fixture.verification_key_v,
  )
}

test accepts_standard_certificate() {
  run_standard_certificate_spend(
    simple_sd_asset_redeemer(),
    simple_stake_distribution_tx(),
  )
}

test accepts_proof_export_compatible_standard_certificate() {
  run_standard_certificate_spend(
    proof_export_compatible_sd_asset_redeemer(),
    proof_export_compatible_stake_distribution_tx(),
  )
}

test rejects_standard_certificate_with_incorrect_phase2_statement_hash() fail {
  run_standard_certificate_spend(
    simple_sd_asset_redeemer(),
    stake_distribution_tx_with_incorrect_phase2_statement_hash(),
  )
}

test rejects_standard_certificate_without_phase2_receipt_input() fail {
  run_standard_certificate_spend(
    simple_sd_asset_redeemer(),
    stake_distribution_tx_without_phase2_receipt(),
  )
}

test rejects_standard_certificate_when_phase2_receipt_is_only_a_reference_input() fail {
  run_standard_certificate_spend(
    simple_sd_asset_redeemer(),
    stake_distribution_tx_with_phase2_receipt_as_reference_input(),
  )
}

test rejects_standard_certificate_without_parent_certificate() fail {
  run_standard_certificate_spend(
    simple_sd_asset_redeemer(),
    stake_distribution_transaction_without_parent_certificate_hash(),
  )
}

test rejects_standard_certificate_when_output_uses_different_spending_script() fail {
  run_standard_certificate_spend(
    simple_sd_asset_redeemer(),
    stake_distribution_tx_new_certificate_with_different_spending_script(),
  )
}

test rejects_standard_certificate_with_incorrect_parent_hash() fail {
  run_standard_certificate_spend(
    sd_asset_redeemer_with_incorrect_parent_hash(),
    stake_distribution_tx_for_certificate_with_incorrect_parent_certificate_hash(),
  )
}

test rejects_standard_certificate_with_invalid_epoch_chain() fail {
  run_standard_certificate_spend(
    sd_asset_redeemer_with_incorrect_epoch_chaining(),
    stake_distribution_tx_for_certificate_with_incorrect_epoch_chaining(),
  )
}

test rejects_standard_certificate_with_incorrect_snark_avk() fail {
  run_standard_certificate_spend(
    sd_asset_redeemer_with_incorrect_aggregate_verification_key(),
    stake_distribution_tx_for_sd_certificate_with_incorrect_aggregate_verification_key(),
  )
}

test rejects_standard_certificate_with_incorrect_protocol_parameters() fail {
  run_standard_certificate_spend(
    sd_asset_redeemer_with_incorrect_protocol_parameters(),
    stake_distribution_tx_for_sd_certificate_with_incorrect_protocol_parameters(),
  )
}

test rejects_certificate_with_non_stake_distribution_signed_entity() fail {
  run_standard_certificate_spend(
    sd_asset_redeemer_with_incorrect_signed_entity_type(),
    stake_distribution_tx_for_sd_certificate_with_incorrect_signed_entity_type(),
  )
}
