use anyhow::{anyhow, bail, ensure, Context, Result};
use blake2b_simd::Params as Blake2bParams;
use blstrs::{G1Projective as BlstrsG1Projective, Scalar as BlstrsScalar};
use ff::{Field, PrimeField};
use group::{Curve, Group, GroupEncoding};
use midnight_curves::{
    Bls12 as MidnightBls12, Fq as MidnightScalar, G1Projective as MidnightG1Projective,
    G2Affine as MidnightG2Affine,
};
use midnight_proofs::poly::{
    kzg::params::ParamsKZG as MidnightParamsKZG,
    kzg::KZGCommitmentScheme as MidnightKZGCommitmentScheme,
};
use midnight_proofs::plonk::prepare as prepare_midnight_verifier;
use midnight_proofs::transcript::{CircuitTranscript, Hashable, Transcript};
use midnight_zk_stdlib::{self as zk, MidnightCircuit};
use rand_chacha::ChaCha20Rng;
use rand_core::SeedableRng;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::Path;

use crate::circuits::mithril_stm::{
    generate_stm_proof_from_bundle, types::CircuitBase, GeneratedStmProof, NormalizedStmBundle,
    NormalizedStmCertificate, NormalizedStmCertificates, NormalizedStmMerklePath,
    NormalizedStmParameters, NormalizedStmRegistration, NormalizedStmStatement,
    NormalizedStmWitness, NormalizedStmWitnessEntry, StmCircuit,
};
use crate::plutus_gen::adjusted_types::CardanoFriendlyBlake2b;
use crate::plutus_gen::extraction::conversion::{
    g1_projective_from_midnight, scalar_from_midnight,
};
use crate::plutus_gen::extraction::data::{
    CircuitExpression, CircuitRepresentation, Commitments, Evaluations, ProofExtractionSteps,
    RotationDescription, ScalarExpression,
};
use crate::plutus_gen::extraction::pcs::kzg::HMOSteps;
use crate::plutus_gen::{extract_circuit_midnight, ExtractPCS};

const PROOF_EXPORT_SCHEMA_VERSION: &str = "1.0.0";
const BUNDLE_SCHEMA_VERSION: &str = "1.0.0";
const BUNDLE_KIND: &str = "mithril_stm_bundle";
const GENERATOR_REPO: &str = "plutus-halo2-verifier-gen";
const GENERATOR_CIRCUIT: &str = "mithril_stm";
const PHASE1_PREFIX_COMMITMENTS: usize = 17;

