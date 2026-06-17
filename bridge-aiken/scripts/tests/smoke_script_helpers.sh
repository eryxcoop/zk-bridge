#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/bridge-aiken-script-smoke.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

# shellcheck disable=SC1090
source "$ROOT_DIR/scripts/lib/flow_observability.sh"
# shellcheck disable=SC1090
source "$ROOT_DIR/scripts/lib/tooling_common.sh"
# shellcheck disable=SC1090
source "$ROOT_DIR/scripts/lib/run_outputs_common.sh"
# shellcheck disable=SC1090
source "$ROOT_DIR/scripts/lib/dolos_common.sh"
# shellcheck disable=SC1090
source "$ROOT_DIR/scripts/lib/session_manifest_common.sh"
# shellcheck disable=SC1090
source "$ROOT_DIR/scripts/lib/sibling_toolchain_contract_common.sh"

assert_eq() {
  local actual="$1"
  local expected="$2"
  local message="$3"

  if [[ "$actual" != "$expected" ]]; then
    echo "assert_eq failed: $message" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
  fi
}

assert_file_exists() {
  local path="$1"
  local message="$2"

  if [[ ! -f "$path" ]]; then
    echo "assert_file_exists failed: $message ($path)" >&2
    exit 1
  fi
}

canonical_path() {
  local path="$1"
  printf '%s/%s\n' "$(cd "$(dirname "$path")" && pwd)" "$(basename "$path")"
}

test_mktemp_in_dir_suffix() {
  local run_dir="$TMP_ROOT/mktemp"
  local result=""

  result="$(mktemp_in_dir "$run_dir" "bridge-sync-test.XXXXXX.log")"
  [[ "$result" == "$run_dir"/bridge-sync-test.*.log ]] || {
    echo "mktemp_in_dir did not preserve suffix: $result" >&2
    exit 1
  }
  assert_file_exists "$result" "mktemp_in_dir should create the file"
}

test_resolve_binary_prefers_candidate_for_generic_env() {
  local bin_dir="$TMP_ROOT/bin"
  local candidate_dir="$TMP_ROOT/candidate"
  local resolved_path=""
  local old_path="$PATH"
  local old_python_bin="${PYTHON_BIN-}"

  mkdir -p "$bin_dir" "$candidate_dir"
  cat >"$bin_dir/python3" <<'EOF'
#!/usr/bin/env bash
echo "path-python"
EOF
  cat >"$candidate_dir/python3" <<'EOF'
#!/usr/bin/env bash
echo "candidate-python"
EOF
  chmod +x "$bin_dir/python3" "$candidate_dir/python3"

  PATH="$bin_dir:$PATH"
  PYTHON_BIN=python3
  resolve_binary_path resolved_path "Python 3 binary" PYTHON_BIN python3 "$candidate_dir/python3"
  PATH="$old_path"
  if [[ -n "$old_python_bin" ]]; then
    PYTHON_BIN="$old_python_bin"
  else
    unset PYTHON_BIN
  fi
  assert_eq "$resolved_path" "$candidate_dir/python3" "generic env name should still prefer repo-local candidate"
}

test_resolve_dolos_binary_uses_path() {
  local fake_root="$TMP_ROOT/workspace/bridge-aiken"
  local fake_dolos_dir="$TMP_ROOT/workspace/dolos"
  local path_bin_dir="$TMP_ROOT/path-bin"
  local resolved=""
  local old_path="$PATH"

  # Since the move to the official Dolos 2.1.0 release, the binary is resolved
  # from PATH. A sibling source tree with a built binary must NOT be preferred
  # anymore, even when it is present.
  mkdir -p "$fake_root" "$fake_dolos_dir/target/debug" "$path_bin_dir"
  cat >"$fake_dolos_dir/Cargo.toml" <<'EOF'
[package]
name = "dolos"
version = "0.0.0"
EOF
  cat >"$fake_dolos_dir/target/debug/dolos" <<'EOF'
#!/usr/bin/env bash
echo "sibling dolos"
EOF
  cat >"$path_bin_dir/dolos" <<'EOF'
#!/usr/bin/env bash
echo "official dolos"
EOF
  chmod +x "$fake_dolos_dir/target/debug/dolos" "$path_bin_dir/dolos"

  init_dolos_layout "$fake_root"
  unset DOLOS_BIN
  PATH="$path_bin_dir:$PATH"
  resolve_dolos_binary
  resolved="$DOLOS_BIN"
  PATH="$old_path"
  assert_eq "$(canonical_path "$resolved")" "$(canonical_path "$path_bin_dir/dolos")" "resolve_dolos_binary should use the dolos found in PATH"
}

