#!/usr/bin/env python3

import re
import sys
from pathlib import Path

import cbor2


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit(
            "usage: locking_txs_updater_param_cbor.py <env-default-path> <unique-mint-utxo-ref|asset-name|initial-merkle-root>"
        )

    text = Path(sys.argv[1]).read_text()
    selector = sys.argv[2]

    if selector == "unique-mint-utxo-ref":
        match = re.search(
            r"pub const locking_txs_updater_unique_mint_utxo_ref: OutputReference =\s*"
            r"OutputReference \{\s*transaction_id: #\"([0-9a-f]+)\",\s*output_index: (\d+),\s*\}",
            text,
            flags=re.S,
        )
        if not match:
            raise SystemExit(
                "Failed to locate locking_txs_updater_unique_mint_utxo_ref"
            )

        tx_id = bytes.fromhex(match.group(1))
        index = int(match.group(2))
        print(cbor2.dumps(cbor2.CBORTag(121, [tx_id, index])).hex())
        return 0

    if selector == "asset-name":
        match = re.search(
            r'pub const locking_txs_updater_asset_name: ByteArray = "([^"]+)"',
            text,
        )
        if not match:
            raise SystemExit("Failed to locate locking_txs_updater_asset_name")

        print(cbor2.dumps(match.group(1).encode()).hex())
        return 0

    if selector == "initial-merkle-root":
        match = re.search(
            r'pub const locking_txs_updater_initial_merkle_root: ByteArray =\s*(?:"([^"]+)"|#"([0-9a-f]+)")',
            text,
            flags=re.S,
        )
        if not match:
            raise SystemExit(
                "Failed to locate locking_txs_updater_initial_merkle_root"
            )

        if match.group(1) is not None:
            value = match.group(1).encode()
        else:
            value = bytes.fromhex(match.group(2))
        print(cbor2.dumps(value).hex())
        return 0

    raise SystemExit(f"Unknown selector: {selector}")


if __name__ == "__main__":
    raise SystemExit(main())
