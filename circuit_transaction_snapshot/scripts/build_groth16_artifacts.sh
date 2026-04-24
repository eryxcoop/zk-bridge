#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON_PIPELINE_SCRIPT="$ROOT_DIR/../zk-circuits-common/circom_fixture_pipeline.sh"
source "$COMMON_PIPELINE_SCRIPT"

ARTIFACTS_DIR="${GROTH16_ARTIFACTS_DIR:-$ROOT_DIR/groth16_artifacts}"
GROTH16_CURVE="${GROTH16_CURVE:-bls12381}"
WRAPPER_CIRCUIT="$ROOT_DIR/mithril_legacy_tx_membership_main.circom"
BASE_CIRCUIT="$ROOT_DIR/mithril_legacy_tx_membership.circom"
R1CS_PATH="$ARTIFACTS_DIR/mithril_legacy_tx_membership_main.r1cs"
SYM_PATH="$ARTIFACTS_DIR/mithril_legacy_tx_membership_main.sym"
WASM_DIR="$ARTIFACTS_DIR/mithril_legacy_tx_membership_main_js"
WASM_PATH="$WASM_DIR/mithril_legacy_tx_membership_main.wasm"
COMPILE_STAMP="$ARTIFACTS_DIR/.compile.stamp"
BUILD_CONFIG_PATH="$ARTIFACTS_DIR/.build_config"
DEPENDENCY_PATHS=(
    "$ROOT_DIR/mithril_legacy_tx_membership_aux_components.circom"
    "$ROOT_DIR/vendor/blake2s.circom"
    "$ROOT_DIR/vendor/blake2_common.circom"
    "$ROOT_DIR/sha256_bytes.circom"
    "$ROOT_DIR/vendor/circomlib_sha256/sha256.circom"
)

circom_pipeline_build_artifacts "${DEPENDENCY_PATHS[@]}"
