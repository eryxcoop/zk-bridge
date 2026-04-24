//! Offchain normalizer for Mithril legacy Cardano transaction membership proofs.
//!
//! This file is designed to live next to:
//! - `mithril_legacy_tx_membership.circom`
//!
//! It performs the offchain transformation from the raw legacy Mithril proof
//! hex payload:
//! - `hex(JSON(MKMapProof))`
//! - recursive `master_proof + sub_proofs`
//!
//! into a circuit-friendly witness made of:
//! - target tx leaf bytes
//! - one flattened sub-tree Merkle/MMR path
//! - one flattened master-tree Merkle/MMR path
//! - the expected `CardanoTransactionsMerkleRoot`
//!
//! Important notes:
//! - Mithril legacy proofs are backed by `ckb-merkle-mountain-range`.
//! - The "Merkle proof" is not emitted as a classical siblings/path-bits array.
//! - This normalizer reconstructs those steps by replaying the upstream verifier
//!   logic from `ckb-merkle-mountain-range`.
//! - Recursive proof levels are supported generically while descending nested
//!   `MKMapProof`s, but the exported `LegacyTxCircuitWitness` matches the current
//!   two-level circuit:
//!   tx-subtree -> master MKMap root
//!
//! Hashing convention reproduced from Mithril:
//! - internal merges use `Blake2s256(left || right)`
//! - tx leaves are ASCII bytes of the transaction hash
//! - MKMap master leaves are `BlockRange-as-ASCII || child_root`
//! - `BlockRange-as-ASCII` is `"<start>-<end>"`

use anyhow::{Context, Result, anyhow, bail, ensure};
use blake2::{Blake2s256, Digest};
use rust_witness::{BigInt, witness};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value, json};
use sha2::Sha256;
use std::collections::VecDeque;
use std::fmt::Debug;
use std::mem;

