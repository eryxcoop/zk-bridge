#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_DIR="$ROOT_DIR/scripts/python"
TOOLING_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/tooling_common.sh"
RUN_OUTPUTS_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/run_outputs_common.sh"
ENTRYPOINT_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/entrypoint_common.sh"
FLOW_OBSERVABILITY_SCRIPT="$ROOT_DIR/scripts/lib/flow_observability.sh"
PLUTUS_JSON="${PLUTUS_JSON:-$ROOT_DIR/plutus.json}"
MAIN_TX3="${MAIN_TX3:-$ROOT_DIR/main.tx3}"
ENV_DEFAULT="${ENV_DEFAULT:-$ROOT_DIR/env/default.ak}"
TII_PATH="${TII_PATH:-$ROOT_DIR/.tx3/tii/main.tii}"
SYNC_BUILD_TX3="${SYNC_BUILD_TX3:-1}"
BRIDGE_FLOW_VERBOSE="${BRIDGE_FLOW_VERBOSE:-0}"
BRIDGE_VERBOSE_CONTEXT="${BRIDGE_VERBOSE_CONTEXT:-sync-runtime}"
portable_mktemp_path() {
  local dir="$1"
  local pattern="$2"
  mkdir -p "$dir"
  if [[ "$pattern" != *XXXXXX* ]]; then
    pattern="${pattern}.XXXXXX"
  fi

  local prefix="${pattern%%XXXXXX*}"
  local suffix="${pattern#*XXXXXX}"
  local temp_path=""
  local final_path=""

  temp_path="$(mktemp "$dir/${prefix}XXXXXX")"
  if [[ "$suffix" == "$pattern" ]]; then
    printf '%s\n' "$temp_path"
    return
  fi

  final_path="${temp_path}${suffix}"
  mv "$temp_path" "$final_path"
  printf '%s\n' "$final_path"
}
APPLIED_STAKE_DISTRIBUTION_SPEND_STEP1_BLUEPRINT="$(portable_mktemp_path "${TMPDIR:-/tmp}" "stake-distribution-spend-step1.XXXXXX.json")"
APPLIED_STAKE_DISTRIBUTION_SPEND_STEP2_BLUEPRINT="$(portable_mktemp_path "${TMPDIR:-/tmp}" "stake-distribution-spend-step2.XXXXXX.json")"
APPLIED_STAKE_DISTRIBUTION_SPEND_BLUEPRINT="$(portable_mktemp_path "${TMPDIR:-/tmp}" "stake-distribution-spend-applied.XXXXXX.json")"
APPLIED_PHASE2_BLUEPRINT="$(portable_mktemp_path "${TMPDIR:-/tmp}" "phase2-applied.XXXXXX.json")"
APPLIED_BRIDGE_MINTING_STEP1_BLUEPRINT="$(portable_mktemp_path "${TMPDIR:-/tmp}" "bridge-minting-step1.XXXXXX.json")"
APPLIED_BRIDGE_MINTING_STEP2_BLUEPRINT="$(portable_mktemp_path "${TMPDIR:-/tmp}" "bridge-minting-step2.XXXXXX.json")"
APPLIED_BRIDGE_MINTING_BLUEPRINT="$(portable_mktemp_path "${TMPDIR:-/tmp}" "bridge-minting-applied.XXXXXX.json")"
APPLIED_LOCKING_TXS_UPDATER_SPEND_BLUEPRINT="$(portable_mktemp_path "${TMPDIR:-/tmp}" "locking-txs-updater-spend-applied.XXXXXX.json")"
PROOF_RECEIPT_CREDENTIAL_CBOR_PY="$PYTHON_DIR/proof_receipt_credential_cbor.py"
BLUEPRINT_PARAM_CBOR_PY="$PYTHON_DIR/blueprint_param_cbor.py"
SYNC_PHASE_SCRIPTS_TO_TX3_PY="$PYTHON_DIR/sync_phase_scripts_to_tx3.py"
LOCKING_TXS_UPDATER_PARAM_CBOR_PY="$PYTHON_DIR/locking_txs_updater_param_cbor.py"
APPLIED_LOCKING_TXS_UPDATER_STEP1_BLUEPRINT="$(portable_mktemp_path "${TMPDIR:-/tmp}" "locking-txs-updater-step1.XXXXXX.json")"
APPLIED_LOCKING_TXS_UPDATER_STEP2_BLUEPRINT="$(portable_mktemp_path "${TMPDIR:-/tmp}" "locking-txs-updater-step2.XXXXXX.json")"
APPLIED_LOCKING_TXS_UPDATER_BLUEPRINT="$(portable_mktemp_path "${TMPDIR:-/tmp}" "locking-txs-updater-applied.XXXXXX.json")"
SYNC_MAIN_TX3_BACKUP_PATH="${SYNC_MAIN_TX3_BACKUP_PATH:-}"
SYNC_ENV_DEFAULT_BACKUP_PATH="${SYNC_ENV_DEFAULT_BACKUP_PATH:-}"
SYNC_MAIN_TX3_BACKUP_PATH=""
SYNC_ENV_DEFAULT_BACKUP_PATH=""

