use anyhow::{Context, Result, anyhow, ensure};
use digest::Digest;
use midnight_proofs::poly::kzg::params::ParamsKZG;
use midnight_zk_stdlib::{self as zk, MidnightCircuit};
use rand_chacha::ChaCha20Rng;
use rand_core::SeedableRng;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, btree_map::Entry};

use mithril_stm::{
    ClosedKeyRegistration, Initializer, KeyRegistration, MembershipDigest, MithrilMembershipDigest,
    Parameters, RegistrationEntryForSnark, Signer, SingleSignature,
};

use super::StmCircuit;
use super::crypto::{BaseFieldElement, SchnorrVerificationKey, UniqueSchnorrSignature};
use super::eligibility::{
    compute_target_value_for_snark_lottery, compute_winning_lottery_indices,
};
use crate::plutus_gen::adjusted_types::CardanoFriendlyBlake2b;
use super::witness::{
    CircuitMerkleTreeLeaf, CircuitWitness, CircuitWitnessEntry, MerklePath, MerkleRoot,
    Position, SignedMessageWithoutPrefix,
};

#[derive(Debug, Deserialize)]
struct SerializedMerkleTree {
    nodes: Vec<Vec<u8>>,
    leaf_off: usize,
    n: usize,
}

#[derive(Debug, Deserialize)]
struct SerializedSingleSignature {
    #[serde(default)]
    snark_signature: Option<SerializedSnarkSignature>,
}

#[derive(Debug, Deserialize)]
struct SerializedSnarkSignature {
    schnorr_signature: mithril_stm::UniqueSchnorrSignature,
}

fn build_snark_message(
    merkle_root: &[u8],
    message: &[u8; 32],
) -> Result<[BaseFieldElement; 2]> {
    let root_bytes: [u8; 32] = merkle_root
        .try_into()
        .with_context(|| "Merkle tree root must be exactly 32 bytes")?;
    let root_as_base_field_element = BaseFieldElement::from_bytes(&root_bytes)
        .with_context(|| "Failed to convert Merkle tree root to a local base field element")?;
    let message_as_base_field_element = BaseFieldElement::from_raw(message)
        .with_context(|| "Failed to convert the message into a local base field element")?;

    Ok([root_as_base_field_element, message_as_base_field_element])
}

fn extract_snark_signature(signature: &SingleSignature) -> Result<UniqueSchnorrSignature> {
    let bytes = signature.to_bytes()?;
    if bytes.first() == Some(&1) {
        let serialized: SerializedSingleSignature = ciborium::de::from_reader(&bytes[1..])
            .context("Failed to decode versioned single signature bytes")?;
        let snark_signature = serialized
            .snark_signature
            .ok_or_else(|| anyhow!("SingleSignature is missing SNARK bytes"))?;
        return UniqueSchnorrSignature::from_bytes(&snark_signature.schnorr_signature.to_bytes())
            .with_context(|| {
                "Failed to decode the SNARK signature into the local crypto copy"
            });
    }

    let bytes = signature.to_bytes()?;
    let nr_indices = u64::from_be_bytes(
        bytes.get(0..8)
            .ok_or_else(|| anyhow!("SingleSignature too short"))?
            .try_into()?,
    ) as usize;
    let offset = 8 + nr_indices * 8 + 48 + 8;
    let snark_signature = bytes
        .get(offset..offset + 96)
        .ok_or_else(|| anyhow!("SingleSignature is missing SNARK bytes"))?;

    UniqueSchnorrSignature::from_bytes(snark_signature)
        .with_context(|| "Failed to decode the SNARK signature into the local crypto copy")
}

fn decode_verification_key(
    verification_key: mithril_stm::VerificationKeyForSnark,
) -> Result<SchnorrVerificationKey> {
    SchnorrVerificationKey::from_bytes(&verification_key.to_bytes())
        .with_context(|| "Failed to decode the SNARK verification key into the local crypto copy")
}

fn decode_merkle_root(root_bytes: &[u8]) -> Result<MerkleRoot> {
    let root_array: [u8; 32] = root_bytes
        .try_into()
        .with_context(|| "Merkle root must be 32 bytes")?;
    Ok(BaseFieldElement::from_bytes(&root_array)?.into())
}