witness!(mithrillegacytxmembershipmain);

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
struct JsonMkTreeNode {
    pub hash: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
struct JsonMkProof {
    pub inner_root: JsonMkTreeNode,
    pub inner_leaves: Vec<(u64, JsonMkTreeNode)>,
    pub inner_proof_size: u64,
    pub inner_proof_items: Vec<JsonMkTreeNode>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
struct JsonBlockRange {
    pub start: u64,
    pub end: u64,
}

impl JsonBlockRange {
    fn to_ascii_bytes(&self) -> Vec<u8> {
        format!("{}-{}", self.start, self.end).into_bytes()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
struct JsonInnerRange {
    pub inner_range: JsonBlockRange,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
struct JsonMkMapProof<K> {
    pub master_proof: JsonMkProof,
    pub sub_proofs: Vec<(K, JsonMkMapProof<K>)>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct PathStep {
    /// Raw sibling bytes as they appear in Mithril's tree.
    /// This can be either:
    /// - a raw leaf bytestring
    /// - or a 32-byte internal hash
    pub sibling: Vec<u8>,
    /// Whether the sibling is hashed on the left:
    /// `parent = Blake2s256(sibling || current)`
    pub sibling_on_left: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct FlatMmrPath {
    pub leaf: Vec<u8>,
    pub leaf_pos: u64,
    pub mmr_size: u64,
    pub root: Vec<u8>,
    pub steps: Vec<PathStep>,
}

impl FlatMmrPath {
    fn compute_root(&self) -> Vec<u8> {
        let mut current = self.leaf.clone();
        for step in &self.steps {
            current = if step.sibling_on_left {
                blake2s256(&step.sibling, &current)
            } else {
                blake2s256(&current, &step.sibling)
            };
        }
        current
    }

    fn validate(&self) -> Result<()> {
        let computed = self.compute_root();
        ensure!(
            computed == self.root,
            "flat path root mismatch: computed={}, expected={}",
            hex::encode(computed),
            hex::encode(&self.root)
        );
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum RecursiveMembershipProof<K> {
    Leaf {
        path: FlatMmrPath,
    },
    Nested {
        key: K,
        master_path: FlatMmrPath,
        child: Box<RecursiveMembershipProof<K>>,
    },
}

impl<K> RecursiveMembershipProof<K> {
    fn root(&self) -> &[u8] {
        match self {
            Self::Leaf { path } => &path.root,
            Self::Nested { master_path, .. } => &master_path.root,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LegacyTypedPathStepWitness {
    pub kind: u64,
    pub raw_sibling: Vec<u8>,
    pub hash_sibling: [u8; 32],
    pub sibling_on_left: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LockingTxHashWitness {
    pub source_tx_id: Vec<u8>,
    pub output_index_ascii: Vec<u8>,
    pub input_payment_credential: Vec<u8>,
    pub input_datum: Vec<u8>,
    pub bridge_policy_id: Vec<u8>,
    pub transferred_asset_name: Vec<u8>,
    pub asset_amount_ascii: Vec<u8>,
    pub ada_amount_ascii: Vec<u8>,
    pub destination_payment_credential: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LegacyTxCircuitWitness {
    /// Internal normalized witness model for the current Rust pipeline.
    ///
    /// This struct is not a stable JSON contract. Callers that need a stable
    /// serialized interface should use `to_circom_inputs()` or
    /// `to_suggested_circom_inputs()`, which define the circuit-facing JSON
    /// shape consumed by the Groth16 tooling.
    /// Full typed prefix of the sub-path up to and including the last raw
    /// sibling. The first entry is the canonical "bottom" step.
    pub sub_prefix_steps: Vec<LegacyTypedPathStepWitness>,
    pub sub_upper_siblings: Vec<[u8; 32]>,
    pub sub_upper_sibling_on_left: Vec<bool>,

    pub range_ascii: Vec<u8>,

    /// Full typed prefix of the master-path up to and including the last raw
    /// sibling. The first entry is the canonical "bottom" step.
    pub master_prefix_steps: Vec<LegacyTypedPathStepWitness>,
    pub master_upper_siblings: Vec<[u8; 32]>,
    pub master_upper_sibling_on_left: Vec<bool>,

    pub expected_root: [u8; 32],

    pub cardano_tx_hash: [u8; 32],
    pub sub_root: [u8; 32],
    pub master_root: [u8; 32],
}

/// Canonical tx hash ASCII length used by Mithril legacy transaction proofs.
pub const LEGACY_TX_HASH_ASCII_BYTES: usize = 64;
pub const LEGACY_TX_BOTTOM_KIND_RAW: u64 = 0;
pub const LEGACY_TX_BOTTOM_KIND_HASH: u64 = 1;

/// Suggested Circom instantiation sizes for `MithrilLegacyTxMembership`.
///
/// These constants match the suggested `component main = MithrilLegacyTxMembership(...)`
/// in `mithril_legacy_tx_membership.circom`.
pub const LEGACY_TX_CIRCOM_MAX_SUB_UPPER_HEIGHT: usize = 32;
pub const LEGACY_TX_CIRCOM_MAX_RANGE_ASCII_BYTES: usize = 32;
pub const LEGACY_TX_CIRCOM_MAX_SUB_PREFIX_LEN: usize = 10;
pub const LEGACY_TX_CIRCOM_MAX_MASTER_PREFIX_LEN: usize = 1;
pub const LEGACY_TX_CIRCOM_MAX_MASTER_UPPER_HEIGHT: usize = 32;
pub const LEGACY_TX_CIRCOM_SUB_RAW_SIBLING_BYTES: usize = LEGACY_TX_HASH_ASCII_BYTES;
pub const LEGACY_TX_CIRCOM_MASTER_RAW_SIBLING_BYTES: usize =
    LEGACY_TX_CIRCOM_MAX_RANGE_ASCII_BYTES + 32;
pub const LOCKING_TX_SOURCE_TX_ID_MAX_BYTES: usize = 64;
pub const LOCKING_TX_OUTPUT_INDEX_ASCII_MAX_BYTES: usize = 20;
pub const LOCKING_TX_INPUT_PAYMENT_CREDENTIAL_MAX_BYTES: usize = 64;
pub const LOCKING_TX_INPUT_DATUM_MAX_BYTES: usize = 128;
pub const LOCKING_TX_BRIDGE_POLICY_ID_MAX_BYTES: usize = 32;
pub const LOCKING_TX_TRANSFERRED_ASSET_NAME_MAX_BYTES: usize = 32;
pub const LOCKING_TX_ASSET_AMOUNT_ASCII_MAX_BYTES: usize = 20;
pub const LOCKING_TX_ADA_AMOUNT_ASCII_MAX_BYTES: usize = 20;
pub const LOCKING_TX_DESTINATION_PAYMENT_CREDENTIAL_MAX_BYTES: usize = 64;
pub const SNAPSHOT_MEMBERSHIP_PACKED_PUBLIC_INPUTS: usize = 6;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PackedSnapshotMembershipPublicInputs {
    pub cardano_tx_hash_hi: String,
    pub cardano_tx_hash_lo: String,
    pub sub_root_hi: String,
    pub sub_root_lo: String,
    pub snapshot_root_hi: String,
    pub snapshot_root_lo: String,
}

pub fn mithril_legacy_tx_membership_rust_witness<I>(inputs: I) -> Vec<BigInt>
where
    I: IntoIterator<Item = (String, Vec<BigInt>)>,
{
    mithrillegacytxmembershipmain_witness(inputs)
}

fn pack_16_bytes_be(bytes: &[u8; 16]) -> u128 {
    bytes
        .iter()
        .fold(0u128, |acc, byte| (acc << 8) | (*byte as u128))
}

fn unpack_16_bytes_be(value: u128) -> [u8; 16] {
    let mut out = [0u8; 16];
    for i in 0..16 {
        out[15 - i] = ((value >> (i * 8)) & 0xff) as u8;
    }
    out
}

fn pack_digest_to_halves(digest: &[u8; 32]) -> [u128; 2] {
    let mut hi = [0u8; 16];
    hi.copy_from_slice(&digest[..16]);
    let mut lo = [0u8; 16];
    lo.copy_from_slice(&digest[16..]);
    [pack_16_bytes_be(&hi), pack_16_bytes_be(&lo)]
}

pub fn pack_snapshot_membership_public_inputs(
    cardano_tx_hash: &[u8; 32],
    sub_root: &[u8; 32],
    snapshot_root: &[u8; 32],
) -> PackedSnapshotMembershipPublicInputs {
    let [cardano_tx_hash_hi, cardano_tx_hash_lo] = pack_digest_to_halves(cardano_tx_hash);
    let [sub_root_hi, sub_root_lo] = pack_digest_to_halves(sub_root);
    let [snapshot_root_hi, snapshot_root_lo] = pack_digest_to_halves(snapshot_root);

    PackedSnapshotMembershipPublicInputs {
        cardano_tx_hash_hi: cardano_tx_hash_hi.to_string(),
        cardano_tx_hash_lo: cardano_tx_hash_lo.to_string(),
        sub_root_hi: sub_root_hi.to_string(),
        sub_root_lo: sub_root_lo.to_string(),
        snapshot_root_hi: snapshot_root_hi.to_string(),
        snapshot_root_lo: snapshot_root_lo.to_string(),
    }
}

pub fn pack_snapshot_membership_public_inputs_vec(
    cardano_tx_hash: &[u8; 32],
    sub_root: &[u8; 32],
    snapshot_root: &[u8; 32],
) -> Vec<String> {
    let packed =
        pack_snapshot_membership_public_inputs(cardano_tx_hash, sub_root, snapshot_root);
    vec![
        packed.cardano_tx_hash_hi,
        packed.cardano_tx_hash_lo,
        packed.sub_root_hi,
        packed.sub_root_lo,
        packed.snapshot_root_hi,
        packed.snapshot_root_lo,
    ]
}

pub fn unpack_snapshot_membership_public_inputs(
    packed: &[String],
) -> Result<([u8; 32], [u8; 32], [u8; 32])> {
    ensure!(
        packed.len() == SNAPSHOT_MEMBERSHIP_PACKED_PUBLIC_INPUTS,
        "expected {} packed public inputs, got {}",
        SNAPSHOT_MEMBERSHIP_PACKED_PUBLIC_INPUTS,
        packed.len()
    );

    let parse = |index: usize| -> Result<u128> {
        packed[index]
            .parse::<u128>()
            .with_context(|| format!("packed public input {index} is not a valid u128"))
    };

    let lock_hi = unpack_16_bytes_be(parse(0)?);
    let lock_lo = unpack_16_bytes_be(parse(1)?);
    let sub_hi = unpack_16_bytes_be(parse(2)?);
    let sub_lo = unpack_16_bytes_be(parse(3)?);
    let root_hi = unpack_16_bytes_be(parse(4)?);
    let root_lo = unpack_16_bytes_be(parse(5)?);

    let mut cardano_tx_hash = [0u8; 32];
    cardano_tx_hash[..16].copy_from_slice(&lock_hi);
    cardano_tx_hash[16..].copy_from_slice(&lock_lo);

    let mut sub_root = [0u8; 32];
    sub_root[..16].copy_from_slice(&sub_hi);
    sub_root[16..].copy_from_slice(&sub_lo);

    let mut snapshot_root = [0u8; 32];
    snapshot_root[..16].copy_from_slice(&root_hi);
    snapshot_root[16..].copy_from_slice(&root_lo);

    Ok((cardano_tx_hash, sub_root, snapshot_root))
}

impl LockingTxHashWitness {
    pub fn validate(&self) -> Result<()> {
        assert_fixed_field_bound(
            &self.source_tx_id,
            LOCKING_TX_SOURCE_TX_ID_MAX_BYTES,
            "locking_tx.source_tx_id",
        )?;
        assert_fixed_field_bound(
            &self.output_index_ascii,
            LOCKING_TX_OUTPUT_INDEX_ASCII_MAX_BYTES,
            "locking_tx.output_index_ascii",
        )?;
        assert_fixed_field_bound(
            &self.input_payment_credential,
            LOCKING_TX_INPUT_PAYMENT_CREDENTIAL_MAX_BYTES,
            "locking_tx.input_payment_credential",
        )?;
        assert_fixed_field_bound(
            &self.input_datum,
            LOCKING_TX_INPUT_DATUM_MAX_BYTES,
            "locking_tx.input_datum",
        )?;
        assert_fixed_field_bound(
            &self.bridge_policy_id,
            LOCKING_TX_BRIDGE_POLICY_ID_MAX_BYTES,
            "locking_tx.bridge_policy_id",
        )?;
        assert_fixed_field_bound(
            &self.transferred_asset_name,
            LOCKING_TX_TRANSFERRED_ASSET_NAME_MAX_BYTES,
            "locking_tx.transferred_asset_name",
        )?;
        assert_fixed_field_bound(
            &self.asset_amount_ascii,
            LOCKING_TX_ASSET_AMOUNT_ASCII_MAX_BYTES,
            "locking_tx.asset_amount_ascii",
        )?;
        assert_fixed_field_bound(
            &self.ada_amount_ascii,
            LOCKING_TX_ADA_AMOUNT_ASCII_MAX_BYTES,
            "locking_tx.ada_amount_ascii",
        )?;
        assert_fixed_field_bound(
            &self.destination_payment_credential,
            LOCKING_TX_DESTINATION_PAYMENT_CREDENTIAL_MAX_BYTES,
            "locking_tx.destination_payment_credential",
        )?;
        Ok(())
    }

    pub fn compute_sha256(&self) -> Result<[u8; 32]> {
        self.validate()?;

        let mut preimage = Vec::with_capacity(496);
        append_fixed_field(&mut preimage, &self.source_tx_id, LOCKING_TX_SOURCE_TX_ID_MAX_BYTES)?;
        append_fixed_field(
            &mut preimage,
            &self.output_index_ascii,
            LOCKING_TX_OUTPUT_INDEX_ASCII_MAX_BYTES,
        )?;
        append_fixed_field(
            &mut preimage,
            &self.input_payment_credential,
            LOCKING_TX_INPUT_PAYMENT_CREDENTIAL_MAX_BYTES,
        )?;
        append_fixed_field(
            &mut preimage,
            &self.input_datum,
            LOCKING_TX_INPUT_DATUM_MAX_BYTES,
        )?;
        append_fixed_field(
            &mut preimage,
            &self.bridge_policy_id,
            LOCKING_TX_BRIDGE_POLICY_ID_MAX_BYTES,
        )?;
        append_fixed_field(
            &mut preimage,
            &self.transferred_asset_name,
            LOCKING_TX_TRANSFERRED_ASSET_NAME_MAX_BYTES,
        )?;
        append_fixed_field(
            &mut preimage,
            &self.asset_amount_ascii,
            LOCKING_TX_ASSET_AMOUNT_ASCII_MAX_BYTES,
        )?;
        append_fixed_field(
            &mut preimage,
            &self.ada_amount_ascii,
            LOCKING_TX_ADA_AMOUNT_ASCII_MAX_BYTES,
        )?;
        append_fixed_field(
            &mut preimage,
            &self.destination_payment_credential,
            LOCKING_TX_DESTINATION_PAYMENT_CREDENTIAL_MAX_BYTES,
        )?;
        append_fixed_field(
            &mut preimage,
            &self.bridge_policy_id,
            LOCKING_TX_BRIDGE_POLICY_ID_MAX_BYTES,
        )?;

        Ok(Sha256::digest(&preimage).into())
    }
}

impl LegacyTxCircuitWitness {
    pub fn sub_bottom(&self) -> Result<&LegacyTypedPathStepWitness> {
        self.sub_prefix_steps
            .first()
            .ok_or_else(|| anyhow!("sub path prefix unexpectedly empty"))
    }

    pub fn master_bottom(&self) -> Result<&LegacyTypedPathStepWitness> {
        self.master_prefix_steps
            .first()
            .ok_or_else(|| anyhow!("master path prefix unexpectedly empty"))
    }

    pub fn range_ascii_len(&self) -> usize {
        self.range_ascii.len()
    }

    /// Export this witness as the stable circuit-facing JSON contract, already
    /// padded to the array sizes expected by the current Circom template.
    pub fn to_circom_inputs(
        &self,
        max_sub_prefix_len: usize,
        max_sub_upper_height: usize,
        max_range_ascii_bytes: usize,
        max_master_prefix_len: usize,
        max_master_upper_height: usize,
    ) -> Result<Value> {
        let sub_bottom = self.sub_bottom()?;
        let master_bottom = self.master_bottom()?;
        ensure!(self.cardano_tx_hash.len() == 32, "cardano tx hash must be 32 bytes");
        ensure!(
            sub_bottom.kind == LEGACY_TX_BOTTOM_KIND_RAW
                || sub_bottom.kind == LEGACY_TX_BOTTOM_KIND_HASH,
            "invalid sub bottom kind"
        );
        ensure!(
            sub_bottom.raw_sibling.len() == LEGACY_TX_CIRCOM_SUB_RAW_SIBLING_BYTES,
            "sub raw sibling must be padded to {} bytes",
            LEGACY_TX_CIRCOM_SUB_RAW_SIBLING_BYTES
        );
        ensure!(
            !self.sub_prefix_steps.is_empty(),
            "sub prefix steps cannot be empty"
        );
        ensure!(
            self.sub_prefix_steps.len() <= max_sub_prefix_len,
            "sub prefix too long"
        );
        ensure!(
            self.sub_prefix_steps
                .iter()
                .all(|step| step.raw_sibling.len() == LEGACY_TX_CIRCOM_SUB_RAW_SIBLING_BYTES),
            "sub raw siblings must be padded to {} bytes",
            LEGACY_TX_CIRCOM_SUB_RAW_SIBLING_BYTES
        );
        ensure!(
            self.sub_prefix_steps.iter().all(|step| {
                step.kind == LEGACY_TX_BOTTOM_KIND_RAW || step.kind == LEGACY_TX_BOTTOM_KIND_HASH
            }),
            "invalid sub prefix kind"
        );
        ensure!(
            self.sub_prefix_steps.len() + self.sub_upper_siblings.len() >= 1,
            "sub path must contain at least one step"
        );
        ensure!(
            self.sub_root.len() == 32,
            "sub root must be 32 bytes"
        );
        ensure!(
            self.sub_prefix_steps.iter().skip(1).all(|step| {
                step.raw_sibling.len() == LEGACY_TX_CIRCOM_SUB_RAW_SIBLING_BYTES
            }),
            "sub prefix raw sibling width mismatch"
        );
        ensure!(
            self.sub_upper_siblings.len() <= max_sub_upper_height,
            "sub upper path too tall"
        );
        ensure!(
            self.range_ascii_len() <= max_range_ascii_bytes,
            "range ascii too large"
        );
        ensure!(
            master_bottom.kind == LEGACY_TX_BOTTOM_KIND_RAW
                || master_bottom.kind == LEGACY_TX_BOTTOM_KIND_HASH,
            "invalid master bottom kind"
        );
        ensure!(
            master_bottom.raw_sibling.len() == LEGACY_TX_CIRCOM_MASTER_RAW_SIBLING_BYTES,
            "master raw sibling must be padded to {} bytes",
            LEGACY_TX_CIRCOM_MASTER_RAW_SIBLING_BYTES
        );
        ensure!(
            !self.master_prefix_steps.is_empty(),
            "master prefix steps cannot be empty"
        );
        ensure!(
            self.master_prefix_steps.len() <= max_master_prefix_len,
            "master prefix too long"
        );
        ensure!(
            self.master_prefix_steps.iter().all(|step| {
                step.raw_sibling.len() == LEGACY_TX_CIRCOM_MASTER_RAW_SIBLING_BYTES
            }),
            "master raw siblings must be padded to {} bytes",
            LEGACY_TX_CIRCOM_MASTER_RAW_SIBLING_BYTES
        );
        ensure!(
            self.master_prefix_steps.iter().all(|step| {
                step.kind == LEGACY_TX_BOTTOM_KIND_RAW || step.kind == LEGACY_TX_BOTTOM_KIND_HASH
            }),
            "invalid master prefix kind"
        );
        ensure!(
            self.master_prefix_steps
                .iter()
                .all(|step| step.kind == LEGACY_TX_BOTTOM_KIND_HASH),
            "current Circom contract only supports hash-only master prefix steps"
        );
        ensure!(
            self.master_root.len() == 32,
            "master root must be 32 bytes"
        );
        ensure!(
            self.master_upper_siblings.len() <= max_master_upper_height,
            "master upper path too tall"
        );

        let mut obj = Map::new();
        obj.insert("cardano_tx_hash_b".to_string(), json!(self.cardano_tx_hash));
        obj.insert(
            "sub_prefix_kinds".to_string(),
            json!(pad_u64s(
                &self.sub_prefix_steps.iter().map(|step| step.kind).collect::<Vec<_>>(),
                max_sub_prefix_len
            )),
        );
        obj.insert(
            "sub_prefix_raw_siblings_b".to_string(),
            json!(pad_nested_bytes(
                &self
                    .sub_prefix_steps
                    .iter()
                    .map(|step| step.raw_sibling.clone())
                    .collect::<Vec<_>>(),
                max_sub_prefix_len,
                LEGACY_TX_CIRCOM_SUB_RAW_SIBLING_BYTES
            )),
        );
        obj.insert(
            "sub_prefix_hash_siblings_b".to_string(),
            json!(pad_vec_32(
                &self
                    .sub_prefix_steps
                    .iter()
                    .map(|step| step.hash_sibling)
                    .collect::<Vec<_>>(),
                max_sub_prefix_len
            )),
        );
        obj.insert(
            "sub_prefix_sibling_on_left".to_string(),
            json!(pad_bools(
                &self
                    .sub_prefix_steps
                    .iter()
                    .map(|step| step.sibling_on_left)
                    .collect::<Vec<_>>(),
                max_sub_prefix_len
            )),
        );
        obj.insert(
            "sub_prefix_enabled".to_string(),
            json!(enabled_flags(self.sub_prefix_steps.len(), max_sub_prefix_len)),
        );
        obj.insert(
            "sub_upper_siblings_b".to_string(),
            json!(pad_vec_32(&self.sub_upper_siblings, max_sub_upper_height)),
        );
        obj.insert(
            "sub_upper_sibling_on_left".to_string(),
            json!(pad_bools(
                &self.sub_upper_sibling_on_left,
                max_sub_upper_height
            )),
        );
        obj.insert(
            "sub_upper_enabled".to_string(),
            json!(enabled_flags(
                self.sub_upper_siblings.len(),
                max_sub_upper_height
            )),
        );
        obj.insert(
            "range_ascii_b".to_string(),
            json!(pad_bytes(&self.range_ascii, max_range_ascii_bytes)),
        );
        obj.insert("range_ascii_len".to_string(), json!(self.range_ascii_len()));
        obj.insert(
            "master_prefix_kinds".to_string(),
            json!(pad_u64s(
                &self
                    .master_prefix_steps
                    .iter()
                    .map(|step| step.kind)
                    .collect::<Vec<_>>(),
                max_master_prefix_len
            )),
        );
        obj.insert(
            "master_prefix_raw_siblings_b".to_string(),
            json!(pad_nested_bytes(
                &self
                    .master_prefix_steps
                    .iter()
                    .map(|step| step.raw_sibling.clone())
                    .collect::<Vec<_>>(),
                max_master_prefix_len,
                LEGACY_TX_CIRCOM_MASTER_RAW_SIBLING_BYTES
            )),
        );
        obj.insert(
            "master_prefix_hash_siblings_b".to_string(),
            json!(pad_vec_32(
                &self
                    .master_prefix_steps
                    .iter()
                    .map(|step| step.hash_sibling)
                    .collect::<Vec<_>>(),
                max_master_prefix_len
            )),
        );
        obj.insert(
            "master_prefix_sibling_on_left".to_string(),
            json!(pad_bools(
                &self
                    .master_prefix_steps
                    .iter()
                    .map(|step| step.sibling_on_left)
                    .collect::<Vec<_>>(),
                max_master_prefix_len
            )),
        );
        obj.insert(
            "master_prefix_enabled".to_string(),
            json!(enabled_flags(
                self.master_prefix_steps.len(),
                max_master_prefix_len
            )),
        );
        obj.insert(
            "master_upper_siblings_b".to_string(),
            json!(pad_vec_32(
                &self.master_upper_siblings,
                max_master_upper_height
            )),
        );
        obj.insert(
            "master_upper_sibling_on_left".to_string(),
            json!(pad_bools(
                &self.master_upper_sibling_on_left,
                max_master_upper_height
            )),
        );
        obj.insert(
            "master_upper_enabled".to_string(),
            json!(enabled_flags(
                self.master_upper_siblings.len(),
                max_master_upper_height
            )),
        );
        obj.insert("expected_root_b".to_string(), json!(self.expected_root));

        Ok(Value::Object(obj))
    }

    /// Export this witness using the canonical stable Circom-facing sizes
    /// documented in `mithril_legacy_tx_membership.circom`.
    pub fn to_suggested_circom_inputs(&self) -> Result<Value> {
        self.to_circom_inputs(
            LEGACY_TX_CIRCOM_MAX_SUB_PREFIX_LEN,
            LEGACY_TX_CIRCOM_MAX_SUB_UPPER_HEIGHT,
            LEGACY_TX_CIRCOM_MAX_RANGE_ASCII_BYTES,
            LEGACY_TX_CIRCOM_MAX_MASTER_PREFIX_LEN,
            LEGACY_TX_CIRCOM_MAX_MASTER_UPPER_HEIGHT,
        )
    }
}

/// Normalize a single legacy proof hex payload into the witness expected by the
/// circuit, assuming the caller already knows the expected root from a verified
/// certificate.
pub fn legacy_tx_witness_from_proof_hex(
    proof_json_hex: &str,
    tx_hash: &str,
    expected_root: [u8; 32],
) -> Result<LegacyTxCircuitWitness> {
    let proof = decode_mkmap_proof_from_json_hex::<JsonInnerRange>(proof_json_hex)?;
    let membership = normalize_recursive_membership(&proof, tx_hash.as_bytes(), &|range| {
        range.inner_range.to_ascii_bytes()
    })?;

    let (range, sub_path, master_path) = match membership {
        RecursiveMembershipProof::Nested {
            key,
            master_path,
            child,
        } => match *child {
            RecursiveMembershipProof::Leaf { path } => (key, path, master_path),
            RecursiveMembershipProof::Nested { .. } => {
                bail!("legacy tx circuit expects exactly one nested block-range level")
            }
        },
        RecursiveMembershipProof::Leaf { .. } => {
            bail!("legacy tx circuit expects one MKMap nesting level")
        }
    };

    ensure!(
        tx_hash.as_bytes() == sub_path.leaf.as_slice(),
        "normalized sub-path leaf does not match tx hash"
    );
    sub_path.validate()?;
    master_path.validate()?;

    let sub_root = to_fixed_32(&sub_path.root)
        .context("sub-root is not 32 bytes; degenerate single-leaf cases are not supported by the current circuit")?;
    let master_root = to_fixed_32(&master_path.root)
        .context("master-root is not 32 bytes; degenerate single-leaf cases are not supported by the current circuit")?;

    ensure!(
        master_root == expected_root,
        "proof root mismatch with expected certificate root"
    );

    let range_ascii = range.inner_range.to_ascii_bytes();
    let sub_split = split_path_for_circuit(&sub_path)?;
    let master_split = split_path_for_circuit(&master_path)?;
    let sub_prefix_steps = classify_sub_prefix_steps(&sub_split.prefix_steps)?;
    let master_prefix_steps = classify_master_prefix_steps(&master_split.prefix_steps)?;
        let cardano_tx_hash = decode_hex_32(tx_hash)
            .with_context(|| format!("tx_hash is not valid 32-byte hex: {tx_hash}"))?;

        Ok(LegacyTxCircuitWitness {
            sub_prefix_steps,
            sub_upper_siblings: sub_split.upper_siblings,
            sub_upper_sibling_on_left: sub_split.upper_sibling_on_left,

            range_ascii,

            master_prefix_steps,
            master_upper_siblings: master_split.upper_siblings,
            master_upper_sibling_on_left: master_split.upper_sibling_on_left,

            expected_root,
            cardano_tx_hash,
            sub_root,
            master_root,
        })
    }

#[derive(Debug, Clone)]
struct SplitForCircuit {
    prefix_steps: Vec<PathStep>,
    upper_siblings: Vec<[u8; 32]>,
    upper_sibling_on_left: Vec<bool>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ClassifiedPathStep {
    kind: u64,
    raw_sibling: Vec<u8>,
    hash_sibling: [u8; 32],
    sibling_on_left: bool,
}

fn split_path_for_circuit(path: &FlatMmrPath) -> Result<SplitForCircuit> {
    let steps = path
        .steps
        .as_slice()
        .split_first()
        .ok_or_else(|| anyhow!("path contains no steps; degenerate single-leaf proofs are not supported by the current circuit"))?;
    let prefix_len = path
        .steps
        .iter()
        .rposition(|step| step.sibling.len() != 32)
        .map_or(1, |index| index + 1);
    let (prefix_steps, upper) = path.steps.split_at(prefix_len);
    let _ = steps;

    let mut upper_siblings = Vec::with_capacity(upper.len());
    let mut upper_sibling_on_left = Vec::with_capacity(upper.len());
    for step in upper {
        upper_siblings.push(
            to_fixed_32(&step.sibling)
                .context("upper-path sibling is not 32 bytes; unsupported proof shape")?,
        );
        upper_sibling_on_left.push(step.sibling_on_left);
    }

    Ok(SplitForCircuit {
        prefix_steps: prefix_steps.to_vec(),
        upper_siblings,
        upper_sibling_on_left,
    })
}

fn classify_sub_step(step: &PathStep) -> Result<ClassifiedPathStep> {
    match step.sibling.len() {
        LEGACY_TX_CIRCOM_SUB_RAW_SIBLING_BYTES => Ok(ClassifiedPathStep {
            kind: LEGACY_TX_BOTTOM_KIND_RAW,
            raw_sibling: step.sibling.clone(),
            hash_sibling: [0u8; 32],
            sibling_on_left: step.sibling_on_left,
        }),
        32 => Ok(ClassifiedPathStep {
            kind: LEGACY_TX_BOTTOM_KIND_HASH,
            raw_sibling: vec![0u8; LEGACY_TX_CIRCOM_SUB_RAW_SIBLING_BYTES],
            hash_sibling: to_fixed_32(&step.sibling)?,
            sibling_on_left: step.sibling_on_left,
        }),
        size => bail!("unsupported sub bottom sibling size: {size}"),
    }
}

fn classify_master_step(step: &PathStep) -> Result<ClassifiedPathStep> {
    match step.sibling.len() {
        32 => Ok(ClassifiedPathStep {
            kind: LEGACY_TX_BOTTOM_KIND_HASH,
            raw_sibling: vec![0u8; LEGACY_TX_CIRCOM_MASTER_RAW_SIBLING_BYTES],
            hash_sibling: to_fixed_32(&step.sibling)?,
            sibling_on_left: step.sibling_on_left,
        }),
        size if (33..=LEGACY_TX_CIRCOM_MASTER_RAW_SIBLING_BYTES).contains(&size) => Ok(
            ClassifiedPathStep {
                kind: LEGACY_TX_BOTTOM_KIND_RAW,
                raw_sibling: pad_bytes(&step.sibling, LEGACY_TX_CIRCOM_MASTER_RAW_SIBLING_BYTES),
                hash_sibling: [0u8; 32],
                sibling_on_left: step.sibling_on_left,
            },
        ),
        size => bail!("unsupported master bottom sibling size: {size}"),
    }
}

fn classify_sub_prefix_steps(steps: &[PathStep]) -> Result<Vec<LegacyTypedPathStepWitness>> {
    steps.iter()
        .map(classify_sub_step)
        .map(|result| {
            result.map(|step| LegacyTypedPathStepWitness {
                kind: step.kind,
                raw_sibling: step.raw_sibling,
                hash_sibling: step.hash_sibling,
                sibling_on_left: step.sibling_on_left,
            })
        })
        .collect()
}

fn classify_master_prefix_steps(steps: &[PathStep]) -> Result<Vec<LegacyTypedPathStepWitness>> {
    steps.iter()
        .map(classify_master_step)
        .map(|result| {
            result.map(|step| LegacyTypedPathStepWitness {
                kind: step.kind,
                raw_sibling: step.raw_sibling,
                hash_sibling: step.hash_sibling,
                sibling_on_left: step.sibling_on_left,
            })
        })
        .collect()
}

fn decode_mkmap_proof_from_json_hex<K>(proof_json_hex: &str) -> Result<JsonMkMapProof<K>>
where
    K: for<'de> Deserialize<'de>,
{
    let raw = hex::decode(proof_json_hex).with_context(|| "proof is not valid hex")?;
    serde_json::from_slice(&raw).with_context(|| "proof hex does not decode to JSON MKMapProof")
}

fn normalize_recursive_membership<K, F>(
    proof: &JsonMkMapProof<K>,
    target_leaf_bytes: &[u8],
    key_to_bytes: &F,
) -> Result<RecursiveMembershipProof<K>>
where
    K: Clone + Debug,
    F: Fn(&K) -> Vec<u8>,
{
    if proof.sub_proofs.is_empty() {
        let path = normalize_mmr_membership_path(&proof.master_proof, target_leaf_bytes)?;
        return Ok(RecursiveMembershipProof::Leaf { path });
    }

    for (key, child) in &proof.sub_proofs {
        if let Ok(child_membership) = normalize_recursive_membership(
            child,
            target_leaf_bytes,
            key_to_bytes,
        )
        {
            let mut master_leaf_preimage = key_to_bytes(key);
            master_leaf_preimage.extend_from_slice(child_membership.root());
            let master_leaf = blake2s256_many(&master_leaf_preimage);
            let master_path = normalize_mmr_membership_path(&proof.master_proof, &master_leaf)?;
            return Ok(RecursiveMembershipProof::Nested {
                key: key.clone(),
                master_path,
                child: Box::new(child_membership),
            });
        }
    }

    bail!("target leaf not found in recursive MKMapProof")
}

fn normalize_mmr_membership_path(
    proof: &JsonMkProof,
    target_leaf_bytes: &[u8],
) -> Result<FlatMmrPath> {
    ensure!(!proof.inner_leaves.is_empty(), "proof contains no leaves");

    let mut leaves: Vec<(u64, Vec<u8>)> = proof
        .inner_leaves
        .iter()
        .map(|(pos, leaf)| (*pos, leaf.hash.clone()))
        .collect();

    if leaves.iter().any(|(pos, _)| pos_height_in_tree(*pos) > 0) {
        bail!("proof contains non-leaf positions");
    }

    leaves.sort_by_key(|(pos, _)| *pos);
    leaves.dedup_by(|a, b| a.0 == b.0);

    let matching_positions: Vec<u64> = leaves
        .iter()
        .filter_map(|(pos, leaf)| (leaf.as_slice() == target_leaf_bytes).then_some(*pos))
        .collect();
    let leaf_pos = match matching_positions.as_slice() {
        [pos] => *pos,
        [] => bail!("target leaf not found in proof leaves"),
        _ => bail!("target leaf appears multiple times in proof leaves"),
    };

    let peaks = get_peaks(proof.inner_proof_size);
    let mut proof_index = 0usize;
    let mut remaining_leaves = leaves;
    let mut peak_hashes: Vec<Vec<u8>> = Vec::new();
    let mut target_peak_index = None;
    let mut target_steps = Vec::new();

    for peak_pos in peaks {
        let peak_leaves = take_while_vec(&mut remaining_leaves, |(pos, _)| *pos <= peak_pos);

        if peak_leaves.len() == 1 && peak_leaves[0].0 == peak_pos {
            let (pos, peak_leaf) = &peak_leaves[0];
            if *pos == leaf_pos {
                target_peak_index = Some(peak_hashes.len());
            }
            peak_hashes.push(peak_leaf.clone());
            continue;
        }

        if peak_leaves.is_empty() {
            if let Some(next_peak_root) = proof.inner_proof_items.get(proof_index) {
                peak_hashes.push(next_peak_root.hash.clone());
                proof_index += 1;
                continue;
            }
            // This matches `ckb-merkle-mountain-range`: once proof items are
            // exhausted while scanning empty peaks, the remaining right-hand
            // peaks are already represented by the last bagged root we
            // consumed, or the proof is malformed. We stop here and let the
            // reconstructed root validation catch malformed cases.
            break;
        }

        let peak = reconstruct_peak_from_multiple_leaves(
            peak_leaves,
            peak_pos,
            &proof.inner_proof_items[proof_index..],
            leaf_pos,
        )?;
        proof_index += peak.consumed;
        if peak.target_is_in_peak {
            target_peak_index = Some(peak_hashes.len());
            target_steps = peak.target_steps;
        }
        peak_hashes.push(peak.peak_root);
    }

    ensure!(
        remaining_leaves.is_empty(),
        "corrupted proof: unconsumed leaves"
    );

    if proof_index < proof.inner_proof_items.len() {
        let rhs_bagged = &proof.inner_proof_items[proof_index];
        peak_hashes.push(rhs_bagged.hash.clone());
        proof_index += 1;
    }

    ensure!(
        proof_index == proof.inner_proof_items.len(),
        "corrupted proof: unconsumed proof items"
    );

    let target_peak_index = target_peak_index.ok_or_else(|| anyhow!("target peak not found"))?;
    let (root, bagging_steps) = bagging_with_target_path(peak_hashes, target_peak_index)?;

    ensure!(
        root == proof.inner_root.hash,
        "reconstructed root mismatch: computed={}, expected={}",
        hex::encode(&root),
        hex::encode(&proof.inner_root.hash)
    );

    target_steps.extend(bagging_steps);

    Ok(FlatMmrPath {
        leaf: target_leaf_bytes.to_vec(),
        leaf_pos,
        mmr_size: proof.inner_proof_size,
        root,
        steps: target_steps,
    })
}

#[derive(Debug, Clone)]
struct PeakReconstruction {
    peak_root: Vec<u8>,
    target_steps: Vec<PathStep>,
    target_is_in_peak: bool,
    consumed: usize,
}

fn reconstruct_peak_from_multiple_leaves(
    leaves: Vec<(u64, Vec<u8>)>,
    peak_pos: u64,
    proof_items: &[JsonMkTreeNode],
    target_leaf_pos: u64,
) -> Result<PeakReconstruction> {
    #[derive(Debug, Clone)]
    struct QueueNode {
        pos: u64,
        hash: Vec<u8>,
        height: u8,
        contains_target: bool,
    }

    ensure!(!leaves.is_empty(), "can't reconstruct peak from empty leaves");

    let mut queue: VecDeque<QueueNode> = leaves
        .into_iter()
        .map(|(pos, hash)| QueueNode {
            pos,
            hash,
            height: 0,
            contains_target: pos == target_leaf_pos,
        })
        .collect();

    let mut proof_index = 0usize;
    let mut target_steps = Vec::new();

    while let Some(current) = queue.pop_front() {
        if current.pos == peak_pos {
            ensure!(queue.is_empty(), "corrupted proof: queue not fully consumed");
            return Ok(PeakReconstruction {
                peak_root: current.hash,
                target_steps,
                target_is_in_peak: current.contains_target,
                consumed: proof_index,
            });
        }

        let next_height = pos_height_in_tree(current.pos + 1);
        let sibling_distance = sibling_offset(current.height);
        let current_is_right_sibling = next_height > current.height;

        let (parent_pos, parent_hash, parent_contains_target) = if current_is_right_sibling {
            let sibling_pos = current
                .pos
                .checked_sub(sibling_distance)
                .ok_or_else(|| anyhow!("corrupted proof: invalid right sibling offset"))?;
            let parent_pos = current.pos + 1;

            if Some(sibling_pos) == queue.front().map(|node| node.pos) {
                let sibling = queue.pop_front().expect("front exists");
                if current.contains_target {
                    target_steps.push(PathStep {
                        sibling: sibling.hash.clone(),
                        sibling_on_left: true,
                    });
                } else if sibling.contains_target {
                    target_steps.push(PathStep {
                        sibling: current.hash.clone(),
                        sibling_on_left: false,
                    });
                }
                (
                    parent_pos,
                    blake2s256(&sibling.hash, &current.hash),
                    current.contains_target || sibling.contains_target,
                )
            } else {
                let sibling = proof_items
                    .get(proof_index)
                    .ok_or_else(|| anyhow!("corrupted proof: missing sibling while climbing peak"))?
                    .hash
                    .clone();
                proof_index += 1;
                if current.contains_target {
                    target_steps.push(PathStep {
                        sibling: sibling.clone(),
                        sibling_on_left: true,
                    });
                }
                (
                    parent_pos,
                    blake2s256(&sibling, &current.hash),
                    current.contains_target,
                )
            }
        } else {
            let sibling_pos = current.pos + sibling_distance;
            let parent_pos = current.pos + parent_offset(current.height);

            if Some(sibling_pos) == queue.front().map(|node| node.pos) {
                let sibling = queue.pop_front().expect("front exists");
                if current.contains_target {
                    target_steps.push(PathStep {
                        sibling: sibling.hash.clone(),
                        sibling_on_left: false,
                    });
                } else if sibling.contains_target {
                    target_steps.push(PathStep {
                        sibling: current.hash.clone(),
                        sibling_on_left: true,
                    });
                }
                (
                    parent_pos,
                    blake2s256(&current.hash, &sibling.hash),
                    current.contains_target || sibling.contains_target,
                )
            } else {
                let sibling = proof_items
                    .get(proof_index)
                    .ok_or_else(|| anyhow!("corrupted proof: missing sibling while climbing peak"))?
                    .hash
                    .clone();
                proof_index += 1;
                if current.contains_target {
                    target_steps.push(PathStep {
                        sibling: sibling.clone(),
                        sibling_on_left: false,
                    });
                }
                (
                    parent_pos,
                    blake2s256(&current.hash, &sibling),
                    current.contains_target,
                )
            }
        };

        ensure!(
            parent_pos <= peak_pos,
            "corrupted proof: parent exceeded peak"
        );

        queue.push_back(QueueNode {
            pos: parent_pos,
            hash: parent_hash,
            height: current.height + 1,
            contains_target: parent_contains_target,
        });
    }

    bail!("corrupted proof: could not reconstruct peak root")
}

fn bagging_with_target_path(
    peak_hashes: Vec<Vec<u8>>,
    target_peak_index: usize,
) -> Result<(Vec<u8>, Vec<PathStep>)> {
    #[derive(Clone)]
    struct Node {
        hash: Vec<u8>,
        contains_target: bool,
    }

    ensure!(!peak_hashes.is_empty(), "cannot bag empty peak set");
    ensure!(
        target_peak_index < peak_hashes.len(),
        "target peak index out of bounds"
    );

    let mut nodes: Vec<Node> = peak_hashes
        .into_iter()
        .enumerate()
        .map(|(i, hash)| Node {
            hash,
            contains_target: i == target_peak_index,
        })
        .collect();

    let mut steps = Vec::new();

    while nodes.len() > 1 {
        let right = nodes.pop().expect("non-empty");
        let left = nodes.pop().expect("at least two nodes");

        let parent_hash = blake2s256(&right.hash, &left.hash);
        let contains_target = right.contains_target || left.contains_target;

        if contains_target {
            if right.contains_target {
                steps.push(PathStep {
                    sibling: left.hash.clone(),
                    sibling_on_left: false,
                });
            } else {
                steps.push(PathStep {
                    sibling: right.hash.clone(),
                    sibling_on_left: true,
                });
            }
        }

        nodes.push(Node {
            hash: parent_hash,
            contains_target,
        });
    }

    Ok((nodes.pop().expect("one root").hash, steps))
}

fn blake2s256(left: &[u8], right: &[u8]) -> Vec<u8> {
    let mut hasher = Blake2s256::new();
    hasher.update(left);
    hasher.update(right);
    hasher.finalize().to_vec()
}

fn blake2s256_many(bytes: &[u8]) -> Vec<u8> {
    let mut hasher = Blake2s256::new();
    hasher.update(bytes);
    hasher.finalize().to_vec()
}

fn to_fixed_32(bytes: &[u8]) -> Result<[u8; 32]> {
    ensure!(bytes.len() == 32, "expected 32 bytes, got {}", bytes.len());
    let mut out = [0u8; 32];
    out.copy_from_slice(bytes);
    Ok(out)
}

fn decode_hex_32(hex_string: &str) -> Result<[u8; 32]> {
    let bytes = hex::decode(hex_string).with_context(|| "invalid root hex")?;
    to_fixed_32(&bytes)
}

fn pad_bytes(bytes: &[u8], target_len: usize) -> Vec<u8> {
    let mut out = vec![0u8; target_len];
    let copy_len = bytes.len().min(target_len);
    out[..copy_len].copy_from_slice(&bytes[..copy_len]);
    out
}

fn assert_fixed_field_bound(bytes: &[u8], max_len: usize, name: &str) -> Result<()> {
    ensure!(
        bytes.len() <= max_len,
        "{name} exceeds max length {max_len}: got {}",
        bytes.len()
    );
    ensure!(
        max_len <= usize::from(u8::MAX),
        "{name} max length must fit in the current fixed-field length prefix"
    );
    Ok(())
}

fn append_fixed_field(out: &mut Vec<u8>, bytes: &[u8], max_len: usize) -> Result<()> {
    assert_fixed_field_bound(bytes, max_len, "fixed-field-bytes")?;
    out.push(0);
    out.push(
        u8::try_from(bytes.len()).context("fixed-field length does not fit in u8 length prefix")?,
    );
    out.extend_from_slice(bytes);
    out.resize(out.len() + (max_len - bytes.len()), 0);
    Ok(())
}

fn pad_vec_32(values: &[[u8; 32]], target_len: usize) -> Vec<[u8; 32]> {
    let mut out = vec![[0u8; 32]; target_len];
    let copy_len = values.len().min(target_len);
    out[..copy_len].copy_from_slice(&values[..copy_len]);
    out
}

fn pad_nested_bytes(values: &[Vec<u8>], target_len: usize, inner_len: usize) -> Vec<Vec<u8>> {
    let mut out = vec![vec![0u8; inner_len]; target_len];
    let copy_len = values.len().min(target_len);
    for i in 0..copy_len {
        out[i] = pad_bytes(&values[i], inner_len);
    }
    out
}

fn pad_u64s(values: &[u64], target_len: usize) -> Vec<u64> {
    let mut out = vec![0u64; target_len];
    let copy_len = values.len().min(target_len);
    out[..copy_len].copy_from_slice(&values[..copy_len]);
    out
}

fn pad_bools(values: &[bool], target_len: usize) -> Vec<u64> {
    let mut out = vec![0u64; target_len];
    for (dst, src) in out.iter_mut().zip(values.iter().copied()) {
        *dst = bool_to_field(src);
    }
    out
}

fn enabled_flags(enabled_len: usize, target_len: usize) -> Vec<u64> {
    let mut out = vec![0u64; target_len];
    for item in out.iter_mut().take(enabled_len.min(target_len)) {
        *item = 1;
    }
    out
}

fn bool_to_field(value: bool) -> u64 {
    if value { 1 } else { 0 }
}

fn parent_offset(height: u8) -> u64 {
    2u64 << height
}

fn sibling_offset(height: u8) -> u64 {
    (2u64 << height) - 1
}

fn pos_height_in_tree(mut pos: u64) -> u8 {
    if pos == 0 {
        return 0;
    }

    let mut peak_size = u64::MAX >> pos.leading_zeros();
    while peak_size > 0 {
        if pos >= peak_size {
            pos -= peak_size;
        }
        peak_size >>= 1;
    }
    pos as u8
}

fn take_while_vec<T, P: Fn(&T) -> bool>(v: &mut Vec<T>, p: P) -> Vec<T> {
    for i in 0..v.len() {
        if !p(&v[i]) {
            return v.drain(..i).collect();
        }
    }
    mem::take(v)
}

fn get_peaks(mmr_size: u64) -> Vec<u64> {
    if mmr_size == 0 {
        return vec![];
    }

    let leading_zeros = mmr_size.leading_zeros();
    let mut pos = mmr_size;
    let mut peak_size = u64::MAX >> leading_zeros;
    let mut peaks = Vec::with_capacity(64 - leading_zeros as usize);
    let mut peaks_sum = 0;
    while peak_size > 0 {
        if pos >= peak_size {
            pos -= peak_size;
            peaks.push(peaks_sum + peak_size - 1);
            peaks_sum += peak_size;
        }
        peak_size >>= 1;
    }
    peaks
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE_TX_HASH: &str =
        "c49f43c59263446f448dc81518d11f53ff0c73355a93064c728abcf4a37fe2b0";
    const SAMPLE_MASTER_ROOT_HEX: &str =
        "ffd8e6eb84efabe853b339f4c45083ddf4e5e714c37374163183c64500658af6";
    const SAMPLE_PROOF_JSON_HEX: &str = "7b226d61737465725f70726f6f66223a7b22696e6e65725f726f6f74223a7b2268617368223a5b3235352c3231362c3233302c3233352c3133322c3233392c3137312c3233322c38332c3137392c35372c3234342c3139362c38302c3133312c3232312c3234342c3232392c3233312c32302c3139352c3131352c3131362c32322c34392c3133312c3139382c36392c302c3130312c3133382c3234365d7d2c22696e6e65725f6c6561766573223a5b5b3438303539392c7b2268617368223a5b3234362c3136312c3132302c3136302c36322c3232362c3139332c3135352c3135362c3231322c37352c3231352c3139392c3138372c3130362c3131352c36302c3132302c3136342c3235332c37362c3131392c3133322c32372c3234352c37302c31312c31312c3135342c3130332c35302c3135355d7d5d5d2c22696e6e65725f70726f6f665f73697a65223a3533363932352c22696e6e65725f70726f6f665f6974656d73223a5b7b2268617368223a5b3134392c3138322c3139382c36312c3131382c36312c36382c3133362c3132312c3134302c37312c3137372c3232332c3230352c35372c3234302c35302c3234322c3138362c38372c3139372c3134372c3234322c39312c32332c3131332c3230372c3231312c38322c35392c3137352c3139375d7d2c7b2268617368223a5b33302c33322c35322c3137322c33312c3135342c3233332c3139312c3133352c34332c3136372c342c3133332c31372c34362c3132362c3131352c3131352c3130312c3235332c34302c32382c31352c3134372c36312c32382c36312c3131372c3137312c33312c3131312c39335d7d2c7b2268617368223a5b3133302c3234312c39392c3231372c3231362c34372c3139312c3234352c3234382c3131302c3138352c36312c34372c3139322c32322c3133302c3135302c3137382c37342c35322c37302c3133332c3138332c37302c3234372c3232332c35392c37352c3232392c37392c3138322c3130335d7d2c7b2268617368223a5b3133352c3130342c34392c3133352c3230302c35392c3232372c3138342c3231372c39392c35302c3137332c3130352c3138382c3134312c37342c3133382c332c3131372c31352c3232362c3234372c3133392c35342c3134342c3137372c33332c3233362c3233332c35332c3133322c35305d7d2c7b2268617368223a5b3134392c31332c3134392c3132352c3233342c31382c32372c3235352c33382c39382c3132342c37352c3131352c3231342c33312c3137352c32372c3133362c382c3130352c3136322c3135302c3138322c39382c36362c3230332c3230332c39342c36352c3139302c3132382c33355d7d2c7b2268617368223a5b3130302c382c372c39392c3231382c35322c3136382c3135362c3130302c39392c3232302c34312c3138342c3230372c3235352c3136342c3130362c3138312c36312c382c36342c3137362c3133392c3131302c35392c3130392c3137372c3230302c3132372c3130332c3130372c3134305d7d2c7b2268617368223a5b33312c3232302c3134332c3235352c3131312c3230362c3231342c37332c3137362c3137322c3133362c3132342c3235322c342c3134332c37362c3139382c3232332c3230322c3233342c3232352c302c3139392c3233322c36392c3233352c32332c3230392c39362c36382c3132332c3131315d7d2c7b2268617368223a5b3136332c3132312c3131392c3138392c3235322c32312c3138302c3132332c3233362c34322c39392c3132322c3138332c3131392c36332c37362c36382c31392c3133382c3133362c3130332c3130372c3136362c37342c3231362c3135342c3234362c36362c3131352c332c3132322c3133355d7d2c7b2268617368223a5b3135312c3139362c3230302c3132302c3230322c3137352c3231362c3231332c3132342c39362c38362c3132322c34382c3136382c3137372c3135382c3138312c3230392c3234312c3232322c3136352c312c39392c3131342c3130392c37312c3137372c302c3132392c31312c3134342c3135395d7d2c7b2268617368223a5b3135342c3132322c3139372c3133312c37362c3234322c33392c34322c33362c372c3132352c38342c3133362c3137322c3233362c3138332c36362c3135372c3134362c39342c3232372c3133322c3232362c3233392c3130372c3131372c3230392c3234302c36392c3233342c37302c3234385d7d2c7b2268617368223a5b39342c3135382c3134382c3133332c3234332c38382c36392c34332c32302c3131372c34382c3137302c37392c3131382c3139312c3231392c3134372c3139362c3139392c31372c3132392c32342c35372c3231392c3132382c3235322c38322c312c3139312c3135332c34352c37325d7d2c7b2268617368223a5b35312c3131362c3138362c34352c3137322c31342c38342c3131362c34322c3230392c3132352c3138382c3132302c39322c36332c35352c3136372c3235332c3138392c3232362c39392c33352c3139362c3235332c3134352c32382c3231382c3135392c39362c3133362c34392c32335d7d2c7b2268617368223a5b3138392c3233342c3234312c3135392c3134372c3132322c3132352c39362c3230382c38332c3133342c3134352c31322c392c3134392c35382c32332c36342c36372c3133352c3139332c3233322c3231392c3130312c3139302c31362c3131352c3136342c3135372c3131312c3235302c365d7d2c7b2268617368223a5b33302c33302c3235302c34372c37302c3231372c39372c3233382c3233352c3138332c3134392c37302c3233302c36322c3137302c37392c3132382c3138322c312c36352c3138382c35352c3133392c3133332c3133362c3230372c3233332c31372c3231302c3231382c37382c37385d7d2c7b2268617368223a5b38362c3137392c3230312c3230342c31392c3130392c35302c38312c3234362c3132312c3137392c3136342c34392c3230302c32312c37362c3131352c3130392c36322c3137362c3135342c3232362c3133312c3231322c3235332c3234362c37302c3232342c3139352c35352c3233372c3138355d7d2c7b2268617368223a5b3134352c3235322c3135372c3232302c3234352c32352c3138322c36332c3138372c3132322c3235352c3130322c3136362c3234382c34312c3130332c3130302c3231392c37372c3235312c3131322c31392c3138392c32342c3233372c3230382c36392c3134322c3139372c32342c33332c34345d7d2c7b2268617368223a5b3135332c35302c3139332c3231362c35372c3234302c3135392c3235302c39342c37302c39342c3233342c362c39362c35392c37392c372c36312c3138352c3135372c39352c3136302c3130342c3138392c3131372c3136322c3136392c31342c3135372c3130332c3131342c3131385d7d2c7b2268617368223a5b3136312c3234372c3231392c37352c33332c3230382c33342c3130342c3133382c33302c34372c35322c3230392c3230382c3131302c34362c3139392c3132312c3139342c3234312c3130382c3130302c37392c3138382c3137342c3135372c3133312c3232382c34382c3134312c372c325d7d2c7b2268617368223a5b39322c3232362c3235342c3130352c33392c32382c3137362c3234372c3130352c3130382c3132392c3233312c36332c3139372c38382c34312c39382c3231372c3133392c35312c32312c36382c3230392c3230382c3234332c3230392c3132382c3230322c37332c37332c3138302c37375d7d5d7d2c227375625f70726f6f6673223a5b5b7b22696e6e65725f72616e6765223a7b227374617274223a333638363134352c22656e64223a333638363136307d7d2c7b226d61737465725f70726f6f66223a7b22696e6e65725f726f6f74223a7b2268617368223a5b36372c3132302c3136352c3230342c3231382c3137312c3133352c3137372c32372c3134372c37302c3231312c3233322c3137362c3139372c32322c34382c3231352c3234392c33322c3139382c3137362c3235352c3135342c3135362c3135372c39312c31322c33332c34382c312c32395d7d2c22696e6e65725f6c6561766573223a5b5b34312c7b2268617368223a5b39392c35322c35372c3130322c35322c35312c39392c35332c35372c35302c35342c35312c35322c35322c35342c3130322c35322c35322c35362c3130302c39392c35362c34392c35332c34392c35362c3130302c34392c34392c3130322c35332c35312c3130322c3130322c34382c39392c35352c35312c35312c35332c35332c39372c35372c35312c34382c35342c35322c39392c35352c35302c35362c39372c39382c39392c3130322c35322c39372c35312c35352c3130322c3130312c35302c39382c34385d7d5d5d2c22696e6e65725f70726f6f665f73697a65223a34362c22696e6e65725f70726f6f665f6974656d73223a5b7b2268617368223a5b32372c3137342c32362c38342c37362c31362c3136342c3233342c3137362c3134322c3233342c32362c3137392c3134372c3139362c3132312c3233372c3132342c3138322c3231382c3135302c3232352c31352c32382c32372c392c3230312c3134372c36342c3232352c33312c38305d7d2c7b2268617368223a5b3130312c35332c35342c34392c3130302c35342c39392c35352c35322c35322c3130322c3130302c39372c35362c35312c39382c35352c35312c35312c3130312c39382c39392c39392c35352c39382c35362c35352c35352c34382c35302c34382c35352c3130322c3130322c34382c3130312c3130312c35372c3130302c35322c39382c35352c39382c3130312c35352c35362c3130322c35372c39372c35302c35362c3130312c3130322c39382c35352c35352c35302c35372c35342c35312c35322c35352c3130322c39375d7d2c7b2268617368223a5b3133382c3133372c39302c3234342c3231312c32332c3138312c38372c3136312c3230332c37302c31332c35352c39332c3139392c3232352c35312c3139382c3232392c3138322c3233302c3137332c31352c31332c33352c3136342c3132352c31332c3130362c392c3231382c34385d7d2c7b2268617368223a5b3235312c3234362c3230362c382c37392c3233322c3133312c32322c3134302c3134322c32302c39372c3133382c3235322c38312c3136342c36362c3136342c31382c3233382c38362c3136312c3139302c31302c3233302c3132352c33362c35322c32342c3231312c3233382c3130355d7d5d7d2c227375625f70726f6f6673223a5b5d7d5d5d7d";

    fn real_sample_expected_root() -> [u8; 32] {
        decode_hex_32(SAMPLE_MASTER_ROOT_HEX).unwrap()
    }

    fn real_sample_proof() -> JsonMkMapProof<JsonInnerRange> {
        decode_mkmap_proof_from_json_hex::<JsonInnerRange>(SAMPLE_PROOF_JSON_HEX).unwrap()
    }

    fn real_sample_witness() -> LegacyTxCircuitWitness {
        legacy_tx_witness_from_proof_hex(
            SAMPLE_PROOF_JSON_HEX,
            SAMPLE_TX_HASH,
            real_sample_expected_root(),
        )
        .unwrap()
    }

    #[test]
    fn block_range_ascii_encoding_matches_mithril() {
        let range = JsonBlockRange {
            start: 3686145,
            end: 3686160,
        };
        assert_eq!(b"3686145-3686160".to_vec(), range.to_ascii_bytes());
    }

    #[test]
    fn bagging_target_left_uses_sibling_on_left() {
        let left = vec![1u8; 32];
        let right = vec![2u8; 32];
        let (root, steps) = bagging_with_target_path(vec![left.clone(), right.clone()], 0).unwrap();
        assert_eq!(1, steps.len());
        assert!(steps[0].sibling_on_left);
        assert_eq!(right, steps[0].sibling);
        assert_eq!(blake2s256(&right, &left), root);
    }

    #[test]
    fn bagging_target_right_uses_sibling_on_right() {
        let left = vec![1u8; 32];
        let right = vec![2u8; 32];
        let (root, steps) = bagging_with_target_path(vec![left.clone(), right.clone()], 1).unwrap();
        assert_eq!(1, steps.len());
        assert!(!steps[0].sibling_on_left);
        assert_eq!(left, steps[0].sibling);
        assert_eq!(blake2s256(&right, &left), root);
    }

    #[test]
    fn decode_mkmap_proof_from_real_sample() {
        let proof = real_sample_proof();
        assert_eq!(1, proof.master_proof.inner_leaves.len());
        assert_eq!(1, proof.sub_proofs.len());
        assert_eq!(536925, proof.master_proof.inner_proof_size);
        assert_eq!(46, proof.sub_proofs[0].1.master_proof.inner_proof_size);
    }

    #[test]
    fn normalize_single_leaf_subproof_from_real_sample() {
        let proof = real_sample_proof();
        let subproof = &proof.sub_proofs[0].1.master_proof;
        let path = normalize_mmr_membership_path(subproof, SAMPLE_TX_HASH.as_bytes()).unwrap();

        assert_eq!(41, path.leaf_pos);
        assert_eq!(46, path.mmr_size);
        assert!(!path.steps.is_empty());
        path.validate().unwrap();
        assert_eq!(hex::encode(path.root), "4378a5ccdaab87b11b9346d3e8b0c51630d7f920c6b0ff9a9c9d5b0c2130011d");
    }

    #[test]
    fn normalize_recursive_membership_from_real_sample() {
        let proof = real_sample_proof();
        let membership = normalize_recursive_membership(&proof, SAMPLE_TX_HASH.as_bytes(), &|range| {
            range.inner_range.to_ascii_bytes()
        })
        .unwrap();

        match membership {
            RecursiveMembershipProof::Nested {
                key,
                master_path,
                child,
            } => {
                assert_eq!(3686145, key.inner_range.start);
                assert_eq!(3686160, key.inner_range.end);
                master_path.validate().unwrap();
                assert_eq!(SAMPLE_MASTER_ROOT_HEX, hex::encode(master_path.root));

                match *child {
                    RecursiveMembershipProof::Leaf { path } => {
                        path.validate().unwrap();
                        assert_eq!(SAMPLE_TX_HASH.as_bytes(), path.leaf.as_slice());
                    }
                    RecursiveMembershipProof::Nested { .. } => panic!("unexpected extra nesting"),
                }
            }
            RecursiveMembershipProof::Leaf { .. } => panic!("expected nested proof"),
        }
    }

    #[test]
    fn legacy_tx_witness_from_proof_hex_from_real_sample() {
        let expected_root = real_sample_expected_root();
        let witness = real_sample_witness();

        assert_eq!(b"3686145-3686160".to_vec(), witness.range_ascii);
        assert_eq!(32, witness.sub_root.len());
        assert_eq!(expected_root, witness.master_root);
        let sub_bottom = witness.sub_bottom().unwrap();
        let master_bottom = witness.master_bottom().unwrap();
        assert!(
            sub_bottom.kind == LEGACY_TX_BOTTOM_KIND_RAW
                || sub_bottom.kind == LEGACY_TX_BOTTOM_KIND_HASH
        );
        assert!(
            master_bottom.kind == LEGACY_TX_BOTTOM_KIND_RAW
                || master_bottom.kind == LEGACY_TX_BOTTOM_KIND_HASH
        );
    }

    #[test]
    fn real_sample_witness_uses_cardano_tx_hash_as_public_digest() {
        let witness = real_sample_witness();
        assert_eq!(hex::encode(witness.cardano_tx_hash), SAMPLE_TX_HASH);
    }

    #[test]
    fn real_sample_witness_has_expected_shape() {
        let witness = real_sample_witness();

        assert_eq!(b"3686145-3686160".to_vec(), witness.range_ascii);
        assert_eq!(witness.range_ascii_len(), witness.range_ascii.len());
        assert_eq!(32, witness.sub_root.len());
        assert_eq!(32, witness.master_root.len());
        assert_eq!(3, witness.sub_upper_siblings.len());
        assert!(witness.master_upper_siblings.len() >= 8);
    }

    #[test]
    fn normalize_recursive_membership_hashes_master_leaf_preimage() {
        let proof = real_sample_proof();
        let membership = normalize_recursive_membership(&proof, SAMPLE_TX_HASH.as_bytes(), &|range| {
            range.inner_range.to_ascii_bytes()
        })
        .unwrap();

        match membership {
            RecursiveMembershipProof::Nested {
                key,
                master_path,
                child,
            } => match *child {
                RecursiveMembershipProof::Leaf { path } => {
                    let mut preimage = key.inner_range.to_ascii_bytes();
                    preimage.extend_from_slice(&path.root);
                    assert_eq!(blake2s256_many(&preimage), master_path.leaf);
                }
                RecursiveMembershipProof::Nested { .. } => panic!("unexpected extra nesting"),
            },
            RecursiveMembershipProof::Leaf { .. } => panic!("expected nested proof"),
        }
    }

    #[test]
    fn split_path_for_circuit_preserves_bottom_and_upper() {
        let path = FlatMmrPath {
            leaf: b"leaf".to_vec(),
            leaf_pos: 0,
            mmr_size: 3,
            root: [9u8; 32].to_vec(),
            steps: vec![
                PathStep {
                    sibling: vec![7u8; 64],
                    sibling_on_left: true,
                },
                PathStep {
                    sibling: vec![8u8; 32],
                    sibling_on_left: false,
                },
            ],
        };

        let split = split_path_for_circuit(&path).unwrap();
        assert_eq!(1, split.prefix_steps.len());
        assert_eq!(64, split.prefix_steps[0].sibling.len());
        assert_eq!([8u8; 32], split.upper_siblings[0]);
        assert_eq!(vec![false], split.upper_sibling_on_left);
    }

    #[test]
    fn split_path_for_circuit_keeps_multi_step_typed_prefix() {
        let path = FlatMmrPath {
            leaf: b"leaf".to_vec(),
            leaf_pos: 0,
            mmr_size: 7,
            root: [3u8; 32].to_vec(),
            steps: vec![
                PathStep {
                    sibling: vec![1u8; 32],
                    sibling_on_left: false,
                },
                PathStep {
                    sibling: vec![2u8; 32],
                    sibling_on_left: true,
                },
                PathStep {
                    sibling: vec![3u8; 64],
                    sibling_on_left: false,
                },
                PathStep {
                    sibling: vec![4u8; 64],
                    sibling_on_left: true,
                },
                PathStep {
                    sibling: vec![5u8; 32],
                    sibling_on_left: false,
                },
            ],
        };

        let split = split_path_for_circuit(&path).unwrap();
        assert_eq!(4, split.prefix_steps.len());
        assert_eq!(32, split.prefix_steps[0].sibling.len());
        assert_eq!(32, split.prefix_steps[1].sibling.len());
        assert_eq!(64, split.prefix_steps[2].sibling.len());
        assert_eq!(64, split.prefix_steps[3].sibling.len());
        assert_eq!(vec![[5u8; 32]], split.upper_siblings);
        assert_eq!(vec![false], split.upper_sibling_on_left);
    }

    #[test]
    fn classify_sub_prefix_steps_accept_hash_then_raw() {
        let steps = vec![
            PathStep {
                sibling: vec![7u8; 32],
                sibling_on_left: true,
            },
            PathStep {
                sibling: vec![8u8; 64],
                sibling_on_left: false,
            },
        ];

        let classified = classify_sub_prefix_steps(&steps).unwrap();
        assert_eq!(2, classified.len());
        assert_eq!(LEGACY_TX_BOTTOM_KIND_HASH, classified[0].kind);
        assert_eq!(LEGACY_TX_BOTTOM_KIND_RAW, classified[1].kind);
        assert_eq!([7u8; 32], classified[0].hash_sibling);
        assert_eq!(64, classified[1].raw_sibling.len());
    }

    #[test]
    fn circom_inputs_are_padded_and_enabled_flags_match_path_lengths() {
        let witness = real_sample_witness();

        let inputs = witness
            .to_circom_inputs(
                1,
                witness.sub_upper_siblings.len(),
                32,
                1,
                witness.master_upper_siblings.len(),
            )
            .unwrap();

        let obj = inputs.as_object().unwrap();
        assert_eq!(32, obj["cardano_tx_hash_b"].as_array().unwrap().len());
        assert_eq!(1, obj["sub_prefix_enabled"].as_array().unwrap().len());
        assert_eq!(1, obj["master_prefix_enabled"].as_array().unwrap().len());
        assert_eq!(64, obj["sub_prefix_raw_siblings_b"][0].as_array().unwrap().len());
        assert_eq!(32, obj["sub_prefix_hash_siblings_b"][0].as_array().unwrap().len());
        assert_eq!(64, obj["master_prefix_raw_siblings_b"][0].as_array().unwrap().len());
        assert_eq!(32, obj["master_prefix_hash_siblings_b"][0].as_array().unwrap().len());
        assert_eq!(32, obj["range_ascii_b"].as_array().unwrap().len());
        assert_eq!(witness.sub_upper_siblings.len(), obj["sub_upper_enabled"].as_array().unwrap().len());
        assert_eq!(witness.master_upper_siblings.len(), obj["master_upper_enabled"].as_array().unwrap().len());
    }

    #[test]
    fn suggested_circom_sizes_accept_real_sample() {
        let witness = real_sample_witness();

        let inputs = witness.to_suggested_circom_inputs().unwrap();
        let obj = inputs.as_object().unwrap();

        assert_eq!(32, obj["cardano_tx_hash_b"].as_array().unwrap().len());
        assert_eq!(
            LEGACY_TX_CIRCOM_MAX_SUB_PREFIX_LEN,
            obj["sub_prefix_kinds"].as_array().unwrap().len()
        );
        assert_eq!(
            LEGACY_TX_CIRCOM_MAX_SUB_UPPER_HEIGHT,
            obj["sub_upper_siblings_b"].as_array().unwrap().len()
        );
        assert_eq!(
            LEGACY_TX_CIRCOM_MAX_RANGE_ASCII_BYTES,
            obj["range_ascii_b"].as_array().unwrap().len()
        );
        assert_eq!(
            LEGACY_TX_CIRCOM_MAX_MASTER_PREFIX_LEN,
            obj["master_prefix_kinds"].as_array().unwrap().len()
        );
        assert_eq!(
            LEGACY_TX_CIRCOM_MAX_MASTER_UPPER_HEIGHT,
            obj["master_upper_siblings_b"].as_array().unwrap().len()
        );
    }

    #[test]
    fn real_sample_fits_within_suggested_circom_bounds() {
        let witness = real_sample_witness();

        assert_eq!(
            LEGACY_TX_CIRCOM_SUB_RAW_SIBLING_BYTES,
            witness.sub_bottom().unwrap().raw_sibling.len()
        );
        assert!(witness.sub_upper_siblings.len() <= LEGACY_TX_CIRCOM_MAX_SUB_UPPER_HEIGHT);
        assert!(witness.range_ascii_len() <= LEGACY_TX_CIRCOM_MAX_RANGE_ASCII_BYTES);
        assert_eq!(
            LEGACY_TX_CIRCOM_MASTER_RAW_SIBLING_BYTES,
            witness.master_bottom().unwrap().raw_sibling.len()
        );
        assert!(witness.master_upper_siblings.len() <= LEGACY_TX_CIRCOM_MAX_MASTER_UPPER_HEIGHT);
        assert_eq!(3, witness.sub_upper_siblings.len());
        assert_eq!(18, witness.master_upper_siblings.len());
        assert_eq!(15, witness.range_ascii_len());
        assert_eq!(LEGACY_TX_BOTTOM_KIND_HASH, witness.master_bottom().unwrap().kind);
    }

    #[test]
    fn real_sample_sub_bottom_matches_future_design2_raw_case() {
        let witness = real_sample_witness();

        let sub_bottom = witness.sub_bottom().unwrap();
        assert_eq!(LEGACY_TX_BOTTOM_KIND_RAW, sub_bottom.kind);
        assert_eq!(64, sub_bottom.raw_sibling.len());
        assert!(sub_bottom.hash_sibling.iter().all(|byte| *byte == 0));
    }

    #[test]
    fn real_sample_master_bottom_matches_future_design2_hash_case() {
        let witness = real_sample_witness();

        let master_bottom = witness.master_bottom().unwrap();
        assert_eq!(LEGACY_TX_BOTTOM_KIND_HASH, master_bottom.kind);
        assert_eq!(64, master_bottom.raw_sibling.len());
        assert_eq!(32, master_bottom.hash_sibling.len());
    }

    #[test]
    fn real_sample_master_leaf_fits_future_fixed_64_byte_bottom_leaf_case() {
        let witness = real_sample_witness();

        let future_master_leaf_fixed_bytes = LEGACY_TX_CIRCOM_MAX_RANGE_ASCII_BYTES + 32;
        assert_eq!(15, witness.range_ascii_len());
        assert_eq!(47, witness.range_ascii_len() + 32);
        assert!(witness.range_ascii_len() + 32 <= future_master_leaf_fixed_bytes);
        assert_eq!(64, future_master_leaf_fixed_bytes);
    }

    #[test]
    fn circom_inputs_reject_too_small_master_height() {
        let witness = real_sample_witness();

        let err = witness
            .to_circom_inputs(
                1,
                witness.sub_upper_siblings.len(),
                32,
                1,
                witness.master_upper_siblings.len().saturating_sub(1),
            )
            .unwrap_err();

        assert!(err.to_string().contains("master upper path too tall"));
    }

    #[test]
    fn circom_inputs_reject_too_small_sub_height() {
        let witness = real_sample_witness();

        let err = witness
            .to_circom_inputs(
                1,
                witness.sub_upper_siblings.len().saturating_sub(1),
                32,
                1,
                witness.master_upper_siblings.len(),
            )
            .unwrap_err();

        assert!(err.to_string().contains("sub upper path too tall"));
    }

    #[test]
    fn circom_inputs_accept_multi_step_sub_prefix_when_capacity_is_sufficient() {
        let mut witness = real_sample_witness();

        witness.sub_prefix_steps.push(LegacyTypedPathStepWitness {
            kind: LEGACY_TX_BOTTOM_KIND_RAW,
            raw_sibling: vec![9u8; LEGACY_TX_CIRCOM_SUB_RAW_SIBLING_BYTES],
            hash_sibling: [0u8; 32],
            sibling_on_left: false,
        });

        let inputs = witness
            .to_circom_inputs(
                2,
                witness.sub_upper_siblings.len(),
                32,
                1,
                witness.master_upper_siblings.len(),
            )
            .unwrap();
        assert_eq!(2, inputs["sub_prefix_enabled"].as_array().unwrap().len());
    }

    #[test]
    fn circom_inputs_reject_too_small_sub_prefix_capacity() {
        let mut witness = real_sample_witness();

        witness.sub_prefix_steps.push(LegacyTypedPathStepWitness {
            kind: LEGACY_TX_BOTTOM_KIND_RAW,
            raw_sibling: vec![9u8; LEGACY_TX_CIRCOM_SUB_RAW_SIBLING_BYTES],
            hash_sibling: [0u8; 32],
            sibling_on_left: false,
        });

        let err = witness
            .to_circom_inputs(1, witness.sub_upper_siblings.len(), 32, 1, witness.master_upper_siblings.len())
            .unwrap_err();
        assert!(err.to_string().contains("sub prefix too long"));
    }

    #[test]
    fn normalize_recursive_membership_rejects_missing_target() {
        let proof = real_sample_proof();
        let err = normalize_recursive_membership(&proof, b"missing", &|range| range.inner_range.to_ascii_bytes())
            .unwrap_err();
        assert!(err.to_string().contains("target leaf not found"));
    }

    #[test]
    fn flat_path_validate_detects_tampering() {
        let proof = real_sample_proof();
        let subproof = &proof.sub_proofs[0].1.master_proof;
        let mut path = normalize_mmr_membership_path(subproof, SAMPLE_TX_HASH.as_bytes()).unwrap();
        path.root[0] ^= 1;
        let err = path.validate().unwrap_err();
        assert!(err.to_string().contains("flat path root mismatch"));
    }
}
