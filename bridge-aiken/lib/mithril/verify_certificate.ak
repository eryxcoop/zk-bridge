use aiken/collection/pairs
use aiken/crypto
use aiken/primitive/bytearray
use aiken/primitive/string
use env
use mithril/certificate_chaining.{
  certificate_epochs_chain, previous_hash_matches_parent,
  protocol_parameters_chain, snark_avk_chains,
}
use mithril/certificate_signature.{GenesisDualSignature, GenesisSignature}
use mithril/mithril_certificate.{GenesisVerificationKey, MithrilCertificate}
use mithril/protocol_message.{
  CurrentEpoch, NextProtocolParameters, NextSnarkAggregateVerificationKey,
}
use mithril/statement_hash.{matches_signed_message}
use utils.{hex_string_to_bytes}
use zk/jubjub_schnorr_verification.{JubjubSchnorrProof}

/// Verification entry points for full Mithril certificates.
///
/// Verifies a `MithrilCertificate` whose signature is a `GenesisSignature` using a
/// given `GenesisVerificationKey`. The certificate's signature MUST be a `GenesisSignature`. 
pub fn verify_mithril_genesis_certificate(
  certificate: MithrilCertificate,
  jubjub_schnorr_proof: JubjubSchnorrProof,
  genesis_vkey: GenesisVerificationKey,
) -> Bool {
  and {
    verify_with_genesis_vkey(genesis_vkey, certificate, jubjub_schnorr_proof)?,
    verify_epoch_matches_protocol_message(certificate)?,
  }
}

/// Verifies a `MithrilCertificate` with a `MultiSignature` by checking that the
/// certificate is chained correctly and that its `signed_message` matches the
/// statement hash already proven by the two-phase verifier.
pub fn verify_mithril_standard_certificate(
  certificate: MithrilCertificate,
  parent_certificate: MithrilCertificate,
  statement_hash: ByteArray,
) -> Bool {
  and {
    verify_is_not_in_infinite_loop(certificate)?,
    verify_statement_hash(certificate, statement_hash)?,
    verify_epoch_matches_protocol_message(certificate)?,
    verify_epoch_chaining(certificate, parent_certificate)?,
    verify_previous_hash_matches_previous_certificate_hash(
      certificate,
      parent_certificate,
    )?,
    verify_aggregate_verification_key_chaining(certificate, parent_certificate)?,
    verify_protocol_parameters_chaining(certificate, parent_certificate)?,
  }
}

/// Verifies that the hash chain of a `MithrilCertificate` is not in an infinite cycle.
/// This is equivalent to verify that its hash does not match its parent's hash.
fn verify_is_not_in_infinite_loop(certificate: MithrilCertificate) -> Bool {
  (certificate.prev_hash != certificate.hash)?
}

fn verify_with_genesis_vkey(
  genesis_vkey: GenesisVerificationKey,
  certificate: MithrilCertificate,
  jubjub_schnorr_proof: JubjubSchnorrProof,
) -> Bool {
  let signed_message = certificate.signed_message
  let GenesisVerificationKey(verification_key) = genesis_vkey

  when certificate.signature is {
    GenesisSignature { signature } ->
      crypto.verify_ed25519_signature(
        verification_key,
        signed_message,
        hex_string_to_bytes(bytearray.to_string(signature)),
      )
    GenesisDualSignature { ed25519_signature, schnorr_signature } -> and {
        crypto.verify_ed25519_signature(
          verification_key,
          signed_message,
          hex_string_to_bytes(bytearray.to_string(ed25519_signature)),
        )?,
        verify_dual_genesis_signature_against_groth16(
          signed_message,
          schnorr_signature,
          jubjub_schnorr_proof,
        )?,
      }
    _ -> False
  }
}

/// Verifies the Groth16 proof attesting the dual-genesis JubJub Schnorr
/// signature over `signed_message`, binding it to the `schnorr_signature`
/// carried in the certificate's `GenesisDualSignature`.
fn verify_dual_genesis_signature_against_groth16(
  signed_message: ByteArray,
  schnorr_signature: ByteArray,
  jubjub_schnorr_proof: JubjubSchnorrProof,
) -> Bool {
  let JubjubSchnorrProof {
    proof,
    verification_key_u,
    verification_key_v,
    signature_response,
    signature_challenge,
  } = jubjub_schnorr_proof

  jubjub_schnorr_verification.jubjub_genesis_schnorr_proof_verifies(
    proof,
    signed_message,
    schnorr_signature,
    env.genesis_schnorr_verification_key_u,
    env.genesis_schnorr_verification_key_v,
    verification_key_u,
    verification_key_v,
    signature_response,
    signature_challenge,
  )
}

/// Verifies that a phase-2 proof receipt is bound to the exact certificate
/// message that Mithril expects to be certified.
fn verify_statement_hash(
  certificate: MithrilCertificate,
  statement_hash: ByteArray,
) -> Bool {
  matches_signed_message(statement_hash, certificate.signed_message)
}

/// Verifies that the `epoch` of a `MithrilCertificate` matches the epoch indicated in its `ProtocolMessage`.
pub fn verify_epoch_matches_protocol_message(
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
  certificate_epochs_chain(certificate.epoch, parent_certificate.epoch)
}

/// Verifies that the `prev_hash` of a `MithrilCertificate` matches the hash of its parent certificate.
fn verify_previous_hash_matches_previous_certificate_hash(
  certificate: MithrilCertificate,
  parent_certificate: MithrilCertificate,
) -> Bool {
  previous_hash_matches_parent(certificate.prev_hash, parent_certificate.hash)
}

/// Verifies that the SNARK aggregate verification key of a
/// `MithrilCertificate`'s parent certificate matches the
/// `NextSnarkAggregateVerificationKey` indicated in its parent's
/// `ProtocolMessage`.
fn verify_aggregate_verification_key_chaining(
  certificate: MithrilCertificate,
  parent_certificate: MithrilCertificate,
) -> Bool {
  expect Some(next_snark_avk) =
    pairs.get_first(
      parent_certificate.protocol_message,
      NextSnarkAggregateVerificationKey,
    )

  snark_avk_chains(
    certificate.epoch,
    parent_certificate.epoch,
    certificate.aggregate_verification_key_snark,
    bytearray.from_string(next_snark_avk),
    parent_certificate.aggregate_verification_key_snark,
  )
}

/// Verifies that the `protocol_parameters` of a `MithrilCertificate`'s parent certificate
/// matches the `NextProtocolParemeters` indicated in its parent's `ProtocolMessage`.
fn verify_protocol_parameters_chaining(
  certificate: MithrilCertificate,
  parent_certificate: MithrilCertificate,
) -> Bool {
  expect Some(next_protocol_parameters) =
    pairs.get_first(certificate.protocol_message, NextProtocolParameters)

  protocol_parameters_chain(
    certificate.epoch,
    parent_certificate.epoch,
    certificate.metadata.protocol_parameters,
    parent_certificate.metadata.protocol_parameters,
    bytearray.from_string(next_protocol_parameters),
  )
}
