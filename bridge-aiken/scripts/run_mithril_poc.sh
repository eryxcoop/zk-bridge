#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_PROOF_EXPORT_BUNDLE_SCRIPT="$ROOT_DIR/scripts/build_bridge_compatible_mithril_stm_proof_export_bundle.sh"
BRIDGE_MINTING_SCRIPT="$ROOT_DIR/scripts/bridge_minting.sh"
PREFLIGHT_SCRIPT="$ROOT_DIR/scripts/preflight_mithril_poc.sh"
TOOLING_CHECK_SCRIPT="$ROOT_DIR/scripts/check_local_tooling.sh"
WORKSPACE_CHECK_SCRIPT="$ROOT_DIR/scripts/check_workspace_layout.sh"
RUN_OUTPUTS_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/run_outputs_common.sh"
TOOLING_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/tooling_common.sh"
ENTRYPOINT_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/entrypoint_common.sh"
FLOW_OBSERVABILITY_SCRIPT="$ROOT_DIR/scripts/lib/flow_observability.sh"
BRIDGE_FLOW_VERBOSE="${BRIDGE_FLOW_VERBOSE:-0}"
BRIDGE_VERBOSE_CONTEXT="${BRIDGE_VERBOSE_CONTEXT:-run-runtime}"
export RUSTFLAGS="${RUSTFLAGS:--Awarnings}"

# shellcheck disable=SC1090
source "$RUN_OUTPUTS_COMMON_SCRIPT"

# shellcheck disable=SC1090
source "$TOOLING_COMMON_SCRIPT"
# shellcheck disable=SC1090
source "$ENTRYPOINT_COMMON_SCRIPT"
# shellcheck disable=SC1090
source "$FLOW_OBSERVABILITY_SCRIPT"

handoff_to_wrapper_if_direct "$ROOT_DIR/scripts/bridge.sh" run "$@"

OUTPUT_DIR_DEFAULT="$(default_flow_run_dir mithril-poc)"
OUTPUT_DIR="$OUTPUT_DIR_DEFAULT"
PROOF_EXPORT_BUNDLE_PATH=""
RUNTIME_PROOF_EXPORT_BUNDLE_PATH=""
SKIP_AIKEN_CHECK=0
SKIP_PREFLIGHT=0
STRICT_RUN=0
RESUME_RUN=0
CLEAN_RUN=0
BASH_BIN=""

