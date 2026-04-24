#!/usr/bin/env bash

set -euo pipefail

circom_pipeline_ensure_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "missing required tool: $1" >&2
        exit 1
    fi
}

circom_pipeline_write_build_config() {
    cat >"$BUILD_CONFIG_PATH" <<EOF
GROTH16_CURVE=$GROTH16_CURVE
EOF
}

circom_pipeline_build_config_matches() {
    [[ -f "$BUILD_CONFIG_PATH" ]] || return 1
    grep -Fxq "GROTH16_CURVE=$GROTH16_CURVE" "$BUILD_CONFIG_PATH"
}

circom_pipeline_needs_recompile() {
    if [[ ! -f "$R1CS_PATH" || ! -f "$SYM_PATH" || ! -f "$WASM_PATH" || ! -f "$COMPILE_STAMP" ]]; then
        return 0
    fi

    circom_pipeline_build_config_matches || return 0

    [[ "$WRAPPER_CIRCUIT" -nt "$COMPILE_STAMP" ]] && return 0
    [[ "$BASE_CIRCUIT" -nt "$COMPILE_STAMP" ]] && return 0

    local dependency
    for dependency in "$@"; do
        [[ "$dependency" -nt "$COMPILE_STAMP" ]] && return 0
    done

    return 1
}

circom_pipeline_build_artifacts() {
    circom_pipeline_ensure_tool circom

    mkdir -p "$ARTIFACTS_DIR"

    if circom_pipeline_needs_recompile "$@"; then
        rm -rf "$WASM_DIR"
        rm -f "$R1CS_PATH" "$SYM_PATH" "$COMPILE_STAMP"
        echo "compiling Circom wrapper into $ARTIFACTS_DIR" >&2
        circom --prime "$GROTH16_CURVE" --r1cs --wasm --sym --output "$ARTIFACTS_DIR" "$WRAPPER_CIRCUIT"
        circom_pipeline_write_build_config
        touch "$COMPILE_STAMP"
    fi

    printf '%s\n' "$ARTIFACTS_DIR"
}

circom_pipeline_run_e2e_test() {
    local work_dir="${1:-$ARTIFACTS_DIR/final_fixture}"
    local aiken_vk_output_path="${2:-}"

    circom_pipeline_ensure_tool cargo

    "$ARTIFACTS_SCRIPT" >/dev/null

    mkdir -p "$work_dir"

    local input_json_path="$work_dir/input.json"
    local cargo_locked_args=()
    if [[ -f "$ROOT_DIR/Cargo.lock" ]]; then
        cargo_locked_args=(--locked)
    fi

    cargo run \
        "${cargo_locked_args[@]}" \
        --quiet \
        --release \
        --manifest-path "$ROOT_DIR/Cargo.toml" \
        --bin generate_test_witness_for_circuit \
        -- >"$input_json_path"

    local export_args=(
        "${cargo_locked_args[@]}"
        --quiet
        --release
        --manifest-path "$ROOT_DIR/Cargo.toml"
        --bin arkworks_circom_fixture_export
        --
        "$input_json_path"
        "$work_dir"
    )

    if [[ -n "$aiken_vk_output_path" ]]; then
        export_args+=("$aiken_vk_output_path")
    fi

    cargo run "${export_args[@]}"

    printf '%s\n' "$work_dir"
}
