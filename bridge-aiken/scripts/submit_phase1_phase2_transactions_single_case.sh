#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC_SCRIPT="$ROOT_DIR/scripts/sync_phase_scripts_to_tx3.sh"
BUILD_PROOF_EXPORT_BUNDLE_SCRIPT="$ROOT_DIR/scripts/build_bridge_compatible_mithril_stm_proof_export_bundle.sh"
COMMON_SCRIPT="$ROOT_DIR/scripts/lib/integration_common.sh"
RUN_OUTPUTS_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/run_outputs_common.sh"
TOOLING_CHECK_SCRIPT="$ROOT_DIR/scripts/check_local_tooling.sh"
WORKSPACE_CHECK_SCRIPT="$ROOT_DIR/scripts/check_workspace_layout.sh"
TOOLING_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/tooling_common.sh"
DOLOS_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/dolos_common.sh"
GUARDRAILS_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/guardrails_common.sh"
ENTRYPOINT_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/entrypoint_common.sh"
FLOW_OBSERVABILITY_SCRIPT="$ROOT_DIR/scripts/lib/flow_observability.sh"
PYTHON_DIR="$ROOT_DIR/scripts/python"
READ_JSON_FIELD_PY="$PYTHON_DIR/read_json_field.py"
PREPARE_TX3_DOLOS_ENV_PY="$PYTHON_DIR/prepare_tx3_dolos_env.py"
BOOTSTRAP_TX3_SCAFFOLDING_PY="$PYTHON_DIR/bootstrap_tx3_scaffolding.py"
TX_PUBLISH_SUMMARY_PY="$PYTHON_DIR/tx_publish_summary.py"
SET_JSON_FIELD_PY="$PYTHON_DIR/set_json_field.py"
BUILD_SUBMIT_RESULT_PY="$PYTHON_DIR/build_submit_result.py"

EXPECTED_PHASE1_HASH="${EXPECTED_PHASE1_HASH:-}"
EXPECTED_PHASE2_HASH="${EXPECTED_PHASE2_HASH:-}"
USER_ADDRESS="${USER_ADDRESS:-addr_test1vqxazu4ekxrxlk238wt0e03h3gk44hrlkjvef85gvh2nahcgnmpfc}"
PHASE1_STATEMENT_HASH_VALUE="${PHASE1_STATEMENT_HASH_VALUE:-}"
PHASE2_PROOF_RECEIPT_STATEMENT_HASH="${PHASE2_PROOF_RECEIPT_STATEMENT_HASH:-}"
PROOF_EXPORT_BUNDLE_PATH="${PROOF_EXPORT_BUNDLE_PATH:-}"
KEEP_TX3_DOLOS_RUNNING="${KEEP_TX3_DOLOS_RUNNING:-0}"
KEEP_TX3_DOLOS_TMP="${KEEP_TX3_DOLOS_TMP:-1}"
BRIDGE_VERBOSE_CONTEXT="${BRIDGE_VERBOSE_CONTEXT:-phase12-runtime}"
PHASE12_SKIP_SYNC="${PHASE12_SKIP_SYNC:-0}"
SUPPRESS_BUNDLE_SUMMARY="${SUPPRESS_BUNDLE_SUMMARY:-0}"
SUPPRESS_SESSION_MANIFEST_MSG="${SUPPRESS_SESSION_MANIFEST_MSG:-0}"
PHASE12_PROOF_NAME="${PHASE12_PROOF_NAME:-}"
PHASE12_REUSE_RUNNING_DOLOS="${PHASE12_REUSE_RUNNING_DOLOS:-0}"
SHARED_PHASE1_REFERENCE_SCRIPT_RESULT_PATH="${SHARED_PHASE1_REFERENCE_SCRIPT_RESULT_PATH:-}"
SHARED_PHASE1_REFERENCE_SCRIPT_UTXO="${SHARED_PHASE1_REFERENCE_SCRIPT_UTXO:-}"
BRIDGE_SKIP_FLOW_CHECKS="${BRIDGE_SKIP_FLOW_CHECKS:-0}"

if [[ "$PHASE12_PROOF_NAME" == "stake_distribution_genesis" ]]; then
  echo "stake_distribution_genesis no longer has a phase1/phase2 lane." >&2
  echo "Use the Aiken-native stake_distribution_genesis_tx path instead." >&2
  exit 1
