mod rust_witness_build_helper {
    include!("../zk-circuits-common/rust_witness_build_helper.rs");
}

fn main() {
    rust_witness_build_helper::transpile_circom_wasm_alias("jubjub_schnorr_verification_main");
}
