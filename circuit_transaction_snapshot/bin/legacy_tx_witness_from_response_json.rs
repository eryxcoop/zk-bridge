use anyhow::{Context, Result, bail};
use mithril_circuits_utils::legacy_tx_witness_from_response_json;
use std::env;
use std::fs;

fn main() {
    if let Err(err) = run() {
        eprintln!("error: {err:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let args: Vec<String> = env::args().collect();

    if args.len() != 4 {
        bail!(
            "usage: {} <response_json_file> <tx_hash> <output_file>",
            args[0]
        );
    }

    let response_json_file = &args[1];
    let tx_hash = &args[2];
    let output_file = &args[3];

    let response_json = fs::read_to_string(response_json_file)
        .with_context(|| format!("failed to read JSON file: {response_json_file}"))?;

    let witness = legacy_tx_witness_from_response_json(&response_json, tx_hash)?;
    let witness_json = serde_json::to_string_pretty(&witness)
        .context("failed to serialize witness as JSON")?;

    fs::write(output_file, format!("{witness_json}\n"))
        .with_context(|| format!("failed to write output file: {output_file}"))?;

    println!("Witness saved to {output_file}");
    Ok(())
}
