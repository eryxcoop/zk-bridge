// Phase 2 validator for the two-phase Mithril STM verifier.
//
// TX2 can do one of two things:
//
//   spend / Verify  – completes the Halo2 verification and mints the proof NFT.
//
//   spend / Recover – after the recovery deadline, lets the signer from TX1
//                     reclaim the locked UTxO, provided no minting happens.
//
// The mint policy remains coupled to the spend path by requiring that at
// least one input from this same script is consumed in the transaction.

use aiken/collection/list
use aiken/interval
use cardano/address.{PaymentCredential, Script, VerificationKey}
use cardano/assets.{PolicyId, has_nft_strict, is_zero}
use cardano/transaction.{
  InlineDatum, Output, OutputReference, Transaction, find_script_outputs,
  resolve_input,
}
use two_phase/proof_verifier_phase2.{phase2_verifier}
use two_phase/two_phase_types.{
  Phase2Redeemer, Phase2State, Recover, Verify, proof_receipt_from_phase2_state,
}

/// Checks whether the transaction consumes at least one input locked by this
/// same phase-2 script.
///
/// The mint policy uses this to ensure that minting the proof NFT is coupled to
/// a spend of the script UTxO and therefore to execution of the spend branch.
fn spends_own_script_input(
  transaction: Transaction,
  policy_id: PolicyId,
) -> Bool {
  list.any(
    transaction.inputs,
    fn(input) { input.output.address.payment_credential == Script(policy_id) },
  )
}

/// Recovers this script's policy id from the consumed script input.
///
/// In the two-phase design the script hash and the minting policy id coincide,
/// so the spend branch can recover the policy id from its own input.
fn own_policy_id(
  output_reference: OutputReference,
  transaction: Transaction,
) -> PolicyId {
  let own_output = resolve_input(transaction.inputs, output_reference)
  when own_output.address.payment_credential is {
    Script(policy_id) -> policy_id
    VerificationKey(_) -> fail
  }
}

/// Authorizes the timed recovery branch of phase 2.
///
/// Recovery is only possible once the timeout has elapsed, only by the signer
/// recorded in `Phase2State`, and only if the transaction performs no minting.
pub fn can_recover_phase2(state: Phase2State, transaction: Transaction) -> Bool {
  and {
    interval.after(state.reclaim_after)
      |> interval.includes(transaction.validity_range),
    is_zero(transaction.mint),
  }
}

/// Authorizes the phase-2 mint policy.
///
/// The minted value must be exactly the expected proof NFT, and the
/// transaction must also spend an input from this same script.
pub fn is_authorized_phase2_mint(
  redeemer: ByteArray,
  policy_id: PolicyId,
  transaction: Transaction,
) -> Bool {
  and {
    has_nft_strict(transaction.mint, policy_id, redeemer),
    spends_own_script_input(transaction, policy_id),
  }
}

/// Checks the unique proof receipt output created when phase 2 completes.
///
/// The receipt must be sent to the dummy script address, must contain the
/// phase-2 NFT, and must carry the statement hash needed to identify the
/// verified Mithril statement in another context.
pub fn has_expected_proof_receipt_output(
  transaction: Transaction,
  policy_id: PolicyId,
  state: Phase2State,
  proof_receipt_spending_script: PaymentCredential,
) -> Bool {
  when proof_receipt_spending_script is {
    Script(proof_receipt_script_hash) ->
      when
        find_script_outputs(transaction.outputs, proof_receipt_script_hash)
      is {
        [Output { datum, value, .. }] -> and {
            datum == InlineDatum(proof_receipt_from_phase2_state(state)),
            has_nft_strict(value, policy_id, state.proof_state.reduced_hash),
          }
        _ -> False
      }
    VerificationKey(_) -> False
  }
}

validator phase2(proof_receipt_spending_script: PaymentCredential) {
  spend(
    datum: Option<Phase2State>,
    redeemer: Phase2Redeemer,
    output_reference: OutputReference,
    transaction: Transaction,
  ) {
    expect Some(state) = datum
    expect list.has(transaction.extra_signatories, state.phase1_signer)
    let policy_id = own_policy_id(output_reference, transaction)

    when redeemer is {
      Verify(reduced_redeemer) -> and {
          has_nft_strict(
            transaction.mint,
            policy_id,
            state.proof_state.reduced_hash,
          ),
          has_expected_proof_receipt_output(
            transaction,
            policy_id,
            state,
            proof_receipt_spending_script,
          ),
          phase2_verifier(state.proof_state, reduced_redeemer),
        }
      Recover -> can_recover_phase2(state, transaction)
    }
  }

  mint(redeemer: ByteArray, policy_id: PolicyId, transaction: Transaction) {
    is_authorized_phase2_mint(redeemer, policy_id, transaction)
  }

  else(_) {
    fail
  }
}
