#!/usr/bin/env python3

import json
import sys
from pathlib import Path

import cbor2


def main() -> int:
    if len(sys.argv) != 4:
        raise SystemExit(
            "usage: blueprint_param_cbor.py <blueprint-json> <validator-title> <policy-id|script-credential>"
        )

    blueprint_path = Path(sys.argv[1])
    validator_title = sys.argv[2]
    selector = sys.argv[3]

    blueprint = json.loads(blueprint_path.read_text())
    validators = {entry["title"]: entry for entry in blueprint["validators"]}

    if validator_title not in validators:
        raise SystemExit(
            f"Missing validator {validator_title!r} in {blueprint_path}"
        )

    hash_bytes = bytes.fromhex(validators[validator_title]["hash"])

    if selector == "policy-id":
        print(cbor2.dumps(hash_bytes).hex())
        return 0

    if selector == "script-credential":
        print(cbor2.dumps(cbor2.CBORTag(122, [hash_bytes])).hex())
        return 0

    raise SystemExit(
        f"Unknown selector {selector!r}; expected 'policy-id' or 'script-credential'"
    )


if __name__ == "__main__":
    raise SystemExit(main())
