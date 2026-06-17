use aiken/builtin.{append_bytearray}
use aiken/crypto.{sha2_256}
use utils.{to_be_bytes}

/// Mithril certificate metadata domain types and hashing helpers.
///
/// This module owns the shape of the metadata carried inside a certificate and
/// the exact hashing contract Mithril expects for protocol-parameter chaining.
pub type ProtocolVersion {
  ProtocolVersion(ByteArray)
}

pub type ProtocolParameters {
  /// Quorum parameter
  k: Int,
  /// Security parameter (number of lotteries)
  m: Int,
  /// f in phi(w) = 1 - (1 - f)^w, where w is the stake of a participant
  /// phi_f_fixed is a fixed decimal representation of phi_f (in Mithril)
  /// it is computed as `U8F24::from_num(self.phi_f)`. Therefore when we build a certificate
  /// in Aiken we must use the U8F24 representation, we can choose `ByteArray`
  phi_f: ByteArray,
}

pub type StakeDistributionParty {
  /// Party identifier as in the stake distribution
  party_id: ByteArray,
  /// Amount of stake owned by the party
  stake: Int,
}

pub type CertificateMetadata {
  /// Cardano network
  network: ByteArray,
  /// Protocol Version (semver)
  /// Useful to achieve backward compatibility of the certificates (including of the multi signature)
  /// part of METADATA(p,n)
  protocol_version: ProtocolVersion,
  /// Protocol parameters
  /// part of METADATA(p,n)
  protocol_parameters: ProtocolParameters,
  /// Date and time when the certificate was initiated (in Mithril it was DateTime<Utc>)
  /// Represents the time at which the single signatures registration is opened
  /// part of METADATA(p,n)
  /// In Aiken we will only save the bytes after the Mithril operations, i.e. the result of:
  /// metadata.initiated_at.timestamp_nanos_opt().unwrap_or_default().to_be_bytes()
  initiated_at: ByteArray,
  /// Date and time when the certificate was sealed (in Mithril it was DateTime<Utc>)
  /// Represents the time at which the quorum of single signatures was reached so that they were aggregated into a multi signature
  /// part of METADATA(p,n)
  /// In Aiken we will only save the bytes after the Mithril operations, i.e. the result of:
  /// metadata.sealed_at.timestamp_nanos_opt().unwrap_or_default().to_be_bytes()
  sealed_at: ByteArray,
  /// The list of the active signers with their stakes and verification keys
  /// part of METADATA(p,n)
  signers: List<StakeDistributionParty>,
}

/// Receives `ProtocolParameters` and hashes them using the same `sha2_256`
/// strategy used by Mithril.
pub fn hash_protocol_parameters(
  protocol_parameters: ProtocolParameters,
) -> ByteArray {
  protocol_parameters.k
    |> to_be_bytes
    |> append_bytearray(to_be_bytes(protocol_parameters.m))
    |> append_bytearray(protocol_parameters.phi_f)
    |> sha2_256
}
