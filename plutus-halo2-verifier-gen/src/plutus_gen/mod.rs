//! Module for generating Aiken verifiers for a given circuit
//! the correct mustashe templates and emitting them to the correct locations.
pub(crate) mod adjusted_types;
pub use adjusted_types::CardanoFriendlyBlake2b;
pub(crate) mod emitters;
pub(crate) mod extraction;
pub mod mithril_stm_proof_export;
pub use emitters::{
    aiken::{emit_verifier_code as emit_verifier_aiken, emit_vk_code as emit_vk_aiken},
};
pub use extraction::pcs::ExtractPCS;
pub use extraction::pcs::PCSType;
pub use extraction::{
    CircuitRepresentation, extract_circuit, extract_circuit_from_midnight_vk,
    extract_circuit_midnight,
};
pub(crate) mod proof_serialization;
pub use mithril_stm_proof_export::{
    build_mithril_stm_proof_export, export_mithril_stm_proof_export, validate_proof_export_file,
    validate_compatible_bundle_file, validate_mithril_stm_proof_export, InputBundle,
    MithrilStmProofExport,
};
pub use proof_serialization::{export_proof, export_public_inputs, serialize_proof};

use anyhow::{Context as _, Result};
use std::path::Path;

use blstrs::{Bls12, G1Projective, Scalar};
use halo2_proofs::plonk::VerifyingKey;
use halo2_proofs::poly::commitment::PolynomialCommitmentScheme;
use halo2_proofs::poly::kzg::params::ParamsKZG;
use midnight_curves::{Bls12 as MidnightBls12, Fq as MidnightScalar};
use midnight_proofs::poly::{kzg::KZGCommitmentScheme as MidnightKZGCommitmentScheme, kzg::params::ParamsKZG as MidnightParamsKZG};
use midnight_zk_stdlib::MidnightVK;

use crate::plutus_gen::extraction::conversion::scalar_from_midnight;

fn emit_aiken_verifier_to_paths<PCS: ExtractPCS>(
    circuit_representation: &CircuitRepresentation<PCS>,
    public_inputs: Vec<Scalar>,
    test_proofs: Option<(Vec<u8>, Vec<u8>)>,
    verifier_file: &Path,
    vk_file: &Path,
    profiler_template: Option<&Path>,
) -> Result<()> {
    let verifier_template_file = match PCS::pcs_type() {
        PCSType::GWC19 => Path::new("aiken-verifier/templates/verification_gwc19.hbs"),
        PCSType::Halo2MultiOpen => Path::new("aiken-verifier/templates/verification_h2.hbs"),
    };

    emit_verifier_aiken(
        verifier_template_file,
        verifier_file,
        profiler_template,
        circuit_representation,
        test_proofs.map(|(p, invalid_p)| (p, invalid_p, public_inputs)),
    )
    .context("Failed to emit the verifier code for aiken")?;
    emit_vk_aiken(
        Path::new("aiken-verifier/templates/vk_constants.hbs"),
        vk_file,
        circuit_representation,
    )
    .context("Failed to emit the verifier key constants for aiken")?;

    Ok(())
}

fn emit_aiken_verifier_from_representation<PCS: ExtractPCS>(
    circuit_representation: &CircuitRepresentation<PCS>,
    public_inputs: Vec<Scalar>,
    test_proofs: Option<(Vec<u8>, Vec<u8>)>,
) -> Result<()> {
    emit_aiken_verifier_to_paths(
        circuit_representation,
        public_inputs,
        test_proofs,
        Path::new("aiken-verifier/aiken_halo2/lib/proof_verifier.ak"),
        Path::new("aiken-verifier/aiken_halo2/lib/verifier_key.ak"),
        Some(Path::new("aiken-verifier/templates/profiler.hbs")),
    )
}

/// Generates an Aiken verifier for a specific circuit and saves the generated
/// code to the specified file paths.
/// Uses different KZG type based on used PolynomialCommitmentScheme.
///
/// # Arguments
/// * `params` - Parameters for the KZG polynomial commitment scheme
/// * `vk` - Verifying key for the circuit, it can have either GWC19, or halo2 based KZG
/// * `instances` - Public inputs to the circuit
///
/// # Returns
/// * `Result<(), String>` - Ok(()) if the generation is successful, Err(String) otherwise
pub fn generate_aiken_verifier<PCS>(
    params: &ParamsKZG<Bls12>,
    vk: &VerifyingKey<Scalar, PCS>,
    instances: &[&[&[Scalar]]],
    test_proofs: Option<(Vec<u8>, Vec<u8>)>,
) -> Result<()>
where
    PCS: ExtractPCS + PolynomialCommitmentScheme<Scalar, Commitment = G1Projective>,
{
    let circuit_representation = extract_circuit(params, vk, instances)
        .context("Failed to extract the circuit representation")?;
    emit_aiken_verifier_from_representation(
        &circuit_representation,
        instances[0][0].to_vec(),
        test_proofs,
    )
}

/// Generates an Aiken verifier from a Midnight `Relation`/`MidnightVK` pair.
///
/// Midnight proofs can contain committed instance columns that are transcripted
/// as curve points before the regular scalar instance columns. This wrapper
/// mirrors that layout and only forwards the non-committed instance scalars as
/// public inputs to the generated Aiken tests.
pub fn generate_aiken_verifier_midnight(
    params: &MidnightParamsKZG<MidnightBls12>,
    vk: &MidnightVK,
    instances: &[&[&[MidnightScalar]]],
    test_proofs: Option<(Vec<u8>, Vec<u8>)>,
) -> Result<()> {
    let circuit_representation =
        extract_circuit_midnight::<MidnightKZGCommitmentScheme<MidnightBls12>>(
            params,
            vk.vk(),
            instances,
        )
        .context("Failed to extract the midnight circuit representation")?;
    let committed_instance_columns = circuit_representation
        .proof_instantiation_data
        .committed_instance_commitments
        .len();
    let public_inputs = instances[0]
        .iter()
        .skip(committed_instance_columns)
        .flat_map(|column| column.iter().copied())
        .map(scalar_from_midnight)
        .collect();

    emit_aiken_verifier_from_representation(&circuit_representation, public_inputs, test_proofs)
}

#[cfg(test)]
mod tests {
    use super::{
        emit_aiken_verifier_to_paths, extract_circuit_midnight, generate_aiken_verifier_midnight,
    };
    use crate::plutus_gen::adjusted_types::CardanoFriendlyBlake2b;
    use crate::circuits::mithril_stm::{generate_stm_proof, circuit::StmCircuit, types::CircuitBase};
    use crate::plutus_gen::extraction::conversion::{g1_projective_from_midnight, scalar_from_midnight};
    use crate::plutus_gen::extraction::data::{
        Commitments, Evaluations, ProofExtractionSteps, RotationDescription,
    };
    use crate::plutus_gen::ExtractPCS;
    use crate::plutus_gen::extraction::pcs::kzg::HMOSteps;
    use blstrs::{G1Projective as BlstrsG1Projective, Scalar as BlstrsScalar};
    use ff::{Field, PrimeField};
    use group::{Group, GroupEncoding};
    use midnight_curves::{Bls12 as MidnightBls12, Fq as MidnightScalar, G1Projective as MidnightG1Projective};
    use midnight_proofs::plonk::prepare as prepare_midnight_verifier;
    use midnight_proofs::poly::{kzg::KZGCommitmentScheme as MidnightKZGCommitmentScheme, kzg::params::ParamsKZG as MidnightParamsKZG};
    use midnight_proofs::transcript::{CircuitTranscript, Transcript};
    use midnight_zk_stdlib::{self as zk, MidnightCircuit};
    use mithril_stm::Parameters;
    use rand_chacha::ChaCha20Rng;
    use rand_core::SeedableRng;
    use std::{
        collections::HashMap,
        fs,
        path::PathBuf,
        sync::OnceLock,
        time::{SystemTime, UNIX_EPOCH},
    };

