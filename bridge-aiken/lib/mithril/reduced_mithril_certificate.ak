use aiken/collection/pairs
use aiken/primitive/bytearray
use aiken/primitive/string
use mithril/certificate_chaining.{
  certificate_epochs_chain, previous_hash_matches_parent,
  protocol_parameters_chain, snark_avk_chains,
}
use mithril/certificate_metadata.{ProtocolParameters}
use mithril/certificate_signature.{
  CardanoTransactions, MithrilStakeDistribution, MultiSignature,
}
use mithril/mithril_certificate.{MithrilCertificate}
use mithril/protocol_message.{
  CardanoTransactionsMerkleRoot, CurrentEpoch, NextAggregateVerificationKey,
  NextProtocolParameters, NextSnarkAggregateVerificationKey,
}
use mithril/statement_hash.{matches_signed_message}
use utils.{hex_string_to_bytes}

/// Reduced certificate state persisted on-chain for the bridge flows.
///
/// The full Mithril certificate is too bulky to keep in datums, so the bridge
/// stores only the fields needed for parent-state chaining and bridge mint
/// validation.
pub type ReducedMithrilCertificate {
  hash: ByteArray,
  prev_hash: ByteArray,
  epoch: Int,
  protocol_parameters: ProtocolParameters,
  protocol_message_next_aggregate_verification_key: ByteArray,
  protocol_message_next_aggregate_verification_key_snark: ByteArray,
  protocol_message_next_protocol_parameters: ByteArray,
  protocol_message_current_epoch: ByteArray,
  protocol_message_cardano_transactions_merkle_root: ByteArray,
  signed_message: ByteArray,
  aggregate_verification_key: ByteArray,
  aggregate_verification_key_snark: ByteArray,
  signed_entity_is_stake_distribution: Bool,
  signed_entity_epoch: Int,
}

/// Projects a full `MithrilCertificate` down to the `ReducedMithrilCertificate`
/// kept on-chain.
///
/// Two things happen here:
///
///   1. Selected `protocol_message` entries are pulled out of the protocol
///      message pairs list and lifted to top-level fields. The fields are
///      addressed by their tag (`NextAggregateVerificationKey`,
///      `NextSnarkAggregateVerificationKey`, `NextProtocolParameters`,
///      `CurrentEpoch`, `CardanoTransactionsMerkleRoot`) so the on-chain
///      consumers don't have to walk the pairs list themselves.
///      The first four are required, while `CardanoTransactionsMerkleRoot` is optional
///      (stake-distribution certificates don't carry one).
///
///   2. The signed-entity discriminant is flattened into two fields
///      (`signed_entity_is_stake_distribution`, `signed_entity_epoch`) so the
///      validators can branch on it without re-decoding the signature.
///      Anything other than `MithrilStakeDistribution` /
///      `CardanoTransactions` collapses to `(False, 0)`.
///
/// Some message bytes are stored as raw UTF-8 (`bytearray.from_string`) while
/// the merkle-root field is stored as decoded hex (`hex_string_to_bytes`).
/// That distinction is intentional: the merkle root is later compared against
/// the public input fed into the Groth16 snapshot-membership verifier, which
/// expects raw bytes, whereas the other fields are compared as ASCII against
/// the certificate's `signed_message`.
pub fn reduced_mithril_certificate_from_certificate(
  certificate: MithrilCertificate,
) -> ReducedMithrilCertificate {
  expect Some(protocol_message_next_aggregate_verification_key) = pairs.get_first(
    certificate.protocol_message,
    NextAggregateVerificationKey,
  )
  expect Some(protocol_message_next_aggregate_verification_key_snark) = pairs.get_first(
    certificate.protocol_message,
    NextSnarkAggregateVerificationKey,
  )
  expect Some(protocol_message_next_protocol_parameters) = pairs.get_first(
    certificate.protocol_message,
    NextProtocolParameters,
  )
  expect Some(protocol_message_current_epoch) = pairs.get_first(
    certificate.protocol_message,
    CurrentEpoch,
  )
  let protocol_message_cardano_transactions_merkle_root = when
    pairs.get_first(certificate.protocol_message, CardanoTransactionsMerkleRoot)
  is {
    Some(root) -> root
    None -> @""
  }

  let (signed_entity_is_stake_distribution, signed_entity_epoch) = when
    certificate.signature
  is {
    MultiSignature { signed_entity_type, .. } ->
      when signed_entity_type is {
        MithrilStakeDistribution { epoch } -> (True, epoch)
        CardanoTransactions { epoch, .. } -> (False, epoch)
        _ -> (False, 0)
      }
    _ -> (False, 0)
  }

  ReducedMithrilCertificate {
    hash: certificate.hash,
    prev_hash: certificate.prev_hash,
    epoch: certificate.epoch,
    protocol_parameters: certificate.metadata.protocol_parameters,
    protocol_message_next_aggregate_verification_key: bytearray.from_string(
      protocol_message_next_aggregate_verification_key,
    ),
    protocol_message_next_aggregate_verification_key_snark: bytearray.from_string(
      protocol_message_next_aggregate_verification_key_snark,
    ),
    protocol_message_next_protocol_parameters: bytearray.from_string(
      protocol_message_next_protocol_parameters,
    ),
    protocol_message_current_epoch: bytearray.from_string(
      protocol_message_current_epoch,
    ),
    protocol_message_cardano_transactions_merkle_root: hex_string_to_bytes(
      protocol_message_cardano_transactions_merkle_root,
    ),
    signed_message: certificate.signed_message,
    aggregate_verification_key: certificate.aggregate_verification_key,
    aggregate_verification_key_snark: certificate.aggregate_verification_key_snark,
    signed_entity_is_stake_distribution,
    signed_entity_epoch,
  }
}

/// Verifies that a child `ReducedMithrilCertificate` is a valid successor of
/// a previously-trusted parent state and that it signs the expected
/// `statement_hash`.
///
/// Returns `True` only if every predicate above holds.
pub fn verify_reduced_mithril_certificate_against_parent_state(
  certificate: ReducedMithrilCertificate,
  parent_hash: ByteArray,
  parent_epoch: Int,
  parent_protocol_parameters: ProtocolParameters,
  parent_next_aggregate_verification_key_snark: ByteArray,
  parent_aggregate_verification_key_snark: ByteArray,
  statement_hash: ByteArray,
) -> Bool {
  and {
    // a certificate cannot point at itself as parent.
    (certificate.prev_hash != certificate.hash)?,
    // The certificate's `signed_message` is the Mithril STM that was proved
    matches_signed_message(statement_hash, certificate.signed_message)?,
    // The protocol message's declared epoch is consistent with the certificate's epoch
    // field. The comparison is done as ASCII bytes because the protocol
    // message stores epochs as decimal strings.
    (certificate.protocol_message_current_epoch == bytearray.from_string(
      string.from_int(certificate.epoch),
    ))?,
    certificate_epochs_chain(certificate.epoch, parent_epoch)?,
    previous_hash_matches_parent(certificate.prev_hash, parent_hash)?,
    snark_avk_chains(
      certificate.epoch,
      parent_epoch,
      certificate.aggregate_verification_key_snark,
      parent_next_aggregate_verification_key_snark,
      parent_aggregate_verification_key_snark,
    )?,
    protocol_parameters_chain(
      certificate.epoch,
      parent_epoch,
      certificate.protocol_parameters,
      parent_protocol_parameters,
      certificate.protocol_message_next_protocol_parameters,
    )?,
  }
}
