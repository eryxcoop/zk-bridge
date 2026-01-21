use aiken/collection/pairs
use aiken/crypto.{sha2_256}
use aiken/primitive/string

// `ProtocolMessage` is a simplified representation of a `BTreeMap` in Rust
// In Mithril, we have the `enum ProtocolMessagePartKey` and this is the order of the possible keys for the map
// It is important to respect this order when hashing the Protocol Message
pub type ProtocolMessagePartKey {
  SnapshotDigest
  CardanoTransactionsMerkleRoot
  NextAggregateVerificationKey
  NextProtocolParameters
  CurrentEpoch
  LatestBlockNumber
  CardanoStakeDistributionEpoch
  CardanoStakeDistributionMerkleRoot
  CardanoDatabaseMerkleRoot
}

/// This function recieves a `ProtocolMessagePartKey` and returns the corresponding string related to
/// this key that should be appended to the input when hashing a `ProtocolMessage`.
fn pmpk_to_string(protocol_message_part_key: ProtocolMessagePartKey) -> String {
  when protocol_message_part_key is {
    SnapshotDigest -> @"snapshot_digest"
    CardanoTransactionsMerkleRoot -> @"cardano_transactions_merkle_root"
    NextAggregateVerificationKey -> @"next_aggregate_verification_key"
    NextProtocolParameters -> @"next_protocol_parameters"
    CurrentEpoch -> @"current_epoch"
    LatestBlockNumber -> @"latest_block_number"
    CardanoStakeDistributionEpoch -> @"cardano_stake_distribution_epoch"
    CardanoStakeDistributionMerkleRoot ->
      @"cardano_stake_distribution_merkle_root"
    CardanoDatabaseMerkleRoot -> @"cardano_database_merkle_root"
  }
}

/// We use a list of pairs with `ProtocolMessagePartKey` as keys to represent a protocol message in Mithril.
pub type ProtocolMessage =
  Pairs<ProtocolMessagePartKey, String>

/// Recieves a `CertificateMetadata` and hashes it using the `sha2_256` hash function in the
/// exact same fashion it is done in Mithril's Rust implementation.w
/// A precondition to achieve the correct hashing result is that the `ProtocolMessage` is
/// constructed as a list of pairs with its keys following the total ordering defined by
/// the `type ProtocolMessagePartKey`.
pub fn hash_protocol_message(protocol_message: ProtocolMessage) -> ByteArray {
  protocol_message
    |> pairs.foldr(
        @"",
        fn(k, v, result) {
          string.concat(string.concat(pmpk_to_string(k), v), result)
        },
      )
    |> string.to_bytearray
    |> sha2_256
}
