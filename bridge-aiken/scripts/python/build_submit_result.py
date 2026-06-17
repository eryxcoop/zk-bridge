#!/usr/bin/env python3

import json
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 4:
        raise SystemExit(
            "usage: build_submit_result.py <skip-json> <submit-json> <output-json>"
        )

    skip_payload = json.loads(Path(sys.argv[1]).read_text())
    submit_payload = json.loads(Path(sys.argv[2]).read_text())
    output_path = Path(sys.argv[3])

    hash_value = submit_payload.get("hash", skip_payload.get("hash"))
    result = {"cbor": skip_payload["cbor"], "hash": hash_value}
    output_path.write_text(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
