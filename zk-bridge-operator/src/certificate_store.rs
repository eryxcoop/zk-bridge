use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

use anyhow::{Result, ensure};
use serde::{Deserialize, Serialize};

use crate::config::ResolvedCli;
use crate::io::{ensure_dir, write_pretty_json};
use crate::mithril_api::{CertificateMessage, MithrilApi};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CertificateSyncIndex {
    pub aggregator_url: String,
    pub genesis_hash: String,
    pub latest_recent_hashes: Vec<String>,
    pub stored_hashes: Vec<String>,
}

pub async fn sync_stake_certificates(cli: &ResolvedCli) -> Result<()> {
    ensure_dir(&cli.certificate_dir)?;

    let api = MithrilApi::new(cli.aggregator_url.clone());
    let features = api.aggregator_features().await?;
    let status = api.aggregator_status().await?;
    ensure_cardano_stake_distribution_supported(&features.capabilities.signed_entity_types)?;

    let genesis = api.genesis_certificate().await?;
    let recent = api.recent_certificates().await?;
    let synced = collect_stake_certificate_chain(&api, &genesis, &recent).await?;

    for certificate in synced.values() {
        write_certificate(&cli.certificate_dir, certificate, cli.force)?;
    }

    let index = CertificateSyncIndex {
        aggregator_url: cli.aggregator_url.clone(),
        genesis_hash: genesis.hash,
        latest_recent_hashes: recent.iter().map(|item| item.hash.clone()).collect(),
        stored_hashes: synced.keys().cloned().collect(),
    };
    write_pretty_json(&cli.certificate_dir.join("index.json"), &index)?;
    write_pretty_json(&cli.certificate_dir.join("aggregator_features.json"), &features)?;
    write_pretty_json(&cli.certificate_dir.join("aggregator_status.json"), &status)?;

    Ok(())
}

async fn collect_stake_certificate_chain(
    api: &MithrilApi,
    genesis: &CertificateMessage,
    recent: &[CertificateMessage],
) -> Result<BTreeMap<String, CertificateMessage>> {
    let mut collected = BTreeMap::new();
    let mut walked = BTreeSet::new();

    if MithrilApi::is_stake_distribution_certificate(genesis) {
        collected.insert(genesis.hash.clone(), genesis.clone());
    }

    for recent_certificate in recent {
        if !MithrilApi::is_stake_distribution_certificate(recent_certificate) {
            continue;
        }

        let mut next_hash = Some(recent_certificate.hash.clone());
        while let Some(hash) = next_hash.take() {
            if !walked.insert(hash.clone()) {
                break;
            }

            let certificate = api.certificate_by_hash(&hash).await?;
            if MithrilApi::is_stake_distribution_certificate(&certificate) {
                collected.insert(certificate.hash.clone(), certificate.clone());
            }

            if certificate.previous_hash.is_empty() {
                break;
            }
            next_hash = Some(certificate.previous_hash.clone());
        }
    }

    Ok(collected)
}

fn ensure_cardano_stake_distribution_supported(signed_entity_types: &[String]) -> Result<()> {
    let supported = signed_entity_types
        .iter()
        .any(|entry| entry.contains("StakeDistribution"));
    ensure!(
        supported,
        "aggregator capabilities do not advertise any stake distribution signed entity"
    );
    Ok(())
}

fn write_certificate(dir: &Path, certificate: &CertificateMessage, force: bool) -> Result<()> {
    let path = dir.join(format!("{}.json", certificate.hash));
    if path.exists() && !force {
        return Ok(());
    }
    write_pretty_json(&path, certificate)
}
