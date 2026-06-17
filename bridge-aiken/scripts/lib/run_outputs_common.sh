#!/usr/bin/env bash

repo_run_outputs_root() {
  printf '%s\n' "${BRIDGE_RUN_OUTPUTS_DIR:-$ROOT_DIR/run_outputs}"
}

default_flow_run_dir() {
  local flow_name="$1"
  printf '%s/%s/latest\n' "$(repo_run_outputs_root)" "$flow_name"
}

ensure_run_dir() {
  mkdir -p "$1"
}

reset_run_dir() {
  rm -rf "$1"
  mkdir -p "$1"
}

setup_run_log_dir() {
  local run_dir="$1"
  BRIDGE_LOG_DIR="${BRIDGE_LOG_DIR:-$run_dir/logs}"
  mkdir -p "$BRIDGE_LOG_DIR"
  export BRIDGE_LOG_DIR
}

mktemp_in_dir() {
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

cache_file_matches() {
  local cache_path="$1"
  local expected_fingerprint="$2"

  [[ -f "$cache_path" ]] || return 1
  [[ "$(tr -d '\n' <"$cache_path")" == "$expected_fingerprint" ]]
}

write_cache_file() {
  local cache_path="$1"
  local fingerprint="$2"

  mkdir -p "$(dirname "$cache_path")"
  printf '%s\n' "$fingerprint" >"$cache_path"
}

backup_file_to_path() {
  local src="$1"
  local backup_path="$2"

  mkdir -p "$(dirname "$backup_path")"
  cp "$src" "$backup_path"
  record_debug_context "backup-file" "$src -> $backup_path"
}

restore_file_from_backup() {
  local backup_path="$1"
  local dst="$2"

  if [[ ! -f "$backup_path" ]]; then
    return 1
  fi

  cp "$backup_path" "$dst"
  record_debug_context "restore-file" "$backup_path -> $dst"
}
