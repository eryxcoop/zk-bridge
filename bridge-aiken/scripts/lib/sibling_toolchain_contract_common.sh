fail_sibling_toolchain_contract() {
  local message="$1"
  shift || true
  echo "$message" >&2
  while [[ $# -gt 0 ]]; do
    echo "$1" >&2
    shift
  done
  return 1
}

require_contract_snippet() {
  local path="$1"
  local snippet="$2"
  local label="$3"

  if [[ ! -f "$path" ]]; then
    fail_sibling_toolchain_contract "Missing toolchain contract file for $label: $path"
    return 1
  fi

  if ! grep -Fq "$snippet" "$path"; then
    fail_sibling_toolchain_contract \
      "Missing required sibling toolchain patch for $label" \
      "File: $path" \
      "Expected snippet: $snippet"
    return 1
  fi
}

require_contract_snippet_count_at_least() {
  local path="$1"
  local snippet="$2"
  local minimum_count="$3"
  local label="$4"
  local count=""

  if [[ ! -f "$path" ]]; then
    fail_sibling_toolchain_contract "Missing toolchain contract file for $label: $path"
    return 1
  fi

  count="$(grep -Fc "$snippet" "$path" || true)"
  if (( count < minimum_count )); then
    fail_sibling_toolchain_contract \
      "Sibling toolchain patch count too low for $label" \
      "File: $path" \
      "Expected at least $minimum_count matches for: $snippet" \
      "Found: $count"
    return 1
  fi
}

check_patched_sibling_toolchain_contract() {
  local uplc_runtime_path="$1"
  local uplc_decoder_path="$2"
  local dolos_daemon_path="$3"

  require_contract_snippet \
    "$uplc_runtime_path" \
    'if size > &Integer::from(INTEGER_TO_BYTE_STRING_MAXIMUM_OUTPUT_LENGTH)' \
    'uplc IntegerToByteString maximum-length comparison' || return 1

  require_contract_snippet \
    "$uplc_decoder_path" \
    'let shifted_part = part << shift;' \
    'uplc FLAT decoder big_word UBig shift' || return 1

  require_contract_snippet \
    "$dolos_daemon_path" \
    '.thread_stack_size(32 * 1024 * 1024)' \
    'dolos Tokio worker stack size' || return 1

  require_contract_snippet_count_at_least \
    "$uplc_runtime_path" \
    'let mut arg1 = ubig_to_bytes(self.arena, &computation, Endianness::Big);' \
    2 \
    'uplc BLS scalar serialization via big-endian bytes' || return 1

  require_contract_snippet_count_at_least \
    "$uplc_runtime_path" \
    'blst::blst_scalar_from_bendian(scalar as *mut _, arg1.as_ptr() as *const _);' \
    2 \
    'uplc BLS scalar handoff to blst from serialized bytes' || return 1
}