    #[derive(Clone)]
    struct StmFixture {
        srs: MidnightParamsKZG<MidnightBls12>,
        vk: zk::MidnightVK,
        instance: Vec<MidnightScalar>,
        proof: Vec<u8>,
    }

    type MidnightGuardTerms<'a> = Vec<(&'a MidnightScalar, &'a MidnightG1Projective)>;

    fn stm_fixture() -> StmFixture {
        static FIXTURE: OnceLock<StmFixture> = OnceLock::new();

        FIXTURE
            .get_or_init(|| {
                let params = Parameters {
                    m: 200,
                    k: 5,
                    phi_f: 0.8,
                };
                let generated = generate_stm_proof(params, 10, [7u8; 32], [2u8; 32]).unwrap();
                let circuit =
                    StmCircuit::try_new(&generated.params, generated.merkle_tree_depth).unwrap();
                let min_k = MidnightCircuit::from_relation(&circuit).min_k();
                let srs = MidnightParamsKZG::<MidnightBls12>::unsafe_setup(
                    min_k,
                    ChaCha20Rng::seed_from_u64(42),
                );
                let vk = zk::setup_vk(&srs, &circuit);
                let pk = zk::setup_pk(&circuit, &vk);
                let proving_instance = generated.instance;
                let proof = zk::prove::<StmCircuit, CardanoFriendlyBlake2b>(
                    &srs,
                    &pk,
                    &circuit,
                    &proving_instance,
                    generated.witness,
                    ChaCha20Rng::seed_from_u64(42),
                )
                .unwrap();
                zk::verify::<StmCircuit, CardanoFriendlyBlake2b>(
                    &srs.verifier_params(),
                    &vk,
                    &proving_instance,
                    None,
                    &proof,
                )
                .unwrap();
                let instance = vec![
                    CircuitBase::from(proving_instance.0),
                    CircuitBase::from(proving_instance.1),
                ];

                StmFixture {
                    srs,
                    vk,
                    instance,
                    proof,
                }
            })
            .clone()
    }

    fn stm_instance_columns(
        instance: &[MidnightScalar],
    ) -> ([MidnightScalar; 0], [MidnightScalar; 2]) {
        ([], [instance[0], instance[1]])
    }

    fn extract_generated_valid_proof_hex(source: &str) -> String {
        let marker = "test check_valid_proof_valid_public_inputs() {\n    expect verifier(#\"";
        let start = source
            .find(marker)
            .expect("generated proof_verifier should contain valid-proof test")
            + marker.len();
        let end = source[start..]
            .find('"')
            .expect("valid-proof test should close proof literal");
        source[start..start + end].to_string()
    }

    #[derive(Clone, Debug)]
    struct ParsedMidnightProof {
        commitments: HashMap<Commitments, BlstrsG1Projective>,
        evaluations: HashMap<Evaluations, BlstrsScalar>,
        x: BlstrsScalar,
        x1: BlstrsScalar,
        x2: BlstrsScalar,
        x3: BlstrsScalar,
        x4: BlstrsScalar,
        f_commitment: BlstrsG1Projective,
        pi_term: BlstrsG1Projective,
        proof_x3_q_evals: Vec<BlstrsScalar>,
    }

    fn blstrs_point_from_midnight(point: MidnightG1Projective) -> BlstrsG1Projective {
        BlstrsG1Projective::from(
            g1_projective_from_midnight(&point)
                .expect("midnight proof point should convert into blstrs"),
        )
    }

    fn aggregate_vanishing_splits_reverse(
        vanishing_splits: &[BlstrsG1Projective],
        xn: BlstrsScalar,
    ) -> BlstrsG1Projective {
        let mut vanishing_g = *vanishing_splits
            .last()
            .expect("midnight proof should contain vanishing split commitments");
        for split in vanishing_splits.iter().rev().skip(1) {
            vanishing_g = (vanishing_g * xn) + split;
        }
        vanishing_g
    }

    fn scalar_from_hex_be(hex_scalar: &str) -> BlstrsScalar {
        let mut bytes = hex::decode(hex_scalar).expect("scalar hex should decode");
        bytes.reverse();
        let mut repr = <BlstrsScalar as PrimeField>::Repr::default();
        repr.as_mut().copy_from_slice(&bytes);
        Option::<BlstrsScalar>::from(BlstrsScalar::from_repr(repr))
            .expect("hex scalar should fit into blstrs::Scalar")
    }

    fn init_stm_transcript(
        circuit: &crate::plutus_gen::CircuitRepresentation<
            MidnightKZGCommitmentScheme<MidnightBls12>,
        >,
        vk: &zk::MidnightVK,
        instances: &[&[&[MidnightScalar]]],
        proof: &[u8],
    ) -> CircuitTranscript<CardanoFriendlyBlake2b> {
        let mut transcript = CircuitTranscript::<CardanoFriendlyBlake2b>::init_from_bytes(proof);
        transcript.common(&vk.vk().transcript_repr()).unwrap();

        for commitment in &circuit
            .proof_instantiation_data
            .committed_instance_commitments
        {
            let bytes = commitment.to_bytes();
            let mut repr = <MidnightG1Projective as GroupEncoding>::Repr::default();
            repr.as_mut().copy_from_slice(bytes.as_ref());
            let point = Option::<MidnightG1Projective>::from(
                MidnightG1Projective::from_bytes(&repr),
            )
            .unwrap();
            transcript.common(&point).unwrap();
        }

        for column in instances[0].iter().skip(
            circuit
                .proof_instantiation_data
                .committed_instance_commitments
                .len(),
        ) {
            transcript
                .common(&MidnightScalar::from(column.len() as u64))
                .unwrap();
            for value in *column {
                transcript.common(value).unwrap();
            }
        }

        transcript
    }

    fn powers(count: usize, base: BlstrsScalar) -> Vec<BlstrsScalar> {
        let mut result = Vec::with_capacity(count);
        let mut current = BlstrsScalar::ONE;
        for _ in 0..count {
            result.push(current);
            current *= base;
        }
        result
    }

    fn rotate_omega(
        omega: BlstrsScalar,
        omega_inv: BlstrsScalar,
        value: BlstrsScalar,
        rotation: i32,
    ) -> BlstrsScalar {
        if rotation < 0 {
            value
                * omega_inv.pow_vartime([(rotation.unsigned_abs()) as u64, 0, 0, 0])
        } else {
            value * omega.pow_vartime([rotation as u64, 0, 0, 0])
        }
    }

    fn rotate_omegas(
        omega: BlstrsScalar,
        omega_inv: BlstrsScalar,
        from: i32,
        to: i32,
    ) -> Vec<BlstrsScalar> {
        (from..=to)
            .map(|rotation| rotate_omega(omega, omega_inv, BlstrsScalar::ONE, rotation))
            .collect()
    }

