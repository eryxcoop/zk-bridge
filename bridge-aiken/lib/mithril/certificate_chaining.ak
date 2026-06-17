use mithril/certificate_metadata.{ProtocolParameters, hash_protocol_parameters}
use utils.{digest_to_bytes_of_string}

/// Shared Mithril certificate-chain predicates.
///
/// Both the full-certificate path and the reduced-certificate path enforce the
/// same parent/child contract. Centralizing those rules keeps the validators
/// declarative and prevents the two paths from drifting apart.
/// Checks that the child certificate's epoch is a valid successor of the
/// parent's epoch under the Mithril chaining rules.
///
/// Mithril allows two cases:
///   - the child is another certificate produced inside the same epoch; the AVK and protocol parameters must
///     therefore be unchanged.
///   - next epoch (`child == parent + 1`): the child is the first
///     certificate of the following epoch and must adopt the AVK / protocol
///     parameters that the parent advertised as "next".
pub fn certificate_epochs_chain(child_epoch: Int, parent_epoch: Int) -> Bool {
  or {
    child_epoch == parent_epoch,
    child_epoch == parent_epoch + 1,
  }
}

/// Checks that the child certificate's `prev_hash` field links back to the
/// parent certificate's hash.
///
/// Encoding: Mithril stores `prev_hash` as **lowercase ASCII hex
/// bytes** (the result of `hex::encode` in Rust), while the parent hash on
/// the bridge side is threaded around as raw digest bytes. The two are not
/// directly comparable, so the parent hash is run through
/// `digest_to_bytes_of_string` (raw bytes -> lowercase hex string -> bytes
/// of that string) before the equality check.
pub fn previous_hash_matches_parent(
  child_prev_hash: ByteArray,
  parent_hash: ByteArray,
) -> Bool {
  child_prev_hash == digest_to_bytes_of_string(parent_hash)
}

/// Checks that the SNARK aggregate verification key (AVK-SNARK) the child
/// certificate uses is the one announced by the parent, picking the right
/// announcement based on the epoch step.
///
///   - Same epoch: the child must reuse the parent's current AVK-SNARK.
///   - Next epoch (`child == parent + 1`): the child must adopt the
///     `next_aggregate_verification_key_snark` that the parent already
///     committed to in its protocol message.
///
/// This pairs with `certificate_epochs_chain`: this function trusts that
/// the caller has already constrained the epoch difference to one of those
/// two cases, so the `else` branch only runs for the legitimate next-epoch
/// case.
///
/// Note: this verifies the SNARK-side AVK only. The non-SNARK
/// `aggregate_verification_key` is chained separately at the call site (or
/// not at all in the reduced path, which only needs the SNARK form).
pub fn snark_avk_chains(
  child_epoch: Int,
  parent_epoch: Int,
  child_aggregate_verification_key_snark: ByteArray,
  parent_next_aggregate_verification_key_snark: ByteArray,
  parent_aggregate_verification_key_snark: ByteArray,
) -> Bool {
  if child_epoch == parent_epoch {
    child_aggregate_verification_key_snark == parent_aggregate_verification_key_snark
  } else {
    parent_next_aggregate_verification_key_snark == child_aggregate_verification_key_snark
  }
}

/// Checks that the child certificate's protocol parameters are consistent
/// with what the parent advertised, again branching on the epoch step as previous 
/// functions.
///
/// Why hash-of-current-vs-self-announced-next instead of compare-against-
/// parent-next: in the reduced/on-chain world the parent's "next protocol
/// parameters" is only available as the already-hashed bytes from the
/// parent's protocol message, while the child's structured parameters are
/// available in full. Reusing the child's own `next_protocol_parameters`
/// announcement (which Mithril guarantees is consistent with the parent's
/// previous announcement, by construction off-chain) gives the same chain
/// guarantee with data we actually have on-chain.
///
/// The hash uses the same `sha2_256(k || m || phi_f)` strategy as Mithril
/// (`hash_protocol_parameters`) and is converted through
/// `digest_to_bytes_of_string` for the same lowercase-ASCII-hex reason as
/// `previous_hash_matches_parent`.
pub fn protocol_parameters_chain(
  child_epoch: Int,
  parent_epoch: Int,
  child_protocol_parameters: ProtocolParameters,
  parent_protocol_parameters: ProtocolParameters,
  child_next_protocol_parameters: ByteArray,
) -> Bool {
  if child_epoch == parent_epoch {
    child_protocol_parameters == parent_protocol_parameters
  } else {
    let protocol_parameters_hash = child_protocol_parameters
      |> hash_protocol_parameters
      |> digest_to_bytes_of_string

    child_next_protocol_parameters == protocol_parameters_hash
  }
}
