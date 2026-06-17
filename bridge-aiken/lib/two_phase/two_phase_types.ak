// Types for the two-phase Mithril STM Halo2 Multi-Open verifier.
//
// Phase1State is the proof-derived state computed in TX1.
// Phase2State is the datum consumed in TX2 and wraps Phase1State with
// recovery controls and the public-instance binding.
// ReducedRedeemer carries only the data TX2 needs to finish the
// linear block and execute the pairing check.

use aiken/crypto.{VerificationKeyHash}

/// Hash that uniquely identifies the Mithril STM public instance bound to a
/// receipt.
pub type StatementHash =
  ByteArray

/// Datum produced by TX1.
///
/// - `rhs_prefix`:   compressed G1 partial accumulator (48 bytes)
/// - `reduced_hash`: blake2b_256 of the serialised ReducedRedeemer (32 bytes)
/// - `x1`:           transcript challenge x1 (32 bytes, little-endian scalar)
/// - `x3`:           transcript challenge x3 (32 bytes, little-endian scalar)
/// - `x4`:           transcript challenge x4 (32 bytes, little-endian scalar)
/// - `v`:            precomputed blinding scalar (32 bytes, little-endian scalar)
pub type Phase1State {
  rhs_prefix: ByteArray,
  reduced_hash: ByteArray,
  x1: ByteArray,
  x3: ByteArray,
  x4: ByteArray,
  v: ByteArray,
}

/// Datum consumed by the phase-2 spending validator.
///
/// Wraps the proof-derived state with the recovery controls needed in TX2:
/// - `phase1_signer`: signer allowed to reclaim the UTxO after timeout
/// - `reclaim_after`: absolute POSIX time (ms) after which recovery is enabled
/// - `statement_hash`: Mithril signed-message digest, carried directly as the
///   second public input of the STM circuit and later certified by TX2
pub type Phase2State {
  proof_state: Phase1State,
  phase1_signer: VerificationKeyHash,
  reclaim_after: Int,
  statement_hash: StatementHash,
}

/// Datum carried by the phase-2 proof receipt output.
///
/// This lets other contexts consume the NFT together with a statement hash
/// that is bound to the Mithril signed message verified by the STM proof.
pub type ProofReceiptDatum {
  statement_hash: StatementHash,
}

pub fn phase2_state(
  proof_state: Phase1State,
  phase1_signer: VerificationKeyHash,
  reclaim_after: Int,
  statement_hash: StatementHash,
) -> Phase2State {
  Phase2State { proof_state, phase1_signer, reclaim_after, statement_hash }
}

pub fn statement_hash_from_phase2_state(state: Phase2State) -> StatementHash {
  state.statement_hash
}

pub fn proof_receipt_from_phase2_state(state: Phase2State) -> ProofReceiptDatum {
  ProofReceiptDatum { statement_hash: statement_hash_from_phase2_state(state) }
}

/// Reduced redeemer consumed by TX2.
///
/// Contains only the proof-derived G1 commitment points that are NOT
/// verification-key constants, plus the PCS witness and f-commitment.
///
/// Layout (flat tuple for minimal CBOR overhead):
///   ( vanishing_g          -- compressed G1 (set 0 suffix, computed)
///   , vanishing_rand       -- compressed G1 (set 0 suffix, from proof)
///   , a1                   -- set 1
///   , a2                   -- set 1
///   , a3                   -- set 1
///   , perm_d               -- set 1 (permutations_committed_d)
///   , lookup_1             -- set 1
///   , lookup_2             -- set 1
///   , perm_a               -- set 2
///   , perm_b               -- set 2
///   , perm_c               -- set 2
///   , perm_input_1         -- set 3
///   , perm_input_2         -- set 3
///   , f_commitment         -- PCS
///   , pi_term              -- PCS witness
///   )
pub type ReducedRedeemer {
  vanishing_g: ByteArray,
  vanishing_rand: ByteArray,
  a1: ByteArray,
  a2: ByteArray,
  a3: ByteArray,
  perm_d: ByteArray,
  lookup_1: ByteArray,
  lookup_2: ByteArray,
  perm_a: ByteArray,
  perm_b: ByteArray,
  perm_c: ByteArray,
  perm_input_1: ByteArray,
  perm_input_2: ByteArray,
  f_commitment: ByteArray,
  pi_term: ByteArray,
}

/// Phase-2 spend redeemer.
///
/// - `Verify` completes the Halo2 verification and must mint the proof NFT.
/// - `Recover` unlocks the UTxO for the signer of TX1 after the timeout.
pub type Phase2Redeemer {
  Verify(ReducedRedeemer)
  Recover
}
