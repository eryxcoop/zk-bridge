fn file_contents_match(left: &std::path::Path, right: &std::path::Path) -> bool {
    match (std::fs::read(left), std::fs::read(right)) {
        (Ok(left_bytes), Ok(right_bytes)) => left_bytes == right_bytes,
        _ => false,
    }
}

pub fn transpile_circom_wasm_alias(wrapper_stem: &str) {
    let wasm_dir = std::path::Path::new("./circuit_build").join(format!("{wrapper_stem}_js"));
    let original_wasm = wasm_dir.join(format!("{wrapper_stem}.wasm"));

    if original_wasm.exists() {
        let out_dir = std::path::PathBuf::from(std::env::var("OUT_DIR").expect("OUT_DIR must be set"));
        let alias_dir = out_dir.join("rust_witness_alias");
        std::fs::create_dir_all(&alias_dir).expect("could not create rust-witness alias dir");

        // `rust-witness` expects the wasm stem to match the exported C symbols.
        // Circom compresses underscores out of C entrypoints, so expose the
        // no-underscore alias here.
        let alias_stem: String = wrapper_stem.chars().filter(|ch| *ch != '_').collect();
        let alias_wasm = alias_dir.join(format!("{alias_stem}.wasm"));
        let needs_copy = !file_contents_match(&original_wasm, &alias_wasm);

        if needs_copy {
            std::fs::copy(&original_wasm, &alias_wasm)
                .expect("could not copy wasm alias for rust-witness");
        }

        rust_witness::transpile::transpile_wasm(alias_dir.display().to_string());
    } else {
        println!(
            "cargo:warning=missing Circom wasm file at {}; run scripts/build_circuit.sh before building arkworks probes",
            original_wasm.display()
        );
    }
}
