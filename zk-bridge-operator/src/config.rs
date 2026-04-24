use std::path::PathBuf;

use anyhow::Result;
use clap::{Args, Parser, Subcommand};

pub const DEFAULT_AGGREGATOR_URL: &str =
    "https://aggregator.pre-release-preview.api.mithril.network/aggregator";
pub const DEFAULT_GENESIS_VERIFICATION_KEY_URL: &str = "https://raw.githubusercontent.com/input-output-hk/mithril/main/mithril-infra/configuration/pre-release-preview/genesis.vkey";

#[derive(Debug, Clone, Parser)]
#[command(name = "zk_circuit_operator")]
#[command(about = "Shared zk-circuit operator for Mithril-backed proofs")]
pub struct Cli {
    #[arg(long, default_value = DEFAULT_AGGREGATOR_URL)]
    pub aggregator_url: String,

    #[arg(long, default_value = DEFAULT_GENESIS_VERIFICATION_KEY_URL)]
    pub genesis_verification_key_url: String,

    #[arg(long, default_value = "certificates")]
    pub certificate_dir: PathBuf,

    #[arg(long, default_value = "tx_artifacts")]
    pub tx_artifacts_dir: PathBuf,

    #[arg(long)]
    pub force: bool,

    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Debug, Clone, Subcommand)]
pub enum Commands {
    Relayer {
        #[command(subcommand)]
        command: RelayerCommands,
    },
    Tx {
        #[command(subcommand)]
        command: TxCommands,
    },
}

#[derive(Debug, Clone, Subcommand)]
pub enum RelayerCommands {
    SyncCertificates,
}

#[derive(Debug, Clone, Subcommand)]
pub enum TxCommands {
    Prove(TxProveArgs),
}

#[derive(Debug, Clone, Args)]
pub struct TxProveArgs {
    pub transaction_hash: String,
}

#[derive(Debug, Clone)]
pub struct ResolvedCli {
    pub aggregator_url: String,
    pub genesis_verification_key_url: String,
    pub certificate_dir: PathBuf,
    pub tx_artifacts_dir: PathBuf,
    pub force: bool,
    pub command: Commands,
    pub repo_root: PathBuf,
}

impl Cli {
    pub fn resolve(&self) -> Result<ResolvedCli> {
        let operator_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let repo_root = operator_dir
            .parent()
            .expect("operator crate must live directly under the repo root")
            .to_path_buf();

        Ok(ResolvedCli {
            aggregator_url: self.aggregator_url.clone(),
            genesis_verification_key_url: self.genesis_verification_key_url.clone(),
            certificate_dir: resolve_path(&operator_dir, &self.certificate_dir),
            tx_artifacts_dir: resolve_path(&operator_dir, &self.tx_artifacts_dir),
            force: self.force,
            command: self.command.clone(),
            repo_root,
        })
    }
}

fn resolve_path(base: &std::path::Path, value: &std::path::Path) -> PathBuf {
    if value.is_absolute() {
        value.to_path_buf()
    } else {
        base.join(value)
    }
}
