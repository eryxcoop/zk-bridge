use aiken/primitive/bytearray
use aiken/primitive/string
use ak_381/groth16.{Proof}
use utils.{hex_string_to_bytes}
use zk/jubjub_schnorr_verification_vk.{jubjub_schnorr_verification_vk}
use zk/verification.{Single, ZKInputType, zk_verify}

/// Prover-supplied data attesting a JubJub Schnorr signature via Groth16: the
/// proof plus the public inputs of the dual-genesis circuit (the signer's
/// verification key `u`/`v` and the signature's `response`/`challenge`, all as
/// ASCII-decimal `ByteArray`s — see `jubjub_genesis_schnorr_proof_verifies`).
pub type JubjubSchnorrProof {
  proof: Proof,
  verification_key_u: ByteArray,
  verification_key_v: ByteArray,
  signature_response: ByteArray,
  signature_challenge: ByteArray,
}

pub fn decimal_ascii_bytes(value: Int) -> ByteArray {
  bytearray.from_string(string.from_int(value))
}

pub fn public_inputs(
  digest_hi: Int,
  digest_low: Int,
  verification_key_u: Int,
  verification_key_v: Int,
  signature_response: Int,
  signature_challenge: Int,
) -> List<ZKInputType> {
  [
    Single(digest_hi),
    Single(digest_low),
    Single(verification_key_u),
    Single(verification_key_v),
    Single(signature_response),
    Single(signature_challenge),
  ]
}

pub fn proof_verifies(
  proof: Proof,
  digest_hi: Int,
  digest_low: Int,
  verification_key_u: Int,
  verification_key_v: Int,
  signature_response: Int,
  signature_challenge: Int,
) -> Bool {
  zk_verify(
    proof,
    public_inputs(
      digest_hi,
      digest_low,
      verification_key_u,
      verification_key_v,
      signature_response,
      signature_challenge,
    ),
    jubjub_schnorr_verification_vk(),
  )
}

fn decimal_ascii_digit_to_int(byte: Int) -> Int {
  if byte >= 48 && byte <= 57 {
    byte - 48
  } else {
    fail
  }
}

pub fn decimal_ascii_bytes_to_int(raw_ascii: ByteArray) -> Int {
  if bytearray.length(raw_ascii) == 0 {
    fail
  } else {
    decimal_ascii_bytes_to_int_loop(raw_ascii, 0, 0)
  }
}

fn decimal_ascii_bytes_to_int_loop(
  raw_ascii: ByteArray,
  cursor: Int,
  acc: Int,
) -> Int {
  if cursor == bytearray.length(raw_ascii) {
    acc
  } else {
    decimal_ascii_bytes_to_int_loop(
      raw_ascii,
      cursor + 1,
      acc * 10 + decimal_ascii_digit_to_int(bytearray.at(raw_ascii, cursor)),
    )
  }
}

fn big_endian_bytes_to_int(bytes: ByteArray) -> Int {
  big_endian_bytes_to_int_loop(bytes, 0, 0)
}

fn big_endian_bytes_to_int_loop(
  bytes: ByteArray,
  cursor: Int,
  acc: Int,
) -> Int {
  if cursor == bytearray.length(bytes) {
    acc
  } else {
    big_endian_bytes_to_int_loop(
      bytes,
      cursor + 1,
      acc * 256 + bytearray.at(bytes, cursor),
    )
  }
}

fn little_endian_bytes_to_int(bytes: ByteArray) -> Int {
  little_endian_bytes_to_int_loop(bytes, 0, 1, 0)
}

fn little_endian_bytes_to_int_loop(
  bytes: ByteArray,
  cursor: Int,
  multiplier: Int,
  acc: Int,
) -> Int {
  if cursor == bytearray.length(bytes) {
    acc
  } else {
    little_endian_bytes_to_int_loop(
      bytes,
      cursor + 1,
      multiplier * 256,
      acc + bytearray.at(bytes, cursor) * multiplier,
    )
  }
}

