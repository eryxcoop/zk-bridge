use anyhow::{Context, Result, anyhow, bail};
use plutus_halo2_verifier_gen::plutus_gen::{
    export_mithril_stm_proof_export, validate_compatible_bundle_file,
};
use std::env;
use std::path::PathBuf;

fn main() -> Result<()> {
    env_logger::init();

    let mut args = env::args().skip(1);
    let mut input = None::<PathBuf>;
    let mut output = None::<PathBuf>;
    let mut check = None::<PathBuf>;
    let mut proving_seed = [7u8; 32];

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--input" => {
                let value = args
                    .next()
                    .ok_or_else(|| anyhow!("Missing value for --input"))?;
                input = Some(PathBuf::from(value));
            }
            "--output" => {
                let value = args
                    .next()
                    .ok_or_else(|| anyhow!("Missing value for --output"))?;
                output = Some(PathBuf::from(value));
            }
            "--check" => {
                let value = args
                    .next()
                    .ok_or_else(|| anyhow!("Missing value for --check"))?;
                check = Some(PathBuf::from(value));
            }
            "--proving-seed" => {
                let value = args
                    .next()
                    .ok_or_else(|| anyhow!("Missing value for --proving-seed"))?;
                proving_seed = parse_seed(&value)?;
            }
            "--help" | "-h" => {
                print_usage();
                return Ok(());
            }
            unknown => bail!("Unknown argument: {unknown}"),
        }
    }

    if let Some(path) = check {
        if input.is_some() || output.is_some() {
            bail!("--check cannot be combined with --input/--output");
        }
        validate_compatible_bundle_file(&path).with_context(|| {
            format!("Compatible bundle validation failed for {}", path.display())
        })?;
        println!("compatible_bundle_ok path={}", path.display());
        return Ok(());
    }

    let input = input.ok_or_else(|| anyhow!("Missing required --input"))?;
    let output = output.ok_or_else(|| anyhow!("Missing required --output"))?;
    let proof_export = export_mithril_stm_proof_export(&input, &output, proving_seed).with_context(|| {
        format!(
            "Failed to export Mithril STM proof_export from {} to {}",
            input.display(),
            output.display()
        )
    })?;

    println!(
        "proof_export_written output={} source_id={} statement_hash={}",
        output.display(),
        proof_export.source_bundle.source_id,
        proof_export.statement.statement_hash
    );
    Ok(())
}

fn parse_seed(value: &str) -> Result<[u8; 32]> {
    let normalized = value.strip_prefix("0x").unwrap_or(value);
    if normalized.len() != 64 {
        bail!("--proving-seed must be exactly 32 bytes encoded as 64 hex chars");
    }
    let bytes = hex::decode(normalized).context("Invalid hex in --proving-seed")?;
    bytes
        .try_into()
        .map_err(|_| anyhow!("--proving-seed must decode to 32 bytes"))
}

fn print_usage() {
    eprintln!(
        "Usage:
  cargo run --bin export_mithril_stm_proof_export -- --input <bundle.json> --output <proof_export.json> [--proving-seed <32-byte-hex>]
  cargo run --bin export_mithril_stm_proof_export -- --check <bridge-compatible-bundle.json>"
    );
}
