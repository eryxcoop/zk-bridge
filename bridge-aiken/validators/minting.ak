////     verified when producing that NFT-bearing UTxO).

use aiken/cbor
use aiken/collection/list
use ak_381/groth16.{Proof}
use bridge/common_types.{LockingTxDatum}
use bridge/locking_tx_hash
use bridge/validator_aux_functions.{
  find_output_with_value, locking_tx_hash_is_added_to_the_used_txs_set,
}
use cardano/address.{PaymentCredential, VerificationKey}
use cardano/assets.{PolicyId}
use cardano/transaction.{Input, Output, Transaction}
use env
use mithril/certificate_metadata.{ProtocolParameters}
use mithril/reduced_mithril_certificate.{
  ReducedMithrilCertificate,
  verify_reduced_mithril_certificate_against_parent_state,
}
use two_phase/proof_receipt
use zk/snapshot_membership

/// The MintingValidatorRedeemer contains a Mithril certificate with a Cardano
/// transactions snapshot plus a merkle proof of inclusion of the locking
/// transaction in that snapshot. The certificate itself is validated against a
/// phase-2 proof receipt present in the transaction inputs.
pub type MintingValidatorRedeemer {
  tx_snapshot_certificate_hash: ByteArray,
  tx_snapshot_certificate_prev_hash: ByteArray,
  tx_snapshot_certificate_epoch: Int,
  tx_snapshot_certificate_protocol_parameters_k: Int,
  tx_snapshot_certificate_protocol_parameters_m: Int,
  tx_snapshot_certificate_protocol_parameters_phi_f: ByteArray,
  tx_snapshot_certificate_protocol_message_next_aggregate_verification_key: ByteArray,
  tx_snapshot_certificate_protocol_message_next_aggregate_verification_key_snark: ByteArray,
  tx_snapshot_certificate_protocol_message_next_protocol_parameters: ByteArray,
  tx_snapshot_certificate_protocol_message_current_epoch: ByteArray,
  tx_snapshot_certificate_protocol_message_cardano_transactions_merkle_root: ByteArray,
  tx_snapshot_certificate_signed_message: ByteArray,
  tx_snapshot_certificate_aggregate_verification_key: ByteArray,
  tx_snapshot_certificate_aggregate_verification_key_snark: ByteArray,
  tx_snapshot_certificate_signed_entity_is_stake_distribution: Bool,
  tx_snapshot_certificate_signed_entity_epoch: Int,
  parent_certificate_hash: ByteArray,
  parent_certificate_epoch: Int,
  parent_certificate_protocol_parameters_k: Int,
  parent_certificate_protocol_parameters_m: Int,
  parent_certificate_protocol_parameters_phi_f: ByteArray,
  parent_certificate_next_aggregate_verification_key_snark: ByteArray,
  parent_certificate_aggregate_verification_key_snark: ByteArray,
  locking_tx_merkle_proof_public_sub_root: ByteArray,
  locking_tx_merkle_proof_pi_a: ByteArray,
  locking_tx_merkle_proof_pi_b: ByteArray,
  locking_tx_merkle_proof_pi_c: ByteArray,
  locking_tx_hash: ByteArray,
  locking_tx_input_output_reference_tx_id: ByteArray,
  locking_tx_input_output_reference_output_index: Int,
  locking_tx_output_address: ByteArray,
  locking_tx_output_lovelace: Int,
  locking_tx_destination_payment_credential: ByteArray,
  locking_tx_asset_amount: Int,
  locking_tx_fee: Int,
}

/// Returns true if the output's value has the stake distribution NFT
fn output_has_stake_distribution_nft(
  output: Output,
  stake_distribution_asset_policy_id: PolicyId,
) -> Bool {
  assets.has_nft_strict(
    output.value,
    stake_distribution_asset_policy_id,
    env.stake_distribution_asset_name,
  )
}

/// Given a list of inputs, returns the one that has the stake distribution NFT
fn find_input_with_stake_distribution_nft(
  inputs: List<Input>,
  stake_distribution_asset_policy_id: PolicyId,
) -> Option<Input> {
  list.find(
    inputs,
    fn(input) {
      output_has_stake_distribution_nft(
        input.output,
        stake_distribution_asset_policy_id,
      )
    },
  )
}

/// Locates the stake-distribution reference input among the transaction's
/// reference inputs.
fn find_sd_reference_input(
  inputs: List<Input>,
  stake_distribution_asset_policy_id: PolicyId,
) -> Option<Input> {
  find_input_with_stake_distribution_nft(
    inputs,
    stake_distribution_asset_policy_id,
  )
}

/// Verifies the merkle proof of inclusion of the legacy-named
/// `locking_tx_hash` field in the transactions snapshot certificate.
///
/// Compatibility note: this field now carries the canonical Cardano
/// transaction hash, not a bridge-derived digest.
pub fn verify_transaction_is_present_in_snapshot(
  tx_snapshot_certificate: ReducedMithrilCertificate,
  proof: Proof,
  redeemer: MintingValidatorRedeemer,
) -> Bool {
  snapshot_membership.proof_verifies(
    proof,
    redeemer.locking_tx_hash,
    redeemer.locking_tx_merkle_proof_public_sub_root,
    tx_snapshot_certificate.protocol_message_cardano_transactions_merkle_root,
  )
}

