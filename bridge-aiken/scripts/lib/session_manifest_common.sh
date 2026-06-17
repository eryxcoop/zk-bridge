fail_session_manifest_dependency() {
  local manifest_path="$1"
  local message="$2"
  shift 2 || true
  echo "[session-manifest] $message" >&2
  echo "Manifest: $manifest_path" >&2
  while [[ $# -gt 0 ]]; do
    echo "$1" >&2
    shift
  done
  exit 1
}

require_session_manifest_var() {
  local manifest_path="$1"
  local var_name="$2"
  local purpose="$3"

  if [[ -z "${!var_name:-}" ]]; then
    fail_session_manifest_dependency \
      "$manifest_path" \
      "Missing required manifest field: $var_name" \
      "Needed for: $purpose"
  fi
}

require_session_manifest_utxo() {
  local manifest_path="$1"
  local var_name="$2"
  local purpose="$3"

  require_session_manifest_var "$manifest_path" "$var_name" "$purpose"
  if [[ ! "${!var_name}" =~ ^[^#[:space:]]+#[0-9]+$ ]]; then
    fail_session_manifest_dependency \
      "$manifest_path" \
      "Invalid UTxO reference in manifest field: $var_name" \
      "Got: ${!var_name}" \
      "Needed for: $purpose"
  fi
}
