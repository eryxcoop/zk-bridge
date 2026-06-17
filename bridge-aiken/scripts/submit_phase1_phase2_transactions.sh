#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PHASE12_SCRIPT="$ROOT_DIR/scripts/submit_phase1_phase2_transactions_single_case.sh"
WORKSPACE_CHECK_SCRIPT="$ROOT_DIR/scripts/check_workspace_layout.sh"
TOOLING_CHECK_SCRIPT="$ROOT_DIR/scripts/check_local_tooling.sh"
RUN_OUTPUTS_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/run_outputs_common.sh"
TOOLING_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/tooling_common.sh"
GUARDRAILS_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/guardrails_common.sh"
ENTRYPOINT_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/entrypoint_common.sh"
FLOW_OBSERVABILITY_SCRIPT="$ROOT_DIR/scripts/lib/flow_observability.sh"
SESSION_MANIFEST_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/session_manifest_common.sh"
SESSION_MANIFEST_CHECK_SCRIPT="$ROOT_DIR/scripts/check_session_manifest.sh"

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
# shellcheck disable=SC1090
source "$SESSION_MANIFEST_COMMON_SCRIPT"

handoff_to_wrapper_if_direct "$ROOT_DIR/scripts/bridge.sh" phase12-all "$@"

PHASE12_ALL_RUN_DIR="${PHASE12_ALL_RUN_DIR:-$(default_flow_run_dir phase12-all)}"
SESSION_ENV_PATH="${TX3_SESSION_ENV_PATH:-$PHASE12_ALL_RUN_DIR/session.env}"
PROOF_EXPORT_BUNDLE_PATH="${PROOF_EXPORT_BUNDLE_PATH:-}"
BRIDGE_SKIP_FLOW_CHECKS="${BRIDGE_SKIP_FLOW_CHECKS:-0}"
PHASE12_ALL_CONFIRM_WAIT_SECONDS="${PHASE12_ALL_CONFIRM_WAIT_SECONDS:-6}"

usage() {
  cat <<'EOF'
usage: submit_phase1_phase2_transactions.sh [--proof-export-bundle <bridge-compatible-mithril-stm-bundle.json>] [--output-dir <dir>]

Runs the two Halo2-backed phase1/phase2 proof domains sequentially:
  - stake_distribution_standard
  - cardano_transactions

Writes a combined session manifest with namespaced PHASE1/PHASE2/receipt vars.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --proof-export-bundle)
      PROOF_EXPORT_BUNDLE_PATH="$2"
      shift 2
      ;;
    --output-dir)
      PHASE12_ALL_RUN_DIR="$2"
      SESSION_ENV_PATH="$PHASE12_ALL_RUN_DIR/session.env"
      shift 2
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

if [[ -z "$PROOF_EXPORT_BUNDLE_PATH" ]]; then
  echo "Missing Mithril STM proof-export bundle path. Pass --proof-export-bundle or set PROOF_EXPORT_BUNDLE_PATH." >&2
  exit 1
fi

PROOF_EXPORT_BUNDLE_PATH="$(cd "$(dirname "$PROOF_EXPORT_BUNDLE_PATH")" && pwd)/$(basename "$PROOF_EXPORT_BUNDLE_PATH")"
if [[ ! -f "$PROOF_EXPORT_BUNDLE_PATH" ]]; then
  echo "Missing Mithril STM proof-export bundle at: $PROOF_EXPORT_BUNDLE_PATH" >&2
  exit 1
fi

if [[ ! -x "$PHASE12_SCRIPT" ]]; then
  echo "Missing phase12 script at: $PHASE12_SCRIPT" >&2
  exit 1
fi

run_flow_guardrails "phase12" "$WORKSPACE_CHECK_SCRIPT" "$TOOLING_CHECK_SCRIPT"

ensure_run_dir "$PHASE12_ALL_RUN_DIR"
setup_run_log_dir "$PHASE12_ALL_RUN_DIR"
setup_flow_observability "$PHASE12_ALL_RUN_DIR" "phase12-all"
trap 'phase12_all_exit=$?; if [[ "$phase12_all_exit" -eq 0 ]]; then finalize_flow_success; else finalize_flow_failure "$phase12_all_exit"; fi' EXIT
rm -f "$SESSION_ENV_PATH"

