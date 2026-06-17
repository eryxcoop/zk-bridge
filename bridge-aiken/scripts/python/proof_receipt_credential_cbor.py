#!/usr/bin/env python3

import json
from pathlib import Path

import cbor2

ROOT_DIR = Path(__file__).resolve().parents[2]
PLUTUS_JSON = ROOT_DIR / "plutus.json"
VALIDATOR_TITLE = "proof_receipt.proof_receipt_validator.spend"


def main() -> int:
    blueprint = json.loads(PLUTUS_JSON.read_text())
    validators = {entry["title"]: entry for entry in blueprint["validators"]}
    if VALIDATOR_TITLE not in validators:
        raise SystemExit(
            f"Missing validator {VALIDATOR_TITLE!r} in {PLUTUS_JSON}"
        )

    hash_bytes = bytes.fromhex(validators[VALIDATOR_TITLE]["hash"])
    print(cbor2.dumps(cbor2.CBORTag(122, [hash_bytes])).hex())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
