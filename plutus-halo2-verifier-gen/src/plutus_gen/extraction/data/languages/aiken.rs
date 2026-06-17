//! All functions related to data's name and manipulation in Aiken language

// CHANGED vs upstream: transpile the pipeline's own `CircuitExpression` instead
// of halo2's `Expression` (the `use halo2_proofs::plonk::Expression` import was
// dropped). Gate/lookup equations are now extracted from a Midnight relation, so
// they no longer carry halo2 query objects — see `base_types/expression.rs`.
use super::super::{
    CircuitExpression, Commitments, Evaluations, ExpressionG1, ScalarExpression, constants::*,
};

use blstrs::Scalar;

use std::io::{BufWriter, Result, Write};

pub trait AikenExpression {
    fn compile_expression(&self) -> String;
}

// CHANGED vs upstream: takes `CircuitExpression<Scalar>` instead of halo2's
// `Expression<Scalar>`.
pub(crate) fn combine_aiken_expressions(
    lookup_expressions: Vec<CircuitExpression<Scalar>>,
) -> String {
    let compiled: Vec<_> = lookup_expressions
        .iter()
        .map(AikenExpression::compile_expression)
        .collect();
    compiled.iter().fold(ZERO_STR.to_string(), |acc, eval| {
        format!("add(mul({}, {}), {})", acc, THETA_STR, eval)
    })
}

impl AikenExpression for Evaluations {
    fn compile_expression(&self) -> String {
        match self {
            // CHANGED vs upstream: added for Midnight support (committed-instance evals).
            Evaluations::CommittedInstance(index) => {
                format!("instance_eval_{:?}", index)
            }
            Evaluations::Advice(index) => {
                format!("advice_eval_{:?}", index)
            }
            Evaluations::Fixed(index) => {
                format!("fixed_eval_{:?}", index)
            }
            Evaluations::Permutation(set, index) => perm_eval_str(set, *index),
            Evaluations::Lookup(index) => {
                format!("product_eval_{:?}", index)
            }
            Evaluations::LookupNext(index) => {
                format!("product_next_eval_{:?}", index)
            }
            Evaluations::PermutedInput(index) => {
                format!("permuted_input_eval_{:?}", index)
            }
            Evaluations::PermutedInputInverse(index) => {
                format!("permuted_input_inv_eval_{:?}", index)
            }
            Evaluations::PermutedTable(index) => {
                format!("permuted_table_eval_{:?}", index)
            }
            Evaluations::PermutationsCommon(index) => {
                format!("permutation_common_{:?}", index)
            }
            // CHANGED vs upstream: added for Midnight support (trash-column evals).
            Evaluations::Trash(index) => {
                format!("trash_eval_{:?}", index)
            }
            Evaluations::VanishingS => "vanishing_s".to_string(),
            Evaluations::RandomEval => "random_eval".to_string(),
        }
    }
}

impl AikenExpression for Commitments {
    fn compile_expression(&self) -> String {
        match self {
            // CHANGED vs upstream: added for Midnight support (committed-instance commitments).
            Commitments::CommittedInstance(index) => {
                format!("committed_instance_commitment_{:?}", index)
            }
            Commitments::Advice(index) => {
                format!("a{:?}", index)
            }
            Commitments::Fixed(index) => {
                format!("f{:?}_commitment", index)
            }
            Commitments::Permutation(set) => {
                format!("permutations_committed_{}", set)
            }
            Commitments::Lookup(index) => {
                format!("lookup_commitment_{:?}", index)
            }
            Commitments::PermutedInput(index) => {
                format!("permuted_input_{:?}", index)
            }
            Commitments::PermutedTable(index) => {
                format!("permuted_table_{:?}", index)
            }
            // CHANGED vs upstream: added for Midnight support (trash-column commitments).
            Commitments::Trash(index) => {
                format!("trash_commitment_{:?}", index)
            }
            Commitments::PermutationsCommon(index) => {
                format!("p{:?}_commitment", index)
            }
            Commitments::VanishingG => VANISH_G_STR.to_string(),
            Commitments::VanishingRand => "vanishing_rand".to_string(),
        }
    }
}

trait AikenTranspiler {
    fn aiken_polynomial<W: Write>(&self, writer: &mut W) -> Result<()>;
}

impl<E: AikenTranspiler> AikenExpression for E {
    fn compile_expression(&self) -> String {
        let mut buf = BufWriter::new(Vec::new());
        let _ = self.aiken_polynomial(&mut buf);
        let bytes = buf
            .into_inner()
            .expect("failed to get bytes for compiled expression");
        String::from_utf8(bytes).expect("failed to convert bytes to string")
    }
}

