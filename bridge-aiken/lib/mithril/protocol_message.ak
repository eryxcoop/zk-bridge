// `ProtocolMessage` is a simplified representation of a `BTreeMap` in Rust
// In Mithril, we have the `enum ProtocolMessagePartKey` and this is the order of the possible keys for the map
// It is important to respect this order when hashing the Protocol Message
pub type ProtocolMessagePartKey {
  SnapshotDigest
  CardanoTransactionsMerkleRoot
  NextAggregateVerificationKey
  NextSnarkAggregateVerificationKey
  NextProtocolParameters
  CurrentEpoch
  LatestBlockNumber
  CardanoStakeDistributionEpoch
  CardanoStakeDistributionMerkleRoot
  CardanoDatabaseMerkleRoot
}

/// We use a list of pairs with `ProtocolMessagePartKey` as keys to represent a protocol message in Mithril.
pub type ProtocolMessage =
  Pairs<ProtocolMessagePartKey, String>
