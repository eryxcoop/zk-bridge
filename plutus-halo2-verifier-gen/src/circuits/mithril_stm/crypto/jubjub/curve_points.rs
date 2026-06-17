use anyhow::anyhow;
use group::{Group, GroupEncoding};
use midnight_circuits::instructions::HashToCurveCPU;
use midnight_circuits::{
    ecc::{hash_to_curve::HashToCurveGadget, native::EccChip},
    hash::poseidon::PoseidonChip,
    types::AssignedNative,
};
use midnight_curves::{
    EDWARDS_D, Fq as JubjubBase, JubjubAffine as JubjubAffinePoint, JubjubExtended,
    JubjubSubgroup,
};
use std::cmp::Ordering;
use std::hash::{Hash, Hasher};
use std::ops::{Add, Mul};

use super::super::{StmResult, UniqueSchnorrSignatureError};
use super::{BaseFieldElement, ScalarFieldElement};

/// CPU hash-to-curve gadget type used by the local crypto copy.
pub(crate) type JubjubHashToCurveGadget = HashToCurveGadget<
    JubjubBase,
    JubjubExtended,
    AssignedNative<JubjubBase>,
    PoseidonChip<JubjubBase>,
    EccChip<JubjubExtended>,
>;

/// Represents a point in affine coordinates on the Jubjub curve.
#[derive(Clone)]
pub(crate) struct AffinePoint(JubjubAffinePoint);

impl AffinePoint {
    pub(crate) fn from_projective_point(projective_point: ProjectivePoint) -> Self {
        AffinePoint(JubjubAffinePoint::from(projective_point.0))
    }

    pub(crate) fn get_u(&self) -> BaseFieldElement {
        BaseFieldElement(self.0.get_u())
    }

    pub(crate) fn get_v(&self) -> BaseFieldElement {
        BaseFieldElement(self.0.get_v())
    }
}

impl From<&PrimeOrderProjectivePoint> for AffinePoint {
    fn from(prime_order_projective_point: &PrimeOrderProjectivePoint) -> Self {
        AffinePoint(JubjubAffinePoint::from(JubjubExtended::from(
            prime_order_projective_point.0,
        )))
    }
}

/// Represents a point in projective coordinates on the Jubjub curve.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct ProjectivePoint(pub(crate) JubjubExtended);

impl ProjectivePoint {
    pub(crate) fn hash_to_projective_point(input: &[BaseFieldElement]) -> StmResult<Self> {
        let base_elements = input.iter().map(|elem| elem.0).collect::<Vec<_>>();
        let point = JubjubHashToCurveGadget::hash_to_curve(&base_elements);
        Ok(ProjectivePoint(JubjubExtended::from(point)))
    }

    pub(crate) fn get_coordinates(&self) -> (BaseFieldElement, BaseFieldElement) {
        let affine_point = AffinePoint::from_projective_point(*self);
        (affine_point.get_u(), affine_point.get_v())
    }

    pub(crate) fn to_bytes(self) -> [u8; 32] {
        self.0.to_bytes()
    }

    pub(crate) fn from_bytes(bytes: &[u8]) -> StmResult<Self> {
        let mut projective_point_bytes = [0u8; 32];
        projective_point_bytes
            .copy_from_slice(bytes.get(..32).ok_or(UniqueSchnorrSignatureError::Serialization)?);

        match JubjubExtended::from_bytes(&projective_point_bytes).into_option() {
            Some(projective_point) => Ok(Self(projective_point)),
            None => Err(anyhow!(
                UniqueSchnorrSignatureError::ProjectivePointSerialization
            )),
        }
    }

    pub(crate) fn is_prime_order(self) -> bool {
        self.0.is_prime_order().into()
    }
}

impl Add for ProjectivePoint {
    type Output = ProjectivePoint;

    fn add(self, other: ProjectivePoint) -> ProjectivePoint {
        ProjectivePoint(self.0 + other.0)
    }
}

