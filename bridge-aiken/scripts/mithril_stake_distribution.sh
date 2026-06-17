#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PHASE12_SCRIPT="$ROOT_DIR/scripts/submit_phase1_phase2_transactions.sh"
SYNC_SCRIPT="$ROOT_DIR/scripts/sync_phase_scripts_to_tx3.sh"
COMMON_SCRIPT="$ROOT_DIR/scripts/lib/integration_common.sh"
RUN_OUTPUTS_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/run_outputs_common.sh"
TOOLING_CHECK_SCRIPT="$ROOT_DIR/scripts/check_local_tooling.sh"
WORKSPACE_CHECK_SCRIPT="$ROOT_DIR/scripts/check_workspace_layout.sh"
TOOLING_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/tooling_common.sh"
GUARDRAILS_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/guardrails_common.sh"
ENTRYPOINT_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/entrypoint_common.sh"
FLOW_OBSERVABILITY_SCRIPT="$ROOT_DIR/scripts/lib/flow_observability.sh"
SESSION_MANIFEST_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/session_manifest_common.sh"
SESSION_MANIFEST_CHECK_SCRIPT="$ROOT_DIR/scripts/check_session_manifest.sh"
PYTHON_DIR="$ROOT_DIR/scripts/python"
PREPARE_MITHRIL_SD_ARGS_PY="$PYTHON_DIR/prepare_mithril_stake_distribution_args.py"
READ_JSON_FIELD_PY="$PYTHON_DIR/read_json_field.py"
SET_JSON_FIELD_PY="$PYTHON_DIR/set_json_field.py"
TX_PUBLISH_SUMMARY_PY="$PYTHON_DIR/tx_publish_summary.py"
PHASE1_RAW_ARGS_PATH="$ROOT_DIR/scripts/data/phase1_args_raw.json"
ENV_DEFAULT_PATH="$ROOT_DIR/env/default.ak"
MAIN_TX3_PATH="$ROOT_DIR/main.tx3"
BRIDGE_VERBOSE_CONTEXT="${BRIDGE_VERBOSE_CONTEXT:-stake-distribution-runtime}"

KEEP_MITHRIL_STAKE_DISTRIBUTION_TMP="${KEEP_MITHRIL_STAKE_DISTRIBUTION_TMP:-1}"
KEEP_MITHRIL_STAKE_DISTRIBUTION_DOLOS_RUNNING="${KEEP_MITHRIL_STAKE_DISTRIBUTION_DOLOS_RUNNING:-0}"
STAKE_DISTRIBUTION_OUTPUT_LOVELACE="${STAKE_DISTRIBUTION_OUTPUT_LOVELACE:-3000000}"
SD_STANDARD_RECEIPT_UTXO="${SD_STANDARD_RECEIPT_UTXO:-}"
EXPECTED_STAKE_DISTRIBUTION_GENESIS_HASH="${EXPECTED_STAKE_DISTRIBUTION_GENESIS_HASH:-}"
EXPECTED_STAKE_DISTRIBUTION_STANDARD_HASH="${EXPECTED_STAKE_DISTRIBUTION_STANDARD_HASH:-}"
TX3_SESSION_ENV_PATH="${TX3_SESSION_ENV_PATH:-}"
PROOF_EXPORT_BUNDLE_PATH="${PROOF_EXPORT_BUNDLE_PATH:-}"
STAKE_DISTRIBUTION_SKIP_SYNC="${STAKE_DISTRIBUTION_SKIP_SYNC:-0}"
PHASE12_SKIP_SYNC="${PHASE12_SKIP_SYNC:-0}"
SUPPRESS_BUNDLE_SUMMARY="${SUPPRESS_BUNDLE_SUMMARY:-0}"
SUPPRESS_SESSION_MANIFEST_MSG="${SUPPRESS_SESSION_MANIFEST_MSG:-0}"
BRIDGE_SKIP_FLOW_CHECKS="${BRIDGE_SKIP_FLOW_CHECKS:-0}"

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
# shellcheck disable=SC1090
source "$SESSION_MANIFEST_COMMON_SCRIPT"

handoff_to_wrapper_if_direct "$ROOT_DIR/scripts/bridge.sh" stake-distribution "$@"

