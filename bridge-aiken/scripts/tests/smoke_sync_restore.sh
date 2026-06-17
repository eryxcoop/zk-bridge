#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_STUB_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bridge-aiken-sync-smoke.XXXXXX")"

# shellcheck disable=SC1090
source "$ROOT_DIR/scripts/lib/tooling_common.sh"

cleanup_smoke() {
  rm -rf "$TMP_STUB_DIR"
}

trap cleanup_smoke EXIT

cat >"$TMP_STUB_DIR/trix" <<'EOF'
#!/usr/bin/env bash
echo "stub trix"
EOF
chmod +x "$TMP_STUB_DIR/trix"

main_hash_before="$(sha256_file "$ROOT_DIR/main.tx3")"
env_hash_before="$(sha256_file "$ROOT_DIR/env/default.ak")"

rm -f "$ROOT_DIR/.tx3/cache/sync-phase12.sha256"

set +e
BRIDGE_SYNC_FAIL_AFTER_SYNC_ON_ROUND=1 \
BRIDGE_ALLOW_CI_SHIMS=1 \
TRIX_BIN="$TMP_STUB_DIR/trix" \
SYNC_SCOPE=phase12 \
"$ROOT_DIR/scripts/bridge.sh" sync >/tmp/bridge-aiken-sync-restore.out 2>/tmp/bridge-aiken-sync-restore.err
exit_code=$?
set -e

if [[ "$exit_code" -ne 91 ]]; then
  echo "expected injected sync failure with exit code 91, got $exit_code" >&2
  tail -n 40 /tmp/bridge-aiken-sync-restore.err >&2 || true
  exit 1
fi

main_hash_after="$(sha256_file "$ROOT_DIR/main.tx3")"
env_hash_after="$(sha256_file "$ROOT_DIR/env/default.ak")"

if [[ "$main_hash_before" != "$main_hash_after" ]]; then
  echo "main.tx3 was not restored after injected sync failure" >&2
  echo "before: $main_hash_before" >&2
  echo "after:  $main_hash_after" >&2
  exit 1
fi

if [[ "$env_hash_before" != "$env_hash_after" ]]; then
  echo "env/default.ak was not restored after injected sync failure" >&2
  echo "before: $env_hash_before" >&2
  echo "after:  $env_hash_after" >&2
  exit 1
fi

if [[ ! -f "$ROOT_DIR/.tx3/cache/sync/debug-context.log" ]]; then
  echo "expected debug-context.log to exist after sync smoke" >&2
  exit 1
fi

grep -Fq $'restore-file\t' "$ROOT_DIR/.tx3/cache/sync/debug-context.log"

echo "sync restore smoke test passed"
