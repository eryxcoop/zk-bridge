use aiken/collection/pairs
use aiken/primitive/bytearray
use aiken/primitive/string
use ak_381/groth16.{Proof, SnarkVerificationKey, groth_verify}
use certificate_metadata.{ProtocolParameters, hash_protocol_parameters}
use certificate_signature.{CertificateSignature}
use mithril_certificate.{
  GenesisVerificationKey, MithrilCertificate, hash_certificate,
}
use protocol_message.{
  CurrentEpoch, NextAggregateVerificationKey, NextProtocolParameters,
}
use utils.{digest_to_bytes_of_string}
use zk_verification.{empty_circuit_vk}

/// Verifies a `MithrilCertificate` whose signature is a `GenesisSignature` using a
/// given `GenesisVerificationKey`. The certificate's signature MUST be a `GenesisSignature`. 
pub fn verify_mithril_genesis_certificate(
  certificate: MithrilCertificate,
  genesis_vkey: GenesisVerificationKey,
) -> Bool {
  and {
    verify_hash_matches_content(certificate)?,
    verify_with_genesis_vkey(
      genesis_vkey,
      certificate.signed_message,
      certificate.signature,
    )?,
    verify_epoch_matches_protocol_message(certificate)?,
  }
}

/// Verifies a `MithrilCertificate` whose signature is a `MultiSignature` given another
/// `MithrilCertificate` that MUST be its parent certificate and a `MithrilProof` which MUST be
/// a valid ZK proof for the certificate. The certificate's signature MUST be a `MultiSignature`. 
pub fn verify_mithril_standard_certificate(
  certificate: MithrilCertificate,
  parent_certificate: MithrilCertificate,
  proof: Proof,
) -> Bool {
  and {
    verify_is_not_in_infinite_loop(certificate)?,
    verify_signed_message_matches_hashed_protocol_message(certificate)?,
    verify_multi_signature(
      certificate.signed_message,
      certificate.signature,
      certificate.aggregate_verification_key,
      certificate.metadata.protocol_parameters,
      proof,
    )?,
    verify_epoch_matches_protocol_message(certificate)?,
    verify_epoch_chaining(certificate, parent_certificate)?,
    verify_previous_hash_matches_previous_certificate_hash(
      certificate,
      parent_certificate,
    )?,
    verify_aggregate_verification_key_chaining(certificate, parent_certificate)?,
    verify_protocol_parameters_chaining(certificate, parent_certificate)?,
    verify_hash_matches_content(certificate)?,
  }
}

/// Verifies that the hash chain of a `MithrilCertificate` is not in an infinite cycle.
/// This is equivalent to verify that its hash does not match its parent's hash.
fn verify_is_not_in_infinite_loop(certificate: MithrilCertificate) -> Bool {
  (certificate.prev_hash != certificate.hash)?
}

/// Verifies that the hash of the content of a `MithrilCertificate` matches its hash.
/// NOTE: This is a function with a heavy cost.
fn verify_hash_matches_content(certificate: MithrilCertificate) -> Bool {
  (certificate.hash == hash_certificate(certificate))?
}

/// This function will be developed in the next milestone. It is expected to always work,
/// since the `GenesisVerificationKey` would be hardcoded in the validator for minting a
/// stake distribution asset. 
fn verify_with_genesis_vkey(
  _genesis_vkey: GenesisVerificationKey,
  _signed_message: ByteArray,
  _genesis_signature: CertificateSignature,
) -> Bool {
  True
}

/// Verifies that `certificate.signed_message` is equal to the hash of its `protocol_message`.
/// However, this is an unnecessary check, since the preimage resistance of `sha2_256` means that
/// `verify_hash_matches_content` implies this predicate.
fn verify_signed_message_matches_hashed_protocol_message(
  _certificate: MithrilCertificate,
) -> Bool {
  True
}

/// This function will be developed in the next milestone. It verifies that a ZK proof (a `MithrilProof`)
/// for a `MithrilCertificate` with a `MultiSignature` is valid, given its `signed_message`, its
/// `aggregate_verification key`, and its `protocol_parameters`. 
fn verify_multi_signature(
  _signed_message: ByteArray,
  _multi_signature: CertificateSignature,
  _aggregate_verification_key: ByteArray,
  protocol_parameters: ProtocolParameters,
  proof: Proof,
) -> Bool {
  let vk = mithril_multisignature_verification_circuit_vk()
  groth_verify(vk, proof, [protocol_parameters.m])
}

/// Verifies that the `epoch` of a `MithrilCertificate` matches the epoch indicated in its `ProtocolMessage`.
fn verify_epoch_matches_protocol_message(
  certificate: MithrilCertificate,
) -> Bool {
  expect Some(epoch) =
    pairs.get_first(certificate.protocol_message, CurrentEpoch)
  epoch == string.from_int(certificate.epoch)
}

/// Verifies that the `epoch` of a `MithrilCertificate` matches the hash chain with its parent certificate.
/// It is implemented in the fashion of Mithril's Rust implementation.
fn verify_epoch_chaining(
  certificate: MithrilCertificate,
  parent_certificate: MithrilCertificate,
) -> Bool {
  or {
    certificate.epoch == parent_certificate.epoch,
    certificate.epoch == parent_certificate.epoch + 1,
  }
}

/// Verifies that the `prev_hash` of a `MithrilCertificate` matches the hash of its parent certificate.
fn verify_previous_hash_matches_previous_certificate_hash(
  certificate: MithrilCertificate,
  parent_certificate: MithrilCertificate,
) -> Bool {
  (certificate.prev_hash == digest_to_bytes_of_string(parent_certificate.hash))?
}

/// Verifies that the `aggregate_verification_key` of a `MithrilCertificate`'s parent certificate
/// matches the `NextAggregateVerificationKey` indicated in its parent's `ProtocolMessage`.
fn verify_aggregate_verification_key_chaining(
  certificate: MithrilCertificate,
  parent_certificate: MithrilCertificate,
) -> Bool {
  if certificate.epoch == parent_certificate.epoch {
    (certificate.aggregate_verification_key == parent_certificate.aggregate_verification_key)?
  } else {
    expect Some(next_avk) =
      pairs.get_first(
        parent_certificate.protocol_message,
        NextAggregateVerificationKey,
      )
    (bytearray.from_string(next_avk) == certificate.aggregate_verification_key)?
  }
}

/// Verifies that the `protocol_parameters` of a `MithrilCertificate`'s parent certificate
/// matches the `NextProtocolParemeters` indicated in its parent's `ProtocolMessage`.
fn verify_protocol_parameters_chaining(
  certificate: MithrilCertificate,
  parent_certificate: MithrilCertificate,
) -> Bool {
  if certificate.epoch == parent_certificate.epoch {
    (certificate.metadata.protocol_parameters == parent_certificate.metadata.protocol_parameters)?
  } else {
    expect Some(next_protocol_parameters) =
      pairs.get_first(certificate.protocol_message, NextProtocolParameters)
    let protocol_parameters_hash =
      certificate.metadata.protocol_parameters
        |> hash_protocol_parameters
        |> digest_to_bytes_of_string
    (bytearray.from_string(next_protocol_parameters) == protocol_parameters_hash)?
  }
}

fn mithril_multisignature_verification_circuit_vk() -> SnarkVerificationKey {
  empty_circuit_vk()
}