/// Checks that the Mithril transactions-snapshot certificate carried in the
/// redeemer is properly anchored to a trusted parent stake distribution certificate and
/// signs the phase-2 statement.
///
/// The check requires two pieces of off-chain data to be present in the transaction:
///   1. A reference input holding the stake-distribution NFT. Its presence is
///      what tells this validator that the parent certificate state passed in
///      the redeemer (`parent_certificate_*` fields) is valid (the certificate was  
///   2. A spent input holding the phase-2 proof-receipt NFT. Its inline
///      datum carries the `statement_hash` produced by phase-2 verification,
///      which is the value the Mithril certificate must be signing.
///
/// When both are present, the function
/// `verify_reduced_mithril_certificate_against_parent_state` is called, which enforces
/// the full chain of constraints between the new `tx_snapshot_certificate`
/// and the parent state (prev_hash link, epoch progression, AVK / SNARK-AVK
/// chaining, protocol-parameter chaining, and that the certificate's
/// `signed_message` matches `statement_hash`).
///
/// Returns `False` if either piece of evidence is missing or if 
/// `verify_reduced_mithril_certificate_against_parent_state` returns `False`.
fn certificate_is_valid_for(
  tx: Transaction,
  tx_snapshot_certificate: ReducedMithrilCertificate,
  redeemer: MintingValidatorRedeemer,
  proof_receipt_spending_script: PaymentCredential,
  phase2_asset_policy_id: PolicyId,
  stake_distribution_asset_policy_id: PolicyId,
) -> Bool {
  when
    find_sd_reference_input(
      tx.reference_inputs,
      stake_distribution_asset_policy_id,
    )
  is {
    Some(_) ->
      when
        proof_receipt.statement_hash(
          tx,
          proof_receipt_spending_script,
          phase2_asset_policy_id,
        )
      is {
        Some(statement_hash) ->
          verify_reduced_mithril_certificate_against_parent_state(
            tx_snapshot_certificate,
            redeemer.parent_certificate_hash,
            redeemer.parent_certificate_epoch,
            ProtocolParameters {
              k: redeemer.parent_certificate_protocol_parameters_k,
              m: redeemer.parent_certificate_protocol_parameters_m,
              phi_f: redeemer.parent_certificate_protocol_parameters_phi_f,
            },
            redeemer.parent_certificate_next_aggregate_verification_key_snark,
            redeemer.parent_certificate_aggregate_verification_key_snark,
            statement_hash,
          )
        None -> False
      }
    None -> False
  }
}

/// Rebuilds the `ReducedMithrilCertificate` value from the flat redeemer
/// fields.
///
/// `MintingValidatorRedeemer` keeps every certificate field at the top level
/// (instead of nesting a `ReducedMithrilCertificate`) so that the off-chain
/// builder can populate it without depending on the Aiken type layout. This
/// helper is the single place where that flat form is reassembled into the
/// structured certificate consumed by the verification helpers.
fn reduced_certificate_from_redeemer(
  redeemer: MintingValidatorRedeemer,
) -> ReducedMithrilCertificate {
  ReducedMithrilCertificate {
    hash: redeemer.tx_snapshot_certificate_hash,
    prev_hash: redeemer.tx_snapshot_certificate_prev_hash,
    epoch: redeemer.tx_snapshot_certificate_epoch,
    protocol_parameters: ProtocolParameters {
      k: redeemer.tx_snapshot_certificate_protocol_parameters_k,
      m: redeemer.tx_snapshot_certificate_protocol_parameters_m,
      phi_f: redeemer.tx_snapshot_certificate_protocol_parameters_phi_f,
    },
    protocol_message_next_aggregate_verification_key: redeemer.tx_snapshot_certificate_protocol_message_next_aggregate_verification_key,
    protocol_message_next_aggregate_verification_key_snark: redeemer.tx_snapshot_certificate_protocol_message_next_aggregate_verification_key_snark,
    protocol_message_next_protocol_parameters: redeemer.tx_snapshot_certificate_protocol_message_next_protocol_parameters,
    protocol_message_current_epoch: redeemer.tx_snapshot_certificate_protocol_message_current_epoch,
    protocol_message_cardano_transactions_merkle_root: redeemer.tx_snapshot_certificate_protocol_message_cardano_transactions_merkle_root,
    signed_message: redeemer.tx_snapshot_certificate_signed_message,
    aggregate_verification_key: redeemer.tx_snapshot_certificate_aggregate_verification_key,
    aggregate_verification_key_snark: redeemer.tx_snapshot_certificate_aggregate_verification_key_snark,
    signed_entity_is_stake_distribution: redeemer.tx_snapshot_certificate_signed_entity_is_stake_distribution,
    signed_entity_epoch: redeemer.tx_snapshot_certificate_signed_entity_epoch,
  }
}

