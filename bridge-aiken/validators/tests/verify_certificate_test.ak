use env
use mithril/mithril_certificate.{GenesisVerificationKey}
use mithril/verify_certificate
use tests/helpers/certificates/stake_distribution_certificates.{
  simple_dual_genesis_certificate, simple_genesis_certificate,
}
use tests/helpers/certificates/stake_distribution_negative_certificates.{
  genesis_certificate_with_incorrect_signature,
  genesis_certificate_with_incorrect_signed_message,
}
use tests/helpers/coherent_dual_genesis_fixture
use zk/jubjub_schnorr_verification.{JubjubSchnorrProof}

// The Schnorr proof is only consumed by the dual-genesis branch; the
// single-signature genesis tests pass it but never read it.
fn coherent_jubjub_schnorr_proof() -> JubjubSchnorrProof {
  JubjubSchnorrProof {
    proof: coherent_dual_genesis_fixture.proof(),
    verification_key_u: coherent_dual_genesis_fixture.verification_key_u_bytes(),
    verification_key_v: coherent_dual_genesis_fixture.verification_key_v_bytes(),
    signature_response: coherent_dual_genesis_fixture.signature_response_bytes(),
    signature_challenge: coherent_dual_genesis_fixture.signature_challenge_bytes(),
  }
}

test accepts_valid_genesis_certificate_signature() {
  verify_certificate.verify_mithril_genesis_certificate(
    simple_genesis_certificate(),
    coherent_jubjub_schnorr_proof(),
    env.genesis_verification_key,
  )
}

test rejects_genesis_certificate_with_incorrect_signature() {
  !verify_certificate.verify_mithril_genesis_certificate(
    genesis_certificate_with_incorrect_signature(),
    coherent_jubjub_schnorr_proof(),
    env.genesis_verification_key,
  )
}

test rejects_genesis_certificate_with_incorrect_signed_message() {
  !verify_certificate.verify_mithril_genesis_certificate(
    genesis_certificate_with_incorrect_signed_message(),
    coherent_jubjub_schnorr_proof(),
    env.genesis_verification_key,
  )
}

test rejects_genesis_certificate_with_incorrect_verification_key() {
  !verify_certificate.verify_mithril_genesis_certificate(
    simple_genesis_certificate(),
    coherent_jubjub_schnorr_proof(),
    GenesisVerificationKey(
      #"80497ca1068983d5cf75c655b0c7a2f1447b77910de8f331e502f9cdcd27eb2c",
    ),
  )
}

test accepts_coherent_dual_genesis_certificate_with_test_verification_key() {
  verify_certificate.verify_mithril_genesis_certificate(
    simple_dual_genesis_certificate(),
    coherent_jubjub_schnorr_proof(),
    coherent_dual_genesis_fixture.genesis_verification_key(),
  )
}
