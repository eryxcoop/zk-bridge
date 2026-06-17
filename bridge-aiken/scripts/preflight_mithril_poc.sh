#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_DIR="$ROOT_DIR/scripts/python"
VERIFIER_GEN_DIR="$ROOT_DIR/../plutus-halo2-verifier-gen"
VERIFIER_GEN_CARGO_LOCK="$VERIFIER_GEN_DIR/Cargo.lock"
BUILD_PROOF_EXPORT_BUNDLE_SCRIPT="$ROOT_DIR/scripts/build_bridge_compatible_mithril_stm_proof_export_bundle.sh"
BUILD_COMPATIBLE_BUNDLE_PY="$PYTHON_DIR/build_bridge_compatible_mithril_stm_bundle.py"
TOOLING_CHECK_SCRIPT="$ROOT_DIR/scripts/check_local_tooling.sh"
WORKSPACE_CHECK_SCRIPT="$ROOT_DIR/scripts/check_workspace_layout.sh"
RUN_OUTPUTS_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/run_outputs_common.sh"
TOOLING_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/tooling_common.sh"
GUARDRAILS_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/guardrails_common.sh"
ENTRYPOINT_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/entrypoint_common.sh"
FLOW_OBSERVABILITY_SCRIPT="$ROOT_DIR/scripts/lib/flow_observability.sh"
SYNC_BRIDGE_ZK_FIXTURE_PY="$PYTHON_DIR/sync_bridge_zk_fixture.py"
CHECK_PREFLIGHT_PY="$PYTHON_DIR/check_mithril_poc_preflight.py"
CHECK_TEST_FIXTURE_ALIGNMENT_PY="$PYTHON_DIR/check_test_fixture_alignment.py"
BRIDGE_FLOW_VERBOSE="${BRIDGE_FLOW_VERBOSE:-0}"
BRIDGE_VERBOSE_CONTEXT="${BRIDGE_VERBOSE_CONTEXT:-preflight-runtime}"
BRIDGE_SKIP_FLOW_CHECKS="${BRIDGE_SKIP_FLOW_CHECKS:-0}"
export RUSTFLAGS="${RUSTFLAGS:--Awarnings}"

# shellcheck disable=SC1090
source "$RUN_OUTPUTS_COMMON_SCRIPT"

# shellcheck disable=SC1090
source "$TOOLING_COMMON_SCRIPT"
# shellcheck disable=SC1090
source "$GUARDRAILS_COMMON_SCRIPT"
# shellcheck disable=SC1090
source "$ENTRYPOINT_COMMON_SCRIPT"
# shellcheck disable=SC1090
source "$FLOW_OBSERVABILITY_SCRIPT"

handoff_to_wrapper_if_direct "$ROOT_DIR/scripts/bridge.sh" preflight "$@"

CARGO_LOCKED_ARGS=()
if [[ -f "$VERIFIER_GEN_CARGO_LOCK" ]]; then
  CARGO_LOCKED_ARGS=(--locked)
fi

OUTPUT_DIR_DEFAULT="$(default_flow_run_dir mithril-poc)"
OUTPUT_DIR="$OUTPUT_DIR_DEFAULT"
PROOF_EXPORT_BUNDLE_PATH=""
RUNTIME_BUILD_PROOF_EXPORT_BUNDLE_PATH=""
WRITE_SNAPSHOT=0
RESUME_RUN=0
CLEAN_RUN=0

usage() {
  cat <<'EOF'
usage: preflight_mithril_poc.sh [--proof-export-bundle <bridge-compatible-mithril-stm-bundle.json>] [--output-dir <dir>] [--resume|--clean] [--write-snapshot]

Runs drift checks for the Mithril PoC before executing the integrated bridge
flow. If --proof-export-bundle is omitted, the canonical bridge-compatible bundle is
generated inside --output-dir and used for the checks. When the canonical
reference snapshot drifts, preflight refreshes it automatically.
EOF
}

