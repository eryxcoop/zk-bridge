verbose_context_prefix() {
  if [[ -n "${BRIDGE_VERBOSE_CONTEXT:-}" ]]; then
    printf '[%s] ' "$BRIDGE_VERBOSE_CONTEXT"
  fi
}

binary_looks_like_ci_shim() {
  local path="$1"

  if [[ "${BRIDGE_ALLOW_CI_SHIMS:-0}" == "1" ]]; then
    return 1
  fi

  [[ -f "$path" ]] || return 1
  grep -Fq 'ci shim ' "$path" 2>/dev/null
}

resolve_binary_path() {
  local out_var="$1"
  local label="$2"
  local env_var_name="$3"
  local command_name="$4"
  shift 4

  local env_value="${!env_var_name:-}"
  local candidate=""
  local resolved=""
  local -a candidate_paths=("$@")
  local candidate_count="${#candidate_paths[@]}"
  local prefer_candidate_for_generic_env=0

  if [[ -n "$env_value" && "$env_value" == "$command_name" && "$candidate_count" -gt 0 ]]; then
    prefer_candidate_for_generic_env=1
  fi

  if [[ "$prefer_candidate_for_generic_env" -eq 1 ]]; then
    for candidate in "${candidate_paths[@]}"; do
      if [[ -n "$candidate" && -x "$candidate" ]] && ! binary_looks_like_ci_shim "$candidate"; then
        resolved="$candidate"
        break
      fi
    done
  fi

  if [[ -z "$resolved" && -n "$env_value" ]]; then
    if [[ "$env_value" == */* ]]; then
      if [[ -x "$env_value" ]]; then
        if binary_looks_like_ci_shim "$env_value"; then
          echo "Configured $label via $env_var_name points to a CI shim, not a real binary: $env_value" >&2
          return 1
        fi
        resolved="$env_value"
      else
        echo "Configured $label via $env_var_name, but it is not executable: $env_value" >&2
        return 1
      fi
    else
      resolved="$(command -v "$env_value" 2>/dev/null || true)"
      if [[ -z "$resolved" ]]; then
        echo "Configured $label via $env_var_name, but it was not found in PATH: $env_value" >&2
        return 1
      fi
      if binary_looks_like_ci_shim "$resolved"; then
        echo "Configured $label via $env_var_name resolves to a CI shim, not a real binary: $resolved" >&2
        return 1
      fi
    fi
  fi

  if [[ -z "$resolved" && "$candidate_count" -gt 0 ]]; then
    for candidate in "${candidate_paths[@]}"; do
      if [[ -n "$candidate" && -x "$candidate" ]] && ! binary_looks_like_ci_shim "$candidate"; then
        resolved="$candidate"
        break
      fi
    done
  fi

  if [[ -z "$resolved" && ( "$command_name" == "trix" || "$command_name" == "cshell" ) ]]; then
    for candidate in "$HOME/.tx3/default/bin/$command_name" "$HOME/.tx3/stable/bin/$command_name"; do
      if [[ -x "$candidate" ]] && ! binary_looks_like_ci_shim "$candidate"; then
        resolved="$candidate"
        break
      fi
    done
  fi

  if [[ -z "$resolved" ]]; then
    resolved="$(command -v "$command_name" 2>/dev/null || true)"
  fi

  if [[ -n "$resolved" ]] && binary_looks_like_ci_shim "$resolved"; then
    resolved=""
  fi

  if [[ -z "$resolved" ]]; then
    echo "Missing $label." >&2
    echo "Set $env_var_name=/path/to/$command_name or install '$command_name' in PATH." >&2
    if [[ "$command_name" == "trix" || "$command_name" == "cshell" ]]; then
      echo "Tip: run ./scripts/bootstrap_dev_env.sh to provision repo-local tooling under .tools/bin." >&2
    fi
    if [[ "$candidate_count" -gt 0 ]]; then
      echo "Checked conventional locations:" >&2
      for candidate in "${candidate_paths[@]}"; do
        [[ -n "$candidate" ]] && echo "  - $candidate" >&2
      done
    fi
    return 1
  fi

  printf -v "$out_var" '%s' "$resolved"
}

print_resolved_value_if_verbose() {
  local label="$1"
  local value="$2"

  if command -v record_debug_context >/dev/null 2>&1; then
    record_debug_context "$label" "$value"
  fi

  if [[ "${BRIDGE_FLOW_VERBOSE:-0}" != "1" ]]; then
    return
  fi

  echo "$(verbose_context_prefix)Resolved $label: $value"
}

print_resolved_binary_if_verbose() {
  local label="$1"
  local value="$2"

  print_resolved_value_if_verbose "$label" "$value"

  if [[ "${BRIDGE_FLOW_VERBOSE:-0}" != "1" ]]; then
    return
  fi

  if [[ -x "$value" ]]; then
    "$value" --version 2>/dev/null | head -n 1 | sed "s/^/$(verbose_context_prefix)${label} version: /" || true
  fi
}

sha256_stream() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
    return
  fi

  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 | awk '{print $NF}'
    return
  fi

  echo "Missing SHA-256 command (sha256sum, shasum, or openssl)." >&2
  return 1
}

sha256_file() {
  local path="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | cut -d' ' -f1
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | cut -d' ' -f1
    return
  fi

  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$path" | awk '{print $NF}'
    return
  fi

  echo "Missing SHA-256 command (sha256sum, shasum, or openssl)." >&2
  return 1
}

hash_sorted_files_from_stdin0() {
  local path=""
  local -a paths=()
  local -a sorted_paths=()
  local old_ifs="$IFS"

  while IFS= read -r -d '' path; do
    paths+=("$path")
  done

  if [[ "${#paths[@]}" -eq 0 ]]; then
    return 0
  fi

  IFS=$'\n' sorted_paths=($(printf '%s\n' "${paths[@]}" | LC_ALL=C sort))
  IFS="$old_ifs"

  for path in "${sorted_paths[@]}"; do
    printf '%s  %s\n' "$(sha256_file "$path")" "$path"
  done
}

list_listening_pids_for_port() {
  local port="$1"
  local result=""

  if command -v lsof >/dev/null 2>&1; then
    lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true
    return
  fi

  if command -v ss >/dev/null 2>&1; then
    result="$(
      ss -ltnp "( sport = :$port )" 2>/dev/null \
        | grep -oE 'pid=[0-9]+' \
        | cut -d= -f2 \
        | sort -u || true
    )"
    if [[ -n "$result" ]]; then
      printf '%s\n' "$result"
    fi
    return
  fi

  return 0
}

export_resolved_toolchain_env() {
  local var_name=""

  for var_name in \
    BRIDGE_VERBOSE_CONTEXT \
    PYTHON_BIN \
    AIKEN_BIN \
    CARGO_BIN \
    UV_BIN \
    TRIX_BIN \
    CSHELL_BIN \
    DOLOS_BIN \
    DOLOS_DIR \
    DOLOS_CARGO_MANIFEST \
    DOLOS_DEVNET_DIR
  do
    if [[ -n "${!var_name:-}" ]]; then
      export "$var_name"
    fi
  done
}

append_effective_toolchain_manifest() {
  local target_path="$1"
  local temp_path=""

  temp_path="$(mktemp_in_dir "$(dirname "$target_path")" "toolchain-manifest.XXXXXX.tmp")"
  if [[ -f "$target_path" ]]; then
    grep -Ev '^(PYTHON_BIN|AIKEN_BIN|CARGO_BIN|UV_BIN|TRIX_BIN|CSHELL_BIN|DOLOS_BIN|DOLOS_CARGO_MANIFEST|DOLOS_DEVNET_DIR)=' \
      "$target_path" >"$temp_path" || true
  fi

  cat >>"$temp_path" <<EOF
PYTHON_BIN=$(printf '%q' "${PYTHON_BIN:-}")
AIKEN_BIN=$(printf '%q' "${AIKEN_BIN:-}")
CARGO_BIN=$(printf '%q' "${CARGO_BIN:-}")
UV_BIN=$(printf '%q' "${UV_BIN:-}")
TRIX_BIN=$(printf '%q' "${TRIX_BIN:-}")
CSHELL_BIN=$(printf '%q' "${CSHELL_BIN:-}")
DOLOS_BIN=$(printf '%q' "${DOLOS_BIN:-}")
DOLOS_CARGO_MANIFEST=$(printf '%q' "${DOLOS_CARGO_MANIFEST:-}")
DOLOS_DEVNET_DIR=$(printf '%q' "${DOLOS_DEVNET_DIR:-}")
EOF

  mv "$temp_path" "$target_path"
}

persist_mithril_aggregator_fingerprint() {
  local output_dir="$1"
  local manifest_path="${2:-}"
  local aggregator_endpoint="${3:-${MITHRIL_AGGREGATOR_ENDPOINT:-}}"
  local helper_path="$ROOT_DIR/scripts/python/write_mithril_aggregator_fingerprint.py"
  local fingerprint_path="$output_dir/mithril-aggregator-fingerprint.json"
  local env_tmp=""
  local manifest_tmp=""
  local filter_regex='^(MITHRIL_AGGREGATOR_(FINGERPRINT_PATH|ENDPOINT|FETCHED_AT_UTC|OPEN_API_VERSION|DOCUMENTATION_URL|EPOCH|CARDANO_NETWORK|CARDANO_ERA|MITHRIL_ERA|CARDANO_NODE_VERSION|NODE_VERSION|PROTOCOL_JSON|NEXT_PROTOCOL_JSON|TOTAL_SIGNERS|TOTAL_NEXT_SIGNERS|TOTAL_STAKES_SIGNERS|TOTAL_NEXT_STAKES_SIGNERS|TOTAL_CARDANO_SPO|TOTAL_CARDANO_STAKE|SIGNED_ENTITY_TYPES|SIGNED_ENTITY_TYPES_JSON|AGGREGATE_SIGNATURE_TYPE|MAX_HASHES_ALLOWED_BY_REQUEST))='
  local -a helper_cmd=("$PYTHON_BIN" "$helper_path" "$fingerprint_path")

  if [[ ! -f "$helper_path" ]]; then
    echo "Warning: missing Mithril aggregator fingerprint helper at: $helper_path" >&2
    return 0
  fi

  mkdir -p "$output_dir"
  env_tmp="$(mktemp_in_dir "$output_dir" "mithril-aggregator-fingerprint.XXXXXX.env")"
  if [[ -n "$aggregator_endpoint" ]]; then
    helper_cmd+=(--aggregator-endpoint "$aggregator_endpoint")
  fi
  if ! "${helper_cmd[@]}" >"$env_tmp"; then
    echo "Warning: could not persist Mithril aggregator fingerprint for $output_dir" >&2
    rm -f "$env_tmp"
    return 0
  fi

  if command -v record_debug_context >/dev/null 2>&1; then
    record_debug_context "Mithril aggregator fingerprint" "$fingerprint_path"
  fi

  if [[ -n "$manifest_path" ]]; then
    manifest_tmp="$(mktemp_in_dir "$(dirname "$manifest_path")" "mithril-aggregator-manifest.XXXXXX.tmp")"
    if [[ -f "$manifest_path" ]]; then
      grep -Ev "$filter_regex" "$manifest_path" >"$manifest_tmp" || true
    fi
    cat "$env_tmp" >>"$manifest_tmp"
    mv "$manifest_tmp" "$manifest_path"
  fi

  rm -f "$env_tmp"
}
