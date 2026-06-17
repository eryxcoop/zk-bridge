#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SD_SCRIPT="$ROOT_DIR/scripts/mithril_stake_distribution.sh"
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
SESSION_MANIFEST_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/session_manifest_common.sh"
SESSION_MANIFEST_CHECK_SCRIPT="$ROOT_DIR/scripts/check_session_manifest.sh"
PYTHON_DIR="$ROOT_DIR/scripts/python"
PATCH_BRIDGE_MINT_TX_MANIFEST="$ROOT_DIR/tools/patch_bridge_mint_tx/Cargo.toml"
PREPARE_MITHRIL_BRIDGE_ARGS_PY="$PYTHON_DIR/prepare_mithril_bridge_minting_args.py"
SYNC_BRIDGE_ZK_FIXTURE_PY="$PYTHON_DIR/sync_bridge_zk_fixture.py"
READ_JSON_FIELD_PY="$PYTHON_DIR/read_json_field.py"
SET_JSON_FIELD_PY="$PYTHON_DIR/set_json_field.py"
TX_PUBLISH_SUMMARY_PY="$PYTHON_DIR/tx_publish_summary.py"
WRITE_BRIDGE_FLOW_CSV_PY="$PYTHON_DIR/write_bridge_flow_csv.py"
BUILD_SUBMIT_RESULT_PY="$PYTHON_DIR/build_submit_result.py"
LOCKING_TXS_UPDATER_SEED_RAW_PATH="$ROOT_DIR/scripts/data/locking_txs_updater_seed_raw.json"
BRIDGE_RAW_PATH="$ROOT_DIR/scripts/data/bridge_mint_raw.json"
BRIDGE_FIXTURE_HELPER_PATH="$ROOT_DIR/validators/tests/helpers/bridge_fixture.ak"
ENV_DEFAULT_PATH="$ROOT_DIR/env/default.ak"
MAIN_TX3_PATH="$ROOT_DIR/main.tx3"
BRIDGE_FLOW_CSV_PATH_DEFAULT="$ROOT_DIR/bridge-flow-summary.csv"
PROOF_EXPORT_BUNDLE_PATH="${PROOF_EXPORT_BUNDLE_PATH:-}"
BRIDGE_MINTING_REUSE_SYNCED_TX3="${BRIDGE_MINTING_REUSE_SYNCED_TX3:-1}"
SUPPRESS_BUNDLE_SUMMARY="${SUPPRESS_BUNDLE_SUMMARY:-0}"
USER_ADDRESS="${USER_ADDRESS:-addr_test1vqxazu4ekxrxlk238wt0e03h3gk44hrlkjvef85gvh2nahcgnmpfc}"

KEEP_MITHRIL_BRIDGE_MINTING_TMP="${KEEP_MITHRIL_BRIDGE_MINTING_TMP:-1}"
BOB_STABLE_COLLATERAL_UTXO_A="${BOB_STABLE_COLLATERAL_UTXO_A:-8d910e3a410a353787d50a708e24c6ba2cc2b6b86ec6d8cb5bf9bbec20bfc937#0}"
BOB_STABLE_STAKE_DISTRIBUTION_GENESIS_SOURCE_UTXO_A="${BOB_STABLE_STAKE_DISTRIBUTION_GENESIS_SOURCE_UTXO_A:-3d930cc9415a0221ff96f4ce00dd0732ee9d692e3b6231b4dbbda540469cf765#0}"
BOB_STABLE_STAKE_DISTRIBUTION_STANDARD_SOURCE_UTXO_A="${BOB_STABLE_STAKE_DISTRIBUTION_STANDARD_SOURCE_UTXO_A:-${BOB_STABLE_STAKE_DISTRIBUTION_SOURCE_UTXO_A:-3d930cc9415a0221ff96f4ce00dd0732ee9d692e3b6231b4dbbda540469cf766#0}}"
BOB_STABLE_LOCKING_SEED_SOURCE_UTXO_A="${BOB_STABLE_LOCKING_SEED_SOURCE_UTXO_A:-3d930cc9415a0221ff96f4ce00dd0732ee9d692e3b6231b4dbbda540469cf767#0}"
BOB_STABLE_PUBLISH_LOCKING_TXS_UPDATER_SOURCE_UTXO_A="${BOB_STABLE_PUBLISH_LOCKING_TXS_UPDATER_SOURCE_UTXO_A:-3d930cc9415a0221ff96f4ce00dd0732ee9d692e3b6231b4dbbda540469cf768#0}"
BOB_STABLE_PUBLISH_BRIDGE_MINTING_SOURCE_UTXO_A="${BOB_STABLE_PUBLISH_BRIDGE_MINTING_SOURCE_UTXO_A:-3d930cc9415a0221ff96f4ce00dd0732ee9d692e3b6231b4dbbda540469cf769#0}"
BOB_STABLE_LOCKING_GENESIS_SOURCE_UTXO_A="${BOB_STABLE_LOCKING_GENESIS_SOURCE_UTXO_A:-3d930cc9415a0221ff96f4ce00dd0732ee9d692e3b6231b4dbbda540469cf76a#0}"
BOB_STABLE_LOCKING_SEED_COLLATERAL_UTXO_A="${BOB_STABLE_LOCKING_SEED_COLLATERAL_UTXO_A:-8d910e3a410a353787d50a708e24c6ba2cc2b6b86ec6d8cb5bf9bbec20bfc93b#0}"
BOB_STABLE_LOCKING_GENESIS_COLLATERAL_UTXO_A="${BOB_STABLE_LOCKING_GENESIS_COLLATERAL_UTXO_A:-8d910e3a410a353787d50a708e24c6ba2cc2b6b86ec6d8cb5bf9bbec20bfc93c#0}"
BOB_STABLE_BRIDGE_MINT_COLLATERAL_UTXO_A="${BOB_STABLE_BRIDGE_MINT_COLLATERAL_UTXO_A:-8d910e3a410a353787d50a708e24c6ba2cc2b6b86ec6d8cb5bf9bbec20bfc93d#0}"
BRIDGE_MINT_MINT_EX_MEM="${BRIDGE_MINT_MINT_EX_MEM:-100000000}"
BRIDGE_MINT_MINT_EX_STEPS="${BRIDGE_MINT_MINT_EX_STEPS:-100000000000}"
BRIDGE_MINT_FEE_BUFFER="${BRIDGE_MINT_FEE_BUFFER:-500000}"
BRIDGE_MINT_COLLATERAL_LOVELACE="${BRIDGE_MINT_COLLATERAL_LOVELACE:-40000000}"
BRIDGE_SKIP_FLOW_CHECKS="${BRIDGE_SKIP_FLOW_CHECKS:-0}"
BRIDGE_VERBOSE_CONTEXT="${BRIDGE_VERBOSE_CONTEXT:-bridge-runtime}"
export RUSTFLAGS="${RUSTFLAGS:--Awarnings}"
CURRENT_STAGE="initializing"
BUNDLE_SOURCE_ID=""
BUNDLE_STATEMENT_HASH=""

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

