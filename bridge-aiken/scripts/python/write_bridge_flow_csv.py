#!/usr/bin/env python3

import csv
import sys
from pathlib import Path

from tx_publish_summary import collect_summary


def main() -> int:
    if len(sys.argv) < 5 or (len(sys.argv) - 3) % 2 != 0:
        raise SystemExit(
            "usage: write_bridge_flow_csv.py <out-csv> <fallback-reference-lovelace> <tx-name> <result-json> [<tx-name> <result-json> ...]"
        )

    out_path = Path(sys.argv[1])
    fallback_reference_lovelace = int(sys.argv[2])
    raw_pairs = sys.argv[3:]

    rows = []
    previous_result_paths: list[Path] = []

    for index in range(0, len(raw_pairs), 2):
        label = raw_pairs[index]
        result_path = Path(raw_pairs[index + 1])
        summary = collect_summary(
            label,
            result_path,
            fallback_reference_lovelace,
            previous_result_paths,
        )
        rows.append(
            {
                "transaction_name": summary["label"],
                "hash": summary["hash"],
                "txSize": summary["tx_size"],
                "cpu_units": summary["cpu"] if summary["cpu"] is not None else "N/A",
                "memory_units": summary["memory"] if summary["memory"] is not None else "N/A",
            }
        )
        previous_result_paths.append(result_path)

    with out_path.open("w", newline="", encoding="utf-8") as outfile:
        writer = csv.DictWriter(
            outfile,
            fieldnames=[
                "transaction_name",
                "hash",
                "txSize",
                "cpu_units",
                "memory_units",
            ],
        )
        writer.writeheader()
        writer.writerows(rows)

    print(out_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