fn build_merkle_path(leaf_index: usize, siblings: &[[u8; 32]]) -> Result<MerklePath> {
    let mut decoded_siblings = Vec::with_capacity(siblings.len());
    for (depth, sibling_bytes) in siblings.iter().enumerate() {
        let node = BaseFieldElement::from_bytes(sibling_bytes)
            .with_context(|| "Merkle sibling is not a canonical field element")?;
        let position = if ((leaf_index >> depth) & 1) == 0 {
            Position::Right
        } else {
            Position::Left
        };
        decoded_siblings.push((position, node.into()));
    }

    Ok(MerklePath::new(decoded_siblings))
}

fn decode_serialized_merkle_tree(tree_bytes: &[u8]) -> Result<SerializedMerkleTree> {
    if tree_bytes.first() == Some(&1) {
        return ciborium::de::from_reader(&tree_bytes[1..])
            .context("Failed to decode versioned Merkle tree bytes");
    }

    let mut u64_bytes = [0u8; 8];
    u64_bytes.copy_from_slice(
        tree_bytes
            .get(..8)
            .ok_or_else(|| anyhow!("Serialized Merkle tree is too short"))?,
    );
    let n = usize::try_from(u64::from_be_bytes(u64_bytes))?;
    let num_nodes = n + n.next_power_of_two() - 1;
    let nodes_bytes = tree_bytes
        .get(8..)
        .ok_or_else(|| anyhow!("Serialized Merkle tree is missing node bytes"))?;
    let node_size = nodes_bytes
        .len()
        .checked_div(num_nodes)
        .ok_or_else(|| anyhow!("Invalid serialized Merkle tree"))?;
    ensure!(
        node_size > 0 && node_size * num_nodes == nodes_bytes.len(),
        "Serialized Merkle tree has inconsistent node sizing"
    );

    let nodes = (0..num_nodes)
        .map(|i| nodes_bytes[i * node_size..(i + 1) * node_size].to_vec())
        .collect();

    Ok(SerializedMerkleTree {
        nodes,
        leaf_off: num_nodes - n,
        n,
    })
}

fn build_merkle_material_from_closed_registration(
    closed_reg: &ClosedKeyRegistration,
) -> Result<([u8; 32], Vec<Vec<[u8; 32]>>)> {
    type SnarkHash = <MithrilMembershipDigest as MembershipDigest>::SnarkHash;

    let tree = closed_reg.to_merkle_tree::<<MithrilMembershipDigest as MembershipDigest>::SnarkHash, RegistrationEntryForSnark>();
    let serialized = decode_serialized_merkle_tree(&tree.to_bytes()?)?;
    ensure!(
        serialized.n == closed_reg.number_of_registered_parties(),
        "Serialized Merkle tree party count does not match closed registration"
    );

    let zero_digest = SnarkHash::digest([0u8]).to_vec();
    let n = serialized.n;
    let nodes = &serialized.nodes;
    let root = serialized
        .nodes
        .first()
        .ok_or_else(|| anyhow!("Serialized Merkle tree has no root node"))?
        .clone()
        .try_into()
        .map_err(|_| anyhow!("Merkle root must be 32 bytes"))?;
    let paths = (0..n)
        .map(|leaf_index| {
            let mut idx = serialized.leaf_off + leaf_index;
            let mut siblings = Vec::new();

            while idx > 0 {
                let sibling = if idx.is_multiple_of(2) { idx - 1 } else { idx + 1 };
                let sibling_bytes: [u8; 32] = nodes
                    .get(sibling)
                    .cloned()
                    .unwrap_or_else(|| zero_digest.clone())
                    .try_into()
                    .map_err(|_| anyhow!("Merkle sibling must be 32 bytes"))?;
                siblings.push(sibling_bytes);
                idx = (idx - 1) / 2;
            }

            Ok(siblings)
        })
        .collect::<Result<Vec<_>>>()?;

    Ok((root, paths))
}

