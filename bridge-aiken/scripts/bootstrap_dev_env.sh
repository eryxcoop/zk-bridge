#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$ROOT_DIR/.tools"
TOOLS_BIN_DIR="$TOOLS_DIR/bin"
TOOLS_ENV_PATH="$TOOLS_DIR/env.sh"
DEFAULT_MODE="link"
MODE="$DEFAULT_MODE"
FORCE=0

usage() {
  cat <<'EOF'
usage: bootstrap_dev_env.sh [--check] [--link|--copy] [--force]

Bootstraps repo-local Tx3 tooling under .tools/ so bridge-aiken can use trix
and cshell without depending on a user-local ~/.tx3 install at runtime. It
also records the preferred Dolos binary in .tools/env.sh.

Resolution for each repo-local tool:
1. TRIX_SOURCE_BIN / CSHELL_SOURCE_BIN, if set
2. known local workspace binaries, if present
3. command -v trix / cshell

Resolution for Dolos env export:
1. DOLOS_SOURCE_BIN, if set
2. command -v dolos

Outputs:
- .tools/bin/trix
- .tools/bin/cshell
- .tools/env.sh

Modes:
- --check: validate whether repo-local tooling is already ready without writing files
- --link: create symlinks to the resolved source binaries
- --copy: copy the resolved source binaries into .tools/bin
EOF
}

CHECK_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      CHECK_ONLY=1
      shift
      ;;
    --link)
      MODE="link"
      shift
      ;;
    --copy)
      MODE="copy"
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

ensure_workspace_local_cshell() {
  local sibling_root="$ROOT_DIR/../cshell-0.14.0"
  local sibling_manifest="$sibling_root/Cargo.toml"
  local sibling_bin="$sibling_root/target/debug/cshell"
  local cargo_bin=""

  if [[ -x "$sibling_bin" ]]; then
    return 0
  fi

  if [[ ! -f "$sibling_manifest" ]]; then
    return 0
  fi

  if [[ "$CHECK_ONLY" == "1" ]]; then
    return 0
  fi

  cargo_bin="$(command -v cargo 2>/dev/null || true)"
  if [[ -z "$cargo_bin" ]]; then
    echo "Missing cargo; cannot build workspace-local cshell at: $sibling_root" >&2
    return 1
  fi

  echo "Building workspace-local cshell from: $sibling_root"
  "$cargo_bin" build -p cshell --manifest-path "$sibling_manifest"
}