handoff_to_wrapper_if_direct "$ROOT_DIR/scripts/bridge.sh" bridge "$@"

BRIDGE_MINTING_RUN_DIR="${BRIDGE_MINTING_RUN_DIR:-$(default_flow_run_dir bridge-minting)}"
ensure_run_dir "$BRIDGE_MINTING_RUN_DIR"
setup_run_log_dir "$BRIDGE_MINTING_RUN_DIR"
setup_flow_observability "$BRIDGE_MINTING_RUN_DIR" "bridge"
RUNTIME_BUNDLE_PATH="$BRIDGE_MINTING_RUN_DIR/runtime-proof-export-bundle/bridge-compatible-mithril-stm-bundle.json"
RUNTIME_BUNDLE_DIR="$BRIDGE_MINTING_RUN_DIR/runtime-proof-export-bundle"
SESSION_ENV_PATH="$BRIDGE_MINTING_RUN_DIR/session.env"
ENV_DEFAULT_BACKUP_PATH="$BRIDGE_MINTING_RUN_DIR/env-default.backup.ak"
MAIN_TX3_BACKUP_PATH="$BRIDGE_MINTING_RUN_DIR/main.tx3.backup"
BRIDGE_RAW_BACKUP_PATH="$BRIDGE_MINTING_RUN_DIR/bridge-mint-raw.backup.json"
BRIDGE_FIXTURE_HELPER_BACKUP_PATH="$BRIDGE_MINTING_RUN_DIR/bridge-fixture-helper.backup.ak"

cleanup() {
  local exit_code="$1"

  if [[ "$exit_code" -ne 0 ]]; then
    finalize_flow_failure "$exit_code"
    print_failure_context "bridge_minting flow" "$exit_code"
  else
    finalize_flow_success
  fi

  if [[ -f "$ENV_DEFAULT_BACKUP_PATH" ]]; then
    restore_file_from_backup "$ENV_DEFAULT_BACKUP_PATH" "$ENV_DEFAULT_PATH" || true
  fi

  if [[ -f "$MAIN_TX3_BACKUP_PATH" ]]; then
    restore_file_from_backup "$MAIN_TX3_BACKUP_PATH" "$MAIN_TX3_PATH" || true
  fi

  if [[ -f "$BRIDGE_RAW_BACKUP_PATH" ]]; then
    restore_file_from_backup "$BRIDGE_RAW_BACKUP_PATH" "$BRIDGE_RAW_PATH" || true
  fi

  if [[ -f "$BRIDGE_FIXTURE_HELPER_BACKUP_PATH" ]]; then
    restore_file_from_backup "$BRIDGE_FIXTURE_HELPER_BACKUP_PATH" "$BRIDGE_FIXTURE_HELPER_PATH" || true
  fi

  rm -rf "$RUNTIME_BUNDLE_DIR"

  if [[ -n "${DOLOS_PID:-}" ]] && kill -0 "$DOLOS_PID" 2>/dev/null; then
    kill "$DOLOS_PID" 2>/dev/null || true
    wait "$DOLOS_PID" 2>/dev/null || true
  fi

  if [[ "$KEEP_MITHRIL_BRIDGE_MINTING_TMP" != "1" ]]; then
    rm -f "$SESSION_ENV_PATH"
    rm -f "$ENV_DEFAULT_BACKUP_PATH"
    rm -f "$MAIN_TX3_BACKUP_PATH"
    rm -f "$BRIDGE_RAW_BACKUP_PATH"
    rm -f "$BRIDGE_FIXTURE_HELPER_BACKUP_PATH"
  else
    echo "Run directory kept at: $BRIDGE_MINTING_RUN_DIR"
    echo "Session manifest kept at: $SESSION_ENV_PATH"
    echo "Env backup kept at: $ENV_DEFAULT_BACKUP_PATH"
    echo "Tx3 backup kept at: $MAIN_TX3_BACKUP_PATH"
  fi
  exit "$exit_code"
}

