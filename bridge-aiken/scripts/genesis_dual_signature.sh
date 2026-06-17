#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_DIR="$(cd "$ROOT_DIR/.." && pwd)"
SYNC_SCRIPT="$ROOT_DIR/scripts/sync_phase_scripts_to_tx3.sh"
COMMON_SCRIPT="$ROOT_DIR/scripts/lib/integration_common.sh"
RUN_OUTPUTS_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/run_outputs_common.sh"
TOOLING_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/tooling_common.sh"
DOLOS_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/dolos_common.sh"
GUARDRAILS_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/guardrails_common.sh"
ENTRYPOINT_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/entrypoint_common.sh"
FLOW_OBSERVABILITY_SCRIPT="$ROOT_DIR/scripts/lib/flow_observability.sh"
SESSION_MANIFEST_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/session_manifest_common.sh"
SESSION_MANIFEST_CHECK_SCRIPT="$ROOT_DIR/scripts/check_session_manifest.sh"
GENESIS_DUAL_PREFLIGHT_SCRIPT="$ROOT_DIR/scripts/preflight_genesis_dual_signature.sh"
PYTHON_DIR="$ROOT_DIR/scripts/python"
PREPARE_TX3_DOLOS_ENV_PY="$PYTHON_DIR/prepare_tx3_dolos_env.py"
BOOTSTRAP_TX3_SCAFFOLDING_PY="$PYTHON_DIR/bootstrap_tx3_scaffolding.py"
PREPARE_ARGS_PY="$PYTHON_DIR/prepare_genesis_dual_signature_args.py"
READ_JSON_FIELD_PY="$PYTHON_DIR/read_json_field.py"
SET_JSON_FIELD_PY="$PYTHON_DIR/set_json_field.py"
TX_PUBLISH_SUMMARY_PY="$PYTHON_DIR/tx_publish_summary.py"
GENESIS_DUAL_FIXTURE_PATH="$ROOT_DIR/scripts/data/jubjub_schnorr_preview_genesis_raw.json"
BRIDGE_VERBOSE_CONTEXT="${BRIDGE_VERBOSE_CONTEXT:-genesis-dual-signature-runtime}"

KEEP_GENESIS_DUAL_SIGNATURE_TMP="${KEEP_GENESIS_DUAL_SIGNATURE_TMP:-1}"
KEEP_GENESIS_DUAL_SIGNATURE_DOLOS_RUNNING="${KEEP_GENESIS_DUAL_SIGNATURE_DOLOS_RUNNING:-0}"
GENESIS_DUAL_SIGNATURE_SKIP_SYNC="${GENESIS_DUAL_SIGNATURE_SKIP_SYNC:-0}"
GENESIS_DUAL_SIGNATURE_SKIP_PREFLIGHT="${GENESIS_DUAL_SIGNATURE_SKIP_PREFLIGHT:-0}"
BRIDGE_SKIP_FLOW_CHECKS="${BRIDGE_SKIP_FLOW_CHECKS:-0}"
SUPPRESS_SESSION_MANIFEST_MSG="${SUPPRESS_SESSION_MANIFEST_MSG:-0}"
STAKE_DISTRIBUTION_OUTPUT_LOVELACE="${STAKE_DISTRIBUTION_OUTPUT_LOVELACE:-3000000}"
EXPECTED_STAKE_DISTRIBUTION_GENESIS_HASH="${EXPECTED_STAKE_DISTRIBUTION_GENESIS_HASH:-}"
TX3_SESSION_ENV_PATH="${TX3_SESSION_ENV_PATH:-}"
USER_ADDRESS="${USER_ADDRESS:-addr_test1vqxazu4ekxrxlk238wt0e03h3gk44hrlkjvef85gvh2nahcgnmpfc}"

# shellcheck disable=SC1090
source "$RUN_OUTPUTS_COMMON_SCRIPT"
# shellcheck disable=SC1090
source "$TOOLING_COMMON_SCRIPT"
# shellcheck disable=SC1090
source "$DOLOS_COMMON_SCRIPT"
# shellcheck disable=SC1090
source "$GUARDRAILS_COMMON_SCRIPT"
# shellcheck disable=SC1090
source "$FLOW_OBSERVABILITY_SCRIPT"
# shellcheck disable=SC1090
source "$ENTRYPOINT_COMMON_SCRIPT"
# shellcheck disable=SC1090
source "$SESSION_MANIFEST_COMMON_SCRIPT"