run_logged() {
  local label="$1"
  shift

  if [[ "$BRIDGE_FLOW_VERBOSE" == "1" ]]; then
    "$@"
    return
  fi

  local log_path
  if [[ -n "${BRIDGE_LOG_DIR:-}" ]]; then
    log_path="$(mktemp_in_dir "$BRIDGE_LOG_DIR" "bridge-preflight-${label// /-}.XXXXXX.log")"
  else
    log_path="$(mktemp_in_dir "${TMPDIR:-/tmp}" "bridge-preflight-${label// /-}.XXXXXX.log")"
  fi

  if "$@" >"$log_path" 2>&1; then
    rm -f "$log_path"
    return
  fi

  set_last_command_failure_context "$label" "$*" "$log_path"

  echo "Command failed during: $label" >&2
  echo "Command: $*" >&2
  echo "Log: $log_path" >&2
  echo "--- log tail ---" >&2
  tail -n 40 "$log_path" >&2 || true
  echo "--- end log tail ---" >&2
  return 1
}

compute_preflight_fingerprint() {
  {
    printf 'preflight-v2\n'
    printf '%s  %s\n' "$(sha256_file "$0")" "$0"
    printf '%s  %s\n' "$(sha256_file "$SYNC_BRIDGE_ZK_FIXTURE_PY")" "$SYNC_BRIDGE_ZK_FIXTURE_PY"
    printf '%s  %s\n' "$(sha256_file "$CHECK_PREFLIGHT_PY")" "$CHECK_PREFLIGHT_PY"
    printf '%s  %s\n' "$(sha256_file "$CHECK_TEST_FIXTURE_ALIGNMENT_PY")" "$CHECK_TEST_FIXTURE_ALIGNMENT_PY"
    printf '%s  %s\n' "$(sha256_file "$ROOT_DIR/scripts/data/bridge_mint_raw.json")" "$ROOT_DIR/scripts/data/bridge_mint_raw.json"
    printf '%s  %s\n' "$(sha256_file "$ROOT_DIR/scripts/data/mithril_poc_reference_snapshot.json")" "$ROOT_DIR/scripts/data/mithril_poc_reference_snapshot.json"
    printf '%s  %s\n' "$(sha256_file "$ROOT_DIR/validators/tests/helpers/bridge_fixture.ak")" "$ROOT_DIR/validators/tests/helpers/bridge_fixture.ak"
    printf '%s  %s\n' "$(sha256_file "$ROOT_DIR/validators/tests/helpers/certificates/cardano_transactions.ak")" "$ROOT_DIR/validators/tests/helpers/certificates/cardano_transactions.ak"
    printf '%s  %s\n' "$(sha256_file "$ROOT_DIR/env/default.ak")" "$ROOT_DIR/env/default.ak"
    if [[ -f "$RUNTIME_BUILD_PROOF_EXPORT_BUNDLE_PATH" ]]; then
      printf '%s  %s\n' "$(sha256_file "$RUNTIME_BUILD_PROOF_EXPORT_BUNDLE_PATH")" "$RUNTIME_BUILD_PROOF_EXPORT_BUNDLE_PATH"
    fi
    printf '%s  %s\n' "$(sha256_file "$VERIFIER_GEN_DIR/Cargo.toml")" "$VERIFIER_GEN_DIR/Cargo.toml"
    if [[ -f "$VERIFIER_GEN_DIR/Cargo.lock" ]]; then
      printf '%s  %s\n' "$(sha256_file "$VERIFIER_GEN_DIR/Cargo.lock")" "$VERIFIER_GEN_DIR/Cargo.lock"
    fi
    find "$VERIFIER_GEN_DIR/src" -type f -print0 | hash_sorted_files_from_stdin0
  } | sha256_stream
}

runtime_bundle_has_proofs() {
  "${PYTHON_BIN:-python3}" - "$1" <<'PY' >/dev/null 2>&1
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
if not isinstance(data.get("proofs"), dict):
    raise SystemExit(1)
PY
}

recover_runtime_bundle_from_intermediates() {
  local output_dir=""
  local base_bundle=""
  local sd_genesis_bundle=""
  local sd_standard_bundle=""
  local tx_snapshot_bundle=""

  output_dir="$(dirname "$RUNTIME_BUILD_PROOF_EXPORT_BUNDLE_PATH")"
  base_bundle="$output_dir/bridge-compatible-mithril-stm-base-bundle.json"
  sd_genesis_bundle="$output_dir/bridge-compatible-mithril-stm-sd-genesis-bundle.json"
  sd_standard_bundle="$output_dir/bridge-compatible-mithril-stm-sd-standard-bundle.json"
  tx_snapshot_bundle="$output_dir/bridge-compatible-mithril-stm-tx-snapshot-bundle.json"

  for path in \
    "$base_bundle" \
    "$sd_genesis_bundle" \
    "$sd_standard_bundle" \
    "$tx_snapshot_bundle"; do
    [[ -f "$path" ]] || return 1
  done

  "$PYTHON_BIN" "$BUILD_COMPATIBLE_BUNDLE_PY" \
    "$base_bundle" \
    "$RUNTIME_BUILD_PROOF_EXPORT_BUNDLE_PATH" \
    --sd-genesis-bundle "$sd_genesis_bundle" \
    --sd-standard-bundle "$sd_standard_bundle" \
    --tx-snapshot-bundle "$tx_snapshot_bundle"
}

ensure_runtime_bundle_is_fresh() {
  if runtime_bundle_has_proofs "$RUNTIME_BUILD_PROOF_EXPORT_BUNDLE_PATH"; then
    return 0
  fi

  if recover_runtime_bundle_from_intermediates; then
    echo "rebuilding stale runtime bundle without proofs"
    echo "Recovered stale runtime bundle from existing intermediate artifacts."
    return 0
  fi

  begin_stage "Ensuring canonical bridge-compatible Mithril STM bundle for preflight" "rebuilding stale runtime bundle without proofs"
  BRIDGE_LOG_DIR="$BRIDGE_LOG_DIR" "$BUILD_PROOF_EXPORT_BUNDLE_SCRIPT" "$RUNTIME_BUILD_PROOF_EXPORT_BUNDLE_PATH"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --proof-export-bundle)
      PROOF_EXPORT_BUNDLE_PATH="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --resume)
      RESUME_RUN=1
      shift
      ;;
    --clean)
      CLEAN_RUN=1
      shift
      ;;
    --write-snapshot)
      WRITE_SNAPSHOT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$RESUME_RUN" == "1" && "$CLEAN_RUN" == "1" ]]; then
  echo "--resume and --clean are mutually exclusive" >&2
  exit 1
