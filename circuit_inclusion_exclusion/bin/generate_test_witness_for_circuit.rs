use anyhow::Result;
use std::env;
use tx_set_update_circuit::{single_insert_empty_tree_witness, TX_ID_BYTES};

fn main() -> Result<()> {
    let tx_id: [u8; TX_ID_BYTES] =
        hex::decode(FixtureConfig::from_args()?.tx_id_hex.trim_start_matches("0x"))?
            .try_into()
            .expect("fixture tx_id must be 32 bytes");
    let witness = single_insert_empty_tree_witness(tx_id);
    witness.validate()?;

    println!(
        "{}",
        serde_json::to_string_pretty(&witness.circuit_inputs_for_current_scaffold())?
    );

    Ok(())
}

struct FixtureConfig {
    tx_id_hex: String,
}

impl FixtureConfig {
    fn from_args() -> Result<Self> {
        let mut config = Self::default();
        let mut args = env::args().skip(1);

        while let Some(arg) = args.next() {
            match arg.as_str() {
                "--tx-id-hex" => {
                    config.tx_id_hex = args
                        .next()
                        .ok_or_else(|| anyhow::anyhow!("missing value for --tx-id-hex"))?;
                }
                "-h" | "--help" => {
                    eprintln!("usage: synthetic_final_fixture_input [--tx-id-hex <hex>]");
                    std::process::exit(0);
                }
                _ => anyhow::bail!("unknown argument: {arg}"),
            }
        }

        Ok(config)
    }
}

impl Default for FixtureConfig {
    fn default() -> Self {
        Self {
            tx_id_hex: "aba2057996571cb3c6bbdbd6c7afd3eeff12edfd4b393924943b8d139b068412"
                .to_string(),
        }
    }
}