resolve_source_bin() {
  local out_var="$1"
  local env_var_name="$2"
  local command_name="$3"
  shift 3

  local env_value="${!env_var_name:-}"
  local resolved=""
  if [[ -n "$env_value" ]]; then
    if [[ "$env_value" == */* ]]; then
      if [[ -x "$env_value" ]]; then
        resolved="$env_value"
      else
        echo "Configured source via $env_var_name, but it is not executable: $env_value" >&2
        return 1
      fi
    else
      resolved="$(command -v "$env_value" 2>/dev/null || true)"
      if [[ -z "$resolved" ]]; then
        echo "Configured source via $env_var_name, but it was not found in PATH: $env_value" >&2
        return 1
      fi
    fi
  fi

  if [[ -z "$resolved" ]]; then
    case "$command_name" in
      cshell)
        local local_cshell="$ROOT_DIR/../cshell-0.14.0/target/debug/cshell"
        if [[ -x "$local_cshell" ]]; then
          resolved="$local_cshell"
        fi
        ;;
    esac
  fi

  if [[ -z "$resolved" ]]; then
    resolved="$(command -v "$command_name" 2>/dev/null || true)"
  fi

  if [[ -z "$resolved" ]]; then
    echo "Could not resolve source binary for $command_name." >&2
    echo "Set $env_var_name=/path/to/$command_name or install '$command_name' in PATH first." >&2
    echo "Then rerun: ./scripts/bridge.sh bootstrap --link" >&2
    return 1
  fi

  printf -v "$out_var" '%s' "$resolved"
}

describe_source_kind() {
  local env_var_name="$1"
  local env_value="${!env_var_name:-}"
  local command_name="$2"

  if [[ -n "$env_value" ]]; then
    echo "$env_var_name"
  elif [[ "$command_name" == "cshell" && -x "$ROOT_DIR/../cshell-0.14.0/target/debug/cshell" ]]; then
    echo "workspace-local"
  else
    echo "PATH"
  fi
}

tool_is_ready() {
  local name="$1"
  local resolved_src="$2"
  local dst="$TOOLS_BIN_DIR/$name"

  [[ -x "$dst" ]] || return 1

  if [[ -L "$dst" ]]; then
    local linked_src
    linked_src="$(readlink "$dst")"
    [[ "$linked_src" == "$resolved_src" ]] || return 1
  fi

  return 0
}

env_export_is_ready() {
  local var_name="$1"
  local expected_value="$2"

  [[ -f "$TOOLS_ENV_PATH" ]] || return 1

  local expected_line="export $var_name=\"$expected_value\""
  grep -Fx "$expected_line" "$TOOLS_ENV_PATH" >/dev/null 2>&1
}

install_bin() {
  local name="$1"
  local src="$2"
  local dst="$TOOLS_BIN_DIR/$name"

  mkdir -p "$TOOLS_BIN_DIR"

  if [[ -e "$dst" || -L "$dst" ]]; then
    if [[ "$FORCE" != "1" ]]; then
      echo "Refusing to overwrite existing repo-local tool without --force: $dst" >&2
      return 1
    fi
    rm -f "$dst"
  fi

  if [[ "$MODE" == "copy" ]]; then
    cp "$src" "$dst"
    chmod +x "$dst"
  else
    ln -s "$src" "$dst"
  fi
}

write_env_file() {
  cat >"$TOOLS_ENV_PATH" <<EOF
export TRIX_BIN="$TOOLS_BIN_DIR/trix"
export CSHELL_BIN="$TOOLS_BIN_DIR/cshell"
export DOLOS_BIN="$DOLOS_SOURCE_RESOLVED"
EOF
}

ensure_workspace_local_cshell

resolve_source_bin TRIX_SOURCE_RESOLVED TRIX_SOURCE_BIN trix
resolve_source_bin CSHELL_SOURCE_RESOLVED CSHELL_SOURCE_BIN cshell
resolve_source_bin DOLOS_SOURCE_RESOLVED DOLOS_SOURCE_BIN dolos
TRIX_SOURCE_KIND="$(describe_source_kind TRIX_SOURCE_BIN trix)"
CSHELL_SOURCE_KIND="$(describe_source_kind CSHELL_SOURCE_BIN cshell)"
DOLOS_SOURCE_KIND="$(describe_source_kind DOLOS_SOURCE_BIN dolos)"

if [[ "$CHECK_ONLY" == "1" ]]; then
  TRIX_READY=0
  CSHELL_READY=0
  TRIX_ENV_READY=0
  CSHELL_ENV_READY=0
  DOLOS_ENV_READY=0

  tool_is_ready trix "$TRIX_SOURCE_RESOLVED" && TRIX_READY=1
  tool_is_ready cshell "$CSHELL_SOURCE_RESOLVED" && CSHELL_READY=1
  env_export_is_ready TRIX_BIN "$TOOLS_BIN_DIR/trix" && TRIX_ENV_READY=1
  env_export_is_ready CSHELL_BIN "$TOOLS_BIN_DIR/cshell" && CSHELL_ENV_READY=1
  env_export_is_ready DOLOS_BIN "$DOLOS_SOURCE_RESOLVED" && DOLOS_ENV_READY=1

  echo "Bootstrap readiness check"
  echo "tools dir:     $TOOLS_DIR"
  echo "trix source:   $TRIX_SOURCE_RESOLVED ($TRIX_SOURCE_KIND)"
  echo "cshell source: $CSHELL_SOURCE_RESOLVED ($CSHELL_SOURCE_KIND)"
  echo "dolos source:  $DOLOS_SOURCE_RESOLVED ($DOLOS_SOURCE_KIND)"
  echo "trix target:   $TOOLS_BIN_DIR/trix"
  echo "cshell target: $TOOLS_BIN_DIR/cshell"
  echo "env dolos:     $DOLOS_SOURCE_RESOLVED"

  if [[ "$TRIX_READY" == "1" && "$CSHELL_READY" == "1" && "$TRIX_ENV_READY" == "1" && "$CSHELL_ENV_READY" == "1" && "$DOLOS_ENV_READY" == "1" ]]; then
    echo "status:        ready"
    exit 0
  fi

  echo "status:        not ready"
  if [[ "$TRIX_READY" != "1" ]]; then
    echo "missing/dirty: $TOOLS_BIN_DIR/trix" >&2
  fi
  if [[ "$CSHELL_READY" != "1" ]]; then
    echo "missing/dirty: $TOOLS_BIN_DIR/cshell" >&2
  fi
  if [[ "$TRIX_ENV_READY" != "1" || "$CSHELL_ENV_READY" != "1" || "$DOLOS_ENV_READY" != "1" ]]; then
    echo "missing/dirty: $TOOLS_ENV_PATH" >&2
  fi
  echo "next step:     ./scripts/bridge.sh bootstrap --link --force" >&2
  exit 1
fi

install_bin trix "$TRIX_SOURCE_RESOLVED"
install_bin cshell "$CSHELL_SOURCE_RESOLVED"
write_env_file

echo "Bootstrapped repo-local tooling under: $TOOLS_DIR"
echo "mode:          $MODE"
echo "trix source:   $TRIX_SOURCE_RESOLVED ($TRIX_SOURCE_KIND)"
echo "cshell source: $CSHELL_SOURCE_RESOLVED ($CSHELL_SOURCE_KIND)"
echo "dolos source:  $DOLOS_SOURCE_RESOLVED ($DOLOS_SOURCE_KIND)"
echo "trix target:   $TOOLS_BIN_DIR/trix"
echo "cshell target: $TOOLS_BIN_DIR/cshell"
echo "env file:      $TOOLS_ENV_PATH"
echo
echo "To export repo-local tooling in the current shell (optional):"
echo "source \"$TOOLS_ENV_PATH\""
