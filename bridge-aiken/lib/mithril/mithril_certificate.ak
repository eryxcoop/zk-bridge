use mithril/certificate_metadata.{CertificateMetadata}
use mithril/certificate_signature.{CertificateSignature}
use mithril/protocol_message.{ProtocolMessage}

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
  /// Message that is signed by the signers.
  ///
  /// In this repo the legacy genesis and standard certificate fixtures still
  /// model this as lowercase ASCII hex bytes, matching the existing
  /// certificate-hash / Ed25519 path. The dual-genesis Jubjub helper decodes
  /// those bytes back to the raw 32-byte digest before binding them to the
  /// Groth16 public inputs `digest_hi` / `digest_low`.
  ///
  /// aka H(MSG(p,n) || AVK(n-1))
  signed_message: ByteArray,
  /// Aggregate verification key
  /// The AVK used to sign during the current epoch
  /// aka AVK(n-2)
  aggregate_verification_key: ByteArray,
  /// Aggregate verification key for the SNARK proof system.
  /// This is the AVK used to verify Lagrange-era aggregate signatures.
  aggregate_verification_key_snark: ByteArray,
  /// Certificate signature
  signature: CertificateSignature,
}
// AVK looks like this, if we convert it from hexadecimal to string:
// {"mt_commitment":{"root":[73,74,229,250,122,226,89,37,231,245,106,183,127,3,99,177,217,65,152,135,32,67,223,35,141,51,4,125,203,38,196,212],"nr_leaves":24,"hasher":null},"total_stake":52375176365882}
