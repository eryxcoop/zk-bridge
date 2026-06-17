use std::fs;
use std::path::PathBuf;
use std::str::FromStr;

use anyhow::{Context, Result, bail};
use ark_bls12_381::{Bls12_381, Fr, G1Affine, G2Affine};
use ark_circom::{CircomBuilder, CircomConfig};
use ark_crypto_primitives::snark::SNARK;
use ark_groth16::{Groth16, Proof};
use ark_serialize::CanonicalDeserialize;
use ark_std::rand::{SeedableRng, rngs::StdRng};
use jubjub_schnorr_verification_circuit::derive_message_base_from_digest_halves;
use serde::Deserialize;
use sha2::{Digest, Sha256};

type Curve = Bls12_381;
type Groth = Groth16<Curve>;

const WRAPPER_STEM: &str = "jubjub_schnorr_verification_main";
const SEED_LABEL: &str = "jubjub-schnorr-stage1-local-fixture-v1";

// Work around local linker environments where `wasmer_vm` references
// `__rust_probestack` but the symbol is not provided at link time.
#[cfg(target_arch = "x86_64")]
#[unsafe(no_mangle)]
pub extern "C" fn __rust_probestack() {}

#[derive(Deserialize)]
struct ProofHex {
    #[serde(rename = "piA")]
    pi_a: String,
    #[serde(rename = "piB")]
    pi_b: String,
    #[serde(rename = "piC")]
    pi_c: String,
}

#[derive(Deserialize)]
struct ExportedFixtureSummary {
    curve: String,
    protocol: String,
    public_inputs: usize,
    digest_hi: String,
    digest_low: String,
    message_base: String,
    verification_key_u: String,
    verification_key_v: String,
    signature_response: String,
    signature_challenge: String,
    jubjub_schnorr_proof: ProofHex,
}

#[tokio::main]
async fn main() -> Result<()> {
    let fixture_path = PathBuf::from(
        std::env::args()
            .nth(1)
            .context("usage: cargo run --bin verify_exported_fixture -- <fixture_summary.json>")?,
    );

    let fixture: ExportedFixtureSummary = serde_json::from_slice(
        &fs::read(&fixture_path)
            .with_context(|| format!("could not read {}", fixture_path.display()))?,
    )
    .with_context(|| format!("invalid fixture JSON at {}", fixture_path.display()))?;

    if fixture.curve != "bls12381" {
        bail!("unexpected curve: {}", fixture.curve);
    }
    if fixture.protocol != "groth16" {
        bail!("unexpected protocol: {}", fixture.protocol);
    }
    if fixture.public_inputs != 6 {
        bail!("unexpected public input count: {}", fixture.public_inputs);
    }

    let derived_message_base =
        derive_message_base_from_digest_halves(&fixture.digest_hi, &fixture.digest_low)?;
    if fixture.message_base != derived_message_base {
        bail!(
            "message_base drifted from digest halves: expected {}, got {}",
            derived_message_base,
            fixture.message_base
        );
    }

    let packed_public_inputs =
        jubjub_schnorr_verification_circuit::pack_jubjub_schnorr_public_inputs_vec(
            fixture.digest_hi.clone(),
            fixture.digest_low.clone(),
            fixture.verification_key_u.clone(),
            fixture.verification_key_v.clone(),
            fixture.signature_response.clone(),
            fixture.signature_challenge.clone(),
        );
    let public_inputs = vec![
        parse_fr(&packed_public_inputs[0], "digest_hi")?,
        parse_fr(&packed_public_inputs[1], "digest_low")?,
        parse_fr(&packed_public_inputs[2], "verification_key_u")?,
        parse_fr(&packed_public_inputs[3], "verification_key_v")?,
        parse_fr(&packed_public_inputs[4], "signature_response")?,
        parse_fr(&packed_public_inputs[5], "signature_challenge")?,
    ];

    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let wasm_path = manifest_dir
        .join("circuit_build")
        .join(format!("{WRAPPER_STEM}_js"))
        .join(format!("{WRAPPER_STEM}.wasm"));
    let r1cs_path = manifest_dir
        .join("circuit_build")
        .join(format!("{WRAPPER_STEM}.r1cs"));

    let cfg = CircomConfig::<Fr>::new(&wasm_path, &r1cs_path).map_err(|err| {
        anyhow::anyhow!(
            "could not open wasm/r1cs inputs at {} and {}: {err}",
            wasm_path.display(),
            r1cs_path.display()
        )
    })?;
    let builder = CircomBuilder::new(cfg);
    let empty_circuit = builder.setup();
    let seed: [u8; 32] = Sha256::digest(SEED_LABEL.as_bytes()).into();
    let mut rng = StdRng::from_seed(seed);
    let params = Groth::generate_random_parameters_with_reduction(empty_circuit, &mut rng)
        .context("arkworks deterministic setup failed while reconstructing the Jubjub Groth16 VK")?;
    let processed_vk =
        Groth::process_vk(&params.vk).context("arkworks process_vk failed")?;

    let proof = Proof::<Curve> {
        a: deserialize_compressed::<G1Affine>(&fixture.jubjub_schnorr_proof.pi_a)
            .context("could not deserialize piA")?,
        b: deserialize_compressed::<G2Affine>(&fixture.jubjub_schnorr_proof.pi_b)
            .context("could not deserialize piB")?,
        c: deserialize_compressed::<G1Affine>(&fixture.jubjub_schnorr_proof.pi_c)
            .context("could not deserialize piC")?,
    };

    let verified = Groth::verify_with_processed_vk(&processed_vk, &public_inputs, &proof)
        .context("arkworks verify failed")?;
    if !verified {
        bail!("exported proof did not verify against the deterministic Jubjub verifier key");
    }

    println!("curve={}", fixture.curve);
    println!("protocol={}", fixture.protocol);
    println!("public_inputs={}", fixture.public_inputs);
    println!("verified=true");
    Ok(())
}

fn deserialize_compressed<T: CanonicalDeserialize>(hex: &str) -> Result<T> {
    let bytes = hex::decode(hex).with_context(|| "invalid hex")?;
    let mut slice = bytes.as_slice();
    T::deserialize_compressed(&mut slice).with_context(|| "invalid canonical compressed encoding")
}

fn parse_fr(raw: &str, label: &str) -> Result<Fr> {
    Fr::from_str(raw).map_err(|_| anyhow::anyhow!("could not parse {label} as BLS12-381 scalar field element"))
}