trap 'cleanup $?' EXIT

if [[ ! -x "$SD_SCRIPT" ]]; then
  echo "Missing stake distribution script at: $SD_SCRIPT" >&2
  exit 1
fi

if [[ ! -x "$SYNC_SCRIPT" ]]; then
  echo "Missing sync script at: $SYNC_SCRIPT" >&2
  exit 1
fi

resolve_binary_path PYTHON_BIN "Python 3 binary" PYTHON_BIN python3 "$ROOT_DIR/.venv/bin/python" || exit 1
resolve_binary_path CARGO_BIN "Cargo binary" CARGO_BIN cargo || exit 1
resolve_binary_path TRIX_BIN "trix binary" TRIX_BIN trix "$ROOT_DIR/.tools/bin/trix" "$ROOT_DIR/.tools/trix" || exit 1
init_dolos_layout "$ROOT_DIR"
resolve_dolos_binary || exit 1
print_resolved_binary_if_verbose "Python 3 binary" "$PYTHON_BIN"
print_resolved_binary_if_verbose "Cargo binary" "$CARGO_BIN"
print_resolved_binary_if_verbose "trix binary" "$TRIX_BIN"
print_dolos_resolution_if_verbose
export_resolved_toolchain_env

run_flow_guardrails "bridge" "$WORKSPACE_CHECK_SCRIPT" "$TOOLING_CHECK_SCRIPT"

# shellcheck disable=SC1090
source "$COMMON_SCRIPT"

cd "$ROOT_DIR"
ensure_run_dir "$BRIDGE_MINTING_RUN_DIR"

backup_file_to_path "$ENV_DEFAULT_PATH" "$ENV_DEFAULT_BACKUP_PATH"
backup_file_to_path "$MAIN_TX3_PATH" "$MAIN_TX3_BACKUP_PATH"
backup_file_to_path "$BRIDGE_RAW_PATH" "$BRIDGE_RAW_BACKUP_PATH"
backup_file_to_path "$BRIDGE_FIXTURE_HELPER_PATH" "$BRIDGE_FIXTURE_HELPER_BACKUP_PATH"

if [[ -n "$PROOF_EXPORT_BUNDLE_PATH" ]] && [[ "$SUPPRESS_BUNDLE_SUMMARY" != "1" ]]; then
  BUNDLE_SOURCE_ID="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$PROOF_EXPORT_BUNDLE_PATH" source_bundle.source_id)"
  BUNDLE_STATEMENT_HASH="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$PROOF_EXPORT_BUNDLE_PATH" statement.statement_hash)"
  begin_stage "Mithril bundle summary"
  print_mithril_bundle_summary "$PROOF_EXPORT_BUNDLE_PATH"
fi

if [[ "$BRIDGE_MINTING_REUSE_SYNCED_TX3" == "1" ]]; then
  begin_stage "Preparing shared Aiken/Tx3 artifacts for the full bridge flow"
  SYNC_SCOPE=all "$SYNC_SCRIPT"
fi

SYNC_BRIDGE_FIXTURE_CHECK_ARGS=(--check)
if [[ -f "$RUNTIME_BUNDLE_PATH" ]]; then
  SYNC_BRIDGE_FIXTURE_CHECK_ARGS+=(--proof-export-bundle "$RUNTIME_BUNDLE_PATH")
elif [[ -n "$PROOF_EXPORT_BUNDLE_PATH" ]]; then
  SYNC_BRIDGE_FIXTURE_CHECK_ARGS+=(--proof-export-bundle "$PROOF_EXPORT_BUNDLE_PATH")
fi
BRIDGE_FIXTURE_ALREADY_CURRENT=0
if "$PYTHON_BIN" "$SYNC_BRIDGE_ZK_FIXTURE_PY" \
  --skip-test-fixture-alignment \
  "${SYNC_BRIDGE_FIXTURE_CHECK_ARGS[@]}" >/dev/null 2>&1; then
  BRIDGE_FIXTURE_ALREADY_CURRENT=1
  skip_stage "Refreshing bridge zk fixture for current policy hashes" "already current"
  if [[ -n "$PROOF_EXPORT_BUNDLE_PATH" ]]; then
    skip_stage "Refreshing runtime Mithril bundle for synced bridge state" "already current"
  fi
  skip_stage "Verifying generated Aiken bridge fixture" "already current"
