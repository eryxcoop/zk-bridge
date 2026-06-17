// Phase 1 minting validator for the two-phase Mithril STM verifier.
//
// TX1 mints a token whose name = reduced_hash (binding the proof data).
// This token is sent to the phase2 script address with a Phase2State datum,
// creating the UTxO that TX2 will consume.

use aiken/crypto.{VerificationKeyHash}
use aiken/crypto/bls12_381/scalar.{from_bytes_little_endian}
use cardano/assets.{PolicyId, has_nft_strict}
use cardano/transaction.{InlineDatum, Output, Transaction, find_script_outputs}
use two_phase/proof_verifier_phase1.{phase1_verifier_state}
use two_phase/two_phase_types.{Phase2State}

/// Extracts the signer that will later be allowed to finalize the phase-2 transaction.
///
/// TX1 is considered well-formed only when there is exactly one extra
/// signatory, which becomes the authority stored in `Phase2State`.
pub fn phase1_signer_from(
  transaction: Transaction,
) -> Option<VerificationKeyHash> {
  when transaction.extra_signatories is {
    [phase1_signer] -> Some(phase1_signer)
    _ -> None
  }
}

/// Checks the unique output that must be created for phase 2.
///
/// The transaction must:
/// - mint exactly the expected NFT under the phase-1 policy;
/// - create exactly one output to the phase-2 script;
/// - store the expected `Phase2State` as inline datum on that output; and
/// - place the freshly minted NFT in that same output.
pub fn has_expected_phase2_output(
  transaction: Transaction,
  phase1_policy_id: PolicyId,
  phase2_policy_id: PolicyId,
  expected_state: Phase2State,
) -> Bool {
  when find_script_outputs(transaction.outputs, phase2_policy_id) is {
    [Output { datum, value, .. }] -> and {
        assets.match(value, transaction.mint, >=),
        has_nft_strict(
          transaction.mint,
          phase1_policy_id,
          expected_state.proof_state.reduced_hash,
        ),
        datum == InlineDatum(expected_state),
      }
    _ -> False
  }
}

/// Redeemer consumed by the phase-1 minting validator.
pub type Phase1Redeemer {
  proof: Data,
  i_1: ByteArray,
  i_2: ByteArray,
  phase2_policy_id: PolicyId,
  reclaim_after: Int,
}

validator phase1 {
  mint(redeemer: Phase1Redeemer, policy_id: PolicyId, transaction: Transaction) {
    when phase1_signer_from(transaction) is {
      Some(phase1_signer) ->
        // TX1 must mint the phase1 NFT and place it in the unique phase2
        // output carrying the control datum that phase2 will later use.
        has_expected_phase2_output(
          transaction,
          policy_id,
          redeemer.phase2_policy_id,
          Phase2State {
            proof_state: phase1_verifier_state(
              redeemer.proof,
              from_bytes_little_endian(redeemer.i_1),
              from_bytes_little_endian(redeemer.i_2),
            ),
            phase1_signer,
            reclaim_after: redeemer.reclaim_after,
            // For the upcoming SNARK-based Mithril era, the second public input is the
            // signed message itself, already as a 32-byte digest. We therefore bind the
            // receipt directly to `i_2` instead of to a synthetic hash of `(i_1, i_2)`.
            statement_hash: redeemer.i_2,
          },
        )

      None -> False
    }
  }

  else(_) {
    fail
  }
}