fi

resolve_binary_path PYTHON_BIN "Python 3 binary" PYTHON_BIN python3 "$ROOT_DIR/.venv/bin/python" || exit 1
resolve_binary_path CARGO_BIN "Cargo binary" CARGO_BIN cargo || exit 1
print_resolved_binary_if_verbose "Python 3 binary" "$PYTHON_BIN"
print_resolved_binary_if_verbose "Cargo binary" "$CARGO_BIN"
export_resolved_toolchain_env

run_flow_guardrails "preflight" "$WORKSPACE_CHECK_SCRIPT" "$TOOLING_CHECK_SCRIPT"

if [[ "$CLEAN_RUN" == "1" && -z "$PROOF_EXPORT_BUNDLE_PATH" ]]; then
  reset_run_dir "$OUTPUT_DIR"
else
  ensure_run_dir "$OUTPUT_DIR"
fi

setup_run_log_dir "$OUTPUT_DIR"
setup_flow_observability "$OUTPUT_DIR" "preflight"
trap 'preflight_exit=$?; if [[ "$preflight_exit" -eq 0 ]]; then finalize_flow_success; else finalize_flow_failure "$preflight_exit"; fi' EXIT

if [[ -z "$PROOF_EXPORT_BUNDLE_PATH" ]]; then
  RUNTIME_BUILD_PROOF_EXPORT_BUNDLE_PATH="$OUTPUT_DIR/bridge-compatible-mithril-stm-bundle.json"
  if [[ "$RESUME_RUN" == "1" ]]; then
    if [[ ! -f "$RUNTIME_BUILD_PROOF_EXPORT_BUNDLE_PATH" ]]; then
      echo "Cannot resume preflight; missing canonical bundle at: $RUNTIME_BUILD_PROOF_EXPORT_BUNDLE_PATH" >&2
      exit 1
    fi
    echo "==> Resuming with canonical bridge-compatible Mithril STM bundle for preflight"
  else
    begin_stage "Ensuring canonical bridge-compatible Mithril STM bundle for preflight"
    BRIDGE_LOG_DIR="$BRIDGE_LOG_DIR" "$BUILD_PROOF_EXPORT_BUNDLE_SCRIPT" "$RUNTIME_BUILD_PROOF_EXPORT_BUNDLE_PATH"
  fi