    fn lagrange_polynomial_basis(
        x: BlstrsScalar,
        xn: BlstrsScalar,
        barycentric_weight: BlstrsScalar,
        rotations: &[BlstrsScalar],
    ) -> Vec<BlstrsScalar> {
        let common = (xn - BlstrsScalar::ONE) * barycentric_weight;
        rotations
            .iter()
            .map(|rotated_omega| {
                common
                    * rotated_omega
                    * (x - rotated_omega)
                        .invert()
                        .expect("lagrange basis denominator should be invertible")
            })
            .collect()
    }

    fn inner_product(values: &[BlstrsScalar], weights: &[BlstrsScalar]) -> BlstrsScalar {
        values
            .iter()
            .zip(weights.iter())
            .fold(BlstrsScalar::ZERO, |acc, (value, weight)| {
                acc + (*value * *weight)
            })
    }

    fn lagrange_evaluation(
        points: &[BlstrsScalar],
        evals: &[BlstrsScalar],
        x: BlstrsScalar,
    ) -> BlstrsScalar {
        assert_eq!(points.len(), evals.len());

        let mut result = BlstrsScalar::ZERO;
        for (index, (&point_i, &eval_i)) in points.iter().zip(evals.iter()).enumerate() {
            let mut numerator = BlstrsScalar::ONE;
            let mut denominator = BlstrsScalar::ONE;

            for (other_index, &point_j) in points.iter().enumerate() {
                if index == other_index {
                    continue;
                }
                numerator *= x - point_j;
                denominator *= point_i - point_j;
            }

            result += eval_i
                * numerator
                * denominator
                    .invert()
                    .expect("lagrange denominator should be invertible");
        }

        result
    }

    fn resolve_rotation_point(
        rotation: RotationDescription,
        x: BlstrsScalar,
        x_prev: BlstrsScalar,
        x_next: BlstrsScalar,
        x_last: BlstrsScalar,
    ) -> BlstrsScalar {
        match rotation {
            RotationDescription::Last => x_last,
            RotationDescription::Previous => x_prev,
            RotationDescription::Current => x,
            RotationDescription::Next => x_next,
        }
    }

    fn eval_circuit_expression(
        expression: &crate::plutus_gen::extraction::data::CircuitExpression<BlstrsScalar>,
        evaluations: &HashMap<Evaluations, BlstrsScalar>,
        instance_evaluations: &HashMap<usize, BlstrsScalar>,
    ) -> BlstrsScalar {
        use crate::plutus_gen::extraction::data::CircuitExpression;

        match expression {
            CircuitExpression::Constant(value) => *value,
            CircuitExpression::Fixed(index) => *evaluations
                .get(&Evaluations::Fixed(*index))
                .unwrap_or_else(|| panic!("missing fixed evaluation {index}")),
            CircuitExpression::Advice(index) => *evaluations
                .get(&Evaluations::Advice(*index))
                .unwrap_or_else(|| panic!("missing advice evaluation {index}")),
            CircuitExpression::Instance(index) => *instance_evaluations
                .get(index)
                .unwrap_or_else(|| panic!("missing instance evaluation {index}")),
            CircuitExpression::Negated(inner) => {
                -eval_circuit_expression(inner, evaluations, instance_evaluations)
            }
            CircuitExpression::Sum(lhs, rhs) => {
                eval_circuit_expression(lhs, evaluations, instance_evaluations)
                    + eval_circuit_expression(rhs, evaluations, instance_evaluations)
            }
            CircuitExpression::Product(lhs, rhs) => {
                eval_circuit_expression(lhs, evaluations, instance_evaluations)
                    * eval_circuit_expression(rhs, evaluations, instance_evaluations)
            }
            CircuitExpression::Scaled(inner, factor) => {
                eval_circuit_expression(inner, evaluations, instance_evaluations) * factor
            }
            CircuitExpression::Selector | CircuitExpression::Challenge => {
                panic!("selector/challenge not expected in compiled verifier expression")
            }
        }
    }

    fn eval_scalar_expression(
        expression: &crate::plutus_gen::extraction::data::ScalarExpression<BlstrsScalar>,
        evaluations: &HashMap<Evaluations, BlstrsScalar>,
        instance_evaluations: &HashMap<usize, BlstrsScalar>,
        variables: &HashMap<&'static str, BlstrsScalar>,
    ) -> BlstrsScalar {
        use crate::plutus_gen::extraction::data::ScalarExpression;

        match expression {
            ScalarExpression::Constant(value) => *value,
            ScalarExpression::Variable(name) => *variables
                .get(name.as_str())
                .unwrap_or_else(|| panic!("missing scalar variable {name}")),
            ScalarExpression::Advice(index) => *evaluations
                .get(&Evaluations::Advice(*index))
                .unwrap_or_else(|| panic!("missing advice evaluation {index}")),
            ScalarExpression::Fixed(index) => *evaluations
                .get(&Evaluations::Fixed(*index))
                .unwrap_or_else(|| panic!("missing fixed evaluation {index}")),
            ScalarExpression::Instance(index) => *instance_evaluations
                .get(index)
                .unwrap_or_else(|| panic!("missing instance evaluation {index}")),
            ScalarExpression::PermutationCommon(index) => *evaluations
                .get(&Evaluations::PermutationsCommon(*index))
                .unwrap_or_else(|| panic!("missing permutation common evaluation {index}")),
            ScalarExpression::Negated(inner) => {
                -eval_scalar_expression(inner, evaluations, instance_evaluations, variables)
            }
            ScalarExpression::Sum(lhs, rhs) => {
                eval_scalar_expression(lhs, evaluations, instance_evaluations, variables)
                    + eval_scalar_expression(rhs, evaluations, instance_evaluations, variables)
            }
            ScalarExpression::Product(lhs, rhs) => {
                eval_scalar_expression(lhs, evaluations, instance_evaluations, variables)
                    * eval_scalar_expression(rhs, evaluations, instance_evaluations, variables)
            }
            ScalarExpression::PowMod(inner, exponent) => eval_scalar_expression(
                inner,
                evaluations,
                instance_evaluations,
                variables,
            )
            .pow_vartime([*exponent as u64, 0, 0, 0]),
        }
    }

