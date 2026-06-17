init_dolos_layout() {
  local root_dir="$1"
  local sibling_manifest=""
  local vendored_devnet_dir="$root_dir/scripts/data/dolos-devnet"

  DOLOS_DIR="${DOLOS_DIR:-$root_dir/../dolos}"
  DOLOS_BIN_SIBLING_DEFAULT="$DOLOS_DIR/target/debug/dolos"
  sibling_manifest="$DOLOS_DIR/Cargo.toml"
  if [[ -z "${DOLOS_CARGO_MANIFEST:-}" && -f "$sibling_manifest" ]]; then
    DOLOS_CARGO_MANIFEST="$sibling_manifest"
  fi

  # Resolve where the Dolos devnet genesis templates live, in priority order
  # (same logic as check_workspace_layout.sh). The bootstrap reads from here to
  # (re)build the `.tx3/dolos` runtime scaffold.
  if [[ -n "${DOLOS_DEVNET_DIR:-}" ]]; then
    # 1. Caller-provided path via the DOLOS_DEVNET_DIR env var: leave it as-is.
    :
  elif [[ -d "$root_dir/.tx3/dolos" ]]; then
    # 2. The scaffold was already built in a previous run: reuse it.
    DOLOS_DEVNET_DIR="$root_dir/.tx3/dolos"
  elif [[ -d "$vendored_devnet_dir" ]]; then
    # 3. Fresh checkout: fall back to the templates vendored in the repo.
    DOLOS_DEVNET_DIR="$vendored_devnet_dir"
  else
    # 4. Nothing found: point at the scaffold path so the bootstrap reports it.
    DOLOS_DEVNET_DIR="$root_dir/.tx3/dolos"
  fi
}

resolve_dolos_binary() {
  resolve_binary_path DOLOS_BIN "Dolos binary" DOLOS_BIN dolos
}

require_dolos_manifest() {
  if [[ ! -f "$DOLOS_CARGO_MANIFEST" ]]; then
    echo "Missing Dolos Cargo manifest at: $DOLOS_CARGO_MANIFEST" >&2
    echo "This flow needs the Dolos source tree in the supported sibling workspace, or DOLOS_CARGO_MANIFEST=/path/to/Cargo.toml." >&2
    return 1
  fi
}

maybe_build_sibling_dolos() {
  local cargo_bin="$1"
  local fingerprint_path=""
  local current_fingerprint=""
  local cargo_locked_args=()

  if [[ "$DOLOS_BIN" == "$DOLOS_BIN_SIBLING_DEFAULT" ]] && [[ -f "${DOLOS_CARGO_MANIFEST:-}" ]]; then
    require_dolos_manifest || return 1
    if [[ -f "$DOLOS_DIR/Cargo.lock" ]]; then
      cargo_locked_args=(--locked)
    fi
    fingerprint_path="$DOLOS_DIR/target/bridge-aiken-dolos-build.sha256"
    current_fingerprint="$(
      {
        printf 'dolos-build-v1\n'
        find "$DOLOS_DIR" \
          \( -path "$DOLOS_DIR/target" -o -path "$DOLOS_DIR/.git" \) -prune -o \
          \( -name '*.rs' -o -name 'Cargo.toml' -o -name 'Cargo.lock' \) -type f -print0 \
          | hash_sorted_files_from_stdin0
      } | sha256_stream
    )"
    if [[ -x "$DOLOS_BIN_SIBLING_DEFAULT" ]] && [[ -f "$fingerprint_path" ]] && [[ "$(cat "$fingerprint_path")" == "$current_fingerprint" ]]; then
      skip_stage "Building sibling Dolos" "fingerprint unchanged"
      return 0
    fi
    begin_stage "Building sibling Dolos"
    run_logged "cargo build dolos" "$cargo_bin" build "${cargo_locked_args[@]}" --manifest-path "$DOLOS_CARGO_MANIFEST" -p dolos
    mkdir -p "$(dirname "$fingerprint_path")"
    printf '%s\n' "$current_fingerprint" >"$fingerprint_path"
  fi
}

print_dolos_resolution_if_verbose() {
  if [[ "${BRIDGE_FLOW_VERBOSE:-0}" != "1" ]]; then
    return
  fi

  print_resolved_binary_if_verbose "Dolos binary" "${DOLOS_BIN:-}"
  print_resolved_value_if_verbose "Dolos manifest" "${DOLOS_CARGO_MANIFEST:-}"
  print_resolved_value_if_verbose "Dolos devnet dir" "${DOLOS_DEVNET_DIR:-}"
}
