use std::{
    cmp::Ordering,
    hash::{Hash, Hasher},
};

use anyhow::{Context, anyhow};
use serde::{Deserialize, Serialize};

use super::{
    BaseFieldElement, PrimeOrderProjectivePoint, ProjectivePoint, SchnorrSigningKey, StmResult,
    UniqueSchnorrSignatureError,
};

/// Schnorr verification key, it consists of a point on the Jubjub curve
/// vk = g * sk, where g is a generator
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SchnorrVerificationKey(pub(crate) PrimeOrderProjectivePoint);

impl SchnorrVerificationKey {
    /// Convert a Schnorr signing key into a verification key
    ///
    /// This is done by computing `vk = g * sk` where g is the generator
    /// of the subgroup and sk is the schnorr signing key
    pub fn new_from_signing_key(signing_key: SchnorrSigningKey) -> Self {
        let generator = PrimeOrderProjectivePoint::create_generator();

        SchnorrVerificationKey(signing_key.0 * generator)
    }

    pub fn is_valid(&self) -> StmResult<()> {
        let projective_point = ProjectivePoint::from(self.0);
        if !projective_point.is_prime_order() {
            return Err(anyhow!(UniqueSchnorrSignatureError::PointIsNotPrimeOrder(
                Box::new(self.0)
            )));
        }
        self.0.is_on_curve()?;

        Ok(())
    }

    /// Convert a `SchnorrVerificationKey` into bytes by decomposing it into
    /// its coordinates first.
    pub fn to_bytes(self) -> [u8; 64] {
        let (x, y) = self.0.get_coordinates();
        let mut output = [0; 64];
        output[0..32].copy_from_slice(&x.to_bytes());
        output[32..64].copy_from_slice(&y.to_bytes());
        output
    }

    /// Convert bytes into a `SchnorrVerificationKey`.
    ///
    /// The bytes must represent two Jubjub Base field elements or the conversion will fail
    pub fn from_bytes(bytes: &[u8]) -> StmResult<Self> {
        if bytes.len() < 64 {
            return Err(anyhow!(UniqueSchnorrSignatureError::Serialization)).with_context(
                || "Not enough bytes provided to construct a Schnorr verification key.",
            );
        }
        let x = BaseFieldElement::from_bytes(&bytes[0..32])?;
        let y = BaseFieldElement::from_bytes(&bytes[32..64])?;
        let prime_order_projective_point = PrimeOrderProjectivePoint::from_coordinates(x, y)
            .with_context(|| "Cannot construct Schnorr verification key from given bytes.")?;

        Ok(SchnorrVerificationKey(prime_order_projective_point))
    }
}

impl Hash for SchnorrVerificationKey {
    fn hash<H: Hasher>(&self, state: &mut H) {
        Hash::hash_slice(&self.to_bytes(), state)
    }
}

impl PartialOrd for SchnorrVerificationKey {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(std::cmp::Ord::cmp(self, other))
    }
}

impl Ord for SchnorrVerificationKey {
    fn cmp(&self, other: &Self) -> Ordering {
        self.to_bytes().cmp(&other.to_bytes())
    }
}