fi

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

handoff_to_wrapper_if_direct "$ROOT_DIR/scripts/bridge.sh" phase12 "$@"

PHASE12_RUN_DIR="${PHASE12_RUN_DIR:-$(default_flow_run_dir phase12)}"
ensure_run_dir "$PHASE12_RUN_DIR"
setup_run_log_dir "$PHASE12_RUN_DIR"
setup_flow_observability "$PHASE12_RUN_DIR" "phase12${PHASE12_PROOF_NAME:+-$PHASE12_PROOF_NAME}"
TMP_DIR="$PHASE12_RUN_DIR"
TX3_SESSION_ENV_PATH="${TX3_SESSION_ENV_PATH:-$TMP_DIR/session.env}"
PHASE12_RUNTIME_BUNDLE_DIR="$TMP_DIR/runtime-proof-export-bundle"
PHASE12_RUNTIME_BUNDLE_PATH="$PHASE12_RUNTIME_BUNDLE_DIR/bridge-compatible-mithril-stm-bundle.json"

GRPC_PORT="${BRIDGE_TX3_GRPC_PORT:-55164}"
TRP_PORT="${BRIDGE_TX3_TRP_PORT:-58164}"
MINIBF_PORT="${BRIDGE_TX3_MINIBF_PORT:-53164}"

STORE_PATH="$TMP_DIR/cshell.toml"
SHELLEY_PATH="$TMP_DIR/shelley.json"
DOLOS_CONFIG_PATH="$TMP_DIR/dolos.toml"
DOLOS_LOG_PATH="$TMP_DIR/dolos.log"
PUBLISH_PHASE1_REFERENCE_SCRIPT_ARGS_PATH="$TMP_DIR/publish-phase1-reference-script-args.json"
PUBLISH_PHASE1_REFERENCE_SCRIPT_RESULT_PATH="$TMP_DIR/publish-phase1-reference-script-submit.json"
PHASE1_ARGS_PATH="$TMP_DIR/phase1-args.json"
PHASE2_ARGS_PATH="$TMP_DIR/phase2-args.json"
PHASE1_RESULT_PATH="$TMP_DIR/phase1-submit.json"
PHASE2_SKIP_PATH="$TMP_DIR/phase2-skip.json"
PHASE2_RESULT_PATH="$TMP_DIR/phase2-submit.json"
PHASE2_SUBMIT_PATH="$TMP_DIR/phase2-submit-response.json"

DOLOS_PID=""
DOLOS_STARTED_BY_SCRIPT=0
BOB_REFERENCE_INPUT_LOVELACE="${BOB_REFERENCE_INPUT_LOVELACE:-10000000}"
BOB_STABLE_COLLATERAL_UTXO_A="${BOB_STABLE_COLLATERAL_UTXO_A:-8d910e3a410a353787d50a708e24c6ba2cc2b6b86ec6d8cb5bf9bbec20bfc937#0}"
BOB_STABLE_SOURCE_UTXO_A="${BOB_STABLE_SOURCE_UTXO_A:-3d930cc9415a0221ff96f4ce00dd0732ee9d692e3b6231b4dbbda540469cf761#0}"
BOB_STABLE_PUBLISH_SOURCE_UTXO_A="${BOB_STABLE_PUBLISH_SOURCE_UTXO_A:-3d930cc9415a0221ff96f4ce00dd0732ee9d692e3b6231b4dbbda540469cf764#0}"
CURRENT_STAGE="initializing"
BUNDLE_SOURCE_ID=""
BUNDLE_STATEMENT_HASH=""

# shellcheck disable=SC1090
source "$COMMON_SCRIPT"