impl Mul<ProjectivePoint> for ScalarFieldElement {
    type Output = ProjectivePoint;

    fn mul(self, point: ProjectivePoint) -> ProjectivePoint {
        ProjectivePoint(point.0 * self.0)
    }
}

impl From<PrimeOrderProjectivePoint> for ProjectivePoint {
    fn from(prime_order_projective_point: PrimeOrderProjectivePoint) -> Self {
        ProjectivePoint(JubjubExtended::from(prime_order_projective_point.0))
    }
}

impl Hash for ProjectivePoint {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.to_bytes().hash(state);
    }
}

impl PartialOrd for ProjectivePoint {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for ProjectivePoint {
    fn cmp(&self, other: &Self) -> Ordering {
        self.to_bytes().cmp(&other.to_bytes())
    }
}

/// Represents a prime-order point in projective coordinates on the Jubjub curve.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub(crate) struct PrimeOrderProjectivePoint(pub(crate) JubjubSubgroup);

impl PrimeOrderProjectivePoint {
    pub(crate) fn create_generator() -> Self {
        PrimeOrderProjectivePoint(JubjubSubgroup::generator())
    }

    pub(crate) fn is_on_curve(&self) -> StmResult<PrimeOrderProjectivePoint> {
        let (x, y) = self.get_coordinates();
        let x_square = x * x;
        let y_square = y * y;

        let lhs = &y_square - &x_square;
        let rhs = (x_square * y_square) * BaseFieldElement(EDWARDS_D) + BaseFieldElement::get_one();

        if lhs != rhs {
            return Err(anyhow!(UniqueSchnorrSignatureError::PointIsNotOnCurve(
                Box::new(*self)
            )));
        }

        Ok(*self)
    }

    pub(crate) fn get_coordinates(&self) -> (BaseFieldElement, BaseFieldElement) {
        let affine_point = AffinePoint::from(self);
        (affine_point.get_u(), affine_point.get_v())
    }

    pub(crate) fn from_coordinates(u: BaseFieldElement, v: BaseFieldElement) -> StmResult<Self> {
        let prime_order_point =
            PrimeOrderProjectivePoint(JubjubSubgroup::from_raw_unchecked(u.0, v.0))
                .is_on_curve()?;

        let projective_point = ProjectivePoint::from(prime_order_point);
        if !projective_point.is_prime_order() {
            return Err(anyhow!(UniqueSchnorrSignatureError::PointIsNotPrimeOrder(
                Box::new(prime_order_point)
            )));
        }

        Ok(prime_order_point)
    }

    pub(crate) fn to_bytes(self) -> [u8; 32] {
        self.0.to_bytes()
    }

    pub(crate) fn from_bytes(bytes: &[u8]) -> StmResult<Self> {
        let mut prime_order_projective_point_bytes = [0u8; 32];
        prime_order_projective_point_bytes
            .copy_from_slice(bytes.get(..32).ok_or(UniqueSchnorrSignatureError::Serialization)?);

        match JubjubSubgroup::from_bytes(&prime_order_projective_point_bytes).into_option() {
            Some(prime_order_projective_point) => Ok(Self(prime_order_projective_point)),
            None => Err(anyhow!(
                UniqueSchnorrSignatureError::PrimeOrderProjectivePointSerialization
            )),
        }
    }
}

impl Add for PrimeOrderProjectivePoint {
    type Output = PrimeOrderProjectivePoint;

    fn add(self, other: PrimeOrderProjectivePoint) -> PrimeOrderProjectivePoint {
        PrimeOrderProjectivePoint(self.0 + other.0)
    }
}

impl Mul<PrimeOrderProjectivePoint> for ScalarFieldElement {
    type Output = PrimeOrderProjectivePoint;

    fn mul(self, point: PrimeOrderProjectivePoint) -> PrimeOrderProjectivePoint {
        PrimeOrderProjectivePoint(point.0 * self.0)
    }
}
