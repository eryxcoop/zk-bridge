use two_phase/two_phase_types.{StatementHash}

/// Canonical bridge-facing statement digest comparison.
///
/// The current STM flow binds the certified Mithril signed message directly to
/// the second public input, so all bridge-side "statement hash" fields are
/// mirrors of the same 32-byte digest.
pub fn matches_signed_message(
  statement_hash: StatementHash,
  signed_message: ByteArray,
) -> Bool {
  signed_message == statement_hash
}
