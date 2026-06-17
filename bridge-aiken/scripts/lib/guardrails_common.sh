run_flow_guardrails() {
  local flow_name="$1"
  local workspace_check_script="$2"
  local tooling_check_script="$3"

  if [[ "${BRIDGE_SKIP_FLOW_CHECKS:-0}" == "1" ]]; then
    echo "==> Skipping workspace layout check for $flow_name (already validated by parent flow)"
    echo "==> Skipping tooling check for $flow_name (already validated by parent flow)"
    return
  fi

  echo "==> Running workspace layout check for $flow_name"
  "$workspace_check_script" --flow "$flow_name"
  echo "==> Running local tooling check for $flow_name"
  "$tooling_check_script" --flow "$flow_name"
}
