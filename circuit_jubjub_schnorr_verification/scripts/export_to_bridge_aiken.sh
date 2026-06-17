#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_DIR="$(cd "$ROOT_DIR/.." && pwd)"
BRIDGE_AIKEN_DIR="$WORKSPACE_DIR/bridge-aiken"
FINAL_FIXTURE_DIR="${JUBJUB_SCHNORR_FINAL_FIXTURE_DIR:-$ROOT_DIR/circuit_build/final_fixture}"
BRIDGE_AIKEN_RAW_JSON="$BRIDGE_AIKEN_DIR/scripts/data/jubjub_schnorr_raw.json"
BRIDGE_AIKEN_VK="$BRIDGE_AIKEN_DIR/lib/zk/jubjub_schnorr_verification_vk.ak"
BRIDGE_AIKEN_HELPER="$BRIDGE_AIKEN_DIR/validators/tests/helpers/jubjub_schnorr_fixture.ak"

if [[ ! -d "$BRIDGE_AIKEN_DIR" ]]; then
  echo "missing bridge-aiken sibling at: $BRIDGE_AIKEN_DIR" >&2
  exit 1
fi

bash "$ROOT_DIR/scripts/run_e2e_test.sh" "$FINAL_FIXTURE_DIR" "$BRIDGE_AIKEN_VK" >/dev/null
cp "$FINAL_FIXTURE_DIR/proof_summary.json" "$BRIDGE_AIKEN_RAW_JSON"
python3 "$BRIDGE_AIKEN_DIR/scripts/python/jubjub_schnorr_fixture.py"

echo "Exported Jubjub Schnorr fixture to:"
echo "  raw:    $BRIDGE_AIKEN_RAW_JSON"
echo "  helper: $BRIDGE_AIKEN_HELPER"
echo "  vk:     $BRIDGE_AIKEN_VK"
