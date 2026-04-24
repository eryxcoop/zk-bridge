use anyhow::{Result, bail};
use blake2::{Blake2s256, Digest};
use mithril_circuits_utils::{
    PackedSnapshotMembershipPublicInputs, pack_snapshot_membership_public_inputs,
    pack_snapshot_membership_public_inputs_vec, unpack_snapshot_membership_public_inputs,
};
use serde::Serialize;

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
    packed_public_inputs: PackedSnapshotMembershipPublicInputs,
    cardano_tx_hash_hex: String,
    locking_tx_merkle_proof_public_sub_root_hex: String,
    tx_snapshot_certificate_protocol_message_cardano_transactions_merkle_root_hex: String,
    minting_merkle_proof: arkworks_fixture_export_helper::ProofHex,
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = arkworks_fixture_export_helper::parse_export_args()?;
    let fixture = arkworks_fixture_export_helper::generate_fixture(
        "mithril_legacy_tx_membership_main",
        "mithril-legacy-tx-membership-local-fixture-v1",
        |bytes| Blake2s256::digest(bytes).into(),
        &args.input_json_path,
    )?;

    let (cardano_tx_hash, sub_root, snapshot_root) =
        unpack_snapshot_membership_public_inputs(&fixture.public_inputs_json)?;
    let packed_public_inputs =
        pack_snapshot_membership_public_inputs(&cardano_tx_hash, &sub_root, &snapshot_root);
    let canonical_public_inputs =
        pack_snapshot_membership_public_inputs_vec(&cardano_tx_hash, &sub_root, &snapshot_root);
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
        cardano_tx_hash_hex: hex::encode(cardano_tx_hash),
        locking_tx_merkle_proof_public_sub_root_hex: hex::encode(sub_root),
        tx_snapshot_certificate_protocol_message_cardano_transactions_merkle_root_hex:
            hex::encode(snapshot_root),
        minting_merkle_proof: fixture.proof_hex.clone(),
    };

    arkworks_fixture_export_helper::write_fixture_outputs(
        &fixture,
        &args.out_dir,
        &summary.packed_public_inputs,
        &summary,
        "snapshot_membership_vk.ak",
        "snapshot_membership_vk",
        args.aiken_vk_output_path.as_deref(),
    )?;
    arkworks_fixture_export_helper::print_fixture_summary(&fixture);

    Ok(())
}
