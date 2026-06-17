//! NEW vs upstream: extractor for Midnight relations.
//! The original tool only understood plain halo2 relations; this module reads
//! the VK, queries, commitments and proof steps from a Midnight relation and
//! feeds them into the pipeline's generic types (see point 3 of
//! PLUTUS_HALO2_VERIFIER_CHANGES.md).

use anyhow::{Error, Result, anyhow};
use blstrs::Scalar;
use ff::Field;
use group::Curve;
use midnight_curves::{Bls12, Fq, G1Projective};
use midnight_proofs::{
    plonk::{Any, Column, VerifyingKey},
    poly::{Rotation, commitment::PolynomialCommitmentScheme, kzg::params::ParamsKZG},
};
use midnight_zk_stdlib::MidnightVK;

use super::conversion::{
    g1_projective_from_midnight, g2_affine_from_midnight, scalar_from_midnight,
};
use super::data::{
    CircuitExpression, CircuitRepresentation, Commitments, Evaluations, RotationDescription,
    ScalarExpression,
    extraction_steps::{evaluate_permutations_terms, vanishing_expressions_midnight},
};
use super::pcs::ExtractPCS;

fn instance_max_length(instances: &[&[&[Fq]]]) -> usize {
    instances
        .iter()
        .flat_map(|instance| instance.iter().map(|instance| instance.len()))
        .max_by(Ord::cmp)
        .unwrap_or_default()
}

fn rotations<PCS>(vk: &VerifyingKey<Fq, PCS>) -> (i32, i32)
where
    PCS: ExtractPCS
        + PolynomialCommitmentScheme<Fq, Commitment = G1Projective, Parameters = ParamsKZG<Bls12>>,
{
    vk.cs()
        .instance_queries()
        .iter()
        .fold((0, 0), |(min, max), (_, rotation)| {
            if rotation.0 < min {
                (rotation.0, max)
            } else if rotation.0 > max {
                (min, rotation.0)
            } else {
                (min, max)
            }
        })
}

