#!/usr/bin/env bash
#
# Builds the canonical bridge-compatible Mithril STM bundle consumed by
# the Aiken validators (phase1, phase2, stake_distribution and bridge).
#
# Starting from the stake distribution fixtures (genesis/standard) and
# the bridge raw data, it generates the intermediate bundles, runs the
# halo2 verifier off-chain to produce phase1_state + reduced_redeemer
# per domain, and packages everything into the multi-proof
# `bridge-compatible-mithril-stm-bundle.json`. Idempotent via an input
# fingerprint.

set -euo pipefail

# Workspace and auxiliary script paths (verifier-gen Rust binaries,
# Python helpers, shared libraries, and canonical input data).
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_DIR="$ROOT_DIR/scripts/python"
VERIFIER_GEN_DIR="$ROOT_DIR/../plutus-halo2-verifier-gen"
VERIFIER_GEN_CARGO_LOCK="$VERIFIER_GEN_DIR/Cargo.lock"
VERIFIER_GEN_TARGET_DIR="${VERIFIER_GEN_TARGET_DIR:-$VERIFIER_GEN_DIR/target}"
EXPORT_FIXTURE_BUNDLE_BIN=""
EXPORT_PROOF_EXPORT_BIN=""
BUILD_COMPATIBLE_BUNDLE_PY="$PYTHON_DIR/build_bridge_compatible_mithril_stm_bundle.py"
CHECK_PROOF_EXPORT_BUNDLE_CONTRACT_PY="$PYTHON_DIR/check_mithril_proof_export_bundle_contract.py"
READ_JSON_FIELD_PY="$PYTHON_DIR/read_json_field.py"
SET_JSON_FIELD_PY="$PYTHON_DIR/set_json_field.py"
TOOLING_CHECK_SCRIPT="$ROOT_DIR/scripts/check_local_tooling.sh"
WORKSPACE_CHECK_SCRIPT="$ROOT_DIR/scripts/check_workspace_layout.sh"
RUN_OUTPUTS_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/run_outputs_common.sh"
TOOLING_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/tooling_common.sh"
ENTRYPOINT_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/entrypoint_common.sh"
FLOW_OBSERVABILITY_SCRIPT="$ROOT_DIR/scripts/lib/flow_observability.sh"
BRIDGE_FLOW_VERBOSE="${BRIDGE_FLOW_VERBOSE:-0}"
BRIDGE_VERBOSE_CONTEXT="${BRIDGE_VERBOSE_CONTEXT:-artifact-runtime}"
RUSTFLAGS="${RUSTFLAGS:--Awarnings}"
export RUSTFLAGS
# Input fixtures: Mithril stake distribution certificates and bridge
# mint raw data (which supplies the tx snapshot merkle root).
GENESIS_FIXTURE_PATH="$ROOT_DIR/scripts/data/mithril_stake_distribution_genesis.json"
STANDARD_FIXTURE_PATH="$ROOT_DIR/scripts/data/mithril_stake_distribution_standard.json"
BRIDGE_RAW_PATH="$ROOT_DIR/scripts/data/bridge_mint_raw.json"

# Shared libraries: hashing/fingerprint helpers, toolchain resolution,
# bridge.sh wrapper handling, and stage observability.
# shellcheck disable=SC1090
source "$RUN_OUTPUTS_COMMON_SCRIPT"

# shellcheck disable=SC1090
source "$TOOLING_COMMON_SCRIPT"
# shellcheck disable=SC1090
source "$ENTRYPOINT_COMMON_SCRIPT"
# shellcheck disable=SC1090
source "$FLOW_OBSERVABILITY_SCRIPT"

# If this script is invoked directly (not via bridge.sh), re-enter
# through the wrapper for unified logging/observability.
handoff_to_wrapper_if_direct "$ROOT_DIR/scripts/bridge.sh" proof-export-bundle "$@"

# Force `--locked` when Cargo.lock is present, for reproducible builds.
CARGO_LOCKED_ARGS=()
if [[ -f "$VERIFIER_GEN_CARGO_LOCK" ]]; then
  CARGO_LOCKED_ARGS=(--locked)
fi

