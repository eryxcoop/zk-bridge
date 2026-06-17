use aiken/builtin.{append_bytearray}
use aiken/collection/list
use aiken/crypto.{sha2_256}
use utils.{digest_to_bytes_of_string, to_be_bytes}

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

/// Recieves a `CertificateMetadata` and hashes it using the `sha2_256` hash function in the
/// exact same fashion it is done in Mithril's Rust implementation.
/// A precondition to achieve the correct hashing result is that `metadata.protocol_message` is
/// constructed as a list of pairs with its keys following the total ordering defined by
/// the `type ProtocolMessagePartKey`.
pub fn hash_certificate_metadata(metadata: CertificateMetadata) -> ByteArray {
  let ProtocolVersion(protocol_version) = metadata.protocol_version
  let protocol_parameters_hash_hex_string =
    metadata.protocol_parameters
      |> hash_protocol_parameters
      |> digest_to_bytes_of_string
  let signers_bytes: ByteArray =
    metadata.signers
      |> list.map(hash_stake_distribution_party)
      |> list.map(digest_to_bytes_of_string)
      |> list.foldr(#"", append_bytearray)

  metadata.network
    |> append_bytearray(protocol_version)
    |> append_bytearray(protocol_parameters_hash_hex_string)
    |> append_bytearray(metadata.initiated_at)
    |> append_bytearray(metadata.sealed_at)
    |> append_bytearray(signers_bytes)
    |> sha2_256
}

/// Recieves a `CertificateMetadata` and hashes it using the `sha2_256` hash function in the
/// exact same fashion it is done in Mithril's Rust implementation.
pub fn hash_protocol_parameters(
  protocol_parameters: ProtocolParameters,
) -> ByteArray {
  protocol_parameters.k
    |> to_be_bytes
    |> append_bytearray(to_be_bytes(protocol_parameters.m))
    |> append_bytearray(protocol_parameters.phi_f)
    |> sha2_256
}

/// Recieves a `StakeDistributionParty` and hashes it using the `sha2_256` hash function in the
/// exact same fashion it is done in Mithril's Rust implementation.
pub fn hash_stake_distribution_party(sdp: StakeDistributionParty) -> ByteArray {
  sdp.party_id
    |> append_bytearray(to_be_bytes(sdp.stake))
    |> sha2_256
}
