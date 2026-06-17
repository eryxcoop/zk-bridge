//! ProofExtractionSteps type

use serde::{Deserialize, Serialize};

/// This type lists all potential steps of the verifier.
/// It is used to emit the right number of phases in the given language.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub(crate) enum ProofExtractionSteps {
    // Advice and fixed column related steps
    AdviceCommitments,
    // CHANGED vs upstream: added for Midnight support (committed-instance eval step).
    InstanceEval,
    AdviceEval,
    FixedEval,
    // Lookup steps
    PermutationsCommitted,
    PermutationEval(char),
    PermutationCommon,
    // Lookup steps
    LookupPermuted,
    LookupCommitment,
    LookupEval,
    // CHANGED vs upstream: added for Midnight support — trash-column commitment
    // and evaluation steps.
    TrashCommitment,
    TrashEval,
    // Vanishing polynoial steps
    VanishingRand,
    RandomEval,
    VanishingSplit,
    // Challenges extraction
    SqueezeChallenge,
    // CHANGED vs upstream: added for Midnight support (trash-column challenge).
    TrashChallenge,
    XCoordinate,
    YCoordinate,
    Theta,
    Beta,
    Gamma,
}