else
  begin_stage "Refreshing bridge zk fixture for current policy hashes"
  SYNC_BRIDGE_FIXTURE_ARGS=(
    --fix-drift
    --skip-test-fixture-alignment
    --work-dir "$BRIDGE_MINTING_RUN_DIR/bridge-zk-fixture"
  )
  if [[ -n "$PROOF_EXPORT_BUNDLE_PATH" ]]; then
    SYNC_BRIDGE_FIXTURE_ARGS+=(--proof-export-bundle "$PROOF_EXPORT_BUNDLE_PATH")
  fi
  "$PYTHON_BIN" "$SYNC_BRIDGE_ZK_FIXTURE_PY" "${SYNC_BRIDGE_FIXTURE_ARGS[@]}"

  if [[ -n "$PROOF_EXPORT_BUNDLE_PATH" ]]; then
    begin_stage "Refreshing runtime Mithril bundle for synced bridge state"
    "$BUILD_PROOF_EXPORT_BUNDLE_SCRIPT" "$RUNTIME_BUNDLE_PATH"
    PROOF_EXPORT_BUNDLE_PATH="$RUNTIME_BUNDLE_PATH"
    BUNDLE_SOURCE_ID="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$PROOF_EXPORT_BUNDLE_PATH" source_bundle.source_id)"
    BUNDLE_STATEMENT_HASH="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$PROOF_EXPORT_BUNDLE_PATH" statement.statement_hash)"
    SYNC_BRIDGE_FIXTURE_CHECK_ARGS=(--check --proof-export-bundle "$PROOF_EXPORT_BUNDLE_PATH")
  fi

  begin_stage "Verifying generated Aiken bridge fixture"
  "$PYTHON_BIN" "$SYNC_BRIDGE_ZK_FIXTURE_PY" \
    --skip-test-fixture-alignment \
    "${SYNC_BRIDGE_FIXTURE_CHECK_ARGS[@]}"
fi

maybe_build_sibling_dolos "$CARGO_BIN" || exit 1
export DOLOS_BIN

begin_stage "Running phase1/phase2/stake-distribution setup"
STAKE_DISTRIBUTION_RUN_DIR="${STAKE_DISTRIBUTION_RUN_DIR:-$BRIDGE_MINTING_RUN_DIR/stake-distribution}" \
KEEP_MITHRIL_STAKE_DISTRIBUTION_TMP=1 \
KEEP_MITHRIL_STAKE_DISTRIBUTION_DOLOS_RUNNING=1 \
PHASE12_SKIP_SYNC="$BRIDGE_MINTING_REUSE_SYNCED_TX3" \
STAKE_DISTRIBUTION_SKIP_SYNC="$BRIDGE_MINTING_REUSE_SYNCED_TX3" \
BOB_STABLE_STAKE_DISTRIBUTION_GENESIS_SOURCE_UTXO_A="$BOB_STABLE_STAKE_DISTRIBUTION_GENESIS_SOURCE_UTXO_A" \
BOB_STABLE_STAKE_DISTRIBUTION_STANDARD_SOURCE_UTXO_A="$BOB_STABLE_STAKE_DISTRIBUTION_STANDARD_SOURCE_UTXO_A" \
BOB_STABLE_STAKE_DISTRIBUTION_STANDARD_COLLATERAL_UTXO_A="${BOB_STABLE_STAKE_DISTRIBUTION_STANDARD_COLLATERAL_UTXO_A:-8d910e3a410a353787d50a708e24c6ba2cc2b6b86ec6d8cb5bf9bbec20bfc93a#0}" \
BRIDGE_SKIP_FLOW_CHECKS=1 \
SUPPRESS_BUNDLE_SUMMARY=1 \
SUPPRESS_SESSION_MANIFEST_MSG=1 \
TX3_SESSION_ENV_PATH="$SESSION_ENV_PATH" \
"$SD_SCRIPT"

if [[ ! -f "$SESSION_ENV_PATH" ]]; then
  echo "The stake distribution flow did not produce a session manifest." >&2
  exit 1
fi

"$SESSION_MANIFEST_CHECK_SCRIPT" --mode stake-distribution --file "$SESSION_ENV_PATH"

# shellcheck disable=SC1090
source "$SESSION_ENV_PATH"

require_session_manifest_var "$SESSION_ENV_PATH" PHASE2_HASH_CARDANO_TRANSACTIONS "building the bridge mint args from the cardano_transactions phase2 proof"
require_session_manifest_var "$SESSION_ENV_PATH" STATEMENT_HASH_CARDANO_TRANSACTIONS "building the bridge mint args from the cardano_transactions statement hash"

TMP_DIR="$BRIDGE_MINTING_RUN_DIR"
LOCKING_GENESIS_ARGS_PATH="$TMP_DIR/locking-txs-updater-genesis-args.json"
LOCKING_SEED_ARGS_PATH="$TMP_DIR/locking-txs-updater-seed-args.json"
LOCKING_SEED_RESULT_PATH="$TMP_DIR/locking-txs-updater-seed-submit.json"
BRIDGE_MINT_ARGS_PATH="$TMP_DIR/bridge-mint-args.json"
PUBLISH_LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_ARGS_PATH="$TMP_DIR/publish-minting-txs-updater-spend-reference-script-args.json"
PUBLISH_LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_RESULT_PATH="$TMP_DIR/publish-minting-txs-updater-spend-reference-script-submit.json"
PUBLISH_BRIDGE_MINTING_REFERENCE_SCRIPT_ARGS_PATH="$TMP_DIR/publish-bridge-minting-reference-script-args.json"
PUBLISH_BRIDGE_MINTING_REFERENCE_SCRIPT_RESULT_PATH="$TMP_DIR/publish-bridge-minting-reference-script-submit.json"
LOCKING_GENESIS_RESULT_PATH="$TMP_DIR/minting-txs-updater-seed-submit.json"
BRIDGE_MINT_SKIP_PATH="$TMP_DIR/bridge-mint-skip.json"
BRIDGE_MINT_PATCHED_PATH="$TMP_DIR/bridge-mint-patched.json"
BRIDGE_MINT_SIGNED_PATH="$TMP_DIR/bridge-mint-signed.json"
BRIDGE_MINT_SUBMIT_PATH="$TMP_DIR/bridge-mint-submit-response.json"
BRIDGE_MINT_RESULT_PATH="$TMP_DIR/bridge-mint-submit.json"
BRIDGE_FLOW_CSV_PATH="${BRIDGE_FLOW_CSV_PATH:-$BRIDGE_FLOW_CSV_PATH_DEFAULT}"
LOCKING_TXS_UPDATER_SEED_OUTPUT_LOVELACE="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$LOCKING_TXS_UPDATER_SEED_RAW_PATH" seed_output_lovelace)"

