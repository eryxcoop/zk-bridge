use std::path::PathBuf;

mod groth16_offline_test_helper {
    include!("../../zk-circuits-common/groth16_offline_test_helper.rs");
}

#[test]
fn groth16_offline_fixture_runs_end_to_end() {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    groth16_offline_test_helper::run_groth16_offline_fixture_test(
        &manifest_dir,
        groth16_offline_test_helper::OfflineFixtureExpectation {
            vk_filename: "snapshot_membership_vk.ak",
            expected_public_inputs: 6,
            required_summary_fragments: &[
                "\"cardano_tx_hash_hex\": \"aba2057996571cb3c6bbdbd6c7afd3eeff12edfd4b393924943b8d139b068412\"",
                "\"packed_public_inputs\"",
            ],
        },
    );
}