handoff_to_wrapper_if_direct "$ROOT_DIR/scripts/bridge.sh" genesis_dual_signature "$@"

RUN_DIR="${GENESIS_DUAL_SIGNATURE_RUN_DIR:-$(default_flow_run_dir genesis-dual-signature)}"
OUTPUT_DIR="$RUN_DIR"
DO_PRELIGHT=1

usage() {
  cat <<'EOF'
usage: genesis_dual_signature.sh [--output-dir <dir>] [--skip-preflight]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="$2"
      RUN_DIR="$2"
      shift 2
      ;;
    --skip-preflight)
      DO_PRELIGHT=0
      shift
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

if [[ "$GENESIS_DUAL_SIGNATURE_SKIP_PREFLIGHT" == "1" ]]; then
  DO_PRELIGHT=0
fi

ensure_run_dir "$OUTPUT_DIR"
setup_run_log_dir "$OUTPUT_DIR"
setup_flow_observability "$OUTPUT_DIR" "genesis-dual-signature"
SESSION_ENV_PATH="${TX3_SESSION_ENV_PATH:-$OUTPUT_DIR/session.env}"
ENV_DEFAULT_BACKUP_PATH="$OUTPUT_DIR/env-default.backup.ak"
MAIN_TX3_BACKUP_PATH="$OUTPUT_DIR/main.tx3.backup"
TMP_DIR="$OUTPUT_DIR"

GRPC_PORT="${BRIDGE_TX3_GRPC_PORT:-55174}"
TRP_PORT="${BRIDGE_TX3_TRP_PORT:-58174}"
MINIBF_PORT="${BRIDGE_TX3_MINIBF_PORT:-53174}"

STORE_PATH="$TMP_DIR/cshell.toml"
SHELLEY_PATH="$TMP_DIR/shelley.json"
DOLOS_CONFIG_PATH="$TMP_DIR/dolos.toml"
DOLOS_LOG_PATH="$TMP_DIR/dolos.log"
GENESIS_DUAL_ARGS_PATH="$TMP_DIR/genesis-dual-signature-args.json"
GENESIS_DUAL_RESULT_PATH="$TMP_DIR/genesis-dual-signature-submit.json"
DOLOS_PID=""
DOLOS_STARTED_BY_SCRIPT=0
BOB_REFERENCE_INPUT_LOVELACE="${BOB_REFERENCE_INPUT_LOVELACE:-10000000}"
BOB_STABLE_COLLATERAL_UTXO_A="${BOB_STABLE_COLLATERAL_UTXO_A:-8d910e3a410a353787d50a708e24c6ba2cc2b6b86ec6d8cb5bf9bbec20bfc937#0}"
BOB_STABLE_STAKE_DISTRIBUTION_GENESIS_SOURCE_UTXO_A="${BOB_STABLE_STAKE_DISTRIBUTION_GENESIS_SOURCE_UTXO_A:-3d930cc9415a0221ff96f4ce00dd0732ee9d692e3b6231b4dbbda540469cf765#0}"

CURRENT_STAGE="initializing"

# shellcheck disable=SC1090
source "$COMMON_SCRIPT"

