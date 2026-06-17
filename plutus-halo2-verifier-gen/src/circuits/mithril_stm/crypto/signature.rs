use anyhow::{Context, anyhow};
use serde::{Deserialize, Serialize};

use super::{
    BaseFieldElement, DOMAIN_SEPARATION_TAG_SIGNATURE, PrimeOrderProjectivePoint, ProjectivePoint,
    ScalarFieldElement, SchnorrVerificationKey, StmResult, UniqueSchnorrSignatureError,
    compute_poseidon_digest,
};

/// Structure of the Unique Schnorr signature to use with the SNARK
///
/// This signature includes a value `commitment_point` which depends only on
/// the message and the signing key.
/// This value is used in the lottery process to determine the correct indices.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, PartialOrd, Ord, Hash)]
pub struct UniqueSchnorrSignature {
    /// Deterministic value depending on the message and signing key
    pub(crate) commitment_point: ProjectivePoint,
    /// Part of the Unique Schnorr signature depending on the signing key
    pub(crate) response: ScalarFieldElement,
    /// Part of the Unique Schnorr signature NOT depending on the signing key
    pub(crate) challenge: BaseFieldElement,
}

impl UniqueSchnorrSignature {
    /// This function performs the verification of a Unique Schnorr signature given the signature, the signed message
    /// and a verification key derived from the signing key used to sign.
    ///
    /// Input:
    ///     - a Unique Schnorr signature
    ///     - a message: some BaseFieldElements
    ///     - a verification key: a value depending on the signing key
    /// Output:
    ///     - Ok(()) if the signature verifies and an error if not
    ///
    /// The protocol computes:
    ///     - msg_hash_point = H(msg)
    ///     - random_point_1_recomputed = response * msg_hash_point + challenge * commitment_point
    ///     - random_point_2_recomputed = response * prime_order_generator_point + challenge * verification_key
    ///     - challenge_recomputed = Poseidon(DST || H(msg) || verification_key
    ///     || commitment_point || random_point_1_recomputed || random_point_2_recomputed)
    ///
    /// Check: challenge == challenge_recomputed
    ///
    pub fn verify(
        &self,
        msg: &[BaseFieldElement],
        verification_key: &SchnorrVerificationKey,
    ) -> StmResult<()> {
        // Check that the verification key is valid
        verification_key
            .is_valid()
            .with_context(|| "Signature verification failed due to invalid verification key")?;

        let prime_order_generator_point = PrimeOrderProjectivePoint::create_generator();

        // First hashing the message to a scalar then hashing it to a curve point
        let msg_hash_point = ProjectivePoint::hash_to_projective_point(msg)?;

        // Computing random_point_1_recomputed = response *  H(msg) + challenge * commitment_point
        let challenge_as_scalar = ScalarFieldElement::from_base_field(&self.challenge)?;
        let random_point_1_recomputed =
            self.response * msg_hash_point + challenge_as_scalar * self.commitment_point;

        // Computing random_point_2_recomputed = response * prime_order_generator_point + challenge * vk
        let random_point_2_recomputed =
            self.response * prime_order_generator_point + challenge_as_scalar * verification_key.0;

        // Since the hash function takes as input scalar elements
        // We need to convert the EC points to their coordinates
        let mut points_coordinates: Vec<BaseFieldElement> = vec![DOMAIN_SEPARATION_TAG_SIGNATURE];
        points_coordinates.extend(
            [
                msg_hash_point,
                ProjectivePoint::from(verification_key.0),
                self.commitment_point,
                random_point_1_recomputed,
                ProjectivePoint::from(random_point_2_recomputed),
            ]
            .iter()
            .flat_map(|point| {
                let (u, v) = point.get_coordinates();
                [u, v]
            }),
        );

        let challenge_recomputed = compute_poseidon_digest(&points_coordinates);

        if challenge_recomputed != self.challenge {
            return Err(anyhow!(UniqueSchnorrSignatureError::SignatureInvalid(
                Box::new(*self)
            )));
        }

        Ok(())
    }

    /// Convert a `UniqueSchnorrSignature` into bytes.
    pub fn to_bytes(self) -> [u8; 96] {
        let mut out = [0; 96];
        out[0..32].copy_from_slice(&self.commitment_point.to_bytes());
        out[32..64].copy_from_slice(&self.response.to_bytes());
        out[64..96].copy_from_slice(&self.challenge.to_bytes());

        out
    }

    /// Convert bytes into a `UniqueSchnorrSignature`.
    pub fn from_bytes(bytes: &[u8]) -> StmResult<Self> {
        if bytes.len() < 96 {
            return Err(anyhow!(UniqueSchnorrSignatureError::Serialization))
                .with_context(|| "Not enough bytes provided to create a signature.");
        }

        let commitment_point = ProjectivePoint::from_bytes(
            bytes
                .get(0..32)
                .ok_or(UniqueSchnorrSignatureError::Serialization)
                .with_context(|| "Could not get the bytes of `commitment_point`")?,
        )
        .with_context(|| "Could not convert bytes to `commitment_point`")?;

        let response = ScalarFieldElement::from_bytes(
            bytes
                .get(32..64)
                .ok_or(UniqueSchnorrSignatureError::Serialization)
                .with_context(|| "Could not get the bytes of `response`")?,
        )
        .with_context(|| "Could not convert the bytes to `response`")?;

        let challenge = BaseFieldElement::from_bytes(
            bytes
                .get(64..96)
                .ok_or(UniqueSchnorrSignatureError::Serialization)
                .with_context(|| "Could not get the bytes of `challenge`")?,
        )
        .with_context(|| "Could not convert bytes to `challenge`")?;

        Ok(Self {
            commitment_point,
            response,
            challenge,
        })
    }
}