test_session_manifest_checks() {
  local manifest="$TMP_ROOT/session.env"
  local fake_root="$TMP_ROOT/fake-root"
  local fake_run="$TMP_ROOT/fake-run"
  local fake_dolos_dir="$TMP_ROOT/fake-dolos"
  local fake_config="$TMP_ROOT/dolos.toml"
  local fake_p1="$TMP_ROOT/p1-ref.json"
  local fake_phase1="$TMP_ROOT/phase1.json"
  local fake_phase2="$TMP_ROOT/phase2.json"
  local fake_python="$TMP_ROOT/python"
  local fake_aiken="$TMP_ROOT/aiken"
  local fake_cargo="$TMP_ROOT/cargo"
  local fake_trix="$TMP_ROOT/trix"
  local fake_cshell="$TMP_ROOT/cshell"
  local fake_dolos_bin="$TMP_ROOT/dolos"

  mkdir -p "$fake_root" "$fake_run" "$fake_dolos_dir/devnet"
  : >"$fake_dolos_dir/Cargo.toml"
  : >"$fake_config"
  : >"$fake_p1"
  : >"$fake_phase1"
  : >"$fake_phase2"
  : >"$fake_dolos_dir/devnet/byron.json"
  : >"$fake_dolos_dir/devnet/shelley.json"
  : >"$fake_dolos_dir/devnet/alonzo.json"
  : >"$fake_dolos_dir/devnet/conway.json"

  for exe in "$fake_python" "$fake_aiken" "$fake_cargo" "$fake_trix" "$fake_cshell" "$fake_dolos_bin"; do
    cat >"$exe" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$exe"
  done

  cat >"$manifest" <<'EOF'
ROOT_DIR=__FAKE_ROOT__
TMP_DIR=__FAKE_RUN__
PYTHON_BIN=__FAKE_PYTHON__
AIKEN_BIN=__FAKE_AIKEN__
CARGO_BIN=__FAKE_CARGO__
UV_BIN=/bin/sh
TRIX_BIN=__FAKE_TRIX__
CSHELL_BIN=__FAKE_CSHELL__
DOLOS_BIN=__FAKE_DOLOS_BIN__
DOLOS_CARGO_MANIFEST=__FAKE_DOLOS_MANIFEST__
DOLOS_DEVNET_DIR=__FAKE_DOLOS_DEVNET__
DOLOS_CONFIG_PATH=__FAKE_CONFIG__
GRPC_PORT=55164
TRP_PORT=58164
MINIBF_PORT=53164
PUBLISH_PHASE1_REFERENCE_SCRIPT_RESULT_PATH=__FAKE_P1__
PHASE1_RESULT_PATH=__FAKE_PHASE1__
PHASE2_RESULT_PATH=__FAKE_PHASE2__
PHASE1_HASH=abc
PHASE2_HASH=def
DOLOS_PID=123
PHASE2_HASH_STAKE_DISTRIBUTION_STANDARD=b
PHASE2_HASH_CARDANO_TRANSACTIONS=c
PHASE2_RECEIPT_UTXO_STAKE_DISTRIBUTION_STANDARD=def#2
PHASE2_RECEIPT_UTXO_CARDANO_TRANSACTIONS=ghi#3
STATEMENT_HASH_STAKE_DISTRIBUTION_STANDARD=s2
STATEMENT_HASH_CARDANO_TRANSACTIONS=s3
STAKE_DISTRIBUTION_GENESIS_HASH=genesis-hash
STAKE_DISTRIBUTION_STANDARD_HASH=standard-hash
EOF

  sed -i.bak \
    -e "s|__FAKE_ROOT__|$fake_root|g" \
    -e "s|__FAKE_RUN__|$fake_run|g" \
    -e "s|__FAKE_PYTHON__|$fake_python|g" \
    -e "s|__FAKE_AIKEN__|$fake_aiken|g" \
    -e "s|__FAKE_CARGO__|$fake_cargo|g" \
    -e "s|__FAKE_TRIX__|$fake_trix|g" \
    -e "s|__FAKE_CSHELL__|$fake_cshell|g" \
    -e "s|__FAKE_DOLOS_BIN__|$fake_dolos_bin|g" \
    -e "s|__FAKE_DOLOS_MANIFEST__|$fake_dolos_dir/Cargo.toml|g" \
    -e "s|__FAKE_DOLOS_DEVNET__|$fake_dolos_dir/devnet|g" \
    -e "s|__FAKE_CONFIG__|$fake_config|g" \
    -e "s|__FAKE_P1__|$fake_p1|g" \
    -e "s|__FAKE_PHASE1__|$fake_phase1|g" \
    -e "s|__FAKE_PHASE2__|$fake_phase2|g" \
    "$manifest"
  rm -f "$manifest.bak"

  "$ROOT_DIR/scripts/check_session_manifest.sh" --mode phase12-case --file "$manifest" >/dev/null
  "$ROOT_DIR/scripts/check_session_manifest.sh" --mode phase12-all --file "$manifest" >/dev/null
  "$ROOT_DIR/scripts/check_session_manifest.sh" --mode stake-distribution --file "$manifest" >/dev/null
  "$ROOT_DIR/scripts/check_session_manifest.sh" --mode bridge --file "$manifest" >/dev/null
}