STAKE_DISTRIBUTION_RUN_DIR="${STAKE_DISTRIBUTION_RUN_DIR:-$(default_flow_run_dir stake-distribution)}"
ensure_run_dir "$STAKE_DISTRIBUTION_RUN_DIR"
setup_run_log_dir "$STAKE_DISTRIBUTION_RUN_DIR"
setup_flow_observability "$STAKE_DISTRIBUTION_RUN_DIR" "stake-distribution"
SESSION_ENV_PATH="${TX3_SESSION_ENV_PATH:-$STAKE_DISTRIBUTION_RUN_DIR/session.env}"
ENV_DEFAULT_BACKUP_PATH="$STAKE_DISTRIBUTION_RUN_DIR/env-default.backup.ak"
MAIN_TX3_BACKUP_PATH="$STAKE_DISTRIBUTION_RUN_DIR/main.tx3.backup"
DOLOS_PID=""
TMP_DIR=""
BOB_REFERENCE_INPUT_LOVELACE="${BOB_REFERENCE_INPUT_LOVELACE:-10000000}"
BOB_STABLE_COLLATERAL_UTXO_A="${BOB_STABLE_COLLATERAL_UTXO_A:-8d910e3a410a353787d50a708e24c6ba2cc2b6b86ec6d8cb5bf9bbec20bfc937#0}"
BOB_STABLE_STAKE_DISTRIBUTION_STANDARD_COLLATERAL_UTXO_A="${BOB_STABLE_STAKE_DISTRIBUTION_STANDARD_COLLATERAL_UTXO_A:-8d910e3a410a353787d50a708e24c6ba2cc2b6b86ec6d8cb5bf9bbec20bfc93a#0}"
BOB_STABLE_STAKE_DISTRIBUTION_GENESIS_SOURCE_UTXO_A="${BOB_STABLE_STAKE_DISTRIBUTION_GENESIS_SOURCE_UTXO_A:-3d930cc9415a0221ff96f4ce00dd0732ee9d692e3b6231b4dbbda540469cf765#0}"
BOB_STABLE_STAKE_DISTRIBUTION_STANDARD_SOURCE_UTXO_A="${BOB_STABLE_STAKE_DISTRIBUTION_STANDARD_SOURCE_UTXO_A:-${BOB_STABLE_STAKE_DISTRIBUTION_SOURCE_UTXO_A:-3d930cc9415a0221ff96f4ce00dd0732ee9d692e3b6231b4dbbda540469cf766#0}}"
BLOCK_PRODUCTION_WAIT_SECS="${BLOCK_PRODUCTION_WAIT_SECS:-6}"
CURRENT_STAGE="initializing"
BUNDLE_SOURCE_ID=""
BUNDLE_STATEMENT_HASH=""

cleanup() {
  local exit_code="$1"

  if [[ "$exit_code" -ne 0 ]]; then
    finalize_flow_failure "$exit_code"
    print_failure_context "stake_distribution flow" "$exit_code"
  else
    finalize_flow_success
  fi

  if [[ -f "$ENV_DEFAULT_BACKUP_PATH" ]]; then
    restore_file_from_backup "$ENV_DEFAULT_BACKUP_PATH" "$ENV_DEFAULT_PATH" || true
  fi

  if [[ -f "$MAIN_TX3_BACKUP_PATH" ]]; then
    restore_file_from_backup "$MAIN_TX3_BACKUP_PATH" "$MAIN_TX3_PATH" || true
  fi

  if [[ "$KEEP_MITHRIL_STAKE_DISTRIBUTION_DOLOS_RUNNING" != "1" ]] && [[ -n "$DOLOS_PID" ]] && kill -0 "$DOLOS_PID" 2>/dev/null; then
    kill "$DOLOS_PID" 2>/dev/null || true
    wait "$DOLOS_PID" 2>/dev/null || true
  fi

  if [[ "$KEEP_MITHRIL_STAKE_DISTRIBUTION_TMP" != "1" ]] && [[ -n "$TMP_DIR" ]] && [[ -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  elif [[ -n "$TMP_DIR" ]] && [[ -d "$TMP_DIR" ]]; then
    echo "Run directory kept at: $TMP_DIR"
  fi

  exit "$exit_code"
}

trap 'cleanup $?' EXIT

# shellcheck disable=SC1090
source "$COMMON_SCRIPT"

run_flow_guardrails "stake-distribution" "$WORKSPACE_CHECK_SCRIPT" "$TOOLING_CHECK_SCRIPT"

resolve_binary_path PYTHON_BIN "Python 3 binary" PYTHON_BIN python3 "$ROOT_DIR/.venv/bin/python" || exit 1
print_resolved_binary_if_verbose "Python 3 binary" "$PYTHON_BIN"
export_resolved_toolchain_env

if [[ ! -f "$PHASE12_SCRIPT" ]]; then
  echo "Missing phase1/phase2-all script at: $PHASE12_SCRIPT" >&2
  exit 1
fi

cd "$ROOT_DIR"
ensure_run_dir "$STAKE_DISTRIBUTION_RUN_DIR"
backup_file_to_path "$ENV_DEFAULT_PATH" "$ENV_DEFAULT_BACKUP_PATH"
backup_file_to_path "$MAIN_TX3_PATH" "$MAIN_TX3_BACKUP_PATH"

if [[ -n "$PROOF_EXPORT_BUNDLE_PATH" ]] && [[ "$SUPPRESS_BUNDLE_SUMMARY" != "1" ]]; then
  BUNDLE_SOURCE_ID="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$PROOF_EXPORT_BUNDLE_PATH" source_bundle.source_id)"
  BUNDLE_STATEMENT_HASH="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$PROOF_EXPORT_BUNDLE_PATH" statement.statement_hash)"
  begin_stage "Proof-export bundle summary"
  print_mithril_bundle_summary "$PROOF_EXPORT_BUNDLE_PATH"