    fn parse_midnight_stm_proof(
        circuit: &crate::plutus_gen::CircuitRepresentation<
            MidnightKZGCommitmentScheme<MidnightBls12>,
        >,
        vk: &zk::MidnightVK,
        instances: &[&[&[MidnightScalar]]],
        proof: &[u8],
    ) -> ParsedMidnightProof {
        let mut transcript = init_stm_transcript(circuit, vk, instances, proof);
        let sets = circuit.compute_sets();

        let mut advice_commitment_index = 0usize;
        let mut lookup_index = 0usize;
        let mut lookup_commitment_index = 0usize;
        let mut trash_commitment_index = 0usize;
        let mut permutation_commitment_index = 0usize;
        let mut vanishing_splits = Vec::with_capacity(circuit.nb_vanishing_splits());

        let mut instance_eval_index = 0usize;
        let mut advice_eval_index = 0usize;
        let mut fixed_eval_index = 0usize;
        let mut permutation_common_index = 0usize;
        let mut permutation_eval_index: HashMap<char, usize> = HashMap::new();
        let mut lookup_eval_index = 0usize;
        let mut trash_eval_index = 0usize;

        let mut commitments = HashMap::new();
        let mut evaluations = HashMap::new();
        let mut theta = None;
        let mut beta = None;
        let mut gamma = None;
        let mut y = None;
        let mut trash_challenge = None;
        let mut x = None;

        for step in &circuit.proof_extraction_steps {
            match step {
                ProofExtractionSteps::AdviceCommitments => {
                    advice_commitment_index += 1;
                    let point: MidnightG1Projective = transcript.read().unwrap();
                    commitments.insert(
                        Commitments::Advice(advice_commitment_index),
                        blstrs_point_from_midnight(point),
                    );
                }
                ProofExtractionSteps::PermutationsCommitted => {
                    let set = sets[permutation_commitment_index];
                    permutation_commitment_index += 1;
                    let point: MidnightG1Projective = transcript.read().unwrap();
                    commitments.insert(
                        Commitments::Permutation(set),
                        blstrs_point_from_midnight(point),
                    );
                }
                ProofExtractionSteps::LookupPermuted => {
                    lookup_index += 1;
                    let input: MidnightG1Projective = transcript.read().unwrap();
                    let table: MidnightG1Projective = transcript.read().unwrap();
                    commitments.insert(
                        Commitments::PermutedInput(lookup_index),
                        blstrs_point_from_midnight(input),
                    );
                    commitments.insert(
                        Commitments::PermutedTable(lookup_index),
                        blstrs_point_from_midnight(table),
                    );
                }
                ProofExtractionSteps::LookupCommitment => {
                    lookup_commitment_index += 1;
                    let point: MidnightG1Projective = transcript.read().unwrap();
                    commitments.insert(
                        Commitments::Lookup(lookup_commitment_index),
                        blstrs_point_from_midnight(point),
                    );
                }
                ProofExtractionSteps::TrashCommitment => {
                    trash_commitment_index += 1;
                    let point: MidnightG1Projective = transcript.read().unwrap();
                    commitments.insert(
                        Commitments::Trash(trash_commitment_index),
                        blstrs_point_from_midnight(point),
                    );
                }
                ProofExtractionSteps::VanishingRand => {
                    let point: MidnightG1Projective = transcript.read().unwrap();
                    commitments.insert(Commitments::VanishingRand, blstrs_point_from_midnight(point));
                }
                ProofExtractionSteps::VanishingSplit => {
                    let point: MidnightG1Projective = transcript.read().unwrap();
                    vanishing_splits.push(blstrs_point_from_midnight(point));
                }
                ProofExtractionSteps::InstanceEval => {
                    instance_eval_index += 1;
                    let value: MidnightScalar = transcript.read().unwrap();
                    evaluations.insert(
                        Evaluations::CommittedInstance(instance_eval_index),
                        scalar_from_midnight(value),
                    );
                }
                ProofExtractionSteps::AdviceEval => {
                    advice_eval_index += 1;
                    let value: MidnightScalar = transcript.read().unwrap();
                    evaluations.insert(
                        Evaluations::Advice(advice_eval_index),
                        scalar_from_midnight(value),
                    );
                }
                ProofExtractionSteps::FixedEval => {
                    fixed_eval_index += 1;
                    let value: MidnightScalar = transcript.read().unwrap();
                    evaluations.insert(
                        Evaluations::Fixed(fixed_eval_index),
                        scalar_from_midnight(value),
                    );
                }
                ProofExtractionSteps::RandomEval => {
                    let value: MidnightScalar = transcript.read().unwrap();
                    evaluations.insert(Evaluations::RandomEval, scalar_from_midnight(value));
                }
                ProofExtractionSteps::PermutationCommon => {
                    permutation_common_index += 1;
                    let value: MidnightScalar = transcript.read().unwrap();
                    evaluations.insert(
                        Evaluations::PermutationsCommon(permutation_common_index),
                        scalar_from_midnight(value),
                    );
                }
                ProofExtractionSteps::PermutationEval(set) => {
                    let subindex = permutation_eval_index
                        .entry(*set)
                        .and_modify(|index| *index += 1)
                        .or_insert(1usize);
                    let value: MidnightScalar = transcript.read().unwrap();
                    evaluations.insert(
                        Evaluations::Permutation(*set, *subindex),
                        scalar_from_midnight(value),
                    );
                }
                ProofExtractionSteps::LookupEval => {
                    lookup_eval_index += 1;
                    let product_eval: MidnightScalar = transcript.read().unwrap();
                    let product_next_eval: MidnightScalar = transcript.read().unwrap();
                    let permuted_input_eval: MidnightScalar = transcript.read().unwrap();
                    let permuted_input_inv_eval: MidnightScalar = transcript.read().unwrap();
                    let permuted_table_eval: MidnightScalar = transcript.read().unwrap();

                    evaluations.insert(
                        Evaluations::Lookup(lookup_eval_index),
                        scalar_from_midnight(product_eval),
                    );
                    evaluations.insert(
                        Evaluations::LookupNext(lookup_eval_index),
                        scalar_from_midnight(product_next_eval),
                    );
                    evaluations.insert(
                        Evaluations::PermutedInput(lookup_eval_index),
                        scalar_from_midnight(permuted_input_eval),
                    );
                    evaluations.insert(
                        Evaluations::PermutedInputInverse(lookup_eval_index),
                        scalar_from_midnight(permuted_input_inv_eval),
                    );
                    evaluations.insert(
                        Evaluations::PermutedTable(lookup_eval_index),
                        scalar_from_midnight(permuted_table_eval),
                    );
                }
                ProofExtractionSteps::TrashEval => {
                    trash_eval_index += 1;
                    let value: MidnightScalar = transcript.read().unwrap();
                    evaluations.insert(
                        Evaluations::Trash(trash_eval_index),
                        scalar_from_midnight(value),
                    );
                }
                ProofExtractionSteps::XCoordinate => {
                    x = Some(scalar_from_midnight(transcript.squeeze_challenge()));
                }
                ProofExtractionSteps::TrashChallenge => {
                    trash_challenge = Some(scalar_from_midnight(transcript.squeeze_challenge()));
                }
                ProofExtractionSteps::YCoordinate => {
                    y = Some(scalar_from_midnight(transcript.squeeze_challenge()));
                }
                ProofExtractionSteps::Theta => {
                    theta = Some(scalar_from_midnight(transcript.squeeze_challenge()));
                }
                ProofExtractionSteps::Beta => {
                    beta = Some(scalar_from_midnight(transcript.squeeze_challenge()));
                }
                ProofExtractionSteps::Gamma => {
                    gamma = Some(scalar_from_midnight(transcript.squeeze_challenge()));
                }
                ProofExtractionSteps::SqueezeChallenge => {
                    let _: MidnightScalar = transcript.squeeze_challenge();
                }
            }
        }

        let mut x1 = None;
        let mut x2 = None;
        let mut x3 = None;
        let mut x4 = None;
        let mut proof_x3_q_evals = vec![];
        let mut f_commitment = None;
        let mut pi_term = None;

        for step in &circuit.pcs_extraction_steps {
            match step {
                HMOSteps::FCommitment => {
                    let point: MidnightG1Projective = transcript.read().unwrap();
                    f_commitment = Some(blstrs_point_from_midnight(point));
                }
                HMOSteps::PI => {
                    let point: MidnightG1Projective = transcript.read().unwrap();
                    pi_term = Some(blstrs_point_from_midnight(point));
                }
                HMOSteps::QEvals => {
                    let value: MidnightScalar = transcript.read().unwrap();
                    proof_x3_q_evals.push(scalar_from_midnight(value));
                }
                HMOSteps::X1 => x1 = Some(scalar_from_midnight(transcript.squeeze_challenge())),
                HMOSteps::X2 => x2 = Some(scalar_from_midnight(transcript.squeeze_challenge())),
                HMOSteps::X3 => x3 = Some(scalar_from_midnight(transcript.squeeze_challenge())),
                HMOSteps::X4 => x4 = Some(scalar_from_midnight(transcript.squeeze_challenge())),
            }
        }

        transcript.assert_empty().unwrap();

        for (index, commitment) in circuit
            .proof_instantiation_data
            .committed_instance_commitments
            .iter()
            .enumerate()
        {
            commitments.insert(
                Commitments::CommittedInstance(index + 1),
                BlstrsG1Projective::from(*commitment),
            );
        }

        for (index, commitment) in circuit
            .proof_instantiation_data
            .fixed_commitments
            .iter()
            .enumerate()
        {
            commitments.insert(
                Commitments::Fixed(index + 1),
                BlstrsG1Projective::from(*commitment),
            );
        }

        for (index, commitment) in circuit
            .proof_instantiation_data
            .permutation_commitments
            .iter()
            .enumerate()
        {
            commitments.insert(
                Commitments::PermutationsCommon(index + 1),
                BlstrsG1Projective::from(*commitment),
            );
        }

        let xn = x
            .expect("x challenge should be present")
            .pow_vartime([circuit.proof_instantiation_data.n_coefficient, 0, 0, 0]);
        let x_chop = x
            .expect("x challenge should be present")
            .pow_vartime([circuit.proof_instantiation_data.n_coefficient - 1, 0, 0, 0]);
        // Midnight serializes vanishing split commitments in reverse order with
        // respect to the usual Horner-style reconstruction used by the verifier.
        let vanishing_g = aggregate_vanishing_splits_reverse(&vanishing_splits, x_chop);
        commitments.insert(Commitments::VanishingG, vanishing_g);

        let theta = theta.unwrap();
        let beta = beta.unwrap();
        let gamma = gamma.unwrap();
        let y = y.unwrap();
        let trash_challenge = trash_challenge.unwrap();
        let x = x.unwrap();

        let mut instance_evaluations = HashMap::new();
        let committed_instance_columns = circuit
            .proof_instantiation_data
            .committed_instance_commitments
            .len();
        for (query_index, (&column_index, &rotation)) in circuit
            .proof_instantiation_data
            .instance_query_columns
            .iter()
            .zip(
                circuit
                    .proof_instantiation_data
                    .instance_query_rotations
                    .iter(),
            )
            .enumerate()
        {
            let query_id = query_index + 1;
            if column_index <= committed_instance_columns {
                let value = *evaluations
                    .get(&Evaluations::CommittedInstance(query_id))
                    .unwrap_or_else(|| panic!("missing committed instance evaluation {query_id}"));
                instance_evaluations.insert(query_id, value);
                continue;
            }

            assert_eq!(
                rotation, 0,
                "only current-rotation public instance queries are supported in STM debug"
            );
            let values = instances[0][column_index - 1]
                .iter()
                .copied()
                .map(scalar_from_midnight)
                .collect::<Vec<_>>();
            let basis = lagrange_polynomial_basis(
                x,
                xn,
                circuit.proof_instantiation_data.barycentric_weight,
                &rotate_omegas(
                    circuit.proof_instantiation_data.omega,
                    circuit.proof_instantiation_data.inverted_omega,
                    0,
                    values.len() as i32,
                ),
            );
            instance_evaluations.insert(query_id, inner_product(&basis, &values));
        }

        let rotations_for_vanishing = rotate_omegas(
            circuit.proof_instantiation_data.omega,
            circuit.proof_instantiation_data.inverted_omega,
            -(circuit.proof_instantiation_data.blinding_factors as i32 + 1),
            0,
        );
        let lagrange_basis_for_vanishing = lagrange_polynomial_basis(
            x,
            xn,
            circuit.proof_instantiation_data.barycentric_weight,
            &rotations_for_vanishing,
        );
        let last_evaluation = lagrange_basis_for_vanishing[0];
        let evaluation_at_0 = *lagrange_basis_for_vanishing
            .last()
            .expect("lagrange basis for vanishing should not be empty");
        let sum_of_evaluation_for_blinding_factors = lagrange_basis_for_vanishing
            .iter()
            .skip(1)
            .take(circuit.proof_instantiation_data.blinding_factors)
            .fold(BlstrsScalar::ZERO, |acc, value| acc + *value);
        let active_rows =
            BlstrsScalar::ONE - (last_evaluation + sum_of_evaluation_for_blinding_factors);

        let scalar_delta =
            scalar_from_hex_be("08634d0aa021aaf843cab354fabb0062f6502437c6a09c006c083479590189d7");
        let mut variables = HashMap::new();
        variables.insert("theta", theta);
        variables.insert("beta", beta);
        variables.insert("gamma", gamma);
        variables.insert("y", y);
        variables.insert("x", x);
        variables.insert("xn", xn);
        variables.insert("scalarOne", BlstrsScalar::ONE);
        variables.insert("scalarZero", BlstrsScalar::ZERO);
        variables.insert("scalarDelta", scalar_delta);
        variables.insert("trash_challenge", trash_challenge);
        variables.insert("evaluation_at_0", evaluation_at_0);
        variables.insert("last_evaluation", last_evaluation);
        variables.insert("active_rows", active_rows);
        for (&query_index, &value) in &instance_evaluations {
            let name = format!("instance_eval_{query_index}");
            let leaked = Box::leak(name.into_boxed_str());
            variables.insert(leaked, value);
        }
        for (&evaluation, &value) in &evaluations {
            let maybe_name = match evaluation {
                Evaluations::CommittedInstance(index) => Some(format!("instance_eval_{index}")),
                Evaluations::Advice(index) => Some(format!("advice_eval_{index}")),
                Evaluations::Fixed(index) => Some(format!("fixed_eval_{index}")),
                Evaluations::Permutation(set, index) => {
                    Some(format!("permutations_evaluated_{set}_{index}"))
                }
                Evaluations::PermutationsCommon(index) => {
                    Some(format!("permutation_common_{index}"))
                }
                Evaluations::VanishingS => Some("vanishing_s".to_string()),
                Evaluations::RandomEval => Some("random_eval".to_string()),
                Evaluations::Lookup(index) => Some(format!("product_eval_{index}")),
                Evaluations::PermutedInput(index) => {
                    Some(format!("permuted_input_eval_{index}"))
                }
                Evaluations::PermutedTable(index) => {
                    Some(format!("permuted_table_eval_{index}"))
                }
                Evaluations::PermutedInputInverse(index) => {
                    Some(format!("permuted_input_inv_eval_{index}"))
                }
                Evaluations::LookupNext(index) => Some(format!("product_next_eval_{index}")),
                Evaluations::Trash(index) => Some(format!("trash_eval_{index}")),
            };
            if let Some(name) = maybe_name {
                let leaked = Box::leak(name.into_boxed_str());
                variables.insert(leaked, value);
            }
        }

        let gate_evaluations = circuit
            .expressions
            .compiled_gate_equations
            .iter()
            .map(|expression| {
                eval_circuit_expression(expression, &evaluations, &instance_evaluations)
            })
            .collect::<Vec<_>>();

        let lookup_table_evaluations = circuit
            .expressions
            .compiled_lookups_equations
            .tables
            .iter()
            .map(|lookup| {
                lookup.iter().fold(BlstrsScalar::ZERO, |acc, expression| {
                    (acc * theta)
                        + eval_circuit_expression(expression, &evaluations, &instance_evaluations)
                })
            })
            .collect::<Vec<_>>();
        let lookup_input_evaluations = circuit
            .expressions
            .compiled_lookups_equations
            .inputs
            .iter()
            .map(|lookup| {
                lookup.iter().fold(BlstrsScalar::ZERO, |acc, expression| {
                    (acc * theta)
                        + eval_circuit_expression(expression, &evaluations, &instance_evaluations)
                })
            })
            .collect::<Vec<_>>();

        let lookup_expressions = (0..lookup_input_evaluations.len())
            .flat_map(|index| {
                let id = index + 1;
                let product_eval = *evaluations
                    .get(&Evaluations::Lookup(id))
                    .unwrap_or_else(|| panic!("missing lookup evaluation {id}"));
                let product_next_eval = *evaluations
                    .get(&Evaluations::LookupNext(id))
                    .unwrap_or_else(|| panic!("missing lookup-next evaluation {id}"));
                let permuted_input_eval = *evaluations
                    .get(&Evaluations::PermutedInput(id))
                    .unwrap_or_else(|| panic!("missing permuted-input evaluation {id}"));
                let permuted_input_inv_eval = *evaluations
                    .get(&Evaluations::PermutedInputInverse(id))
                    .unwrap_or_else(|| panic!("missing permuted-input-inverse evaluation {id}"));
                let permuted_table_eval = *evaluations
                    .get(&Evaluations::PermutedTable(id))
                    .unwrap_or_else(|| panic!("missing permuted-table evaluation {id}"));
                let lookup_input = lookup_input_evaluations[index];
                let lookup_table = lookup_table_evaluations[index];
                let l1 = evaluation_at_0 * (BlstrsScalar::ONE - product_eval);
                let l2 = last_evaluation * ((product_eval * product_eval) - product_eval);
                let lookup_left =
                    product_next_eval * (permuted_input_eval + beta) * (permuted_table_eval + gamma);
                let lookup_right = product_eval * (lookup_input + beta) * (lookup_table + gamma);
                let l3 = (lookup_left - lookup_right) * active_rows;
                let l4 = evaluation_at_0 * (permuted_input_eval - permuted_table_eval);
                let l5 =
                    (permuted_input_eval - permuted_table_eval)
                        * (permuted_input_eval - permuted_input_inv_eval)
                        * active_rows;
                [l1, l2, l3, l4, l5]
            })
            .collect::<Vec<_>>();

        let permutation_eval_terms = circuit
            .expressions
            .permutations_evaluated_terms
            .iter()
            .map(|expression| {
                eval_scalar_expression(
                    expression,
                    &evaluations,
                    &instance_evaluations,
                    &variables,
                )
            })
            .collect::<Vec<_>>();

        let mut lhs_sets = HashMap::<char, BlstrsScalar>::new();
        for (set, expression) in &circuit.expressions.permutation_terms_left {
            let value = eval_scalar_expression(
                expression,
                &evaluations,
                &instance_evaluations,
                &variables,
            );
            lhs_sets
                .entry(*set)
                .and_modify(|acc| *acc *= value)
                .or_insert(value);
        }

        let mut rhs_sets = HashMap::<char, BlstrsScalar>::new();
        for (set, expression) in &circuit.expressions.permutation_terms_right {
            let value = eval_scalar_expression(
                expression,
                &evaluations,
                &instance_evaluations,
                &variables,
            );
            rhs_sets
                .entry(*set)
                .and_modify(|acc| *acc *= value)
                .or_insert(value);
        }

        let mut set_ids = lhs_sets.keys().copied().collect::<Vec<_>>();
        set_ids.sort_unstable();
        let permutation_combined = set_ids
            .iter()
            .map(|set_id| {
                let left = evaluations
                    .get(&Evaluations::Permutation(*set_id, 2))
                    .unwrap_or_else(|| panic!("missing permutation eval {}_2", set_id))
                    * lhs_sets
                        .get(set_id)
                        .unwrap_or_else(|| panic!("missing left set {set_id}"));
                let right = evaluations
                    .get(&Evaluations::Permutation(*set_id, 1))
                    .unwrap_or_else(|| panic!("missing permutation eval {}_1", set_id))
                    * rhs_sets
                        .get(set_id)
                        .unwrap_or_else(|| panic!("missing right set {set_id}"));
                (left - right) * active_rows
            })
            .collect::<Vec<_>>();

        let trash_evaluations = circuit
            .expressions
            .trash_expressions
            .iter()
            .map(|expression| {
                eval_scalar_expression(
                    expression,
                    &evaluations,
                    &instance_evaluations,
                    &variables,
                )
            })
            .collect::<Vec<_>>();

        let vanishing_terms = gate_evaluations
            .into_iter()
            .chain(permutation_eval_terms)
            .chain(permutation_combined)
            .chain(lookup_expressions)
            .chain(trash_evaluations)
            .collect::<Vec<_>>();
        let h_eval = vanishing_terms
            .into_iter()
            .reduce(|acc, expression| (acc * y) + expression)
            .expect("vanishing terms should not be empty");
        let vanishing_s = h_eval
            * (xn - BlstrsScalar::ONE)
                .invert()
                .expect("xn - 1 should be invertible");
        evaluations.insert(Evaluations::VanishingS, vanishing_s);

        ParsedMidnightProof {
            commitments,
            evaluations,
            x,
            x1: x1.unwrap(),
            x2: x2.unwrap(),
            x3: x3.unwrap(),
            x4: x4.unwrap(),
            f_commitment: f_commitment.unwrap(),
            pi_term: pi_term.unwrap(),
            proof_x3_q_evals,
        }
    }

