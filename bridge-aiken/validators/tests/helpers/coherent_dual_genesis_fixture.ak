use aiken/primitive/bytearray
use aiken/primitive/string
use ak_381/groth16.{Proof}
use mithril/mithril_certificate.{GenesisVerificationKey}
use utils.{digest_to_bytes_of_string}
use zk/verification.{Single, ZKInputType}

/// Coherent dual-genesis test fixture derived from Mithril test-only primitives.
///
/// Provenance:
/// - `input-output-hk/mithril`
/// - branch `jpraynaud/3145-snark-friendly-genesis-certificate`
/// - Ed25519 half:
///   - `GenesisEd25519Signer::create_deterministic_signer()`
///   - signing `signed_message.as_bytes()`
/// - Schnorr half:
///   - `GenesisSchnorrSigner::create_deterministic_signer()`
///   - `sign_standard([digest_to_field_element(sha256([0u8; 32]))], ChaCha20Rng([0u8; 32]))`
/// - Groth16 proof:
///   - `circuit_jubjub_schnorr_verification`
///   - witness built from the same Mithril deterministic Schnorr signature
///
/// This fixture is intentionally test-only. It is coherent for the current
/// bridge-side experimental checks:
/// - Ed25519 verifies against `signed_message`
/// - Jubjub Schnorr proof verifies against the same digest-derived message base
/// - response/challenge halves match the embedded Schnorr signature
pub const signed_message_raw =
  #"66687aadf862bd776c8fc18b8e9f8e20089714856ee233b3902a591d0d5f2925"

pub const ed25519_signature_raw =
  #"420aaa62fd1527e1d5741022b2212b0732e47bb21b95340957c23041d43f221c53bc696c960435855d7d4c22c8b4785af6f4317d8ee0f6d9fb17bfad002acc02"

pub const schnorr_signature_raw =
  #"73356412f1e4f469b2a6e3f41aaba7df0d5ea3609f20e1c8d8fd302dbc377c040552ae9dc3059c6d122931f0682bc9f1920c9457a34058e40bed1e2dd8c64941"

pub const ed25519_verification_key_raw =
  #"20fdbac9b10b7587bba7b5bc163bce69e796d71e4ed44c10fcb4488689f7a144"

pub const digest_hi = 136123742680664453477343918734746553888
pub const digest_low = 11418277011772585854330833085247990053

pub const message_base =
  16808672146709759238327133555736750089977066230599028589193936481731504400486

pub const verification_key_u =
  28153324423867457666386337918486746564366670615804845649025564287389474821818

pub const verification_key_v =
  19834851423795617621281065444719196780261659977294753884839631378592271643792

pub const signature_response =
  2028725099643839211567864736665210621086068885113628619301333265390370043251

pub const signature_challenge =
  29530687367518057264722346418844753825312377469230878509046554206052968976901

fn decimal_ascii_bytes(value: Int) -> ByteArray {
  bytearray.from_string(string.from_int(value))
}

pub fn genesis_verification_key() -> GenesisVerificationKey {
  GenesisVerificationKey(ed25519_verification_key_raw)
}

pub fn schnorr_signature_ascii_hex() -> ByteArray {
  digest_to_bytes_of_string(schnorr_signature_raw)
}

pub fn ed25519_signature_ascii_hex() -> ByteArray {
  digest_to_bytes_of_string(ed25519_signature_raw)
}

pub fn signed_message_ascii_hex() -> ByteArray {
  digest_to_bytes_of_string(signed_message_raw)
}

pub fn proof() -> Proof {
  Proof {
    piA: #"af458b5ab6274976aabe5fd7c0895a764788a745a0d5d1e84508fa69d23eaab9baf3cb8d448fce2deee39ed9dbcce7be",
    piB: #"954538cfb6d6847cd82ccc604939e3455086b3b13d2ce9ae47baf72fc88b2644f332a3bbaf471f1f94aeeb4bf88da4510bca7d4cdf9de3eb21e6a0e815b762ac033ba08ad0978831d6550094312cf05736899e05a2c11b7c9fa33a3da44a148f",
    piC: #"8387c97efd49e9a76c035b02417c8b3f5f07d5bf16277ecd57c27c7c043082547095082d12309d9380782805887689b2",
  }
}

pub fn public_inputs() -> List<ZKInputType> {
  [
    Single(digest_hi),
    Single(digest_low),
    Single(verification_key_u),
    Single(verification_key_v),
    Single(signature_response),
    Single(signature_challenge),
  ]
}

pub fn digest_hi_bytes() -> ByteArray {
  decimal_ascii_bytes(digest_hi)
}

pub fn digest_low_bytes() -> ByteArray {
  decimal_ascii_bytes(digest_low)
}

pub fn verification_key_u_bytes() -> ByteArray {
  decimal_ascii_bytes(verification_key_u)
}

pub fn verification_key_v_bytes() -> ByteArray {
  decimal_ascii_bytes(verification_key_v)
}

pub fn signature_response_bytes() -> ByteArray {
  decimal_ascii_bytes(signature_response)
}

pub fn signature_challenge_bytes() -> ByteArray {
  decimal_ascii_bytes(signature_challenge)
}
