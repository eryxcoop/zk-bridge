#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
DEFAULT_ARTIFACT_OUTPUT_PATH="$ROOT_DIR/artifacts/mithril-poc/latest/bridge-compatible-mithril-stm-bundle.json"

usage() {
  cat <<'EOF'
usage: bridge.sh <command> [args...]

Unified operator entrypoint for bridge-aiken.

Official short path:
  ./scripts/bridge.sh bootstrap --link
  uv sync
  ./scripts/bridge.sh run --strict

Commands:
  bootstrap            Prepare or check repo-local trix/cshell tooling
  workspace [flow]     Validate sibling workspace layout
  tooling [flow]       Validate local commands and Python dependencies
  doctor [flow]        Run workspace + tooling checks for a flow
  run                  Run the integrated Mithril PoC flow (use --strict for the recommended CI-like validation)
  proof-export-bundle  Build the canonical bridge-compatible Mithril STM proof-export bundle
  preflight            Run the Mithril PoC preflight
  phase12              Run publish_phase1_reference_script -> phase1_setup -> phase2_verify
  phase12-all          Run the two Halo2-backed phase1/phase2 proof domains sequentially
  genesis_dual_signature  Run the one-tx GenesisDualSignature experimental flow
  stake-distribution   Run the stake distribution flow
  bridge               Run the full bridge minting flow
  sync                 Sync Aiken artifacts into main.tx3
  help                 Show this help

Examples:
  ./scripts/bridge.sh bootstrap --link
  ./scripts/bridge.sh proof-export-bundle
  ./scripts/bridge.sh proof-export-bundle run_outputs/custom/bridge-compatible-mithril-stm-bundle.json
  ./scripts/bridge.sh bootstrap --check
  ./scripts/bridge.sh doctor check
  ./scripts/bridge.sh run --strict
  ./scripts/bridge.sh run --proof-export-bundle run_outputs/mithril-poc/latest/bridge-compatible-mithril-stm-bundle.json
EOF
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

forward_flow_command() {
  local script_path="$1"
  shift
  local flow_default="$1"
  shift

  if [[ $# -eq 0 ]]; then
    exec "$script_path" --flow "$flow_default"
  fi

  case "$1" in
    -h|--help)
      exec "$script_path" --help
      ;;
    --flow)
      exec "$script_path" "$@"
      ;;
    *)
      local flow="$1"
      shift
      exec "$script_path" --flow "$flow" "$@"
      ;;
  esac
}

COMMAND="$1"
shift

case "$COMMAND" in
  bootstrap)
    export BRIDGE_INTERNAL_CALL=1
    exec "$SCRIPTS_DIR/bootstrap_dev_env.sh" "$@"
    ;;
  workspace)
    export BRIDGE_INTERNAL_CALL=1
    forward_flow_command "$SCRIPTS_DIR/check_workspace_layout.sh" check "$@"
    ;;
  tooling)
    export BRIDGE_INTERNAL_CALL=1
    forward_flow_command "$SCRIPTS_DIR/check_local_tooling.sh" check "$@"
    ;;
  doctor)
    export BRIDGE_INTERNAL_CALL=1
    if [[ $# -eq 0 ]]; then
      "$SCRIPTS_DIR/check_workspace_layout.sh" --flow check
      exec "$SCRIPTS_DIR/check_local_tooling.sh" --flow check
    fi
    case "$1" in
      -h|--help)
        "$SCRIPTS_DIR/check_workspace_layout.sh" --help
        exec "$SCRIPTS_DIR/check_local_tooling.sh" --help
        ;;
      --flow)
        "$SCRIPTS_DIR/check_workspace_layout.sh" "$@"
        exec "$SCRIPTS_DIR/check_local_tooling.sh" "$@"
        ;;
      *)
        FLOW="$1"
        shift
        "$SCRIPTS_DIR/check_workspace_layout.sh" --flow "$FLOW" "$@"
        exec "$SCRIPTS_DIR/check_local_tooling.sh" --flow "$FLOW" "$@"
        ;;
    esac
    ;;
  run)
    export BRIDGE_INTERNAL_CALL=1
    exec "$SCRIPTS_DIR/run_mithril_poc.sh" "$@"
    ;;
  proof-export-bundle)
    export BRIDGE_INTERNAL_CALL=1
    if [[ $# -eq 0 ]]; then
      exec "$SCRIPTS_DIR/build_bridge_compatible_mithril_stm_proof_export_bundle.sh" "$@"
    fi
    exec "$SCRIPTS_DIR/build_bridge_compatible_mithril_stm_proof_export_bundle.sh" "$@"
    ;;
  preflight)
    export BRIDGE_INTERNAL_CALL=1
    exec "$SCRIPTS_DIR/preflight_mithril_poc.sh" "$@"
    ;;
  phase12)
    export BRIDGE_INTERNAL_CALL=1
    exec "$SCRIPTS_DIR/submit_phase1_phase2_transactions_single_case.sh" "$@"
    ;;
  phase12-all)
    export BRIDGE_INTERNAL_CALL=1
    exec "$SCRIPTS_DIR/submit_phase1_phase2_transactions.sh" "$@"
    ;;
  genesis_dual_signature)
    export BRIDGE_INTERNAL_CALL=1
    exec "$SCRIPTS_DIR/genesis_dual_signature.sh" "$@"
    ;;
  stake-distribution)
    export BRIDGE_INTERNAL_CALL=1
    exec "$SCRIPTS_DIR/mithril_stake_distribution.sh" "$@"
    ;;
  bridge)
    export BRIDGE_INTERNAL_CALL=1
    exec "$SCRIPTS_DIR/bridge_minting.sh" "$@"
    ;;
  sync)
    export BRIDGE_INTERNAL_CALL=1
    exec "$SCRIPTS_DIR/sync_phase_scripts_to_tx3.sh" "$@"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "Unknown command: $COMMAND" >&2
    usage >&2
    exit 1
    ;;
esac
