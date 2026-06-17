use aiken/collection/list
use cardano/address.{Credential}
use cardano/assets.{PolicyId, has_any_nft}
use cardano/transaction.{InlineDatum, Input, Transaction}
use two_phase/two_phase_types.{ProofReceiptDatum}

/// Finds the phase-2 proof receipt consumed by a transaction.
///
/// The receipt NFT asset name is the reduced redeemer hash produced by phase 1,
/// so callers can only know the script credential and policy id statically.
pub fn find_phase2_input(
  tx: Transaction,
  proof_receipt_spending_script: Credential,
  phase2_asset_policy_id: PolicyId,
) -> Option<Input> {
  list.find(
    tx.inputs,
    fn(input) {
      and {
        input.output.address.payment_credential == proof_receipt_spending_script,
        has_any_nft(input.output.value, phase2_asset_policy_id),
      }
    },
  )
}

pub fn statement_hash(
  tx: Transaction,
  proof_receipt_spending_script: Credential,
  phase2_asset_policy_id: PolicyId,
) -> Option<ByteArray> {
  when
    find_phase2_input(tx, proof_receipt_spending_script, phase2_asset_policy_id)
  is {
    Some(receipt_input) ->
      when receipt_input.output.datum is {
        InlineDatum(raw) ->
          if raw is ProofReceiptDatum { statement_hash }: ProofReceiptDatum {
            Some(statement_hash)
          } else {
            None
          }
        _ -> None
      }
    None -> None
  }
}

pub fn has_input(tx: Transaction, phase2_asset_policy_id: PolicyId) -> Bool {
  list.any(
    tx.inputs,
    fn(input) { has_any_nft(input.output.value, phase2_asset_policy_id) },
  )
}