fn setup_signers(
    params: Parameters,
    nparties: usize,
    seed: [u8; 32],
) -> Result<(Vec<Signer<MithrilMembershipDigest>>, ClosedKeyRegistration)> {
    let mut rng = ChaCha20Rng::from_seed(seed);
    let mut key_reg = KeyRegistration::initialize();
    let mut initializers = Vec::with_capacity(nparties);

    for _ in 0..nparties {
        let init = Initializer::new(params, 1, &mut rng);
        key_reg
            .register_by_entry(&init.clone().try_into()?)
            .context("Failed to register signer")?;
        initializers.push(init);
    }

    let closed_reg = key_reg
        .close_registration(&params)
        .context("Failed to close registration")?;
    let signers = initializers
        .into_iter()
        .map(|init| init.try_create_signer::<MithrilMembershipDigest>(&closed_reg))
        .collect::<mithril_stm::StmResult<Vec<_>>>()
        .context("Failed to create signers from the closed registration")?;

    Ok((signers, closed_reg))
}

fn collect_signatures(
    signers: &[Signer<MithrilMembershipDigest>],
    message: &[u8; 32],
) -> Vec<SingleSignature> {
    signers
        .iter()
        .filter_map(|signer| signer.create_single_signature(message).ok())
        .collect()
}

fn prepare_instance_and_witness(
    closed_reg: &ClosedKeyRegistration,
    signatures: &[SingleSignature],
    params: Parameters,
    message: &[u8; 32],
) -> Result<((MerkleRoot, SignedMessageWithoutPrefix), Vec<CircuitWitnessEntry>)> {
    let (merkle_root_bytes, merkle_paths) = build_merkle_material_from_closed_registration(closed_reg)?;
    let message_to_sign = build_snark_message(&merkle_root_bytes, message)?;

    let mut unique_index_signature_map: BTreeMap<u64, (SingleSignature, UniqueSchnorrSignature)> =
        BTreeMap::new();

    for signature in signatures {
        let signer_index = signature.signer_index;
        let entry = match closed_reg.get_registration_entry_for_index(&signer_index) {
            Ok(entry) => entry,
            Err(_) => continue,
        };
        let Some(verification_key) = entry.get_verification_key_for_snark() else {
            continue;
        };
        let local_verification_key = decode_verification_key(verification_key)?;
        let snark_signature = match extract_snark_signature(signature) {
            Ok(signature) => signature,
            Err(_) => continue,
        };
        if snark_signature
            .verify(&message_to_sign, &local_verification_key)
            .is_err()
        {
            continue;
        }

        let target = compute_target_value_for_snark_lottery(
            params.phi_f,
            entry.get_stake(),
            closed_reg.total_stake,
        )?;
        let indices = match compute_winning_lottery_indices(
            params.m,
            &message_to_sign,
            &snark_signature,
            target,
        ) {
            Ok(indices) => indices,
            Err(_) => continue,
        };

        for index in indices {
            match unique_index_signature_map.entry(index) {
                Entry::Occupied(mut existing) => {
                    if existing.get().1 > snark_signature {
                        existing.insert((signature.clone(), snark_signature));
                    }
                }
                Entry::Vacant(vacant) => {
                    vacant.insert((signature.clone(), snark_signature));
                }
            }
        }
    }

    if unique_index_signature_map.len() < params.k as usize {
        return Err(anyhow!(
            "Not enough valid signatures for k={}, got {}",
            params.k,
            unique_index_signature_map.len()
        ));
    }

    while unique_index_signature_map.len() > params.k as usize {
        unique_index_signature_map.pop_last();
    }

    let mut witness = Vec::with_capacity(unique_index_signature_map.len());
    for (lottery_index, (signature, snark_signature)) in unique_index_signature_map {
        let signer_index = signature.signer_index;
        let entry = closed_reg
            .get_registration_entry_for_index(&signer_index)
            .context("Missing closed registration entry for signer")?;
        let verification_key = entry
            .get_verification_key_for_snark()
            .ok_or_else(|| anyhow!("Missing SNARK verification key in registration entry"))?;
        let target = compute_target_value_for_snark_lottery(
            params.phi_f,
            entry.get_stake(),
            closed_reg.total_stake,
        )?;
        let merkle_path = build_merkle_path(
            signer_index as usize,
            merkle_paths
                .get(signer_index as usize)
                .ok_or_else(|| anyhow!("Missing Merkle path for signer"))?,
        )?;
        witness.push(CircuitWitnessEntry {
            leaf: CircuitMerkleTreeLeaf(decode_verification_key(verification_key)?, target.into()),
            merkle_path,
            unique_schnorr_signature: snark_signature,
            lottery_index,
        });
    }

    Ok((
        (
            decode_merkle_root(&merkle_root_bytes)?,
            message_to_sign[1].into(),
        ),
        witness,
    ))
}