test_session_manifest_rejects_invalid_utxo() {
  local manifest="$TMP_ROOT/session-invalid-utxo.env"
  local fake_dolos_dir="$TMP_ROOT/invalid-utxo-dolos"

  mkdir -p "$fake_dolos_dir/devnet"
  : >"$fake_dolos_dir/Cargo.toml"

  cat >"$manifest" <<EOF
PYTHON_BIN=/bin/sh
AIKEN_BIN=/bin/sh
CARGO_BIN=/bin/sh
TRIX_BIN=/bin/sh
CSHELL_BIN=/bin/sh
DOLOS_BIN=/bin/sh
DOLOS_CARGO_MANIFEST=$fake_dolos_dir/Cargo.toml
DOLOS_DEVNET_DIR=$fake_dolos_dir/devnet
TMP_DIR=$TMP_ROOT
DOLOS_PID=123
PHASE2_HASH_STAKE_DISTRIBUTION_STANDARD=def
PHASE2_RECEIPT_UTXO_STAKE_DISTRIBUTION_STANDARD=not-a-utxo
STATEMENT_HASH_STAKE_DISTRIBUTION_STANDARD=statement
STAKE_DISTRIBUTION_GENESIS_HASH=genesis
STAKE_DISTRIBUTION_STANDARD_HASH=standard
EOF

  if "$ROOT_DIR/scripts/check_session_manifest.sh" --mode stake-distribution --file "$manifest" >/dev/null 2>&1; then
    echo "invalid session manifest unexpectedly passed" >&2
    exit 1
  fi
}

test_session_manifest_rejects_unsafe_shell() {
  local manifest="$TMP_ROOT/session-unsafe.env"

  cat >"$manifest" <<'EOF'
PYTHON_BIN=$(echo hacked)
EOF

  if "$ROOT_DIR/scripts/check_session_manifest.sh" --mode bridge --file "$manifest" >/dev/null 2>&1; then
    echo "unsafe session manifest unexpectedly passed" >&2
    exit 1
  fi
}

