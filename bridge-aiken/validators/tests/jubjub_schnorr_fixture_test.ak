use tests/helpers/certificates/stake_distribution_certificates.{ simple_dual_genesis_certificate }
use tests/helpers/certificates/stake_distribution_negative_certificates.{
  dual_genesis_certificate_with_incorrect_signed_message,
}
use tests/helpers/coherent_dual_genesis_fixture
use tests/helpers/jubjub_schnorr_fixture
use zk/jubjub_schnorr_verification
use zk/jubjub_schnorr_verification_vk.{jubjub_schnorr_verification_vk}

test jubjub_schnorr_vk_expects_six_public_inputs() {
  jubjub_schnorr_verification_vk().nPublic == 6
}

test jubjub_schnorr_public_inputs_match_exported_fixture() {
  jubjub_schnorr_verification.public_inputs(
    jubjub_schnorr_fixture.final_digest_hi,
    jubjub_schnorr_fixture.final_digest_low,
    jubjub_schnorr_fixture.final_verification_key_u,
    jubjub_schnorr_fixture.final_verification_key_v,
    jubjub_schnorr_fixture.final_signature_response,
    jubjub_schnorr_fixture.final_signature_challenge,
  ) == jubjub_schnorr_fixture.final_public_inputs()
}

test jubjub_schnorr_exported_proof_verifies_directly() {
  jubjub_schnorr_verification.proof_verifies(
    jubjub_schnorr_fixture.final_proof(),
    jubjub_schnorr_fixture.final_digest_hi,
    jubjub_schnorr_fixture.final_digest_low,
    jubjub_schnorr_fixture.final_verification_key_u,
    jubjub_schnorr_fixture.final_verification_key_v,
    jubjub_schnorr_fixture.final_signature_response,
    jubjub_schnorr_fixture.final_signature_challenge,
  )
}

test jubjub_signed_message_matches_exported_digest_halves() {
  let certificate = simple_dual_genesis_certificate()

  jubjub_schnorr_verification.signed_message_matches_digest_halves(
    certificate.signed_message,
    coherent_dual_genesis_fixture.digest_hi,
    coherent_dual_genesis_fixture.digest_low,
  )
}

test jubjub_genesis_schnorr_helper_rejects_wrong_signed_message_binding() {
  let certificate = dual_genesis_certificate_with_incorrect_signed_message()

  !jubjub_schnorr_verification.jubjub_genesis_schnorr_proof_verifies(
    coherent_dual_genesis_fixture.proof(),
    certificate.signed_message,
    coherent_dual_genesis_fixture.schnorr_signature_ascii_hex(),
    coherent_dual_genesis_fixture.verification_key_u,
    coherent_dual_genesis_fixture.verification_key_v,
    coherent_dual_genesis_fixture.verification_key_u_bytes(),
    coherent_dual_genesis_fixture.verification_key_v_bytes(),
    coherent_dual_genesis_fixture.signature_response_bytes(),
    coherent_dual_genesis_fixture.signature_challenge_bytes(),
  )
}

test jubjub_decimal_ascii_roundtrips_exported_digest_limb() {
  jubjub_schnorr_verification.decimal_ascii_bytes_to_int(
    coherent_dual_genesis_fixture.digest_hi_bytes(),
  ) == coherent_dual_genesis_fixture.digest_hi
}
