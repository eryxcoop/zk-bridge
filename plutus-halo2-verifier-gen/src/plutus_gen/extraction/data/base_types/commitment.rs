//! Commitments type

use serde::{Deserialize, Serialize};

/// Commitments' types
#[derive(Clone, Copy, Debug, Serialize, Deserialize, Eq, PartialEq, Hash)]
pub(crate) enum Commitments {
    // CHANGED vs upstream: added for Midnight support — the STM circuit uses
    // committed instances (instance columns committed as polynomials).
    CommittedInstance(usize),
    Advice(usize),
    Fixed(usize),
    Permutation(char),
    PermutationsCommon(usize),
    VanishingG,
    VanishingRand,
    Lookup(usize),
    PermutedInput(usize),
    PermutedTable(usize),
    // CHANGED vs upstream: added for Midnight support — "trash" columns present
    // in the Midnight STM circuit but absent from the original toy examples.
    Trash(usize),
}

impl Default for Commitments {
    fn default() -> Self {
        Commitments::Advice(0)
    }
}
