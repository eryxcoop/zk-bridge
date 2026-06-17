#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKSPACE_DIR="$(cd "$ROOT_DIR/.." && pwd)"
export RUSTFLAGS="${RUSTFLAGS:--Awarnings}"

announce() {
  printf '\n==> %s\n' "$1"
}

usage() {
  cat <<'EOF'
usage: run_ci_jobs_locally.sh <job>

Jobs:
  quick-lane
  standard-lane
  full-lane
  guardrails
  bootstrap-doctor-smoke
  mithril-bundle-preflight-smoke
  operator-runtime-smoke
  phase12-runtime-smoke
  stake-distribution-runtime-smoke
  bridge-runtime-smoke
  all

Notes:
  - By default, jobs run in a temporary clean git worktree to mimic CI without
    mutating your current checkout.
  - Runtime smoke jobs expect real `trix` and `cshell` installed under
    $HOME/.tx3/default/bin, typically via `tx3up`.
  - You can run this script from anywhere.
EOF
}

job="${1:-}"
if [[ -z "$job" ]]; then
  usage >&2
  exit 1
fi

if [[ "${CI_LOCAL_USE_CLEAN_WORKTREE:-1}" == "1" ]]; then
  GIT_ROOT="$(git -C "$WORKSPACE_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$GIT_ROOT" ]] && git -C "$GIT_ROOT" diff --quiet && git -C "$GIT_ROOT" diff --cached --quiet; then
    announce "Preparing temporary clean git worktree"
    TEMP_WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/bridge-aiken-ci-worktree.XXXXXX")"
    cleanup_workspace_copy() {
      git -C "$GIT_ROOT" worktree remove --force "$TEMP_WORKSPACE" >/dev/null 2>&1 || true
      rm -rf "$TEMP_WORKSPACE"
    }
    trap cleanup_workspace_copy EXIT
    git -C "$GIT_ROOT" worktree add --detach "$TEMP_WORKSPACE" HEAD >/dev/null
  else
    announce "Preparing temporary clean workspace copy"
    TEMP_WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/bridge-aiken-ci-workspace.XXXXXX")"
    cleanup_workspace_copy() {
      rm -rf "$TEMP_WORKSPACE"
    }
    trap cleanup_workspace_copy EXIT

    if command -v rsync >/dev/null 2>&1; then
      rsync -a \
        --exclude '.git' \
        --exclude '.omx' \
        --exclude 'run_outputs' \
        --exclude 'build' \
        --exclude '.tools' \
        --exclude '.venv' \
        "$WORKSPACE_DIR/" "$TEMP_WORKSPACE/"
    else
      cp -R "$WORKSPACE_DIR/." "$TEMP_WORKSPACE/"
      rm -rf \
        "$TEMP_WORKSPACE/.git" \
        "$TEMP_WORKSPACE/.omx" \
        "$TEMP_WORKSPACE/run_outputs" \
        "$TEMP_WORKSPACE/build" \
        "$TEMP_WORKSPACE/bridge-aiken/.tools" \
        "$TEMP_WORKSPACE/bridge-aiken/.venv"
    fi
  fi

  if [[ -d "$TEMP_WORKSPACE/bridge-aiken" ]]; then
    ROOT_DIR="$TEMP_WORKSPACE/bridge-aiken"
    WORKSPACE_DIR="$TEMP_WORKSPACE"
  else
    ROOT_DIR="$TEMP_WORKSPACE"
    WORKSPACE_DIR="$(cd "$ROOT_DIR/.." && pwd)"
  fi
  CI_LOCAL_USE_CLEAN_WORKTREE=0
fi

prepare_ci_shims() {
  local shim_dir="${TMPDIR:-/tmp}/bridge-aiken-ci-shims"
  mkdir -p "$shim_dir"
  cat >"$shim_dir/trix" <<'EOF'
#!/usr/bin/env bash
echo "ci shim trix"
EOF
  cat >"$shim_dir/cshell" <<'EOF'
#!/usr/bin/env bash
echo "ci shim cshell"
EOF
  chmod +x "$shim_dir/trix" "$shim_dir/cshell"
  echo "$shim_dir"
}

require_real_tx3_tools() {
  local trix_bin="$HOME/.tx3/default/bin/trix"
  local cshell_bin="$HOME/.tx3/default/bin/cshell"

  if [[ ! -x "$trix_bin" || ! -x "$cshell_bin" ]]; then
    echo "Missing real tx3 tools under $HOME/.tx3/default/bin." >&2
    echo "Install them first, for example:" >&2
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\"" >&2
    echo "  tx3up install --channel stable" >&2
    echo "  tx3up use stable" >&2
    exit 1
  fi
}

