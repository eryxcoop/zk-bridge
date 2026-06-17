//! Module for extracting the Halo2 variant of KZG PCS' steps and data.
use crate::plutus_gen::extraction::data::CircuitRepresentation;

use super::{ExtractPCS, PCSType};

use blstrs::Bls12;
use halo2_proofs::poly::kzg::KZGCommitmentScheme;
use midnight_curves::Bls12 as MidnightBls12;
use midnight_proofs::poly::kzg::KZGCommitmentScheme as MidnightKZGCommitmentScheme;

#[cfg(feature = "plutus_debug")]
use log::info;

use itertools::Itertools;

type Halo2MultiOpenScheme = KZGCommitmentScheme<Bls12>;
// CHANGED vs upstream: added the Midnight KZG scheme alias (and its imports
// above), so the pipeline can extract from a Midnight relation, not just halo2.
type MidnightMultiOpenScheme = MidnightKZGCommitmentScheme<MidnightBls12>;

/// Halo2 Multi-Open PCS data comprises the number of q evaluations only.
#[derive(Default)]
pub struct HMOData {
    q_evaluations_count: usize,
}

/// The Halo2 Multi-Open PCS steps comprise five challenge generation (x1 to x4
/// and pi) and the handling of the f commitment and the q evaluations.
#[derive(PartialEq, Clone, Debug)]
pub enum HMOSteps {
    X1,
    X2,
    X3,
    X4,
    PI,
    QEvals,
    FCommitment,
}

impl ExtractPCS for Halo2MultiOpenScheme {
    type PCSExtractionSteps = HMOSteps;
    type PCSData = HMOData;
    fn pcs_type() -> PCSType {
        PCSType::Halo2MultiOpen
    }

    fn pcs_data(circuit_repr: &CircuitRepresentation<Self>) -> usize {
        circuit_repr.pcs_instantiation_data.q_evaluations_count
    }

    fn pcs_data_aiken(circuit_repr: &CircuitRepresentation<Self>) -> String {
        (1..=circuit_repr.pcs_instantiation_data.q_evaluations_count)
            .map(|n| format!("q_eval_on_x3_{}", n))
            .join(", ")
    }

    fn extract_pcs(circuit_repr: &mut CircuitRepresentation<Self>) {
        circuit_repr.pcs_extraction_steps.push(HMOSteps::X1);

        circuit_repr.pcs_extraction_steps.push(HMOSteps::X2);

        circuit_repr
            .pcs_extraction_steps
            .push(HMOSteps::FCommitment);

        circuit_repr.pcs_extraction_steps.push(HMOSteps::X3);

        // number of final witnesses is equal to number of different point sets
        let (sets, _) = Self::precompute_intermediate_sets(circuit_repr);
        let number_of_witnesses = sets.len();
        circuit_repr.pcs_instantiation_data.q_evaluations_count = number_of_witnesses;

        // witnesses
        for _ in 0..number_of_witnesses {
            circuit_repr.pcs_extraction_steps.push(HMOSteps::QEvals);
        }

        circuit_repr.pcs_extraction_steps.push(HMOSteps::X4);

        circuit_repr.pcs_extraction_steps.push(HMOSteps::PI);
    }

    fn step_to_aiken(step: Self::PCSExtractionSteps, number: usize) -> String {
        match step {
            HMOSteps::X1 => {
                "    let (x1, transcript) = squeeze_challenge(transcript)\n".to_string()
            }
            HMOSteps::X2 => {
                "    let (x2, transcript) = squeeze_challenge(transcript)\n".to_string()
            }
            HMOSteps::X3 => {
                "    let (x3, transcript) = squeeze_challenge(transcript)\n".to_string()
            }
            HMOSteps::X4 => {
                "    let (x4, transcript) = squeeze_challenge(transcript)\n".to_string()
            }
            HMOSteps::PI => "    let (pi_term, _) =  read_point(transcript)\n".to_string(),
            HMOSteps::FCommitment => {
                "    let (f_commitment, transcript) =  read_point(transcript)\n".to_string()
            }
            HMOSteps::QEvals => format!(
                "    let (q_eval_on_x3_{}, transcript) = read_scalar(transcript)\n",
                number
            ),
        }
    }
    // CHANGED vs upstream: removed the Plinth emitter methods `pcs_data_plinth`
    // and `step_to_plinth` (Aiken-only subrepo, see point 2).
}

// CHANGED vs upstream: new impl. Mirrors the Halo2 KZG multi-open extractor for
// the Midnight KZG scheme; `extract_pcs` derives the witness/q-eval count from
// `precompute_intermediate_sets`, and `step_to_aiken` reuses the Halo2 emitter.
impl ExtractPCS for MidnightMultiOpenScheme {
    type PCSExtractionSteps = HMOSteps;
    type PCSData = HMOData;

    fn pcs_type() -> PCSType {
        PCSType::Halo2MultiOpen
    }

    fn pcs_data(circuit_repr: &CircuitRepresentation<Self>) -> usize {
        circuit_repr.pcs_instantiation_data.q_evaluations_count
    }

    fn pcs_data_aiken(circuit_repr: &CircuitRepresentation<Self>) -> String {
        (1..=circuit_repr.pcs_instantiation_data.q_evaluations_count)
            .map(|n| format!("q_eval_on_x3_{}", n))
            .join(", ")
    }

    fn extract_pcs(circuit_repr: &mut CircuitRepresentation<Self>) {
        circuit_repr.pcs_extraction_steps.push(HMOSteps::X1);
        circuit_repr.pcs_extraction_steps.push(HMOSteps::X2);
        circuit_repr
            .pcs_extraction_steps
            .push(HMOSteps::FCommitment);
        circuit_repr.pcs_extraction_steps.push(HMOSteps::X3);

        let (sets, _) = Self::precompute_intermediate_sets(circuit_repr);
        let number_of_witnesses = sets.len();
        circuit_repr.pcs_instantiation_data.q_evaluations_count = number_of_witnesses;

        for _ in 0..number_of_witnesses {
            circuit_repr.pcs_extraction_steps.push(HMOSteps::QEvals);
        }

        circuit_repr.pcs_extraction_steps.push(HMOSteps::X4);
        circuit_repr.pcs_extraction_steps.push(HMOSteps::PI);
    }

    fn step_to_aiken(step: Self::PCSExtractionSteps, number: usize) -> String {
        <Halo2MultiOpenScheme as ExtractPCS>::step_to_aiken(step, number)
    }

}