usage() {
  cat <<'EOF'
usage: run_mithril_poc.sh [--proof-export-bundle <bridge-compatible-mithril-stm-bundle.json>] [--output-dir <dir>] [--resume|--clean] [--skip-aiken-check] [--skip-preflight] [--strict]

If --proof-export-bundle is omitted, the script generates the canonical bridge-compatible
Mithril STM bundle inside --output-dir and then runs the full bridge flow
with two Halo2-backed phase1/phase2 domains plus the Aiken-native
stake-distribution genesis bootstrap.

--strict pins the preflight to the front of the pipeline (before
`aiken check`) and forbids --skip-preflight. Recommended for CI-like
local validation.
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
    log_path="$(mktemp_in_dir "$BRIDGE_LOG_DIR" "bridge-poc-${label// /-}.XXXXXX.log")"
  else
    log_path="$(mktemp_in_dir "${TMPDIR:-/tmp}" "bridge-poc-${label// /-}.XXXXXX.log")"
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

run_aiken_check_logged() {
  local quoted_aiken_bin=""
  printf -v quoted_aiken_bin '%q' "$AIKEN_BIN"
  run_logged "aiken check" "$BASH_BIN" -lc "env NO_COLOR=1 $quoted_aiken_bin check --plain-numbers 2>&1"
}

compute_aiken_check_fingerprint() {
  {
    printf 'aiken-check-v1\n'
    "$AIKEN_BIN" --version 2>/dev/null || true
    printf '%s  %s\n' "$(sha256_file "$0")" "$0"
    printf '%s  %s\n' "$(sha256_file "$ROOT_DIR/aiken.toml")" "$ROOT_DIR/aiken.toml"
    printf '%s  %s\n' "$(sha256_file "$ROOT_DIR/aiken.lock")" "$ROOT_DIR/aiken.lock"
    if [[ -f "$ROOT_DIR/plutus.json" ]]; then
      printf '%s  %s\n' "$(sha256_file "$ROOT_DIR/plutus.json")" "$ROOT_DIR/plutus.json"
    fi
    find "$ROOT_DIR/lib" "$ROOT_DIR/validators" "$ROOT_DIR/env" -type f -print0 | hash_sorted_files_from_stdin0
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
    --skip-aiken-check)
      SKIP_AIKEN_CHECK=1
      shift
      ;;
    --skip-preflight)
      SKIP_PREFLIGHT=1
      shift
      ;;
    --strict)
      STRICT_RUN=1
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

if [[ "$STRICT_RUN" == "1" && "$SKIP_PREFLIGHT" == "1" ]]; then
  echo "--strict and --skip-preflight are mutually exclusive" >&2
  exit 1
fi

resolve_binary_path AIKEN_BIN "Aiken binary" AIKEN_BIN aiken || exit 1
resolve_binary_path \
  BASH_BIN \
  "Bash binary" \
  BASH_BIN \
  bash \
  "${BASH:-}" \
  /opt/homebrew/bin/bash \
  /usr/local/bin/bash \
  /bin/bash \
  /usr/bin/bash || exit 1
print_resolved_binary_if_verbose "Aiken binary" "$AIKEN_BIN"
print_resolved_binary_if_verbose "Bash binary" "$BASH_BIN"
export_resolved_toolchain_env

"$WORKSPACE_CHECK_SCRIPT" --flow run
"$TOOLING_CHECK_SCRIPT" --flow run

if [[ "$CLEAN_RUN" == "1" ]]; then
  reset_run_dir "$OUTPUT_DIR"
else
  ensure_run_dir "$OUTPUT_DIR"
fi

setup_run_log_dir "$OUTPUT_DIR"
setup_flow_observability "$OUTPUT_DIR" "run"
trap 'run_exit=$?; if [[ "$run_exit" -eq 0 ]]; then finalize_flow_success; else finalize_flow_failure "$run_exit"; fi' EXIT

if [[ -z "$PROOF_EXPORT_BUNDLE_PATH" ]]; then
  RUNTIME_PROOF_EXPORT_BUNDLE_PATH="$OUTPUT_DIR/bridge-compatible-mithril-stm-bundle.json"
  if [[ "$RESUME_RUN" == "1" ]]; then
    if [[ ! -f "$RUNTIME_PROOF_EXPORT_BUNDLE_PATH" ]]; then
      echo "Cannot resume PoC run; missing canonical bundle at: $RUNTIME_PROOF_EXPORT_BUNDLE_PATH" >&2
      exit 1
    fi
    echo "==> Resuming with canonical bridge-compatible Mithril STM bundle"
  else
    begin_stage "Ensuring canonical bridge-compatible Mithril STM bundle"
    BRIDGE_LOG_DIR="$BRIDGE_LOG_DIR" "$BUILD_PROOF_EXPORT_BUNDLE_SCRIPT" "$RUNTIME_PROOF_EXPORT_BUNDLE_PATH"
  fi
else
  PROOF_EXPORT_BUNDLE_PATH="$(cd "$(dirname "$PROOF_EXPORT_BUNDLE_PATH")" && pwd)/$(basename "$PROOF_EXPORT_BUNDLE_PATH")"
  RUNTIME_PROOF_EXPORT_BUNDLE_PATH="$PROOF_EXPORT_BUNDLE_PATH"
fi

if [[ ! -f "$RUNTIME_PROOF_EXPORT_BUNDLE_PATH" ]]; then
  echo "Missing Mithril STM runtime bundle at: $RUNTIME_PROOF_EXPORT_BUNDLE_PATH" >&2
  exit 1
fi

cd "$ROOT_DIR"

run_preflight_stage() {
  begin_stage "Running Mithril PoC preflight"
  local preflight_args=(--proof-export-bundle "$RUNTIME_PROOF_EXPORT_BUNDLE_PATH" --output-dir "$OUTPUT_DIR")
  if [[ "$CLEAN_RUN" == "1" ]]; then
    preflight_args+=(--clean)
  fi
  if [[ "$RESUME_RUN" == "1" ]]; then
    preflight_args+=(--resume)
  fi
  BRIDGE_SKIP_FLOW_CHECKS=1 "$PREFLIGHT_SCRIPT" "${preflight_args[@]}"
}

# In strict mode the preflight is pinned to the front of the pipeline,
# so any contract or fixture drift is caught before `aiken check` or
# the bridge flow run.
if [[ "$STRICT_RUN" == "1" ]]; then
  run_preflight_stage
fi

if [[ "$SKIP_AIKEN_CHECK" != "1" ]]; then
  begin_stage "Running aiken check"
  run_aiken_check_logged
else
  skip_stage "Running aiken check" "--skip-aiken-check"
fi

if [[ "$STRICT_RUN" != "1" ]]; then
  if [[ "$SKIP_PREFLIGHT" != "1" ]]; then
    run_preflight_stage
  else
    skip_stage "Running Mithril PoC preflight" "--skip-preflight"
  fi
fi

begin_stage "Running full Mithril PoC bridge flow"
BRIDGE_MINTING_RUN_DIR="${BRIDGE_MINTING_RUN_DIR:-$OUTPUT_DIR/bridge-minting}" \
PROOF_EXPORT_BUNDLE_PATH="$RUNTIME_PROOF_EXPORT_BUNDLE_PATH" \
BRIDGE_SKIP_FLOW_CHECKS=1 \
  "$BRIDGE_MINTING_SCRIPT"

echo "Runtime Mithril STM bundle: $RUNTIME_PROOF_EXPORT_BUNDLE_PATH"
