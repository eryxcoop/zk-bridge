#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLING_COMMON_SCRIPT="$ROOT_DIR/scripts/lib/tooling_common.sh"
Aiken_TOML_PATH="$ROOT_DIR/aiken.toml"
FLOW="all"

# shellcheck disable=SC1090
source "$TOOLING_COMMON_SCRIPT"

usage() {
  cat <<'EOF'
usage: check_local_tooling.sh [--flow <name>]

Validates local command and Python-package prerequisites for bridge-aiken.

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
- bootstrap
EOF
}

fail_tooling_check() {
  local message="$1"
  shift || true
  echo "[tooling:$FLOW] $message" >&2
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
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail_tooling_check "Unknown argument: $1"
      ;;
  esac
done

BRIDGE_VERBOSE_CONTEXT="${BRIDGE_VERBOSE_CONTEXT:-tooling:$FLOW}"

REQUIRE_AIKEN=0
REQUIRE_PYTHON=0
REQUIRE_CARGO=0
REQUIRE_CURL=0
REQUIRE_PORT_INSPECTOR=0
REQUIRE_TRIX=0
REQUIRE_CSHELL=0
REQUIRE_UV=0
REQUIRE_CBOR2=0

case "$FLOW" in
  all|check|run)
    REQUIRE_AIKEN=1
    REQUIRE_PYTHON=1
    REQUIRE_CARGO=1
    REQUIRE_CURL=1
    REQUIRE_PORT_INSPECTOR=1
    REQUIRE_TRIX=1
    REQUIRE_CSHELL=1
    REQUIRE_UV=1
    REQUIRE_CBOR2=1
    ;;
  preflight)
    REQUIRE_PYTHON=1
    REQUIRE_CARGO=1
    REQUIRE_UV=1
    REQUIRE_CBOR2=1
    ;;
  proof-export-bundle)
    REQUIRE_PYTHON=1
    REQUIRE_CARGO=1
    REQUIRE_UV=1
    ;;
  phase12|genesis-dual-signature|stake-distribution|bridge)
    REQUIRE_AIKEN=1
    REQUIRE_PYTHON=1
    REQUIRE_CARGO=1
    REQUIRE_CURL=1
    REQUIRE_PORT_INSPECTOR=1
    REQUIRE_TRIX=1
    REQUIRE_CSHELL=1
    REQUIRE_UV=1
    REQUIRE_CBOR2=1
    ;;
  bootstrap)
    ;;
  *)
    usage >&2
    fail_tooling_check "Unsupported flow: $FLOW"
    ;;
esac

missing_cmd() {
  local label="$1"
  local install_hint="$2"
  fail_tooling_check "Missing required command: $label" "$install_hint"
}

extract_version() {
  local raw="$1"
  echo "$raw" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1
}

version_lt() {
  local actual="$1"
  local required="$2"
  "$PYTHON_BIN" - "$actual" "$required" <<'PY'
import sys

def parse(version: str):
    parts = []
    for chunk in version.split("."):
        digits = "".join(ch for ch in chunk if ch.isdigit())
        parts.append(int(digits or "0"))
    return tuple(parts)

actual = parse(sys.argv[1])
required = parse(sys.argv[2])
raise SystemExit(0 if actual < required else 1)
PY
}

require_min_version() {
  local label="$1"
  local actual="$2"
  local required="$3"
  local install_hint="$4"

  if version_lt "$actual" "$required"; then
    fail_tooling_check \
      "Unsupported $label version: $actual" \
      "Minimum supported version: $required" \
      "$install_hint"
  fi
}

check_python_module() {
  local module_name="$1"
  local requirement_hint="$2"

  if ! "$PYTHON_BIN" -c "import $module_name" >/dev/null 2>&1; then
    fail_tooling_check "Missing required Python module: $module_name" "$requirement_hint"
  fi
}

if [[ "$REQUIRE_PYTHON" == "1" ]]; then
  resolve_binary_path PYTHON_BIN "Python 3 binary" PYTHON_BIN python3 "$ROOT_DIR/.venv/bin/python" || exit 1
  print_resolved_binary_if_verbose "Python 3 binary" "$PYTHON_BIN"
fi

if [[ "$REQUIRE_AIKEN" == "1" ]]; then
  resolve_binary_path AIKEN_BIN "Aiken binary" AIKEN_BIN aiken || exit 1
  print_resolved_binary_if_verbose "Aiken binary" "$AIKEN_BIN"
  AIKEN_REQUIRED_VERSION="$(sed -n 's/^compiler = "v\([0-9][0-9.]*\)"/\1/p' "$Aiken_TOML_PATH" | head -n1)"
  AIKEN_ACTUAL_VERSION="$(extract_version "$("$AIKEN_BIN" --version 2>/dev/null || true)")"
  if [[ -n "$AIKEN_REQUIRED_VERSION" && -n "$AIKEN_ACTUAL_VERSION" ]]; then
    require_min_version "Aiken" "$AIKEN_ACTUAL_VERSION" "$AIKEN_REQUIRED_VERSION" \
      "Install or upgrade Aiken, for example with: aikup v$AIKEN_REQUIRED_VERSION"
  fi
fi

if [[ "$REQUIRE_CARGO" == "1" ]]; then
  resolve_binary_path CARGO_BIN "Cargo binary" CARGO_BIN cargo || exit 1
  print_resolved_binary_if_verbose "Cargo binary" "$CARGO_BIN"
fi

if [[ "$REQUIRE_UV" == "1" ]]; then
  resolve_binary_path UV_BIN "uv binary" UV_BIN uv || exit 1
  print_resolved_binary_if_verbose "uv binary" "$UV_BIN"
  UV_ACTUAL_VERSION="$(extract_version "$("$UV_BIN" --version 2>/dev/null || true)")"
  UV_REQUIRED_VERSION="0.11.0"
  if [[ -n "$UV_ACTUAL_VERSION" ]]; then
    require_min_version "uv" "$UV_ACTUAL_VERSION" "$UV_REQUIRED_VERSION" \
      "Install or upgrade uv and then rerun: uv sync"
  fi
fi

if [[ "$REQUIRE_TRIX" == "1" ]]; then
  resolve_binary_path TRIX_BIN "trix binary" TRIX_BIN trix "$ROOT_DIR/.tools/bin/trix" || exit 1
  print_resolved_binary_if_verbose "trix binary" "$TRIX_BIN"
fi

if [[ "$REQUIRE_CSHELL" == "1" ]]; then
  resolve_binary_path CSHELL_BIN "CShell binary" CSHELL_BIN cshell "$ROOT_DIR/.tools/bin/cshell" || exit 1
  print_resolved_binary_if_verbose "CShell binary" "$CSHELL_BIN"
fi

if [[ "$REQUIRE_CURL" == "1" ]] && ! command -v curl >/dev/null 2>&1; then
  missing_cmd "curl" "Install curl with your system package manager."
fi

if [[ "$REQUIRE_PORT_INSPECTOR" == "1" ]] && ! command -v lsof >/dev/null 2>&1 && ! command -v ss >/dev/null 2>&1; then
  fail_tooling_check \
    "Missing required port-inspection command: lsof or ss" \
    "Install lsof or iproute2 with your system package manager."
fi

if [[ "$REQUIRE_CBOR2" == "1" ]]; then
  check_python_module "cbor2" "Install Python dependencies with: uv sync"
fi

echo "Local tooling check passed for flow: $FLOW"