fn extract_proof_steps_midnight<PCS>(
    circuit_repr: &mut CircuitRepresentation<PCS>,
    vk: &VerifyingKey<Fq, PCS>,
    committed_instance_columns: usize,
) where
    PCS: PolynomialCommitmentScheme<Fq, Commitment = G1Projective, Parameters = ParamsKZG<Bls12>>
        + ExtractPCS,
{
    let chunk_len = vk.cs().degree() - 2;

    let mut advice_commitments = vec![(); vk.cs().num_advice_columns()];
    let mut challenges = vec![(); vk.cs().num_challenges()];

    let all_phases = vk.cs().advice_column_phase();
    let max_phase = all_phases
        .iter()
        .max()
        .expect("No max_phase for phases found");
    let all_phases = 0..=(*max_phase);

    for current_phase in all_phases {
        for (phase, _commitment) in vk
            .cs()
            .advice_column_phase()
            .iter()
            .zip(advice_commitments.iter_mut())
        {
            if current_phase == *phase {
                circuit_repr.extract_step(super::data::ProofExtractionSteps::AdviceCommitments);
            }
        }
        for (phase, _challenge) in vk.cs().challenge_phase().iter().zip(challenges.iter_mut()) {
            if current_phase == *phase {
                circuit_repr.extract_step(super::data::ProofExtractionSteps::SqueezeChallenge);
            }
        }
    }

    circuit_repr.extract_step(super::data::ProofExtractionSteps::Theta);

    let nb_lookups = vk.cs().lookups().len();
    (0..nb_lookups).for_each(|_| {
        circuit_repr.extract_step(super::data::ProofExtractionSteps::LookupPermuted);
    });

    circuit_repr.extract_step(super::data::ProofExtractionSteps::Beta);
    circuit_repr.extract_step(super::data::ProofExtractionSteps::Gamma);

    let nb_permutation_commitments = vk.cs().permutation().columns.chunks(chunk_len).len();
    (0..nb_permutation_commitments).for_each(|_| {
        circuit_repr.extract_step(super::data::ProofExtractionSteps::PermutationsCommitted);
    });

    (0..nb_lookups).for_each(|_| {
        circuit_repr.extract_step(super::data::ProofExtractionSteps::LookupCommitment)
    });

    circuit_repr.extract_step(super::data::ProofExtractionSteps::TrashChallenge);
    (0..vk.cs().trashcans().len()).for_each(|_| {
        circuit_repr.extract_step(super::data::ProofExtractionSteps::TrashCommitment);
    });

    circuit_repr.extract_step(super::data::ProofExtractionSteps::VanishingRand);
    circuit_repr.extract_step(super::data::ProofExtractionSteps::YCoordinate);

    (0..vk.get_domain().get_quotient_poly_degree()).for_each(|_| {
        circuit_repr.extract_step(super::data::ProofExtractionSteps::VanishingSplit);
    });

    circuit_repr.extract_step(super::data::ProofExtractionSteps::XCoordinate);

    for (column, _) in vk.cs().instance_queries().iter() {
        if column.index() < committed_instance_columns {
            circuit_repr.extract_step(super::data::ProofExtractionSteps::InstanceEval);
        }
    }

    (0..vk.cs().advice_queries().len()).for_each(|_| {
        circuit_repr.extract_step(super::data::ProofExtractionSteps::AdviceEval);
    });

    (0..vk.cs().fixed_queries().len()).for_each(|_| {
        circuit_repr.extract_step(super::data::ProofExtractionSteps::FixedEval);
    });

    circuit_repr.extract_step(super::data::ProofExtractionSteps::RandomEval);

    (0..vk.permutation().commitments().len()).for_each(|_| {
        circuit_repr.extract_step(super::data::ProofExtractionSteps::PermutationCommon);
    });

    let letters = 'a'..='z';
    let last_index = nb_permutation_commitments - 1;
    (0..nb_permutation_commitments)
        .zip(letters)
        .enumerate()
        .for_each(|(index, (_, letter))| {
            circuit_repr.extract_permutation_eval(letter);
            circuit_repr.extract_permutation_eval(letter);
            if index != last_index {
                circuit_repr.extract_permutation_eval(letter);
            }
        });

    (0..nb_lookups)
        .for_each(|_| circuit_repr.extract_step(super::data::ProofExtractionSteps::LookupEval));
    (0..vk.cs().trashcans().len())
        .for_each(|_| circuit_repr.extract_step(super::data::ProofExtractionSteps::TrashEval));
}

fn get_any_query_index<PCS>(vk: &VerifyingKey<Fq, PCS>, column: Column<Any>, at: Rotation) -> usize
where
    PCS: PolynomialCommitmentScheme<Fq>,
{
    match column.column_type() {
        Any::Advice(_) => {
            for (index, advice_query) in vk.cs().advice_queries().iter().enumerate() {
                if (advice_query.0.into(), advice_query.1) == (column, at) {
                    return index;
                }
            }
            panic!("get_advice_query_index called for non-existent query");
        }
        Any::Fixed => {
            for (index, fixed_query) in vk.cs().fixed_queries().iter().enumerate() {
                if (fixed_query.0.into(), fixed_query.1) == (column, at) {
                    return index;
                }
            }
            panic!("get_fixed_query_index called for non-existent query");
        }
        Any::Instance => {
            for (index, instance_query) in vk.cs().instance_queries().iter().enumerate() {
                if (instance_query.0.into(), instance_query.1) == (column, at) {
                    return index;
                }
            }
            panic!("get_instance_query_index called for non-existent query");
        }
    }
}

