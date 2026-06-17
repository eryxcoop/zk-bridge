//! Polynomial commitment scheme (PCS) module
//! This module contains the code related to the extraction of the polynomial
//! commitment scheme (PCS) steps and data from a Halo2 circuit, as well as the
//! code for emitting in these in the supported languages.
//! It includes the definition of generic type and trait that all supported PCS
//! must implement, as well as the implementation of the trait for the supported
//! KZG based PCS.

use super::data::{CircuitRepresentation, CommitmentData, Commitments, RotationDescription};

#[cfg(feature = "plutus_debug")]
use log::info;

use std::collections::HashMap;

pub(crate) mod gwc;
pub(crate) mod kzg;

/// List of all supported PCS.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PCSType {
    GWC19,
    Halo2MultiOpen,
}

/// Type for permutation point sets and related committed data.
pub(crate) type IntermediateSets = (Vec<Vec<RotationDescription>>, Vec<CommitmentData>);

/// Generic trait for extracting PCS steps and data, as well as emitting them
/// in the supported languages.
pub trait ExtractPCS {
    type PCSExtractionSteps: PartialEq + Clone;

    type PCSData: Default;

    /// Function to precompute the permutation sets and related committed data.
    // CHANGED vs upstream: rewritten. The original grouped commitments with
    // itertools (`into_group_map_by` / `unique`). This version assigns each
    // distinct rotation a stable point index and builds the point sets by index,
    // panicking on duplicated queries. It is deterministic and handles the larger
    // Midnight circuit's query set (committed instances, trash, more lookups).
    fn precompute_intermediate_sets(
        circuit_repr: &CircuitRepresentation<Self>,
    ) -> IntermediateSets {
        let queries = circuit_repr.queries.all_ordered();
        #[derive(Clone, Debug)]
        struct RawCommitmentData {
            commitment: Commitments,
            point_set_index: usize,
            point_indices: Vec<usize>,
            evaluations: Vec<super::data::Evaluations>,
        }

        let mut commitments: Vec<RawCommitmentData> = vec![];
        let mut point_index_map: HashMap<RotationDescription, usize> = HashMap::new();
        let mut inverse_point_index_map: Vec<RotationDescription> = vec![];

        for query in queries.iter().flatten() {
            let point_idx = if let Some(existing) = point_index_map.get(&query.point) {
                *existing
            } else {
                let next_index = inverse_point_index_map.len();
                point_index_map.insert(query.point, next_index);
                inverse_point_index_map.push(query.point);
                next_index
            };

            if let Some(commitment_data) = commitments
                .iter_mut()
                .find(|commitment_data| commitment_data.commitment == query.commitment)
            {
                if commitment_data.point_indices.contains(&point_idx) {
                    panic!(
                        "duplicated query for commitment {:?} at point {:?}",
                        query.commitment, query.point
                    );
                }
                commitment_data.point_indices.push(point_idx);
            } else {
                commitments.push(RawCommitmentData {
                    commitment: query.commitment,
                    point_set_index: 0,
                    point_indices: vec![point_idx],
                    evaluations: vec![],
                });
            }
        }

        let mut commitment_set_map: Vec<(Commitments, Vec<usize>)> =
            Vec::with_capacity(commitments.len());
        let mut point_sets: Vec<Vec<usize>> = vec![];

        for commitment_data in commitments.iter() {
            let mut point_index_set = commitment_data.point_indices.clone();
            point_index_set.sort_unstable();

            commitment_set_map.push((commitment_data.commitment, point_index_set.clone()));

            if !point_sets.contains(&point_index_set) {
                point_sets.push(point_index_set);
            }
        }

        for commitment_data in commitments.iter_mut() {
            commitment_data.evaluations =
                vec![super::data::Evaluations::default(); commitment_data.point_indices.len()];
        }

        for query in queries.iter().flatten() {
            let point_index = point_index_map
                .get(&query.point)
                .unwrap_or_else(|| panic!("point index for {:?} not found", query.point));

            let point_index_set = commitment_set_map
                .iter()
                .find(|(commitment, _)| *commitment == query.commitment)
                .map(|(_, set)| set)
                .unwrap_or_else(|| {
                    panic!(
                        "point index set for commitment {:?} not found",
                        query.commitment
                    )
                });

            let point_index_in_set = point_index_set
                .iter()
                .position(|index| index == point_index)
                .unwrap_or_else(|| {
                    panic!(
                        "point index {:?} not found in set for commitment {:?}",
                        point_index, query.commitment
                    )
                });

            let point_set_index = point_sets
                .iter()
                .position(|set| set == point_index_set)
                .unwrap_or_else(|| panic!("point set {:?} not found", point_index_set));

            let commitment_data = commitments
                .iter_mut()
                .find(|commitment_data| commitment_data.commitment == query.commitment)
                .unwrap_or_else(|| {
                    panic!("commitment data for {:?} not found", query.commitment)
                });

            commitment_data.point_set_index = point_set_index;
            commitment_data.evaluations[point_index_in_set] = query.evaluation;
        }

        let unique_grouped_points = point_sets
            .iter()
            .map(|point_index_set| {
                point_index_set
                    .iter()
                    .map(|point_index| {
                        *inverse_point_index_map.get(*point_index).unwrap_or_else(|| {
                            panic!("inverse point index {:?} not found", point_index)
                        })
                    })
                    .collect::<Vec<_>>()
            })
            .collect::<Vec<_>>();

        let commitment_data = commitments
            .into_iter()
            .map(|commitment_data| {
                unique_grouped_points
                    .get(commitment_data.point_set_index)
                    .unwrap_or_else(|| {
                        panic!(
                            "grouped points for set {} not found",
                            commitment_data.point_set_index
                        )
                    });

                CommitmentData {
                    commitment: commitment_data.commitment,
                    point_set_index: commitment_data.point_set_index,
                    evaluations: commitment_data.evaluations,
                }
            })
            .collect();

        (unique_grouped_points, commitment_data)
    }

    /// Function for extracting the PCS steps to the circuit representation
    /// structure.
    fn extract_pcs(circuit_repr: &mut CircuitRepresentation<Self>);
    /// Function for emitting the PCS steps in Aiken.
    fn step_to_aiken(step: Self::PCSExtractionSteps, number: usize) -> String;

    /// Function for extracting the PCS data to the circuit representation
    /// structure.
    fn pcs_data(circuit_repr: &CircuitRepresentation<Self>) -> usize;
    /// Function for emitting the PCS data in Aiken.
    fn pcs_data_aiken(circuit_repr: &CircuitRepresentation<Self>) -> String;

    /// Function for determining the type of PCS used in the circuit.
    fn pcs_type() -> PCSType;
    // CHANGED vs upstream: removed the Plinth trait methods `step_to_plinth` and
    // `pcs_data_plinth` (Aiken-only subrepo, see point 2).
}
