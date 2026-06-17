#!/usr/bin/env python3

import json
import sys
from pathlib import Path


def assign_path(data, field: str, value: str) -> None:
    parts = field.split(".")
    current = data
    for part in parts[:-1]:
        if isinstance(current, list):
            current = current[int(part)]
        else:
            current = current[part]
    last = parts[-1]
    if isinstance(current, list):
        current[int(last)] = value
    else:
        current[last] = value


def main() -> int:
    if len(sys.argv) != 4:
        raise SystemExit("usage: set_json_field.py <json-path> <field> <value>")

    path = Path(sys.argv[1])
    field = sys.argv[2]
    value = sys.argv[3]

    data = json.loads(path.read_text())
    assign_path(data, field, value)
    path.write_text(json.dumps(data, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
