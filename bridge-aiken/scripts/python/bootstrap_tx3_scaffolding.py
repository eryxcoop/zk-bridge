#!/usr/bin/env python3

import os
from pathlib import Path
import shutil


CSHELL_TOML = """[[wallets]]
name = "bob"
public_key = "d0f7c93d2a3ea762ab3f3fe223569f859f7538e79507c946e7e71081a7873e8fdb3e0d7ae3d358cceaf402f7f72a5ea3c30233d411dd49e5bfea6c6d92e110d5"
private_key = "88d604e141947705ff74e0042be492b62b8364d4436510881eee38154b8a825b0bf9b3fb3edaedb092703d5e21d579c2fa2e01ca6c1a2e6bdb4414de764116db"
created = "2026-04-03T20:13:52.524535364-03:00"
modified = "2026-04-03T20:13:52.524568762-03:00"
is_default = true
is_unsafe = true

[[wallets]]
name = "charlie"
public_key = "1f8e40e528e6b6fdfa2d24250aa1e74d0191a2b3a28aa6196b58cda1d91732d17a6f40872c2e4df984dfac237e5782a2b6db6aeb67f6ab11123870b4145efbe5"
private_key = "b0b942738bef2b73ffc15075aa9e5003a1d5090e7e3e011a7e1f6f136d14c056e48bfb9bdb39dde7022e444db53ba4925e7b1a5c2b014fa463fa8e70610c9af1"
created = "2026-04-03T20:13:52.536849791-03:00"
modified = "2026-04-03T20:13:52.536850874-03:00"
is_default = false
is_unsafe = true

[[wallets]]
name = "alice"
public_key = "9b1622919b3a74c037599d67d065f10c46c047801efe024a80344e79be4d9c0b2edb662977726943b63e8c9c5ee761c77f682ee31ef28e74fcab8a54bf692438"
private_key = "30bf896c2667e069f3a27e1d0b5c99dba3703261ad378aa0540006072137fc5bf31fdb286ec09dc31365f5e4dbfc70e0fd8dc3cf219d22fe5a93fe0cd331979d"
created = "2026-04-03T20:13:52.548781986-03:00"
modified = "2026-04-03T20:13:52.548782766-03:00"
is_default = false
is_unsafe = true

[[providers]]
type = "Provider"
name = "trix-local"
url = "http://localhost:5164/u5c"
is_default = false
is_testnet = true
trp_url = "http://localhost:8164"

[providers.headers]

[providers.trp_headers]
"""


DOLOS_TOML = """[upstream]
block_production_interval = 5

[storage]
version = "v3"
path = "data"

[storage.wal]
backend = "in_memory"

[storage.state]
backend = "in_memory"

[storage.archive]
backend = "in_memory"

[storage.index]
backend = "in_memory"

[genesis]
byron_path = "./byron.json"
shelley_path = "./shelley.json"
alonzo_path = "./alonzo.json"
conway_path = "./conway.json"
force_protocol = 9

[sync]
pull_batch_size = 100

[serve.grpc]
listen_address = "[::]:5164"
permissive_cors = true

[serve.minibf]
listen_address = "[::]:3164"
permissive_cors = true

[serve.trp]
listen_address = "[::]:8164"
max_optimize_rounds = 10
permissive_cors = true

[chain]
type = "cardano"

[[chain.custom_utxos]]
ref = [
    "8d910e3a410a353787d50a708e24c6ba2cc2b6b86ec6d8cb5bf9bbec20bfc937",
    0,
]
era = 7
cbor = [
    162,
    0,
    88,
    29,
    96,
    13,
    209,
    114,
    185,
    177,
    134,
    111,
    217,
    81,
    59,
    150,
    252,
    190,
    55,
    138,
    45,
    90,
    220,
    127,
    180,
    153,
    148,
    158,
    136,
    101,
    213,
    62,
    223,
    1,
    27,
    0,
    0,
    0,
    23,
    72,
    118,
    232,
    0,
]

[[chain.custom_utxos]]
ref = [
    "3d930cc9415a0221ff96f4ce00dd0732ee9d692e3b6231b4dbbda540469cf761",
    0,
]
era = 7
cbor = [
    162,
    0,
    88,
    29,
    96,
    13,
    209,
    114,
    185,
    177,
    134,
    111,
    217,
    81,
    59,
    150,
    252,
    190,
    55,
    138,
    45,
    90,
    220,
    127,
    180,
    153,
    148,
    158,
    136,
    101,
    213,
    62,
    223,
    1,
    26,
    0,
    152,
    150,
    128,
]

[logging]
include_grpc = true
"""

VENDORED_DOLOS_DEVNET_DIR = (
    Path(__file__).resolve().parent.parent / "data" / "dolos-devnet"
)


def genesis_templates_exist(path: Path) -> bool:
    return path.is_dir() and all(
        (path / name).is_file()
        for name in ("byron.json", "shelley.json", "alonzo.json", "conway.json")
    )


def resolve_dolos_devnet_dir(root: Path) -> Path:
    # `.tx3/dolos/` is a regenerable runtime scaffold, not the canonical source
    # of truth. When it is absent, we rebuild it from the vendored Dolos devnet
    # checked into `scripts/data/dolos-devnet/`.
    env_value = os.environ.get("DOLOS_DEVNET_DIR")
    if env_value:
        return Path(env_value)

    candidates = [
        root / ".tx3" / "dolos",
        VENDORED_DOLOS_DEVNET_DIR,
        root.parent / "dolos" / "crates" / "cardano" / "src" / "include" / "devnet",
    ]
    for candidate in candidates:
        if genesis_templates_exist(candidate):
            return candidate

    return root / ".tx3" / "dolos"


def copy_if_missing(src: Path, dst: Path) -> bool:
    if dst.exists():
        return False
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)
    return True


def write_if_missing(dst: Path, content: str) -> bool:
    if dst.exists():
        return False
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(content)
    return True


def main() -> int:
    root = Path(__file__).resolve().parent.parent.parent
    created = []

    dolos_devnet_dir = resolve_dolos_devnet_dir(root)
    if not genesis_templates_exist(dolos_devnet_dir):
        raise SystemExit(
            "Missing Dolos devnet genesis directory: "
            f"{dolos_devnet_dir}. Set DOLOS_DEVNET_DIR=/path/to/devnet, "
            "or restore bridge-aiken/scripts/data/dolos-devnet."
        )

    for name in ["byron.json", "shelley.json", "alonzo.json", "conway.json"]:
        src = dolos_devnet_dir / name
        dst = root / ".tx3" / "dolos" / name
        if not src.is_file():
            raise SystemExit(f"Missing genesis template: {src}")
        if copy_if_missing(src, dst):
            created.append(str(dst.relative_to(root)))

    if write_if_missing(root / ".tx3" / "dolos" / "dolos.toml", DOLOS_TOML):
        created.append(".tx3/dolos/dolos.toml")

    if write_if_missing(root / ".tx3" / "cshell" / "cshell.toml", CSHELL_TOML):
        created.append(".tx3/cshell/cshell.toml")

    if created:
        print("Bootstrapped Tx3 scaffolding:")
        for path in created:
            print(f"  - {path}")
    else:
        print("Tx3 scaffolding already present.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
