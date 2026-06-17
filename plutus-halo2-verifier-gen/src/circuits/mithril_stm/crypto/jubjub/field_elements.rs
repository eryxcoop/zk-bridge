use anyhow::{Context, anyhow};
use ff::Field;
use midnight_curves::{Fq as JubjubBase, Fr as JubjubScalar};
use rand_core::{CryptoRng, RngCore};
use sha2::{Digest, Sha256};
use std::hash::{Hash, Hasher};
use std::ops::{Add, Mul, Neg, Sub};

use super::super::{StmError, StmResult, UniqueSchnorrSignatureError};

/// Represents an element in the base field of the Jubjub curve.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Hash, PartialOrd, Ord)]
pub struct BaseFieldElement(pub(crate) JubjubBase);

impl BaseFieldElement {
    /// Retrieves the multiplicative identity element of the base field.
    pub(crate) fn get_one() -> Self {
        BaseFieldElement(JubjubBase::ONE)
    }

    /// Generates a new random scalar field element.
    #[allow(dead_code)]
    pub(crate) fn random(rng: &mut (impl RngCore + CryptoRng)) -> Self {
        BaseFieldElement(JubjubBase::random(rng))
    }

    /// Converts the base field element to its byte representation in little endian form.
    pub(crate) fn to_bytes(self) -> [u8; 32] {
        self.0.to_bytes_le()
    }

    /// Constructs a base field element from its canonical byte representation.
    pub(crate) fn from_bytes(bytes: &[u8]) -> StmResult<Self> {
        let mut base_bytes = [0u8; 32];
        base_bytes.copy_from_slice(
            bytes
                .get(..32)
                .ok_or(UniqueSchnorrSignatureError::BaseFieldElementSerialization)?,
        );

        match JubjubBase::from_bytes_le(&base_bytes).into_option() {
            Some(base_field_element) => Ok(Self(base_field_element)),
            None => Err(anyhow!(
                UniqueSchnorrSignatureError::BaseFieldElementSerialization
            )),
        }
    }

    /// Constructs a base field element from bytes by applying modulus reduction.
    pub(crate) fn from_raw(bytes: &[u8; 32]) -> StmResult<Self> {
        Ok(BaseFieldElement(JubjubBase::from_raw([
            u64::from_le_bytes(bytes[0..8].try_into()?),
            u64::from_le_bytes(bytes[8..16].try_into()?),
            u64::from_le_bytes(bytes[16..24].try_into()?),
            u64::from_le_bytes(bytes[24..32].try_into()?),
        ])))
    }
}

impl TryFrom<&[u8]> for BaseFieldElement {
    type Error = StmError;

    fn try_from(value: &[u8]) -> Result<Self, Self::Error> {
        let hashed_input: [u8; 32] = Sha256::digest(value).into();
        BaseFieldElement::from_raw(&hashed_input)
    }
}

impl From<u64> for BaseFieldElement {
    fn from(integer: u64) -> Self {
        BaseFieldElement(JubjubBase::from(integer))
    }
}

impl From<JubjubBase> for BaseFieldElement {
    fn from(base: JubjubBase) -> Self {
        BaseFieldElement(base)
    }
}

impl Add for BaseFieldElement {
    type Output = BaseFieldElement;

    fn add(self, other: BaseFieldElement) -> BaseFieldElement {
        BaseFieldElement(self.0 + other.0)
    }
}

impl Neg for BaseFieldElement {
    type Output = BaseFieldElement;

    fn neg(self) -> BaseFieldElement {
        BaseFieldElement(-self.0)
    }
}

impl Sub for &BaseFieldElement {
    type Output = BaseFieldElement;

    fn sub(self, other: &BaseFieldElement) -> BaseFieldElement {
        BaseFieldElement(self.0 - other.0)
    }
}

impl Mul for BaseFieldElement {
    type Output = BaseFieldElement;

