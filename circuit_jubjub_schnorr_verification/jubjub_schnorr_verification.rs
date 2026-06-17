use anyhow::{bail, Context, Result};
use num_bigint::BigUint;
use serde::{Deserialize, Serialize};

pub const EXPECTED_PUBLIC_INPUTS: usize = 6;
const JUBJUB_BASE_FIELD_MODULUS_DECIMAL: &str =
    "52435875175126190479447740508185965837690552500527637822603658699938581184513";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct JubjubSchnorrCircuitInputs {
    pub digest_hi: String,
    pub digest_low: String,
    pub verification_key_u: String,
    pub verification_key_v: String,
    pub signature_response: String,
    pub signature_challenge: String,
    pub challenge_scalar: String,
    pub challenge_quotient: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PackedJubjubSchnorrPublicInputs {
    pub digest_hi: String,
    pub digest_low: String,
    pub verification_key_u: String,
    pub verification_key_v: String,
    pub signature_response: String,
    pub signature_challenge: String,
}

pub fn load_example_valid_witness() -> Result<JubjubSchnorrCircuitInputs> {
    let witness: JubjubSchnorrCircuitInputs =
        serde_json::from_str(include_str!("examples/valid_algebraic_statement.json"))
            .context("embedded valid_algebraic_statement.json must stay valid JSON")?;
    witness.validate()?;
    Ok(witness)
}

impl JubjubSchnorrCircuitInputs {
    pub fn validate(&self) -> Result<()> {
        for (label, value) in [
            ("digest_hi", &self.digest_hi),
            ("digest_low", &self.digest_low),
            ("verification_key_u", &self.verification_key_u),
            ("verification_key_v", &self.verification_key_v),
            ("signature_response", &self.signature_response),
            ("signature_challenge", &self.signature_challenge),
            ("challenge_scalar", &self.challenge_scalar),
            ("challenge_quotient", &self.challenge_quotient),
        ] {
            if value.trim().is_empty() {
                bail!("{label} must not be empty");
            }
        }

        parse_u128_decimal(&self.digest_hi, "digest_hi")?;
        parse_u128_decimal(&self.digest_low, "digest_low")?;

        for (label, value) in [
            ("verification_key_u", &self.verification_key_u),
            ("verification_key_v", &self.verification_key_v),
            ("signature_response", &self.signature_response),
            ("signature_challenge", &self.signature_challenge),
            ("challenge_scalar", &self.challenge_scalar),
            ("challenge_quotient", &self.challenge_quotient),
        ] {
            parse_biguint_decimal(value, label)?;
        }

        Ok(())
    }

    pub fn message_base(&self) -> Result<String> {
        derive_message_base_from_digest_halves(&self.digest_hi, &self.digest_low)
    }

    pub fn packed_public_inputs(&self) -> PackedJubjubSchnorrPublicInputs {
        pack_jubjub_schnorr_public_inputs(
            &self.digest_hi,
            &self.digest_low,
            &self.verification_key_u,
            &self.verification_key_v,
            &self.signature_response,
            &self.signature_challenge,
        )
    }
}

pub fn pack_jubjub_schnorr_public_inputs(
    digest_hi: impl Into<String>,
    digest_low: impl Into<String>,
    verification_key_u: impl Into<String>,
    verification_key_v: impl Into<String>,
    signature_response: impl Into<String>,
    signature_challenge: impl Into<String>,
) -> PackedJubjubSchnorrPublicInputs {
    PackedJubjubSchnorrPublicInputs {
        digest_hi: digest_hi.into(),
        digest_low: digest_low.into(),
        verification_key_u: verification_key_u.into(),
        verification_key_v: verification_key_v.into(),
        signature_response: signature_response.into(),
        signature_challenge: signature_challenge.into(),
    }
}

pub fn pack_jubjub_schnorr_public_inputs_vec(
    digest_hi: impl Into<String>,
    digest_low: impl Into<String>,
    verification_key_u: impl Into<String>,
    verification_key_v: impl Into<String>,
    signature_response: impl Into<String>,
    signature_challenge: impl Into<String>,
) -> Vec<String> {
    let packed = pack_jubjub_schnorr_public_inputs(
        digest_hi,
        digest_low,
        verification_key_u,
        verification_key_v,
        signature_response,
        signature_challenge,
    );

    vec![
        packed.digest_hi,
        packed.digest_low,
        packed.verification_key_u,
        packed.verification_key_v,
        packed.signature_response,
        packed.signature_challenge,
    ]
}

pub fn unpack_jubjub_schnorr_public_inputs(
    public_inputs: &[String],
) -> Result<(String, String, String, String, String, String)> {
    if public_inputs.len() != EXPECTED_PUBLIC_INPUTS {
        bail!(
            "expected {EXPECTED_PUBLIC_INPUTS} public inputs, got {}",
            public_inputs.len()
        );
    }

    Ok((
        public_inputs[0].clone(),
        public_inputs[1].clone(),
        public_inputs[2].clone(),
        public_inputs[3].clone(),
        public_inputs[4].clone(),
        public_inputs[5].clone(),
    ))
}

pub fn derive_message_base_from_digest_halves(digest_hi: &str, digest_low: &str) -> Result<String> {
    let hi = parse_u128_decimal(digest_hi, "digest_hi")?;
    let low = parse_u128_decimal(digest_low, "digest_low")?;
    let modulus =
        parse_biguint_decimal(JUBJUB_BASE_FIELD_MODULUS_DECIMAL, "jubjub_base_field_modulus")?;

    let mut digest_bytes = [0u8; 32];
    digest_bytes[..16].copy_from_slice(&hi.to_be_bytes());
    digest_bytes[16..].copy_from_slice(&low.to_be_bytes());

    Ok((BigUint::from_bytes_le(&digest_bytes) % modulus).to_string())
}

pub fn split_digest_hex_to_halves_decimal(digest_hex: &str) -> Result<(String, String)> {
    let digest_bytes = hex::decode(digest_hex)
        .with_context(|| format!("digest hex must be valid lowercase/uppercase hex: {digest_hex}"))?;

    if digest_bytes.len() != 32 {
        bail!(
            "digest hex must decode to exactly 32 bytes, got {}",
            digest_bytes.len()
        );
    }

    let digest_hi = u128::from_be_bytes(
        digest_bytes[..16]
            .try_into()
            .expect("first 16 bytes must exist"),
    );
    let digest_low = u128::from_be_bytes(
        digest_bytes[16..]
            .try_into()
            .expect("last 16 bytes must exist"),
    );

    Ok((digest_hi.to_string(), digest_low.to_string()))
}

fn parse_u128_decimal(value: &str, label: &str) -> Result<u128> {
    value
        .parse::<u128>()
        .with_context(|| format!("{label} must be a base-10 unsigned integer that fits in u128"))
}

fn parse_biguint_decimal(value: &str, label: &str) -> Result<BigUint> {
    value
        .parse::<u128>()
        .map(BigUint::from)
        .or_else(|_| value.parse::<BigUint>())
        .with_context(|| format!("{label} must be a base-10 unsigned integer"))
}