cleanup() {
  local exit_code="$1"

  if [[ "$exit_code" -ne 0 ]]; then
    finalize_flow_failure "$exit_code"
    print_failure_context "genesis_dual_signature flow" "$exit_code"
  else
    finalize_flow_success
  fi

  if [[ -f "$ENV_DEFAULT_BACKUP_PATH" ]]; then
    restore_file_from_backup "$ENV_DEFAULT_BACKUP_PATH" "$ROOT_DIR/env/default.ak" || true
  fi

  if [[ -f "$MAIN_TX3_BACKUP_PATH" ]]; then
    restore_file_from_backup "$MAIN_TX3_BACKUP_PATH" "$ROOT_DIR/main.tx3" || true
  fi

  if [[ "$KEEP_GENESIS_DUAL_SIGNATURE_DOLOS_RUNNING" != "1" ]] && [[ -n "$DOLOS_PID" ]] && kill -0 "$DOLOS_PID" 2>/dev/null; then
    kill "$DOLOS_PID" 2>/dev/null || true
    wait "$DOLOS_PID" 2>/dev/null || true
  fi

  if [[ "$KEEP_GENESIS_DUAL_SIGNATURE_TMP" != "1" ]] && [[ -n "$TMP_DIR" ]] && [[ -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  elif [[ -n "$TMP_DIR" ]] && [[ -d "$TMP_DIR" ]]; then
    echo "Run directory kept at: $TMP_DIR"
  fi
}

trap 'cleanup $?' EXIT

free_port() {
  local port="$1"
  local pids=""

  pids="$(list_listening_pids_for_port "$port")"
  if [[ -z "$pids" ]]; then
    return
  fi

  echo "==> Releasing port $port from existing listener(s): $pids"
  kill $pids 2>/dev/null || true
  sleep 1
}

trp_ready() {
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${TRP_PORT}" || true)"
  [[ "$code" == "200" || "$code" == "400" || "$code" == "404" || "$code" == "405" ]]
}

resolve_binary_path PYTHON_BIN "Python 3 binary" PYTHON_BIN python3 "$ROOT_DIR/.venv/bin/python" || exit 1
resolve_binary_path AIKEN_BIN "Aiken binary" AIKEN_BIN aiken || exit 1
resolve_binary_path CARGO_BIN "Cargo binary" CARGO_BIN cargo || exit 1
resolve_binary_path TRIX_BIN "trix binary" TRIX_BIN trix "$ROOT_DIR/.tools/bin/trix" "$ROOT_DIR/.tools/trix" || exit 1
resolve_binary_path CSHELL_BIN "CShell binary" CSHELL_BIN cshell "$ROOT_DIR/.tools/bin/cshell" "$ROOT_DIR/.tools/cshell" || exit 1
init_dolos_layout "$ROOT_DIR"
resolve_dolos_binary || exit 1
maybe_build_sibling_dolos "$CARGO_BIN" || exit 1
print_resolved_binary_if_verbose "Python 3 binary" "$PYTHON_BIN"
print_resolved_binary_if_verbose "Aiken binary" "$AIKEN_BIN"
print_resolved_binary_if_verbose "Cargo binary" "$CARGO_BIN"
print_resolved_binary_if_verbose "trix binary" "$TRIX_BIN"
print_resolved_binary_if_verbose "CShell binary" "$CSHELL_BIN"
print_dolos_resolution_if_verbose
export_resolved_toolchain_env

command -v curl >/dev/null 2>&1 || { echo "Missing required command: curl" >&2; exit 1; }
if ! command -v lsof >/dev/null 2>&1 && ! command -v ss >/dev/null 2>&1; then
  echo "Missing required port-inspection command: lsof or ss" >&2
  exit 1
fi

run_flow_guardrails "genesis-dual-signature" "$ROOT_DIR/scripts/check_workspace_layout.sh" "$ROOT_DIR/scripts/check_local_tooling.sh"

cd "$ROOT_DIR"
backup_file_to_path "$ROOT_DIR/env/default.ak" "$ENV_DEFAULT_BACKUP_PATH"
backup_file_to_path "$ROOT_DIR/main.tx3" "$MAIN_TX3_BACKUP_PATH"

if [[ "$DO_PRELIGHT" == "1" ]]; then
  begin_stage "Running genesis dual-signature preflight"
  BRIDGE_SKIP_FLOW_CHECKS=1 "$GENESIS_DUAL_PREFLIGHT_SCRIPT" --output-dir "$OUTPUT_DIR/preflight"
else
  skip_stage "Running genesis dual-signature preflight" "--skip-preflight"
fi

if [[ "$GENESIS_DUAL_SIGNATURE_SKIP_SYNC" == "1" ]]; then
  skip_stage "Syncing Aiken/Tx3 artifacts for genesis_dual_signature" "explicitly skipped"
else
  begin_stage "Syncing Aiken/Tx3 artifacts for genesis_dual_signature"
  SYNC_SCOPE=stake_distribution "$SYNC_SCRIPT"
fi

begin_stage "Ensuring local Tx3 scaffolding"
DOLOS_DEVNET_DIR="$DOLOS_DEVNET_DIR" "$PYTHON_BIN" "$BOOTSTRAP_TX3_SCAFFOLDING_PY"

cp .tx3/dolos/shelley.json "$SHELLEY_PATH"
"$PYTHON_BIN" "$PREPARE_TX3_DOLOS_ENV_PY" \
  "$ROOT_DIR" \
  "$TMP_DIR" \
  "$USER_ADDRESS" \
  "$GRPC_PORT" \
  "$TRP_PORT" \
  "$MINIBF_PORT"

free_port "$GRPC_PORT"
free_port "$TRP_PORT"
free_port "$MINIBF_PORT"

begin_stage "Starting patched Dolos on ports grpc=$GRPC_PORT trp=$TRP_PORT"
RUST_LOG="${RUST_LOG:-info}" "$DOLOS_BIN" daemon -c "$DOLOS_CONFIG_PATH" >"$DOLOS_LOG_PATH" 2>&1 &
DOLOS_PID="$!"
DOLOS_STARTED_BY_SCRIPT=1

for _ in $(seq 1 60); do
  if curl -fsS "http://localhost:${GRPC_PORT}/u5c" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -fsS "http://localhost:${GRPC_PORT}/u5c" >/dev/null 2>&1; then
  echo "Dolos did not become ready in time." >&2
  exit 1
fi

for _ in $(seq 1 60); do
  if trp_ready; then
    break
  fi
  sleep 1
done

if ! trp_ready; then
  echo "Dolos TRP did not become ready in time." >&2
  exit 1
fi

begin_stage "Preparing genesis dual-signature args"
"$PYTHON_BIN" "$PREPARE_ARGS_PY" \
  "$GENESIS_DUAL_ARGS_PATH" \
  "$USER_ADDRESS" \
  "$STAKE_DISTRIBUTION_OUTPUT_LOVELACE" \
  "$BOB_STABLE_STAKE_DISTRIBUTION_GENESIS_SOURCE_UTXO_A" \
  "$BOB_STABLE_COLLATERAL_UTXO_A"

begin_stage "Submitting stake_distribution_genesis_tx"
cshell_tx_invoke \
  stake_distribution_dual_genesis_tx \
  "$GENESIS_DUAL_ARGS_PATH" \
  "$GENESIS_DUAL_RESULT_PATH"

STAKE_DISTRIBUTION_GENESIS_HASH="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$GENESIS_DUAL_RESULT_PATH" hash)"

if [[ -n "$EXPECTED_STAKE_DISTRIBUTION_GENESIS_HASH" ]] && [[ "$STAKE_DISTRIBUTION_GENESIS_HASH" != "$EXPECTED_STAKE_DISTRIBUTION_GENESIS_HASH" ]]; then
  echo "Unexpected stake_distribution_genesis_tx hash: $STAKE_DISTRIBUTION_GENESIS_HASH" >&2
  echo "Expected: $EXPECTED_STAKE_DISTRIBUTION_GENESIS_HASH" >&2
  exit 1
fi

print_tx_publish_summary "stake_distribution_genesis_tx" "$GENESIS_DUAL_RESULT_PATH"

mkdir -p "$(dirname "$SESSION_ENV_PATH")"
cat >"$SESSION_ENV_PATH" <<EOF
ROOT_DIR=$(printf '%q' "$ROOT_DIR")
TMP_DIR=$(printf '%q' "$TMP_DIR")
USER_ADDRESS=$(printf '%q' "$USER_ADDRESS")
STORE_PATH=$(printf '%q' "$STORE_PATH")
SHELLEY_PATH=$(printf '%q' "$SHELLEY_PATH")
DOLOS_CONFIG_PATH=$(printf '%q' "$DOLOS_CONFIG_PATH")
DOLOS_LOG_PATH=$(printf '%q' "$DOLOS_LOG_PATH")
GENESIS_DUAL_ARGS_PATH=$(printf '%q' "$GENESIS_DUAL_ARGS_PATH")
GENESIS_DUAL_RESULT_PATH=$(printf '%q' "$GENESIS_DUAL_RESULT_PATH")
GENESIS_DUAL_FIXTURE_PATH=$(printf '%q' "$GENESIS_DUAL_FIXTURE_PATH")
STAKE_DISTRIBUTION_GENESIS_HASH=$(printf '%q' "$STAKE_DISTRIBUTION_GENESIS_HASH")
GRPC_PORT=$(printf '%q' "$GRPC_PORT")
TRP_PORT=$(printf '%q' "$TRP_PORT")
MINIBF_PORT=$(printf '%q' "$MINIBF_PORT")
DOLOS_PID=$(printf '%q' "$DOLOS_PID")
EOF
append_effective_toolchain_manifest "$SESSION_ENV_PATH"

if [[ "$SUPPRESS_SESSION_MANIFEST_MSG" != "1" ]]; then
  echo "Session manifest written to: $SESSION_ENV_PATH"
fi

"$SESSION_MANIFEST_CHECK_SCRIPT" --mode genesis-dual-signature --file "$SESSION_ENV_PATH"

echo "Genesis dual-signature flow passed."
echo "stake_distribution_genesis_tx hash: $STAKE_DISTRIBUTION_GENESIS_HASH"