/// Minimal normalized certificate view needed by the STM proof bundle.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NormalizedStmCertificate {
    pub hash: [u8; 32],
    #[serde(default)]
    pub prev_hash: Vec<u8>,
    pub epoch: u64,
    pub signed_message: [u8; 32],
}

/// Parent/child certificate pair carried alongside the proof bundle.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NormalizedStmCertificates {
    pub parent: NormalizedStmCertificate,
    pub child: NormalizedStmCertificate,
}

/// Circuit parameters for the normalized bundle path.
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct NormalizedStmParameters {
    pub m: u64,
    pub k: u64,
    pub phi_f: f64,
}

impl NormalizedStmParameters {
    fn to_mithril_parameters(self) -> Parameters {
        Parameters {
            m: self.m,
            k: self.k,
            phi_f: self.phi_f,
        }
    }
}

impl From<Parameters> for NormalizedStmParameters {
    fn from(value: Parameters) -> Self {
        Self {
            m: value.m,
            k: value.k,
            phi_f: value.phi_f,
        }
    }
}

/// Public statement committed by the STM proof.
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct NormalizedStmStatement {
    pub public_input_1_merkle_root: [u8; 32],
    pub public_input_2_signed_message: [u8; 32],
}

/// Registration summary needed to rebuild the circuit configuration.
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct NormalizedStmRegistration {
    pub parties_count: usize,
    pub merkle_tree_depth: u32,
}

/// Merkle path representation used in the normalized bundle.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NormalizedStmMerklePath {
    pub leaf_index: usize,
    pub siblings: Vec<[u8; 32]>,
}

/// Single witness entry in the normalized bundle.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NormalizedStmWitnessEntry {
    pub signer_index: usize,
    pub lottery_index: u64,
    pub verification_key_snark: Vec<u8>,
    pub target: [u8; 32],
    pub merkle_path: NormalizedStmMerklePath,
    pub unique_schnorr_signature: Vec<u8>,
}

/// Witness section of the normalized bundle.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NormalizedStmWitness {
    pub entries: Vec<NormalizedStmWitnessEntry>,
}

/// Circuit-facing normalized bundle used by the new proof-generation API.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NormalizedStmBundle {
    pub schema_version: String,
    pub bundle_kind: String,
    pub source_id: String,
    pub stm_parameters: NormalizedStmParameters,
    pub certificates: NormalizedStmCertificates,
    pub statement: NormalizedStmStatement,
    pub registration: NormalizedStmRegistration,
    pub witness: NormalizedStmWitness,
}

impl NormalizedStmBundle {
    fn validate(&self) -> Result<()> {
        ensure!(
            self.schema_version == "1.0.0",
            "Unsupported bundle schema version: {}",
            self.schema_version
        );
        ensure!(
            self.bundle_kind == "mithril_stm_bundle",
            "Unsupported bundle kind: {}",
            self.bundle_kind
        );
        ensure!(
            self.statement.public_input_2_signed_message == self.certificates.child.signed_message,
            "statement.public_input_2_signed_message must match child certificate signed_message"
        );
        ensure!(
            self.witness.entries.len() >= self.stm_parameters.k as usize,
            "Not enough witness entries for k={}, got {}",
            self.stm_parameters.k,
            self.witness.entries.len()
        );

        for entry in &self.witness.entries {
            ensure!(
                entry.signer_index == entry.merkle_path.leaf_index,
                "signer_index must match merkle_path.leaf_index"
            );
            ensure!(
                entry.merkle_path.siblings.len() == self.registration.merkle_tree_depth as usize,
                "Merkle path length {} does not match configured depth {}",
                entry.merkle_path.siblings.len(),
                self.registration.merkle_tree_depth
            );
        }

        Ok(())
    }
}

