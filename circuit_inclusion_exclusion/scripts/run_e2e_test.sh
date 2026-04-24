#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON_PIPELINE_SCRIPT="$ROOT_DIR/../zk-circuits-common/circom_fixture_pipeline.sh"
source "$COMMON_PIPELINE_SCRIPT"

ARTIFACTS_SCRIPT="$ROOT_DIR/scripts/build_groth16_artifacts.sh"
ARTIFACTS_DIR="${GROTH16_ARTIFACTS_DIR:-$ROOT_DIR/groth16_artifacts}"
circom_pipeline_run_e2e_test "${1:-$ARTIFACTS_DIR/final_fixture}" "${2:-}"