pub fn signed_message_matches_digest_halves(
  signed_message_ascii_hex: ByteArray,
  actual_digest_hi: Int,
  actual_digest_low: Int,
) -> Bool {
  let raw_signed_message = hex_string_to_bytes(
    bytearray.to_string(signed_message_ascii_hex),
  )

  if bytearray.length(raw_signed_message) != 32 {
    False
  } else {
    and {
      actual_digest_hi == big_endian_bytes_to_int(
        bytearray.take(raw_signed_message, 16),
      ),
      actual_digest_low == big_endian_bytes_to_int(
        bytearray.drop(raw_signed_message, 16),
      ),
    }
  }
}

pub fn signature_matches_public_inputs(
  signature_ascii_hex: ByteArray,
  expected_verification_key_u: Int,
  expected_verification_key_v: Int,
  actual_verification_key_u: Int,
  actual_verification_key_v: Int,
  actual_signature_response: Int,
  actual_signature_challenge: Int,
) -> Bool {
  let raw_signature = hex_string_to_bytes(
    bytearray.to_string(signature_ascii_hex),
  )

  if bytearray.length(raw_signature) != 64 {
    False
  } else {
    and {
      actual_verification_key_u == expected_verification_key_u,
      actual_verification_key_v == expected_verification_key_v,
      actual_signature_response == little_endian_bytes_to_int(
        bytearray.take(raw_signature, 32),
      ),
      actual_signature_challenge == little_endian_bytes_to_int(
        bytearray.drop(raw_signature, 32),
      ),
    }
  }
}

/// Verifies the experimental dual-genesis Jubjub Schnorr proof.
///
/// Public-input transport split:
/// - `digest_hi` / `digest_low` are *not* passed in from the redeemer anymore.
///   They are reconstructed directly from `signed_message_ascii_hex`, which is
///   already the canonical 32-byte certificate digest encoded as lowercase
///   ASCII hex.
/// - `verification_key_u`, `verification_key_v`, `signature_response`, and
///   `signature_challenge` still arrive from the redeemer as ASCII-decimal
///   `ByteArray`s and must be converted back to on-chain `Int`s here.
///
/// The reason for that asymmetry is operational rather than cryptographic:
/// Tx3/cshell historically narrowed runtime integer arguments to `i128`, which
/// broke these ~250-bit Jubjub public inputs. Encoding them as decimal bytes
/// avoided that runtime boundary issue while keeping the on-chain verifier
/// unchanged.
pub fn jubjub_genesis_schnorr_proof_verifies(
  proof: Proof,
  signed_message_ascii_hex: ByteArray,
  signature_ascii_hex: ByteArray,
  expected_verification_key_u: Int,
  expected_verification_key_v: Int,
  verification_key_u_ascii_decimal: ByteArray,
  verification_key_v_ascii_decimal: ByteArray,
  signature_response_ascii_decimal: ByteArray,
  signature_challenge_ascii_decimal: ByteArray,
) -> Bool {
  let verification_key_u = decimal_ascii_bytes_to_int(
    verification_key_u_ascii_decimal,
  )
  let verification_key_v = decimal_ascii_bytes_to_int(
    verification_key_v_ascii_decimal,
  )
  let signature_response = decimal_ascii_bytes_to_int(
    signature_response_ascii_decimal,
  )
  let signature_challenge = decimal_ascii_bytes_to_int(
    signature_challenge_ascii_decimal,
  )
  let raw_signed_message = hex_string_to_bytes(
    bytearray.to_string(signed_message_ascii_hex),
  )

  if bytearray.length(raw_signed_message) != 32 {
    False
  } else {
    let digest_hi = big_endian_bytes_to_int(bytearray.take(raw_signed_message, 16))
    let digest_low = big_endian_bytes_to_int(bytearray.drop(raw_signed_message, 16))

    and {
      proof_verifies(
        proof,
        digest_hi,
        digest_low,
        verification_key_u,
        verification_key_v,
        signature_response,
        signature_challenge,
      )?,
      signature_matches_public_inputs(
        signature_ascii_hex,
        expected_verification_key_u,
        expected_verification_key_v,
        verification_key_u,
        verification_key_v,
        signature_response,
        signature_challenge,
      )?,
    }
  }
}