cleanup() {
  local exit_code="$1"
  local keep_running=0

  if [[ "$exit_code" -ne 0 ]]; then
    finalize_flow_failure "$exit_code"
    print_failure_context "phase1/phase2 flow" "$exit_code"
  else
    finalize_flow_success
  fi

  if [[ "$exit_code" -eq 0 ]] && [[ "$KEEP_TX3_DOLOS_RUNNING" == "1" ]]; then
    keep_running=1
  fi

  if [[ "$DOLOS_STARTED_BY_SCRIPT" -eq 1 ]] && [[ "$keep_running" -ne 1 ]] && [[ -n "$DOLOS_PID" ]] && kill -0 "$DOLOS_PID" 2>/dev/null; then
    kill "$DOLOS_PID" 2>/dev/null || true
    wait "$DOLOS_PID" 2>/dev/null || true
  fi

  if [[ "$exit_code" -eq 0 ]] && [[ "$KEEP_TX3_DOLOS_TMP" != "1" ]] && [[ "$keep_running" -ne 1 ]]; then
    rm -rf "$TMP_DIR"
  else
    echo "Run directory kept at: $TMP_DIR"
    if [[ -f "$DOLOS_LOG_PATH" ]]; then
      echo "Dolos log: $DOLOS_LOG_PATH"
    fi
  fi
}

trap 'cleanup $?' EXIT

ensure_run_dir "$TMP_DIR"

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

run_flow_guardrails "phase12" "$WORKSPACE_CHECK_SCRIPT" "$TOOLING_CHECK_SCRIPT"

if [[ ! -x "$SYNC_SCRIPT" ]]; then
  echo "Missing sync script at: $SYNC_SCRIPT" >&2
  exit 1
fi

cd "$ROOT_DIR"

echo "==> Ensuring local Tx3 scaffolding"
DOLOS_DEVNET_DIR="$DOLOS_DEVNET_DIR" "$PYTHON_BIN" "$BOOTSTRAP_TX3_SCAFFOLDING_PY"

if [[ -n "$PROOF_EXPORT_BUNDLE_PATH" ]] && [[ "$SUPPRESS_BUNDLE_SUMMARY" != "1" ]]; then
  BUNDLE_SOURCE_ID="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$PROOF_EXPORT_BUNDLE_PATH" source_bundle.source_id)"
  if [[ -n "$PHASE12_PROOF_NAME" ]]; then
    BUNDLE_STATEMENT_HASH="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$PROOF_EXPORT_BUNDLE_PATH" "proofs.${PHASE12_PROOF_NAME}.statement.statement_hash")"
  else
    BUNDLE_STATEMENT_HASH="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$PROOF_EXPORT_BUNDLE_PATH" statement.statement_hash)"
  fi
  begin_stage "Mithril bundle summary"
  print_mithril_bundle_summary "$PROOF_EXPORT_BUNDLE_PATH"
fi

if [[ "$PHASE12_SKIP_SYNC" == "1" ]]; then
  skip_stage "Syncing Aiken scripts into main.tx3" "shared sync already prepared"
else
  begin_stage "Syncing Aiken scripts into main.tx3"
  SYNC_SCOPE=phase12 "$SYNC_SCRIPT"
fi

if [[ -n "$PROOF_EXPORT_BUNDLE_PATH" ]]; then
  begin_stage "Refreshing runtime Mithril bundle for synced phase12 state"
  "$BUILD_PROOF_EXPORT_BUNDLE_SCRIPT" "$PHASE12_RUNTIME_BUNDLE_PATH"
  PROOF_EXPORT_BUNDLE_PATH="$PHASE12_RUNTIME_BUNDLE_PATH"
  if [[ -n "$PHASE12_PROOF_NAME" ]]; then
    BUNDLE_STATEMENT_HASH="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$PROOF_EXPORT_BUNDLE_PATH" "proofs.${PHASE12_PROOF_NAME}.statement.statement_hash")"
  else
    BUNDLE_STATEMENT_HASH="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$PROOF_EXPORT_BUNDLE_PATH" statement.statement_hash)"
  fi
fi

cp .tx3/dolos/shelley.json "$SHELLEY_PATH"

PREPARE_TX3_DOLOS_ENV_ARGS=(
  "$ROOT_DIR"
  "$TMP_DIR"
  "$USER_ADDRESS"
  "$GRPC_PORT"
  "$TRP_PORT"
  "$MINIBF_PORT"
)