    fn mul(self, other: BaseFieldElement) -> BaseFieldElement {
        BaseFieldElement(self.0 * other.0)
    }
}

impl Mul for &BaseFieldElement {
    type Output = BaseFieldElement;

    fn mul(self, other: &BaseFieldElement) -> BaseFieldElement {
        BaseFieldElement(self.0 * other.0)
    }
}

/// Represents an element in the scalar field of the Jubjub curve.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) struct ScalarFieldElement(pub(crate) JubjubScalar);

impl ScalarFieldElement {
    /// Generates a new random scalar value.
    pub(crate) fn new_random_scalar(rng: &mut (impl RngCore + CryptoRng)) -> Self {
        ScalarFieldElement(JubjubScalar::random(rng))
    }

    /// Checks whether the scalar is zero.
    pub(crate) fn is_zero(&self) -> bool {
        self.0 == JubjubScalar::zero()
    }

    /// Tries to generate a non-zero scalar within a bounded number of attempts.
    pub(crate) fn new_random_nonzero_scalar(
        rng: &mut (impl RngCore + CryptoRng),
    ) -> StmResult<Self> {
        for _ in 0..100 {
            let random_scalar = Self::new_random_scalar(rng);
            if !random_scalar.is_zero() {
                return Ok(random_scalar);
            }
        }

        Err(anyhow!(UniqueSchnorrSignatureError::RandomScalarGeneration))
    }

    /// Converts the scalar field element to bytes.
    pub(crate) fn to_bytes(self) -> [u8; 32] {
        self.0.to_bytes()
    }

    /// Constructs a scalar field element from canonical bytes.
    pub(crate) fn from_bytes(bytes: &[u8]) -> StmResult<Self> {
        let mut scalar_bytes = [0u8; 32];
        scalar_bytes.copy_from_slice(
            bytes
                .get(..32)
                .ok_or(UniqueSchnorrSignatureError::ScalarFieldElementSerialization)?,
        );

        match JubjubScalar::from_bytes(&scalar_bytes).into_option() {
            Some(scalar_field_element) => Ok(Self(scalar_field_element)),
            None => Err(anyhow!(
                UniqueSchnorrSignatureError::ScalarFieldElementSerialization
            )),
        }
    }

    /// Constructs a scalar field element by reducing raw bytes modulo the field modulus.
    pub(crate) fn from_raw(bytes: &[u8]) -> StmResult<Self> {
        let mut scalar_bytes = [0u8; 32];
        scalar_bytes.copy_from_slice(
            bytes
                .get(..32)
                .ok_or(UniqueSchnorrSignatureError::ScalarFieldElementSerialization)?,
        );

        let mut bytes64 = [0u64; 4];
        for i in 0..4 {
            bytes64[i] =
                u64::from_le_bytes(bytes[8 * i..8 * (i + 1)].try_into().with_context(|| {
                    anyhow!(UniqueSchnorrSignatureError::ScalarFieldElementSerialization)
                })?)
        }

        Ok(Self(JubjubScalar::from_raw(bytes64)))
    }

    /// Converts a base field element into a scalar using the shared byte representation.
    pub(crate) fn from_base_field(base_element: &BaseFieldElement) -> StmResult<Self> {
        let base_element_bytes = base_element.0.to_bytes_le();
        ScalarFieldElement::from_raw(&base_element_bytes)
    }
}

impl Mul for ScalarFieldElement {
    type Output = ScalarFieldElement;

    fn mul(self, other: ScalarFieldElement) -> ScalarFieldElement {
        ScalarFieldElement(self.0 * other.0)
    }
}

impl Sub for ScalarFieldElement {
    type Output = ScalarFieldElement;

    fn sub(self, other: ScalarFieldElement) -> ScalarFieldElement {
        ScalarFieldElement(self.0 - other.0)
    }
}

impl Hash for ScalarFieldElement {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.to_bytes().hash(state);
    }
}
