//! Expression types for scalar and group elements, used as a simple DSL for
//! the verifier side equations that are not part of the prover's.
//! The related functions can be found in the folder expression_steps

use serde::{Deserialize, Serialize};

/// Backend-agnostic PLONK expression used by the emitters.
// CHANGED vs upstream: new type. Upstream used halo2's `Expression` directly;
// this generic, backend-agnostic expression lets the pipeline carry gate/lookup
// equations extracted from a Midnight relation (which is not plain halo2).
#[derive(Clone, PartialEq, Eq, Debug, Deserialize, Serialize)]
pub(crate) enum CircuitExpression<F> {
    Constant(F),
    Selector,
    Fixed(usize),
    Advice(usize),
    Instance(usize),
    Challenge,
    Negated(Box<CircuitExpression<F>>),
    Sum(Box<CircuitExpression<F>>, Box<CircuitExpression<F>>),
    Product(Box<CircuitExpression<F>>, Box<CircuitExpression<F>>),
    Scaled(Box<CircuitExpression<F>>, F),
}

/// Operations and types for Scalars
#[derive(Clone, PartialEq, Eq, Debug, Deserialize, Serialize)]
pub(crate) enum ScalarExpression<F> {
    Constant(F),
    Variable(String),
    Advice(usize),
    Fixed(usize),
    Instance(usize),
    PermutationCommon(usize),
    Negated(Box<ScalarExpression<F>>),
    Sum(Box<ScalarExpression<F>>, Box<ScalarExpression<F>>),
    Product(Box<ScalarExpression<F>>, Box<ScalarExpression<F>>),
    PowMod(Box<ScalarExpression<F>>, usize),
}

/// Operations and types for G1 elements
// CHANGED vs upstream: dropped the `Zero` variant. The reworked vanishing
// expressions no longer build a `scale(Zero, xn)` seed term, so an explicit
// zero G1 element is no longer needed (see extraction_steps/vanishing.rs).
#[derive(Clone, PartialEq, Eq, Debug)]
pub(crate) enum ExpressionG1<F> {
    Sum(Box<ExpressionG1<F>>, Box<ExpressionG1<F>>),
    Scale(Box<ExpressionG1<F>>, ScalarExpression<F>),
    VanishingSplit(usize),
    Variable(String),
}