    // Recompute the Aiken-side Halo2 multi-open accumulator in Rust so we can
    // regression-test the emitted verifier against Midnight's native guard.
    fn compute_aiken_style_right(
        circuit: &crate::plutus_gen::CircuitRepresentation<
            MidnightKZGCommitmentScheme<MidnightBls12>,
        >,
        parsed: &ParsedMidnightProof,
    ) -> BlstrsG1Projective {
        let (unique_grouped_points, commitment_data) =
            <MidnightKZGCommitmentScheme<MidnightBls12> as ExtractPCS>::precompute_intermediate_sets(
                circuit,
            );

        let max_commitments_per_set = (0..unique_grouped_points.len())
            .map(|point_set_index| {
                commitment_data
                    .iter()
                    .filter(|entry| entry.point_set_index == point_set_index)
                    .count()
            })
            .max()
            .unwrap_or(0);

        let x1_powers = powers(max_commitments_per_set, parsed.x1);
        let x4_powers = powers(unique_grouped_points.len() + 1, parsed.x4);
        let x_prev = parsed.x * circuit.proof_instantiation_data.inverted_omega;
        let x_next = parsed.x * circuit.proof_instantiation_data.omega;
        let x_last = parsed.x
            * circuit
                .proof_instantiation_data
                .inverted_omega
                .pow_vartime([
                    (circuit.proof_instantiation_data.blinding_factors as u64) + 1,
                    0,
                    0,
                    0,
                ]);

        let point_sets = unique_grouped_points
            .iter()
            .map(|point_set| {
                point_set
                    .iter()
                    .map(|rotation| {
                        resolve_rotation_point(*rotation, parsed.x, x_prev, x_next, x_last)
                    })
                    .collect::<Vec<_>>()
            })
            .collect::<Vec<_>>();

        let mut final_com = BlstrsG1Projective::identity();
        let mut q_eval_sets = Vec::with_capacity(point_sets.len());

        for (point_set_index, x4_power) in x4_powers.iter().take(point_sets.len()).enumerate() {
            let commitments_for_set = commitment_data
                .iter()
                .filter(|entry| entry.point_set_index == point_set_index)
                .collect::<Vec<_>>();

            let mut q_comm = BlstrsG1Projective::identity();
            let mut eval_set = vec![BlstrsScalar::ZERO; point_sets[point_set_index].len()];

            for (x1_power, entry) in x1_powers.iter().zip(commitments_for_set.iter()) {
                let commitment = parsed
                    .commitments
                    .get(&entry.commitment)
                    .unwrap_or_else(|| panic!("missing commitment value for {:?}", entry.commitment));
                q_comm += *commitment * *x1_power;

                for (slot, evaluation) in entry.evaluations.iter().enumerate() {
                    let value = parsed.evaluations.get(evaluation).unwrap_or_else(|| {
                        panic!("missing evaluation value for {:?}", evaluation)
                    });
                    eval_set[slot] += *value * *x1_power;
                }
            }

            final_com += q_comm * *x4_power;
            q_eval_sets.push(eval_set);
        }

        final_com += parsed.f_commitment * *x4_powers.last().unwrap();

        let mut f_eval = BlstrsScalar::ZERO;
        for ((points, evals), proof_q_eval) in point_sets
            .iter()
            .zip(q_eval_sets.iter())
            .zip(parsed.proof_x3_q_evals.iter())
            .rev()
        {
            let r_eval = lagrange_evaluation(points, evals, parsed.x3);
            let denominator = points.iter().fold(BlstrsScalar::ONE, |acc, point| {
                acc * (parsed.x3 - point)
            });
            let evaluation = (*proof_q_eval - r_eval)
                * denominator
                    .invert()
                    .expect("x3 should not collide with an evaluation point");
            f_eval = (f_eval * parsed.x2) + evaluation;
        }

        let v = x4_powers
            .iter()
            .zip(
                parsed
                    .proof_x3_q_evals
                    .iter()
                    .copied()
                    .chain(std::iter::once(f_eval)),
            )
            .fold(BlstrsScalar::ZERO, |acc, (power, eval)| acc + (*power * eval));

        final_com + (BlstrsG1Projective::generator() * (-v)) + (parsed.pi_term * parsed.x3)
    }

