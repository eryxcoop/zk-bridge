use anyhow::{anyhow, bail, Context, Result};
use plutus_halo2_verifier_gen::plutus_gen::mithril_stm_proof_export::debug_compare_proof_export_split_with_bundle;
use std::env;
use std::path::PathBuf;

fn main() -> Result<()> {
    let mut bundle: Option<PathBuf> = None;
    let mut proof_export: Option<PathBuf> = None;

    let mut args = env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--bundle" => {
                bundle = Some(
                    args.next()
                        .map(PathBuf::from)
                        .ok_or_else(|| anyhow!("Missing value for --bundle"))?,
                );
            }
            "--proof_export" => {
                proof_export = Some(
                    args.next()
                        .map(PathBuf::from)
                        .ok_or_else(|| anyhow!("Missing value for --proof_export"))?,
                );
            }
            "--help" | "-h" => {
                print_help();
                return Ok(());
            }
            _ => bail!("Unknown argument: {arg}"),
        }
    }

    let bundle = bundle.ok_or_else(|| anyhow!("Missing required --bundle"))?;
    let proof_export = proof_export.ok_or_else(|| anyhow!("Missing required --proof_export"))?;

    let report = debug_compare_proof_export_split_with_bundle(&bundle, &proof_export).with_context(|| {
        format!(
            "Failed to compare split accumulator for bundle {} and proof_export {}",
            bundle.display(),
            proof_export.display()
        )
    })?;

    println!("{}", serde_json::to_string_pretty(&report)?);
    Ok(())
}

fn print_help() {
    eprintln!(
        "\
Usage:
  cargo run --bin debug_mithril_stm_split -- --bundle <bundle.json> --proof_export <proof_export.json>"
    );
}
