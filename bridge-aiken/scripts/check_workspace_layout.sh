#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_DIR="$(cd "$ROOT_DIR/.." && pwd)"
DOLOS_DIR="${DOLOS_DIR:-$WORKSPACE_DIR/dolos}"
DOLOS_CARGO_MANIFEST="${DOLOS_CARGO_MANIFEST:-}"
VENDORED_DOLOS_DEVNET_DIR="$ROOT_DIR/scripts/data/dolos-devnet"
if [[ -n "${DOLOS_DEVNET_DIR:-}" ]]; then
  DOLOS_DEVNET_DIR="$DOLOS_DEVNET_DIR"
elif [[ -d "$ROOT_DIR/.tx3/dolos" ]]; then
  DOLOS_DEVNET_DIR="$ROOT_DIR/.tx3/dolos"
elif [[ -d "$VENDORED_DOLOS_DEVNET_DIR" ]]; then
  DOLOS_DEVNET_DIR="$VENDORED_DOLOS_DEVNET_DIR"
else
  DOLOS_DEVNET_DIR="$ROOT_DIR/.tx3/dolos"
fi
VERIFIER_GEN_DIR="$WORKSPACE_DIR/plutus-halo2-verifier-gen"
FLOW="all"
SCAN_PERSONAL_PATHS=1

usage() {
  cat <<'EOF'
usage: check_workspace_layout.sh [--flow <name>] [--skip-personal-path-scan]

Validates the supported sibling-workspace contract for bridge-aiken.

Supported flows:
- all
- check
- run
- preflight
- proof-export-bundle
- phase12
- genesis-dual-signature
- stake-distribution
- bridge
- bootstrap-tx3

Checks performed:
- expected sibling repositories exist when required by the selected flow
- required key files/directories exist inside those sibling repositories
- selected scripts/docs do not contain personal absolute paths

Supported overrides:
- DOLOS_DIR
- DOLOS_DEVNET_DIR
EOF
}

fail_workspace_check() {
  local message="$1"
  shift || true
  echo "[workspace:$FLOW] $message" >&2
  while [[ $# -gt 0 ]]; do
    echo "$1" >&2
    shift
  done
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --flow)
      FLOW="$2"
      shift 2
      ;;
    --skip-personal-path-scan)
      SCAN_PERSONAL_PATHS=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail_workspace_check "Unknown argument: $1"
      ;;
  esac
done

REQUIRE_DOLOS_DEVNET=0
REQUIRE_VERIFIER_GEN=0

case "$FLOW" in
  all)
    REQUIRE_DOLOS_DEVNET=1
    REQUIRE_VERIFIER_GEN=1
    ;;
  check|run)
    REQUIRE_DOLOS_DEVNET=1
    REQUIRE_VERIFIER_GEN=1
    ;;
  preflight|proof-export-bundle)
    REQUIRE_VERIFIER_GEN=1
    ;;
  phase12|genesis-dual-signature)
    REQUIRE_DOLOS_DEVNET=1
    ;;
  stake-distribution|bridge)
    REQUIRE_DOLOS_DEVNET=1
    ;;
  bootstrap-tx3)
    REQUIRE_DOLOS_DEVNET=1
    ;;
  *)
    usage >&2
    fail_workspace_check "Unsupported flow: $FLOW"
    ;;
esac

ensure_dir() {
  local path="$1"
  local label="$2"

  if [[ ! -d "$path" ]]; then
    fail_workspace_check "Missing $label at: $path"
  fi
}

ensure_file() {
  local path="$1"
  local label="$2"

  if [[ ! -f "$path" ]]; then
    fail_workspace_check "Missing $label at: $path"
  fi
}

scan_for_personal_paths() {
  local scan_output
  local self_script="$ROOT_DIR/scripts/check_workspace_layout.sh"
  local -a scan_targets=(
    "$ROOT_DIR/LOCAL_TESTING.md"
    "$ROOT_DIR/scripts"
    "$ROOT_DIR/scripts/README.md"
    "$WORKSPACE_DIR/.github/workflows"
  )

  if command -v rg >/dev/null 2>&1; then
    scan_output="$(
      rg -n \
        -e '/home/[A-Za-z0-9._-]+/' \
        -e '/Users/[A-Za-z0-9._-]+/' \
        -e '(^|[^A-Za-z])Desktop/' \
        -e '~/.tx3/stable/bin' \
        "${scan_targets[@]}" \
        2>/dev/null || true
    )"
  else
    scan_output="$(
      grep -R -n -E \
        '/home/[A-Za-z0-9._-]+/|/Users/[A-Za-z0-9._-]+/|(^|[^A-Za-z])Desktop/|~/.tx3/stable/bin' \
        "${scan_targets[@]}" 2>/dev/null || true
    )"
  fi

  if [[ -n "$scan_output" ]]; then
    scan_output="$(
      printf '%s\n' "$scan_output" | grep -F -v "$self_script:" || true
    )"
  fi

  if [[ -n "$scan_output" ]]; then
    fail_workspace_check \
      "Found personal absolute path references in checked scripts/docs:" \
      "$scan_output" \
      "Use workspace-relative paths or documented environment overrides instead."
  fi
}

if [[ "$REQUIRE_DOLOS_DEVNET" == "1" ]]; then
  ensure_dir "$DOLOS_DEVNET_DIR" "Dolos devnet genesis directory"
  ensure_file "$DOLOS_DEVNET_DIR/byron.json" "Dolos byron genesis template"
  ensure_file "$DOLOS_DEVNET_DIR/shelley.json" "Dolos shelley genesis template"
  ensure_file "$DOLOS_DEVNET_DIR/alonzo.json" "Dolos alonzo genesis template"
  ensure_file "$DOLOS_DEVNET_DIR/conway.json" "Dolos conway genesis template"
fi

if [[ "$REQUIRE_VERIFIER_GEN" == "1" ]]; then
  ensure_dir "$VERIFIER_GEN_DIR" "sibling plutus-halo2-verifier-gen repo"
  ensure_file "$VERIFIER_GEN_DIR/Cargo.toml" "plutus-halo2-verifier-gen Cargo.toml"
fi

if [[ "$SCAN_PERSONAL_PATHS" == "1" ]]; then
  scan_for_personal_paths
fi

echo "Workspace layout check passed for flow: $FLOW"
echo "Workspace root: $WORKSPACE_DIR"
