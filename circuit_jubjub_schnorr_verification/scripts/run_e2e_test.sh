#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON_PIPELINE_SCRIPT="$ROOT_DIR/../zk-circuits-common/circom_pipeline.sh"
source "$COMMON_PIPELINE_SCRIPT"

BUILD_CIRCUIT_SCRIPT="$ROOT_DIR/scripts/build_groth16_artifacts.sh"
CIRCUIT_BUILD_DIR="${GROTH16_ARTIFACTS_DIR:-$ROOT_DIR/circuit_build}"
circom_pipeline_run_e2e_test "${1:-$CIRCUIT_BUILD_DIR/final_fixture}" "${2:-}"