test_session_manifest_dependency_helpers() {
  local manifest="$TMP_ROOT/session-helper.env"

  cat >"$manifest" <<'EOF'
GOOD_FIELD=value
GOOD_UTXO=abc#1
BAD_UTXO=not-a-utxo
EOF

  # shellcheck disable=SC1090
  source "$manifest"

  require_session_manifest_var "$manifest" GOOD_FIELD "testing helper happy path"
  require_session_manifest_utxo "$manifest" GOOD_UTXO "testing helper UTxO happy path"

  if (require_session_manifest_utxo "$manifest" BAD_UTXO "testing helper UTxO failure") >/dev/null 2>&1; then
    echo "invalid helper UTxO unexpectedly passed" >&2
    exit 1
  fi
}

test_sibling_toolchain_contract_helpers() {
  local toolchain_root="$TMP_ROOT/toolchain"
  local runtime_path="$toolchain_root/runtime.rs"
  local decoder_path="$toolchain_root/decoder.rs"
  local daemon_path="$toolchain_root/daemon.rs"

  mkdir -p "$toolchain_root"
  cat >"$runtime_path" <<'EOF'
if size > &Integer::from(INTEGER_TO_BYTE_STRING_MAXIMUM_OUTPUT_LENGTH) {
}
let mut arg1 = ubig_to_bytes(self.arena, &computation, Endianness::Big);
blst::blst_scalar_from_bendian(scalar as *mut _, arg1.as_ptr() as *const _);
let mut arg1 = ubig_to_bytes(self.arena, &computation, Endianness::Big);
blst::blst_scalar_from_bendian(scalar as *mut _, arg1.as_ptr() as *const _);
EOF
  cat >"$decoder_path" <<'EOF'
let shifted_part = part << shift;
EOF
  cat >"$daemon_path" <<'EOF'
.thread_stack_size(32 * 1024 * 1024)
EOF

  check_patched_sibling_toolchain_contract "$runtime_path" "$decoder_path" "$daemon_path"

  cat >"$decoder_path" <<'EOF'
let shifted_part = part << broken_shift;
EOF
  if (check_patched_sibling_toolchain_contract "$runtime_path" "$decoder_path" "$daemon_path") >/dev/null 2>&1; then
    echo "invalid sibling toolchain contract unexpectedly passed" >&2
    exit 1
  fi
}

test_backup_restore_debug_context() {
  local run_dir="$TMP_ROOT/observability"
  local source_file="$TMP_ROOT/source.txt"
  local backup_file="$run_dir/source.backup"
  local restore_target="$TMP_ROOT/restored.txt"

  printf 'original\n' >"$source_file"
  setup_flow_observability "$run_dir" "script-smoke"
  backup_file_to_path "$source_file" "$backup_file"
  printf 'mutated\n' >"$restore_target"
  restore_file_from_backup "$backup_file" "$restore_target"

  assert_eq "$(cat "$restore_target")" "$(cat "$source_file")" "restore_file_from_backup should restore original contents"
  assert_file_exists "$run_dir/debug-context.log" "debug-context.log should be created"
  grep -Fq $'backup-file\t'"$source_file -> $backup_file" "$run_dir/debug-context.log"
  grep -Fq $'restore-file\t'"$backup_file -> $restore_target" "$run_dir/debug-context.log"
}

main() {
  test_mktemp_in_dir_suffix
  test_resolve_binary_prefers_candidate_for_generic_env
  test_resolve_dolos_binary_uses_path
  test_session_manifest_checks
  test_session_manifest_rejects_invalid_utxo
  test_session_manifest_rejects_unsafe_shell
  test_session_manifest_dependency_helpers
  test_sibling_toolchain_contract_helpers
  test_backup_restore_debug_context
  echo "script helper smoke tests passed"
}

main "$@"