type StmMidnightPcs = MidnightKZGCommitmentScheme<MidnightBls12>;
type StmCircuitRepresentation = CircuitRepresentation<StmMidnightPcs>;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InputBundle {
    pub schema_version: String,
    pub bundle_kind: String,
    pub source: InputSource,
    pub circuit: InputCircuit,
    pub stm_parameters: InputParameters,
    pub certificates: InputCertificates,
    pub statement: InputStatement,
    pub registration: InputRegistration,
    pub witness: InputWitness,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InputSource {
    pub source_id: String,
    pub source_kind: String,
    pub network: String,
    #[serde(default)]
    pub generated_at: Option<String>,
    #[serde(default)]
    pub notes: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InputCircuit {
    pub name: String,
    pub public_input_contract: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InputParameters {
    pub m: u64,
    pub k: u64,
    pub phi_f: InputPhiF,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum InputPhiF {
    Number(f64),
    Hex(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InputCertificates {
    pub parent: InputCertificate,
    pub child: InputCertificate,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InputCertificate {
    pub kind: String,
    pub hash: String,
    pub prev_hash: String,
    pub epoch: u64,
    pub metadata: CertificateMetadata,
    pub protocol_parameters: CertificateProtocolParameters,
    pub protocol_message: CertificateProtocolMessage,
    pub signed_message: String,
    pub aggregate_verification_key_text: String,
    pub aggregate_verification_key_snark_text: String,
    pub signature: CertificateSignatureInfo,
    pub signed_entity: SignedEntity,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CertificateMetadata {
    pub network: String,
    pub protocol_version: String,
    pub initiated_at: String,
    pub sealed_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CertificateProtocolParameters {
    pub k: u64,
    pub m: u64,
    pub phi_f: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CertificateProtocolMessage {
    pub current_epoch_text: String,
    pub next_aggregate_verification_key_text: String,
    pub next_aggregate_verification_key_snark_text: String,
    pub next_protocol_parameters_text: String,
    #[serde(default)]
    pub cardano_transactions_merkle_root_hex: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CertificateSignatureInfo {
    #[serde(rename = "type")]
    pub signature_type: String,
    pub bytes_hex: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignedEntity {
    pub kind: String,
    #[serde(default)]
    pub epoch: Option<u64>,
    #[serde(default)]
    pub block_number: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InputStatement {
    pub public_input_1_merkle_root: String,
    pub public_input_2_signed_message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InputRegistration {
    pub total_stake: u64,
    pub parties_count: usize,
    pub merkle_tree_depth: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InputWitness {
    pub entries: Vec<InputWitnessEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InputWitnessEntry {
    pub signer_index: usize,
    pub lottery_index: u64,
    pub verification_key_snark: String,
    pub target: String,
    pub merkle_path: InputMerklePath,
    pub unique_schnorr_signature: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InputMerklePath {
    pub leaf_index: usize,
    pub siblings: Vec<String>,
}

/// Canonical, self-contained proof export for a single Mithril STM proof.
///
/// This is the file-based contract between this generator and `bridge-aiken`:
/// the generator serializes it to JSON (validated against
/// `schemas/mithril_stm_proof_export.schema.json`) and the bridge reads it.
/// It bundles everything the on-chain verifier needs to check one proof,
/// already split for the two-phase Aiken verifier (`phase1_state` /
/// `reduced_redeemer`).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MithrilStmProofExport {
    /// Version of the proof-export format; checked on load against
    /// `PROOF_EXPORT_SCHEMA_VERSION` so an incompatible file is rejected.
    pub schema_version: String,
    /// Provenance of the input bundle this proof was generated from.
    pub source_bundle: SourceBundle,
    /// Metadata about the generator (repo, circuit, version) that produced this.
    pub generator: GeneratorMetadata,
    /// The two public inputs verified by the proof (merkle root + signed message).
    pub statement: Statement,
    /// The raw SNARK proof bytes (hex).
    pub proof: Proof,
    /// State carried from the phase-1 transaction to the phase-2 transaction.
    pub phase1_state: Phase1State,
    /// Proof commitments consumed as the redeemer of the phase-2 transaction.
    pub reduced_redeemer: ReducedRedeemer,
    /// The Mithril certificates (parent/child) this proof attests to.
    pub certificates: InputCertificates,
    /// Flattened mirrors of the data above, shaped for direct bridge consumption.
    pub bridge_aiken: BridgeAikenCompat,
}

/// Provenance header identifying where this proof export came from. Downstream
/// bridge flows read `source_id` to identify and log which bundle is being
/// consumed; the schema/kind/hash fields pin the input format and content.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SourceBundle {
    pub bundle_schema_version: String,
    pub bundle_kind: String,
    pub source_id: String,
    pub bundle_hash_hex: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GeneratorMetadata {
    pub repo: String,
    pub circuit: String,
    pub proof_export_schema_version: String,
    pub notes: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Statement {
    pub public_input_1: String,
    pub public_input_2: String,
    /// Compatibility mirror of `public_input_2` for downstream consumers that
    /// still speak in terms of "statement hash".
    pub statement_hash: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Proof {
    pub proof_bytes: String,
}

/// State the phase-1 transaction computes and hands to the phase-2 transaction
/// (via the on-chain datum).
///
/// The production verifier splits the KZG pairing check across two transactions
/// to fit the Plutus budget. Phase 1 does the heavy partial work — accumulating
/// the first `PHASE1_PREFIX_COMMITMENTS` commitments and pinning the transcript
/// challenges — so that phase 2 only has to fold in the remaining commitments
/// (the [`ReducedRedeemer`]) and run the final pairing.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Phase1State {
    /// Partial right-hand-side accumulation: the first
    /// `PHASE1_PREFIX_COMMITMENTS` set-0 commitments folded with powers of `x1`,
    /// as a compressed G1 point (hex). Precomputed here so phase 2 skips it.
    pub rhs_prefix: String,
    /// `blake2b-256` of the serialized [`ReducedRedeemer`] (hex). Commits phase 1
    /// to the exact redeemer phase 2 must supply, and is reused as the phase-2
    /// token name.
    pub reduced_hash: String,
    /// Fiat-Shamir challenge scalars from the proof transcript (32-byte LE).
    pub x1: String,
    pub x3: String,
    pub x4: String,
    /// Aggregated KZG batch-evaluation scalar `v` (32-byte LE), used to build the
    /// `-v·G` term of the pairing's right-hand side.
    pub v: String,
}

/// The proof commitments phase 2 needs to finish rebuilding the pairing's
/// right-hand side (the commitments not already folded into
/// [`Phase1State::rhs_prefix`]).
///
/// This is the "reduced" redeemer: every field is a single compressed G1 point
/// (hex). Its `blake2b-256` hash is pinned in [`Phase1State::reduced_hash`], so
/// phase 2 cannot tamper with the set phase 1 committed to.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReducedRedeemer {
    /// Vanishing-argument quotient commitment.
    pub vanishing_g: String,
    /// Vanishing-argument random/blinding commitment.
    pub vanishing_rand: String,
    /// Advice column commitments a{column_number}.
    pub a1: String,
    pub a2: String,
    pub a3: String,
    /// Permutation grand-product commitment `d`.
    pub perm_d: String,
    /// Lookup argument commitments
    pub lookup_1: String,
    pub lookup_2: String,
    /// Permutation grand-product commitments
    pub perm_a: String,
    pub perm_b: String,
    pub perm_c: String,
    /// Permuted lookup input commitments
    pub perm_input_1: String,
    pub perm_input_2: String,
    /// Commitment to the batched `f` polynomial (multi-open aggregation).
    pub f_commitment: String,
    /// Public-input term commitment (`pi_term`), scaled by `x3` in phase 2.
    pub pi_term: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeAikenCompat {
    pub phase1: BridgeAikenPhase1Compat,
    pub phase2: BridgeAikenPhase2Compat,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeAikenPhase1Compat {
    pub proof_bytes: String,
    pub public_input_1: String,
    pub public_input_2: String,
    pub phase1_state_rhs_prefix: String,
    pub phase1_state_reduced_hash: String,
    pub phase1_state_x1: String,
    pub phase1_state_x3: String,
    pub phase1_state_x4: String,
    pub phase1_state_v: String,
    /// Compatibility mirror of the canonical statement digest.
    pub statement_hash_value: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeAikenPhase2Compat {
    pub token_name: String,
    /// Compatibility mirror of the canonical statement digest.
    pub proof_receipt_statement_hash: String,
    pub reduced_redeemer_vanishing_g: String,
    pub reduced_redeemer_vanishing_rand: String,
    pub reduced_redeemer_a1: String,
    pub reduced_redeemer_a2: String,
    pub reduced_redeemer_a3: String,
    pub reduced_redeemer_perm_d: String,
    pub reduced_redeemer_lookup_1: String,
    pub reduced_redeemer_lookup_2: String,
    pub reduced_redeemer_perm_a: String,
    pub reduced_redeemer_perm_b: String,
    pub reduced_redeemer_perm_c: String,
    pub reduced_redeemer_perm_input_1: String,
    pub reduced_redeemer_perm_input_2: String,
    pub reduced_redeemer_f_commitment: String,
    pub reduced_redeemer_pi_term: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct MithrilStmSplitDebugReport {
    pub bundle_path: String,
    pub proof_export_path: String,
    pub s_g2: String,
    pub native_guard_ok: bool,
    pub native_blstrs_pairing_ok: bool,
    pub native_left: String,
    pub native_right: String,
    pub parsed_pi_term: String,
    pub left_matches_pi_term: bool,
    pub full_right: String,
    pub split_right: String,
    pub matches: bool,
    pub full_matches_native_right: bool,
    pub split_matches_native_right: bool,
    pub rhs_prefix: String,
    pub set_0_suffix: String,
    pub set_1: String,
    pub set_2: String,
    pub set_3: String,
    pub f_term: String,
    pub v_term: String,
    pub pi_term_scaled: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MithrilStmNativeGuardDebugReport {
    pub bundle_path: String,
    pub proof_export_path: String,
    pub native_guard_ok: bool,
    pub midnight_pairing_ok: bool,
    pub blstrs_pairing_ok: bool,
    pub midnight_left: String,
    pub midnight_right: String,
    pub blstrs_left: String,
    pub blstrs_right: String,
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

#[derive(Debug)]
struct DerivedSplitProofData {
    phase1_state: Phase1State,
    reduced_redeemer: ReducedRedeemer,
}

impl Statement {
    fn new(public_input_1: String, public_input_2: String) -> Self {
        Self {
            public_input_1,
            statement_hash: public_input_2.clone(),
            public_input_2,
        }
    }

    fn canonical_statement_hash(&self) -> &str {
        &self.public_input_2
    }
}

impl BridgeAikenPhase1Compat {
    fn statement_hash_value(&self) -> &str {
        &self.statement_hash_value
    }
}

impl BridgeAikenPhase2Compat {
    fn proof_receipt_statement_hash(&self) -> &str {
        &self.proof_receipt_statement_hash
    }
}

impl MithrilStmProofExport {
    fn canonical_statement_hash(&self) -> &str {
        self.statement.canonical_statement_hash()
    }
}

impl InputPhiF {
    fn to_f64(&self) -> Result<f64> {
        match self {
            Self::Number(value) => Ok(*value),
            Self::Hex(hex) => parse_phi_f_hex(hex),
        }
    }
}

impl InputBundle {
    fn validate(&self) -> Result<()> {
        ensure!(
            self.schema_version == BUNDLE_SCHEMA_VERSION,
            "Unsupported bundle schema version: {}",
            self.schema_version
        );
        ensure!(
            self.bundle_kind == BUNDLE_KIND,
            "Unsupported bundle kind: {}",
            self.bundle_kind
        );
        ensure!(
            self.circuit.name == GENERATOR_CIRCUIT,
            "Unsupported bundle circuit: {}",
            self.circuit.name
        );
        ensure!(
            self.statement.public_input_2_signed_message == self.certificates.child.signed_message,
            "statement.public_input_2_signed_message must match child certificate signed_message"
        );

        Ok(())
    }

    fn to_runtime_bundle(&self) -> Result<NormalizedStmBundle> {
        self.validate()?;

        let entries = self
            .witness
            .entries
            .iter()
            .map(|entry| {
                Ok(NormalizedStmWitnessEntry {
                    signer_index: entry.signer_index,
                    lottery_index: entry.lottery_index,
                    verification_key_snark: decode_hex_bytes(&entry.verification_key_snark)?,
                    target: decode_bytes32(&entry.target)?,
                    merkle_path: NormalizedStmMerklePath {
                        leaf_index: entry.merkle_path.leaf_index,
                        siblings: entry
                            .merkle_path
                            .siblings
                            .iter()
                            .map(|sibling| decode_bytes32(sibling))
                            .collect::<Result<Vec<_>>>()?,
                    },
                    unique_schnorr_signature: decode_hex_bytes(&entry.unique_schnorr_signature)?,
                })
            })
            .collect::<Result<Vec<_>>>()?;

        Ok(NormalizedStmBundle {
            schema_version: self.schema_version.clone(),
            bundle_kind: self.bundle_kind.clone(),
            source_id: self.source.source_id.clone(),
            stm_parameters: NormalizedStmParameters {
                m: self.stm_parameters.m,
                k: self.stm_parameters.k,
                phi_f: self.stm_parameters.phi_f.to_f64()?,
            },
            certificates: NormalizedStmCertificates {
                parent: NormalizedStmCertificate {
                    hash: decode_bytes32(&self.certificates.parent.hash)?,
                    prev_hash: decode_hex_bytes(&self.certificates.parent.prev_hash)?,
                    epoch: self.certificates.parent.epoch,
                    signed_message: decode_bytes32(&self.certificates.parent.signed_message)?,
                },
                child: NormalizedStmCertificate {
                    hash: decode_bytes32(&self.certificates.child.hash)?,
                    prev_hash: decode_hex_bytes(&self.certificates.child.prev_hash)?,
                    epoch: self.certificates.child.epoch,
                    signed_message: decode_bytes32(&self.certificates.child.signed_message)?,
                },
            },
            statement: NormalizedStmStatement {
                public_input_1_merkle_root: decode_bytes32(
                    &self.statement.public_input_1_merkle_root,
                )?,
                public_input_2_signed_message: decode_bytes32(
                    &self.statement.public_input_2_signed_message,
                )?,
            },
            registration: NormalizedStmRegistration {
                parties_count: self.registration.parties_count,
                merkle_tree_depth: self.registration.merkle_tree_depth,
            },
            witness: NormalizedStmWitness { entries },
        })
    }
}

pub fn build_mithril_stm_proof_export(
    bundle: &InputBundle,
    bundle_hash_hex: String,
    proving_seed: [u8; 32],
) -> Result<MithrilStmProofExport> {
    let runtime_bundle = bundle.to_runtime_bundle()?;
    let generated = generate_stm_proof_from_bundle(&runtime_bundle, proving_seed)?;
    let derived = derive_split_proof_data(&generated)?;

    let public_input_1 = bytes32_hex(&circuit_base_bytes32(CircuitBase::from(
        generated.instance.0,
    )));
    let public_input_2 = bytes32_hex(&circuit_base_bytes32(CircuitBase::from(
        generated.instance.1,
    )));
    let proof_bytes = hex_bytes(&generated.proof);
    let statement = Statement::new(public_input_1.clone(), public_input_2.clone());
    let canonical_statement_hash = statement.canonical_statement_hash().to_string();

    let phase1 = BridgeAikenPhase1Compat {
        proof_bytes: proof_bytes.clone(),
        public_input_1: public_input_1.clone(),
        public_input_2: public_input_2.clone(),
        phase1_state_rhs_prefix: derived.phase1_state.rhs_prefix.clone(),
        phase1_state_reduced_hash: derived.phase1_state.reduced_hash.clone(),
        phase1_state_x1: derived.phase1_state.x1.clone(),
        phase1_state_x3: derived.phase1_state.x3.clone(),
        phase1_state_x4: derived.phase1_state.x4.clone(),
        phase1_state_v: derived.phase1_state.v.clone(),
        statement_hash_value: canonical_statement_hash.clone(),
    };

    let phase2 = BridgeAikenPhase2Compat {
        token_name: derived.phase1_state.reduced_hash.clone(),
        proof_receipt_statement_hash: canonical_statement_hash.clone(),
        reduced_redeemer_vanishing_g: derived.reduced_redeemer.vanishing_g.clone(),
        reduced_redeemer_vanishing_rand: derived.reduced_redeemer.vanishing_rand.clone(),
        reduced_redeemer_a1: derived.reduced_redeemer.a1.clone(),
        reduced_redeemer_a2: derived.reduced_redeemer.a2.clone(),
        reduced_redeemer_a3: derived.reduced_redeemer.a3.clone(),
        reduced_redeemer_perm_d: derived.reduced_redeemer.perm_d.clone(),
        reduced_redeemer_lookup_1: derived.reduced_redeemer.lookup_1.clone(),
        reduced_redeemer_lookup_2: derived.reduced_redeemer.lookup_2.clone(),
        reduced_redeemer_perm_a: derived.reduced_redeemer.perm_a.clone(),
        reduced_redeemer_perm_b: derived.reduced_redeemer.perm_b.clone(),
        reduced_redeemer_perm_c: derived.reduced_redeemer.perm_c.clone(),
        reduced_redeemer_perm_input_1: derived.reduced_redeemer.perm_input_1.clone(),
        reduced_redeemer_perm_input_2: derived.reduced_redeemer.perm_input_2.clone(),
        reduced_redeemer_f_commitment: derived.reduced_redeemer.f_commitment.clone(),
        reduced_redeemer_pi_term: derived.reduced_redeemer.pi_term.clone(),
    };

    let proof_export = MithrilStmProofExport {
        schema_version: PROOF_EXPORT_SCHEMA_VERSION.to_string(),
        source_bundle: SourceBundle {
            bundle_schema_version: bundle.schema_version.clone(),
            bundle_kind: bundle.bundle_kind.clone(),
            source_id: bundle.source.source_id.clone(),
            bundle_hash_hex,
        },
        generator: GeneratorMetadata {
            repo: GENERATOR_REPO.to_string(),
            circuit: GENERATOR_CIRCUIT.to_string(),
            proof_export_schema_version: env!("CARGO_PKG_VERSION").to_string(),
            notes: "PoC export for bridge-aiken phase1/phase2 consumption".to_string(),
        },
        statement,
        proof: Proof { proof_bytes },
        phase1_state: derived.phase1_state,
        reduced_redeemer: derived.reduced_redeemer,
        certificates: bundle.certificates.clone(),
        bridge_aiken: BridgeAikenCompat { phase1, phase2 },
    };

    validate_mithril_stm_proof_export(&proof_export)?;
    Ok(proof_export)
}

pub fn export_mithril_stm_proof_export(
    input_path: &Path,
    output_path: &Path,
    proving_seed: [u8; 32],
) -> Result<MithrilStmProofExport> {
    let bundle_bytes = fs::read(input_path)
        .with_context(|| format!("Failed to read bundle file {}", input_path.display()))?;
    let bundle_hash_hex = blake2b_256_hex(&bundle_bytes);
    let bundle: InputBundle = serde_json::from_slice(&bundle_bytes)
        .with_context(|| format!("Failed to deserialize bundle {}", input_path.display()))?;
    let proof_export = build_mithril_stm_proof_export(&bundle, bundle_hash_hex, proving_seed)?;
    let serialized =
        serde_json::to_vec_pretty(&proof_export).context("Failed to serialize proof_export to JSON")?;
    fs::write(output_path, serialized)
        .with_context(|| format!("Failed to write proof_export file {}", output_path.display()))?;
    Ok(proof_export)
}

pub fn validate_proof_export_file(path: &Path) -> Result<MithrilStmProofExport> {
    let bytes =
        fs::read(path).with_context(|| format!("Failed to read proof_export {}", path.display()))?;
    let proof_export: MithrilStmProofExport = serde_json::from_slice(&bytes)
        .with_context(|| format!("Failed to deserialize proof_export {}", path.display()))?;
    validate_mithril_stm_proof_export(&proof_export)?;
    Ok(proof_export)
}

#[derive(Debug, Clone, Deserialize)]
struct CompatibleBundleProofStatement {
    statement_hash: String,
    public_input_2: String,
}

#[derive(Debug, Clone, Deserialize)]
struct CompatibleBundleProofEntry {
    statement: CompatibleBundleProofStatement,
    bridge_aiken: BridgeAikenCompat,
    certificate: InputCertificate,
}

/// Validates a bridge-compatible Mithril STM bundle by reconstructing a
/// `MithrilStmProofExport` for each entry under `proofs.<domain>` and applying
/// the same invariants as `validate_mithril_stm_proof_export`. This is the
/// canonical contract check now that the standalone `mithril_stm_proof_export.json`
/// has been retired.
pub fn validate_compatible_bundle_file(path: &Path) -> Result<()> {
    let bytes = fs::read(path)
        .with_context(|| format!("Failed to read compatible bundle {}", path.display()))?;
    let value: serde_json::Value = serde_json::from_slice(&bytes)
        .with_context(|| format!("Failed to deserialize bundle JSON {}", path.display()))?;
    // public_input_1 (the stake-distribution merkle root) is shared by every
    // proof in the bundle, so it lives once at the top-level statement.
    let public_input_1 = value
        .get("statement")
        .and_then(|v| v.get("public_input_1"))
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| {
            anyhow!(
                "compatible bundle missing top-level statement.public_input_1: {}",
                path.display()
            )
        })?;
    let proofs = value
        .get("proofs")
        .and_then(|v| v.as_object())
        .ok_or_else(|| {
            anyhow!(
                "compatible bundle missing `proofs` section: {}",
                path.display()
            )
        })?;

    if proofs.is_empty() {
        bail!(
            "compatible bundle `proofs` section is empty: {}",
            path.display()
        );
    }

    for (proof_name, proof_value) in proofs {
        let entry: CompatibleBundleProofEntry = serde_json::from_value(proof_value.clone())
            .with_context(|| {
                format!("failed to parse proofs.{} of {}", proof_name, path.display())
            })?;
        let virtual_proof_export = build_virtual_proof_export_from_proof_entry(&entry, &public_input_1);
        validate_mithril_stm_proof_export(&virtual_proof_export).with_context(|| {
            format!(
                "proofs.{} failed contract validation in {}",
                proof_name,
                path.display()
            )
        })?;
    }

    Ok(())
}

fn build_virtual_proof_export_from_proof_entry(
    entry: &CompatibleBundleProofEntry,
    public_input_1: &str,
) -> MithrilStmProofExport {
    let phase1_state = Phase1State {
        rhs_prefix: entry.bridge_aiken.phase1.phase1_state_rhs_prefix.clone(),
        reduced_hash: entry.bridge_aiken.phase1.phase1_state_reduced_hash.clone(),
        x1: entry.bridge_aiken.phase1.phase1_state_x1.clone(),
        x3: entry.bridge_aiken.phase1.phase1_state_x3.clone(),
        x4: entry.bridge_aiken.phase1.phase1_state_x4.clone(),
        v: entry.bridge_aiken.phase1.phase1_state_v.clone(),
    };
    let reduced_redeemer = ReducedRedeemer {
        vanishing_g: entry.bridge_aiken.phase2.reduced_redeemer_vanishing_g.clone(),
        vanishing_rand: entry
            .bridge_aiken
            .phase2
            .reduced_redeemer_vanishing_rand
            .clone(),
        a1: entry.bridge_aiken.phase2.reduced_redeemer_a1.clone(),
        a2: entry.bridge_aiken.phase2.reduced_redeemer_a2.clone(),
        a3: entry.bridge_aiken.phase2.reduced_redeemer_a3.clone(),
        perm_d: entry.bridge_aiken.phase2.reduced_redeemer_perm_d.clone(),
        lookup_1: entry.bridge_aiken.phase2.reduced_redeemer_lookup_1.clone(),
        lookup_2: entry.bridge_aiken.phase2.reduced_redeemer_lookup_2.clone(),
        perm_a: entry.bridge_aiken.phase2.reduced_redeemer_perm_a.clone(),
        perm_b: entry.bridge_aiken.phase2.reduced_redeemer_perm_b.clone(),
        perm_c: entry.bridge_aiken.phase2.reduced_redeemer_perm_c.clone(),
        perm_input_1: entry.bridge_aiken.phase2.reduced_redeemer_perm_input_1.clone(),
        perm_input_2: entry.bridge_aiken.phase2.reduced_redeemer_perm_input_2.clone(),
        f_commitment: entry.bridge_aiken.phase2.reduced_redeemer_f_commitment.clone(),
        pi_term: entry.bridge_aiken.phase2.reduced_redeemer_pi_term.clone(),
    };
    // `validate_mithril_stm_proof_export` only inspects the child certificate;
    // we reuse it as a placeholder for the parent slot since the validator
    // never reads it.
    let child = entry.certificate.clone();
    let parent = child.clone();
    MithrilStmProofExport {
        schema_version: PROOF_EXPORT_SCHEMA_VERSION.to_string(),
        source_bundle: SourceBundle {
            bundle_schema_version: BUNDLE_SCHEMA_VERSION.to_string(),
            bundle_kind: BUNDLE_KIND.to_string(),
            source_id: "compatible-bundle-virtual".to_string(),
            bundle_hash_hex: bytes32_hex(&[0u8; 32]),
        },
        generator: GeneratorMetadata {
            repo: GENERATOR_REPO.to_string(),
            circuit: GENERATOR_CIRCUIT.to_string(),
            proof_export_schema_version: env!("CARGO_PKG_VERSION").to_string(),
            notes: "virtual proof_export for compatible-bundle proof entry".to_string(),
        },
        statement: Statement {
            public_input_1: public_input_1.to_string(),
            public_input_2: entry.statement.public_input_2.clone(),
            statement_hash: entry.statement.statement_hash.clone(),
        },
        proof: Proof {
            proof_bytes: entry.bridge_aiken.phase1.proof_bytes.clone(),
        },
        phase1_state,
        reduced_redeemer,
        certificates: InputCertificates { parent, child },
        bridge_aiken: entry.bridge_aiken.clone(),
    }
}

pub fn validate_mithril_stm_proof_export(proof_export: &MithrilStmProofExport) -> Result<()> {
    ensure!(
        proof_export.schema_version == PROOF_EXPORT_SCHEMA_VERSION,
        "Unsupported proof_export schema version: {}",
        proof_export.schema_version
    );
    ensure!(
        proof_export.statement.statement_hash == proof_export.canonical_statement_hash(),
        "statement_hash must equal public_input_2"
    );
    ensure!(
        proof_export.bridge_aiken.phase1.statement_hash_value() == proof_export.canonical_statement_hash(),
        "bridge_aiken.phase1.statement_hash_value must equal statement_hash"
    );
    ensure!(
        proof_export.bridge_aiken.phase2.proof_receipt_statement_hash()
            == proof_export.canonical_statement_hash(),
        "bridge_aiken.phase2.proof_receipt_statement_hash must equal statement_hash"
    );
    ensure!(
        proof_export.bridge_aiken.phase2.token_name == proof_export.phase1_state.reduced_hash,
        "bridge_aiken.phase2.token_name must equal phase1_state.reduced_hash"
    );
    ensure!(
        proof_export.certificates.child.signed_message == proof_export.canonical_statement_hash(),
        "child certificate signed_message must equal public_input_2"
    );
    ensure!(
        proof_export.proof.proof_bytes == proof_export.bridge_aiken.phase1.proof_bytes,
        "bridge_aiken.phase1.proof_bytes must mirror proof.proof_bytes"
    );
    ensure!(
        proof_export.phase1_state.rhs_prefix == proof_export.bridge_aiken.phase1.phase1_state_rhs_prefix,
        "bridge_aiken.phase1.phase1_state_rhs_prefix must mirror phase1_state.rhs_prefix"
    );

    let reduced_hash = bytes32_hex(&hash_reduced_redeemer(&proof_export.reduced_redeemer));
    ensure!(
        reduced_hash == proof_export.phase1_state.reduced_hash,
        "phase1_state.reduced_hash must equal blake2b_256(serialized reduced redeemer)"
    );

    decode_bytes32(&proof_export.statement.public_input_1)?;
    decode_bytes32(proof_export.canonical_statement_hash())?;
    decode_bytes32(&proof_export.statement.statement_hash)?;
    decode_bytes32(&proof_export.phase1_state.reduced_hash)?;
    decode_bytes32(&proof_export.phase1_state.x1)?;
    decode_bytes32(&proof_export.phase1_state.x3)?;
    decode_bytes32(&proof_export.phase1_state.x4)?;
    decode_bytes32(&proof_export.phase1_state.v)?;
    decode_hex_bytes(&proof_export.phase1_state.rhs_prefix)?;
    decode_hex_bytes(&proof_export.proof.proof_bytes)?;
    decode_hex_bytes(&proof_export.reduced_redeemer.vanishing_g)?;
    decode_hex_bytes(&proof_export.reduced_redeemer.vanishing_rand)?;
    decode_hex_bytes(&proof_export.reduced_redeemer.a1)?;
    decode_hex_bytes(&proof_export.reduced_redeemer.a2)?;
    decode_hex_bytes(&proof_export.reduced_redeemer.a3)?;
    decode_hex_bytes(&proof_export.reduced_redeemer.perm_d)?;
    decode_hex_bytes(&proof_export.reduced_redeemer.lookup_1)?;
    decode_hex_bytes(&proof_export.reduced_redeemer.lookup_2)?;
    decode_hex_bytes(&proof_export.reduced_redeemer.perm_a)?;
    decode_hex_bytes(&proof_export.reduced_redeemer.perm_b)?;
    decode_hex_bytes(&proof_export.reduced_redeemer.perm_c)?;
    decode_hex_bytes(&proof_export.reduced_redeemer.perm_input_1)?;
    decode_hex_bytes(&proof_export.reduced_redeemer.perm_input_2)?;
    decode_hex_bytes(&proof_export.reduced_redeemer.f_commitment)?;
    decode_hex_bytes(&proof_export.reduced_redeemer.pi_term)?;

    Ok(())
}

pub fn debug_compare_proof_export_split_with_bundle(
    bundle_path: &Path,
    proof_export_path: &Path,
) -> Result<MithrilStmSplitDebugReport> {
    use group::prime::PrimeCurveAffine;
    use midnight_curves::pairing::{MillerLoopResult as _, MultiMillerLoop};
    use midnight_proofs::poly::commitment::Guard as _;

    let bundle_contents = fs::read_to_string(bundle_path)
        .with_context(|| format!("Failed to read bundle file {}", bundle_path.display()))?;
    let bundle: InputBundle = serde_json::from_str(&bundle_contents)
        .with_context(|| format!("Failed to parse bundle JSON {}", bundle_path.display()))?;
    bundle.validate()?;
    let runtime_bundle = bundle.to_runtime_bundle()?;

    let proof_export = validate_proof_export_file(proof_export_path)?;

    let generated = generate_stm_proof_from_bundle(&runtime_bundle, [0u8; 32]).with_context(|| {
        format!(
            "Failed to regenerate the Mithril STM circuit from bundle {}",
            bundle_path.display()
        )
    })?;

    let proof_bytes = decode_hex_bytes(&proof_export.proof.proof_bytes)?;
    let circuit = StmCircuit::try_new(&generated.params, generated.merkle_tree_depth)?;
    let min_k = MidnightCircuit::from_relation(&circuit).min_k();
    let srs =
        MidnightParamsKZG::<MidnightBls12>::unsafe_setup(min_k, ChaCha20Rng::seed_from_u64(42));
    let vk = zk::setup_vk(&srs, &circuit);

    let public_inputs = [
        CircuitBase::from(generated.instance.0),
        CircuitBase::from(generated.instance.1),
    ];
    let empty_committed: [MidnightScalar; 0] = [];
    let columns: [&[MidnightScalar]; 2] = [&empty_committed, &public_inputs];
    let instances: [&[&[MidnightScalar]]; 1] = [&columns];
    let circuit_repr = extract_circuit_midnight::<StmMidnightPcs>(&srs, vk.vk(), &instances)
        .context("Failed to extract the midnight STM circuit representation")?;
    let parsed = parse_midnight_stm_proof(&circuit_repr, &vk, &instances, &proof_bytes)?;
    let normal_instance_columns: [&[MidnightScalar]; 1] = [&public_inputs];
    let normal_instances: [&[&[MidnightScalar]]; 1] = [&normal_instance_columns];

    let (unique_grouped_points, commitment_data) =
        <StmMidnightPcs as ExtractPCS>::precompute_intermediate_sets(&circuit_repr);
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
    let point_sets = build_point_sets(&circuit_repr, &unique_grouped_points, &parsed);
    let (_q_eval_sets, f_eval) =
        compute_q_eval_sets_and_f_eval(&commitment_data, &point_sets, &x1_powers, &parsed)?;

    let mut full_right = BlstrsG1Projective::identity();
    for (point_set_index, x4_power) in x4_powers.iter().take(point_sets.len()).enumerate() {
        let q_comm = commitment_data
            .iter()
            .filter(|entry| entry.point_set_index == point_set_index)
            .zip(x1_powers.iter())
            .fold(BlstrsG1Projective::identity(), |acc, (entry, x1_power)| {
                let commitment = parsed
                    .commitments
                    .get(&entry.commitment)
                    .unwrap_or_else(|| panic!("missing commitment value for {:?}", entry.commitment));
                acc + (*commitment * *x1_power)
            });
        full_right += q_comm * *x4_power;
    }
    full_right += parsed.f_commitment * *x4_powers.last().unwrap();
    let full_v = x4_powers
        .iter()
        .zip(
            parsed
                .proof_x3_q_evals
                .iter()
                .copied()
                .chain(std::iter::once(f_eval)),
        )
        .fold(BlstrsScalar::ZERO, |acc, (power, eval)| acc + (*power * eval));
    full_right +=
        (BlstrsG1Projective::generator() * (-full_v)) + (parsed.pi_term * parsed.x3);
    let mut transcript_verifier = CircuitTranscript::<CardanoFriendlyBlake2b>::init_from_bytes(&proof_bytes);
    let committed_instances_storage = circuit_repr
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
    let committed_instances_columns: [&[MidnightG1Projective]; 1] = [&committed_instances_storage];
    let guard =
        prepare_midnight_verifier::<
            _,
            MidnightKZGCommitmentScheme<MidnightBls12>,
            CircuitTranscript<CardanoFriendlyBlake2b>,
        >(
            vk.vk(),
            &committed_instances_columns,
            &normal_instances,
            &mut transcript_verifier,
        )
        .context("Failed to prepare native verifier guard terms")?;
    let native_guard_ok = guard.clone().verify(&srs.verifier_params()).is_ok();
    let (left_terms, right_terms): (Vec<_>, Vec<_>) = guard.split();
    let native_left = left_terms
        .into_iter()
        .fold(BlstrsG1Projective::identity(), |acc, (scalar, point)| {
            acc + (g1_projective_from_midnight(point).unwrap() * scalar_from_midnight(*scalar))
        });
    let native_right = right_terms
        .into_iter()
        .fold(BlstrsG1Projective::identity(), |acc, (scalar, point)| {
            acc + (g1_projective_from_midnight(point).unwrap() * scalar_from_midnight(*scalar))
        });
    let native_blstrs_pairing_ok = {
        let left_affine = blstrs::G1Affine::from(native_left);
        let right_affine = blstrs::G1Affine::from(native_right);
        let sg2 = blstrs::G2Prepared::from(circuit_repr.proof_instantiation_data.s_g2);
        let neg_g2 = blstrs::G2Prepared::from(-blstrs::G2Affine::generator());
        bool::from(
            blstrs::Bls12::multi_miller_loop(&[(&left_affine, &sg2), (&right_affine, &neg_g2)])
                .final_exponentiation()
                .is_identity(),
        )
    };

    let x1 = scalar_from_hex_le(&proof_export.phase1_state.x1)?;
    let x3 = scalar_from_hex_le(&proof_export.phase1_state.x3)?;
    let x4 = scalar_from_hex_le(&proof_export.phase1_state.x4)?;
    let v = scalar_from_hex_le(&proof_export.phase1_state.v)?;
    let x1_powers_split = powers(max_commitments_per_set, x1);
    let x4_powers_split = powers(unique_grouped_points.len() + 1, x4);

    let rhs_prefix = g1_from_hex(&proof_export.phase1_state.rhs_prefix)?;
    let set_0_suffix = commitment_data
        .iter()
        .filter(|entry| entry.point_set_index == 0)
        .skip(PHASE1_PREFIX_COMMITMENTS)
        .zip(x1_powers_split.iter().skip(PHASE1_PREFIX_COMMITMENTS))
        .fold(BlstrsG1Projective::identity(), |acc, (entry, x1_power)| {
            let commitment = parsed
                .commitments
                .get(&entry.commitment)
                .unwrap_or_else(|| panic!("missing commitment value for {:?}", entry.commitment));
            acc + (*commitment * *x1_power)
        });

    let set_1 =
        [
            &proof_export.reduced_redeemer.a1,
            &proof_export.reduced_redeemer.a2,
            &proof_export.reduced_redeemer.a3,
            &proof_export.reduced_redeemer.perm_d,
            &proof_export.reduced_redeemer.lookup_1,
            &proof_export.reduced_redeemer.lookup_2,
        ]
        .iter()
        .zip(x1_powers_split.iter())
        .fold(BlstrsG1Projective::identity(), |acc, (point_hex, x1_power)| {
            acc + (g1_from_hex(point_hex).expect("proof_export point must decode") * *x1_power)
        })
            * x4_powers_split[1];

    let set_2 =
        [
            &proof_export.reduced_redeemer.perm_a,
            &proof_export.reduced_redeemer.perm_b,
            &proof_export.reduced_redeemer.perm_c,
        ]
        .iter()
        .zip(x1_powers_split.iter())
        .fold(BlstrsG1Projective::identity(), |acc, (point_hex, x1_power)| {
            acc + (g1_from_hex(point_hex).expect("proof_export point must decode") * *x1_power)
        })
            * x4_powers_split[2];

    let set_3 =
        [
            &proof_export.reduced_redeemer.perm_input_1,
            &proof_export.reduced_redeemer.perm_input_2,
        ]
        .iter()
        .zip(x1_powers_split.iter())
        .fold(BlstrsG1Projective::identity(), |acc, (point_hex, x1_power)| {
            acc + (g1_from_hex(point_hex).expect("proof_export point must decode") * *x1_power)
        })
            * x4_powers_split[3];

    let f_term = g1_from_hex(&proof_export.reduced_redeemer.f_commitment)? * x4_powers_split[4];
    let v_term = BlstrsG1Projective::generator() * (-v);
    let pi_term_scaled = g1_from_hex(&proof_export.reduced_redeemer.pi_term)? * x3;
    let split_right = rhs_prefix + set_0_suffix + set_1 + set_2 + set_3 + f_term + v_term + pi_term_scaled;

    Ok(MithrilStmSplitDebugReport {
        bundle_path: bundle_path.display().to_string(),
        proof_export_path: proof_export_path.display().to_string(),
        s_g2: compress_g2_hex(&circuit_repr.proof_instantiation_data.s_g2),
        native_guard_ok,
        native_blstrs_pairing_ok,
        native_left: compress_g1_hex(&native_left),
        native_right: compress_g1_hex(&native_right),
        parsed_pi_term: compress_g1_hex(&parsed.pi_term),
        left_matches_pi_term: native_left == parsed.pi_term,
        full_right: compress_g1_hex(&full_right),
        split_right: compress_g1_hex(&split_right),
        matches: full_right == split_right,
        full_matches_native_right: full_right == native_right,
        split_matches_native_right: split_right == native_right,
        rhs_prefix: compress_g1_hex(&rhs_prefix),
        set_0_suffix: compress_g1_hex(&set_0_suffix),
        set_1: compress_g1_hex(&set_1),
        set_2: compress_g1_hex(&set_2),
        set_3: compress_g1_hex(&set_3),
        f_term: compress_g1_hex(&f_term),
        v_term: compress_g1_hex(&v_term),
        pi_term_scaled: compress_g1_hex(&pi_term_scaled),
    })
}

pub fn debug_native_guard_pairing_with_bundle(
    bundle_path: &Path,
    proof_export_path: &Path,
) -> Result<MithrilStmNativeGuardDebugReport> {
    use group::prime::PrimeCurveAffine;
    use midnight_curves::pairing::{MillerLoopResult as _, MultiMillerLoop};
    use midnight_proofs::poly::commitment::Guard as _;

    let bundle_contents = fs::read_to_string(bundle_path)
        .with_context(|| format!("Failed to read bundle file {}", bundle_path.display()))?;
    let bundle: InputBundle = serde_json::from_str(&bundle_contents)
        .with_context(|| format!("Failed to parse bundle JSON {}", bundle_path.display()))?;
    bundle.validate()?;
    let runtime_bundle = bundle.to_runtime_bundle()?;

    let proof_export = validate_proof_export_file(proof_export_path)?;

    let generated = generate_stm_proof_from_bundle(&runtime_bundle, [0u8; 32]).with_context(|| {
        format!(
            "Failed to regenerate the Mithril STM circuit from bundle {}",
            bundle_path.display()
        )
    })?;

    let proof_bytes = decode_hex_bytes(&proof_export.proof.proof_bytes)?;
    let circuit = StmCircuit::try_new(&generated.params, generated.merkle_tree_depth)?;
    let min_k = MidnightCircuit::from_relation(&circuit).min_k();
    let srs =
        MidnightParamsKZG::<MidnightBls12>::unsafe_setup(min_k, ChaCha20Rng::seed_from_u64(42));
    let vk = zk::setup_vk(&srs, &circuit);

    let public_inputs = [
        CircuitBase::from(generated.instance.0),
        CircuitBase::from(generated.instance.1),
    ];
    let empty_committed: [MidnightScalar; 0] = [];
    let columns: [&[MidnightScalar]; 2] = [&empty_committed, &public_inputs];
    let instances: [&[&[MidnightScalar]]; 1] = [&columns];
    let circuit_repr = extract_circuit_midnight::<StmMidnightPcs>(&srs, vk.vk(), &instances)
        .context("Failed to extract the midnight STM circuit representation")?;

    let committed_instances_storage = circuit_repr
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
    let committed_instances_columns: [&[MidnightG1Projective]; 1] = [&committed_instances_storage];

    let mut transcript_verifier =
        CircuitTranscript::<CardanoFriendlyBlake2b>::init_from_bytes(&proof_bytes);
    let guard =
        prepare_midnight_verifier::<
            _,
            MidnightKZGCommitmentScheme<MidnightBls12>,
            CircuitTranscript<CardanoFriendlyBlake2b>,
        >(
            vk.vk(),
            &committed_instances_columns,
            &instances,
            &mut transcript_verifier,
        )
        .context("Failed to prepare native verifier guard")?;

    let native_guard_ok = guard.clone().verify(&srs.verifier_params()).is_ok();
    let (left_terms, right_terms): (Vec<_>, Vec<_>) = guard.split();

    let midnight_left =
        left_terms
            .into_iter()
            .fold(MidnightG1Projective::identity(), |acc, (scalar, point)| {
                acc + (*point * *scalar)
            });
    let midnight_right =
        right_terms
            .into_iter()
            .fold(MidnightG1Projective::identity(), |acc, (scalar, point)| {
                acc + (*point * *scalar)
            });

    let sg2_blstrs = circuit_repr.proof_instantiation_data.s_g2;
    let midnight_pairing_ok = {
        let left_affine = midnight_left.to_affine();
        let right_affine = midnight_right.to_affine();
        let sg2 = midnight_curves::G2Prepared::from(midnight_g2_affine_from_blstrs(sg2_blstrs)?);
        let neg_g2 = midnight_curves::G2Prepared::from(-MidnightG2Affine::generator());
        bool::from(
            MidnightBls12::multi_miller_loop(&[(&left_affine, &sg2), (&right_affine, &neg_g2)])
                .final_exponentiation()
                .is_identity(),
        )
    };

    let blstrs_left = BlstrsG1Projective::from(g1_projective_from_midnight(&midnight_left)?);
    let blstrs_right = BlstrsG1Projective::from(g1_projective_from_midnight(&midnight_right)?);
    let blstrs_pairing_ok = {
        let left_affine = blstrs::G1Affine::from(blstrs_left);
        let right_affine = blstrs::G1Affine::from(blstrs_right);
        let sg2 = blstrs::G2Prepared::from(sg2_blstrs);
        let neg_g2 = blstrs::G2Prepared::from(-blstrs::G2Affine::generator());
        bool::from(
            blstrs::Bls12::multi_miller_loop(&[(&left_affine, &sg2), (&right_affine, &neg_g2)])
                .final_exponentiation()
                .is_identity(),
        )
    };

    Ok(MithrilStmNativeGuardDebugReport {
        bundle_path: bundle_path.display().to_string(),
        proof_export_path: proof_export_path.display().to_string(),
        native_guard_ok,
        midnight_pairing_ok,
        blstrs_pairing_ok,
        midnight_left: hex_bytes(midnight_left.to_affine().to_bytes().as_ref()),
        midnight_right: hex_bytes(midnight_right.to_affine().to_bytes().as_ref()),
        blstrs_left: compress_g1_hex(&blstrs_left),
        blstrs_right: compress_g1_hex(&blstrs_right),
    })
}

fn derive_split_proof_data(generated: &GeneratedStmProof) -> Result<DerivedSplitProofData> {
    let circuit = StmCircuit::try_new(&generated.params, generated.merkle_tree_depth)?;
    let min_k = MidnightCircuit::from_relation(&circuit).min_k();
    let srs =
        MidnightParamsKZG::<MidnightBls12>::unsafe_setup(min_k, ChaCha20Rng::seed_from_u64(42));
    let vk = zk::setup_vk(&srs, &circuit);

    let public_inputs = [
        CircuitBase::from(generated.instance.0),
        CircuitBase::from(generated.instance.1),
    ];
    let empty_committed: [MidnightScalar; 0] = [];
    let columns: [&[MidnightScalar]; 2] = [&empty_committed, &public_inputs];
    let instances: [&[&[MidnightScalar]]; 1] = [&columns];

    let circuit_repr = extract_circuit_midnight::<StmMidnightPcs>(&srs, vk.vk(), &instances)
        .context("Failed to extract the midnight STM circuit representation")?;
    let parsed = parse_midnight_stm_proof(&circuit_repr, &vk, &instances, &generated.proof)?;

    let (unique_grouped_points, commitment_data) =
        <StmMidnightPcs as ExtractPCS>::precompute_intermediate_sets(&circuit_repr);
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
    let point_sets = build_point_sets(&circuit_repr, &unique_grouped_points, &parsed);
    let (q_eval_sets, f_eval) =
        compute_q_eval_sets_and_f_eval(&commitment_data, &point_sets, &x1_powers, &parsed)?;
    let v = x4_powers
        .iter()
        .zip(
            parsed
                .proof_x3_q_evals
                .iter()
                .copied()
                .chain(std::iter::once(f_eval)),
        )
        .fold(BlstrsScalar::ZERO, |acc, (power, eval)| {
            acc + (*power * eval)
        });

    let set_0_commitments = commitment_data
        .iter()
        .filter(|entry| entry.point_set_index == 0)
        .collect::<Vec<_>>();
    ensure!(
        set_0_commitments.len() >= PHASE1_PREFIX_COMMITMENTS,
        "Set 0 must contain at least {} commitments, got {}",
        PHASE1_PREFIX_COMMITMENTS,
        set_0_commitments.len()
    );
    let rhs_prefix = set_0_commitments
        .iter()
        .take(PHASE1_PREFIX_COMMITMENTS)
        .zip(x1_powers.iter())
        .fold(BlstrsG1Projective::identity(), |acc, (entry, x1_power)| {
            let commitment = parsed
                .commitments
                .get(&entry.commitment)
                .unwrap_or_else(|| panic!("missing commitment value for {:?}", entry.commitment));
            acc + (*commitment * *x1_power)
        });

    let reduced_redeemer = ReducedRedeemer {
        vanishing_g: compress_g1_hex(get_commitment(&parsed, Commitments::VanishingG)?),
        vanishing_rand: compress_g1_hex(get_commitment(&parsed, Commitments::VanishingRand)?),
        a1: compress_g1_hex(get_commitment(&parsed, Commitments::Advice(1))?),
        a2: compress_g1_hex(get_commitment(&parsed, Commitments::Advice(2))?),
        a3: compress_g1_hex(get_commitment(&parsed, Commitments::Advice(3))?),
        perm_d: compress_g1_hex(get_commitment(&parsed, Commitments::Permutation('d'))?),
        lookup_1: compress_g1_hex(get_commitment(&parsed, Commitments::Lookup(1))?),
        lookup_2: compress_g1_hex(get_commitment(&parsed, Commitments::Lookup(2))?),
        perm_a: compress_g1_hex(get_commitment(&parsed, Commitments::Permutation('a'))?),
        perm_b: compress_g1_hex(get_commitment(&parsed, Commitments::Permutation('b'))?),
        perm_c: compress_g1_hex(get_commitment(&parsed, Commitments::Permutation('c'))?),
        perm_input_1: compress_g1_hex(get_commitment(&parsed, Commitments::PermutedInput(1))?),
        perm_input_2: compress_g1_hex(get_commitment(&parsed, Commitments::PermutedInput(2))?),
        f_commitment: compress_g1_hex(&parsed.f_commitment),
        pi_term: compress_g1_hex(&parsed.pi_term),
    };
    let reduced_hash = hash_reduced_redeemer(&reduced_redeemer);

    let phase1_state = Phase1State {
        rhs_prefix: compress_g1_hex(&rhs_prefix),
        reduced_hash: bytes32_hex(&reduced_hash),
        x1: bytes32_hex(&parsed.x1.to_bytes_le()),
        x3: bytes32_hex(&parsed.x3.to_bytes_le()),
        x4: bytes32_hex(&parsed.x4.to_bytes_le()),
        v: bytes32_hex(&v.to_bytes_le()),
    };

    let _ = q_eval_sets;

    Ok(DerivedSplitProofData {
        phase1_state,
        reduced_redeemer,
    })
}

fn parse_midnight_stm_proof(
    circuit: &StmCircuitRepresentation,
    vk: &zk::MidnightVK,
    instances: &[&[&[MidnightScalar]]],
    proof: &[u8],
) -> Result<ParsedMidnightProof> {
    let mut transcript = init_stm_transcript(circuit, vk, instances, proof)?;
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
                let point: MidnightG1Projective = transcript.read()?;
                commitments.insert(
                    Commitments::Advice(advice_commitment_index),
                    blstrs_point_from_midnight(point)?,
                );
            }
            ProofExtractionSteps::PermutationsCommitted => {
                let set = sets[permutation_commitment_index];
                permutation_commitment_index += 1;
                let point: MidnightG1Projective = transcript.read()?;
                commitments.insert(
                    Commitments::Permutation(set),
                    blstrs_point_from_midnight(point)?,
                );
            }
            ProofExtractionSteps::LookupPermuted => {
                lookup_index += 1;
                let input: MidnightG1Projective = transcript.read()?;
                let table: MidnightG1Projective = transcript.read()?;
                commitments.insert(
                    Commitments::PermutedInput(lookup_index),
                    blstrs_point_from_midnight(input)?,
                );
                commitments.insert(
                    Commitments::PermutedTable(lookup_index),
                    blstrs_point_from_midnight(table)?,
                );
            }
            ProofExtractionSteps::LookupCommitment => {
                lookup_commitment_index += 1;
                let point: MidnightG1Projective = transcript.read()?;
                commitments.insert(
                    Commitments::Lookup(lookup_commitment_index),
                    blstrs_point_from_midnight(point)?,
                );
            }
            ProofExtractionSteps::TrashCommitment => {
                trash_commitment_index += 1;
                let point: MidnightG1Projective = transcript.read()?;
                commitments.insert(
                    Commitments::Trash(trash_commitment_index),
                    blstrs_point_from_midnight(point)?,
                );
            }
            ProofExtractionSteps::VanishingRand => {
                let point: MidnightG1Projective = transcript.read()?;
                commitments.insert(
                    Commitments::VanishingRand,
                    blstrs_point_from_midnight(point)?,
                );
            }
            ProofExtractionSteps::VanishingSplit => {
                let point: MidnightG1Projective = transcript.read()?;
                vanishing_splits.push(blstrs_point_from_midnight(point)?);
            }
            ProofExtractionSteps::InstanceEval => {
                instance_eval_index += 1;
                let value: MidnightScalar = transcript.read()?;
                evaluations.insert(
                    Evaluations::CommittedInstance(instance_eval_index),
                    scalar_from_midnight(value),
                );
            }
            ProofExtractionSteps::AdviceEval => {
                advice_eval_index += 1;
                let value: MidnightScalar = transcript.read()?;
                evaluations.insert(
                    Evaluations::Advice(advice_eval_index),
                    scalar_from_midnight(value),
                );
            }
            ProofExtractionSteps::FixedEval => {
                fixed_eval_index += 1;
                let value: MidnightScalar = transcript.read()?;
                evaluations.insert(
                    Evaluations::Fixed(fixed_eval_index),
                    scalar_from_midnight(value),
                );
            }
            ProofExtractionSteps::RandomEval => {
                let value: MidnightScalar = transcript.read()?;
                evaluations.insert(Evaluations::RandomEval, scalar_from_midnight(value));
            }
            ProofExtractionSteps::PermutationCommon => {
                permutation_common_index += 1;
                let value: MidnightScalar = transcript.read()?;
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
                let value: MidnightScalar = transcript.read()?;
                evaluations.insert(
                    Evaluations::Permutation(*set, *subindex),
                    scalar_from_midnight(value),
                );
            }
            ProofExtractionSteps::LookupEval => {
                lookup_eval_index += 1;
                let product_eval: MidnightScalar = transcript.read()?;
                let product_next_eval: MidnightScalar = transcript.read()?;
                let permuted_input_eval: MidnightScalar = transcript.read()?;
                let permuted_input_inv_eval: MidnightScalar = transcript.read()?;
                let permuted_table_eval: MidnightScalar = transcript.read()?;

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
                let value: MidnightScalar = transcript.read()?;
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
                let point: MidnightG1Projective = transcript.read()?;
                f_commitment = Some(blstrs_point_from_midnight(point)?);
            }
            HMOSteps::PI => {
                let point: MidnightG1Projective = transcript.read()?;
                pi_term = Some(blstrs_point_from_midnight(point)?);
            }
            HMOSteps::QEvals => {
                let value: MidnightScalar = transcript.read()?;
                proof_x3_q_evals.push(scalar_from_midnight(value));
            }
            HMOSteps::X1 => x1 = Some(scalar_from_midnight(transcript.squeeze_challenge())),
            HMOSteps::X2 => x2 = Some(scalar_from_midnight(transcript.squeeze_challenge())),
            HMOSteps::X3 => x3 = Some(scalar_from_midnight(transcript.squeeze_challenge())),
            HMOSteps::X4 => x4 = Some(scalar_from_midnight(transcript.squeeze_challenge())),
        }
    }

    transcript.assert_empty()?;

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
        .ok_or_else(|| anyhow!("Missing x challenge"))?
        .pow_vartime([circuit.proof_instantiation_data.n_coefficient, 0, 0, 0]);
    let x_chop = x
        .ok_or_else(|| anyhow!("Missing x challenge"))?
        .pow_vartime([circuit.proof_instantiation_data.n_coefficient - 1, 0, 0, 0]);
    let vanishing_g = aggregate_vanishing_splits_reverse(&vanishing_splits, x_chop);
    commitments.insert(Commitments::VanishingG, vanishing_g);

    let theta = theta.ok_or_else(|| anyhow!("Missing theta challenge"))?;
    let beta = beta.ok_or_else(|| anyhow!("Missing beta challenge"))?;
    let gamma = gamma.ok_or_else(|| anyhow!("Missing gamma challenge"))?;
    let y = y.ok_or_else(|| anyhow!("Missing y challenge"))?;
    let trash_challenge = trash_challenge.ok_or_else(|| anyhow!("Missing trash challenge"))?;
    let x = x.ok_or_else(|| anyhow!("Missing x challenge"))?;

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
                .ok_or_else(|| anyhow!("Missing committed instance evaluation {query_id}"))?;
            instance_evaluations.insert(query_id, value);
            continue;
        }

        ensure!(
            rotation == 0,
            "Only current-rotation public instance queries are supported in STM proof_export export"
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
        .ok_or_else(|| anyhow!("Missing lagrange basis value at rotation 0"))?;
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
            Evaluations::PermutationsCommon(index) => Some(format!("permutation_common_{index}")),
            Evaluations::VanishingS => Some("vanishing_s".to_string()),
            Evaluations::RandomEval => Some("random_eval".to_string()),
            Evaluations::Lookup(index) => Some(format!("product_eval_{index}")),
            Evaluations::PermutedInput(index) => Some(format!("permuted_input_eval_{index}")),
            Evaluations::PermutedTable(index) => Some(format!("permuted_table_eval_{index}")),
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
        .map(|expression| eval_circuit_expression(expression, &evaluations, &instance_evaluations))
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
            let l5 = (permuted_input_eval - permuted_table_eval)
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
            eval_scalar_expression(expression, &evaluations, &instance_evaluations, &variables)
        })
        .collect::<Vec<_>>();

    let mut lhs_sets = HashMap::<char, BlstrsScalar>::new();
    for (set, expression) in &circuit.expressions.permutation_terms_left {
        let value =
            eval_scalar_expression(expression, &evaluations, &instance_evaluations, &variables);
        lhs_sets
            .entry(*set)
            .and_modify(|acc| *acc *= value)
            .or_insert(value);
    }

    let mut rhs_sets = HashMap::<char, BlstrsScalar>::new();
    for (set, expression) in &circuit.expressions.permutation_terms_right {
        let value =
            eval_scalar_expression(expression, &evaluations, &instance_evaluations, &variables);
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
            eval_scalar_expression(expression, &evaluations, &instance_evaluations, &variables)
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
        .ok_or_else(|| anyhow!("Vanishing terms should not be empty"))?;
    let vanishing_s = h_eval
        * Option::<BlstrsScalar>::from((xn - BlstrsScalar::ONE).invert())
            .ok_or_else(|| anyhow!("xn - 1 should be invertible"))?;
    evaluations.insert(Evaluations::VanishingS, vanishing_s);

    Ok(ParsedMidnightProof {
        commitments,
        evaluations,
        x,
        x1: x1.ok_or_else(|| anyhow!("Missing x1 challenge"))?,
        x2: x2.ok_or_else(|| anyhow!("Missing x2 challenge"))?,
        x3: x3.ok_or_else(|| anyhow!("Missing x3 challenge"))?,
        x4: x4.ok_or_else(|| anyhow!("Missing x4 challenge"))?,
        f_commitment: f_commitment.ok_or_else(|| anyhow!("Missing f_commitment"))?,
        pi_term: pi_term.ok_or_else(|| anyhow!("Missing pi_term"))?,
        proof_x3_q_evals,
    })
}

fn build_point_sets(
    circuit: &StmCircuitRepresentation,
    unique_grouped_points: &[Vec<RotationDescription>],
    parsed: &ParsedMidnightProof,
) -> Vec<Vec<BlstrsScalar>> {
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

    unique_grouped_points
        .iter()
        .map(|point_set| {
            point_set
                .iter()
                .map(|rotation| resolve_rotation_point(*rotation, parsed.x, x_prev, x_next, x_last))
                .collect::<Vec<_>>()
        })
        .collect()
}

fn compute_q_eval_sets_and_f_eval(
    commitment_data: &[crate::plutus_gen::extraction::data::CommitmentData],
    point_sets: &[Vec<BlstrsScalar>],
    x1_powers: &[BlstrsScalar],
    parsed: &ParsedMidnightProof,
) -> Result<(Vec<Vec<BlstrsScalar>>, BlstrsScalar)> {
    let mut q_eval_sets = Vec::with_capacity(point_sets.len());

    for (point_set_index, points) in point_sets.iter().enumerate() {
        let commitments_for_set = commitment_data
            .iter()
            .filter(|entry| entry.point_set_index == point_set_index)
            .collect::<Vec<_>>();
        let mut eval_set = vec![BlstrsScalar::ZERO; points.len()];

        for (x1_power, entry) in x1_powers.iter().zip(commitments_for_set.iter()) {
            for (slot, evaluation) in entry.evaluations.iter().enumerate() {
                let value = parsed
                    .evaluations
                    .get(evaluation)
                    .ok_or_else(|| anyhow!("Missing evaluation value for {:?}", evaluation))?;
                eval_set[slot] += *value * *x1_power;
            }
        }

        q_eval_sets.push(eval_set);
    }

    let mut f_eval = BlstrsScalar::ZERO;
    for ((points, evals), proof_q_eval) in point_sets
        .iter()
        .zip(q_eval_sets.iter())
        .zip(parsed.proof_x3_q_evals.iter())
        .rev()
    {
        let r_eval = lagrange_evaluation(points, evals, parsed.x3);
        let denominator = points
            .iter()
            .fold(BlstrsScalar::ONE, |acc, point| acc * (parsed.x3 - point));
        let evaluation = (*proof_q_eval - r_eval)
            * Option::<BlstrsScalar>::from(denominator.invert())
                .ok_or_else(|| anyhow!("x3 should not collide with an evaluation point"))?;
        f_eval = (f_eval * parsed.x2) + evaluation;
    }

    Ok((q_eval_sets, f_eval))
}

fn init_stm_transcript(
    circuit: &StmCircuitRepresentation,
    vk: &zk::MidnightVK,
    instances: &[&[&[MidnightScalar]]],
    proof: &[u8],
) -> Result<CircuitTranscript<CardanoFriendlyBlake2b>> {
    let mut transcript = CircuitTranscript::<CardanoFriendlyBlake2b>::init_from_bytes(proof);
    transcript.common(&vk.vk().transcript_repr())?;

    for commitment in &circuit
        .proof_instantiation_data
        .committed_instance_commitments
    {
        let bytes = commitment.to_bytes();
        let mut repr = <MidnightG1Projective as GroupEncoding>::Repr::default();
        repr.as_mut().copy_from_slice(bytes.as_ref());
        let point = Option::<MidnightG1Projective>::from(MidnightG1Projective::from_bytes(&repr))
            .ok_or_else(|| anyhow!("Committed instance point should decode"))?;
        transcript.common(&point)?;
    }

    for column in instances[0].iter().skip(
        circuit
            .proof_instantiation_data
            .committed_instance_commitments
            .len(),
    ) {
        transcript.common(&MidnightScalar::from(column.len() as u64))?;
        for value in *column {
            transcript.common(value)?;
        }
    }

    Ok(transcript)
}

fn get_commitment(parsed: &ParsedMidnightProof, key: Commitments) -> Result<&BlstrsG1Projective> {
    parsed
        .commitments
        .get(&key)
        .ok_or_else(|| anyhow!("Missing commitment value for {:?}", key))
}

fn hash_reduced_redeemer(reduced_redeemer: &ReducedRedeemer) -> [u8; 32] {
    let serialized = [
        reduced_redeemer.vanishing_g.as_str(),
        reduced_redeemer.vanishing_rand.as_str(),
        reduced_redeemer.a1.as_str(),
        reduced_redeemer.a2.as_str(),
        reduced_redeemer.a3.as_str(),
        reduced_redeemer.perm_d.as_str(),
        reduced_redeemer.lookup_1.as_str(),
        reduced_redeemer.lookup_2.as_str(),
        reduced_redeemer.perm_a.as_str(),
        reduced_redeemer.perm_b.as_str(),
        reduced_redeemer.perm_c.as_str(),
        reduced_redeemer.perm_input_1.as_str(),
        reduced_redeemer.perm_input_2.as_str(),
        reduced_redeemer.f_commitment.as_str(),
        reduced_redeemer.pi_term.as_str(),
    ]
    .into_iter()
    .flat_map(|hex_value| decode_hex_bytes(hex_value).expect("reduced redeemer hex must decode"))
    .collect::<Vec<_>>();
    Blake2bParams::new()
        .hash_length(32)
        .hash(&serialized)
        .as_bytes()
        .try_into()
        .expect("blake2b_256 output must be 32 bytes")
}

fn blake2b_256_hex(bytes: &[u8]) -> String {
    hex_bytes(Blake2bParams::new().hash_length(32).hash(bytes).as_bytes())
}

fn bytes32_hex(bytes: &[u8]) -> String {
    assert_eq!(bytes.len(), 32, "expected 32 bytes");
    hex_bytes(bytes)
}

fn circuit_base_bytes32(value: CircuitBase) -> [u8; 32] {
    <CircuitBase as Hashable<CardanoFriendlyBlake2b>>::to_bytes(&value)
        .try_into()
        .expect("CircuitBase transcript encoding must be 32 bytes")
}

fn hex_bytes(bytes: &[u8]) -> String {
    format!("0x{}", hex::encode(bytes))
}

fn decode_hex_bytes(value: &str) -> Result<Vec<u8>> {
    let normalized = value.strip_prefix("0x").unwrap_or(value);
    if normalized.is_empty() {
        return Ok(Vec::new());
    }
    ensure!(
        normalized.len() % 2 == 0,
        "Hex strings must contain an even number of digits"
    );
    hex::decode(normalized).with_context(|| format!("Invalid hex string: {value}"))
}

fn decode_bytes32(value: &str) -> Result<[u8; 32]> {
    let bytes = decode_hex_bytes(value)?;
    bytes
        .try_into()
        .map_err(|_| anyhow!("Expected 32-byte hex value"))
}

fn compress_g1_hex(point: &BlstrsG1Projective) -> String {
    hex_bytes(point.to_bytes().as_ref())
}

fn compress_g2_hex(point: &blstrs::G2Affine) -> String {
    hex_bytes(point.to_bytes().as_ref())
}

fn g1_from_hex(hex: &str) -> Result<BlstrsG1Projective> {
    let bytes = decode_hex_bytes(hex)?;
    let mut repr = <blstrs::G1Affine as GroupEncoding>::Repr::default();
    repr.as_mut().copy_from_slice(&bytes);
    let affine = Option::<blstrs::G1Affine>::from(blstrs::G1Affine::from_bytes(&repr))
        .ok_or_else(|| anyhow!("Compressed G1 point failed to decode"))?;
    Ok(BlstrsG1Projective::from(affine))
}

fn scalar_from_hex_le(hex: &str) -> Result<BlstrsScalar> {
    let bytes = decode_bytes32(hex)?;
    let mut repr = <BlstrsScalar as PrimeField>::Repr::default();
    repr.as_mut().copy_from_slice(&bytes);
    Option::<BlstrsScalar>::from(BlstrsScalar::from_repr(repr))
        .ok_or_else(|| anyhow!("Scalar bytes do not fit into blstrs::Scalar"))
}

fn parse_phi_f_hex(value: &str) -> Result<f64> {
    let bytes = decode_hex_bytes(value)?;
    ensure!(
        bytes.len() <= 4,
        "phi_f fixed-point encoding currently supports at most 4 bytes"
    );
    let mut padded = [0u8; 4];
    padded[4 - bytes.len()..].copy_from_slice(&bytes);
    let fixed = u32::from_be_bytes(padded);
    Ok((fixed as f64) / ((1u64 << 24) as f64))
}

fn blstrs_point_from_midnight(point: MidnightG1Projective) -> Result<BlstrsG1Projective> {
    Ok(BlstrsG1Projective::from(g1_projective_from_midnight(
        &point,
    )?))
}

fn midnight_g2_affine_from_blstrs(value: blstrs::G2Affine) -> Result<MidnightG2Affine> {
    let bytes = value.to_bytes();
    let mut repr = <MidnightG2Affine as GroupEncoding>::Repr::default();
    repr.as_mut().copy_from_slice(bytes.as_ref());
    Option::<MidnightG2Affine>::from(MidnightG2Affine::from_bytes(&repr))
        .ok_or_else(|| anyhow!("failed to convert blstrs::G2Affine into midnight G2Affine"))
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
        value * omega_inv.pow_vartime([(rotation.unsigned_abs()) as u64, 0, 0, 0])
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
    expression: &CircuitExpression<BlstrsScalar>,
    evaluations: &HashMap<Evaluations, BlstrsScalar>,
    instance_evaluations: &HashMap<usize, BlstrsScalar>,
) -> BlstrsScalar {
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
    expression: &ScalarExpression<BlstrsScalar>,
    evaluations: &HashMap<Evaluations, BlstrsScalar>,
    instance_evaluations: &HashMap<usize, BlstrsScalar>,
    variables: &HashMap<&'static str, BlstrsScalar>,
) -> BlstrsScalar {
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
        ScalarExpression::PowMod(inner, exponent) => {
            eval_scalar_expression(inner, evaluations, instance_evaluations, variables)
                .pow_vartime([*exponent as u64, 0, 0, 0])
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::circuits::mithril_stm::generate_stm_proof;
    use crate::circuits::mithril_stm::witness::Position;
    use crate::plutus_gen::adjusted_types::CardanoFriendlyBlake2b;
    use crate::plutus_gen::extraction::conversion::scalar_from_midnight;
    use midnight_circuits::hash::poseidon::PoseidonState;
    use midnight_proofs::plonk::prepare as prepare_midnight_verifier;
    use midnight_proofs::transcript::CircuitTranscript;

    fn g1_from_hex(hex: &str) -> BlstrsG1Projective {
        let bytes = decode_hex_bytes(hex).expect("compressed G1 hex should decode");
        let mut repr = <blstrs::G1Affine as GroupEncoding>::Repr::default();
        repr.as_mut().copy_from_slice(&bytes);
        let affine = Option::<blstrs::G1Affine>::from(blstrs::G1Affine::from_bytes(&repr))
            .expect("compressed G1 point should decode");
        BlstrsG1Projective::from(affine)
    }

    fn scalar_from_hex_le(hex: &str) -> BlstrsScalar {
        let bytes = decode_bytes32(hex).expect("scalar hex should decode");
        let mut repr = <BlstrsScalar as PrimeField>::Repr::default();
        repr.as_mut().copy_from_slice(&bytes);
        Option::<BlstrsScalar>::from(BlstrsScalar::from_repr(repr))
            .expect("scalar bytes should fit into blstrs::Scalar")
    }

    fn full_right_for_parsed(
        circuit: &StmCircuitRepresentation,
        parsed: &ParsedMidnightProof,
    ) -> BlstrsG1Projective {
        let (unique_grouped_points, commitment_data) =
            <StmMidnightPcs as ExtractPCS>::precompute_intermediate_sets(circuit);
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
        let point_sets = build_point_sets(circuit, &unique_grouped_points, parsed);
        let (q_eval_sets, f_eval) =
            compute_q_eval_sets_and_f_eval(&commitment_data, &point_sets, &x1_powers, parsed)
                .expect("q evals should compute");

        let mut final_com = BlstrsG1Projective::identity();
        for (point_set_index, x4_power) in x4_powers.iter().take(point_sets.len()).enumerate() {
            let q_comm = commitment_data
                .iter()
                .filter(|entry| entry.point_set_index == point_set_index)
                .zip(x1_powers.iter())
                .fold(BlstrsG1Projective::identity(), |acc, (entry, x1_power)| {
                    let commitment = parsed
                        .commitments
                        .get(&entry.commitment)
                        .unwrap_or_else(|| panic!("missing commitment value for {:?}", entry.commitment));
                    acc + (*commitment * *x1_power)
                });
            final_com += q_comm * *x4_power;
        }
        final_com += parsed.f_commitment * *x4_powers.last().unwrap();

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

        let _ = q_eval_sets;

        final_com + (BlstrsG1Projective::generator() * (-v)) + (parsed.pi_term * parsed.x3)
    }

    fn split_right_from_proof_export(
        circuit: &StmCircuitRepresentation,
        parsed: &ParsedMidnightProof,
        proof_export: &MithrilStmProofExport,
    ) -> BlstrsG1Projective {
        let (unique_grouped_points, commitment_data) =
            <StmMidnightPcs as ExtractPCS>::precompute_intermediate_sets(circuit);
        let max_commitments_per_set = (0..unique_grouped_points.len())
            .map(|point_set_index| {
                commitment_data
                    .iter()
                    .filter(|entry| entry.point_set_index == point_set_index)
                    .count()
            })
            .max()
            .unwrap_or(0);

        let x1 = scalar_from_hex_le(&proof_export.phase1_state.x1);
        let x3 = scalar_from_hex_le(&proof_export.phase1_state.x3);
        let x4 = scalar_from_hex_le(&proof_export.phase1_state.x4);
        let v = scalar_from_hex_le(&proof_export.phase1_state.v);
        let x1_powers = powers(max_commitments_per_set, x1);
        let x4_powers = powers(unique_grouped_points.len() + 1, x4);

        let rhs_prefix = g1_from_hex(&proof_export.phase1_state.rhs_prefix);
        let set_0_suffix_sum = commitment_data
            .iter()
            .filter(|entry| entry.point_set_index == 0)
            .skip(PHASE1_PREFIX_COMMITMENTS)
            .zip(x1_powers.iter().skip(PHASE1_PREFIX_COMMITMENTS))
            .fold(BlstrsG1Projective::identity(), |acc, (entry, x1_power)| {
                let commitment = parsed
                    .commitments
                    .get(&entry.commitment)
                    .unwrap_or_else(|| panic!("missing commitment value for {:?}", entry.commitment));
                acc + (*commitment * *x1_power)
            });

        let set_1_sum =
            [
                &proof_export.reduced_redeemer.a1,
                &proof_export.reduced_redeemer.a2,
                &proof_export.reduced_redeemer.a3,
                &proof_export.reduced_redeemer.perm_d,
                &proof_export.reduced_redeemer.lookup_1,
                &proof_export.reduced_redeemer.lookup_2,
            ]
            .iter()
            .zip(x1_powers.iter())
            .fold(BlstrsG1Projective::identity(), |acc, (point_hex, x1_power)| {
                acc + (g1_from_hex(point_hex) * *x1_power)
            })
                * x4_powers[1];

        let set_2_sum =
            [
                &proof_export.reduced_redeemer.perm_a,
                &proof_export.reduced_redeemer.perm_b,
                &proof_export.reduced_redeemer.perm_c,
            ]
            .iter()
            .zip(x1_powers.iter())
            .fold(BlstrsG1Projective::identity(), |acc, (point_hex, x1_power)| {
                acc + (g1_from_hex(point_hex) * *x1_power)
            })
                * x4_powers[2];

        let set_3_sum =
            [
                &proof_export.reduced_redeemer.perm_input_1,
                &proof_export.reduced_redeemer.perm_input_2,
            ]
            .iter()
            .zip(x1_powers.iter())
            .fold(BlstrsG1Projective::identity(), |acc, (point_hex, x1_power)| {
                acc + (g1_from_hex(point_hex) * *x1_power)
            })
                * x4_powers[3];

        let f_term = g1_from_hex(&proof_export.reduced_redeemer.f_commitment) * x4_powers[4];
        let final_com = rhs_prefix + set_0_suffix_sum + set_1_sum + set_2_sum + set_3_sum + f_term;
        let v_term = BlstrsG1Projective::generator() * (-v);
        let pi_term = g1_from_hex(&proof_export.reduced_redeemer.pi_term);

        final_com + v_term + (pi_term * x3)
    }

    fn native_guard_right(
        circuit: &StmCircuitRepresentation,
        vk: &zk::MidnightVK,
        normal_instances: &[&[&[MidnightScalar]]; 1],
        proof: &[u8],
    ) -> BlstrsG1Projective {
        let (_, right) = native_guard_sides(circuit, vk, normal_instances, proof);
        right
    }

    fn native_guard_sides(
        circuit: &StmCircuitRepresentation,
        vk: &zk::MidnightVK,
        normal_instances: &[&[&[MidnightScalar]]; 1],
        proof: &[u8],
    ) -> (BlstrsG1Projective, BlstrsG1Projective) {
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
        let (left_terms, right_terms) = guard.split();
        let left = left_terms
            .into_iter()
            .fold(BlstrsG1Projective::identity(), |acc, (scalar, point)| {
                acc + (g1_projective_from_midnight(point).unwrap() * scalar_from_midnight(*scalar))
            });
        let right = right_terms
            .into_iter()
            .fold(BlstrsG1Projective::identity(), |acc, (scalar, point)| {
                acc + (g1_projective_from_midnight(point).unwrap() * scalar_from_midnight(*scalar))
            });
        (left, right)
    }

    fn sample_bundle_from_generated(
        generated: &GeneratedStmProof,
        message: [u8; 32],
        nparties: usize,
    ) -> InputBundle {
        let public_input_1_merkle_root = bytes32_hex(&circuit_base_bytes32(CircuitBase::from(
            generated.instance.0,
        )));
        let public_input_2_signed_message = bytes32_hex(&circuit_base_bytes32(CircuitBase::from(
            generated.instance.1,
        )));
        let entries = generated
            .witness
            .iter()
            .map(|entry| {
                let leaf_index = entry.merkle_path.siblings.iter().enumerate().fold(
                    0usize,
                    |acc, (depth, (position, _))| match position {
                        Position::Left => acc | (1usize << depth),
                        Position::Right => acc,
                    },
                );
                let siblings = entry
                    .merkle_path
                    .siblings
                    .iter()
                    .map(|(_, sibling)| {
                        bytes32_hex(&circuit_base_bytes32(CircuitBase::from(*sibling)))
                    })
                    .collect();

                InputWitnessEntry {
                    signer_index: leaf_index,
                    lottery_index: entry.lottery_index,
                    verification_key_snark: hex_bytes(&entry.leaf.verification_key().to_bytes()),
                    target: bytes32_hex(&circuit_base_bytes32(CircuitBase::from(
                        entry.leaf.lottery_target_value(),
                    ))),
                    merkle_path: InputMerklePath {
                        leaf_index,
                        siblings,
                    },
                    unique_schnorr_signature: hex_bytes(&entry.unique_schnorr_signature.to_bytes()),
                }
            })
            .collect();

        let phi_f = InputPhiF::Number(generated.params.phi_f);
        let parent = InputCertificate {
            kind: "genesis".to_string(),
            hash: bytes32_hex(&[0u8; 32]),
            prev_hash: "0x".to_string(),
            epoch: 0,
            metadata: CertificateMetadata {
                network: "poc".to_string(),
                protocol_version: "0.1.0".to_string(),
                initiated_at: "0x00".to_string(),
                sealed_at: "0x01".to_string(),
            },
            protocol_parameters: CertificateProtocolParameters {
                k: generated.params.k,
                m: generated.params.m,
                phi_f: "0x00cccccd".to_string(),
            },
            protocol_message: CertificateProtocolMessage {
                current_epoch_text: "0".to_string(),
                next_aggregate_verification_key_text: "".to_string(),
                next_aggregate_verification_key_snark_text: "".to_string(),
                next_protocol_parameters_text: "".to_string(),
                cardano_transactions_merkle_root_hex: None,
            },
            signed_message: bytes32_hex(&[0u8; 32]),
            aggregate_verification_key_text: "".to_string(),
            aggregate_verification_key_snark_text: "".to_string(),
            signature: CertificateSignatureInfo {
                signature_type: "genesis".to_string(),
                bytes_hex: "0x".to_string(),
            },
            signed_entity: SignedEntity {
                kind: "unknown".to_string(),
                epoch: None,
                block_number: None,
            },
        };
        let child = InputCertificate {
            kind: "standard".to_string(),
            hash: bytes32_hex(&[1u8; 32]),
            prev_hash: bytes32_hex(&[0u8; 32]),
            epoch: 1,
            metadata: CertificateMetadata {
                network: "poc".to_string(),
                protocol_version: "0.1.0".to_string(),
                initiated_at: "0x02".to_string(),
                sealed_at: "0x03".to_string(),
            },
            protocol_parameters: CertificateProtocolParameters {
                k: generated.params.k,
                m: generated.params.m,
                phi_f: "0x00cccccd".to_string(),
            },
            protocol_message: CertificateProtocolMessage {
                current_epoch_text: "1".to_string(),
                next_aggregate_verification_key_text: "".to_string(),
                next_aggregate_verification_key_snark_text: "".to_string(),
                next_protocol_parameters_text: "".to_string(),
                cardano_transactions_merkle_root_hex: None,
            },
            signed_message: bytes32_hex(&message),
            aggregate_verification_key_text: "".to_string(),
            aggregate_verification_key_snark_text: "".to_string(),
            signature: CertificateSignatureInfo {
                signature_type: "multi".to_string(),
                bytes_hex: "0x1234".to_string(),
            },
            signed_entity: SignedEntity {
                kind: "mithril_stake_distribution".to_string(),
                epoch: Some(1),
                block_number: None,
            },
        };

        InputBundle {
            schema_version: BUNDLE_SCHEMA_VERSION.to_string(),
            bundle_kind: BUNDLE_KIND.to_string(),
            source: InputSource {
                source_id: "synthetic-test-fixture".to_string(),
                source_kind: "fixture".to_string(),
                network: "poc".to_string(),
                generated_at: None,
                notes: None,
            },
            circuit: InputCircuit {
                name: GENERATOR_CIRCUIT.to_string(),
                public_input_contract:
                    "public_input_1=registration_merkle_root,public_input_2=child_certificate.signed_message"
                        .to_string(),
            },
            stm_parameters: InputParameters {
                m: generated.params.m,
                k: generated.params.k,
                phi_f,
            },
            certificates: InputCertificates { parent, child },
            statement: InputStatement {
                public_input_1_merkle_root,
                public_input_2_signed_message,
            },
            registration: InputRegistration {
                total_stake: nparties as u64,
                parties_count: nparties,
                merkle_tree_depth: generated.merkle_tree_depth,
            },
            witness: InputWitness { entries },
        }
    }

    #[test]
    fn mithril_stm_proof_export_builds_and_validates() {
        let params = mithril_stm::Parameters {
            m: 200,
            k: 5,
            phi_f: 0.8,
        };
        let message = [7u8; 32];
        let seed = [9u8; 32];
        let generated = generate_stm_proof(params, 10, message, seed).unwrap();
        let bundle = sample_bundle_from_generated(&generated, message, 10);

        let proof_export = build_mithril_stm_proof_export(&bundle, "0xdeadbeef".to_string(), seed).unwrap();

        assert_eq!(
            proof_export.statement.statement_hash,
            proof_export.statement.public_input_2
        );
        assert_eq!(
            proof_export.bridge_aiken.phase2.proof_receipt_statement_hash,
            proof_export.statement.statement_hash
        );
        assert_eq!(
            proof_export.bridge_aiken.phase2.token_name,
            proof_export.phase1_state.reduced_hash
        );
        assert_eq!(
            proof_export.certificates.child.signed_message,
            proof_export.statement.public_input_2
        );
        assert!(!decode_hex_bytes(&proof_export.proof.proof_bytes)
            .unwrap()
            .is_empty());
        validate_mithril_stm_proof_export(&proof_export).unwrap();
    }

    #[test]
    fn mithril_stm_proof_export_rejects_bad_reduced_hash() {
        let params = mithril_stm::Parameters {
            m: 200,
            k: 5,
            phi_f: 0.8,
        };
        let message = [7u8; 32];
        let generated = generate_stm_proof(params, 10, message, [10u8; 32]).unwrap();
        let bundle = sample_bundle_from_generated(&generated, message, 10);
        let mut proof_export =
            build_mithril_stm_proof_export(&bundle, "0xbeef".to_string(), [10u8; 32]).unwrap();
        proof_export.phase1_state.reduced_hash = bytes32_hex(&[0u8; 32]);
        proof_export.bridge_aiken.phase1.phase1_state_reduced_hash =
            proof_export.phase1_state.reduced_hash.clone();
        proof_export.bridge_aiken.phase2.token_name = proof_export.phase1_state.reduced_hash.clone();

        let error = validate_mithril_stm_proof_export(&proof_export).unwrap_err();
        assert!(error
            .to_string()
            .contains("phase1_state.reduced_hash must equal blake2b_256"));
    }

    #[test]
    fn debug_exported_split_right_matches_full_and_native() {
        let params = mithril_stm::Parameters {
            m: 200,
            k: 5,
            phi_f: 0.8,
        };
        let message = [7u8; 32];
        let seed = [9u8; 32];
        let generated_fixture = generate_stm_proof(params, 10, message, seed).unwrap();
        let bundle = sample_bundle_from_generated(&generated_fixture, message, 10);
        let proof_export = build_mithril_stm_proof_export(&bundle, "0xdeadbeef".to_string(), seed).unwrap();
        let runtime_bundle = bundle.to_runtime_bundle().unwrap();
        let generated = generate_stm_proof_from_bundle(&runtime_bundle, seed).unwrap();
        let proof_export_proof = decode_hex_bytes(&proof_export.proof.proof_bytes).unwrap();

        let circuit = StmCircuit::try_new(&generated.params, generated.merkle_tree_depth).unwrap();
        let min_k = MidnightCircuit::from_relation(&circuit).min_k();
        let srs =
            MidnightParamsKZG::<MidnightBls12>::unsafe_setup(min_k, ChaCha20Rng::seed_from_u64(42));
        let vk = zk::setup_vk(&srs, &circuit);
        let public_inputs = [
            CircuitBase::from(generated.instance.0),
            CircuitBase::from(generated.instance.1),
        ];
        let empty_committed: [MidnightScalar; 0] = [];
        let columns: [&[MidnightScalar]; 2] = [&empty_committed, &public_inputs];
        let instances: [&[&[MidnightScalar]]; 1] = [&columns];
        let normal_instance_columns: [&[MidnightScalar]; 1] = [&public_inputs];
        let normal_instances: [&[&[MidnightScalar]]; 1] = [&normal_instance_columns];
        let circuit_repr =
            extract_circuit_midnight::<StmMidnightPcs>(&srs, vk.vk(), &instances).unwrap();
        let parsed = parse_midnight_stm_proof(&circuit_repr, &vk, &instances, &proof_export_proof).unwrap();

        let full_right = full_right_for_parsed(&circuit_repr, &parsed);
        let split_right = split_right_from_proof_export(&circuit_repr, &parsed, &proof_export);
        let native_right = native_guard_right(&circuit_repr, &vk, &normal_instances, &proof_export_proof);

        let (unique_grouped_points, commitment_data) =
            <StmMidnightPcs as ExtractPCS>::precompute_intermediate_sets(&circuit_repr);
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
        let full_set_0 = commitment_data
            .iter()
            .filter(|entry| entry.point_set_index == 0)
            .zip(x1_powers.iter())
            .fold(BlstrsG1Projective::identity(), |acc, (entry, x1_power)| {
                let commitment = parsed
                    .commitments
                    .get(&entry.commitment)
                    .unwrap_or_else(|| panic!("missing commitment value for {:?}", entry.commitment));
                acc + (*commitment * *x1_power)
            });
        let split_set_0 = g1_from_hex(&proof_export.phase1_state.rhs_prefix)
            + commitment_data
                .iter()
                .filter(|entry| entry.point_set_index == 0)
                .skip(PHASE1_PREFIX_COMMITMENTS)
                .zip(x1_powers.iter().skip(PHASE1_PREFIX_COMMITMENTS))
                .fold(BlstrsG1Projective::identity(), |acc, (entry, x1_power)| {
                    let commitment = parsed
                        .commitments
                        .get(&entry.commitment)
                        .unwrap_or_else(|| panic!("missing commitment value for {:?}", entry.commitment));
                    acc + (*commitment * *x1_power)
                });
        let full_set_1 = [
            Commitments::Advice(1),
            Commitments::Advice(2),
            Commitments::Advice(3),
            Commitments::Permutation('d'),
            Commitments::Lookup(1),
            Commitments::Lookup(2),
        ]
        .iter()
        .zip(x1_powers.iter())
        .fold(BlstrsG1Projective::identity(), |acc, (commitment_key, x1_power)| {
            acc + (*parsed.commitments.get(commitment_key).unwrap() * *x1_power)
        });
        let split_set_1 = [
            &proof_export.reduced_redeemer.a1,
            &proof_export.reduced_redeemer.a2,
            &proof_export.reduced_redeemer.a3,
            &proof_export.reduced_redeemer.perm_d,
            &proof_export.reduced_redeemer.lookup_1,
            &proof_export.reduced_redeemer.lookup_2,
        ]
        .iter()
        .zip(x1_powers.iter())
        .fold(BlstrsG1Projective::identity(), |acc, (point_hex, x1_power)| {
            acc + (g1_from_hex(point_hex) * *x1_power)
        });
        let full_v = {
            let point_sets = build_point_sets(&circuit_repr, &unique_grouped_points, &parsed);
            let (_, f_eval) =
                compute_q_eval_sets_and_f_eval(&commitment_data, &point_sets, &x1_powers, &parsed)
                    .unwrap();
            let x4_powers = powers(unique_grouped_points.len() + 1, parsed.x4);
            x4_powers
                .iter()
                .zip(
                    parsed
                        .proof_x3_q_evals
                        .iter()
                        .copied()
                        .chain(std::iter::once(f_eval)),
                )
                .fold(BlstrsScalar::ZERO, |acc, (power, eval)| acc + (*power * eval))
        };
        let split_v = scalar_from_hex_le(&proof_export.phase1_state.v);

        println!("full_eq_native={}", full_right == native_right);
        println!("split_eq_full={}", split_right == full_right);
        println!("split_eq_native={}", split_right == native_right);
        println!("set0_eq={}", split_set_0 == full_set_0);
        println!("set1_eq={}", split_set_1 == full_set_1);
        println!("v_eq={}", split_v == full_v);
        println!(
            "x1_hex_eq={}",
            proof_export.phase1_state.x1 == bytes32_hex(&parsed.x1.to_bytes_le())
        );
        println!(
            "x3_hex_eq={}",
            proof_export.phase1_state.x3 == bytes32_hex(&parsed.x3.to_bytes_le())
        );
        println!(
            "x4_hex_eq={}",
            proof_export.phase1_state.x4 == bytes32_hex(&parsed.x4.to_bytes_le())
        );
        println!(
            "a1_hex_eq={}",
            proof_export.reduced_redeemer.a1
                == compress_g1_hex(parsed.commitments.get(&Commitments::Advice(1)).unwrap())
        );
        println!("er_hex={}", compress_g1_hex(&native_right));

        assert_eq!(full_right, native_right);
        assert_eq!(split_right, native_right);
    }

    #[test]
    fn proof_export_proof_uses_cardano_transcript_and_not_poseidon() {
        let params = mithril_stm::Parameters {
            m: 200,
            k: 5,
            phi_f: 0.8,
        };
        let message = [7u8; 32];
        let seed = [11u8; 32];
        let generated_fixture = generate_stm_proof(params, 10, message, seed).unwrap();
        let bundle = sample_bundle_from_generated(&generated_fixture, message, 10);
        let proof_export = build_mithril_stm_proof_export(&bundle, "0xdeadbeef".to_string(), seed).unwrap();
        let runtime_bundle = bundle.to_runtime_bundle().unwrap();
        let generated = generate_stm_proof_from_bundle(&runtime_bundle, seed).unwrap();
        let proof_export_proof = decode_hex_bytes(&proof_export.proof.proof_bytes).unwrap();

        let circuit = StmCircuit::try_new(&generated.params, generated.merkle_tree_depth).unwrap();
        let min_k = MidnightCircuit::from_relation(&circuit).min_k();
        let srs =
            MidnightParamsKZG::<MidnightBls12>::unsafe_setup(min_k, ChaCha20Rng::seed_from_u64(42));
        let vk = zk::setup_vk(&srs, &circuit);
        let instance = (generated.instance.0, generated.instance.1);

        zk::verify::<StmCircuit, CardanoFriendlyBlake2b>(
            &srs.verifier_params(),
            &vk,
            &instance,
            None,
            &proof_export_proof,
        )
        .expect("proof_export proof should verify with the Cardano-friendly transcript");

        let poseidon_result = zk::verify::<StmCircuit, PoseidonState<CircuitBase>>(
            &srs.verifier_params(),
            &vk,
            &instance,
            None,
            &proof_export_proof,
        );

        assert!(
            poseidon_result.is_err(),
            "the same proof must be rejected under Poseidon because the transcript defines different Fiat-Shamir challenges",
        );
    }
}
