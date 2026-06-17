#!/usr/bin/env python3

import json
import sys
from pathlib import Path


def resolve_path(data, field: str):
    current = data
    for part in field.split("."):
        if isinstance(current, list):
            current = current[int(part)]
        else:
            current = current[part]
    return current


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: read_json_field.py <json-path> <field>")

    path = Path(sys.argv[1])
    field = sys.argv[2]
    data = json.loads(path.read_text())
    value = resolve_path(data, field)
    if isinstance(value, (dict, list)):
        print(json.dumps(value))
    else:
        print(value)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
