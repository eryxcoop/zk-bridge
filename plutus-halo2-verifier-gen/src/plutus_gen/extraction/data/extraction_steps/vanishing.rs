//! Code for extracting vasnishing related expressions.

use super::super::{CircuitRepresentation, ExpressionG1, ScalarExpression, constants::*};
use crate::plutus_gen::extraction::pcs::ExtractPCS;

#[cfg(feature = "plutus_debug")]
use log::info;

pub(crate) fn vanishing_expressions<PCS>(circuit_repr: &mut CircuitRepresentation<PCS>)
where
    PCS: ExtractPCS,
{
    let nb_vanishing_splits = circuit_repr.nb_vanishing_splits();

    // CHANGED vs upstream: hCommitment1 seed simplified. Upstream built
    // `scale(Zero, xn) + vanishingSplit_N`; since `scale(Zero, xn)` is always
    // zero it is dropped, so the seed is just `vanishingSplit_N` (this is why the
    // `Zero` variant of ExpressionG1 could be removed).
    {
        let init_expr = ExpressionG1::VanishingSplit(nb_vanishing_splits);
        circuit_repr.expressions.vanishing(h_com_str(1), init_expr);
    }

    // Render last on as vanishing_g
    // !hCommitment{:?} = scale xn hCommitment{:?} + vanishingSplit{:?}
    // a + b
    for i in 1..(nb_vanishing_splits - 1) {
        let a = ExpressionG1::Scale(
            Box::new(ExpressionG1::Variable(h_com_str(i))),
            ScalarExpression::Variable(XN_STR.to_string()),
        );
        let b = ExpressionG1::VanishingSplit(nb_vanishing_splits - i);
        let loop_expr = ExpressionG1::Sum(Box::new(a), Box::new(b));

        // terms.push((h_com_str(i + 1), term));
        circuit_repr
            .expressions
            .vanishing(h_com_str(i + 1), loop_expr);
    }

    // !vanishing_g = scale xn hCommitment{} + vanishingSplit1; nb_vanishing_splits - 1
    // a + b
    {
        let a = ExpressionG1::Scale(
            Box::new(ExpressionG1::Variable(h_com_str(nb_vanishing_splits - 1))),
            ScalarExpression::Variable(XN_STR.to_string()),
        );
        let b = ExpressionG1::VanishingSplit(1);
        let g_expr = ExpressionG1::Sum(Box::new(a), Box::new(b));
        circuit_repr
            .expressions
            .vanishing(VANISH_G_STR.to_string(), g_expr);
    }
}

// CHANGED vs upstream: new function. Same structure as `vanishing_expressions`
// but folds the h-commitments with `x_chop` (x^(n-1)) instead of `xn`, as the
// Midnight verifier requires.
pub(crate) fn vanishing_expressions_midnight<PCS>(circuit_repr: &mut CircuitRepresentation<PCS>)
where
    PCS: ExtractPCS,
{
    let nb_vanishing_splits = circuit_repr.nb_vanishing_splits();

    {
        let init_expr = ExpressionG1::VanishingSplit(nb_vanishing_splits);
        circuit_repr.expressions.vanishing(h_com_str(1), init_expr);
    }

    for i in 1..(nb_vanishing_splits - 1) {
        let a = ExpressionG1::Scale(
            Box::new(ExpressionG1::Variable(h_com_str(i))),
            ScalarExpression::Variable(X_CHOP_STR.to_string()),
        );
        let b = ExpressionG1::VanishingSplit(nb_vanishing_splits - i);
        let loop_expr = ExpressionG1::Sum(Box::new(a), Box::new(b));
        circuit_repr
            .expressions
            .vanishing(h_com_str(i + 1), loop_expr);
    }

    {
        let a = ExpressionG1::Scale(
            Box::new(ExpressionG1::Variable(h_com_str(nb_vanishing_splits - 1))),
            ScalarExpression::Variable(X_CHOP_STR.to_string()),
        );
        let b = ExpressionG1::VanishingSplit(1);
        let g_expr = ExpressionG1::Sum(Box::new(a), Box::new(b));
        circuit_repr
            .expressions
            .vanishing(VANISH_G_STR.to_string(), g_expr);
    }
}
