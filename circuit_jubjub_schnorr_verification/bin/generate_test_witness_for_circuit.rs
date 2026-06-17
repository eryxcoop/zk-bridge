use anyhow::{anyhow, bail, Context, Result};
use jubjub_schnorr_verification_circuit::{load_example_valid_witness, JubjubSchnorrCircuitInputs};
use std::{env, fs, path::PathBuf};

fn main() -> Result<()> {
    let config = FixtureConfig::from_args()?;
    let witness = match config.input_json_path {
        Some(path) => load_witness_from_path(&path)?,
        None => load_example_valid_witness()?,
    };
    witness.validate()?;
    println!("{}", serde_json::to_string_pretty(&witness)?);
    Ok(())
}

#[derive(Default)]
struct FixtureConfig {
    input_json_path: Option<PathBuf>,
}

impl FixtureConfig {
    fn from_args() -> Result<Self> {
        let mut config = Self::default();
        let mut args = env::args().skip(1);

        while let Some(arg) = args.next() {
            match arg.as_str() {
                "--input-json" => {
                    config.input_json_path = Some(PathBuf::from(required_value(&mut args, &arg)?));
                }
                "-h" | "--help" => {
                    print_usage();
                    std::process::exit(0);
                }
                _ => bail!("unknown argument: {arg}"),
            }
        }

        Ok(config)
    }
}

fn load_witness_from_path(path: &PathBuf) -> Result<JubjubSchnorrCircuitInputs> {
    let json = fs::read_to_string(path)
        .with_context(|| format!("could not read witness JSON from {}", path.display()))?;
    let witness: JubjubSchnorrCircuitInputs = serde_json::from_str(&json)
        .with_context(|| format!("invalid witness JSON in {}", path.display()))?;
    Ok(witness)
}

fn print_usage() {
    eprintln!(
        "usage: generate_test_witness_for_circuit [--input-json <path>]\n\
         defaults to the embedded strict valid witness from examples/valid_algebraic_statement.json"
    );
}

fn required_value(args: &mut impl Iterator<Item = String>, flag: &str) -> Result<String> {
    args.next()
        .ok_or_else(|| anyhow!("missing value for {flag}"))
}
