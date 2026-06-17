#!/usr/bin/env python3

from pathlib import Path
import sys

from check_mithril_poc_preflight import validate_proof_export_bundle_usage


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: check_mithril_proof_export_bundle_contract.py <proof-export-bundle-json>")

    bundle_path = Path(sys.argv[1])
    validate_proof_export_bundle_usage(bundle_path)
    print(f"Proof-export bundle contract check passed: {bundle_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