fi

begin_stage "Running phase1/phase2 multi-proof setup"
if [[ -n "$PROOF_EXPORT_BUNDLE_PATH" ]]; then
  echo "Using Mithril STM proof-export bundle for phase1/phase2 multi-proof setup: $PROOF_EXPORT_BUNDLE_PATH"
  PHASE12_ALL_RUN_DIR="${PHASE12_ALL_RUN_DIR:-$STAKE_DISTRIBUTION_RUN_DIR/phase12-all}" \
  PROOF_EXPORT_BUNDLE_PATH="$PROOF_EXPORT_BUNDLE_PATH" \
  PHASE12_SKIP_SYNC="$PHASE12_SKIP_SYNC" \
  SUPPRESS_BUNDLE_SUMMARY=1 \
  SUPPRESS_SESSION_MANIFEST_MSG=1 \
  BRIDGE_SKIP_FLOW_CHECKS=1 \
  KEEP_TX3_DOLOS_RUNNING=1 \
  KEEP_TX3_DOLOS_TMP=1 \
  TX3_SESSION_ENV_PATH="$SESSION_ENV_PATH" \
  bash "$PHASE12_SCRIPT"
else
  echo "The stake-distribution flow now requires a Mithril STM proof-export bundle to materialize the remaining Halo2 proof domains." >&2
  exit 1
fi

if [[ ! -f "$SESSION_ENV_PATH" ]]; then
  echo "The phase1/phase2 script did not produce a session manifest." >&2
  exit 1
fi

"$SESSION_MANIFEST_CHECK_SCRIPT" --mode phase12-all --file "$SESSION_ENV_PATH"

# shellcheck disable=SC1090
source "$SESSION_ENV_PATH"

require_session_manifest_var "$SESSION_ENV_PATH" TMP_DIR "writing stake-distribution args and submit artifacts"
require_session_manifest_var "$SESSION_ENV_PATH" DOLOS_PID "reusing the running Dolos instance from phase12-all"
require_session_manifest_var "$SESSION_ENV_PATH" PHASE2_HASH_STAKE_DISTRIBUTION_STANDARD "building the standard stake-distribution transaction"

SD_STANDARD_RECEIPT_UTXO="${SD_STANDARD_RECEIPT_UTXO:-${PHASE2_RECEIPT_UTXO_STAKE_DISTRIBUTION_STANDARD:-}}"

require_session_manifest_utxo "$SESSION_ENV_PATH" SD_STANDARD_RECEIPT_UTXO "consuming the standard phase2 proof receipt in stake-distribution"

if [[ "${BRIDGE_FLOW_VERBOSE:-0}" == "1" ]]; then
  begin_stage "Waiting for phase2 receipts to become spendable"
fi
sleep "$BLOCK_PRODUCTION_WAIT_SECS"

if [[ "$STAKE_DISTRIBUTION_SKIP_SYNC" == "1" ]]; then
  skip_stage "Syncing Aiken/Tx3 artifacts for stake_distribution" "shared sync already prepared"