# Runs a command capturing stdout/stderr into a temporary log. On
# failure, prints the log tail and records the failure context.
run_logged() {
  local label="$1"
  shift

  if [[ "$BRIDGE_FLOW_VERBOSE" == "1" ]]; then
    "$@"
    return
  fi

  local log_path
  if [[ -n "${BRIDGE_LOG_DIR:-}" ]]; then
    log_path="$(mktemp_in_dir "$BRIDGE_LOG_DIR" "bridge-artifact-${label// /-}.XXXXXX.log")"
  else
    log_path="$(mktemp_in_dir "${TMPDIR:-/tmp}" "bridge-artifact-${label// /-}.XXXXXX.log")"
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

# Background job pool: PIDs, labels, commands and logs. Used to launch
# the bundle exports in parallel (they are independent).
BG_PIDS=()
BG_LABELS=()
BG_COMMANDS=()
BG_LOGS=()

reset_bg_jobs() {
  BG_PIDS=()
  BG_LABELS=()
  BG_COMMANDS=()
  BG_LOGS=()
}

# Launches a command in the background with its own log, registering it
# in the pool so wait_for_logged_bg_jobs can wait for all of them together.
launch_logged_bg() {
  local label="$1"
  shift

  local log_path
  if [[ -n "${BRIDGE_LOG_DIR:-}" ]]; then
    log_path="$(mktemp_in_dir "$BRIDGE_LOG_DIR" "bridge-artifact-${label// /-}.XXXXXX.log")"
  else
    log_path="$(mktemp_in_dir "${TMPDIR:-/tmp}" "bridge-artifact-${label// /-}.XXXXXX.log")"
  fi

  (
    "$@" >"$log_path" 2>&1
  ) &

  BG_PIDS+=("$!")
  BG_LABELS+=("$label")
  BG_COMMANDS+=("$*")
  BG_LOGS+=("$log_path")
}

# Waits for every job in the pool. If any failed, reports the first one
# (with log tail) and propagates its exit code.
wait_for_logged_bg_jobs() {
  local idx=""
  local status=0
  local first_failure_idx=-1

  for idx in "${!BG_PIDS[@]}"; do
    if ! wait "${BG_PIDS[$idx]}"; then
      status=$?
      if [[ "$first_failure_idx" -lt 0 ]]; then
        first_failure_idx="$idx"
      fi
    fi
  done

  if [[ "$first_failure_idx" -ge 0 ]]; then
    set_last_command_failure_context \
      "${BG_LABELS[$first_failure_idx]}" \
      "${BG_COMMANDS[$first_failure_idx]}" \
      "${BG_LOGS[$first_failure_idx]}"

    echo "Command failed during: ${BG_LABELS[$first_failure_idx]}" >&2
    echo "Command: ${BG_COMMANDS[$first_failure_idx]}" >&2
    echo "Log: ${BG_LOGS[$first_failure_idx]}" >&2
    echo "--- log tail ---" >&2
    tail -n 40 "${BG_LOGS[$first_failure_idx]}" >&2 || true
    echo "--- end log tail ---" >&2
    reset_bg_jobs
    return "${status:-1}"
  fi

  for idx in "${!BG_LOGS[@]}"; do
    rm -f "${BG_LOGS[$idx]}"
  done
  reset_bg_jobs
}

# Builds the verifier-gen Rust binaries in release mode and resolves
# their paths:
#   - export_mithril_stm_fixture_bundle: assembles each bundle from fixtures.
#   - export_mithril_stm_proof_export: runs halo2 and exports the final JSON.
ensure_verifier_gen_bins() {
  run_logged "cargo build verifier-gen bins" \
    "$CARGO_BIN" build "${CARGO_LOCKED_ARGS[@]}" \
      --manifest-path "$VERIFIER_GEN_DIR/Cargo.toml" \
      --release \
      --bins

  EXPORT_FIXTURE_BUNDLE_BIN="$VERIFIER_GEN_TARGET_DIR/release/export_mithril_stm_fixture_bundle"
  EXPORT_PROOF_EXPORT_BIN="$VERIFIER_GEN_TARGET_DIR/release/export_mithril_stm_proof_export"

  if [[ ! -x "$EXPORT_FIXTURE_BUNDLE_BIN" ]]; then
    echo "Missing compiled export_mithril_stm_fixture_bundle binary at: $EXPORT_FIXTURE_BUNDLE_BIN" >&2
    exit 1
  fi

  if [[ ! -x "$EXPORT_PROOF_EXPORT_BIN" ]]; then
    echo "Missing compiled export_mithril_stm_proof_export binary at: $EXPORT_PROOF_EXPORT_BIN" >&2
    exit 1
  fi
}

# Computes a sha256 summarising every input that affects the proof-export
# bundle: builder version, signed messages of each certificate, hashes of this
# script + Python helper + fixtures + Cargo.toml/lock + Rust sources.
# Used to compare against the persisted fingerprint to decide whether to rebuild.
compute_proof_export_bundle_inputs_fingerprint() {
  {
    printf 'proof-export-bundle-builder-v2\n'
    printf 'sd_genesis_message=%s\n' "$SD_GENESIS_MESSAGE"
    printf 'sd_standard_message=%s\n' "$SD_STANDARD_MESSAGE"
    printf 'tx_snapshot_message=%s\n' "$TX_SNAPSHOT_MESSAGE"
    printf '%s  %s\n' "$(sha256_file "$0")" "$0"
    printf '%s  %s\n' "$(sha256_file "$BUILD_COMPATIBLE_BUNDLE_PY")" "$BUILD_COMPATIBLE_BUNDLE_PY"
    printf '%s  %s\n' "$(sha256_file "$GENESIS_FIXTURE_PATH")" "$GENESIS_FIXTURE_PATH"
    printf '%s  %s\n' "$(sha256_file "$STANDARD_FIXTURE_PATH")" "$STANDARD_FIXTURE_PATH"
    printf '%s  %s\n' "$(sha256_file "$BRIDGE_RAW_PATH")" "$BRIDGE_RAW_PATH"
    printf '%s  %s\n' "$(sha256_file "$VERIFIER_GEN_DIR/Cargo.toml")" "$VERIFIER_GEN_DIR/Cargo.toml"
    if [[ -f "$VERIFIER_GEN_DIR/Cargo.lock" ]]; then
      printf '%s  %s\n' "$(sha256_file "$VERIFIER_GEN_DIR/Cargo.lock")" "$VERIFIER_GEN_DIR/Cargo.lock"
    fi
    find "$VERIFIER_GEN_DIR/src" -type f -print0 | hash_sorted_files_from_stdin0
  } | sha256_stream
}

# Checks that every intermediate and final output exists, and that the
# combined bundle has the `proofs` section (i.e. it was not left stale
# by an interrupted run).
all_proof_export_bundle_outputs_present() {
  local path
  for path in \
    "$BASE_BUNDLE_PATH" \
    "$SD_GENESIS_BUNDLE_PATH" \
    "$SD_STANDARD_BUNDLE_PATH" \
    "$TX_SNAPSHOT_BUNDLE_PATH" \
    "$SD_GENESIS_PROOF_EXPORT_PATH" \
    "$SD_STANDARD_PROOF_EXPORT_PATH" \
    "$TX_SNAPSHOT_PROOF_EXPORT_PATH" \
    "$OUTPUT_BUNDLE_PATH"; do
    [[ -f "$path" ]] || return 1
  done

  "$PYTHON_BIN" - "$OUTPUT_BUNDLE_PATH" <<'PY' >/dev/null 2>&1 || return 1
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
if not isinstance(data.get("proofs"), dict):
    raise SystemExit(1)
PY
}

# Single positional argument: path of the final bundle to generate.
if [[ $# -ne 1 ]]; then
  echo "usage: build_bridge_compatible_mithril_stm_proof_export_bundle.sh <output-bundle-json>" >&2
  exit 1
fi

# Resolves and exports the toolchain (Python 3, Cargo) and validates
# workspace + local tooling before starting the build.
resolve_binary_path PYTHON_BIN "Python 3 binary" PYTHON_BIN python3 "$ROOT_DIR/.venv/bin/python" || exit 1
resolve_binary_path CARGO_BIN "Cargo binary" CARGO_BIN cargo || exit 1
print_resolved_binary_if_verbose "Python 3 binary" "$PYTHON_BIN"
print_resolved_binary_if_verbose "Cargo binary" "$CARGO_BIN"
export_resolved_toolchain_env

"$WORKSPACE_CHECK_SCRIPT" --flow proof-export-bundle
"$TOOLING_CHECK_SCRIPT" --flow proof-export-bundle

# Resolves the output directory and declares the paths of every
# intermediate and final proof export that will be produced:
#   - bundles: base + one per domain (sd_genesis, sd_standard, tx_snapshot).
#   - partial proof exports: one per proof bundle.
#   - final multi-proof bundle + persisted input fingerprint.
OUTPUT_BUNDLE_PATH="$1"
mkdir -p "$(dirname "$OUTPUT_BUNDLE_PATH")"
OUTPUT_DIR="$(cd "$(dirname "$OUTPUT_BUNDLE_PATH")" && pwd)"
OUTPUT_BUNDLE_BASENAME="$(basename "$OUTPUT_BUNDLE_PATH")"
OUTPUT_BUNDLE_PATH="$OUTPUT_DIR/$OUTPUT_BUNDLE_BASENAME"
BASE_BUNDLE_PATH="$OUTPUT_DIR/bridge-compatible-mithril-stm-base-bundle.json"
SD_GENESIS_BUNDLE_PATH="$OUTPUT_DIR/bridge-compatible-mithril-stm-sd-genesis-bundle.json"
SD_STANDARD_BUNDLE_PATH="$OUTPUT_DIR/bridge-compatible-mithril-stm-sd-standard-bundle.json"
TX_SNAPSHOT_BUNDLE_PATH="$OUTPUT_DIR/bridge-compatible-mithril-stm-tx-snapshot-bundle.json"
SD_GENESIS_PROOF_EXPORT_PATH="$OUTPUT_DIR/bridge-compatible-mithril-stm-sd-genesis-proof-export.json"
SD_STANDARD_PROOF_EXPORT_PATH="$OUTPUT_DIR/bridge-compatible-mithril-stm-sd-standard-proof-export.json"
TX_SNAPSHOT_PROOF_EXPORT_PATH="$OUTPUT_DIR/bridge-compatible-mithril-stm-tx-snapshot-proof-export.json"
PROOF_EXPORT_BUNDLE_FINGERPRINT_PATH="$OUTPUT_DIR/bridge-compatible-mithril-stm-bundle.inputs.sha256"
# Signed messages of each Mithril certificate. Critical inputs: they
# define public_input_2 of the SNARK and feed into the fingerprint.
SD_GENESIS_MESSAGE="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$GENESIS_FIXTURE_PATH" signed_message_text)"
SD_STANDARD_MESSAGE="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$STANDARD_FIXTURE_PATH" signed_message_text)"
TX_SNAPSHOT_MESSAGE="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$BRIDGE_RAW_PATH" tx_snapshot_certificate_protocol_message_cardano_transactions_merkle_root_text)"

# Initializes stage observability and records success/failure on exit.
setup_flow_observability "$OUTPUT_DIR" "proof-export-bundle"
trap 'flow_exit=$?; if [[ "$flow_exit" -eq 0 ]]; then finalize_flow_success; else finalize_flow_failure "$flow_exit"; fi' EXIT

# Idempotent short-circuit: if the current fingerprint matches the
# persisted one and every output is present, there is nothing to redo.
PROOF_EXPORT_BUNDLE_INPUTS_FINGERPRINT="$(compute_proof_export_bundle_inputs_fingerprint)"
if [[ -f "$PROOF_EXPORT_BUNDLE_FINGERPRINT_PATH" ]] && [[ "$(cat "$PROOF_EXPORT_BUNDLE_FINGERPRINT_PATH")" == "$PROOF_EXPORT_BUNDLE_INPUTS_FINGERPRINT" ]] && all_proof_export_bundle_outputs_present; then
  skip_stage "Building bridge-compatible Mithril STM bundle" "fingerprint unchanged"
  persist_mithril_aggregator_fingerprint "$OUTPUT_DIR"
  echo "Bridge-compatible Mithril STM bundle written to: $OUTPUT_BUNDLE_PATH"
  exit 0
fi

begin_stage "Building bridge-compatible Mithril STM bundle"

# Build the verifier-gen Rust binaries before using them.
ensure_verifier_gen_bins

# Base bundle (no signed message): provides the common data shared by
# every proof (circuit parameters, registration keys, etc).
run_logged "export_mithril_stm_fixture_bundle base" "$EXPORT_FIXTURE_BUNDLE_BIN" \
  --output "$BASE_BUNDLE_PATH"
# Per-domain bundles in parallel: each one takes the signed message of
# its certificate and generates the bundle specialised for that proof.
launch_logged_bg "export_mithril_stm_fixture_bundle sd genesis" "$EXPORT_FIXTURE_BUNDLE_BIN" \
  --output "$SD_GENESIS_BUNDLE_PATH" \
  --message "$SD_GENESIS_MESSAGE"
launch_logged_bg "export_mithril_stm_fixture_bundle sd standard" "$EXPORT_FIXTURE_BUNDLE_BIN" \
  --output "$SD_STANDARD_BUNDLE_PATH" \
  --message "$SD_STANDARD_MESSAGE"
launch_logged_bg "export_mithril_stm_fixture_bundle tx snapshot" "$EXPORT_FIXTURE_BUNDLE_BIN" \
  --output "$TX_SNAPSHOT_BUNDLE_PATH" \
  --message "$TX_SNAPSHOT_MESSAGE"
wait_for_logged_bg_jobs
# Normalises the child certificate's `signed_message` in the bundles
# whose message came from an external hex: replaces it with the
# canonical digest that actually entered the SNARK as public_input_2.
# That way the `child.signed_message == public_input_2` invariant holds.
SD_GENESIS_NORMALIZED_MESSAGE="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$SD_GENESIS_BUNDLE_PATH" statement.public_input_2_signed_message)"
TX_SNAPSHOT_NORMALIZED_MESSAGE="$("$PYTHON_BIN" "$READ_JSON_FIELD_PY" "$TX_SNAPSHOT_BUNDLE_PATH" statement.public_input_2_signed_message)"
"$PYTHON_BIN" "$SET_JSON_FIELD_PY" \
  "$SD_GENESIS_BUNDLE_PATH" \
  certificates.child.signed_message \
  "$SD_GENESIS_NORMALIZED_MESSAGE"
"$PYTHON_BIN" "$SET_JSON_FIELD_PY" \
  "$TX_SNAPSHOT_BUNDLE_PATH" \
  certificates.child.signed_message \
  "$TX_SNAPSHOT_NORMALIZED_MESSAGE"

# Runs the halo2 verifier off-chain over each bundle: generates the
# proof, extracts phase1_state + reduced_redeemer, and produces the
# partial proof export.
run_logged "export_mithril_stm_proof_export sd genesis" "$EXPORT_PROOF_EXPORT_BIN" \
  --input "$SD_GENESIS_BUNDLE_PATH" \
  --output "$SD_GENESIS_PROOF_EXPORT_PATH"
run_logged "export_mithril_stm_proof_export sd standard" "$EXPORT_PROOF_EXPORT_BIN" \
  --input "$SD_STANDARD_BUNDLE_PATH" \
  --output "$SD_STANDARD_PROOF_EXPORT_PATH"
run_logged "export_mithril_stm_proof_export tx snapshot" "$EXPORT_PROOF_EXPORT_BIN" \
  --input "$TX_SNAPSHOT_BUNDLE_PATH" \
  --output "$TX_SNAPSHOT_PROOF_EXPORT_PATH"

# Combines the base + the 3 bundles + the 3 partial proof exports into the
# final canonical multi-proof bundle with a `proofs` section indexed by
# domain. This is the JSON consumed by the Aiken validators and the
# bridge flows.
"$PYTHON_BIN" "$BUILD_COMPATIBLE_BUNDLE_PY" \
  "$BASE_BUNDLE_PATH" \
  "$OUTPUT_BUNDLE_PATH" \
  --sd-genesis-bundle "$SD_GENESIS_BUNDLE_PATH" \
  --sd-standard-bundle "$SD_STANDARD_BUNDLE_PATH" \
  --tx-snapshot-bundle "$TX_SNAPSHOT_BUNDLE_PATH" \
  --sd-genesis-proof-export "$SD_GENESIS_PROOF_EXPORT_PATH" \
  --sd-standard-proof-export "$SD_STANDARD_PROOF_EXPORT_PATH" \
  --tx-snapshot-proof-export "$TX_SNAPSHOT_PROOF_EXPORT_PATH"

# Checks the structural/cryptographic invariants of the bundle contract
# (see validate_compatible_bundle_file in plutus-halo2-verifier-gen).
begin_stage "Validating Mithril bundle contract"
run_logged "python check_mithril_proof_export_bundle_contract" "$PYTHON_BIN" "$CHECK_PROOF_EXPORT_BUNDLE_CONTRACT_PY" "$OUTPUT_BUNDLE_PATH"

# Persist the fingerprint so the next run can skip the work if the
# inputs did not change.
printf '%s\n' "$PROOF_EXPORT_BUNDLE_INPUTS_FINGERPRINT" >"$PROOF_EXPORT_BUNDLE_FINGERPRINT_PATH"
persist_mithril_aggregator_fingerprint "$OUTPUT_DIR"

echo "Bridge-compatible Mithril STM bundle written to: $OUTPUT_BUNDLE_PATH"
