use anyhow::{Result, bail};
use sha2::{Digest, Sha256};
use serde::Serialize;
use tx_set_update_circuit::{
    fr_to_hex,
    pack_tx_set_update_public_inputs, pack_tx_set_update_public_inputs_vec,
    unpack_tx_set_update_public_inputs, PackedTxSetUpdatePublicInputs,
};

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
    packed_public_inputs: PackedTxSetUpdatePublicInputs,
    tx_id_hex: String,
    mt_root_in_hex: String,
    mt_root_out_hex: String,
    tx_set_update_proof: arkworks_fixture_export_helper::ProofHex,
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = arkworks_fixture_export_helper::parse_export_args()?;
    let fixture = arkworks_fixture_export_helper::generate_fixture(
        "tx_set_update_main",
        "tx-set-update-local-fixture-v1",
        |bytes| Sha256::digest(bytes).into(),
        &args.input_json_path,
    )?;

    let (tx_id, mt_root_in, mt_root_out) =
        unpack_tx_set_update_public_inputs(&fixture.public_inputs_json)?;
    let packed_public_inputs = pack_tx_set_update_public_inputs(&tx_id, mt_root_in, mt_root_out);
    let canonical_public_inputs =
        pack_tx_set_update_public_inputs_vec(&tx_id, mt_root_in, mt_root_out);
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
        tx_id_hex: hex::encode(tx_id),
        mt_root_in_hex: fr_to_hex(mt_root_in),
        mt_root_out_hex: fr_to_hex(mt_root_out),
        tx_set_update_proof: fixture.proof_hex.clone(),
    };

    arkworks_fixture_export_helper::write_fixture_outputs(
        &fixture,
        &args.out_dir,
        &summary.packed_public_inputs,
        &summary,
        "tx_set_update_vk.ak",
        "tx_set_update_vk",
        args.aiken_vk_output_path.as_deref(),
    )?;
    arkworks_fixture_export_helper::print_fixture_summary(&fixture);

    Ok(())
}
