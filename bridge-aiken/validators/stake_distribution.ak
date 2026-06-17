use aiken/collection/list
use aiken/collection/pairs
use aiken/crypto
use aiken/primitive/bytearray
use cardano/address.{Credential}
use cardano/assets.{PolicyId}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use env
use mithril/certificate_metadata.{ProtocolParameters}
use mithril/certificate_signature.{GenesisDualSignature}
use mithril/mithril_certificate.{GenesisVerificationKey, MithrilCertificate}
use mithril/protocol_message.{
  NextAggregateVerificationKey, NextSnarkAggregateVerificationKey,
}
use mithril/reduced_mithril_certificate.{
  ReducedMithrilCertificate, reduced_mithril_certificate_from_certificate,
  verify_reduced_mithril_certificate_against_parent_state,
}
use mithril/verify_certificate.{
  verify_epoch_matches_protocol_message, verify_mithril_genesis_certificate,
}
use two_phase/proof_receipt
use utils.{hex_string_to_bytes}
use zk/jubjub_schnorr_verification.{JubjubSchnorrProof}

pub type StakeDistributionMintRedeemer {
  new_certificate: MithrilCertificate,
  jubjub_schnorr_proof: JubjubSchnorrProof,
}

pub type StakeDistributionCertificateState {
  hash: ByteArray,
  epoch: Int,
  protocol_parameters: ProtocolParameters,
  next_aggregate_verification_key: ByteArray,
  aggregate_verification_key: ByteArray,
  next_aggregate_verification_key_snark: ByteArray,
  aggregate_verification_key_snark: ByteArray,
}

pub type StakeDistributionAssetDatum {
  certificate: StakeDistributionCertificateState,
}

pub fn certificate_state_from_certificate(
  certificate: MithrilCertificate,
) -> StakeDistributionCertificateState {
  expect Some(next_aggregate_verification_key) =
    pairs.get_first(certificate.protocol_message, NextAggregateVerificationKey)
  expect Some(next_aggregate_verification_key_snark) =
    pairs.get_first(
      certificate.protocol_message,
      NextSnarkAggregateVerificationKey,
    )

  StakeDistributionCertificateState {
    hash: certificate.hash,
    epoch: certificate.epoch,
    protocol_parameters: certificate.metadata.protocol_parameters,
    next_aggregate_verification_key: bytearray.from_string(
      next_aggregate_verification_key,
    ),
    aggregate_verification_key: certificate.aggregate_verification_key,
    next_aggregate_verification_key_snark: bytearray.from_string(
      next_aggregate_verification_key_snark,
    ),
    aggregate_verification_key_snark: certificate.aggregate_verification_key_snark,
  }
}

fn certificate_state_from_spend_redeemer(
  certificate: ReducedMithrilCertificate,
) -> StakeDistributionCertificateState {
  StakeDistributionCertificateState {
    hash: certificate.hash,
    epoch: certificate.epoch,
    protocol_parameters: certificate.protocol_parameters,
    next_aggregate_verification_key: certificate.protocol_message_next_aggregate_verification_key,
    aggregate_verification_key: certificate.aggregate_verification_key,
    next_aggregate_verification_key_snark: certificate.protocol_message_next_aggregate_verification_key_snark,
    aggregate_verification_key_snark: certificate.aggregate_verification_key_snark,
  }
}

fn find_new_certificate_output(
  tx: Transaction,
  new_certificate_state: StakeDistributionCertificateState,
) -> Option<Output> {
  list.find(
    tx.outputs,
    fn(o) {
      when o.datum is {
        InlineDatum(raw) ->
          if raw
          is StakeDistributionAssetDatum { certificate }: StakeDistributionAssetDatum {
            (certificate == new_certificate_state)?
          } else {
            False
          }
        _ -> False
      }
    },
  )
}

/// Extracts the statement hash from the unique phase-2 proof receipt.
fn statement_hash_from_phase2_receipt(
  tx: Transaction,
  proof_receipt_spending_script: Credential,
  phase2_asset_policy_id: PolicyId,
) -> ByteArray {
  expect Some(statement_hash) =
    proof_receipt.statement_hash(
      tx,
      proof_receipt_spending_script,
      phase2_asset_policy_id,
    )
  statement_hash
}

pub fn verify_standard_certificate_against_parent_state(
  certificate: ReducedMithrilCertificate,
  parent_certificate: StakeDistributionCertificateState,
  statement_hash: ByteArray,
) -> Bool {
  verify_reduced_mithril_certificate_against_parent_state(
    certificate,
    parent_certificate.hash,
    parent_certificate.epoch,
    parent_certificate.protocol_parameters,
    parent_certificate.next_aggregate_verification_key_snark,
    parent_certificate.aggregate_verification_key_snark,
    statement_hash,
  )
}

