#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Uso: $0 <response_json_file> <tx_hash> <output_file>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cargo run \
  --manifest-path "$SCRIPT_DIR/Cargo.toml" \
  --bin legacy_tx_witness_from_response_json \
  -- "$1" "$2" "$3"