fn scalar_expression_from_circuit(
    expression: CircuitExpression<Scalar>,
) -> ScalarExpression<Scalar> {
    match expression {
        CircuitExpression::Constant(value) => ScalarExpression::Constant(value),
        CircuitExpression::Fixed(index) => ScalarExpression::Fixed(index),
        CircuitExpression::Advice(index) => ScalarExpression::Advice(index),
        CircuitExpression::Instance(index) => ScalarExpression::Instance(index),
        CircuitExpression::Negated(inner) => {
            ScalarExpression::Negated(Box::new(scalar_expression_from_circuit(*inner)))
        }
        CircuitExpression::Sum(lhs, rhs) => ScalarExpression::Sum(
            Box::new(scalar_expression_from_circuit(*lhs)),
            Box::new(scalar_expression_from_circuit(*rhs)),
        ),
        CircuitExpression::Product(lhs, rhs) => ScalarExpression::Product(
            Box::new(scalar_expression_from_circuit(*lhs)),
            Box::new(scalar_expression_from_circuit(*rhs)),
        ),
        CircuitExpression::Scaled(inner, factor) => ScalarExpression::Product(
            Box::new(scalar_expression_from_circuit(*inner)),
            Box::new(ScalarExpression::Constant(factor)),
        ),
        CircuitExpression::Selector | CircuitExpression::Challenge => {
            panic!("unsupported trash expression component")
        }
    }
}

fn permutation_terms_both_midnight<PCS>(
    circuit_repr: &mut CircuitRepresentation<PCS>,
    vk: &VerifyingKey<Fq, PCS>,
    chunk_len: usize,
    sets: &[char],
    nb_permutation_common: usize,
) where
    PCS: PolynomialCommitmentScheme<Fq, Commitment = G1Projective, Parameters = ParamsKZG<Bls12>>
        + ExtractPCS,
{
    use super::data::{ScalarExpression, constants::*};

    sets.iter()
        .zip(vk.cs().permutation().columns.chunks(chunk_len))
        .zip(1..=nb_permutation_common)
        .enumerate()
        .for_each(|(chunk_index, ((set, columns), _))| {
            columns.iter().enumerate().for_each(|(idx, &column)| {
                let permutation_index = (chunk_index * chunk_len) + idx + 1;
                let eval_index = get_any_query_index(vk, column, Rotation::cur()) + 1;
                match column.column_type() {
                    Any::Advice(_) => {
                        let term = ScalarExpression::Sum(
                            Box::new(ScalarExpression::Sum(
                                Box::new(ScalarExpression::Advice(eval_index)),
                                Box::new(ScalarExpression::Product(
                                    Box::new(ScalarExpression::Variable(BETA_STR.to_string())),
                                    Box::new(ScalarExpression::PermutationCommon(
                                        permutation_index,
                                    )),
                                )),
                            )),
                            Box::new(ScalarExpression::Variable(GAMMA_STR.to_string())),
                        );
                        circuit_repr.expressions.permutation_left(*set, term);
                    }
                    Any::Fixed => {
                        let term = ScalarExpression::Sum(
                            Box::new(ScalarExpression::Sum(
                                Box::new(ScalarExpression::Fixed(eval_index)),
                                Box::new(ScalarExpression::Product(
                                    Box::new(ScalarExpression::Variable(BETA_STR.to_string())),
                                    Box::new(ScalarExpression::PermutationCommon(
                                        permutation_index,
                                    )),
                                )),
                            )),
                            Box::new(ScalarExpression::Variable(GAMMA_STR.to_string())),
                        );
                        circuit_repr.expressions.permutation_left(*set, term);
                    }
                    Any::Instance => {
                        let term = ScalarExpression::Sum(
                            Box::new(ScalarExpression::Sum(
                                Box::new(ScalarExpression::Instance(eval_index)),
                                Box::new(ScalarExpression::Product(
                                    Box::new(ScalarExpression::Variable(BETA_STR.to_string())),
                                    Box::new(ScalarExpression::PermutationCommon(
                                        permutation_index,
                                    )),
                                )),
                            )),
                            Box::new(ScalarExpression::Variable(GAMMA_STR.to_string())),
                        );
                        circuit_repr.expressions.permutation_left(*set, term);
                    }
                }
            });

            columns.iter().enumerate().for_each(|(idx, &column)| {
                let power = chunk_index * chunk_len + idx;
                let eval_index = get_any_query_index(vk, column, Rotation::cur()) + 1;
                match column.column_type() {
                    Any::Advice(_) => {
                        let term = ScalarExpression::Sum(
                            Box::new(ScalarExpression::Sum(
                                Box::new(ScalarExpression::Advice(eval_index)),
                                Box::new(ScalarExpression::Product(
                                    Box::new(ScalarExpression::Product(
                                        Box::new(ScalarExpression::Variable(BETA_STR.to_string())),
                                        Box::new(ScalarExpression::Variable(X_STR.to_string())),
                                    )),
                                    Box::new(ScalarExpression::PowMod(
                                        Box::new(ScalarExpression::Variable(
                                            SCALAR_DELTA_STR.to_string(),
                                        )),
                                        power,
                                    )),
                                )),
                            )),
                            Box::new(ScalarExpression::Variable(GAMMA_STR.to_string())),
                        );
                        circuit_repr.expressions.permutation_right(*set, term);
                    }
                    Any::Fixed => {
                        let term = ScalarExpression::Sum(
                            Box::new(ScalarExpression::Sum(
                                Box::new(ScalarExpression::Fixed(eval_index)),
                                Box::new(ScalarExpression::Product(
                                    Box::new(ScalarExpression::Product(
                                        Box::new(ScalarExpression::Variable(BETA_STR.to_string())),
                                        Box::new(ScalarExpression::Variable(X_STR.to_string())),
                                    )),
                                    Box::new(ScalarExpression::PowMod(
                                        Box::new(ScalarExpression::Variable(
                                            SCALAR_DELTA_STR.to_string(),
                                        )),
                                        power,
                                    )),
                                )),
                            )),
                            Box::new(ScalarExpression::Variable(GAMMA_STR.to_string())),
                        );
                        circuit_repr.expressions.permutation_right(*set, term);
                    }
                    Any::Instance => {
                        let term = ScalarExpression::Sum(
                            Box::new(ScalarExpression::Sum(
                                Box::new(ScalarExpression::Instance(eval_index)),
                                Box::new(ScalarExpression::Product(
                                    Box::new(ScalarExpression::Product(
                                        Box::new(ScalarExpression::Variable(BETA_STR.to_string())),
                                        Box::new(ScalarExpression::Variable(X_STR.to_string())),
                                    )),
                                    Box::new(ScalarExpression::PowMod(
                                        Box::new(ScalarExpression::Variable(
                                            SCALAR_DELTA_STR.to_string(),
                                        )),
                                        power,
                                    )),
                                )),
                            )),
                            Box::new(ScalarExpression::Variable(GAMMA_STR.to_string())),
                        );
                        circuit_repr.expressions.permutation_right(*set, term);
                    }
                }
            });
        });
}

