use std::fs;
use std::path::{Path, PathBuf};
use std::str::FromStr;

use anyhow::{Context, Result, bail};
use ark_bls12_381::{Bls12_381, Fr};
use ark_circom::{CircomBuilder, CircomConfig};
use ark_crypto_primitives::snark::SNARK;
use ark_groth16::Groth16;
use ark_serialize::CanonicalSerialize;
use ark_std::rand::{SeedableRng, rngs::StdRng};
use circom_prover::prover::{
    PublicInputs,
    circom::{Inputs, Proof},
};
use num_bigint::BigInt;
use serde::Serialize;
use serde_json::Value;

pub type Curve = Bls12_381;
type Groth = Groth16<Curve>;

pub struct ExportArgs {
    pub input_json_path: PathBuf,
    pub out_dir: PathBuf,
    pub aiken_vk_output_path: Option<PathBuf>,
}

#[derive(Serialize, Clone)]
pub struct ProofHex {
    #[serde(rename = "piA")]
    pub pi_a: String,
    #[serde(rename = "piB")]
    pub pi_b: String,
    #[serde(rename = "piC")]
    pub pi_c: String,
}

pub struct GeneratedFixture {
    pub proof_json: Proof,
    pub proof_hex: ProofHex,
    pub public_inputs_json: Vec<String>,
    pub curve: String,
    pub protocol: String,
    pub verified: bool,
    pub vk: ark_groth16::VerifyingKey<Curve>,
}

pub fn parse_export_args() -> Result<ExportArgs> {
    let mut args = std::env::args().skip(1);
    let input_json_path = PathBuf::from(args.next().context(
        "usage: cargo run --release --bin arkworks_circom_fixture_export -- <input_json_path> <out_dir> [aiken_vk_output_path]",
    )?);
    let out_dir = PathBuf::from(args.next().context(
        "usage: cargo run --release --bin arkworks_circom_fixture_export -- <input_json_path> <out_dir> [aiken_vk_output_path]",
    )?);
    let aiken_vk_output_path = args.next().map(PathBuf::from);

    if args.next().is_some() {
        bail!(
            "usage: cargo run --release --bin arkworks_circom_fixture_export -- <input_json_path> <out_dir> [aiken_vk_output_path]"
        );
    }

    Ok(ExportArgs {
        input_json_path,
        out_dir,
        aiken_vk_output_path,
    })
}

pub fn generate_fixture(
    wrapper_stem: &str,
    seed_label: &str,
    digest_seed: impl Fn(&[u8]) -> [u8; 32],
    input_json_path: &Path,
) -> Result<GeneratedFixture> {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let wasm_path = manifest_dir
        .join("circuit_build")
        .join(format!("{wrapper_stem}_js"))
        .join(format!("{wrapper_stem}.wasm"));
    let r1cs_path = manifest_dir
        .join("circuit_build")
        .join(format!("{wrapper_stem}.r1cs"));

    let input_json = fs::read_to_string(input_json_path)
        .with_context(|| format!("could not read {}", input_json_path.display()))?;
    let input_value: Value =
        serde_json::from_str(&input_json).context("input JSON must be valid JSON")?;

    let cfg = CircomConfig::<Fr>::new(&wasm_path, &r1cs_path).map_err(|err| {
        anyhow::anyhow!(
            "could not open wasm/r1cs inputs at {} and {}: {err}",
            wasm_path.display(),
            r1cs_path.display()
        )
    })?;
    let mut builder = CircomBuilder::new(cfg);
    push_inputs_from_json(&mut builder, &input_value)?;

    let seed = digest_seed(seed_label.as_bytes());
    let mut rng = StdRng::from_seed(seed);

    let empty_circuit = builder.setup();
    let params = Groth::generate_random_parameters_with_reduction(empty_circuit, &mut rng)
        .with_context(|| {
            format!("arkworks trusted setup failed for {wrapper_stem}.{{wasm,r1cs}}")
        })?;

    let circuit = builder
        .build()
        .map_err(|err| anyhow::anyhow!("arkworks witness generation failed: {err}"))?;
    let public_inputs_fr = circuit
        .get_public_inputs()
        .context("could not read public inputs from built circuit")?;
    let proof = Groth::prove(&params, circuit, &mut rng).context("arkworks prove failed")?;
    let processed_vk = Groth::process_vk(&params.vk).context("arkworks process_vk failed")?;
    let verified = Groth::verify_with_processed_vk(&processed_vk, &public_inputs_fr, &proof)
        .context("arkworks verify failed")?;

    let proof_json: Proof = proof.clone().into();
    let curve = proof_json.curve.clone();
    let protocol = proof_json.protocol.clone();
    let public_inputs_json: Vec<String> =
        PublicInputs(Inputs::from(public_inputs_fr.as_slice()).0).into();
    let proof_hex = ProofHex {
        pi_a: serialize_hex_compressed(&proof.a)?,
        pi_b: serialize_hex_compressed(&proof.b)?,
        pi_c: serialize_hex_compressed(&proof.c)?,
    };

    Ok(GeneratedFixture {
        proof_json,
        proof_hex,
        public_inputs_json,
        curve,
        protocol,
        verified,
        vk: params.vk,
    })
}

