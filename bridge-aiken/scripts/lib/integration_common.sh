FLOW_OBSERVABILITY_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/flow_observability.sh"

# shellcheck disable=SC1090
source "$FLOW_OBSERVABILITY_SCRIPT"

BRIDGE_FLOW_VERBOSE="${BRIDGE_FLOW_VERBOSE:-0}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

run_logged() {
  local label="$1"
  shift

  if [[ "$BRIDGE_FLOW_VERBOSE" == "1" ]]; then
    "$@"
    return
  fi

  local log_path
  if [[ -n "${BRIDGE_LOG_DIR:-}" ]]; then
    log_path="$(mktemp_in_dir "$BRIDGE_LOG_DIR" "bridge-flow-${label// /-}.XXXXXX.log")"
  else
    log_path="$(mktemp_in_dir "${TMPDIR:-/tmp}" "bridge-flow-${label// /-}.XXXXXX.log")"
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

print_mithril_bundle_summary() {
  local bundle_path="$1"

  if [[ -z "$bundle_path" ]] || [[ ! -f "$bundle_path" ]]; then
    return
  fi

  local source_id
  local statement_hash
  local child_signed_message

  source_id="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$bundle_path" source_bundle.source_id 2>/dev/null || echo unknown)"
  statement_hash="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$bundle_path" statement.statement_hash 2>/dev/null || echo unknown)"
  child_signed_message="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$bundle_path" certificates.child.signed_message 2>/dev/null || echo unknown)"

  echo "Bundle path:      $bundle_path"
  echo "Bundle source_id: $source_id"
  echo "Bundle statement: $statement_hash"
  echo "Child signed msg: $child_signed_message"
}

print_failure_context() {
  local script_name="$1"
  local exit_code="$2"

  echo "Flow failed in $script_name" >&2
  echo "Last stage: ${CURRENT_STAGE:-unknown}" >&2

  if [[ -n "${PROOF_EXPORT_BUNDLE_PATH:-}" ]]; then
    echo "Bundle path: $PROOF_EXPORT_BUNDLE_PATH" >&2
  fi

  if [[ -n "${BUNDLE_SOURCE_ID:-}" ]]; then
    echo "Bundle source_id: $BUNDLE_SOURCE_ID" >&2
  fi

  if [[ -n "${BUNDLE_STATEMENT_HASH:-}" ]]; then
    echo "Bundle statement_hash: $BUNDLE_STATEMENT_HASH" >&2
  fi

  if [[ -n "${PHASE2_RECEIPT_STATEMENT_HASH:-}" ]]; then
    echo "Live phase2 receipt statement_hash: $PHASE2_RECEIPT_STATEMENT_HASH" >&2
  fi

  if [[ -n "${TX3_SESSION_ENV_PATH:-}" ]]; then
    echo "Requested session manifest: $TX3_SESSION_ENV_PATH" >&2
  fi

  if [[ -n "${SESSION_ENV_PATH:-}" ]]; then
    echo "Session manifest: $SESSION_ENV_PATH" >&2
  fi

  if [[ -n "${TMP_DIR:-}" ]]; then
    echo "Temporary directory: $TMP_DIR" >&2
  fi

  if [[ -n "${DOLOS_LOG_PATH:-}" && -f "${DOLOS_LOG_PATH:-}" ]]; then
    echo "Dolos log: $DOLOS_LOG_PATH" >&2
  fi

  if [[ -n "${LAST_FAILED_COMMAND_LABEL:-}" ]]; then
    echo "Failed command label: $LAST_FAILED_COMMAND_LABEL" >&2
  fi

  if [[ -n "${LAST_FAILED_COMMAND:-}" ]]; then
    echo "Failed command: $LAST_FAILED_COMMAND" >&2
  fi

  if [[ -n "${LAST_FAILED_COMMAND_LOG_PATH:-}" && -f "${LAST_FAILED_COMMAND_LOG_PATH:-}" ]]; then
    echo "Failed command log: $LAST_FAILED_COMMAND_LOG_PATH" >&2
  fi

  if [[ -n "${FLOW_STAGE_TRACE_PATH:-}" && -f "${FLOW_STAGE_TRACE_PATH:-}" ]]; then
    echo "Stage trace: $FLOW_STAGE_TRACE_PATH" >&2
  fi

  if [[ -n "${FLOW_DEBUG_CONTEXT_PATH:-}" && -f "${FLOW_DEBUG_CONTEXT_PATH:-}" ]]; then
    echo "Debug context: $FLOW_DEBUG_CONTEXT_PATH" >&2
  fi

  echo "Exit code: $exit_code" >&2
}

print_tx_publish_summary() {
  local label="$1"
  local result_path="$2"
  shift 2

  "$PYTHON_BIN" "$TX_PUBLISH_SUMMARY_PY" \
    "$label" \
    "$result_path" \
    "${BOB_REFERENCE_INPUT_LOVELACE:-10000000}" \
    "$@"
}

reference_script_output_index() {
  local result_path="$1"

  "$PYTHON_BIN" - "$result_path" <<'PY'
import cbor2
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as infile:
    result = json.load(infile)

tx = cbor2.loads(bytes.fromhex(result["cbor"]))
outputs = tx[0][1]

for index, output in enumerate(outputs):
    if isinstance(output, dict) and 3 in output:
        print(index)
        break
else:
    raise SystemExit("publish tx did not contain a reference-script output")
PY
}

cshell_tx_invoke() {
  local tx_template="$1"
  local args_file="$2"
  local output_path="$3"
  shift 3

  local tii_file
  tii_file="$(resolve_tx3_tii_file)"

  "$CSHELL_BIN" tx invoke \
    --tii-file "$tii_file" \
    --store-path "$STORE_PATH" \
    --provider trix-local \
    --signers bob \
    --unsafe \
    --tx-template "$tx_template" \
    --args-file "$args_file" \
    "$@" \
    -o json > "$output_path"
}

resolve_tx3_tii_file() {
  local flat_tii=".tx3/tii/main.tii"
  local namespaced_tii=""

  namespaced_tii="$(
    find .tx3/tii -type f -name main.tii ! -path "./.tx3/tii/main.tii" 2>/dev/null \
      | sort \
      | head -n 1
  )"

  if [[ -n "$namespaced_tii" ]]; then
    printf '%s\n' "$namespaced_tii"
  else
    printf '%s\n' "$flat_tii"
  fi
}

cshell_tx_submit() {
  local cbor="$1"
  local output_path="$2"

  "$CSHELL_BIN" tx submit \
    --store-path "$STORE_PATH" \
    --provider trix-local \
    -o json \
    "$cbor" > "$output_path"
}

cshell_tx_sign() {
  local cbor="$1"
  local output_path="$2"
  local signer="${3:-bob}"

  "$CSHELL_BIN" tx sign \
    --store-path "$STORE_PATH" \
    --signer "$signer" \
    --unsafe \
    -o json \
    "$cbor" > "$output_path"
}