else
  begin_stage "Syncing Aiken/Tx3 artifacts for stake_distribution"
  SYNC_SCOPE=stake_distribution "$SYNC_SCRIPT"
fi

SD_GENESIS_ARGS_PATH="$TMP_DIR/stake-distribution-genesis-args.json"
SD_STANDARD_ARGS_PATH="$TMP_DIR/stake-distribution-standard-args.json"
SD_STANDARD_PHASE2_RESULT_PATH="${PHASE2_RESULT_PATH_STAKE_DISTRIBUTION_STANDARD:-${PHASE12_ALL_RUN_DIR:-$STAKE_DISTRIBUTION_RUN_DIR/phase12-all}/stake_distribution_standard/phase2-submit.json}"
SD_GENESIS_RESULT_PATH="$TMP_DIR/stake-distribution-genesis-submit.json"
SD_STANDARD_SKIP_PATH="$TMP_DIR/stake-distribution-standard-skip.json"
SD_STANDARD_RESULT_PATH="$TMP_DIR/stake-distribution-standard-submit.json"
SD_STANDARD_RECEIPT_STATEMENT_HASH="${STATEMENT_HASH_STAKE_DISTRIBUTION_STANDARD:-}"

require_session_manifest_var "$SESSION_ENV_PATH" SD_STANDARD_RECEIPT_STATEMENT_HASH "preparing the standard stake-distribution args JSON"

if [[ "${BRIDGE_FLOW_VERBOSE:-0}" == "1" ]]; then
  begin_stage "Preparing stake-distribution args"
fi
PREPARE_MITHRIL_SD_ARGS_CMD=(
  "$PYTHON_BIN" "$PREPARE_MITHRIL_SD_ARGS_PY"
  "$SD_GENESIS_ARGS_PATH"
  "$SD_STANDARD_ARGS_PATH"
  "$USER_ADDRESS"
  "$SD_STANDARD_RECEIPT_STATEMENT_HASH"
  "$STAKE_DISTRIBUTION_OUTPUT_LOVELACE"
  "$SD_STANDARD_RECEIPT_UTXO"
  "$BOB_STABLE_STAKE_DISTRIBUTION_GENESIS_SOURCE_UTXO_A"
)
if [[ -n "$PROOF_EXPORT_BUNDLE_PATH" ]]; then
  PREPARE_MITHRIL_SD_ARGS_CMD+=(--proof-export-bundle "$PROOF_EXPORT_BUNDLE_PATH")
fi
"${PREPARE_MITHRIL_SD_ARGS_CMD[@]}"

"$PYTHON_BIN" "$SET_JSON_FIELD_PY" "$SD_GENESIS_ARGS_PATH" source_utxo "$BOB_STABLE_STAKE_DISTRIBUTION_GENESIS_SOURCE_UTXO_A"
"$PYTHON_BIN" "$SET_JSON_FIELD_PY" "$SD_STANDARD_ARGS_PATH" source_utxo "$BOB_STABLE_STAKE_DISTRIBUTION_STANDARD_SOURCE_UTXO_A"
"$PYTHON_BIN" "$SET_JSON_FIELD_PY" "$SD_GENESIS_ARGS_PATH" collateral_utxo "$BOB_STABLE_COLLATERAL_UTXO_A"

begin_stage "Submitting stake_distribution_genesis_tx"
cshell_tx_invoke \
  stake_distribution_genesis_tx \
  "$SD_GENESIS_ARGS_PATH" \
  "$SD_GENESIS_RESULT_PATH"

STAKE_DISTRIBUTION_GENESIS_HASH="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$SD_GENESIS_RESULT_PATH" hash)"

if [[ -n "$EXPECTED_STAKE_DISTRIBUTION_GENESIS_HASH" ]] && [[ "$STAKE_DISTRIBUTION_GENESIS_HASH" != "$EXPECTED_STAKE_DISTRIBUTION_GENESIS_HASH" ]]; then
  echo "Unexpected stake_distribution_genesis_tx hash: $STAKE_DISTRIBUTION_GENESIS_HASH" >&2
  echo "Expected: $EXPECTED_STAKE_DISTRIBUTION_GENESIS_HASH" >&2
  exit 1
fi

