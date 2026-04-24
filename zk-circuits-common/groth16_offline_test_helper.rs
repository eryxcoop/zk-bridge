use std::fs;
use std::path::Path;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

pub struct OfflineFixtureExpectation<'a> {
    pub vk_filename: &'a str,
    pub expected_public_inputs: usize,
    pub required_summary_fragments: &'a [&'a str],
}

pub fn run_groth16_offline_fixture_test(
    manifest_dir: &Path,
    expectation: OfflineFixtureExpectation<'_>,
) {
    let script_path = manifest_dir.join("scripts/run_e2e_test.sh");
    let artifacts_dir = manifest_dir.join("groth16_artifacts");
    let work_dir = artifacts_dir.join("test_runs").join(unique_suffix());

    let output = Command::new("bash")
        .arg(script_path)
        .arg(&work_dir)
        .current_dir(manifest_dir)
        .output()
        .expect("should run Groth16 offline flow script");

    if !output.status.success() {
        let stdout = String::from_utf8_lossy(&output.stdout);
        let stderr = String::from_utf8_lossy(&output.stderr);
        panic!(
            "offline Groth16 flow failed\nstatus: {:?}\nstdout:\n{}\nstderr:\n{}",
            output.status.code(),
            stdout,
            stderr
        );
    }

    for filename in [
        "input.json",
        "proof.json",
        "public.json",
        "packed_public_inputs.json",
        "fixture_summary.json",
        expectation.vk_filename,
    ] {
        assert_exists(&work_dir.join(filename));
    }

    let verify_log = fs::read_to_string(work_dir.join("verify.log"))
        .expect("verify log should be written by the flow script");
    assert!(
        verify_log.contains("verified=true"),
        "expected arkworks verification success, got:\n{}",
        verify_log
    );
    assert!(
        verify_log.contains(&format!("public_inputs={}", expectation.expected_public_inputs)),
        "expected packed {}-public-input statement, got:\n{}",
        expectation.expected_public_inputs,
        verify_log
    );

    let summary = fs::read_to_string(work_dir.join("fixture_summary.json"))
        .expect("fixture summary should be written by the flow script");
    assert!(
        summary.contains(&format!("\"public_inputs\": {}", expectation.expected_public_inputs)),
        "expected packed {}-public-input statement, got:\n{}",
        expectation.expected_public_inputs,
        summary
    );

    for fragment in expectation.required_summary_fragments {
        assert!(
            summary.contains(fragment),
            "expected fixture summary fragment {:?}, got:\n{}",
            fragment,
            summary
        );
    }
}

fn assert_exists(path: &Path) {
    assert!(
        path.exists(),
        "expected artifact to exist: {}",
        path.display()
    );
}

fn unique_suffix() -> String {
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock should be after unix epoch")
        .as_millis();
    format!("offline_{millis}")
}
