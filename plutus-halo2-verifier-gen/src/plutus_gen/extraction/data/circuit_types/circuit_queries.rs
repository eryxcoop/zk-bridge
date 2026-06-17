//! Circuit query structure and associated functions.

use super::super::{Commitments, Evaluations, Query, RotationDescription};

/// CircuitQueries structure
/// This structure contains all circuit's queries.
#[derive(Clone, Debug, Default)]
pub(crate) struct CircuitQueries {
    // CHANGED vs upstream: added `committed_instance` and `trash` query lists
    // for Midnight support.
    pub(crate) committed_instance: Vec<Query>,
    pub(crate) advice: Vec<Query>,
    pub(crate) fixed: Vec<Query>,
    pub(crate) permutation: Vec<Query>,
    pub(crate) common: Vec<Query>,
    pub(crate) vanishing: Vec<Query>,
    pub(crate) lookup: Vec<Query>,
    pub(crate) trash: Vec<Query>,
}

impl CircuitQueries {
    // Order of queries from halo2:
    // 1. ADVICE
    // 2. PERMUTATION
    // 3. LOOKUP
    // 4. FIXED
    // 5. COMMON
    // 6. VANISHING
    /// Returns all queries ordered by type.
    // CHANGED vs upstream: returns 8 lists instead of 6 (added committed_instance
    // and trash).
    pub(crate) fn all_ordered(&self) -> [Vec<Query>; 8] {
        [
            self.committed_instance.clone(),
            self.advice.clone(),
            self.permutation.clone(),
            self.lookup.clone(),
            self.trash.clone(),
            self.fixed.clone(),
            self.common.clone(),
            self.vanishing.clone(),
        ]
    }

    /// Extract a committed-instance query to the CircuitQueries structure.
    // CHANGED vs upstream: new method for Midnight committed instances.
    pub(crate) fn committed_instance(
        &mut self,
        commitment_index: usize,
        evaluation_index: usize,
        point: i32,
    ) {
        let query = Query::new(
            Commitments::CommittedInstance(commitment_index),
            Evaluations::CommittedInstance(evaluation_index),
            RotationDescription::from_i32(point),
        );
        self.committed_instance.push(query);
    }

    /// Extract an advice query to the CircuitQueries structure.
    pub(crate) fn advice(&mut self, commitment_index: usize, evaluation_index: usize, point: i32) {
        let query = Query::new(
            Commitments::Advice(commitment_index), //format!("a{:?}", column.index() + 1),
            Evaluations::Advice(evaluation_index), //format!("adviceEval{:?}", query_index + 1),
            RotationDescription::from_i32(point),
        );
        self.advice.push(query);
    }

    /// Extract a fixed query to the CircuitQueries structure.
    pub(crate) fn fixed(&mut self, commitment_index: usize, evaluation_index: usize, point: i32) {
        let query = Query::new(
            Commitments::Fixed(commitment_index), //format!("f{:?}_commitment", column.index() + 1),
            Evaluations::Fixed(evaluation_index), //format!("fixedEval{:?}", query_index + 1),
            RotationDescription::from_i32(point),
        );
        self.fixed.push(query);
    }

    /// Extract a permutation query to the CircuitQueries structure.
    pub(crate) fn permutation(
        &mut self,
        index: char,
        evaluation_subindex: usize,
        point: RotationDescription,
    ) {
        let query = Query::new(
            Commitments::Permutation(index), //format!("permutations_committed_{}", set),
            Evaluations::Permutation(index, evaluation_subindex), //format!("permutations_evaluated_{}_2", set),
            point,
        );
        self.permutation.push(query);
    }

    /// Extract a common permutation query to the CircuitQueries structure.
    pub(crate) fn common(&mut self, index: usize) {
        let query = Query::new(
            Commitments::PermutationsCommon(index), //format!("p{:?}_commitment", idx + 1),
            Evaluations::PermutationsCommon(index), //format!("permutationCommon{:?}", idx + 1),
            RotationDescription::Current,
        );
        self.common.push(query);
    }

    /// Extract a vanishing query to the CircuitQueries structure.
    pub(crate) fn vanishing_queries(&mut self) {
        let query = Query::new(
            Commitments::VanishingG, //"vanishing_g".to_string(),
            Evaluations::VanishingS, //"vanishing_s".to_string()
            RotationDescription::Current,
        );
        self.vanishing.push(query);

        let query = Query::new(
            Commitments::VanishingRand, //"vanishingRand".to_string(),
            Evaluations::RandomEval,    //"randomEval".to_string(),
            RotationDescription::Current,
        );
        self.vanishing.push(query);
    }

    /// Extract a lookup query to the CircuitQueries structure.
    pub(crate) fn lookup(
        &mut self,
        commitment: Commitments,
        evaluation: Evaluations,
        point: RotationDescription,
    ) {
        let query = Query::new(commitment, evaluation, point);
        self.lookup.push(query);
    }

    /// Extract a trash query to the CircuitQueries structure.
    // CHANGED vs upstream: new method for the Midnight circuit's trash columns.
    pub(crate) fn trash(&mut self, index: usize) {
        let query = Query::new(
            Commitments::Trash(index),
            Evaluations::Trash(index),
            RotationDescription::Current,
        );
        self.trash.push(query);
    }
}
