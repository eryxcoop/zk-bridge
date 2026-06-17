#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
usage: check_session_manifest.sh --mode <phase12-case|phase12-all|genesis-dual-signature|stake-distribution|bridge> --file <session.env>
EOF
}

fail_manifest_check() {
  local message="$1"
  shift || true
  echo "[session-manifest:$MODE] $message" >&2
  while [[ $# -gt 0 ]]; do
    echo "$1" >&2
    shift
  done
  exit 1
}

MODE=""
FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift 2
      ;;
    --file)
      FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail_manifest_check "Unknown argument: $1"
      ;;
  esac
done

if [[ -z "$MODE" || -z "$FILE" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -f "$FILE" ]]; then
  fail_manifest_check "Missing session manifest at: $FILE"
fi

validate_manifest_source_safety() {
  local line_number=0
  local line=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))

    if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
      continue
    fi

    if [[ ! "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      fail_manifest_check \
        "Unsafe or invalid manifest line at $FILE:$line_number" \
        "Expected simple KEY=value assignments only." \
        "Offending line: $line"
    fi

    if [[ "$line" == *'$('* || "$line" == *'`'* || "$line" == *';'* || "$line" == *'&&'* || "$line" == *'||'* ]]; then
      fail_manifest_check \
        "Unsafe shell construct detected in manifest at $FILE:$line_number" \
        "Offending line: $line"
    fi
  done <"$FILE"
}

validate_manifest_source_safety

# shellcheck disable=SC1090
source "$FILE"

require_vars() {
  local missing=0
  local var_name=""

  for var_name in "$@"; do
    if [[ -z "${!var_name:-}" ]]; then
      echo "[session-manifest:$MODE] Missing required session manifest field: $var_name" >&2
      missing=1
    fi
  done

  if [[ "$missing" -ne 0 ]]; then
    exit 1
  fi
}

require_integer_vars() {
  local var_name=""

  for var_name in "$@"; do
    if [[ -n "${!var_name:-}" ]] && [[ ! "${!var_name}" =~ ^[0-9]+$ ]]; then
      fail_manifest_check "Expected integer value for $var_name, got: ${!var_name}"
    fi
  done
}

require_existing_files() {
  local var_name=""
  local path=""

  for var_name in "$@"; do
    path="${!var_name:-}"
    if [[ -n "$path" && ! -f "$path" ]]; then
      fail_manifest_check "Expected file path in $var_name, but file is missing: $path"
    fi
  done
}

require_existing_dirs() {
  local var_name=""
  local path=""

  for var_name in "$@"; do
    path="${!var_name:-}"
    if [[ -n "$path" && ! -d "$path" ]]; then
      fail_manifest_check "Expected directory path in $var_name, but directory is missing: $path"
    fi
  done
}

require_executable_files() {
  local var_name=""
  local path=""

  for var_name in "$@"; do
    path="${!var_name:-}"
    if [[ -n "$path" && ! -x "$path" ]]; then
      fail_manifest_check "Expected executable path in $var_name, but it is not executable: $path"
    fi
  done
}

require_utxo_vars() {
  local var_name=""

  for var_name in "$@"; do
    if [[ -n "${!var_name:-}" ]] && [[ ! "${!var_name}" =~ ^[^#[:space:]]+#[0-9]+$ ]]; then
      fail_manifest_check "Expected UTxO reference in $var_name, got: ${!var_name}"
    fi
  done
}

case "$MODE" in
  phase12-case)
    require_vars \
      ROOT_DIR TMP_DIR PYTHON_BIN AIKEN_BIN CARGO_BIN TRIX_BIN CSHELL_BIN DOLOS_BIN DOLOS_DEVNET_DIR DOLOS_CONFIG_PATH GRPC_PORT TRP_PORT MINIBF_PORT \
      PUBLISH_PHASE1_REFERENCE_SCRIPT_RESULT_PATH PHASE1_RESULT_PATH PHASE2_RESULT_PATH \
      PHASE1_HASH PHASE2_HASH
    require_integer_vars GRPC_PORT TRP_PORT MINIBF_PORT
    require_existing_dirs ROOT_DIR TMP_DIR DOLOS_DEVNET_DIR
    require_existing_files DOLOS_CONFIG_PATH PUBLISH_PHASE1_REFERENCE_SCRIPT_RESULT_PATH PHASE1_RESULT_PATH PHASE2_RESULT_PATH
    require_executable_files PYTHON_BIN AIKEN_BIN CARGO_BIN TRIX_BIN CSHELL_BIN DOLOS_BIN
    ;;
  phase12-all)
    require_vars \
      PYTHON_BIN AIKEN_BIN CARGO_BIN TRIX_BIN CSHELL_BIN DOLOS_BIN DOLOS_DEVNET_DIR DOLOS_PID GRPC_PORT TRP_PORT MINIBF_PORT \
      PHASE2_HASH_STAKE_DISTRIBUTION_STANDARD PHASE2_HASH_CARDANO_TRANSACTIONS \
      PHASE2_RECEIPT_UTXO_STAKE_DISTRIBUTION_STANDARD PHASE2_RECEIPT_UTXO_CARDANO_TRANSACTIONS \
      STATEMENT_HASH_STAKE_DISTRIBUTION_STANDARD STATEMENT_HASH_CARDANO_TRANSACTIONS
    require_integer_vars DOLOS_PID GRPC_PORT TRP_PORT MINIBF_PORT
    require_existing_dirs DOLOS_DEVNET_DIR
    require_executable_files PYTHON_BIN AIKEN_BIN CARGO_BIN TRIX_BIN CSHELL_BIN DOLOS_BIN
    require_utxo_vars PHASE2_RECEIPT_UTXO_STAKE_DISTRIBUTION_STANDARD PHASE2_RECEIPT_UTXO_CARDANO_TRANSACTIONS
    ;;
  stake-distribution)
    require_vars \
      TMP_DIR PYTHON_BIN AIKEN_BIN CARGO_BIN TRIX_BIN CSHELL_BIN DOLOS_BIN DOLOS_DEVNET_DIR DOLOS_PID \
      PHASE2_HASH_STAKE_DISTRIBUTION_STANDARD \
      PHASE2_RECEIPT_UTXO_STAKE_DISTRIBUTION_STANDARD \
      STATEMENT_HASH_STAKE_DISTRIBUTION_STANDARD \
      STAKE_DISTRIBUTION_GENESIS_HASH STAKE_DISTRIBUTION_STANDARD_HASH
    require_integer_vars DOLOS_PID
    require_existing_dirs TMP_DIR DOLOS_DEVNET_DIR
    require_executable_files PYTHON_BIN AIKEN_BIN CARGO_BIN TRIX_BIN CSHELL_BIN DOLOS_BIN
    require_utxo_vars PHASE2_RECEIPT_UTXO_STAKE_DISTRIBUTION_STANDARD
    ;;
  genesis-dual-signature)
    require_vars \
      TMP_DIR PYTHON_BIN AIKEN_BIN CARGO_BIN TRIX_BIN CSHELL_BIN DOLOS_BIN DOLOS_DEVNET_DIR DOLOS_PID GRPC_PORT TRP_PORT MINIBF_PORT \
      GENESIS_DUAL_ARGS_PATH GENESIS_DUAL_RESULT_PATH GENESIS_DUAL_FIXTURE_PATH \
      STAKE_DISTRIBUTION_GENESIS_HASH
    require_integer_vars DOLOS_PID GRPC_PORT TRP_PORT MINIBF_PORT
    require_existing_dirs TMP_DIR DOLOS_DEVNET_DIR
    require_existing_files GENESIS_DUAL_ARGS_PATH GENESIS_DUAL_RESULT_PATH GENESIS_DUAL_FIXTURE_PATH
    require_executable_files PYTHON_BIN AIKEN_BIN CARGO_BIN TRIX_BIN CSHELL_BIN DOLOS_BIN
    ;;
  bridge)
    require_vars \
      PYTHON_BIN AIKEN_BIN CARGO_BIN TRIX_BIN CSHELL_BIN DOLOS_BIN DOLOS_DEVNET_DIR \
      PHASE2_HASH_CARDANO_TRANSACTIONS STATEMENT_HASH_CARDANO_TRANSACTIONS \
      STAKE_DISTRIBUTION_GENESIS_HASH STAKE_DISTRIBUTION_STANDARD_HASH
    require_existing_dirs DOLOS_DEVNET_DIR
    require_executable_files PYTHON_BIN AIKEN_BIN CARGO_BIN TRIX_BIN CSHELL_BIN DOLOS_BIN
    ;;
  *)
    usage >&2
    fail_manifest_check "Unsupported manifest check mode: $MODE"
    ;;
esac

echo "Session manifest check passed for mode: $MODE"
