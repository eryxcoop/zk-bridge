use anyhow::{Result, anyhow};
use blake2::{Blake2s256, Digest};
use mithril_circuits_utils::{
    LEGACY_TX_BOTTOM_KIND_HASH, LEGACY_TX_BOTTOM_KIND_RAW, LegacyTxCircuitWitness,
    LegacyTypedPathStepWitness,
};
use std::env;

fn main() -> Result<()> {
    let witness = synthetic_final_fixture_witness(&FixtureConfig::from_args()?)?;
    println!("{}", serde_json::to_string_pretty(&witness.to_suggested_circom_inputs()?)?);
    Ok(())
}

struct FixtureConfig {
    tx_hash_hex: String,
}

impl FixtureConfig {
    fn from_args() -> Result<Self> {
        let mut config = Self::default();
        let mut args = env::args().skip(1);

        while let Some(arg) = args.next() {
            match arg.as_str() {
                "--tx-hash-hex" => config.tx_hash_hex = required_value(&mut args, &arg)?,
                "-h" | "--help" => {
                    print_usage();
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
            tx_hash_hex: "aba2057996571cb3c6bbdbd6c7afd3eeff12edfd4b393924943b8d139b068412"
                .to_string(),
        }
    }
}

fn print_usage() {
    eprintln!("usage: synthetic_final_fixture_input [--tx-hash-hex <64-hex>]");
}

fn required_value(args: &mut impl Iterator<Item = String>, flag: &str) -> Result<String> {
    args.next()
        .ok_or_else(|| anyhow::anyhow!("missing value for {flag}"))
}

fn synthetic_final_fixture_witness(config: &FixtureConfig) -> Result<LegacyTxCircuitWitness> {
    let tx_hash_hex = config.tx_hash_hex.trim_start_matches("0x");
    let cardano_tx_hash: [u8; 32] = hex::decode(tx_hash_hex)?
        .try_into()
        .map_err(|_| anyhow!("tx hash must be exactly 32 bytes"))?;
    let locking_tx_leaf_ascii = hex::encode(cardano_tx_hash).into_bytes();

    let sub_raw_sibling =
        b"1111111111111111111111111111111111111111111111111111111111111111".to_vec();
    let sub_root = blake2s256(&locking_tx_leaf_ascii, &sub_raw_sibling);

    let range_ascii = b"4000000-4000015".to_vec();
    let mut master_leaf_preimage = range_ascii.clone();
    master_leaf_preimage.extend_from_slice(&sub_root);
    let master_leaf = blake2s256_many(&master_leaf_preimage);

    let master_hash_sibling =
        hex::decode("4242424242424242424242424242424242424242424242424242424242424242")?;
    let master_root = blake2s256(&master_leaf, &master_hash_sibling);

    Ok(LegacyTxCircuitWitness {
        sub_prefix_steps: vec![LegacyTypedPathStepWitness {
            kind: LEGACY_TX_BOTTOM_KIND_RAW,
            raw_sibling: sub_raw_sibling.clone(),
            hash_sibling: [0u8; 32],
            sibling_on_left: false,
        }],
        sub_upper_siblings: Vec::new(),
        sub_upper_sibling_on_left: Vec::new(),
        range_ascii: range_ascii.clone(),
        master_prefix_steps: vec![LegacyTypedPathStepWitness {
            kind: LEGACY_TX_BOTTOM_KIND_HASH,
            raw_sibling: vec![0u8; 64],
            hash_sibling: to_fixed_32(&master_hash_sibling),
            sibling_on_left: false,
        }],
        master_upper_siblings: Vec::new(),
        master_upper_sibling_on_left: Vec::new(),
        expected_root: to_fixed_32(&master_root),
        cardano_tx_hash,
        sub_root: to_fixed_32(&sub_root),
        master_root: to_fixed_32(&master_root),
    })
}

fn blake2s256(left: &[u8], right: &[u8]) -> Vec<u8> {
    let mut hasher = Blake2s256::new();
    hasher.update(left);
    hasher.update(right);
    hasher.finalize().to_vec()
}

fn blake2s256_many(bytes: &[u8]) -> Vec<u8> {
    let mut hasher = Blake2s256::new();
    hasher.update(bytes);
    hasher.finalize().to_vec()
}

fn to_fixed_32(bytes: &[u8]) -> [u8; 32] {
    let mut out = [0u8; 32];
    out.copy_from_slice(bytes);
    out
}