require_circom() {
  if ! command -v circom >/dev/null 2>&1; then
    echo "Missing circom in PATH." >&2
    echo "Install it first to build the required circuit artifacts." >&2
    exit 1
  fi
}

bootstrap_with_shims() {
  local shim_dir
  shim_dir="$(prepare_ci_shims)"
  (
    cd "$ROOT_DIR"
    BRIDGE_ALLOW_CI_SHIMS=1 \
    TRIX_SOURCE_BIN="$shim_dir/trix" \
    CSHELL_SOURCE_BIN="$shim_dir/cshell" \
    ./scripts/bridge.sh bootstrap --link --force
  )
}

bootstrap_with_real_tools() {
  require_real_tx3_tools
  (
    cd "$ROOT_DIR"
    TRIX_SOURCE_BIN="$HOME/.tx3/default/bin/trix" \
    CSHELL_SOURCE_BIN="$HOME/.tx3/default/bin/cshell" \
    ./scripts/bridge.sh bootstrap --link --force
  )
}

sync_python_env() {
  (cd "$ROOT_DIR" && uv sync)
}

prepare_circuit_artifacts() {
  require_circom
  (
    cd "$WORKSPACE_DIR/circuit_transaction_snapshot"
    ./scripts/build_circuit.sh
  )
  (
    cd "$WORKSPACE_DIR/circuit_inclusion_exclusion"
    ./scripts/build_circuit.sh
  )
}