fn build_merkle_path_from_bundle(path: &NormalizedStmMerklePath) -> Result<MerklePath> {
    build_merkle_path(path.leaf_index, &path.siblings)
}

fn prepare_instance_and_witness_from_bundle(
    bundle: &NormalizedStmBundle,
) -> Result<((MerkleRoot, SignedMessageWithoutPrefix), Vec<CircuitWitnessEntry>)> {
    bundle.validate()?;

    let message_to_sign = build_snark_message(
        &bundle.statement.public_input_1_merkle_root,
        &bundle.statement.public_input_2_signed_message,
    )?;
    let verification_message = message_to_sign.to_vec();

    let witness = bundle
        .witness
        .entries
        .iter()
        .map(|entry| {
            let verification_key = SchnorrVerificationKey::from_bytes(&entry.verification_key_snark)
                .with_context(|| "Failed to decode bundle verification key")?;
            let signature = UniqueSchnorrSignature::from_bytes(&entry.unique_schnorr_signature)
                .with_context(|| "Failed to decode bundle unique Schnorr signature")?;
            let target = BaseFieldElement::from_bytes(&entry.target)
                .with_context(|| "Failed to decode bundle lottery target")?;

            signature
                .verify(&verification_message, &verification_key)
                .with_context(|| "Bundle signature does not verify against the provided statement")?;

            let winning_indices = compute_winning_lottery_indices(
                bundle.stm_parameters.m,
                &verification_message,
                &signature,
                target,
            )
            .with_context(|| "Bundle witness entry does not win the lottery for the given target")?;
            ensure!(
                winning_indices.contains(&entry.lottery_index),
                "Bundle witness lottery index {} is not valid for the given signature",
                entry.lottery_index
            );

            Ok(CircuitWitnessEntry {
                leaf: CircuitMerkleTreeLeaf(verification_key, target.into()),
                merkle_path: build_merkle_path_from_bundle(&entry.merkle_path)?,
                unique_schnorr_signature: signature,
                lottery_index: entry.lottery_index,
            })
        })
        .collect::<Result<Vec<_>>>()?;

    Ok((
        (
            decode_merkle_root(&bundle.statement.public_input_1_merkle_root)?,
            message_to_sign[1].into(),
        ),
        witness,
    ))
}

fn prove_stm_from_prepared_inputs(
    params: Parameters,
    merkle_tree_depth: u32,
    instance: (MerkleRoot, SignedMessageWithoutPrefix),
    witness: CircuitWitness,
    proving_seed: [u8; 32],
) -> Result<GeneratedStmProof> {
    let circuit = StmCircuit::try_new(&params, merkle_tree_depth)?;

    let min_k = MidnightCircuit::from_relation(&circuit).min_k();
    let srs =
        ParamsKZG::<midnight_curves::Bls12>::unsafe_setup(min_k, ChaCha20Rng::seed_from_u64(42));
    let vk = zk::setup_vk(&srs, &circuit);
    let pk = zk::setup_pk(&circuit, &vk);

    let proof = zk::prove::<StmCircuit, CardanoFriendlyBlake2b>(
        &srs,
        &pk,
        &circuit,
        &instance,
        witness.clone(),
        ChaCha20Rng::from_seed(proving_seed),
    )
    .context("STM proof generation failed")?;

    zk::verify::<StmCircuit, CardanoFriendlyBlake2b>(
        &srs.verifier_params(),
        &vk,
        &instance,
        None,
        &proof,
    )
    .context("STM proof verification failed")?;

    Ok(GeneratedStmProof {
        proof,
        instance,
        witness,
        params,
        merkle_tree_depth,
    })
}

#[derive(Debug, Clone)]
pub struct GeneratedStmProof {
    pub proof: Vec<u8>,
    pub instance: (MerkleRoot, SignedMessageWithoutPrefix),
    pub witness: CircuitWitness,
    pub params: Parameters,
    pub merkle_tree_depth: u32,
}

