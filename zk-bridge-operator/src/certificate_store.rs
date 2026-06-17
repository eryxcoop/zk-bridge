use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

use anyhow::{ensure, Result};
use serde::{Deserialize, Serialize};

use crate::config::ResolvedCli;
use crate::io::{ensure_dir, write_pretty_json};
use crate::mithril_api::{CardanoStakeDistributionListItem, CertificateMessage, MithrilApi};

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
    let stake_distributions = api.cardano_stake_distributions().await?;
    let synced =
        collect_stake_certificate_chain(&api, &genesis, &recent, &stake_distributions).await?;

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
    write_pretty_json(
        &cli.certificate_dir.join("aggregator_features.json"),
        &features,
    )?;
    write_pretty_json(&cli.certificate_dir.join("aggregator_status.json"), &status)?;

    Ok(())
}

async fn collect_stake_certificate_chain(
    api: &MithrilApi,
    genesis: &CertificateMessage,
    recent: &[CertificateMessage],
    stake_distributions: &[CardanoStakeDistributionListItem],
) -> Result<BTreeMap<String, CertificateMessage>> {
    let mut collected = BTreeMap::new();
    let mut walked = BTreeSet::new();

    if MithrilApi::is_stake_distribution_certificate(genesis) {
        collected.insert(genesis.hash.clone(), genesis.clone());
    }

    for seed_hash in stake_certificate_seed_hashes(recent, stake_distributions) {
        let mut next_hash = Some(seed_hash);
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

fn stake_certificate_seed_hashes(
    recent: &[CertificateMessage],
    stake_distributions: &[CardanoStakeDistributionListItem],
) -> BTreeSet<String> {
    let mut seed_hashes = BTreeSet::new();

    for certificate in recent {
        if MithrilApi::is_stake_distribution_certificate(certificate) {
            seed_hashes.insert(certificate.hash.clone());
        }
    }

    for distribution in stake_distributions {
        seed_hashes.insert(distribution.certificate_hash.clone());
    }

    seed_hashes
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

#[cfg(test)]
mod tests {
    use super::stake_certificate_seed_hashes;
    use crate::mithril_api::{
        CardanoStakeDistributionListItem, CertificateMessage, ProtocolMessage,
    };
    use serde_json::json;
    use std::collections::BTreeMap;

    #[test]
    fn seed_hashes_include_stake_distribution_artifact_certificates() {
        let recent = vec![certificate(
            "tx-cert",
            "CardanoTransactions",
            json!([1323, 4364579]),
        )];
        let distributions = vec![CardanoStakeDistributionListItem {
            epoch: 1322,
            hash: "stake-artifact".into(),
            certificate_hash: "stake-cert".into(),
            created_at: "2026-06-09T00:06:35.627155419Z".into(),
        }];

        let seed_hashes = stake_certificate_seed_hashes(&recent, &distributions);

        assert!(seed_hashes.contains("stake-cert"));
        assert!(!seed_hashes.contains("tx-cert"));
    }

    #[test]
    fn seed_hashes_keep_recent_stake_distribution_certificates() {
        let recent = vec![certificate(
            "stake-cert",
            "MithrilStakeDistribution",
            json!(1323),
        )];

        let seed_hashes = stake_certificate_seed_hashes(&recent, &[]);

        assert!(seed_hashes.contains("stake-cert"));
    }

    fn certificate(hash: &str, kind: &str, payload: serde_json::Value) -> CertificateMessage {
        let mut signed_entity_type = BTreeMap::new();
        signed_entity_type.insert(kind.to_string(), payload);

        CertificateMessage {
            hash: hash.to_string(),
            previous_hash: String::new(),
            epoch: 0,
            signed_entity_type,
            metadata: json!({}),
            protocol_message: ProtocolMessage {
                message_parts: BTreeMap::new(),
            },
            signed_message: String::new(),
            aggregate_verification_key: String::new(),
            multi_signature: None,
            genesis_signature: None,
        }
    }
}