PROOF_NAMES=(
  "stake_distribution_standard"
  "cardano_transactions"
)
LAST_PROOF_NAME="${PROOF_NAMES[${#PROOF_NAMES[@]}-1]}"
PHASE12_ALL_COLLATERAL_UTXOS=(
  "${PHASE12_ALL_COLLATERAL_UTXO_1:-8d910e3a410a353787d50a708e24c6ba2cc2b6b86ec6d8cb5bf9bbec20bfc937#0}"
  "${PHASE12_ALL_COLLATERAL_UTXO_2:-8d910e3a410a353787d50a708e24c6ba2cc2b6b86ec6d8cb5bf9bbec20bfc938#0}"
)
PHASE12_ALL_SOURCE_UTXOS=(
  "${PHASE12_ALL_SOURCE_UTXO_1:-3d930cc9415a0221ff96f4ce00dd0732ee9d692e3b6231b4dbbda540469cf761#0}"
  "${PHASE12_ALL_SOURCE_UTXO_2:-3d930cc9415a0221ff96f4ce00dd0732ee9d692e3b6231b4dbbda540469cf762#0}"
)
PHASE12_ALL_PUBLISH_SOURCE_UTXO="${PHASE12_ALL_PUBLISH_SOURCE_UTXO:-3d930cc9415a0221ff96f4ce00dd0732ee9d692e3b6231b4dbbda540469cf764#0}"

shared_grpc_port=""
shared_trp_port=""
shared_minibf_port=""
shared_dolos_pid=""
shared_publish_phase1_result_path=""
shared_phase1_reference_script_utxo=""
first_case=1
proof_index=0