    // Fold the native Midnight verifier guard terms into a single G1 element so
    // it can be compared directly with the Rust model of the generated Aiken code.
    fn native_guard_right(
        circuit: &crate::plutus_gen::CircuitRepresentation<
            MidnightKZGCommitmentScheme<MidnightBls12>,
        >,
        vk: &zk::MidnightVK,
        normal_instances: &[&[&[MidnightScalar]]; 1],
        proof: &[u8],
    ) -> BlstrsG1Projective {
        let mut transcript_verifier =
            CircuitTranscript::<CardanoFriendlyBlake2b>::init_from_bytes(proof);
        let committed_instances_storage = circuit
            .proof_instantiation_data
            .committed_instance_commitments
            .iter()
            .map(|commitment| {
                let bytes = commitment.to_bytes();
                let mut repr = <MidnightG1Projective as GroupEncoding>::Repr::default();
                repr.as_mut().copy_from_slice(bytes.as_ref());
                Option::<MidnightG1Projective>::from(MidnightG1Projective::from_bytes(&repr))
                    .unwrap()
            })
            .collect::<Vec<_>>();
        let committed_instances_columns: [&[MidnightG1Projective]; 1] =
            [&committed_instances_storage];
        let guard =
            prepare_midnight_verifier::<
                _,
                MidnightKZGCommitmentScheme<MidnightBls12>,
                CircuitTranscript<CardanoFriendlyBlake2b>,
            >(
                vk.vk(),
                &committed_instances_columns,
                normal_instances,
                &mut transcript_verifier,
            )
            .unwrap();
        let (_, right_terms): (MidnightGuardTerms<'_>, MidnightGuardTerms<'_>) = guard.split();
        right_terms
            .into_iter()
            .fold(BlstrsG1Projective::identity(), |acc, (scalar, point)| {
                acc + (blstrs_point_from_midnight(*point) * scalar_from_midnight(*scalar))
            })
    }