PARENT_CERTIFICATE_UTXO="${STAKE_DISTRIBUTION_GENESIS_HASH}#0"
"$PYTHON_BIN" "$SET_JSON_FIELD_PY" "$SD_STANDARD_ARGS_PATH" parent_certificate_utxo "$PARENT_CERTIFICATE_UTXO"
"$PYTHON_BIN" "$SET_JSON_FIELD_PY" "$SD_STANDARD_ARGS_PATH" collateral_utxo "$BOB_STABLE_STAKE_DISTRIBUTION_STANDARD_COLLATERAL_UTXO_A"

begin_stage "Submitting stake_distribution_standard_tx"
cshell_tx_invoke \
  stake_distribution_standard_tx \
  "$SD_STANDARD_ARGS_PATH" \
  "$SD_STANDARD_RESULT_PATH"

STAKE_DISTRIBUTION_STANDARD_HASH="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$SD_STANDARD_RESULT_PATH" hash)"

if [[ -n "$EXPECTED_STAKE_DISTRIBUTION_STANDARD_HASH" ]] && [[ "$STAKE_DISTRIBUTION_STANDARD_HASH" != "$EXPECTED_STAKE_DISTRIBUTION_STANDARD_HASH" ]]; then
  echo "Unexpected stake_distribution_standard_tx hash: $STAKE_DISTRIBUTION_STANDARD_HASH" >&2
  echo "Expected: $EXPECTED_STAKE_DISTRIBUTION_STANDARD_HASH" >&2
  exit 1
fi

print_tx_publish_summary "stake_distribution_standard_tx" "$SD_STANDARD_RESULT_PATH" "$SD_GENESIS_RESULT_PATH" "$SD_STANDARD_PHASE2_RESULT_PATH"
print_tx_publish_summary "stake_distribution_genesis_tx" "$SD_GENESIS_RESULT_PATH"

sleep "$BLOCK_PRODUCTION_WAIT_SECS"

if [[ -n "$TX3_SESSION_ENV_PATH" ]]; then
  mkdir -p "$(dirname "$TX3_SESSION_ENV_PATH")"
  if [[ "$SESSION_ENV_PATH" != "$TX3_SESSION_ENV_PATH" ]]; then
    cat "$SESSION_ENV_PATH" >"$TX3_SESSION_ENV_PATH"
  fi
  cat >>"$TX3_SESSION_ENV_PATH" <<EOF
SD_GENESIS_ARGS_PATH=$(printf '%q' "$SD_GENESIS_ARGS_PATH")
SD_STANDARD_ARGS_PATH=$(printf '%q' "$SD_STANDARD_ARGS_PATH")
SD_GENESIS_RESULT_PATH=$(printf '%q' "$SD_GENESIS_RESULT_PATH")
SD_STANDARD_RESULT_PATH=$(printf '%q' "$SD_STANDARD_RESULT_PATH")
STAKE_DISTRIBUTION_GENESIS_HASH=$(printf '%q' "$STAKE_DISTRIBUTION_GENESIS_HASH")
STAKE_DISTRIBUTION_STANDARD_HASH=$(printf '%q' "$STAKE_DISTRIBUTION_STANDARD_HASH")
PARENT_CERTIFICATE_UTXO=$(printf '%q' "$PARENT_CERTIFICATE_UTXO")
SD_STANDARD_RECEIPT_UTXO=$(printf '%q' "$SD_STANDARD_RECEIPT_UTXO")
SD_STANDARD_RECEIPT_STATEMENT_HASH=$(printf '%q' "$SD_STANDARD_RECEIPT_STATEMENT_HASH")
EOF
  append_effective_toolchain_manifest "$TX3_SESSION_ENV_PATH"
  persist_mithril_aggregator_fingerprint "$STAKE_DISTRIBUTION_RUN_DIR" "$TX3_SESSION_ENV_PATH"
  if [[ "$SUPPRESS_SESSION_MANIFEST_MSG" != "1" ]]; then
    echo "Session manifest written to: $TX3_SESSION_ENV_PATH"
  fi
fi

if [[ -n "$TX3_SESSION_ENV_PATH" ]]; then
  "$SESSION_MANIFEST_CHECK_SCRIPT" --mode stake-distribution --file "$TX3_SESSION_ENV_PATH"
fi

echo "Mithril stake-distribution flow passed."
echo "phase2_verify standard hash:       $PHASE2_HASH_STAKE_DISTRIBUTION_STANDARD"
echo "stake_distribution_genesis_tx:     $STAKE_DISTRIBUTION_GENESIS_HASH"
echo "stake_distribution_standard_tx:    $STAKE_DISTRIBUTION_STANDARD_HASH"
