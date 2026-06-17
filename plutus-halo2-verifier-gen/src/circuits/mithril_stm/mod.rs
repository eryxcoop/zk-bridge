pub mod circuit;
pub mod errors;
mod crypto;
mod eligibility;
mod runtime;
pub mod types;
pub mod witness;
pub(crate) mod witness_assignments;

pub(crate) mod gadgets;

pub(crate) type StmError = anyhow::Error;
pub(crate) type StmResult<T> = Result<T, StmError>;

pub use circuit::StmCircuit;
pub use runtime::{
    GeneratedStmProof, NormalizedStmBundle, NormalizedStmCertificate,
    NormalizedStmCertificates, NormalizedStmMerklePath, NormalizedStmParameters,
    NormalizedStmRegistration, NormalizedStmStatement, NormalizedStmWitness,
    NormalizedStmWitnessEntry, generate_stm_fixture_bundle, generate_stm_proof,
    generate_stm_proof_fixture, generate_stm_proof_from_bundle,
};