/// Rebuilds the Groth16 `Proof` of inclusion of the locking transaction in
/// the Mithril snapshot from the flat redeemer fields.
///
/// As with `reduced_certificate_from_redeemer`, the proof's curve points are
/// passed in the redeemer as separate `pi_a` / `pi_b` / `pi_c` byte arrays
/// for off-chain ergonomics; this helper packages them into the `Proof`
/// record expected by the snapshot-membership verifier.
pub fn merkle_proof_from_redeemer(redeemer: MintingValidatorRedeemer) -> Proof {
  Proof {
    piA: redeemer.locking_tx_merkle_proof_pi_a,
    piB: redeemer.locking_tx_merkle_proof_pi_b,
    piC: redeemer.locking_tx_merkle_proof_pi_c,
  }
}

/// Rebuilds the canonical Cardano transaction id of the minimal locking
/// transaction from the redeemer's body fields and checks it equals the
/// `locking_tx_hash` that the Mithril snapshot proof binds.
///
/// The bridge forces the locking transaction into a rigid layout (one input,
/// one output at index 0 carrying the bridged native asset plus an inline
/// `LockingTxDatum`, a fee, and nothing else). Both the bridge native asset
/// `(policy, name)` and the datum's `bridge_id` are fixed by the running
/// minting policy and `env`, so they cannot be forged in the redeemer: any
/// deviation produces a different hash that won't match the proved one. This is
/// what cryptographically ties the locked amount and destination to a real,
/// settled Cardano transaction.
///
/// The bridge native asset policy and the datum's `bridge_id` both equal this
/// minting validator's own policy id. Reading the runtime `policy_id` (rather
/// than the `env.bridge_minting_policy_id` / `env.transferred_asset_policy_id`
/// constants, which are themselves this hash) keeps the constant out of the
/// compiled code, so the validator hash does not depend on itself.
fn locking_tx_body_hash_is_valid(
  redeemer: MintingValidatorRedeemer,
  policy_id: PolicyId,
) -> Bool {
  let datum =
    cbor.serialise(
      LockingTxDatum {
        bridge_id: policy_id,
        destination_address: VerificationKey(
          redeemer.locking_tx_destination_payment_credential,
        ),
      },
    )
  locking_tx_hash.canonical_locking_tx_hash(
    redeemer.locking_tx_input_output_reference_tx_id,
    redeemer.locking_tx_input_output_reference_output_index,
    redeemer.locking_tx_output_address,
    redeemer.locking_tx_output_lovelace,
    policy_id,
    env.transferred_asset_name,
    redeemer.locking_tx_asset_amount,
    datum,
    redeemer.locking_tx_fee,
  ) == redeemer.locking_tx_hash
}

/// Binds the minted bridge tokens to the locked asset: exactly
/// `locking_tx_asset_amount` units of the bridge asset must be minted, and an
/// output must carry that amount to the locking transaction's declared
/// destination credential. Both quantities are already tied to the locking
/// transaction by `locking_tx_body_hash_is_valid`.
fn minted_amount_and_destination_are_valid(
  tx: Transaction,
  policy_id: PolicyId,
  redeemer: MintingValidatorRedeemer,
) -> Bool {
  and {
    (assets.quantity_of(tx.mint, policy_id, env.transferred_asset_name) == redeemer.locking_tx_asset_amount)?,
    when
      find_output_with_value(
        tx,
        assets.from_asset(
          policy_id,
          env.transferred_asset_name,
          redeemer.locking_tx_asset_amount,
        ),
        VerificationKey(redeemer.locking_tx_destination_payment_credential),
      )
    is {
      Some(_) -> True
      None -> False
    }?,
  }
}

validator minting_validator(
  proof_receipt_spending_script: PaymentCredential,
  phase2_asset_policy_id: PolicyId,
  stake_distribution_asset_policy_id: PolicyId,
) {
  mint(redeemer: MintingValidatorRedeemer, policy_id: PolicyId, tx: Transaction) {
    let tx_snapshot_certificate = reduced_certificate_from_redeemer(redeemer)

    and {
      locking_tx_hash_is_added_to_the_used_txs_set(
        tx,
        redeemer.locking_tx_hash,
        env.locking_txs_updater_policy_id,
        env.locking_txs_updater_asset_name,
      )?,
      certificate_is_valid_for(
        tx,
        tx_snapshot_certificate,
        redeemer,
        proof_receipt_spending_script,
        phase2_asset_policy_id,
        stake_distribution_asset_policy_id,
      )?,
      verify_transaction_is_present_in_snapshot(
        tx_snapshot_certificate,
        merkle_proof_from_redeemer(redeemer),
        redeemer,
      )?,
      locking_tx_body_hash_is_valid(redeemer, policy_id)?,
      minted_amount_and_destination_are_valid(tx, policy_id, redeemer)?,
    }
  }

  else(_) {
    fail
  }
}