cat >"$LOCKING_SEED_ARGS_PATH" <<EOF
{
  "user": "$USER_ADDRESS",
  "seed_output_lovelace": $LOCKING_TXS_UPDATER_SEED_OUTPUT_LOVELACE,
  "source_utxo": "$BOB_STABLE_LOCKING_SEED_SOURCE_UTXO_A",
  "collateral_utxo": "$BOB_STABLE_LOCKING_SEED_COLLATERAL_UTXO_A"
}
EOF

begin_stage "Submitting locking_txs_updater_seed_tx"
cshell_tx_invoke \
  locking_txs_updater_seed_tx \
  "$LOCKING_SEED_ARGS_PATH" \
  "$LOCKING_SEED_RESULT_PATH"

LOCKING_TXS_UPDATER_SEED_HASH="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$LOCKING_SEED_RESULT_PATH" hash)"
LOCKING_TXS_UPDATER_UNIQUE_MINT_UTXO="${LOCKING_TXS_UPDATER_SEED_HASH}#1"

if [[ "$BRIDGE_MINTING_REUSE_SYNCED_TX3" == "1" ]]; then
  skip_stage "Syncing Aiken/Tx3 artifacts for bridge" "shared sync already prepared"
else
  begin_stage "Syncing Aiken/Tx3 artifacts for bridge"
  SYNC_SCOPE=bridge "$SYNC_SCRIPT"
  begin_stage "Refreshing Tx3 invoke interface"
  run_logged "trix build" "$TRIX_BIN" build -v
fi

if [[ "${BRIDGE_FLOW_VERBOSE:-0}" == "1" ]]; then
  begin_stage "Preparing locking txs updater + bridge mint args"
fi
PREPARE_MITHRIL_BRIDGE_ARGS_CMD=(
  "$PYTHON_BIN" "$PREPARE_MITHRIL_BRIDGE_ARGS_PY"
  "$LOCKING_GENESIS_ARGS_PATH"
  "$BRIDGE_MINT_ARGS_PATH"
  "$USER_ADDRESS"
  "$PHASE2_HASH_CARDANO_TRANSACTIONS"
  "$STATEMENT_HASH_CARDANO_TRANSACTIONS"
  "$STAKE_DISTRIBUTION_STANDARD_HASH"
  "$LOCKING_TXS_UPDATER_UNIQUE_MINT_UTXO"
  "${LOCKING_TXS_UPDATER_SEED_HASH}#1"
)
if [[ -n "$PROOF_EXPORT_BUNDLE_PATH" ]]; then
  PREPARE_MITHRIL_BRIDGE_ARGS_CMD+=(--proof-export-bundle "$PROOF_EXPORT_BUNDLE_PATH")
fi
"${PREPARE_MITHRIL_BRIDGE_ARGS_CMD[@]}"

cat >"$PUBLISH_LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_ARGS_PATH" <<EOF
{
  "user": "$USER_ADDRESS",
  "reference_script_lovelace": ${BOB_REFERENCE_INPUT_LOVELACE:-10000000},
  "source_utxo": "$BOB_STABLE_PUBLISH_LOCKING_TXS_UPDATER_SOURCE_UTXO_A"
}
EOF

cat >"$PUBLISH_BRIDGE_MINTING_REFERENCE_SCRIPT_ARGS_PATH" <<EOF
{
  "user": "$USER_ADDRESS",
  "reference_script_lovelace": ${BOB_REFERENCE_INPUT_LOVELACE:-10000000},
  "source_utxo": "$BOB_STABLE_PUBLISH_BRIDGE_MINTING_SOURCE_UTXO_A"
}
EOF

begin_stage "Submitting publish_minting_txs_updater_spend_reference_script"
cshell_tx_invoke \
  publish_minting_txs_updater_spend_reference_script \
  "$PUBLISH_LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_ARGS_PATH" \
  "$PUBLISH_LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_RESULT_PATH"

PUBLISH_LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_HASH="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$PUBLISH_LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_RESULT_PATH" hash)"
PUBLISH_LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_OUTPUT_INDEX="$(reference_script_output_index "$PUBLISH_LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_RESULT_PATH")"
LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_UTXO="${PUBLISH_LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_HASH}#${PUBLISH_LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_OUTPUT_INDEX}"
print_tx_publish_summary "publish_minting_txs_updater_spend_reference_script" "$PUBLISH_LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_RESULT_PATH" "$LOCKING_SEED_RESULT_PATH"

begin_stage "Submitting publish_bridge_minting_reference_script"
cshell_tx_invoke \
  publish_bridge_minting_reference_script \
  "$PUBLISH_BRIDGE_MINTING_REFERENCE_SCRIPT_ARGS_PATH" \
  "$PUBLISH_BRIDGE_MINTING_REFERENCE_SCRIPT_RESULT_PATH"

