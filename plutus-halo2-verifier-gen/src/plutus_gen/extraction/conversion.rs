//! NEW vs upstream: conversions between Midnight types and the pipeline's
//! generic types (scalars, G1/G2 points, and `CircuitExpression`). Lets the
//! Midnight extractor reuse the backend-agnostic pipeline (see point 3 of
//! PLUTUS_HALO2_VERIFIER_CHANGES.md).

use anyhow::{Result, anyhow};
use blstrs::{G1Affine, G2Affine, Scalar};
use ff::PrimeField;
use group::{Curve, GroupEncoding};
use halo2_proofs::plonk::Expression as Halo2Expression;
use midnight_curves::{Fq as MidnightScalar, G1Affine as MidnightG1Affine, G2Affine as MidnightG2Affine};
use midnight_proofs::plonk::Expression as MidnightExpression;

use super::data::CircuitExpression;

pub(crate) fn scalar_from_midnight(value: MidnightScalar) -> Scalar {
    Option::<Scalar>::from(Scalar::from_repr(value.to_repr()))
        .expect("midnight scalar should map to blstrs::Scalar")
}

pub(crate) fn g1_affine_from_midnight(value: MidnightG1Affine) -> Result<G1Affine> {
    let bytes = value.to_bytes();
    let mut repr = <G1Affine as GroupEncoding>::Repr::default();
    repr.as_mut().copy_from_slice(bytes.as_ref());
    Option::<G1Affine>::from(G1Affine::from_bytes(&repr))
        .ok_or_else(|| anyhow!("failed to convert midnight G1 point into blstrs::G1Affine"))
}

pub(crate) fn g2_affine_from_midnight(value: MidnightG2Affine) -> Result<G2Affine> {
    let bytes = value.to_bytes();
    let mut repr = <G2Affine as GroupEncoding>::Repr::default();
    repr.as_mut().copy_from_slice(bytes.as_ref());
    Option::<G2Affine>::from(G2Affine::from_bytes(&repr))
        .ok_or_else(|| anyhow!("failed to convert midnight G2 point into blstrs::G2Affine"))
}

pub(crate) fn g1_projective_from_midnight<P>(value: &P) -> Result<G1Affine>
where
    P: Curve<AffineRepr = MidnightG1Affine>,
{
    g1_affine_from_midnight(value.to_affine())
}

impl From<Halo2Expression<Scalar>> for CircuitExpression<Scalar> {
    fn from(expression: Halo2Expression<Scalar>) -> Self {
        match expression {
            Halo2Expression::Constant(value) => Self::Constant(value),
            Halo2Expression::Selector(_) => Self::Selector,
            Halo2Expression::Fixed(query) => {
                Self::Fixed(query.index().expect("fixed query index is missing") + 1)
            }
            Halo2Expression::Advice(query) => {
                Self::Advice(query.index.expect("advice query index is missing") + 1)
            }
            Halo2Expression::Instance(query) => {
                Self::Instance(query.index.expect("instance query index is missing") + 1)
            }
            Halo2Expression::Challenge(_) => Self::Challenge,
            Halo2Expression::Negated(inner) => Self::Negated(Box::new((*inner).into())),
            Halo2Expression::Sum(lhs, rhs) => {
                Self::Sum(Box::new((*lhs).into()), Box::new((*rhs).into()))
            }
            Halo2Expression::Product(lhs, rhs) => {
                Self::Product(Box::new((*lhs).into()), Box::new((*rhs).into()))
            }
            Halo2Expression::Scaled(inner, factor) => {
                Self::Scaled(Box::new((*inner).into()), factor)
            }
        }
    }
}

impl From<MidnightExpression<MidnightScalar>> for CircuitExpression<Scalar> {
    fn from(expression: MidnightExpression<MidnightScalar>) -> Self {
        match expression {
            MidnightExpression::Constant(value) => Self::Constant(scalar_from_midnight(value)),
            MidnightExpression::Selector(_) => Self::Selector,
            MidnightExpression::Fixed(query) => {
                Self::Fixed(query.index().expect("fixed query index is missing") + 1)
            }
            MidnightExpression::Advice(query) => {
                Self::Advice(query.index.expect("advice query index is missing") + 1)
            }
            MidnightExpression::Instance(query) => {
                Self::Instance(query.index.expect("instance query index is missing") + 1)
            }
            MidnightExpression::Challenge(_) => Self::Challenge,
            MidnightExpression::Negated(inner) => Self::Negated(Box::new((*inner).into())),
            MidnightExpression::Sum(lhs, rhs) => {
                Self::Sum(Box::new((*lhs).into()), Box::new((*rhs).into()))
            }
            MidnightExpression::Product(lhs, rhs) => {
                Self::Product(Box::new((*lhs).into()), Box::new((*rhs).into()))
            }
            MidnightExpression::Scaled(inner, factor) => {
                Self::Scaled(Box::new((*inner).into()), scalar_from_midnight(factor))
            }
        }
    }
}
