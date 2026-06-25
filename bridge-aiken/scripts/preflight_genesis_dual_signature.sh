#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_DIR="$(cd "$ROOT_DIR/.." && pwd)"
RUN_OUTPUTS_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/run_outputs_common.sh"
TOOLING_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/tooling_common.sh"
GUARDRAILS_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/guardrails_common.sh"
FLOW_OBSERVABILITY_SCRIPT="$ROOT_DIR/scripts/lib/flow_observability.sh"
ENTRYPOINT_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/entrypoint_common.sh"
WORKSPACE_CHECK_SCRIPT="$ROOT_DIR/scripts/check_workspace_layout.sh"
TOOLING_CHECK_SCRIPT="$ROOT_DIR/scripts/check_local_tooling.sh"
PYTHON_DIR="$ROOT_DIR/scripts/python"
CHECK_PREFLIGHT_PY="$PYTHON_DIR/check_genesis_dual_signature_preflight.py"
JUBJUB_CIRCUIT_DIR="$WORKSPACE_DIR/circuit_jubjub_schnorr_verification"
JUBJUB_BUILD_SCRIPT="$JUBJUB_CIRCUIT_DIR/scripts/build_groth16_artifacts.sh"
JUBJUB_CARGO_MANIFEST="$JUBJUB_CIRCUIT_DIR/Cargo.toml"
GENESIS_DUAL_FIXTURE_PATH="$ROOT_DIR/scripts/data/jubjub_schnorr_genesis_raw.json"
BRIDGE_VERBOSE_CONTEXT="${BRIDGE_VERBOSE_CONTEXT:-genesis-dual-signature-preflight}"

# shellcheck disable=SC1090
source "$RUN_OUTPUTS_COMMON_SCRIPT"
# shellcheck disable=SC1090
source "$TOOLING_COMMON_SCRIPT"
# shellcheck disable=SC1090
source "$GUARDRAILS_COMMON_SCRIPT"
# shellcheck disable=SC1090
source "$FLOW_OBSERVABILITY_SCRIPT"
# shellcheck disable=SC1090
source "$ENTRYPOINT_COMMON_SCRIPT"

OUTPUT_DIR="${GENESIS_DUAL_PREFLIGHT_OUTPUT_DIR:-$(default_flow_run_dir genesis-dual-signature-preflight)}"

usage() {
  cat <<'EOF'
usage: preflight_genesis_dual_signature.sh [--output-dir <dir>]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

ensure_run_dir "$OUTPUT_DIR"
setup_run_log_dir "$OUTPUT_DIR"
setup_flow_observability "$OUTPUT_DIR" "genesis-dual-signature-preflight"
trap 'preflight_exit=$?; if [[ "$preflight_exit" -eq 0 ]]; then finalize_flow_success; else finalize_flow_failure "$preflight_exit"; fi' EXIT

run_flow_guardrails "genesis-dual-signature" "$WORKSPACE_CHECK_SCRIPT" "$TOOLING_CHECK_SCRIPT"

resolve_binary_path PYTHON_BIN "Python 3 binary" PYTHON_BIN python3 "$ROOT_DIR/.venv/bin/python" || exit 1
resolve_binary_path CARGO_BIN "Cargo binary" CARGO_BIN cargo || exit 1
print_resolved_binary_if_verbose "Python 3 binary" "$PYTHON_BIN"
print_resolved_binary_if_verbose "Cargo binary" "$CARGO_BIN"
export_resolved_toolchain_env

if [[ ! -x "$JUBJUB_BUILD_SCRIPT" ]]; then
  echo "Missing Jubjub circuit build script at: $JUBJUB_BUILD_SCRIPT" >&2
  exit 1
fi

begin_stage "Building or reusing Jubjub circuit artifacts"
(cd "$JUBJUB_CIRCUIT_DIR" && "$JUBJUB_BUILD_SCRIPT")

begin_stage "Checking preview dual-genesis fixture wiring"
"$PYTHON_BIN" "$CHECK_PREFLIGHT_PY"

begin_stage "Verifying preview dual-genesis proof against deterministic Jubjub circuit VK"
"$CARGO_BIN" run --manifest-path "$JUBJUB_CARGO_MANIFEST" --bin verify_exported_fixture -- "$GENESIS_DUAL_FIXTURE_PATH"

echo "Genesis dual-signature preflight passed."