if [[ -n "$PROOF_EXPORT_BUNDLE_PATH" ]]; then
  echo "Using Mithril STM proof-export bundle: $PROOF_EXPORT_BUNDLE_PATH"
  PREPARE_TX3_DOLOS_ENV_ARGS+=(--mithril-stm-proof-export-bundle "$PROOF_EXPORT_BUNDLE_PATH")
  if [[ -n "$PHASE12_PROOF_NAME" ]]; then
    PREPARE_TX3_DOLOS_ENV_ARGS+=(--proof-name "$PHASE12_PROOF_NAME")
  fi
fi

"$PYTHON_BIN" "$PREPARE_TX3_DOLOS_ENV_PY" "${PREPARE_TX3_DOLOS_ENV_ARGS[@]}"

if [[ "$PHASE12_REUSE_RUNNING_DOLOS" == "1" ]]; then
  skip_stage "Starting patched Dolos on ports grpc=$GRPC_PORT trp=$TRP_PORT" "reusing already running Dolos"
else
  free_port "$GRPC_PORT"
  free_port "$TRP_PORT"
  free_port "$MINIBF_PORT"

  if [[ "${BRIDGE_FLOW_VERBOSE:-0}" == "1" ]]; then
    begin_stage "Starting patched Dolos on ports grpc=$GRPC_PORT trp=$TRP_PORT"
  fi
  RUST_LOG="${RUST_LOG:-info}" "$DOLOS_BIN" daemon -c "$DOLOS_CONFIG_PATH" >"$DOLOS_LOG_PATH" 2>&1 &
  DOLOS_PID="$!"
  DOLOS_STARTED_BY_SCRIPT=1
fi

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

if [[ -n "$SHARED_PHASE1_REFERENCE_SCRIPT_RESULT_PATH" ]] && [[ -n "$SHARED_PHASE1_REFERENCE_SCRIPT_UTXO" ]]; then
  skip_stage "Submitting publish_phase1_reference_script" "reusing shared phase1 reference script UTxO"
  PUBLISH_PHASE1_REFERENCE_SCRIPT_RESULT_PATH="$SHARED_PHASE1_REFERENCE_SCRIPT_RESULT_PATH"
  PHASE1_REFERENCE_SCRIPT_UTXO="$SHARED_PHASE1_REFERENCE_SCRIPT_UTXO"
  PUBLISH_PHASE1_REFERENCE_SCRIPT_HASH="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$PUBLISH_PHASE1_REFERENCE_SCRIPT_RESULT_PATH" hash)"
  PUBLISH_PHASE1_REFERENCE_SCRIPT_OUTPUT_INDEX="${PHASE1_REFERENCE_SCRIPT_UTXO##*#}"
else
  "$PYTHON_BIN" "$SET_JSON_FIELD_PY" "$PUBLISH_PHASE1_REFERENCE_SCRIPT_ARGS_PATH" source_utxo "$BOB_STABLE_PUBLISH_SOURCE_UTXO_A"
  begin_stage "Submitting publish_phase1_reference_script"
  cshell_tx_invoke \
    publish_phase1_reference_script \
    "$PUBLISH_PHASE1_REFERENCE_SCRIPT_ARGS_PATH" \
    "$PUBLISH_PHASE1_REFERENCE_SCRIPT_RESULT_PATH"

  PUBLISH_PHASE1_REFERENCE_SCRIPT_HASH="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$PUBLISH_PHASE1_REFERENCE_SCRIPT_RESULT_PATH" hash)"
  PUBLISH_PHASE1_REFERENCE_SCRIPT_OUTPUT_INDEX="$(reference_script_output_index "$PUBLISH_PHASE1_REFERENCE_SCRIPT_RESULT_PATH")"
  PHASE1_REFERENCE_SCRIPT_UTXO="${PUBLISH_PHASE1_REFERENCE_SCRIPT_HASH}#${PUBLISH_PHASE1_REFERENCE_SCRIPT_OUTPUT_INDEX}"
fi

"$PYTHON_BIN" "$SET_JSON_FIELD_PY" "$PHASE1_ARGS_PATH" phase1_reference_script_utxo "$PHASE1_REFERENCE_SCRIPT_UTXO"
"$PYTHON_BIN" "$SET_JSON_FIELD_PY" "$PHASE1_ARGS_PATH" collateral_utxo "$BOB_STABLE_COLLATERAL_UTXO_A"
"$PYTHON_BIN" "$SET_JSON_FIELD_PY" "$PHASE1_ARGS_PATH" source_utxo "$BOB_STABLE_SOURCE_UTXO_A"