// CHANGED vs upstream: implemented for the pipeline's `CircuitExpression<Scalar>`
// instead of halo2's `Expression<Scalar>`. `Selector`/`Challenge` are now unit
// variants, and `Fixed`/`Advice` carry their column index directly instead of a
// halo2 query object (so there is no more `query.index()` unwrapping).
impl AikenTranspiler for CircuitExpression<Scalar> {
    fn aiken_polynomial<W: Write>(&self, writer: &mut W) -> Result<()> {
        match self {
            CircuitExpression::Constant(scalar) => {
                write!(writer, "from_int(0x{})", hex::encode(scalar.to_bytes_be()))
            }
            CircuitExpression::Selector => {
                panic!("Selector not supported in custom gate")
            }
            CircuitExpression::Fixed(index) => write!(writer, "fixed_eval_{index}"),
            CircuitExpression::Advice(index) => write!(writer, "advice_eval_{index}"),
            CircuitExpression::Instance(_index) => {
                panic!("Instance not supported")
            }
            CircuitExpression::Challenge => {
                panic!("Challenge not supported")
            }
            CircuitExpression::Negated(a) => {
                writer.write_all(b" neg(")?;
                a.aiken_polynomial(writer)?;
                writer.write_all(b") ")
            }
            CircuitExpression::Sum(a, b) => {
                writer.write_all(b"add(")?;
                a.aiken_polynomial(writer)?;
                writer.write_all(b", ")?;
                b.aiken_polynomial(writer)?;
                writer.write_all(b")")
            }
            CircuitExpression::Product(a, b) => {
                writer.write_all(b"mul(")?;
                a.aiken_polynomial(writer)?;
                writer.write_all(b", ")?;
                b.aiken_polynomial(writer)?;
                writer.write_all(b")")
            }
            CircuitExpression::Scaled(a, f) => {
                writer.write_all(b"mul(")?;
                a.aiken_polynomial(writer)?;
                write!(writer, ", {:?})", f)
            }
        }
    }
}

impl AikenTranspiler for ExpressionG1<Scalar> {
    fn aiken_polynomial<W: Write>(&self, writer: &mut W) -> Result<()> {
        // CHANGED vs upstream: dropped the `ExpressionG1::Zero => " zero "` arm;
        // the reworked vanishing expressions no longer emit a zero G1 seed term
        // (see base_types/expression.rs and extraction_steps/vanishing.rs).
        match self {
            ExpressionG1::Sum(a, b) => {
                writer.write_all(b"addG1(")?;
                a.aiken_polynomial(writer)?;
                writer.write_all(b", ")?;
                b.aiken_polynomial(writer)?;
                writer.write_all(b")")
            }
            ExpressionG1::Scale(a, scalar) => {
                writer.write_all(b"scaleG1(")?;
                a.aiken_polynomial(writer)?;
                writer.write_all(b", ")?;
                scalar.aiken_polynomial(writer)?;
                writer.write_all(b")")
            }
            ExpressionG1::Variable(name) => {
                write!(writer, " {} ", name)
            }
            ExpressionG1::VanishingSplit(index) => {
                write!(writer, " vanishing_split_{} ", index)
            }
        }
    }
}

impl AikenTranspiler for ScalarExpression<Scalar> {
    fn aiken_polynomial<W: Write>(&self, writer: &mut W) -> Result<()> {
        match self {
            // CHANGED vs upstream: prefix the hex literal with `0x` (was `from_int({})`),
            // so the constant is parsed as hex rather than decimal by the generated Aiken.
            ScalarExpression::Constant(value) => {
                write!(writer, "from_int(0x{})", hex::encode(value.to_bytes_be()))
            }
            ScalarExpression::Variable(name) => {
                write!(writer, " {} ", name)
            }
            ScalarExpression::Negated(a) => {
                writer.write_all(b"neg(")?;
                a.aiken_polynomial(writer)?;
                writer.write_all(b")")
            }
            ScalarExpression::Sum(a, b) => {
                writer.write_all(b"add(")?;
                a.aiken_polynomial(writer)?;
                writer.write_all(b", ")?;
                b.aiken_polynomial(writer)?;
                writer.write_all(b")")
            }
            ScalarExpression::Product(a, b) => {
                writer.write_all(b"mul(")?;
                a.aiken_polynomial(writer)?;
                writer.write_all(b", ")?;
                b.aiken_polynomial(writer)?;
                writer.write_all(b")")
            }
            ScalarExpression::PowMod(a, exponent) => {
                writer.write_all(b"scale(")?;
                a.aiken_polynomial(writer)?;
                write!(writer, ", {:?})", exponent)
            }
            ScalarExpression::Advice(index) => {
                write!(writer, "advice_eval_{}", index)
            }
            ScalarExpression::Fixed(index) => {
                write!(writer, "fixed_eval_{}", index)
            }
            ScalarExpression::Instance(index) => {
                write!(writer, "instance_eval_{:?}", index)
            }
            ScalarExpression::PermutationCommon(index) => {
                write!(writer, "permutation_common_{:?}", index)
            }
        }
    }
}
