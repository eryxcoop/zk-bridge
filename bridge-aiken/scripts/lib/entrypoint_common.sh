handoff_to_wrapper_if_direct() {
  local wrapper_path="$1"
  local wrapper_subcommand="$2"
  shift 2
  local rendered_args=""

  if [[ "${BRIDGE_INTERNAL_CALL:-0}" == "1" ]]; then
    return
  fi

  if [[ "$#" -gt 0 ]]; then
    rendered_args=" $*"
  fi

  echo "Notice: '$0' is no longer a standalone public entrypoint." >&2
  echo "Redirecting to: ./scripts/bridge.sh $wrapper_subcommand$rendered_args" >&2

  exec "$wrapper_path" "$wrapper_subcommand" "$@"
}