else
  PROOF_EXPORT_BUNDLE_PATH="$(cd "$(dirname "$PROOF_EXPORT_BUNDLE_PATH")" && pwd)/$(basename "$PROOF_EXPORT_BUNDLE_PATH")"
  RUNTIME_BUILD_PROOF_EXPORT_BUNDLE_PATH="$PROOF_EXPORT_BUNDLE_PATH"
fi

if [[ ! -f "$RUNTIME_BUILD_PROOF_EXPORT_BUNDLE_PATH" ]]; then
  echo "Missing Mithril STM runtime bundle at: $RUNTIME_BUILD_PROOF_EXPORT_BUNDLE_PATH" >&2
  exit 1
fi

begin_stage "Checking Mithril aggregator compatibility"
"$PYTHON_BIN" "$CHECK_PREFLIGHT_PY" --aggregator-only

ensure_runtime_bundle_is_fresh

begin_stage "Verifying generated bridge fixture"
SYNC_BRIDGE_FIXTURE_ARGS=()
if [[ -n "$RUNTIME_BUILD_PROOF_EXPORT_BUNDLE_PATH" ]]; then
  SYNC_BRIDGE_FIXTURE_ARGS+=(--proof-export-bundle "$RUNTIME_BUILD_PROOF_EXPORT_BUNDLE_PATH")
fi
if [[ "$CLEAN_RUN" == "1" ]]; then
  "$PYTHON_BIN" "$SYNC_BRIDGE_ZK_FIXTURE_PY" \
    --fix-drift \
    --skip-test-fixture-alignment \
    "${SYNC_BRIDGE_FIXTURE_ARGS[@]}"
else
  "$PYTHON_BIN" "$SYNC_BRIDGE_ZK_FIXTURE_PY" --check "${SYNC_BRIDGE_FIXTURE_ARGS[@]}"
fi

begin_stage "Validating Mithril STM bundle contract"
run_logged "cargo run export_mithril_stm_proof_export --check" \
  "$CARGO_BIN" run "${CARGO_LOCKED_ARGS[@]}" --manifest-path "$VERIFIER_GEN_DIR/Cargo.toml" --bin export_mithril_stm_proof_export -- \
  --check "$RUNTIME_BUILD_PROOF_EXPORT_BUNDLE_PATH"

begin_stage "Checking proof exports reuse across phase1/phase2, stake_distribution, and bridge"
CHECK_ARGS=("$RUNTIME_BUILD_PROOF_EXPORT_BUNDLE_PATH")
if [[ "$WRITE_SNAPSHOT" == "1" ]]; then
  CHECK_ARGS+=(--write-snapshot)
else
  CHECK_ARGS+=(--refresh-snapshot-on-drift)
fi
"$PYTHON_BIN" "$CHECK_PREFLIGHT_PY" "${CHECK_ARGS[@]}"

echo "Mithril PoC preflight passed."
echo "Checked runtime bundle: $RUNTIME_BUILD_PROOF_EXPORT_BUNDLE_PATH"