PUBLISH_BRIDGE_MINTING_REFERENCE_SCRIPT_HASH="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$PUBLISH_BRIDGE_MINTING_REFERENCE_SCRIPT_RESULT_PATH" hash)"
PUBLISH_BRIDGE_MINTING_REFERENCE_SCRIPT_OUTPUT_INDEX="$(reference_script_output_index "$PUBLISH_BRIDGE_MINTING_REFERENCE_SCRIPT_RESULT_PATH")"
BRIDGE_MINTING_REFERENCE_SCRIPT_UTXO="${PUBLISH_BRIDGE_MINTING_REFERENCE_SCRIPT_HASH}#${PUBLISH_BRIDGE_MINTING_REFERENCE_SCRIPT_OUTPUT_INDEX}"
print_tx_publish_summary "publish_bridge_minting_reference_script" "$PUBLISH_BRIDGE_MINTING_REFERENCE_SCRIPT_RESULT_PATH" "$PUBLISH_LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_RESULT_PATH" "$LOCKING_SEED_RESULT_PATH"

"$PYTHON_BIN" "$SET_JSON_FIELD_PY" \
  "$LOCKING_GENESIS_ARGS_PATH" \
  bridge_collateral_lovelace \
  "$BRIDGE_MINT_COLLATERAL_LOVELACE"
"$PYTHON_BIN" "$SET_JSON_FIELD_PY" "$LOCKING_GENESIS_ARGS_PATH" source_utxo "$BOB_STABLE_LOCKING_GENESIS_SOURCE_UTXO_A"

LOCKING_GENESIS_COLLATERAL_UTXO="$BOB_STABLE_LOCKING_GENESIS_COLLATERAL_UTXO_A"
"$PYTHON_BIN" "$SET_JSON_FIELD_PY" "$LOCKING_GENESIS_ARGS_PATH" collateral_utxo "$LOCKING_GENESIS_COLLATERAL_UTXO"

begin_stage "Submitting minting_txs_updater_seed_tx"
cshell_tx_invoke \
  minting_txs_updater_seed_tx \
  "$LOCKING_GENESIS_ARGS_PATH" \
  "$LOCKING_GENESIS_RESULT_PATH"

LOCKING_TXS_UPDATER_GENESIS_HASH="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$LOCKING_GENESIS_RESULT_PATH" hash)"
LOCKING_TXS_UPDATER_UTXO="${LOCKING_TXS_UPDATER_GENESIS_HASH}#0"
"$PYTHON_BIN" "$SET_JSON_FIELD_PY" "$BRIDGE_MINT_ARGS_PATH" locking_txs_updater_utxo "$LOCKING_TXS_UPDATER_UTXO"
"$PYTHON_BIN" "$SET_JSON_FIELD_PY" "$BRIDGE_MINT_ARGS_PATH" locking_txs_updater_spend_reference_script_utxo "$LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_UTXO"
"$PYTHON_BIN" "$SET_JSON_FIELD_PY" "$BRIDGE_MINT_ARGS_PATH" bridge_minting_reference_script_utxo "$BRIDGE_MINTING_REFERENCE_SCRIPT_UTXO"
BRIDGE_COLLATERAL_UTXO="$BOB_STABLE_BRIDGE_MINT_COLLATERAL_UTXO_A"
BRIDGE_SOURCE_UTXO="${LOCKING_TXS_UPDATER_GENESIS_HASH}#2"
"$PYTHON_BIN" "$SET_JSON_FIELD_PY" "$BRIDGE_MINT_ARGS_PATH" source_utxo "$BRIDGE_SOURCE_UTXO"
"$PYTHON_BIN" "$SET_JSON_FIELD_PY" "$BRIDGE_MINT_ARGS_PATH" collateral_utxo "$BRIDGE_COLLATERAL_UTXO"
BRIDGE_COLLATERAL_TXID="${BRIDGE_COLLATERAL_UTXO%#*}"
BRIDGE_COLLATERAL_INDEX="${BRIDGE_COLLATERAL_UTXO##*#}"

begin_stage "Prebuilding bridge_mint_tx"
cshell_tx_invoke \
  bridge_mint_tx \
  "$BRIDGE_MINT_ARGS_PATH" \
  "$BRIDGE_MINT_SKIP_PATH" \
  --skip-submit

begin_stage "Patching bridge_mint_tx budget"
if [[ ! -f "$PATCH_BRIDGE_MINT_TX_MANIFEST" ]]; then
  echo "Missing local patch_bridge_mint_tx helper manifest at: $PATCH_BRIDGE_MINT_TX_MANIFEST" >&2
  exit 1
fi
Patch_bridge_mint_tx_cargo_locked_args=()
if [[ -f "$(dirname "$PATCH_BRIDGE_MINT_TX_MANIFEST")/Cargo.lock" ]]; then
  Patch_bridge_mint_tx_cargo_locked_args=(--locked)
fi
run_logged "cargo run patch_bridge_mint_tx" "$CARGO_BIN" run "${Patch_bridge_mint_tx_cargo_locked_args[@]}" --manifest-path "$PATCH_BRIDGE_MINT_TX_MANIFEST" -- \
  "$BRIDGE_MINT_SKIP_PATH" \
  "$BRIDGE_MINT_PATCHED_PATH" \
  "$ROOT_DIR/.tx3/dolos/conway.json" \
  "$ROOT_DIR/.tx3/dolos/alonzo.json" \
  "$BRIDGE_MINT_MINT_EX_MEM" \
  "$BRIDGE_MINT_MINT_EX_STEPS" \
  "$BRIDGE_MINT_FEE_BUFFER" \
  "$BRIDGE_COLLATERAL_TXID" \
  "$BRIDGE_COLLATERAL_INDEX"
