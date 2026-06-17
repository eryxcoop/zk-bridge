use std::collections::BTreeMap;

use anyhow::{anyhow, bail, ensure, Context, Result};
use mithril_client::{
    AggregatorDiscoveryType, ClientBuilder, GenesisVerificationKey, MessageBuilder,
};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AggregatorFeatures {
    pub open_api_version: String,
    pub documentation_url: String,
    pub capabilities: AggregatorCapabilities,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AggregatorCapabilities {
    pub signed_entity_types: Vec<String>,
    pub aggregate_signature_type: String,
    pub cardano_transactions_prover: CardanoTransactionsProverCapabilities,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CardanoTransactionsProverCapabilities {
    pub max_hashes_allowed_by_request: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AggregatorStatus {
    pub epoch: u64,
    pub cardano_era: String,
    pub cardano_network: String,
    pub mithril_era: String,
    pub cardano_node_version: String,
    pub aggregator_node_version: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProtocolMessage {
    pub message_parts: BTreeMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CertificateMessage {
    pub hash: String,
    pub previous_hash: String,
    pub epoch: u64,
    pub signed_entity_type: BTreeMap<String, Value>,
    pub metadata: Value,
    pub protocol_message: ProtocolMessage,
    pub signed_message: String,
    pub aggregate_verification_key: String,
    #[serde(default)]
    pub multi_signature: Option<String>,
    #[serde(default)]
    pub genesis_signature: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CardanoTransactionSnapshotListItem {
    pub merkle_root: String,
    pub epoch: u64,
    pub block_number: u64,
    pub hash: String,
    pub certificate_hash: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CardanoStakeDistributionListItem {
    pub epoch: u64,
    pub hash: String,
    pub certificate_hash: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CardanoTransactionSnapshotMessage {
    pub merkle_root: String,
    pub epoch: u64,
    pub block_number: u64,
    pub hash: String,
    pub certificate_hash: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CardanoTransactionProofMessage {
    pub certificate_hash: String,
    pub certified_transactions: Vec<CertifiedTransactionsGroup>,
    pub non_certified_transactions: Vec<String>,
    pub latest_block_number: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CertifiedTransactionsGroup {
    pub transactions_hashes: Vec<String>,
    pub proof: String,
}

#[derive(Debug, Clone)]
pub struct SelectedTransactionProof {
    pub certificate_hash: String,
    pub proof: String,
    pub latest_block_number: u64,
}

#[derive(Debug, Clone)]
pub struct MithrilApi {
    aggregator_url: String,
    http: Client,
}

impl MithrilApi {
    pub fn new(aggregator_url: impl Into<String>) -> Self {
        Self {
            aggregator_url: aggregator_url.into(),
            http: Client::new(),
        }
    }

    pub async fn fetch_text(&self, url: &str) -> Result<String> {
        let response = self
            .http
            .get(url)
            .send()
            .await
            .with_context(|| format!("request failed for {url}"))?;
        let response = response
            .error_for_status()
            .with_context(|| format!("request returned error status for {url}"))?;
        response
            .text()
            .await
            .with_context(|| format!("reading text response from {url}"))
    }

    pub async fn aggregator_features(&self) -> Result<AggregatorFeatures> {
        self.get_json("/")
            .await
            .context("fetching aggregator features")
    }

    pub async fn aggregator_status(&self) -> Result<AggregatorStatus> {
        self.get_json("/status")
            .await
            .context("fetching aggregator status")
    }

    pub async fn genesis_certificate(&self) -> Result<CertificateMessage> {
        self.get_json("/certificate/genesis")
            .await
            .context("fetching genesis certificate")
    }

    pub async fn recent_certificates(&self) -> Result<Vec<CertificateMessage>> {
        self.get_json("/certificates")
            .await
            .context("fetching recent certificates")
    }

    pub async fn certificate_by_hash(&self, hash: &str) -> Result<CertificateMessage> {
        self.get_json(&format!("/certificate/{hash}"))
            .await
            .with_context(|| format!("fetching certificate {hash}"))
    }

    pub async fn cardano_transaction_snapshots(
        &self,
    ) -> Result<Vec<CardanoTransactionSnapshotListItem>> {
        self.get_json("/artifact/cardano-transactions")
            .await
            .context("fetching cardano transaction snapshots")
    }

    pub async fn cardano_stake_distributions(
        &self,
    ) -> Result<Vec<CardanoStakeDistributionListItem>> {
        self.get_json("/artifact/cardano-stake-distributions")
            .await
            .context("fetching cardano stake distributions")
    }

    pub async fn cardano_transaction_snapshot(
        &self,
        hash: &str,
    ) -> Result<CardanoTransactionSnapshotMessage> {
        self.get_json(&format!("/artifact/cardano-transaction/{hash}"))
            .await
            .with_context(|| format!("fetching tx snapshot {hash}"))
    }

    pub async fn proof_for_transaction(
        &self,
        tx_hash: &str,
    ) -> Result<CardanoTransactionProofMessage> {
        let response = self
            .http
            .get(format!("{}/proof/cardano-transaction", self.aggregator_url))
            .query(&[("transaction_hashes", tx_hash)])
            .send()
            .await
            .with_context(|| format!("requesting transaction proof for {tx_hash}"))?;
        let response = response
            .error_for_status()
            .with_context(|| format!("transaction proof request failed for {tx_hash}"))?;
        response
            .json::<CardanoTransactionProofMessage>()
            .await
            .with_context(|| format!("decoding transaction proof response for {tx_hash}"))
    }

    pub fn select_certified_proof(
        proof: &CardanoTransactionProofMessage,
        tx_hash: &str,
    ) -> Result<SelectedTransactionProof> {
        let normalized_tx_hash = tx_hash.to_lowercase();
        if proof
            .non_certified_transactions
            .iter()
            .any(|item| item.eq_ignore_ascii_case(&normalized_tx_hash))
        {
            bail!("transaction {tx_hash} is not certified yet by Mithril");
        }

        let group = proof
            .certified_transactions
            .iter()
            .find(|group| {
                group
                    .transactions_hashes
                    .iter()
                    .any(|item| item.eq_ignore_ascii_case(&normalized_tx_hash))
            })
            .ok_or_else(|| anyhow!("no certified proof found for transaction {tx_hash}"))?;

        Ok(SelectedTransactionProof {
            certificate_hash: proof.certificate_hash.clone(),
            proof: group.proof.clone(),
            latest_block_number: proof.latest_block_number,
        })
    }

    pub async fn find_snapshot_by_certificate_hash(
        &self,
        certificate_hash: &str,
    ) -> Result<Option<CardanoTransactionSnapshotMessage>> {
        let item = self
            .cardano_transaction_snapshots()
            .await?
            .into_iter()
            .find(|snapshot| snapshot.certificate_hash == certificate_hash);
        match item {
            Some(item) => self
                .cardano_transaction_snapshot(&item.hash)
                .await
                .map(Some),
            None => Ok(None),
        }
    }

    pub fn cardano_transactions_merkle_root(certificate: &CertificateMessage) -> Result<[u8; 32]> {
        let root = certificate
            .protocol_message
            .message_parts
            .get("cardano_transactions_merkle_root")
            .ok_or_else(|| {
                anyhow!("certificate does not expose cardano_transactions_merkle_root")
            })?;
        let bytes = hex::decode(root)
            .with_context(|| "cardano_transactions_merkle_root is not valid hex")?;
        ensure!(bytes.len() == 32, "expected 32-byte cardano tx merkle root");
        let mut out = [0u8; 32];
        out.copy_from_slice(&bytes);
        Ok(out)
    }

    pub fn is_stake_distribution_certificate(certificate: &CertificateMessage) -> bool {
        certificate
            .signed_entity_type
            .keys()
            .any(|key| key.contains("StakeDistribution"))
    }

    pub async fn verify_transaction_proof(
        &self,
        genesis_verification_key: &str,
        tx_hash: &str,
        expected_certificate_hash: &str,
    ) -> Result<()> {
        let client = ClientBuilder::new(AggregatorDiscoveryType::Url(self.aggregator_url.clone()))
            .set_genesis_verification_key(GenesisVerificationKey::JsonHex(
                genesis_verification_key.to_string(),
            ))
            .build()
            .context("building mithril client")?;

        let cardano_transaction_proof =
            client
                .cardano_transaction()
                .get_proofs(&[tx_hash])
                .await
                .with_context(|| format!("requesting verifiable proof for {tx_hash}"))?;
        let verified_transactions = cardano_transaction_proof
            .verify()
            .context("verifying Mithril transaction proof")?;
        let certificate = client
            .certificate()
            .verify_chain(&cardano_transaction_proof.certificate_hash)
            .await
            .context("verifying Mithril certificate chain")?;
        ensure!(
            cardano_transaction_proof
                .certificate_hash
                .eq_ignore_ascii_case(expected_certificate_hash),
            "verified proof certificate hash {} does not match expected certificate hash {}",
            cardano_transaction_proof.certificate_hash,
            expected_certificate_hash
        );

        let message = MessageBuilder::new()
            .compute_cardano_transactions_proofs_message(&certificate, &verified_transactions);
        ensure!(
            certificate.match_message(&message),
            "verified proof message does not match verified certificate"
        );

        Ok(())
    }

    async fn get_json<T: for<'de> Deserialize<'de>>(&self, path: &str) -> Result<T> {
        let url = format!("{}{}", self.aggregator_url, path);
        let response = self
            .http
            .get(&url)
            .send()
            .await
            .with_context(|| format!("request failed for {url}"))?;
        let response = response
            .error_for_status()
            .with_context(|| format!("request returned error status for {url}"))?;
        response
            .json::<T>()
            .await
            .with_context(|| format!("decoding JSON response from {url}"))
    }
}
