#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON_PIPELINE_SCRIPT="$ROOT_DIR/../zk-circuits-common/circom_pipeline.sh"
source "$COMMON_PIPELINE_SCRIPT"

CIRCUIT_BUILD_DIR="${GROTH16_ARTIFACTS_DIR:-$ROOT_DIR/circuit_build}"
GROTH16_CURVE="${GROTH16_CURVE:-bls12381}"
WRAPPER_CIRCUIT="$ROOT_DIR/jubjub_schnorr_verification_main.circom"
BASE_CIRCUIT="$ROOT_DIR/jubjub_schnorr_verification.circom"
R1CS_PATH="$CIRCUIT_BUILD_DIR/jubjub_schnorr_verification_main.r1cs"
SYM_PATH="$CIRCUIT_BUILD_DIR/jubjub_schnorr_verification_main.sym"
WASM_DIR="$CIRCUIT_BUILD_DIR/jubjub_schnorr_verification_main_js"
WASM_PATH="$WASM_DIR/jubjub_schnorr_verification_main.wasm"
COMPILE_STAMP="$CIRCUIT_BUILD_DIR/.compile.stamp"
BUILD_CONFIG_PATH="$CIRCUIT_BUILD_DIR/.build_config"
DEPENDENCY_PATHS=(
    "$ROOT_DIR/jubjub_schnorr_verification_aux_components.circom"
    "$ROOT_DIR/midnight_poseidon3_sponge.circom"
    "$ROOT_DIR/midnight_poseidon3_constants.circom"
)

circom_pipeline_build_circuit "${DEPENDENCY_PATHS[@]}"