    #[test]
    fn verifies_real_midnight_stm_proof_with_cardano_transcript() {
        let fixture = stm_fixture();
        assert!(!fixture.proof.is_empty());
    }

    #[test]
    fn parses_real_midnight_stm_proof_with_generated_aiken_layout() {
        let fixture = stm_fixture();
        let (empty_committed, public_inputs) = stm_instance_columns(&fixture.instance);
        let columns: [&[MidnightScalar]; 2] = [&empty_committed, &public_inputs];
        let instances: [&[&[MidnightScalar]]; 1] = [&columns];
        let circuit = extract_circuit_midnight::<MidnightKZGCommitmentScheme<MidnightBls12>>(
            &fixture.srs,
            fixture.vk.vk(),
            &instances,
        )
        .unwrap();

        let mut transcript =
            CircuitTranscript::<CardanoFriendlyBlake2b>::init_from_bytes(&fixture.proof);
        transcript
            .common(&fixture.vk.vk().transcript_repr())
            .unwrap();
        for commitment in &circuit
            .proof_instantiation_data
            .committed_instance_commitments
        {
            use group::GroupEncoding;

            let bytes = commitment.to_bytes();
            let mut repr = <midnight_curves::G1Projective as GroupEncoding>::Repr::default();
            repr.as_mut().copy_from_slice(bytes.as_ref());
            let point = Option::<midnight_curves::G1Projective>::from(
                midnight_curves::G1Projective::from_bytes(&repr),
            )
            .unwrap();
            transcript.common(&point).unwrap();
        }
        for column in instances[0].iter().skip(
            circuit
                .proof_instantiation_data
                .committed_instance_commitments
                .len(),
        ) {
            transcript
                .common(&MidnightScalar::from(column.len() as u64))
                .unwrap();
            for value in *column {
                transcript.common(value).unwrap();
            }
        }

        for (step_index, step) in circuit.proof_extraction_steps.iter().enumerate() {
            match step {
                ProofExtractionSteps::AdviceCommitments
                | ProofExtractionSteps::PermutationsCommitted
                | ProofExtractionSteps::LookupCommitment
                | ProofExtractionSteps::TrashCommitment
                | ProofExtractionSteps::VanishingRand
                | ProofExtractionSteps::VanishingSplit => {
                    let _: midnight_curves::G1Projective = transcript.read().unwrap_or_else(
                        |_| panic!("failed to read point at proof step {step_index}: {step:?}"),
                    );
                }
                ProofExtractionSteps::LookupPermuted => {
                    let _: midnight_curves::G1Projective = transcript.read().unwrap_or_else(
                        |_| panic!("failed to read first lookup point at proof step {step_index}"),
                    );
                    let _: midnight_curves::G1Projective = transcript.read().unwrap_or_else(
                        |_| panic!("failed to read second lookup point at proof step {step_index}"),
                    );
                }
                ProofExtractionSteps::AdviceEval
                | ProofExtractionSteps::FixedEval
                | ProofExtractionSteps::RandomEval
                | ProofExtractionSteps::PermutationCommon
                | ProofExtractionSteps::PermutationEval(_)
                | ProofExtractionSteps::InstanceEval => {
                    let _: MidnightScalar = transcript.read().unwrap_or_else(
                        |_| panic!("failed to read scalar at proof step {step_index}: {step:?}"),
                    );
                }
                ProofExtractionSteps::LookupEval => {
                    for lookup_scalar in 0..5 {
                        let _: MidnightScalar = transcript.read().unwrap_or_else(|_| {
                            panic!(
                                "failed to read lookup scalar {lookup_scalar} at proof step {step_index}"
                            )
                        });
                    }
                }
                ProofExtractionSteps::TrashEval => {
                    let _: MidnightScalar = transcript.read().unwrap_or_else(|_| {
                        panic!("failed to read trash scalar at proof step {step_index}")
                    });
                }
                ProofExtractionSteps::SqueezeChallenge
                | ProofExtractionSteps::TrashChallenge
                | ProofExtractionSteps::XCoordinate
                | ProofExtractionSteps::YCoordinate
                | ProofExtractionSteps::Theta
                | ProofExtractionSteps::Beta
                | ProofExtractionSteps::Gamma => {
                    let _: MidnightScalar = transcript.squeeze_challenge();
                }
            }
        }

        for (step_index, step) in circuit.pcs_extraction_steps.iter().enumerate() {
            match step {
                HMOSteps::FCommitment | HMOSteps::PI => {
                    let _: midnight_curves::G1Projective = transcript.read().unwrap_or_else(
                        |_| panic!("failed to read PCS point at pcs step {step_index}: {step:?}"),
                    );
                }
                HMOSteps::QEvals => {
                    let _: MidnightScalar = transcript.read().unwrap_or_else(|_| {
                        panic!("failed to read PCS scalar at pcs step {step_index}")
                    });
                }
                HMOSteps::X1 | HMOSteps::X2 | HMOSteps::X3 | HMOSteps::X4 => {
                    let _: MidnightScalar = transcript.squeeze_challenge();
                }
            }
        }

        transcript.assert_empty().unwrap();
    }