if [[ -z "$SHARED_PHASE1_REFERENCE_SCRIPT_RESULT_PATH" ]]; then
  print_tx_publish_summary "publish_phase1_reference_script" "$PUBLISH_PHASE1_REFERENCE_SCRIPT_RESULT_PATH"
fi

begin_stage "Submitting phase1_setup"
cshell_tx_invoke \
  phase1_setup \
  "$PHASE1_ARGS_PATH" \
  "$PHASE1_RESULT_PATH"

PHASE1_HASH="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$PHASE1_RESULT_PATH" hash)"
PHASE2_LOCKED_UTXO="${PHASE1_HASH}#0"
PHASE2_SOURCE_UTXO="${PHASE1_HASH}#1"

"$PYTHON_BIN" "$SET_JSON_FIELD_PY" "$PHASE2_ARGS_PATH" phase2_locked_utxo "$PHASE2_LOCKED_UTXO"
"$PYTHON_BIN" "$SET_JSON_FIELD_PY" "$PHASE2_ARGS_PATH" source_utxo "$PHASE2_SOURCE_UTXO"
"$PYTHON_BIN" "$SET_JSON_FIELD_PY" "$PHASE2_ARGS_PATH" collateral_utxo "$BOB_STABLE_COLLATERAL_UTXO_A"

if [[ -n "$EXPECTED_PHASE1_HASH" ]] && [[ "$PHASE1_HASH" != "$EXPECTED_PHASE1_HASH" ]]; then
  echo "Unexpected phase1 hash: $PHASE1_HASH" >&2
  echo "Expected: $EXPECTED_PHASE1_HASH" >&2
  exit 1
fi

print_tx_publish_summary "phase1_setup" "$PHASE1_RESULT_PATH" "$PUBLISH_PHASE1_REFERENCE_SCRIPT_RESULT_PATH"

begin_stage "Prebuilding phase2_verify"
cshell_tx_invoke \
  phase2_verify \
  "$PHASE2_ARGS_PATH" \
  "$PHASE2_SKIP_PATH" \
  --skip-submit

print_tx_publish_summary "phase2_verify" "$PHASE2_SKIP_PATH" "$PHASE1_RESULT_PATH"

begin_stage "Submitting phase2_verify"
cshell_tx_submit \
  "$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$PHASE2_SKIP_PATH" cbor)" \
  "$PHASE2_SUBMIT_PATH"

"$PYTHON_BIN" "$BUILD_SUBMIT_RESULT_PY" \
  "$PHASE2_SKIP_PATH" \
  "$PHASE2_SUBMIT_PATH" \
  "$PHASE2_RESULT_PATH"

PHASE2_HASH="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$PHASE2_RESULT_PATH" hash)"

if [[ -n "$EXPECTED_PHASE2_HASH" ]] && [[ "$PHASE2_HASH" != "$EXPECTED_PHASE2_HASH" ]]; then
  echo "Unexpected phase2 hash: $PHASE2_HASH" >&2
  echo "Expected: $EXPECTED_PHASE2_HASH" >&2
  exit 1
fi

if [[ -n "$TX3_SESSION_ENV_PATH" ]]; then
  mkdir -p "$(dirname "$TX3_SESSION_ENV_PATH")"
  cat >"$TX3_SESSION_ENV_PATH" <<EOF
