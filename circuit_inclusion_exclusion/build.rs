mod rust_witness_build_helper {
    include!("../zk-circuits-common/rust_witness_build_helper.rs");
}

fn main() {
    rust_witness_build_helper::transpile_circom_wasm_alias("tx_set_update_main");
}