pub fn write_fixture_outputs<S: Serialize, P: Serialize>(
    fixture: &GeneratedFixture,
    out_dir: &Path,
    packed_public_inputs: &P,
    summary: &S,
    vk_filename: &str,
    vk_function_name: &str,
    aiken_vk_output_path: Option<&Path>,
) -> Result<()> {
    fs::create_dir_all(out_dir)
        .with_context(|| format!("could not create {}", out_dir.display()))?;
    fs::write(
        out_dir.join("proof.json"),
        serde_json::to_vec_pretty(&fixture.proof_json).context("could not serialize proof.json")?,
    )
    .with_context(|| format!("could not write {}", out_dir.join("proof.json").display()))?;
    fs::write(
        out_dir.join("public.json"),
        serde_json::to_vec_pretty(&fixture.public_inputs_json)
            .context("could not serialize public.json")?,
    )
    .with_context(|| format!("could not write {}", out_dir.join("public.json").display()))?;
    fs::write(
        out_dir.join("packed_public_inputs.json"),
        serde_json::to_vec_pretty(packed_public_inputs)
            .context("could not serialize packed_public_inputs.json")?,
    )
    .with_context(|| {
        format!(
            "could not write {}",
            out_dir.join("packed_public_inputs.json").display()
        )
    })?;
    fs::write(
        out_dir.join("verify.log"),
        format!(
            "curve={}\nprotocol={}\npublic_inputs={}\nverified={}\n",
            fixture.curve,
            fixture.protocol,
            fixture.public_inputs_json.len(),
            fixture.verified,
        ),
    )
    .with_context(|| format!("could not write {}", out_dir.join("verify.log").display()))?;
    fs::write(
        out_dir.join("proof_summary.json"),
        serde_json::to_vec_pretty(summary).context("could not serialize proof_summary.json")?,
    )
    .with_context(|| {
        format!(
            "could not write {}",
            out_dir.join("proof_summary.json").display()
        )
    })?;

    let rendered_vk = render_aiken_vk_module(&fixture.vk, vk_function_name)?;
    fs::write(out_dir.join(vk_filename), &rendered_vk)
        .with_context(|| format!("could not write {}", out_dir.join(vk_filename).display()))?;

    if let Some(path) = aiken_vk_output_path {
        fs::write(path, rendered_vk)
            .with_context(|| format!("could not write {}", path.display()))?;
    }

    Ok(())
}

pub fn print_fixture_summary(fixture: &GeneratedFixture) {
    println!("curve={}", fixture.curve);
    println!("protocol={}", fixture.protocol);
    println!("public_inputs={}", fixture.public_inputs_json.len());
    println!("verified={}", fixture.verified);
}

fn push_inputs_from_json(builder: &mut CircomBuilder<Fr>, value: &Value) -> Result<()> {
    let object = value
        .as_object()
        .context("top-level input JSON must be an object")?;

    for (name, value) in object {
        push_input_value(builder, name, value)?;
    }

    Ok(())
}

fn push_input_value(builder: &mut CircomBuilder<Fr>, name: &str, value: &Value) -> Result<()> {
    match value {
        Value::Array(items) => {
            for item in items {
                push_input_value(builder, name, item)?;
            }
            Ok(())
        }
        Value::Number(number) => {
            let bigint = BigInt::from_str(&number.to_string())
                .with_context(|| format!("could not parse numeric input for {name}"))?;
            builder.push_input(name, bigint);
            Ok(())
        }
        Value::String(text) => {
            let bigint = BigInt::from_str(text)
                .with_context(|| format!("could not parse string input for {name}: {text}"))?;
            builder.push_input(name, bigint);
            Ok(())
        }
        Value::Bool(flag) => {
            builder.push_input(name, if *flag { 1 } else { 0 });
            Ok(())
        }
        _ => bail!("unsupported JSON input shape for {name}: {value}"),
    }
}

fn serialize_hex_compressed<T: CanonicalSerialize>(value: &T) -> Result<String> {
    let mut bytes = Vec::new();
    value
        .serialize_compressed(&mut bytes)
        .context("could not serialize point")?;
    Ok(hex::encode(bytes))
}

fn render_aiken_vk_module(
    vk: &ark_groth16::VerifyingKey<Curve>,
    fn_name: &str,
) -> Result<String> {
    let mut lines = Vec::new();
    lines.push("use ak_381/groth16.{SnarkVerificationKey}".to_string());
    lines.push(String::new());
    lines.push(
        "/// Deterministic local-fixture VK generated by `arkworks_circom_fixture_export`."
            .to_string(),
    );
    lines.push(format!("pub fn {fn_name}() -> SnarkVerificationKey {{"));
    lines.push("  SnarkVerificationKey {".to_string());
    lines.push(format!(
        "    nPublic: {},",
        vk.gamma_abc_g1.len().saturating_sub(1)
    ));
    lines.push(format!(
        "    vkAlpha: #\"{}\",",
        serialize_hex_compressed(&vk.alpha_g1)?
    ));
    lines.push(format!(
        "    vkBeta: #\"{}\",",
        serialize_hex_compressed(&vk.beta_g2)?
    ));
    lines.push(format!(
        "    vkGamma: #\"{}\",",
        serialize_hex_compressed(&vk.gamma_g2)?
    ));
    lines.push(format!(
        "    vkDelta: #\"{}\",",
        serialize_hex_compressed(&vk.delta_g2)?
    ));
    lines.push("    vkAlphaBeta: [],".to_string());
    lines.push("    vkIC: [".to_string());

    for point in &vk.gamma_abc_g1 {
        lines.push(format!("      #\"{}\",", serialize_hex_compressed(point)?));
    }

    lines.push("    ],".to_string());
    lines.push("  }".to_string());
    lines.push("}".to_string());

    Ok(lines.join("\n"))
}