ROOT_DIR=$(printf '%q' "$ROOT_DIR")
TMP_DIR=$(printf '%q' "$TMP_DIR")
USER_ADDRESS=$(printf '%q' "$USER_ADDRESS")
STORE_PATH=$(printf '%q' "$STORE_PATH")
SHELLEY_PATH=$(printf '%q' "$SHELLEY_PATH")
DOLOS_CONFIG_PATH=$(printf '%q' "$DOLOS_CONFIG_PATH")
DOLOS_LOG_PATH=$(printf '%q' "$DOLOS_LOG_PATH")
PUBLISH_PHASE1_REFERENCE_SCRIPT_ARGS_PATH=$(printf '%q' "$PUBLISH_PHASE1_REFERENCE_SCRIPT_ARGS_PATH")
PUBLISH_PHASE1_REFERENCE_SCRIPT_RESULT_PATH=$(printf '%q' "$PUBLISH_PHASE1_REFERENCE_SCRIPT_RESULT_PATH")
PHASE1_ARGS_PATH=$(printf '%q' "$PHASE1_ARGS_PATH")
PHASE2_ARGS_PATH=$(printf '%q' "$PHASE2_ARGS_PATH")
PHASE1_RESULT_PATH=$(printf '%q' "$PHASE1_RESULT_PATH")
PHASE2_SKIP_PATH=$(printf '%q' "$PHASE2_SKIP_PATH")
PHASE2_RESULT_PATH=$(printf '%q' "$PHASE2_RESULT_PATH")
PHASE2_SUBMIT_PATH=$(printf '%q' "$PHASE2_SUBMIT_PATH")
PUBLISH_PHASE1_REFERENCE_SCRIPT_HASH=$(printf '%q' "$PUBLISH_PHASE1_REFERENCE_SCRIPT_HASH")
PUBLISH_PHASE1_REFERENCE_SCRIPT_OUTPUT_INDEX=$(printf '%q' "$PUBLISH_PHASE1_REFERENCE_SCRIPT_OUTPUT_INDEX")
PHASE1_REFERENCE_SCRIPT_UTXO=$(printf '%q' "$PHASE1_REFERENCE_SCRIPT_UTXO")
PHASE1_HASH=$(printf '%q' "$PHASE1_HASH")
PHASE2_HASH=$(printf '%q' "$PHASE2_HASH")
PHASE12_PROOF_NAME=$(printf '%q' "$PHASE12_PROOF_NAME")
GRPC_PORT=$(printf '%q' "$GRPC_PORT")
TRP_PORT=$(printf '%q' "$TRP_PORT")
MINIBF_PORT=$(printf '%q' "$MINIBF_PORT")
DOLOS_PID=$(printf '%q' "$DOLOS_PID")
EOF
  append_effective_toolchain_manifest "$TX3_SESSION_ENV_PATH"
  if [[ -n "$PHASE12_PROOF_NAME" ]]; then
    PHASE12_PROOF_NAME_ENV_SUFFIX="$(printf '%s' "$PHASE12_PROOF_NAME" | tr '[:lower:]-' '[:upper:]_')"
    cat >>"$TX3_SESSION_ENV_PATH" <<EOF
PHASE1_HASH_${PHASE12_PROOF_NAME_ENV_SUFFIX}=$(printf '%q' "$PHASE1_HASH")
PHASE2_HASH_${PHASE12_PROOF_NAME_ENV_SUFFIX}=$(printf '%q' "$PHASE2_HASH")
PHASE2_RECEIPT_UTXO_${PHASE12_PROOF_NAME_ENV_SUFFIX}=$(printf '%q' "${PHASE2_HASH}#0")
STATEMENT_HASH_${PHASE12_PROOF_NAME_ENV_SUFFIX}=$(printf '%q' "$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$PHASE2_ARGS_PATH" proof_receipt_statement_hash)")
PUBLISH_PHASE1_REFERENCE_SCRIPT_RESULT_PATH_${PHASE12_PROOF_NAME_ENV_SUFFIX}=$(printf '%q' "$PUBLISH_PHASE1_REFERENCE_SCRIPT_RESULT_PATH")
PHASE1_RESULT_PATH_${PHASE12_PROOF_NAME_ENV_SUFFIX}=$(printf '%q' "$PHASE1_RESULT_PATH")
PHASE2_RESULT_PATH_${PHASE12_PROOF_NAME_ENV_SUFFIX}=$(printf '%q' "$PHASE2_RESULT_PATH")
EOF
  fi
  if [[ "$SUPPRESS_SESSION_MANIFEST_MSG" != "1" ]]; then
    echo "Session manifest written to: $TX3_SESSION_ENV_PATH"
  fi
fi

echo "Integration test passed."
echo "publish_phase1_reference_script hash: $PUBLISH_PHASE1_REFERENCE_SCRIPT_HASH"
echo "phase1_setup hash:                    $PHASE1_HASH"
echo "phase2_verify hash:                   $PHASE2_HASH"