# shellcheck disable=SC1090
source "$TOOLING_COMMON_SCRIPT"
# shellcheck disable=SC1090
source "$RUN_OUTPUTS_COMMON_SCRIPT"
# shellcheck disable=SC1090
source "$ENTRYPOINT_COMMON_SCRIPT"
# shellcheck disable=SC1090
source "$FLOW_OBSERVABILITY_SCRIPT"

usage() {
  cat <<'EOF'
usage: sync_phase_scripts_to_tx3.sh

Compatibility wrapper for:
  ./scripts/bridge.sh sync

Behavior is configured through environment variables such as:
  SYNC_SCOPE
  PLUTUS_JSON
  MAIN_TX3
  ENV_DEFAULT
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

handoff_to_wrapper_if_direct "$ROOT_DIR/scripts/bridge.sh" sync "$@"

cleanup() {
  local exit_code="${1:-0}"

  if [[ "$exit_code" -ne 0 ]]; then
    if [[ -n "${SYNC_MAIN_TX3_BACKUP_PATH:-}" ]]; then
      restore_file_from_backup "$SYNC_MAIN_TX3_BACKUP_PATH" "$MAIN_TX3" || true
    fi
    if [[ -n "${SYNC_ENV_DEFAULT_BACKUP_PATH:-}" ]]; then
      restore_file_from_backup "$SYNC_ENV_DEFAULT_BACKUP_PATH" "$ENV_DEFAULT" || true
    fi
  fi

  rm -f "$APPLIED_STAKE_DISTRIBUTION_SPEND_STEP1_BLUEPRINT"
  rm -f "$APPLIED_STAKE_DISTRIBUTION_SPEND_STEP2_BLUEPRINT"
  rm -f "$APPLIED_STAKE_DISTRIBUTION_SPEND_BLUEPRINT"
  rm -f "$APPLIED_PHASE2_BLUEPRINT"
  rm -f "$APPLIED_BRIDGE_MINTING_STEP1_BLUEPRINT"
  rm -f "$APPLIED_BRIDGE_MINTING_STEP2_BLUEPRINT"
  rm -f "$APPLIED_BRIDGE_MINTING_BLUEPRINT"
  rm -f "$APPLIED_LOCKING_TXS_UPDATER_SPEND_BLUEPRINT"
  rm -f "$APPLIED_LOCKING_TXS_UPDATER_STEP1_BLUEPRINT"
  rm -f "$APPLIED_LOCKING_TXS_UPDATER_STEP2_BLUEPRINT"
  rm -f "$APPLIED_LOCKING_TXS_UPDATER_BLUEPRINT"
}

trap 'cleanup $?' EXIT

run_logged() {
  local label="$1"
  shift

  if [[ "$BRIDGE_FLOW_VERBOSE" == "1" ]]; then
    "$@"
    return
  fi

  local log_path
  if [[ -n "${BRIDGE_LOG_DIR:-}" ]]; then
    log_path="$(portable_mktemp_path "$BRIDGE_LOG_DIR" "bridge-sync-${label// /-}.XXXXXX.log")"
  else
    log_path="$(portable_mktemp_path "${TMPDIR:-/tmp}" "bridge-sync-${label// /-}.XXXXXX.log")"
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

current_sync_scope() {
  printf '%s' "${SYNC_SCOPE:-all}"
}

sync_cache_path() {
  printf '%s/.tx3/cache/sync-%s.sha256' "$ROOT_DIR" "$(current_sync_scope)"
}

compute_sync_inputs_fingerprint() {
  {
    printf 'sync-v2\n'
    printf 'scope=%s\n' "$(current_sync_scope)"
    printf '%s  %s\n' "$(sha256_file "$0")" "$0"
    printf '%s  %s\n' "$(sha256_file "$PLUTUS_JSON")" "$PLUTUS_JSON"
    printf '%s  %s\n' "$(sha256_file "$MAIN_TX3")" "$MAIN_TX3"
    printf '%s  %s\n' "$(sha256_file "$ENV_DEFAULT")" "$ENV_DEFAULT"
    printf '%s  %s\n' "$(sha256_file "$ROOT_DIR/aiken.toml")" "$ROOT_DIR/aiken.toml"
    printf '%s  %s\n' "$(sha256_file "$PROOF_RECEIPT_CREDENTIAL_CBOR_PY")" "$PROOF_RECEIPT_CREDENTIAL_CBOR_PY"
    printf '%s  %s\n' "$(sha256_file "$BLUEPRINT_PARAM_CBOR_PY")" "$BLUEPRINT_PARAM_CBOR_PY"
    printf '%s  %s\n' "$(sha256_file "$LOCKING_TXS_UPDATER_PARAM_CBOR_PY")" "$LOCKING_TXS_UPDATER_PARAM_CBOR_PY"
    printf '%s  %s\n' "$(sha256_file "$SYNC_PHASE_SCRIPTS_TO_TX3_PY")" "$SYNC_PHASE_SCRIPTS_TO_TX3_PY"
    find "$ROOT_DIR/lib" "$ROOT_DIR/validators" -type f -print0 | hash_sorted_files_from_stdin0
  } | sha256_stream
}

resolve_binary_path AIKEN_BIN "Aiken binary" AIKEN_BIN aiken || exit 1
resolve_binary_path PYTHON_BIN "Python 3 binary" PYTHON_BIN python3 "$ROOT_DIR/.venv/bin/python" || exit 1
resolve_binary_path TRIX_BIN "trix binary" TRIX_BIN trix "$ROOT_DIR/.tools/bin/trix" "$ROOT_DIR/.tools/trix" || exit 1
print_resolved_binary_if_verbose "Aiken binary" "$AIKEN_BIN"
print_resolved_binary_if_verbose "Python 3 binary" "$PYTHON_BIN"
print_resolved_binary_if_verbose "trix binary" "$TRIX_BIN"

tii_contains_tx() {
  local tx_name="$1"
  local tii_path="$2"

  [[ -f "$tii_path" ]] || return 1
  grep -Fq "\"$tx_name\"" "$tii_path"
}

tii_contains_party() {
  local party_name="$1"
  local tii_path="$2"

  [[ -f "$tii_path" ]] || return 1
  grep -Fq "\"$party_name\"" "$tii_path"
}

tii_needs_refresh_for_scope() {
  local tii_path="$1"
  local scope="${SYNC_SCOPE:-all}"
  local required=()
  local required_parties=(user)

  case "$scope" in
    all)
      required=(
        publish_phase1_reference_script
        phase1_setup
        phase2_verify
        stake_distribution_genesis_tx
        stake_distribution_dual_genesis_tx
        stake_distribution_standard_tx
        locking_txs_updater_seed_tx
        publish_minting_txs_updater_spend_reference_script
        publish_bridge_minting_reference_script
        minting_txs_updater_seed_tx
        bridge_mint_tx
      )
      ;;
    phase12)
      required=(
        publish_phase1_reference_script
        phase1_setup
        phase2_verify
      )
      ;;
    stake_distribution)
      required=(
        stake_distribution_genesis_tx
        stake_distribution_dual_genesis_tx
        stake_distribution_standard_tx
      )
      ;;
    bridge)
      required=(
        locking_txs_updater_seed_tx
        publish_minting_txs_updater_spend_reference_script
        publish_bridge_minting_reference_script
        minting_txs_updater_seed_tx
        bridge_mint_tx
      )
      ;;
    *)
      echo "Unsupported SYNC_SCOPE for TII verification: $scope" >&2
      return 1
      ;;
  esac

  local tx_name
  for tx_name in "${required[@]}"; do
    if ! tii_contains_tx "$tx_name" "$tii_path"; then
      echo "==> TII refresh required: missing tx template '$tx_name' in $tii_path"
      return 0
    fi
  done

  local party_name
  for party_name in "${required_parties[@]}"; do
    if ! tii_contains_party "$party_name" "$tii_path"; then
      echo "==> TII refresh required: missing party '$party_name' in $tii_path"
      return 0
    fi
  done

  return 1
}

