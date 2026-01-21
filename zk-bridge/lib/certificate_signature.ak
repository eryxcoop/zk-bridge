use aiken/builtin.{append_bytearray}
use utils.{to_be_bytes}

/// Each `MithrilCertificate` must have a `SignedEntityType` in its signature. It is the entity
/// that defines the purpose of the certificate.
/// Only `MultiSignature` certificates have a `SignedEntityType`.
pub type SignedEntityType {
  /// Mithril stake distribution
  MithrilStakeDistribution { epoch: Int }
  /// Cardano Stake Distribution
  CardanoStakeDistribution { epoch: Int }
  /// Full Cardano Immutable Files
  CardanoImmutableFilesFull { epoch: Int, immutable_file_number: Int }
  /// Full Cardano Immutable Files
  CardanoDatabase { epoch: Int, immutable_file_number: Int }
  /// Cardano Transactions
  CardanoTransactions { epoch: Int, block_number: Int }
}

/// This function recieves a `SignedEntityType` and returns the corresponding `ByteArray`
/// related to it that should be appended to the input when hashing a `MithrilCertificate`.
pub fn serialize_signed_entity_type(
  signed_entity_type: SignedEntityType,
) -> ByteArray {
  when signed_entity_type is {
    MithrilStakeDistribution { epoch } -> to_be_bytes(epoch)
    CardanoStakeDistribution { epoch } -> to_be_bytes(epoch)
    CardanoImmutableFilesFull { epoch, immutable_file_number } ->
      append_bytearray(to_be_bytes(epoch), to_be_bytes(immutable_file_number))
    CardanoDatabase { epoch, immutable_file_number } ->
      append_bytearray(to_be_bytes(epoch), to_be_bytes(immutable_file_number))
    CardanoTransactions { epoch, block_number } ->
      append_bytearray(to_be_bytes(epoch), to_be_bytes(block_number))
  }
}

// fn signed_entity_type_index(signed_entity_type: SignedEntityType) -> Int {
//   when signed_entity_type is {
//     MithrilStakeDistribution {..} -> 0
//     CardanoStakeDistribution {..} -> 1
//     CardanoImmutableFilesFull {..} -> 2
//     CardanoTransactions {..} -> 3
//     CardanoDatabase {..} -> 4
//   }
// } 

pub type CertificateSignature {
  /// Every certificate which is not a genesis certificate has a `MultiSignature
  /// and includes a `SignedEntityType`.
  MultiSignature { signed_entity_type: SignedEntityType, signature: ByteArray }
  /// The `GenesisSignature` is the signature used for genesis certificate, which can be verified
  /// using Mithril's `GenesisVerificationKey`.
  GenesisSignature { signature: ByteArray }
}