    #[test]
    fn extracts_midnight_stm_circuit_representation() {
        let fixture = stm_fixture();
        let (empty_committed, public_inputs) = stm_instance_columns(&fixture.instance);
        let columns: [&[MidnightScalar]; 2] = [&empty_committed, &public_inputs];
        let instances: [&[&[MidnightScalar]]; 1] = [&columns];

        let circuit = extract_circuit_midnight::<MidnightKZGCommitmentScheme<MidnightBls12>>(
            &fixture.srs,
            fixture.vk.vk(),
            &instances,
        )
        .unwrap();

        assert_eq!(circuit.public_inputs, 2);
        assert!(!circuit.proof_extraction_steps.is_empty());
        assert!(!circuit.expressions.compiled_gate_equations.is_empty());
        assert!(!circuit.queries.advice.is_empty());
        assert_eq!(
            circuit
                .proof_instantiation_data
                .committed_instance_commitments
                .len(),
            1
        );
    }

    #[test]
    fn emits_midnight_stm_aiken_verifier_to_custom_paths() {
        let fixture = stm_fixture();
        let (empty_committed, public_inputs_column) = stm_instance_columns(&fixture.instance);
        let columns: [&[MidnightScalar]; 2] = [&empty_committed, &public_inputs_column];
        let instances: [&[&[MidnightScalar]]; 1] = [&columns];
        let circuit = extract_circuit_midnight::<MidnightKZGCommitmentScheme<MidnightBls12>>(
            &fixture.srs,
            fixture.vk.vk(),
            &instances,
        )
        .unwrap();
        let public_inputs = fixture
            .instance
            .iter()
            .copied()
            .map(scalar_from_midnight)
            .collect();

        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let output_dir = PathBuf::from(format!(
            "/tmp/plutus-halo2-verifier-gen-midnight-{unique}"
        ));
        fs::create_dir_all(&output_dir).unwrap();
        let verifier_file = output_dir.join("proof_verifier.ak");
        let vk_file = output_dir.join("verifier_key.ak");

        emit_aiken_verifier_to_paths(
            &circuit,
            public_inputs,
            Some((fixture.proof.clone(), fixture.proof.clone())),
            &verifier_file,
            &vk_file,
            None,
        )
        .unwrap();

        let verifier_source = fs::read_to_string(&verifier_file).unwrap();
        let vk_source = fs::read_to_string(&vk_file).unwrap();

        assert!(verifier_source.contains("common_point"));
        assert!(verifier_source.contains("q_eval_on_x3_1"));
        assert!(verifier_source.contains("fn verifier("));
        assert!(vk_source.contains("pub const omega"));
    }

    #[test]
    fn generates_midnight_stm_aiken_verifier_in_project_paths() {
        let fixture = stm_fixture();
        let (empty_committed, public_inputs_column) = stm_instance_columns(&fixture.instance);
        let columns: [&[MidnightScalar]; 2] = [&empty_committed, &public_inputs_column];
        let instances: [&[&[MidnightScalar]]; 1] = [&columns];

        generate_aiken_verifier_midnight(
            &fixture.srs,
            &fixture.vk,
            &instances,
            Some((fixture.proof.clone(), fixture.proof.clone())),
        )
            .unwrap();

        let verifier_source =
            fs::read_to_string("aiken-verifier/aiken_halo2/lib/proof_verifier.ak").unwrap();
        let vk_source =
            fs::read_to_string("aiken-verifier/aiken_halo2/lib/verifier_key.ak").unwrap();

        assert!(verifier_source.contains("common_point"));
        assert!(verifier_source.contains("q_eval_on_x3_1"));
        assert!(vk_source.contains("pub const omega"));
    }

    #[test]
    fn generated_midnight_aiken_multiopen_matches_native_guard() {
        let fixture = stm_fixture();
        let (empty_committed, public_inputs_column) = stm_instance_columns(&fixture.instance);
        let columns: [&[MidnightScalar]; 2] = [&empty_committed, &public_inputs_column];
        let instances: [&[&[MidnightScalar]]; 1] = [&columns];
        let normal_instance_columns: [&[MidnightScalar]; 1] = [&public_inputs_column];
        let normal_instances: [&[&[MidnightScalar]]; 1] = [&normal_instance_columns];

        generate_aiken_verifier_midnight(
            &fixture.srs,
            &fixture.vk,
            &instances,
            Some((fixture.proof.clone(), fixture.proof.clone())),
        )
        .unwrap();

        let verifier_source =
            fs::read_to_string("aiken-verifier/aiken_halo2/lib/proof_verifier.ak").unwrap();
        let generated_proof_hex = extract_generated_valid_proof_hex(&verifier_source);
        let generated_proof = hex::decode(&generated_proof_hex).unwrap();

        let circuit = extract_circuit_midnight::<MidnightKZGCommitmentScheme<MidnightBls12>>(
            &fixture.srs,
            fixture.vk.vk(),
            &instances,
        )
        .unwrap();
        let parsed = parse_midnight_stm_proof(&circuit, &fixture.vk, &instances, &generated_proof);
        // This is the regression test for the multi-open ordering bug: the
        // Rust model of the emitted Aiken verifier must reproduce the exact
        // `right` accumulator produced by Midnight's native verifier.
        let aiken_right = compute_aiken_style_right(&circuit, &parsed);
        let native_right =
            native_guard_right(&circuit, &fixture.vk, &normal_instances, &generated_proof);

        assert_eq!(generated_proof, fixture.proof);
        assert_eq!(aiken_right, native_right);
    }
}
