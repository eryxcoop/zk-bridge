mod certificate_store;
mod config;
mod io;
mod mithril_api;
mod prove;
mod targets;

use anyhow::Result;
use clap::Parser;
use config::{Cli, Commands, RelayerCommands, TxCommands};

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    let resolved = cli.resolve()?;
    run_command(&resolved).await
}

async fn run_command(resolved: &config::ResolvedCli) -> Result<()> {
    match &resolved.command {
        Commands::Relayer { command } => match command {
            RelayerCommands::SyncCertificates => {
                certificate_store::sync_stake_certificates(&resolved).await?
            }
        },
        Commands::Tx { command } => match command {
            TxCommands::Prove(args) => prove::prove_transaction(&resolved, args).await?,
        },
    }

    Ok(())
}
