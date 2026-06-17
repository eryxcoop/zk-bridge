use anyhow::{Context, anyhow};
use rand_core::{CryptoRng, RngCore};
use serde::{Deserialize, Serialize};

use super::{
    BaseFieldElement, DOMAIN_SEPARATION_TAG_SIGNATURE, PrimeOrderProjectivePoint, ProjectivePoint,
    ScalarFieldElement, SchnorrVerificationKey, StmResult, UniqueSchnorrSignature,
    UniqueSchnorrSignatureError, compute_poseidon_digest,
};

/// Schnorr Signing key, it is essentially a random scalar of the Jubjub scalar field
#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct SchnorrSigningKey(pub(crate) ScalarFieldElement);

impl SchnorrSigningKey {
    /// Generate a random scalar value to use as signing key
    pub fn generate<R: RngCore + CryptoRng>(rng: &mut R) -> Self {
        SchnorrSigningKey(ScalarFieldElement::new_random_scalar(rng))
    }

    /// This function is an adapted version of the Schnorr signature scheme that includes
    /// the computation of a deterministic value (called commitment_point) based on the message and the signing key
    /// and works with the Jubjub elliptic curve and the Poseidon hash function.
    ///
    /// Input:
    ///     - a message: some BaseFieldElements
    ///     - a signing key: an element of the scalar field of the Jubjub curve
    /// Output:
    ///     - a unique signature of the form (commitment_point, response, challenge):
    ///         - commitment_point is deterministic depending only on the message and signing key
    ///         - the response and challenge depends on a random value generated during the signature
    ///
    /// The protocol computes:
    ///     - commitment_point = signing_key * H(msg)
    ///     - random_scalar, a random value
    ///     - random_point_1 = random_scalar * H(msg)
    ///     - random_point_2 = random_scalar * prime_order_generator_point, where generator is a generator of the prime-order subgroup of Jubjub
    ///     - challenge = Poseidon(DST || H(msg) || verification_key || commitment_point || random_point_1 || random_point_2)
    ///     - response = random_scalar - challenge * signing_key
    ///
    /// Output the signature (`commitment_point`, `response`, `challenge`)
    ///
    pub fn sign<R: RngCore + CryptoRng>(
        &self,
        msg: &[BaseFieldElement],
        rng: &mut R,
    ) -> StmResult<UniqueSchnorrSignature> {
        // Use the subgroup generator to compute the curve points
        let prime_order_generator_point = PrimeOrderProjectivePoint::create_generator();
        let verification_key = SchnorrVerificationKey::new_from_signing_key(self.clone());

        // First hashing the message to a scalar then hashing it to a curve point
        let msg_hash_point = ProjectivePoint::hash_to_projective_point(msg)?;

        let commitment_point = self.0 * msg_hash_point;

        let random_scalar = ScalarFieldElement::new_random_nonzero_scalar(rng)
            .with_context(|| "Random scalar generation failed during signing.")?;

        let random_point_1 = random_scalar * msg_hash_point;
        let random_point_2 = random_scalar * prime_order_generator_point;

        // Since the hash function takes as input scalar elements
        // We need to convert the EC points to their coordinates
        // The order must be preserved
        let mut points_coordinates: Vec<BaseFieldElement> = vec![DOMAIN_SEPARATION_TAG_SIGNATURE];
        points_coordinates.extend(
            [
                msg_hash_point,
                ProjectivePoint::from(verification_key.0),
                commitment_point,
                random_point_1,
                ProjectivePoint::from(random_point_2),
            ]
            .iter()
            .flat_map(|point| {
                let (u, v) = point.get_coordinates();
                [u, v]
            }),
        );

        let challenge = compute_poseidon_digest(&points_coordinates);
        let challenge_times_sk = ScalarFieldElement::from_base_field(&challenge)? * self.0;
        let response = random_scalar - challenge_times_sk;

        Ok(UniqueSchnorrSignature {
            commitment_point,
            response,
            challenge,
        })
    }

    /// Convert a `SchnorrSigningKey` into bytes.
    pub fn to_bytes(&self) -> [u8; 32] {
        self.0.to_bytes()
    }

    /// Convert bytes into a `SchnorrSigningKey`.
    ///
    /// The bytes must represent a Jubjub scalar or the conversion will fail
    pub fn from_bytes(bytes: &[u8]) -> StmResult<Self> {
        if bytes.len() < 32 {
            return Err(anyhow!(UniqueSchnorrSignatureError::Serialization)).with_context(
                || "Not enough bytes provided to re-construct a Schnorr signing key.",
            );
        }
        let scalar_field_element = ScalarFieldElement::from_bytes(bytes)
            .with_context(|| "Could not construct Schnorr signing key from given bytes.")?;
        Ok(SchnorrSigningKey(scalar_field_element))
    }
}
