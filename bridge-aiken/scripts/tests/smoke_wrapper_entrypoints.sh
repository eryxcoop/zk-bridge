#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

assert_redirects() {
  local script_path="$1"
  local expected="$2"
  printf 'checking wrapper: %s\n' "$script_path"
  grep -Fq 'handoff_to_wrapper_if_direct "$ROOT_DIR/scripts/bridge.sh" '"$expected" "$script_path"
}

assert_wrapper_help() {
  local command_name="$1"
  local expected_text="$2"
  local output=""

  output="$("$ROOT_DIR/scripts/bridge.sh" "$command_name" --help 2>&1 || true)"
  grep -Fq "$expected_text" <<<"$output"
}

assert_redirects "$ROOT_DIR/scripts/submit_phase1_phase2_transactions_single_case.sh" "phase12"
assert_redirects "$ROOT_DIR/scripts/submit_phase1_phase2_transactions.sh" "phase12-all"
assert_redirects "$ROOT_DIR/scripts/mithril_stake_distribution.sh" "stake-distribution"
assert_redirects "$ROOT_DIR/scripts/bridge_minting.sh" "bridge"
assert_redirects "$ROOT_DIR/scripts/preflight_mithril_poc.sh" "preflight"
assert_redirects "$ROOT_DIR/scripts/build_bridge_compatible_mithril_stm_proof_export_bundle.sh" "proof-export-bundle"
assert_wrapper_help "workspace" "usage: check_workspace_layout.sh"
assert_wrapper_help "tooling" "usage: check_local_tooling.sh"

echo "wrapper entrypoint smoke tests passed"