validate_inputs() {
  if [[ ! -f "$PLUTUS_JSON" ]]; then
    echo "Missing plutus blueprint: $PLUTUS_JSON" >&2
    exit 1
  fi

  if [[ ! -f "$MAIN_TX3" ]]; then
    echo "Missing Tx3 file: $MAIN_TX3" >&2
    exit 1
  fi

  if [[ ! -f "$ENV_DEFAULT" ]]; then
    echo "Missing env file: $ENV_DEFAULT" >&2
    exit 1
  fi
}

apply_parameterized_blueprints() {
  local proof_receipt_credential_cbor
  local phase2_asset_policy_cbor
  local stake_distribution_asset_policy_cbor
  local locking_txs_updater_policy_cbor
  local locking_txs_updater_asset_name_cbor
  local locking_txs_updater_initial_merkle_root_cbor

  proof_receipt_credential_cbor="$("$PYTHON_BIN" "$PROOF_RECEIPT_CREDENTIAL_CBOR_PY")"

  echo "==> Applying parameters to phase2 blueprint"
  run_logged "aiken blueprint apply phase2" "$AIKEN_BIN" blueprint apply \
    "$proof_receipt_credential_cbor" \
    -i "$PLUTUS_JSON" \
    -m phase2 \
    -v phase2 \
    -o "$APPLIED_PHASE2_BLUEPRINT"

  echo "==> Applying parameters to locking txs updater mint blueprint"
  locking_txs_updater_asset_name_cbor="$("$PYTHON_BIN" "$LOCKING_TXS_UPDATER_PARAM_CBOR_PY" "$ENV_DEFAULT" asset-name)"
  locking_txs_updater_initial_merkle_root_cbor="$("$PYTHON_BIN" "$LOCKING_TXS_UPDATER_PARAM_CBOR_PY" "$ENV_DEFAULT" initial-merkle-root)"

  run_logged "aiken blueprint apply txs_updater mint step1" "$AIKEN_BIN" blueprint apply \
    "$locking_txs_updater_asset_name_cbor" \
    -i "$PLUTUS_JSON" \
    -m txs_updater_common \
    -v txs_updater_validator_mint \
    -o "$APPLIED_LOCKING_TXS_UPDATER_STEP1_BLUEPRINT"

  run_logged "aiken blueprint apply txs_updater mint step2" "$AIKEN_BIN" blueprint apply \
    "$locking_txs_updater_initial_merkle_root_cbor" \
    -i "$APPLIED_LOCKING_TXS_UPDATER_STEP1_BLUEPRINT" \
    -m txs_updater_common \
    -v txs_updater_validator_mint \
    -o "$APPLIED_LOCKING_TXS_UPDATER_BLUEPRINT"

  phase2_asset_policy_cbor="$("$PYTHON_BIN" "$BLUEPRINT_PARAM_CBOR_PY" "$APPLIED_PHASE2_BLUEPRINT" "phase2.phase2.spend" policy-id)"
  stake_distribution_asset_policy_cbor="$("$PYTHON_BIN" "$BLUEPRINT_PARAM_CBOR_PY" "$PLUTUS_JSON" "stake_distribution.stake_distribution_validator_mint.mint" policy-id)"
  locking_txs_updater_policy_cbor="$("$PYTHON_BIN" "$BLUEPRINT_PARAM_CBOR_PY" "$APPLIED_LOCKING_TXS_UPDATER_BLUEPRINT" "txs_updater_common.txs_updater_validator_mint.mint" policy-id)"

  run_logged "aiken blueprint apply stake_distribution spend step1" "$AIKEN_BIN" blueprint apply \
    "$proof_receipt_credential_cbor" \
    -i "$PLUTUS_JSON" \
    -m stake_distribution \
    -v stake_distribution_validator_spend \
    -o "$APPLIED_STAKE_DISTRIBUTION_SPEND_STEP1_BLUEPRINT"

  run_logged "aiken blueprint apply stake_distribution spend step2" "$AIKEN_BIN" blueprint apply \
    "$phase2_asset_policy_cbor" \
    -i "$APPLIED_STAKE_DISTRIBUTION_SPEND_STEP1_BLUEPRINT" \
    -m stake_distribution \
    -v stake_distribution_validator_spend \
    -o "$APPLIED_STAKE_DISTRIBUTION_SPEND_STEP2_BLUEPRINT"

  run_logged "aiken blueprint apply stake_distribution spend step3" "$AIKEN_BIN" blueprint apply \
    "$stake_distribution_asset_policy_cbor" \
    -i "$APPLIED_STAKE_DISTRIBUTION_SPEND_STEP2_BLUEPRINT" \
    -m stake_distribution \
    -v stake_distribution_validator_spend \
    -o "$APPLIED_STAKE_DISTRIBUTION_SPEND_BLUEPRINT"

  run_logged "aiken blueprint apply txs_updater spend" "$AIKEN_BIN" blueprint apply \
    "$locking_txs_updater_policy_cbor" \
    -i "$PLUTUS_JSON" \
    -m txs_updater_minting \
    -v txs_updater_minting_validator_spend \
    -o "$APPLIED_LOCKING_TXS_UPDATER_SPEND_BLUEPRINT"

  run_logged "aiken blueprint apply bridge mint step1" "$AIKEN_BIN" blueprint apply \
    "$proof_receipt_credential_cbor" \
    -i "$PLUTUS_JSON" \
    -m minting \
    -v minting_validator \
    -o "$APPLIED_BRIDGE_MINTING_STEP1_BLUEPRINT"

  run_logged "aiken blueprint apply bridge mint step2" "$AIKEN_BIN" blueprint apply \
    "$phase2_asset_policy_cbor" \
    -i "$APPLIED_BRIDGE_MINTING_STEP1_BLUEPRINT" \
    -m minting \
    -v minting_validator \
    -o "$APPLIED_BRIDGE_MINTING_STEP2_BLUEPRINT"

  run_logged "aiken blueprint apply bridge mint step3" "$AIKEN_BIN" blueprint apply \
    "$stake_distribution_asset_policy_cbor" \
    -i "$APPLIED_BRIDGE_MINTING_STEP2_BLUEPRINT" \
    -m minting \
    -v minting_validator \
    -o "$APPLIED_BRIDGE_MINTING_BLUEPRINT"
}