pub fn verify_mithril_certificate_against_parent_state(
  certificate: MithrilCertificate,
  parent_certificate: StakeDistributionCertificateState,
  statement_hash: ByteArray,
) -> Bool {
  let reduced_certificate =
    reduced_mithril_certificate_from_certificate(certificate)
  verify_standard_certificate_against_parent_state(
    reduced_certificate,
    parent_certificate,
    statement_hash,
  )
}

pub fn spend_redeemer_from_certificate(
  certificate: MithrilCertificate,
) -> ReducedMithrilCertificate {
  reduced_mithril_certificate_from_certificate(certificate)
}

pub fn experimental_dual_genesis_certificate_verifies(
  redeemer: StakeDistributionMintRedeemer,
  certificate: MithrilCertificate,
  genesis_verification_key: GenesisVerificationKey,
  genesis_schnorr_verification_key_u: Int,
  genesis_schnorr_verification_key_v: Int,
) -> Bool {
  let GenesisVerificationKey(verification_key) = genesis_verification_key
  when certificate.signature is {
    GenesisDualSignature { ed25519_signature, schnorr_signature } -> and {
        jubjub_schnorr_verification.jubjub_genesis_schnorr_proof_verifies(
          redeemer.jubjub_schnorr_proof.proof,
          certificate.signed_message,
          schnorr_signature,
          genesis_schnorr_verification_key_u,
          genesis_schnorr_verification_key_v,
          redeemer.jubjub_schnorr_proof.verification_key_u,
          redeemer.jubjub_schnorr_proof.verification_key_v,
          redeemer.jubjub_schnorr_proof.signature_response,
          redeemer.jubjub_schnorr_proof.signature_challenge,
        )?,
        crypto.verify_ed25519_signature(
          verification_key,
          certificate.signed_message,
          hex_string_to_bytes(bytearray.to_string(ed25519_signature)),
        )?,
        verify_epoch_matches_protocol_message(certificate)?,
      }
    _ -> False
  }
}

validator stake_distribution_validator_spend(
  proof_receipt_spending_script: Credential,
  phase2_asset_policy_id: PolicyId,
  stake_distribution_asset_policy_id: PolicyId,
) {
  spend(
    datum: Option<StakeDistributionAssetDatum>,
    redeemer: ReducedMithrilCertificate,
    own_ref: OutputReference,
    tx: Transaction,
  ) {
    // We verify the parent certificate from the input's datum
    expect Some(StakeDistributionAssetDatum { certificate: parent_certificate }) =
      datum

    // We verify that the stake distribution NFT is being transferred from the UTxO with the parent certificate
    // to the UTxO with the new certificate. `own_input` is the parent certificate's input.
    expect Some(own_input) = transaction.find_input(tx.inputs, own_ref)

    // `redeemer` contains the new certificate, and the transaction must also
    // consume the phase-2 receipt proving the certificate's signed message.
    let new_certificate = redeemer
    let new_certificate_state =
      certificate_state_from_spend_redeemer(new_certificate)
    expect Some(new_certificate_output) =
      find_new_certificate_output(tx, new_certificate_state)
    let statement_hash =
      statement_hash_from_phase2_receipt(
        tx,
        proof_receipt_spending_script,
        phase2_asset_policy_id,
      )
    and {
      (new_certificate_output.address.payment_credential == own_input.output.address.payment_credential)?,
      new_certificate.signed_entity_is_stake_distribution?,
      (new_certificate.signed_entity_epoch == new_certificate.epoch)?,
      assets.has_nft_strict(
        own_input.output.value,
        stake_distribution_asset_policy_id,
        env.stake_distribution_asset_name,
      )?,
      assets.has_nft_strict(
        new_certificate_output.value,
        stake_distribution_asset_policy_id,
        env.stake_distribution_asset_name,
      )?,
      verify_standard_certificate_against_parent_state(
        new_certificate,
        parent_certificate,
        statement_hash,
      )?,
    }
  }

  else(_) {
    fail
  }
}

validator stake_distribution_validator_mint {
  mint(
    redeemer: StakeDistributionMintRedeemer,
    policy_id: PolicyId,
    tx: Transaction,
  ) {
    // `redeemer` contains a genesis certificate, and the transaction generates
    // an UTxO with an NFT carrying the genesis-authenticated parent state.
    let new_certificate = redeemer.new_certificate
    let new_certificate_state =
      certificate_state_from_certificate(new_certificate)
    expect Some(genesis_certificate_output) =
      find_new_certificate_output(tx, new_certificate_state)
    and {
      assets.has_nft_strict(
        genesis_certificate_output.value,
        policy_id,
        env.stake_distribution_asset_name,
      )?,
      verify_mithril_genesis_certificate(
        new_certificate,
        redeemer.jubjub_schnorr_proof,
        env.genesis_verification_key,
      )?,
    }
  }

  else(_) {
    fail
  }
}