/// Backward-compatible synthetic STM proof generation path.
///
/// This path fabricates signers and signatures from seeds. It is preserved for
/// tests and deterministic fixtures.
pub fn generate_stm_proof(
    params: Parameters,
    nparties: usize,
    message: [u8; 32],
    seed: [u8; 32],
) -> Result<GeneratedStmProof> {
    generate_stm_proof_fixture(params, nparties, message, seed)
}

/// Synthetic STM proof generation path for tests and deterministic fixtures.
pub fn generate_stm_proof_fixture(
    params: Parameters,
    nparties: usize,
    message: [u8; 32],
    seed: [u8; 32],
) -> Result<GeneratedStmProof> {
    let (signers, closed_reg) = setup_signers(params, nparties, seed)?;
    let signatures = collect_signatures(&signers, &message);
    let (instance, witness) =
        prepare_instance_and_witness(&closed_reg, &signatures, params, &message)?;

    let merkle_tree_depth = closed_reg
        .number_of_registered_parties()
        .next_power_of_two()
        .trailing_zeros();
    prove_stm_from_prepared_inputs(params, merkle_tree_depth, instance, witness, seed)
}

/// Deterministic normalized bundle helper for PoC and integration tooling.
pub fn generate_stm_fixture_bundle(
    params: Parameters,
    nparties: usize,
    message: [u8; 32],
    seed: [u8; 32],
) -> Result<NormalizedStmBundle> {
    let generated = generate_stm_proof_fixture(params, nparties, message, seed)?;
    Ok(bundle_from_generated(&generated, message, nparties))
}

/// STM proof generation path from a normalized bundle.
///
/// This path does not synthesize signers or signatures. It assumes the caller
/// already normalized the circuit-facing statement and witness material into a
/// bundle compatible with the circuit.
pub fn generate_stm_proof_from_bundle(
    bundle: &NormalizedStmBundle,
    proving_seed: [u8; 32],
) -> Result<GeneratedStmProof> {
    let params = bundle.stm_parameters.to_mithril_parameters();
    let merkle_tree_depth = bundle.registration.merkle_tree_depth;
    let (instance, witness) = prepare_instance_and_witness_from_bundle(bundle)?;
    prove_stm_from_prepared_inputs(params, merkle_tree_depth, instance, witness, proving_seed)
}

fn bundle_from_generated(
    generated: &GeneratedStmProof,
    message: [u8; 32],
    nparties: usize,
) -> NormalizedStmBundle {
    let public_input_1_merkle_root = BaseFieldElement::from(generated.instance.0).to_bytes();
    let public_input_2_signed_message = BaseFieldElement::from(generated.instance.1).to_bytes();
    let entries = generated
        .witness
        .iter()
        .map(|entry| {
            let leaf_index = entry
                .merkle_path
                .siblings
                .iter()
                .enumerate()
                .fold(0usize, |acc, (depth, (position, _))| match position {
                    Position::Left => acc | (1usize << depth),
                    Position::Right => acc,
                });
            let siblings = entry
                .merkle_path
                .siblings
                .iter()
                .map(|(_, sibling)| BaseFieldElement::from(*sibling).to_bytes())
                .collect();

            NormalizedStmWitnessEntry {
                signer_index: leaf_index,
                lottery_index: entry.lottery_index,
                verification_key_snark: entry.leaf.verification_key().to_bytes().to_vec(),
                target: BaseFieldElement::from(entry.leaf.lottery_target_value()).to_bytes(),
                merkle_path: NormalizedStmMerklePath {
                    leaf_index,
                    siblings,
                },
                unique_schnorr_signature: entry.unique_schnorr_signature.to_bytes().to_vec(),
            }
        })
        .collect();

    NormalizedStmBundle {
        schema_version: "1.0.0".to_string(),
        bundle_kind: "mithril_stm_bundle".to_string(),
        source_id: "synthetic-test-fixture".to_string(),
        stm_parameters: NormalizedStmParameters::from(generated.params),
        certificates: NormalizedStmCertificates {
            parent: NormalizedStmCertificate {
                hash: [0u8; 32],
                prev_hash: Vec::new(),
                epoch: 0,
                signed_message: [0u8; 32],
            },
            child: NormalizedStmCertificate {
                hash: [1u8; 32],
                prev_hash: vec![0u8; 32],
                epoch: 1,
                signed_message: message,
            },
        },
        statement: NormalizedStmStatement {
            public_input_1_merkle_root,
            public_input_2_signed_message,
        },
        registration: NormalizedStmRegistration {
            parties_count: nparties,
            merkle_tree_depth: generated.merkle_tree_depth,
        },
        witness: NormalizedStmWitness { entries },
    }
}