pub fn extract_circuit_midnight<PCS>(
    params: &ParamsKZG<Bls12>,
    vk: &VerifyingKey<Fq, PCS>,
    instances: &[&[&[Fq]]],
) -> Result<CircuitRepresentation<PCS>, Error>
where
    PCS: ExtractPCS
        + PolynomialCommitmentScheme<Fq, Commitment = G1Projective, Parameters = ParamsKZG<Bls12>>,
{
    let chunk_len = vk.cs().degree() - 2;

    for instance in instances.iter() {
        if instance.len() != vk.cs().num_instance_columns() {
            return Err(anyhow!(
                "Invalid number of instances, #instances ({}) != #instance_columns ({})",
                instance.len(),
                vk.cs().num_instance_columns()
            ));
        }
    }

    if instances.len() > 1 {
        return Err(anyhow!(
            "Only one proof can be processed at a time, {} were received",
            instances.len()
        ));
    }

    let mut circuit_description = CircuitRepresentation::<PCS>::new();

    let (min_rotation, max_rotation) = rotations(vk);
    let max_instance_len = instance_max_length(instances) as i32;
    let rotations = -max_rotation..max_instance_len + min_rotation.abs();

    circuit_description
        .proof_instantiation_data
        .fixed_commitments = vk
        .fixed_commitments()
        .iter()
        .map(g1_projective_from_midnight)
        .collect::<Result<_>>()?;
    circuit_description
        .proof_instantiation_data
        .permutation_commitments = vk
        .permutation()
        .commitments()
        .iter()
        .map(g1_projective_from_midnight)
        .collect::<Result<_>>()?;
    let committed_instance_columns = instances[0]
        .iter()
        .take_while(|column| column.is_empty())
        .count();
    circuit_description
        .proof_instantiation_data
        .committed_instance_commitments = instances[0]
        .iter()
        .take(committed_instance_columns)
        .map(|values| {
            let mut poly = vk.get_domain().empty_lagrange();
            for (poly_eval, value) in poly.iter_mut().zip(values.iter()) {
                *poly_eval = *value;
            }
            let commitment = PCS::commit_lagrange(params, &poly);
            g1_projective_from_midnight(&commitment)
        })
        .collect::<Result<_>>()?;
    circuit_description
        .proof_instantiation_data
        .instance_column_lengths = instances[0].iter().map(|column| column.len()).collect();
    circuit_description
        .proof_instantiation_data
        .instance_query_columns = vk
        .cs()
        .instance_queries()
        .iter()
        .map(|(column, _)| column.index() + 1)
        .collect();
    circuit_description
        .proof_instantiation_data
        .instance_query_rotations = vk
        .cs()
        .instance_queries()
        .iter()
        .map(|(_, rotation)| rotation.0)
        .collect();
    circuit_description.proof_instantiation_data.omega =
        scalar_from_midnight(vk.get_domain().get_omega());
    circuit_description.proof_instantiation_data.inverted_omega =
        scalar_from_midnight(vk.get_domain().get_omega_inv());
    circuit_description
        .proof_instantiation_data
        .barycentric_weight = Scalar::from(vk.n())
        .invert()
        .expect("there should be an inverse");
    circuit_description.proof_instantiation_data.s_g2 =
        g2_affine_from_midnight(params.s_g2().to_affine())?;
    circuit_description
        .proof_instantiation_data
        .omega_rotation_count_for_instances = rotations.len();
    circuit_description.proof_instantiation_data.n_coefficient = vk.n();
    circuit_description
        .proof_instantiation_data
        .blinding_factors = vk.cs().blinding_factors();
    circuit_description
        .proof_instantiation_data
        .transcript_representation = scalar_from_midnight(vk.transcript_repr());
    circuit_description
        .proof_instantiation_data
        .public_inputs_count = instances[0]
        .iter()
        .skip(committed_instance_columns)
        .map(|column| column.len())
        .sum();

    for instance in instances.iter() {
        for instance in instance.iter().skip(committed_instance_columns) {
            for _value in instance.iter() {
                circuit_description.increment_public_inputs();
            }
        }
    }

    extract_proof_steps_midnight(&mut circuit_description, vk, committed_instance_columns);

    let sets = circuit_description.compute_sets();
    let nb_permutation_common = circuit_description.nb_permutation_common();
    let nb_lookup_commitments = circuit_description.nb_lookup_commitments();

    vk.cs().gates().iter().for_each(|gate| {
        gate.polynomials().iter().for_each(|poly| {
            circuit_description.expressions.gate(poly.clone().into());
        })
    });

    vk.cs().lookups().iter().for_each(|argument| {
        let inputs = argument
            .input_expressions()
            .iter()
            .cloned()
            .map(Into::into)
            .collect();
        let tables = argument
            .table_expressions()
            .iter()
            .cloned()
            .map(Into::into)
            .collect();
        circuit_description.expressions.lookup(inputs, tables);
    });

    for (index, argument) in vk.cs().trashcans().iter().enumerate() {
        let compressed_expressions = argument
            .constraint_expressions()
            .iter()
            .cloned()
            .map(Into::into)
            .map(scalar_expression_from_circuit)
            .fold(ScalarExpression::Constant(Scalar::ZERO), |acc, eval| {
                ScalarExpression::Sum(
                    Box::new(ScalarExpression::Product(
                        Box::new(acc),
                        Box::new(ScalarExpression::Variable("trash_challenge".to_string())),
                    )),
                    Box::new(eval),
                )
            });
        let selector = scalar_expression_from_circuit(argument.selector().clone().into());
        let expression = ScalarExpression::Sum(
            Box::new(compressed_expressions),
            Box::new(ScalarExpression::Negated(Box::new(
                ScalarExpression::Product(
                    Box::new(ScalarExpression::Sum(
                        Box::new(ScalarExpression::Constant(Scalar::ONE)),
                        Box::new(ScalarExpression::Negated(Box::new(selector))),
                    )),
                    Box::new(ScalarExpression::Variable(format!(
                        "trash_eval_{}",
                        index + 1
                    ))),
                ),
            ))),
        );
        circuit_description.expressions.trash(expression);
    }

    evaluate_permutations_terms(&mut circuit_description, &sets);
    permutation_terms_both_midnight(
        &mut circuit_description,
        vk,
        chunk_len,
        &sets,
        nb_permutation_common,
    );
    vanishing_expressions_midnight(&mut circuit_description);

    vk.cs()
        .advice_queries()
        .iter()
        .enumerate()
        .for_each(|(query_index, &(column, at))| {
            circuit_description
                .queries
                .advice(column.index() + 1, query_index + 1, at.0);
        });

    vk.cs()
        .instance_queries()
        .iter()
        .enumerate()
        .filter(|(_, (column, _))| column.index() < committed_instance_columns)
        .for_each(|(query_index, &(column, at))| {
            circuit_description.queries.committed_instance(
                column.index() + 1,
                query_index + 1,
                at.0,
            );
        });

    vk.cs()
        .fixed_queries()
        .iter()
        .enumerate()
        .for_each(|(query_index, &(column, at))| {
            circuit_description
                .queries
                .fixed(column.index() + 1, query_index + 1, at.0);
        });

    for set in sets.iter() {
        circuit_description
            .queries
            .permutation(*set, 1, RotationDescription::Current);
        circuit_description
            .queries
            .permutation(*set, 2, RotationDescription::Next);
    }
    for set in sets.iter().rev().skip(1) {
        circuit_description
            .queries
            .permutation(*set, 3, RotationDescription::Last);
    }

    (0..nb_permutation_common).for_each(|idx| {
        circuit_description.queries.common(idx + 1);
    });

    circuit_description.queries.vanishing_queries();

    (0..nb_lookup_commitments).for_each(|idx| {
        circuit_description.queries.lookup(
            Commitments::Lookup(idx + 1),
            Evaluations::Lookup(idx + 1),
            RotationDescription::Current,
        );
        circuit_description.queries.lookup(
            Commitments::PermutedInput(idx + 1),
            Evaluations::PermutedInput(idx + 1),
            RotationDescription::Current,
        );
        circuit_description.queries.lookup(
            Commitments::PermutedTable(idx + 1),
            Evaluations::PermutedTable(idx + 1),
            RotationDescription::Current,
        );
        circuit_description.queries.lookup(
            Commitments::PermutedInput(idx + 1),
            Evaluations::PermutedInputInverse(idx + 1),
            RotationDescription::Previous,
        );
        circuit_description.queries.lookup(
            Commitments::Lookup(idx + 1),
            Evaluations::LookupNext(idx + 1),
            RotationDescription::Next,
        );
    });

    (0..vk.cs().trashcans().len()).for_each(|idx| {
        circuit_description.queries.trash(idx + 1);
    });

    PCS::extract_pcs(&mut circuit_description);

    Ok(circuit_description)
}

pub fn extract_circuit_from_midnight_vk(
    params: &ParamsKZG<Bls12>,
    vk: &MidnightVK,
    instances: &[&[&[Fq]]],
) -> Result<CircuitRepresentation<midnight_proofs::poly::kzg::KZGCommitmentScheme<Bls12>>, Error> {
    extract_circuit_midnight(params, vk.vk(), instances)
}