build_aiken_artifacts() {
  begin_stage "Building Aiken artifacts (round $round/$MAX_SYNC_ROUNDS)"
  run_logged "aiken build" "$AIKEN_BIN" build

  apply_parameterized_blueprints
}

sync_tx3_once() {
  begin_stage "Syncing policies, env constants, and inline scripts into main.tx3"
  "$PYTHON_BIN" "$SYNC_PHASE_SCRIPTS_TO_TX3_PY" \
    "$PLUTUS_JSON" \
    "$APPLIED_PHASE2_BLUEPRINT" \
    "$PLUTUS_JSON" \
    "$APPLIED_STAKE_DISTRIBUTION_SPEND_BLUEPRINT" \
    "$APPLIED_LOCKING_TXS_UPDATER_BLUEPRINT" \
    "$APPLIED_LOCKING_TXS_UPDATER_SPEND_BLUEPRINT" \
    "$APPLIED_BRIDGE_MINTING_BLUEPRINT" \
    "$MAIN_TX3" \
    "$ENV_DEFAULT"
}

sync_round_converged() {
  if [[ "$before_env" == "$after_env" ]]; then
    echo "Sync finished after $round round(s); env/default.ak is unchanged."
    return 0
  fi

  if [[ "$before_main" == "$after_main" && "$before_env" == "$after_env" ]]; then
    echo "Sync finished after $round round(s)."
    return 0
  fi

  return 1
}