#[cfg(test)]
mod tests {
    use midnight_proofs::poly::kzg::params::ParamsKZG;
    use midnight_zk_stdlib::{self as zk, MidnightCircuit};
    use rand_chacha::ChaCha20Rng;
    use rand_core::SeedableRng;

    use super::{bundle_from_generated, generate_stm_proof, generate_stm_proof_from_bundle};
    use crate::circuits::mithril_stm::circuit::StmCircuit;
    use crate::circuits::mithril_stm::crypto::BaseFieldElement;
    use crate::plutus_gen::adjusted_types::CardanoFriendlyBlake2b;
    use mithril_stm::Parameters;

    #[test]
    fn proves_and_verifies_stm_end_to_end() {
        let params = Parameters {
            m: 200,
            k: 5,
            phi_f: 0.8,
        };

        let generated = generate_stm_proof(params, 10, [7u8; 32], [0u8; 32]).unwrap();
        assert!(!generated.proof.is_empty());
    }

    #[test]
    fn proof_is_rejected_for_a_different_message() {
        let params = Parameters {
            m: 200,
            k: 5,
            phi_f: 0.8,
        };

        let generated = generate_stm_proof(params, 10, [7u8; 32], [1u8; 32]).unwrap();
        let wrong_instance = (
            generated.instance.0,
            BaseFieldElement::from_raw(&[9u8; 32]).unwrap().into(),
        );

        let circuit = StmCircuit::try_new(&generated.params, generated.merkle_tree_depth).unwrap();
        let min_k = MidnightCircuit::from_relation(&circuit).min_k();
        let srs =
            ParamsKZG::<midnight_curves::Bls12>::unsafe_setup(min_k, ChaCha20Rng::seed_from_u64(42));
        let vk = zk::setup_vk(&srs, &circuit);

        let result = zk::verify::<StmCircuit, CardanoFriendlyBlake2b>(
            &srs.verifier_params(),
            &vk,
            &wrong_instance,
            None,
            &generated.proof,
        );

        assert!(result.is_err(), "verification should fail for the wrong message");
    }

    #[test]
    fn bundle_generation_matches_fixture_generation() {
        let params = Parameters {
            m: 200,
            k: 5,
            phi_f: 0.8,
        };
        let message = [7u8; 32];
        let seed = [3u8; 32];

        let generated = generate_stm_proof(params, 10, message, seed).unwrap();
        let bundle = bundle_from_generated(&generated, message, 10);
        let regenerated = generate_stm_proof_from_bundle(&bundle, seed).unwrap();

        assert_eq!(generated.params, regenerated.params);
        assert_eq!(generated.merkle_tree_depth, regenerated.merkle_tree_depth);
        assert_eq!(generated.instance.0, regenerated.instance.0);
        assert_eq!(generated.instance.1, regenerated.instance.1);
        assert_eq!(generated.witness.len(), regenerated.witness.len());
        assert!(!generated.proof.is_empty());
        assert!(!regenerated.proof.is_empty());
    }

    #[test]
    fn bundle_rejects_mismatched_child_signed_message() {
        let params = Parameters {
            m: 200,
            k: 5,
            phi_f: 0.8,
        };
        let message = [7u8; 32];
        let generated = generate_stm_proof(params, 10, message, [4u8; 32]).unwrap();
        let mut bundle = bundle_from_generated(&generated, message, 10);
        bundle.certificates.child.signed_message = [9u8; 32];

        let error = generate_stm_proof_from_bundle(&bundle, [4u8; 32]).unwrap_err();
        assert!(
            error
                .to_string()
                .contains("statement.public_input_2_signed_message must match child certificate signed_message")
        );
    }
}
