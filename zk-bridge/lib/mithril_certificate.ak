use aiken/builtin.{append_bytearray}
use aiken/crypto.{sha2_256}
use certificate_metadata.{CertificateMetadata, hash_certificate_metadata}
use certificate_signature.{
  CertificateSignature, GenesisSignature, MultiSignature,
  serialize_signed_entity_type,
}
use protocol_message.{ProtocolMessage, hash_protocol_message}
use utils.{digest_to_bytes_of_string, to_be_bytes}

pub type GenesisVerificationKey {
  GenesisVerificationKey(ByteArray)
}

pub type MithrilCertificate {
  /// Hash of the current certificate
  /// Computed from the other fields of the certificate
  /// aka H(Cp,n))
  hash: ByteArray,
  /// Hash of the previous certificate in the chain
  /// This is either the hash of the first certificate of the epoch in the chain
  /// Or the first certificate of the previous epoch in the chain (if the certificate is the first of its epoch)
  /// aka H(FC(n))
  /// It is not null only if the certificate is not a genesis certificate
  prev_hash: ByteArray,
  /// Cardano chain epoch number
  epoch: Int,
  /// Certificate metadata (this is necessary for doing the multisignature verification)
  /// aka METADATA(p,n)
  metadata: CertificateMetadata,
  /// Structured message that is used to create the signed message
  /// aka MSG(p,n) U AVK(n-1)
  protocol_message: ProtocolMessage,
  /// Message that is signed by the signers
  /// aka H(MSG(p,n) || AVK(n-1))
  signed_message: ByteArray,
  /// Aggregate verification key
  /// The AVK used to sign during the current epoch
  /// aka AVK(n-2)
  aggregate_verification_key: ByteArray,
  /// Certificate signature
  signature: CertificateSignature,
}

// AVK looks like this, if we convert it from hexadecimal to string:
// {"mt_commitment":{"root":[73,74,229,250,122,226,89,37,231,245,106,183,127,3,99,177,217,65,152,135,32,67,223,35,141,51,4,125,203,38,196,212],"nr_leaves":24,"hasher":null},"total_stake":52375176365882}

/// Recieves a `MithrilCertificate` and hashes it using the `sha2_256` hash function in the
/// exact same fashion it is done in Mithril's Rust implementation.
/// We observe that the algorithm is slightly different for a certificate with a `GenesisSignature` than
/// for a certificate with a `MultiSignature`.
/// A precondition to achieve the correct hashing result is that `certificate.metadata.protocol_message`
/// is constructed as a list of pairs with its keys following the total ordering defined by
/// the `type ProtocolMessagePartKey`.
pub fn hash_certificate(certificate: MithrilCertificate) -> ByteArray {
  let metadata_hash_bytes =
    certificate.metadata
      |> hash_certificate_metadata
      |> digest_to_bytes_of_string
  let protocol_message_hash_bytes =
    certificate.protocol_message
      |> hash_protocol_message
      |> digest_to_bytes_of_string
  let partial_bytearray =
    certificate.prev_hash
      |> append_bytearray(to_be_bytes(certificate.epoch))
      |> append_bytearray(metadata_hash_bytes)
      |> append_bytearray(protocol_message_hash_bytes)
      // `certificate.signed_message` should also be equal to `protocol_message_hash_bytes`
      |> append_bytearray(certificate.signed_message)
      |> append_bytearray(certificate.aggregate_verification_key)
  when certificate.signature is {
    MultiSignature { signed_entity_type, signature } ->
      partial_bytearray
        |> append_bytearray(serialize_signed_entity_type(signed_entity_type))
        |> append_bytearray(signature)
        |> sha2_256
    GenesisSignature { signature } ->
      partial_bytearray
        |> append_bytearray(signature)
        |> sha2_256
  }
}
