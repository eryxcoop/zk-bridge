flow_now_epoch() {
  date +%s
}

flow_now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

flow_sanitize_label() {
  printf '%s' "$1" | tr '[:space:]/:' '---' | tr -cd '[:alnum:]_.-'
}

flow_append_event() {
  local status="$1"
  local label="$2"
  local detail="${3:-}"
  local duration_secs="${4:-}"

  if [[ -z "${FLOW_STAGE_TRACE_PATH:-}" ]]; then
    return
  fi

  mkdir -p "$(dirname "$FLOW_STAGE_TRACE_PATH")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(flow_now_iso)" \
    "${FLOW_NAME:-unknown}" \
    "$status" \
    "$label" \
    "$duration_secs" \
    "$detail" >>"$FLOW_STAGE_TRACE_PATH"
}

setup_flow_observability() {
  local run_dir="$1"
  local flow_name="$2"

  FLOW_NAME="$flow_name"
  FLOW_STAGE_TRACE_PATH="$run_dir/stage-trace.log"
  FLOW_DEBUG_CONTEXT_PATH="$run_dir/debug-context.log"
  CURRENT_STAGE="${CURRENT_STAGE:-initializing}"
  CURRENT_STAGE_ACTIVE=0
  CURRENT_STAGE_STARTED_AT=""
  export FLOW_NAME FLOW_STAGE_TRACE_PATH FLOW_DEBUG_CONTEXT_PATH CURRENT_STAGE CURRENT_STAGE_ACTIVE CURRENT_STAGE_STARTED_AT

  mkdir -p "$run_dir"
  {
    printf '# flow=%s started_at=%s\n' "$FLOW_NAME" "$(flow_now_iso)"
    printf '# columns: timestamp\tflow\tstatus\tlabel\tduration_secs\tdetail\n'
  } >>"$FLOW_STAGE_TRACE_PATH"
  {
    printf '# flow=%s started_at=%s\n' "$FLOW_NAME" "$(flow_now_iso)"
    printf '# context log for resolved toolchain, logs and artifacts\n'
  } >>"$FLOW_DEBUG_CONTEXT_PATH"
}

record_debug_context() {
  local label="$1"
  local value="${2:-}"

  if [[ -z "${FLOW_DEBUG_CONTEXT_PATH:-}" ]]; then
    return
  fi

  mkdir -p "$(dirname "$FLOW_DEBUG_CONTEXT_PATH")"
  printf '%s\t%s\t%s\n' "$(flow_now_iso)" "$label" "$value" >>"$FLOW_DEBUG_CONTEXT_PATH"
}

set_last_command_failure_context() {
  LAST_FAILED_COMMAND_LABEL="${1:-}"
  LAST_FAILED_COMMAND="${2:-}"
  LAST_FAILED_COMMAND_LOG_PATH="${3:-}"
  export LAST_FAILED_COMMAND_LABEL LAST_FAILED_COMMAND LAST_FAILED_COMMAND_LOG_PATH
  record_debug_context "failed-command-label" "$LAST_FAILED_COMMAND_LABEL"
  record_debug_context "failed-command" "$LAST_FAILED_COMMAND"
  record_debug_context "failed-command-log" "$LAST_FAILED_COMMAND_LOG_PATH"
}

finish_current_stage() {
  local status="${1:-done}"
  local detail="${2:-}"

  if [[ "${CURRENT_STAGE_ACTIVE:-0}" != "1" ]]; then
    return
  fi

  local now duration
  now="$(flow_now_epoch)"
  duration=$((now - CURRENT_STAGE_STARTED_AT))
  flow_append_event "$status" "$CURRENT_STAGE" "$detail" "$duration"
  CURRENT_STAGE_ACTIVE=0
  CURRENT_STAGE_STARTED_AT=""
}

begin_stage() {
  local label="$1"
  local detail="${2:-}"

  if [[ "${CURRENT_STAGE_ACTIVE:-0}" == "1" ]]; then
    finish_current_stage "done"
  fi

  CURRENT_STAGE="$label"
  CURRENT_STAGE_STARTED_AT="$(flow_now_epoch)"
  CURRENT_STAGE_ACTIVE=1
  export CURRENT_STAGE CURRENT_STAGE_STARTED_AT CURRENT_STAGE_ACTIVE

  echo "==> $label"
  flow_append_event "start" "$label" "$detail" ""
}

skip_stage() {
  local label="$1"
  local detail="${2:-}"

  if [[ "${CURRENT_STAGE_ACTIVE:-0}" == "1" && "${CURRENT_STAGE:-}" == "$label" ]]; then
    echo "==> Skipping $label${detail:+ ($detail)}"
    finish_current_stage "skip" "$detail"
    return
  fi

  echo "==> Skipping $label${detail:+ ($detail)}"
  flow_append_event "skip" "$label" "$detail" "0"
}

note_stage_detail() {
  local label="$1"
  local detail="$2"
  flow_append_event "note" "$label" "$detail" ""
}

finalize_flow_success() {
  finish_current_stage "done" "flow completed"
  flow_append_event "flow-success" "${FLOW_NAME:-unknown}" "" ""
}

finalize_flow_failure() {
  local exit_code="$1"
  finish_current_stage "failed" "exit_code=$exit_code"
  flow_append_event "flow-failure" "${FLOW_NAME:-unknown}" "exit_code=$exit_code" ""
}