mv "$BRIDGE_MINT_PATCHED_PATH" "$BRIDGE_MINT_SKIP_PATH"

begin_stage "Re-signing patched bridge_mint_tx"
cshell_tx_sign \
  "$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$BRIDGE_MINT_SKIP_PATH" cbor)" \
  "$BRIDGE_MINT_SIGNED_PATH"

CARDANO_TRANSACTIONS_PHASE2_RESULT_PATH="${PHASE2_RESULT_PATH_CARDANO_TRANSACTIONS:-${PHASE12_ALL_RUN_DIR:-$BRIDGE_MINTING_RUN_DIR/stake-distribution/phase12-all}/cardano_transactions/phase2-submit.json}"
print_tx_publish_summary "bridge_mint_tx" "$BRIDGE_MINT_SKIP_PATH" "$LOCKING_GENESIS_RESULT_PATH" "$PUBLISH_BRIDGE_MINTING_REFERENCE_SCRIPT_RESULT_PATH" "$PUBLISH_LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_RESULT_PATH" "$LOCKING_SEED_RESULT_PATH" "$SD_STANDARD_RESULT_PATH" "$CARDANO_TRANSACTIONS_PHASE2_RESULT_PATH"

begin_stage "Submitting bridge_mint_tx"
cshell_tx_submit \
  "$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$BRIDGE_MINT_SIGNED_PATH" cbor)" \
  "$BRIDGE_MINT_SUBMIT_PATH"

"$PYTHON_BIN" "$BUILD_SUBMIT_RESULT_PY" \
  "$BRIDGE_MINT_SIGNED_PATH" \
  "$BRIDGE_MINT_SUBMIT_PATH" \
  "$BRIDGE_MINT_RESULT_PATH"

BRIDGE_MINT_HASH="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$BRIDGE_MINT_RESULT_PATH" hash)"
print_tx_publish_summary "minting_txs_updater_seed_tx" "$LOCKING_GENESIS_RESULT_PATH" "$SD_STANDARD_RESULT_PATH"
print_tx_publish_summary "locking_txs_updater_seed_tx" "$LOCKING_SEED_RESULT_PATH" "$SD_STANDARD_RESULT_PATH"

"$PYTHON_BIN" "$WRITE_BRIDGE_FLOW_CSV_PY" \
  "$BRIDGE_FLOW_CSV_PATH" \
  "${BOB_REFERENCE_INPUT_LOVELACE:-10000000}" \
  publish_phase1_reference_script "${PUBLISH_PHASE1_REFERENCE_SCRIPT_RESULT_PATH_STAKE_DISTRIBUTION_GENESIS:-$PUBLISH_PHASE1_REFERENCE_SCRIPT_RESULT_PATH}" \
  phase1_setup_stake_distribution_standard "${PHASE1_RESULT_PATH_STAKE_DISTRIBUTION_STANDARD:-${PHASE12_ALL_RUN_DIR:-$BRIDGE_MINTING_RUN_DIR/stake-distribution/phase12-all}/stake_distribution_standard/phase1-submit.json}" \
  phase2_verify_stake_distribution_standard "${PHASE2_RESULT_PATH_STAKE_DISTRIBUTION_STANDARD:-${PHASE12_ALL_RUN_DIR:-$BRIDGE_MINTING_RUN_DIR/stake-distribution/phase12-all}/stake_distribution_standard/phase2-submit.json}" \
  phase1_setup_cardano_transactions "${PHASE1_RESULT_PATH_CARDANO_TRANSACTIONS:-${PHASE12_ALL_RUN_DIR:-$BRIDGE_MINTING_RUN_DIR/stake-distribution/phase12-all}/cardano_transactions/phase1-submit.json}" \
  phase2_verify_cardano_transactions "${PHASE2_RESULT_PATH_CARDANO_TRANSACTIONS:-${PHASE12_ALL_RUN_DIR:-$BRIDGE_MINTING_RUN_DIR/stake-distribution/phase12-all}/cardano_transactions/phase2-submit.json}" \
  stake_distribution_genesis_tx "$SD_GENESIS_RESULT_PATH" \
  stake_distribution_standard_tx "$SD_STANDARD_RESULT_PATH" \
  locking_txs_updater_seed_tx "$LOCKING_SEED_RESULT_PATH" \
  publish_minting_txs_updater_spend_reference_script "$PUBLISH_LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_RESULT_PATH" \
  publish_bridge_minting_reference_script "$PUBLISH_BRIDGE_MINTING_REFERENCE_SCRIPT_RESULT_PATH" \
  minting_txs_updater_seed_tx "$LOCKING_GENESIS_RESULT_PATH" \
  bridge_mint_tx "$BRIDGE_MINT_RESULT_PATH" >/dev/null

