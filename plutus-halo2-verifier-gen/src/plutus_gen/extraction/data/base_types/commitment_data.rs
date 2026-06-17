//! CommitmentData type

use super::*;

/// Type storing all information associated to a commitment
#[derive(Clone, Debug, Default)]
pub struct CommitmentData {
    pub(crate) commitment: Commitments,
    pub(crate) point_set_index: usize,
    pub(crate) evaluations: Vec<Evaluations>,
    // CHANGED vs upstream: dropped the `points: Vec<RotationDescription>` field.
    // Point sets are now resolved by index in `precompute_intermediate_sets`
    // (see pcs/mod.rs), so the per-commitment rotation list is redundant.
}
