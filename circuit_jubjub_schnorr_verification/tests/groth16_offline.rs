use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, MutexGuard, Once, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};

use jubjub_schnorr_verification_circuit::{
    load_example_valid_witness, split_digest_hex_to_halves_decimal,
    JubjubSchnorrCircuitInputs,
};
use num_bigint::BigUint;
use serde::Deserialize;

mod groth16_offline_test_helper {
    include!("../../zk-circuits-common/groth16_offline_test_helper.rs");
}

static BUILD_ONCE: Once = Once::new();
static TEMP_COUNTER: AtomicU64 = AtomicU64::new(0);
static TEST_MUTEX: OnceLock<Mutex<()>> = OnceLock::new();

#[derive(Deserialize)]
struct UpstreamVectorFixture {
    sha256_digest_hex: String,
    verification_key_coordinates_le_hex: UpstreamVerificationKeyHex,
    signature_split_hex: UpstreamSignatureSplitHex,
}

#[derive(Deserialize)]
struct UpstreamVerificationKeyHex {
    u_hex: String,
    v_hex: String,
}

#[derive(Deserialize)]
struct UpstreamSignatureSplitHex {
    response_hex: String,
    challenge_hex: String,
}

#[test]
fn groth16_offline_fixture_runs_end_to_end() {
    let _guard = test_guard();
    let manifest_dir = manifest_dir();
    groth16_offline_test_helper::run_groth16_offline_fixture_test(
        &manifest_dir,
        groth16_offline_test_helper::OfflineFixtureExpectation {
            vk_filename: "jubjub_schnorr_verification_vk.ak",
            expected_public_inputs: 6,
            required_summary_fragments: &[
                "\"message_base\": \"16808672146709759238327133555736750089977066230599028589193936481731504400486\"",
                "\"digest_hi\"",
                "\"digest_low\"",
                "\"signature_challenge\": \"10095715300072557500893906797299109643152202583587719141187011679836436092212\"",
                "\"packed_public_inputs\"",
            ],
        },
    );
}

#[test]
fn invalid_digest_is_rejected() {
    let _guard = test_guard();
    let mut input = load_example_valid_witness().expect("valid witness should load");
    input.digest_low = decimal_plus_one_u128(&input.digest_low);

    let output = run_node_witness_expect_failure(&input);
    assert_stderr_contains(&output, "Assert Failed.");
}

#[test]
fn invalid_response_is_rejected() {
    let _guard = test_guard();
    let mut input = load_example_valid_witness().expect("valid witness should load");
    input.signature_response = decimal_plus_one(&input.signature_response);

    let output = run_node_witness_expect_failure(&input);
    assert_stderr_contains(&output, "Assert Failed.");
}

#[test]
fn invalid_challenge_is_rejected() {
    let _guard = test_guard();
    let mut input = load_example_valid_witness().expect("valid witness should load");
    input.signature_challenge = decimal_plus_one(&input.signature_challenge);
    let (challenge_scalar, challenge_quotient) =
        reduce_base_field_decimal_to_scalar(&input.signature_challenge);
    input.challenge_scalar = challenge_scalar;
    input.challenge_quotient = challenge_quotient;

    let output = run_node_witness_expect_failure(&input);
    assert_stderr_contains(&output, "Assert Failed.");
}

#[test]
fn invalid_verification_key_is_rejected() {
    let _guard = test_guard();
    let mut input = load_example_valid_witness().expect("valid witness should load");
    input.verification_key_u = decimal_plus_one(&input.verification_key_u);

    let output = run_node_witness_expect_failure(&input);
    assert_stderr_contains(&output, "Assert Failed.");
}

#[test]
fn torsion_verification_key_is_rejected() {
    let _guard = test_guard();
    let input: JubjubSchnorrCircuitInputs = serde_json::from_str(include_str!(
        "../examples/invalid_torsion_key_statement.json"
    ))
    .expect("invalid_torsion_key_statement.json must stay valid JSON");

    let output = run_node_witness_expect_failure(&input);
    assert_stderr_contains(&output, "Assert Failed.");
}

#[test]
fn canonical_upstream_vector_now_validates_end_to_end() {
    let _guard = test_guard();
    let valid_example = load_example_valid_witness().expect("valid witness should load");
    let upstream = load_canonical_upstream_fixture().expect("upstream fixture should parse");

    assert_eq!(upstream.digest_hi, valid_example.digest_hi);
    assert_eq!(upstream.digest_low, valid_example.digest_low);
    assert_eq!(
        upstream.verification_key_u,
        valid_example.verification_key_u
    );
    assert_eq!(
        upstream.verification_key_v,
        valid_example.verification_key_v
    );
    assert_eq!(
        upstream.signature_response,
        valid_example.signature_response
    );
    assert_eq!(
        upstream.signature_challenge,
        valid_example.signature_challenge
    );
    assert_eq!(upstream.challenge_scalar, valid_example.challenge_scalar);
    assert_eq!(
        upstream.challenge_quotient,
        valid_example.challenge_quotient
    );
    assert_eq!(
        upstream.message_base().expect("upstream digest should derive message_base"),
        valid_example
            .message_base()
            .expect("example digest should derive message_base")
    );

    run_node_witness_expect_success(&upstream);
}

