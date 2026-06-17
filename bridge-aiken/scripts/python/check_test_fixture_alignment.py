#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
from pathlib import Path

from bridge_zk_fixture import DATA_PATH, OUTPUT_PATH, load_bridge_zk_fixture


ROOT_DIR = Path(__file__).resolve().parent.parent.parent
CARDANO_TRANSACTIONS_CERTIFICATE_PATH = (
    ROOT_DIR / "validators" / "tests" / "helpers" / "certificates" / "cardano_transactions.ak"
)


def ensure_0x(value: str) -> str:
    return value if value.startswith("0x") else f"0x{value}"


def require_equal(label: str, actual: str, expected: str) -> None:
    if actual != expected:
        raise SystemExit(f"{label} drifted: expected {expected}, got {actual}")


def parse_aiken_bytearray_const(path: Path, const_name: str) -> str:
    pattern = re.compile(
        rf"pub const {re.escape(const_name)}\s*=\s*#\"([0-9a-fA-F]+)\"",
        re.MULTILINE,
    )
    match = pattern.search(path.read_text())
    if match is None:
        raise SystemExit(f"missing {const_name} in {path}")
    return ensure_0x(match.group(1).lower())


def parse_cardano_transactions_root(path: Path) -> str:
    pattern = re.compile(
        r"Pair\(\s*CardanoTransactionsMerkleRoot,\s*@\"([0-9a-fA-F]+)\"\s*,?\s*\)",
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(path.read_text())
    if match is None:
        raise SystemExit(f"missing CardanoTransactionsMerkleRoot fixture in {path}")
    return ensure_0x(match.group(1).lower())


def check_fixture_alignment(
    *,
    data_path: Path = DATA_PATH,
    bridge_fixture_path: Path = OUTPUT_PATH,
    cardano_transactions_path: Path = CARDANO_TRANSACTIONS_CERTIFICATE_PATH,
) -> dict[str, str]:
    bridge_raw = load_bridge_zk_fixture(data_path)
    bridge_raw_root = ensure_0x(
        bridge_raw["tx_snapshot_certificate_protocol_message_cardano_transactions_merkle_root_text"].lower()
    )
    bridge_fixture_root = parse_aiken_bytearray_const(
        bridge_fixture_path,
        "final_snapshot_root",
    )
    cardano_transactions_root = parse_cardano_transactions_root(cardano_transactions_path)

    require_equal(
        "bridge_fixture.final_snapshot_root",
        bridge_fixture_root,
        bridge_raw_root,
    )
    require_equal(
        "cardano_transactions fixture root",
        cardano_transactions_root,
        bridge_raw_root,
    )

    return {
        "bridge_raw_root": bridge_raw_root,
        "bridge_fixture_root": bridge_fixture_root,
        "cardano_transactions_root": cardano_transactions_root,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", type=Path, default=DATA_PATH)
    parser.add_argument("--bridge-fixture", type=Path, default=OUTPUT_PATH)
    parser.add_argument(
        "--cardano-transactions-certificate",
        type=Path,
        default=CARDANO_TRANSACTIONS_CERTIFICATE_PATH,
    )
    args = parser.parse_args()

    roots = check_fixture_alignment(
        data_path=args.data,
        bridge_fixture_path=args.bridge_fixture,
        cardano_transactions_path=args.cardano_transactions_certificate,
    )
    print(
        "Bridge fixture alignment OK:",
        f"bridge_raw={roots['bridge_raw_root']}",
        f"bridge_fixture={roots['bridge_fixture_root']}",
        f"cardano_transactions={roots['cardano_transactions_root']}",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