maybe_inject_sync_failure_after_mutation() {
  local fail_round="${BRIDGE_SYNC_FAIL_AFTER_SYNC_ON_ROUND:-}"

  if [[ -z "$fail_round" ]]; then
    return
  fi

  if [[ "$round" == "$fail_round" ]]; then
    echo "Injected sync failure after mutation on round $round" >&2
    exit 91
  fi
}

run_sync_rounds() {
  round=1

  while (( round <= MAX_SYNC_ROUNDS )); do
    build_aiken_artifacts

    before_main="$(sha256_file "$MAIN_TX3")"
    before_env="$(sha256_file "$ENV_DEFAULT")"

    sync_tx3_once

    after_main="$(sha256_file "$MAIN_TX3")"
    after_env="$(sha256_file "$ENV_DEFAULT")"
    maybe_inject_sync_failure_after_mutation

    if sync_round_converged; then
      return
    fi

    round=$((round + 1))
  done

  echo "Sync did not converge after $MAX_SYNC_ROUNDS rounds." >&2
  exit 1
}

refresh_tx3_interface_if_needed() {
  if [[ "$SYNC_BUILD_TX3" != "1" ]]; then
    skip_stage "Building Tx3 artifacts" "SYNC_BUILD_TX3=0"
    return
  fi

  if [[ ! -f "$TII_PATH" ]] || [[ "$sync_cache_unchanged" != "1" ]] || [[ "$sync_initial_main_hash" != "$sync_final_main_hash" ]] || [[ "$sync_initial_env_hash" != "$sync_final_env_hash" ]] || tii_needs_refresh_for_scope "$TII_PATH"; then
    begin_stage "Building Tx3 artifacts"
    run_logged "trix build" "$TRIX_BIN" build -v
  else
    skip_stage "Building Tx3 artifacts" "main.tx3 and env/default.ak are unchanged"
  fi
}