run_guardrails() {
  (
    cd "$WORKSPACE_DIR"
    announce "Running guardrails: workspace contract"
    bridge-aiken/scripts/check_workspace_layout.sh --flow check
    announce "Running guardrails: shell syntax"
    find bridge-aiken/scripts -name '*.sh' -print0 | xargs -0 bash -n
    cd bridge-aiken
    announce "Running guardrails: python syntax"
    python3 -m py_compile scripts/python/*.py
    announce "Running guardrails: fixture alignment"
    python3 scripts/python/check_test_fixture_alignment.py
    announce "Running guardrails: script helper smoke"
    ./scripts/tests/smoke_script_helpers.sh
    announce "Running guardrails: wrapper entrypoint smoke"
    ./scripts/tests/smoke_wrapper_entrypoints.sh
    announce "Running guardrails: onboarding docs checks"
    grep -Eq '\./scripts/bridge\.sh bootstrap --link' LOCAL_TESTING.md
    grep -Eq 'uv sync' LOCAL_TESTING.md
    grep -Eq '\./scripts/bridge\.sh run --strict' LOCAL_TESTING.md
    echo "Verified clean-checkout onboarding commands remain documented."
  )
}

run_bootstrap_doctor_smoke() {
  announce "Running bootstrap-doctor-smoke"
  local shim_dir
  shim_dir="$(prepare_ci_shims)"
  (
    cd "$ROOT_DIR"
    TRIX_SOURCE_BIN="$shim_dir/trix" \
    CSHELL_SOURCE_BIN="$shim_dir/cshell" \
    ./scripts/bridge.sh bootstrap --link --force
  )
  (
    cd "$ROOT_DIR"
    BRIDGE_ALLOW_CI_SHIMS=1 \
    TRIX_SOURCE_BIN="$shim_dir/trix" \
    CSHELL_SOURCE_BIN="$shim_dir/cshell" \
    ./scripts/bridge.sh bootstrap --check
    uv sync
    ./scripts/tests/smoke_sync_restore.sh
    BRIDGE_ALLOW_CI_SHIMS=1 \
    ./scripts/bridge.sh doctor check
  )
}

run_mithril_bundle_preflight_smoke() {
  announce "Running mithril-bundle-preflight-smoke"
  bootstrap_with_shims
  (
    cd "$ROOT_DIR"
    uv sync
    ./scripts/bridge.sh workspace proof-export-bundle
    ./scripts/bridge.sh tooling proof-export-bundle
    cargo test --manifest-path ../zk-bridge-operator/Cargo.toml
    cargo run --manifest-path ../zk-bridge-operator/Cargo.toml -- --help
    ./scripts/bridge.sh proof-export-bundle run_outputs/ci/bridge-compatible-mithril-stm-bundle.json
    .venv/bin/python scripts/python/check_mithril_proof_export_bundle_contract.py run_outputs/ci/bridge-compatible-mithril-stm-bundle.json
    output="$(./scripts/bridge.sh proof-export-bundle run_outputs/ci/bridge-compatible-mithril-stm-bundle.json 2>&1)"
    echo "$output"
    grep -Fq "Skipping Building bridge-compatible Mithril STM bundle (fingerprint unchanged)" <<<"$output"
    .venv/bin/python - <<'PY'
import json
from pathlib import Path

path = Path("run_outputs/ci/bridge-compatible-mithril-stm-bundle.json")
data = json.loads(path.read_text())
data.pop("proofs", None)
path.write_text(json.dumps(data, indent=2))
PY
    output="$(./scripts/bridge.sh preflight --proof-export-bundle run_outputs/ci/bridge-compatible-mithril-stm-bundle.json --output-dir run_outputs/ci 2>&1)"
    echo "$output"
    grep -Fq "rebuilding stale runtime bundle without proofs" <<<"$output"
    .venv/bin/python - <<'PY'
import json
from pathlib import Path

data = json.loads(Path("run_outputs/ci/bridge-compatible-mithril-stm-bundle.json").read_text())
assert isinstance(data.get("proofs"), dict), "recovered runtime bundle is still missing proofs"
PY
    test -f run_outputs/ci/stage-trace.log
    test -f run_outputs/ci/debug-context.log
    output="$(./scripts/bridge.sh preflight --proof-export-bundle run_outputs/ci/bridge-compatible-mithril-stm-bundle.json --output-dir run_outputs/ci 2>&1)"
    echo "$output"
    grep -Fq "Mithril PoC preflight passed." <<<"$output"
  )
}

run_operator_runtime_smoke() {
  announce "Running operator-runtime-smoke"
  bootstrap_with_shims
  (
    cd "$ROOT_DIR"
    uv sync
    prepare_circuit_artifacts
    cargo test --manifest-path ../zk-bridge-operator/Cargo.toml
    cargo run --manifest-path ../zk-bridge-operator/Cargo.toml -- --help
    cargo build --release --manifest-path ../circuit_transaction_snapshot/Cargo.toml --bin arkworks_circom_fixture_export
    cargo build --release --manifest-path ../circuit_inclusion_exclusion/Cargo.toml --bin arkworks_circom_fixture_export
    local_tx_hash="601c6513db4646317449e575104044e53f9e7db721fa7424782a83889961b6be"
    local_operator_smoke_dir="${TMPDIR:-/tmp}/zk-circuit-operator-smoke"
    cargo run --manifest-path ../zk-bridge-operator/Cargo.toml -- \
      --proven-transactions-dir "$local_operator_smoke_dir" \
      --force \
      tx prove "$local_tx_hash"
    test -f "$local_operator_smoke_dir/$local_tx_hash/manifest.json"
    test -f "$local_operator_smoke_dir/$local_tx_hash/snapshot_membership/proof_summary.json"
    test -f "$local_operator_smoke_dir/$local_tx_hash/tx_set_update/proof_summary.json"
  )
}

run_phase12_runtime_smoke() {
  announce "Running phase12-runtime-smoke"
  bootstrap_with_real_tools
  (
    cd "$ROOT_DIR"
    uv sync
    prepare_circuit_artifacts
    ./scripts/bridge.sh proof-export-bundle run_outputs/ci-phase12/bridge-compatible-mithril-stm-bundle.json
    PROOF_EXPORT_BUNDLE_PATH="$ROOT_DIR/run_outputs/ci-phase12/bridge-compatible-mithril-stm-bundle.json" \
    PHASE12_RUN_DIR="$ROOT_DIR/run_outputs/ci-phase12/phase12-runtime" \
    TX3_SESSION_ENV_PATH="$ROOT_DIR/run_outputs/ci-phase12/phase12-runtime/session.env" \
    PHASE12_PROOF_NAME=stake_distribution_standard \
    KEEP_TX3_DOLOS_TMP=1 \
    KEEP_TX3_DOLOS_RUNNING=0 \
    SUPPRESS_BUNDLE_SUMMARY=1 \
    SUPPRESS_SESSION_MANIFEST_MSG=1 \
    ./scripts/bridge.sh phase12
    test -f run_outputs/ci-phase12/phase12-runtime/session.env
    test -f run_outputs/ci-phase12/phase12-runtime/stage-trace.log
    test -f run_outputs/ci-phase12/phase12-runtime/debug-context.log
    test -f run_outputs/ci-phase12/phase12-runtime/dolos.log
    ./scripts/check_session_manifest.sh --mode phase12-case --file run_outputs/ci-phase12/phase12-runtime/session.env
    grep -Fq "Submitting phase2_verify" run_outputs/ci-phase12/phase12-runtime/stage-trace.log
    grep -Fq $'Python 3 binary\t' run_outputs/ci-phase12/phase12-runtime/debug-context.log
    grep -Eq '^PYTHON_BIN=.*/bridge-aiken/\.venv/bin/python$' run_outputs/ci-phase12/phase12-runtime/session.env
    grep -Eq '^DOLOS_BIN=.*/bridge-aiken/\.\./dolos/target/debug/dolos$' run_outputs/ci-phase12/phase12-runtime/session.env
  )
}

