//! Circuit expressions structure and associated functions.

use super::super::{CircuitExpression, ExpressionG1, ScalarExpression};

use blstrs::Scalar;

// CHANGED vs upstream: new struct. Replaces the upstream tuple
// `(Vec<Vec<Expression>>, Vec<Vec<Expression>>)` for lookup equations with a
// named type, and uses the backend-agnostic `CircuitExpression` instead of
// halo2's `Expression` (so Midnight relations can be carried).
#[derive(Clone, Debug, Default)]
pub(crate) struct LookupExpressions {
    pub(crate) inputs: Vec<Vec<CircuitExpression<Scalar>>>,
    pub(crate) tables: Vec<Vec<CircuitExpression<Scalar>>>,
}

/// CircuitExpressions structure
/// This structure contains all expressions a circuit must satisfy.
/// These are extracted from the verifying key.
#[derive(Clone, Debug, Default)]
pub(crate) struct CircuitExpressions {
    // CHANGED vs upstream: gate/lookup equations now use `CircuitExpression`
    // (was halo2 `Expression`) and the named `LookupExpressions` type; added
    // `trash_expressions` for the Midnight circuit's trash columns.
    pub(crate) compiled_gate_equations: Vec<CircuitExpression<Scalar>>,
    pub(crate) compiled_lookups_equations: LookupExpressions,
    pub(crate) trash_expressions: Vec<ScalarExpression<Scalar>>,
    pub(crate) permutations_evaluated_terms: Vec<ScalarExpression<Scalar>>,
    pub(crate) permutation_terms_left: Vec<(char, ScalarExpression<Scalar>)>,
    pub(crate) permutation_terms_right: Vec<(char, ScalarExpression<Scalar>)>,
    pub(crate) h_commitments: Vec<(String, ExpressionG1<Scalar>)>,
}

impl CircuitExpressions {
    /// Extract a gate expression to the CircuitExpressions structure.
    pub(crate) fn gate(&mut self, expression: CircuitExpression<Scalar>) {
        self.compiled_gate_equations.push(expression);
    }

    /// Extract a lookup expression to the CircuitExpressions structure.
    pub(crate) fn lookup(
        &mut self,
        inputs: Vec<CircuitExpression<Scalar>>,
        tables: Vec<CircuitExpression<Scalar>>,
    ) {
        self.compiled_lookups_equations.inputs.push(inputs);
        self.compiled_lookups_equations.tables.push(tables);
    }

    /// Extract a trash expression to the CircuitExpressions structure.
    // CHANGED vs upstream: new method for the Midnight circuit's trash columns.
    pub(crate) fn trash(&mut self, expression: ScalarExpression<Scalar>) {
        self.trash_expressions.push(expression);
    }

    /// Extract a permutation evaluation expression to the CircuitExpressions
    /// structure.
    pub(crate) fn permutation_eval(&mut self, expression: ScalarExpression<Scalar>) {
        self.permutations_evaluated_terms.push(expression);
    }

    /// Extract a permutation left expression to the CircuitExpressions
    /// structure.
    pub(crate) fn permutation_left(&mut self, index: char, expression: ScalarExpression<Scalar>) {
        self.permutation_terms_left.push((index, expression));
    }

    /// Extract a permutation right expression to the CircuitExpressions
    /// structure.
    pub(crate) fn permutation_right(&mut self, index: char, expression: ScalarExpression<Scalar>) {
        self.permutation_terms_right.push((index, expression));
    }

    /// Extract a vanishing, h_commitment, expression to the CircuitExpressions
    /// structure.
    pub(crate) fn vanishing(&mut self, name: String, expression: ExpressionG1<Scalar>) {
        self.h_commitments.push((name, expression));
    }
}
