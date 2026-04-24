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
            vk_filename: "tx_set_update_vk.ak",
            expected_public_inputs: 4,
            required_summary_fragments: &["\"tx_id_hex\"", "\"packed_public_inputs\""],
        },
    );
}