run_stake_distribution_runtime_smoke() {
  announce "Running stake-distribution-runtime-smoke"
  bootstrap_with_real_tools
  (
    cd "$ROOT_DIR"
    uv sync
    prepare_circuit_artifacts
    ./scripts/bridge.sh proof-export-bundle run_outputs/ci-stake/bridge-compatible-mithril-stm-bundle.json
    PROOF_EXPORT_BUNDLE_PATH="$ROOT_DIR/run_outputs/ci-stake/bridge-compatible-mithril-stm-bundle.json" \
    STAKE_DISTRIBUTION_RUN_DIR="$ROOT_DIR/run_outputs/ci-stake/stake-distribution-runtime" \
    TX3_SESSION_ENV_PATH="$ROOT_DIR/run_outputs/ci-stake/stake-distribution-runtime/session.env" \
    ./scripts/bridge.sh stake-distribution
    test -f run_outputs/ci-stake/stake-distribution-runtime/session.env
    test -f run_outputs/ci-stake/stake-distribution-runtime/stage-trace.log
    test -f run_outputs/ci-stake/stake-distribution-runtime/debug-context.log
    ./scripts/check_session_manifest.sh --mode stake-distribution --file run_outputs/ci-stake/stake-distribution-runtime/session.env
    grep -Fq "Running phase1/phase2 multi-proof setup" run_outputs/ci-stake/stake-distribution-runtime/stage-trace.log
    grep -Fq $'Python 3 binary\t' run_outputs/ci-stake/stake-distribution-runtime/debug-context.log
  )
}

run_bridge_runtime_smoke() {
  announce "Running bridge-runtime-smoke"
  bootstrap_with_real_tools
  (
    cd "$ROOT_DIR"
    uv sync
    prepare_circuit_artifacts
    ./scripts/bridge.sh run --output-dir run_outputs/ci-bridge/run --clean
    test -f run_outputs/ci-bridge/run/bridge-minting/session.env
    test -f run_outputs/ci-bridge/run/bridge-minting/stage-trace.log
    test -f run_outputs/ci-bridge/run/bridge-minting/debug-context.log
    ./scripts/check_session_manifest.sh --mode bridge --file run_outputs/ci-bridge/run/bridge-minting/session.env
    grep -Fq "Running phase1/phase2/stake-distribution setup" run_outputs/ci-bridge/run/bridge-minting/stage-trace.log
    grep -Fq $'Dolos manifest\t' run_outputs/ci-bridge/run/bridge-minting/debug-context.log
  )
}

run_quick_lane() {
  announce "Running quick-lane"
  run_guardrails
  run_bootstrap_doctor_smoke
}

run_standard_lane() {
  announce "Running standard-lane"
  run_quick_lane
  run_mithril_bundle_preflight_smoke
}

run_full_lane() {
  announce "Running full-lane"
  run_standard_lane
  run_operator_runtime_smoke
  run_phase12_runtime_smoke
  run_stake_distribution_runtime_smoke
  run_bridge_runtime_smoke
}

case "$job" in
  quick-lane)
    run_quick_lane
    ;;
  standard-lane)
    run_standard_lane
    ;;
  full-lane)
    run_full_lane
    ;;
  guardrails)
    run_guardrails
    ;;
  bootstrap-doctor-smoke)
    run_bootstrap_doctor_smoke
    ;;
  mithril-bundle-preflight-smoke)
    run_mithril_bundle_preflight_smoke
    ;;
  operator-runtime-smoke)
    run_operator_runtime_smoke
    ;;
  phase12-runtime-smoke)
    run_phase12_runtime_smoke
    ;;
  stake-distribution-runtime-smoke)
    run_stake_distribution_runtime_smoke
    ;;
  bridge-runtime-smoke)
    run_bridge_runtime_smoke
    ;;
  all)
    run_full_lane
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