cd "$ROOT_DIR"
validate_inputs

SYNC_OBSERVABILITY_DIR="${SYNC_OBSERVABILITY_DIR:-$ROOT_DIR/.tx3/cache/sync}"
mkdir -p "$SYNC_OBSERVABILITY_DIR" "$(dirname "$(sync_cache_path)")"
setup_flow_observability "$SYNC_OBSERVABILITY_DIR" "sync-$(current_sync_scope)"
SYNC_MAIN_TX3_BACKUP_PATH="$SYNC_OBSERVABILITY_DIR/main.tx3.backup"
SYNC_ENV_DEFAULT_BACKUP_PATH="$SYNC_OBSERVABILITY_DIR/env.default.ak.backup"
backup_file_to_path "$MAIN_TX3" "$SYNC_MAIN_TX3_BACKUP_PATH"
backup_file_to_path "$ENV_DEFAULT" "$SYNC_ENV_DEFAULT_BACKUP_PATH"
record_debug_context "sync-target" "$MAIN_TX3"
record_debug_context "sync-target" "$ENV_DEFAULT"
trap 'sync_exit=$?; cleanup "$sync_exit"; if [[ "$sync_exit" -eq 0 ]]; then finalize_flow_success; else finalize_flow_failure "$sync_exit"; fi' EXIT

MAX_SYNC_ROUNDS="${MAX_SYNC_ROUNDS:-5}"
sync_initial_main_hash="$(sha256_file "$MAIN_TX3")"
sync_initial_env_hash="$(sha256_file "$ENV_DEFAULT")"
sync_initial_inputs_fingerprint="$(compute_sync_inputs_fingerprint)"
sync_cache_unchanged=0

if [[ -f "$(sync_cache_path)" ]] && [[ "$(cat "$(sync_cache_path)")" == "$sync_initial_inputs_fingerprint" ]] && ! tii_needs_refresh_for_scope "$TII_PATH"; then
  sync_cache_unchanged=1
  skip_stage "Syncing Aiken scripts into main.tx3" "fingerprint unchanged for scope $(current_sync_scope)"
  exit 0
fi

run_sync_rounds

sync_final_main_hash="$(sha256_file "$MAIN_TX3")"
sync_final_env_hash="$(sha256_file "$ENV_DEFAULT")"

refresh_tx3_interface_if_needed

compute_sync_inputs_fingerprint >"$(sync_cache_path)"
