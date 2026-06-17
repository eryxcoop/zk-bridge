use aiken/cbor.{serialise}
use aiken/collection/list
use aiken/crypto.{Hash, Sha3_256, sha3_256}
use ak_381/groth16.{Proof, SnarkVerificationKey}
use cardano/address.{Address, PaymentCredential}
use cardano/assets.{PolicyId, Value, from_lovelace, merge}
use cardano/transaction.{
  Datum, InlineDatum, Input, Output, OutputReference, Transaction,
}
use common_types.{BridgeId, LockingTxDatum}
use env
use mithril_certificate.{MithrilCertificate}
use stake_distribution.{StakeDistributionAssetDatum}
use validator_aux_functions.{
  find_output_with_value, locking_tx_hash_is_added_to_the_used_txs_set,
}
use verify_certificate.{verify_mithril_standard_certificate}
use zk_verification.{Single, empty_circuit_vk, zk_verify}

/// The MintingValidatorRedeemer contains a mithril certificate, this certificate should contain
/// a merkle root of the Cardano transactions snapshot. The redeemer should also contain a proof that 
/// verifies that the certificate is valid (´locking_tx_mithril_proof´) and a merkle proof of 
/// inclusion of the locking transaction (´locking_tx_hash´) in the certificate's merkle root.
/// The last 5 fields are used to build the locking transaction in the validator and check that it's hash
/// matches ´locking_tx_hash´
pub type MintingValidatorRedeemer {
  tx_snapshot_certificate: MithrilCertificate,
  locking_tx_mithril_proof: Proof,
  locking_tx_merkle_proof: Proof,
  locking_tx_hash: Hash<Sha3_256, Transaction>,
  locking_tx_input_output_reference: OutputReference,
  locking_tx_input_payment_credential: PaymentCredential,
  locking_tx_input_datum: Datum,
  locking_tx_destination_address: PaymentCredential,
  locking_tx_ada_amount: Int,
}

/// Returns true if the output's value has the stake distribution NFT
fn output_has_stake_distribution_nft(output: Output) -> Bool {
  assets.has_nft_strict(
    output.value,
    env.stake_distribution_asset_policy_id,
    env.stake_distribution_asset_name,
  )
}

/// Given a list of inputs, returns the one that has the stake distribution NFT
fn find_input_with_stake_distribution_nft(inputs: List<Input>) -> Option<Input> {
  list.find(
    inputs,
    fn(input) { output_has_stake_distribution_nft(input.output) },
  )
}

/// Verifies the merkle proof of inclusion of the locking_tx_hash in the transactions snapshot
/// certificate
fn verify_transaction_is_present_in_snapshot(
  tx_snapshot_certificate: MithrilCertificate,
  proof: Proof,
  _locking_tx_hash: Hash<Sha3_256, Transaction>,
) -> Bool {
  let public_input = tx_snapshot_certificate.epoch
  zk_verify(proof, [Single(public_input)], merkle_proof_verification_vk())
}

/// For this milestone we use a placeholder circuit which can be found in `milestone_4_deliverables/circuits/minting_circuit.circom`
fn merkle_proof_verification_vk() -> SnarkVerificationKey {
  empty_circuit_vk()
}

/// Builds the locking transaction using the given parameters. The locking transaction must 
/// have one input and one output
fn expected_locking_tx_from(
  input_output_reference: OutputReference,
  input_payment_credential: PaymentCredential,
  input_datum: Datum,
  asset_value: Value,
  destination_address: PaymentCredential,
  bridge_id: BridgeId,
) -> Transaction {
  let expected_tx_input =
    Input {
      output_reference: input_output_reference,
      output: Output {
        address: Address {
          payment_credential: input_payment_credential,
          stake_credential: None,
        },
        datum: input_datum,
        value: asset_value,
        reference_script: None,
      },
    }
  let expected_tx_utxo =
    Output {
      address: Address {
        payment_credential: env.unlocked_funds_spending_script,
        stake_credential: None,
      },
      datum: InlineDatum(LockingTxDatum { bridge_id, destination_address }),
      value: asset_value,
      reference_script: None,
    }
  Transaction {
    ..transaction.placeholder,
    inputs: [expected_tx_input],
    outputs: [expected_tx_utxo],
  }
}

/// This function gets the stake distribution certificate that must be in the reference inputs
/// of the minting transaction
fn get_sd_certificate_from_ref_inputs(tx: Transaction) {
  expect Some(sd_input) =
    find_input_with_stake_distribution_nft(tx.reference_inputs)
  expect InlineDatum(raw) = sd_input.output.datum
  expect StakeDistributionAssetDatum { certificate: sd_certificate } = raw
  sd_certificate
}

/// Computes the hash of the locking transaction using data from the redeemer and some data from the minting transaction itself
/// (i.e. minted tokens and address from the output that contains the minted tokens) 
fn compute_locking_tx_hash(
  redeemer: MintingValidatorRedeemer,
  policy_id: PolicyId,
  minting_tx: Transaction,
) {
  let MintingValidatorRedeemer {
    locking_tx_input_output_reference,
    locking_tx_input_payment_credential,
    locking_tx_input_datum,
    locking_tx_destination_address,
    locking_tx_ada_amount,
    ..
  } = redeemer

  expect Some(minted_asset_output) =
    find_output_with_value(
      minting_tx,
      minting_tx.mint,
      locking_tx_destination_address,
    )

  let locking_tx_value =
    merge(minting_tx.mint, from_lovelace(locking_tx_ada_amount))

  let expected_locking_tx =
    expected_locking_tx_from(
      input_output_reference: locking_tx_input_output_reference,
      input_payment_credential: locking_tx_input_payment_credential,
      input_datum: locking_tx_input_datum,
      asset_value: locking_tx_value,
      destination_address: minted_asset_output.address.payment_credential,
      bridge_id: policy_id,
    )
  sha3_256(serialise(expected_locking_tx))
}

fn locking_tx_hash_is_correct(
  tx: Transaction,
  redeemer: MintingValidatorRedeemer,
  policy_id: PolicyId,
) {
  let expected_locking_tx_hash: Hash<Sha3_256, Transaction> =
    compute_locking_tx_hash(redeemer, policy_id, tx)

  (redeemer.locking_tx_hash == expected_locking_tx_hash)?
}

validator minting_validator {
  mint(redeemer: MintingValidatorRedeemer, policy_id: PolicyId, tx: Transaction) {
    let MintingValidatorRedeemer {
      tx_snapshot_certificate,
      locking_tx_mithril_proof,
      locking_tx_merkle_proof,
      locking_tx_hash,
      ..
    } = redeemer

    let stake_distribution_certificate = get_sd_certificate_from_ref_inputs(tx)
    and {
      locking_tx_hash_is_added_to_the_used_txs_set(tx,
        locking_tx_hash,
        env.locking_txs_updater_policy_id,
        env.locking_txs_updater_asset_name
      )?,
      verify_mithril_standard_certificate(
        certificate: tx_snapshot_certificate,
        parent_certificate: stake_distribution_certificate,
        proof: locking_tx_mithril_proof,
      )?,
      verify_transaction_is_present_in_snapshot(
        tx_snapshot_certificate,
        locking_tx_merkle_proof,
        locking_tx_hash,
      )?,
      locking_tx_hash_is_correct(tx, redeemer, policy_id),
    }
  }

  else(_) {
    fail
  }
}