cat >>"$SESSION_ENV_PATH" <<EOF
LOCKING_SEED_ARGS_PATH=$(printf '%q' "$LOCKING_SEED_ARGS_PATH")
LOCKING_SEED_RESULT_PATH=$(printf '%q' "$LOCKING_SEED_RESULT_PATH")
LOCKING_GENESIS_ARGS_PATH=$(printf '%q' "$LOCKING_GENESIS_ARGS_PATH")
BRIDGE_MINT_ARGS_PATH=$(printf '%q' "$BRIDGE_MINT_ARGS_PATH")
PUBLISH_LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_ARGS_PATH=$(printf '%q' "$PUBLISH_LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_ARGS_PATH")
PUBLISH_LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_RESULT_PATH=$(printf '%q' "$PUBLISH_LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_RESULT_PATH")
PUBLISH_BRIDGE_MINTING_REFERENCE_SCRIPT_ARGS_PATH=$(printf '%q' "$PUBLISH_BRIDGE_MINTING_REFERENCE_SCRIPT_ARGS_PATH")
PUBLISH_BRIDGE_MINTING_REFERENCE_SCRIPT_RESULT_PATH=$(printf '%q' "$PUBLISH_BRIDGE_MINTING_REFERENCE_SCRIPT_RESULT_PATH")
LOCKING_GENESIS_RESULT_PATH=$(printf '%q' "$LOCKING_GENESIS_RESULT_PATH")
BRIDGE_MINT_SKIP_PATH=$(printf '%q' "$BRIDGE_MINT_SKIP_PATH")
BRIDGE_MINT_SIGNED_PATH=$(printf '%q' "$BRIDGE_MINT_SIGNED_PATH")
BRIDGE_MINT_SUBMIT_PATH=$(printf '%q' "$BRIDGE_MINT_SUBMIT_PATH")
BRIDGE_MINT_RESULT_PATH=$(printf '%q' "$BRIDGE_MINT_RESULT_PATH")
PUBLISH_LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_HASH=$(printf '%q' "$PUBLISH_LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_HASH")
PUBLISH_LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_OUTPUT_INDEX=$(printf '%q' "$PUBLISH_LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_OUTPUT_INDEX")
LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_UTXO=$(printf '%q' "$LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_UTXO")
PUBLISH_BRIDGE_MINTING_REFERENCE_SCRIPT_HASH=$(printf '%q' "$PUBLISH_BRIDGE_MINTING_REFERENCE_SCRIPT_HASH")
PUBLISH_BRIDGE_MINTING_REFERENCE_SCRIPT_OUTPUT_INDEX=$(printf '%q' "$PUBLISH_BRIDGE_MINTING_REFERENCE_SCRIPT_OUTPUT_INDEX")
BRIDGE_MINTING_REFERENCE_SCRIPT_UTXO=$(printf '%q' "$BRIDGE_MINTING_REFERENCE_SCRIPT_UTXO")
LOCKING_TXS_UPDATER_SEED_HASH=$(printf '%q' "$LOCKING_TXS_UPDATER_SEED_HASH")
LOCKING_TXS_UPDATER_GENESIS_HASH=$(printf '%q' "$LOCKING_TXS_UPDATER_GENESIS_HASH")
BRIDGE_MINT_HASH=$(printf '%q' "$BRIDGE_MINT_HASH")
LOCKING_TXS_UPDATER_UTXO=$(printf '%q' "$LOCKING_TXS_UPDATER_UTXO")
LOCKING_TXS_UPDATER_UNIQUE_MINT_UTXO=$(printf '%q' "$LOCKING_TXS_UPDATER_UNIQUE_MINT_UTXO")
BRIDGE_SOURCE_UTXO=$(printf '%q' "$BRIDGE_SOURCE_UTXO")
BRIDGE_COLLATERAL_UTXO=$(printf '%q' "$BRIDGE_COLLATERAL_UTXO")
BRIDGE_FLOW_CSV_PATH=$(printf '%q' "$BRIDGE_FLOW_CSV_PATH")
EOF
append_effective_toolchain_manifest "$SESSION_ENV_PATH"
persist_mithril_aggregator_fingerprint "$BRIDGE_MINTING_RUN_DIR" "$SESSION_ENV_PATH"
if [[ "${BRIDGE_FLOW_VERBOSE:-0}" == "1" ]]; then
  echo "Session manifest written to: $SESSION_ENV_PATH"
fi

echo "Mithril bridge minting flow passed."
echo "publish_phase1_reference_script hash: $PUBLISH_PHASE1_REFERENCE_SCRIPT_HASH"
echo "phase1_setup hash:                   $PHASE1_HASH"
echo "phase2_verify cardano tx hash:       $PHASE2_HASH_CARDANO_TRANSACTIONS"
echo "stake_distribution_genesis_tx hash:  $STAKE_DISTRIBUTION_GENESIS_HASH"
echo "stake_distribution_standard_tx hash: $STAKE_DISTRIBUTION_STANDARD_HASH"
echo "locking_txs_updater_seed_tx hash:    $LOCKING_TXS_UPDATER_SEED_HASH"
echo "publish_minting_txs_updater_spend_reference_script hash: $PUBLISH_LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_HASH"
echo "publish_bridge_minting_reference_script hash:            $PUBLISH_BRIDGE_MINTING_REFERENCE_SCRIPT_HASH"
echo "minting_txs_updater_seed_tx hash: $LOCKING_TXS_UPDATER_GENESIS_HASH"
echo "bridge_mint_tx hash:                 $BRIDGE_MINT_HASH"
echo "bridge flow csv:                    $BRIDGE_FLOW_CSV_PATH"

"$SESSION_MANIFEST_CHECK_SCRIPT" --mode bridge --file "$SESSION_ENV_PATH"
