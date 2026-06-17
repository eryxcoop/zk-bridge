use anyhow::{bail, Result};
use jubjub_schnorr_verification_circuit::{
    derive_message_base_from_digest_halves, pack_jubjub_schnorr_public_inputs,
    pack_jubjub_schnorr_public_inputs_vec, unpack_jubjub_schnorr_public_inputs,
    PackedJubjubSchnorrPublicInputs,
};
use serde::Serialize;
use sha2::{Digest, Sha256};

mod arkworks_fixture_export_helper {
    include!("../../zk-circuits-common/arkworks_fixture_export_helper.rs");
}

// Work around local linker environments where `wasmer_vm` references
// `__rust_probestack` but the symbol is not provided at link time.
#[cfg(target_arch = "x86_64")]
#[unsafe(no_mangle)]
pub extern "C" fn __rust_probestack() {}

#[derive(Serialize)]
struct FixtureSummary {
    curve: String,
    protocol: String,
    public_inputs: usize,
    verified: bool,
    packed_public_inputs: PackedJubjubSchnorrPublicInputs,
    digest_hi: String,
    digest_low: String,
    message_base: String,
    verification_key_u: String,
    verification_key_v: String,
    signature_response: String,
    signature_challenge: String,
    jubjub_schnorr_proof: arkworks_fixture_export_helper::ProofHex,
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = arkworks_fixture_export_helper::parse_export_args()?;
    let fixture = arkworks_fixture_export_helper::generate_fixture(
        "jubjub_schnorr_verification_main",
        "jubjub-schnorr-stage1-local-fixture-v1",
        |bytes| Sha256::digest(bytes).into(),
        &args.input_json_path,
    )?;

    let (
        digest_hi,
        digest_low,
        verification_key_u,
        verification_key_v,
        signature_response,
        signature_challenge,
    ) = unpack_jubjub_schnorr_public_inputs(&fixture.public_inputs_json)?;
    let message_base = derive_message_base_from_digest_halves(&digest_hi, &digest_low)?;
    let packed_public_inputs = pack_jubjub_schnorr_public_inputs(
        digest_hi.clone(),
        digest_low.clone(),
        verification_key_u.clone(),
        verification_key_v.clone(),
        signature_response.clone(),
        signature_challenge.clone(),
    );
    let canonical_public_inputs = pack_jubjub_schnorr_public_inputs_vec(
        digest_hi.clone(),
        digest_low.clone(),
        verification_key_u.clone(),
        verification_key_v.clone(),
        signature_response.clone(),
        signature_challenge.clone(),
    );
    if canonical_public_inputs != fixture.public_inputs_json {
        bail!(
            "canonical packed public inputs do not match circuit output: expected {:?}, got {:?}",
            canonical_public_inputs,
            fixture.public_inputs_json
        );
    }

    let summary = FixtureSummary {
        curve: fixture.curve.clone(),
        protocol: fixture.protocol.clone(),
        public_inputs: fixture.public_inputs_json.len(),
        verified: fixture.verified,
        packed_public_inputs,
        digest_hi,
        digest_low,
        message_base,
        verification_key_u,
        verification_key_v,
        signature_response,
        signature_challenge,
        jubjub_schnorr_proof: fixture.proof_hex.clone(),
    };

    arkworks_fixture_export_helper::write_fixture_outputs(
        &fixture,
        &args.out_dir,
        &summary.packed_public_inputs,
        &summary,
        "jubjub_schnorr_verification_vk.ak",
        "jubjub_schnorr_verification_vk",
        args.aiken_vk_output_path.as_deref(),
    )?;
    arkworks_fixture_export_helper::print_fixture_summary(&fixture);

    Ok(())
}