for proof_name in "${PROOF_NAMES[@]}"; do
  case_run_dir="$PHASE12_ALL_RUN_DIR/$proof_name"
  case_session_env="$case_run_dir/session.env"
  case_collateral_utxo="${PHASE12_ALL_COLLATERAL_UTXOS[$proof_index]}"
  case_source_utxo="${PHASE12_ALL_SOURCE_UTXOS[$proof_index]}"

  begin_stage "Running phase12 case: $proof_name"
  if [[ "$first_case" -eq 1 ]]; then
    PHASE12_RUN_DIR="$case_run_dir" \
    TX3_SESSION_ENV_PATH="$case_session_env" \
    PHASE12_PROOF_NAME="$proof_name" \
    PROOF_EXPORT_BUNDLE_PATH="$PROOF_EXPORT_BUNDLE_PATH" \
    SUPPRESS_SESSION_MANIFEST_MSG=1 \
    BRIDGE_SKIP_FLOW_CHECKS=1 \
    KEEP_TX3_DOLOS_RUNNING=1 \
    BOB_STABLE_PUBLISH_SOURCE_UTXO_A="$PHASE12_ALL_PUBLISH_SOURCE_UTXO" \
    BOB_STABLE_SOURCE_UTXO_A="$case_source_utxo" \
    BOB_STABLE_COLLATERAL_UTXO_A="$case_collateral_utxo" \
    "$PHASE12_SCRIPT"
  else
    PHASE12_RUN_DIR="$case_run_dir" \
    TX3_SESSION_ENV_PATH="$case_session_env" \
    PHASE12_PROOF_NAME="$proof_name" \
    PROOF_EXPORT_BUNDLE_PATH="$PROOF_EXPORT_BUNDLE_PATH" \
    SUPPRESS_SESSION_MANIFEST_MSG=1 \
    BRIDGE_SKIP_FLOW_CHECKS=1 \
    KEEP_TX3_DOLOS_RUNNING=1 \
    PHASE12_REUSE_RUNNING_DOLOS=1 \
    BRIDGE_TX3_GRPC_PORT="$shared_grpc_port" \
    BRIDGE_TX3_TRP_PORT="$shared_trp_port" \
    BRIDGE_TX3_MINIBF_PORT="$shared_minibf_port" \
    DOLOS_PID="$shared_dolos_pid" \
    SHARED_PHASE1_REFERENCE_SCRIPT_RESULT_PATH="$shared_publish_phase1_result_path" \
    SHARED_PHASE1_REFERENCE_SCRIPT_UTXO="$shared_phase1_reference_script_utxo" \
    BOB_STABLE_PUBLISH_SOURCE_UTXO_A="$PHASE12_ALL_PUBLISH_SOURCE_UTXO" \
    BOB_STABLE_SOURCE_UTXO_A="$case_source_utxo" \
    BOB_STABLE_COLLATERAL_UTXO_A="$case_collateral_utxo" \
    "$PHASE12_SCRIPT"
  fi

  if [[ ! -f "$case_session_env" ]]; then
    echo "Missing phase12 case session manifest at: $case_session_env" >&2
    exit 1
  fi

  "$SESSION_MANIFEST_CHECK_SCRIPT" --mode phase12-case --file "$case_session_env"

  if [[ "$first_case" -eq 1 ]]; then
    # shellcheck disable=SC1090
    source "$case_session_env"
    require_session_manifest_var "$case_session_env" GRPC_PORT "reusing the shared Dolos gRPC port across phase12-all cases"
    require_session_manifest_var "$case_session_env" TRP_PORT "reusing the shared Dolos TRP port across phase12-all cases"
    require_session_manifest_var "$case_session_env" MINIBF_PORT "reusing the shared Dolos minibf port across phase12-all cases"
    require_session_manifest_var "$case_session_env" DOLOS_PID "reusing the shared Dolos process across phase12-all cases"
    require_session_manifest_var "$case_session_env" PUBLISH_PHASE1_REFERENCE_SCRIPT_RESULT_PATH "reusing the shared phase1 reference-script publish across phase12-all cases"
    require_session_manifest_var "$case_session_env" PHASE1_REFERENCE_SCRIPT_UTXO "reusing the shared phase1 reference-script UTxO across phase12-all cases"
    shared_grpc_port="${GRPC_PORT:-}"
    shared_trp_port="${TRP_PORT:-}"
    shared_minibf_port="${MINIBF_PORT:-}"
    shared_dolos_pid="${DOLOS_PID:-}"
    shared_publish_phase1_result_path="${PUBLISH_PHASE1_REFERENCE_SCRIPT_RESULT_PATH:-}"
    shared_phase1_reference_script_utxo="${PHASE1_REFERENCE_SCRIPT_UTXO:-}"
    first_case=0
  fi

  if [[ ! -f "$SESSION_ENV_PATH" ]]; then
    cat "$case_session_env" >"$SESSION_ENV_PATH"
  else
    grep -E '^(PHASE1_HASH_|PHASE2_HASH_|PHASE2_RECEIPT_UTXO_|STATEMENT_HASH_|PUBLISH_PHASE1_REFERENCE_SCRIPT_RESULT_PATH_|PHASE1_RESULT_PATH_|PHASE2_RESULT_PATH_|PHASE12_PROOF_NAME=)' \
      "$case_session_env" >>"$SESSION_ENV_PATH"
  fi

  if [[ "$proof_name" != "$LAST_PROOF_NAME" ]]; then
    echo "==> Waiting ${PHASE12_ALL_CONFIRM_WAIT_SECONDS}s for the shared Dolos mempool to confirm the previous phase12 case"
    sleep "$PHASE12_ALL_CONFIRM_WAIT_SECONDS"
  fi

  proof_index=$((proof_index + 1))

done

append_effective_toolchain_manifest "$SESSION_ENV_PATH"
persist_mithril_aggregator_fingerprint "$PHASE12_ALL_RUN_DIR" "$SESSION_ENV_PATH"
"$SESSION_MANIFEST_CHECK_SCRIPT" --mode phase12-all --file "$SESSION_ENV_PATH"

echo "Combined phase12 session manifest written to: $SESSION_ENV_PATH"
