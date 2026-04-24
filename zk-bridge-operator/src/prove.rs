use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{Context, Result, anyhow, bail};
use mithril_snapshot_circuit::legacy_tx_witness_from_proof_hex;
use serde::Serialize;
use tx_set_update_circuit::{TX_ID_BYTES, single_insert_empty_tree_witness};

use crate::config::{ResolvedCli, TxProveArgs};
use crate::io::{ensure_dir, write_pretty_json};
use crate::mithril_api::MithrilApi;
use crate::targets::{CircuitKind, proof_targets};

#[derive(Debug, Serialize)]
struct ProofManifest {
    aggregator_url: String,
    transaction_hash: String,
    proof_certificate_hash: String,
    latest_block_number: u64,
    verified: bool,
    snapshot_hash: Option<String>,
}

pub async fn prove_transaction(cli: &ResolvedCli, args: &TxProveArgs) -> Result<()> {
    let tx_hash = normalize_tx_hash(&args.transaction_hash)?;
    let output_dir = cli.tx_artifacts_dir.join(&tx_hash);
    if output_dir.exists() && !cli.force {
        bail!(
            "output directory {} already exists; rerun with --force to overwrite",
            output_dir.display()
        );
    }
    ensure_dir(&output_dir)?;

    let api = MithrilApi::new(cli.aggregator_url.clone());
    let features = api.aggregator_features().await?;
    let status = api.aggregator_status().await?;
    let genesis_verification_key = api
        .fetch_text(&cli.genesis_verification_key_url)
        .await
        .context("fetching genesis verification key")?;

    let proof_response = api.proof_for_transaction(&tx_hash).await?;
    let selected_proof = MithrilApi::select_certified_proof(&proof_response, &tx_hash)?;
    let certificate = api
        .certificate_by_hash(&selected_proof.certificate_hash)
        .await?;
    let snapshot = api
        .find_snapshot_by_certificate_hash(&selected_proof.certificate_hash)
        .await?;
    api.verify_transaction_proof(
        &genesis_verification_key,
        &tx_hash,
        &selected_proof.certificate_hash,
    )
    .await?;
    let expected_root = MithrilApi::cardano_transactions_merkle_root(&certificate)?;

    write_pretty_json(&output_dir.join("aggregator_features.json"), &features)?;
    write_pretty_json(&output_dir.join("aggregator_status.json"), &status)?;
    write_pretty_json(&output_dir.join("proof_response.json"), &proof_response)?;
    write_pretty_json(&output_dir.join("certificate.json"), &certificate)?;
    if let Some(snapshot) = &snapshot {
        write_pretty_json(&output_dir.join("snapshot.json"), snapshot)?;
    }

    for target in proof_targets(&cli.repo_root) {
        let target_output_dir = output_dir.join(target.output_dir_name);
        ensure_dir(&target_output_dir)?;
        let input_path = match target.kind {
            CircuitKind::SnapshotMembership => build_snapshot_circuit_input(
                &target_output_dir,
                &tx_hash,
                &selected_proof.proof,
                expected_root,
            )?,
            CircuitKind::TxSetUpdate => build_tx_set_update_input(&target_output_dir, &tx_hash)?,
        };
        run_exporter(
            &target.crate_dir,
            target.exporter_bin,
            &input_path,
            &target_output_dir,
        )?;
    }

    let manifest = ProofManifest {
        aggregator_url: cli.aggregator_url.clone(),
        transaction_hash: tx_hash,
        proof_certificate_hash: selected_proof.certificate_hash,
        latest_block_number: selected_proof.latest_block_number,
        verified: true,
        snapshot_hash: snapshot.map(|snapshot| snapshot.hash),
    };
    write_pretty_json(&output_dir.join("manifest.json"), &manifest)?;

    Ok(())
}

fn build_snapshot_circuit_input(
    output_dir: &Path,
    tx_hash: &str,
    proof_hex: &str,
    expected_root: [u8; 32],
) -> Result<PathBuf> {
    let witness = legacy_tx_witness_from_proof_hex(proof_hex, tx_hash, expected_root)
        .context("normalizing Mithril proof into snapshot witness")?;
    let circom_inputs = witness.to_suggested_circom_inputs()?;
    let input_path = output_dir.join("input.json");
    write_pretty_json(&input_path, &circom_inputs)?;
    Ok(input_path)
}

fn build_tx_set_update_input(output_dir: &Path, tx_hash: &str) -> Result<PathBuf> {
    let tx_id: [u8; TX_ID_BYTES] = hex::decode(tx_hash)?
        .try_into()
        .map_err(|_| anyhow!("transaction hash must decode to 32 bytes"))?;
    let witness = single_insert_empty_tree_witness(tx_id);
    witness.validate()?;
    let input_path = output_dir.join("input.json");
    write_pretty_json(&input_path, &witness.circuit_inputs_for_current_scaffold())?;
    Ok(input_path)
}

fn run_exporter(
    crate_dir: &Path,
    bin_name: &str,
    input_path: &Path,
    output_dir: &Path,
) -> Result<()> {
    let status = Command::new("cargo")
        .args([
            "run",
            "--release",
            "--bin",
            bin_name,
            "--",
            input_path
                .to_str()
                .ok_or_else(|| anyhow!("non-utf8 input path"))?,
            output_dir
                .to_str()
                .ok_or_else(|| anyhow!("non-utf8 output path"))?,
        ])
        .current_dir(crate_dir)
        .status()
        .with_context(|| format!("running {bin_name} in {}", crate_dir.display()))?;
    if !status.success() {
        bail!("{bin_name} failed with status {status}");
    }
    Ok(())
}

fn normalize_tx_hash(tx_hash: &str) -> Result<String> {
    let normalized = tx_hash.trim().trim_start_matches("0x").to_lowercase();
    if normalized.len() != 64 {
        bail!("transaction hash must be exactly 64 hex characters");
    }
    let _ = hex::decode(&normalized).context("transaction hash must be valid hex")?;
    Ok(normalized)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::targets::{CircuitKind, proof_targets};

    #[test]
    fn normalize_tx_hash_accepts_prefixed_mixed_case() {
        let normalized =
            normalize_tx_hash("0xAABBCCDDEEFF00112233445566778899AABBCCDDEEFF00112233445566778899")
                .expect("hash should normalize");
        assert_eq!(
            normalized,
            "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899"
        );
    }

    #[test]
    fn normalize_tx_hash_rejects_invalid_length() {
        assert!(normalize_tx_hash("abcd").is_err());
    }

    #[test]
    fn proof_targets_define_both_circuit_outputs() {
        let repo_root = Path::new("/repo");
        let targets = proof_targets(repo_root);
        assert_eq!(targets.len(), 2);
        assert_eq!(targets[0].kind, CircuitKind::SnapshotMembership);
        assert_eq!(targets[1].kind, CircuitKind::TxSetUpdate);
        assert_eq!(targets[0].output_dir_name, "snapshot_membership");
        assert_eq!(targets[1].output_dir_name, "tx_set_update");
        assert_eq!(
            targets[0].crate_dir,
            repo_root.join("circuit_transaction_snapshot")
        );
        assert_eq!(
            targets[1].crate_dir,
            repo_root.join("circuit_inclusion_exclusion")
        );
    }
}