fn run_node_witness_expect_failure(input: &JubjubSchnorrCircuitInputs) -> Output {
    ensure_artifacts_built();
    input
        .validate()
        .expect("test inputs should remain syntactically valid");

    let temp_dir = temp_test_dir();
    fs::create_dir_all(&temp_dir).expect("should create test temp dir");
    let input_path = temp_dir.join("input.json");
    let witness_path = temp_dir.join("witness.wtns");
    fs::write(
        &input_path,
        serde_json::to_vec_pretty(input).expect("input should serialize"),
    )
    .expect("should write temp input");

    let output = Command::new("node")
        .arg(generate_witness_js_path())
        .arg(wasm_path())
        .arg(&input_path)
        .arg(&witness_path)
        .current_dir(manifest_dir())
        .output()
        .expect("node witness generation should run");

    assert!(
        !output.status.success(),
        "expected witness generation to fail, but it succeeded\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );

    output
}

fn run_node_witness_expect_success(input: &JubjubSchnorrCircuitInputs) {
    ensure_artifacts_built();
    input
        .validate()
        .expect("test inputs should remain syntactically valid");

    let temp_dir = temp_test_dir();
    fs::create_dir_all(&temp_dir).expect("should create test temp dir");
    let input_path = temp_dir.join("input.json");
    let witness_path = temp_dir.join("witness.wtns");
    fs::write(
        &input_path,
        serde_json::to_vec_pretty(input).expect("input should serialize"),
    )
    .expect("should write temp input");

    let output = Command::new("node")
        .arg(generate_witness_js_path())
        .arg(wasm_path())
        .arg(&input_path)
        .arg(&witness_path)
        .current_dir(manifest_dir())
        .output()
        .expect("node witness generation should run");

    assert!(
        output.status.success(),
        "expected witness generation to succeed, but it failed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

fn load_canonical_upstream_fixture() -> anyhow::Result<JubjubSchnorrCircuitInputs> {
    let fixture: UpstreamVectorFixture =
        serde_json::from_str(include_str!("../fixtures/valid_deterministic_vector.json"))?;
    let (digest_hi, digest_low) = split_digest_hex_to_halves_decimal(&fixture.sha256_digest_hex)?;
    let verification_key_u = le_hex_to_decimal(&fixture.verification_key_coordinates_le_hex.u_hex);
    let verification_key_v = le_hex_to_decimal(&fixture.verification_key_coordinates_le_hex.v_hex);
    let signature_response = le_hex_to_decimal(&fixture.signature_split_hex.response_hex);
    let signature_challenge = le_hex_to_decimal(&fixture.signature_split_hex.challenge_hex);
    let (challenge_scalar, challenge_quotient) =
        reduce_base_field_decimal_to_scalar(&signature_challenge);

    Ok(JubjubSchnorrCircuitInputs {
        digest_hi,
        digest_low,
        verification_key_u,
        verification_key_v,
        signature_response,
        signature_challenge,
        challenge_scalar,
        challenge_quotient,
    })
}

fn ensure_artifacts_built() {
    BUILD_ONCE.call_once(|| {
        let output = Command::new("bash")
            .arg(manifest_dir().join("scripts/build_circuit.sh"))
            .current_dir(manifest_dir())
            .output()
            .expect("should run build_circuit.sh");

        if !output.status.success() {
            panic!(
                "artifact build failed\nstatus: {:?}\nstdout:\n{}\nstderr:\n{}",
                output.status.code(),
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr),
            );
        }
    });
}

fn manifest_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn test_guard() -> MutexGuard<'static, ()> {
    TEST_MUTEX
        .get_or_init(|| Mutex::new(()))
        .lock()
        .unwrap_or_else(|poison| poison.into_inner())
}

fn generate_witness_js_path() -> PathBuf {
    manifest_dir()
        .join("circuit_build")
        .join("jubjub_schnorr_verification_main_js")
        .join("generate_witness.js")
}

fn wasm_path() -> PathBuf {
    manifest_dir()
        .join("circuit_build")
        .join("jubjub_schnorr_verification_main_js")
        .join("jubjub_schnorr_verification_main.wasm")
}

fn temp_test_dir() -> PathBuf {
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock should be after unix epoch")
        .as_millis();
    let counter = TEMP_COUNTER.fetch_add(1, Ordering::Relaxed);
    std::env::temp_dir().join(format!(
        "jubjub_schnorr_offline_{}_{}_{}",
        std::process::id(),
        millis,
        counter
    ))
}

fn assert_stderr_contains(output: &Output, needle: &str) {
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains(needle),
        "expected stderr to contain {:?}, got:\n{}",
        needle,
        stderr
    );
}

fn decimal_plus_one(value: &str) -> String {
    let parsed: BigUint = value.parse().expect("decimal string should parse");
    (parsed + BigUint::from(1u8)).to_string()
}

fn decimal_plus_one_u128(value: &str) -> String {
    let parsed: u128 = value.parse().expect("decimal u128 string should parse");
    (parsed + 1).to_string()
}

fn reduce_base_field_decimal_to_scalar(base_decimal: &str) -> (String, String) {
    let base: BigUint = base_decimal.parse().expect("base decimal should parse");
    let scalar_order = BigUint::parse_bytes(
        b"0e7db4ea6533afa906673b0101343b00a6682093ccc81082d0970e5ed6f72cb7",
        16,
    )
    .expect("scalar order hex should parse");
    let quotient = &base / &scalar_order;
    let remainder = &base % &scalar_order;
    (remainder.to_string(), quotient.to_string())
}

fn le_hex_to_decimal(hex_le: &str) -> String {
    let bytes = decode_hex(hex_le);
    BigUint::from_bytes_le(&bytes).to_string()
}

fn decode_hex(text: &str) -> Vec<u8> {
    assert!(text.len() % 2 == 0, "hex input must have even length");
    let mut bytes = Vec::with_capacity(text.len() / 2);
    for chunk in text.as_bytes().chunks_exact(2) {
        let hex = std::str::from_utf8(chunk).expect("hex should be utf-8");
        bytes.push(u8::from_str_radix(hex, 16).expect("hex byte should parse"));
    }
    bytes
}

#[allow(dead_code)]
fn _debug_path_exists(path: &Path) -> bool {
    path.exists()
}
