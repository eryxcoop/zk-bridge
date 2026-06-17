#!/usr/bin/env python3

import argparse
import json
import os
from pathlib import Path

from bootstrap_tx3_scaffolding import CSHELL_TOML
from build_phase12_args_from_mithril_proof_export_bundle import (
    build_phase12_args_from_proof_export_bundle_file,
)

EXTRA_COLLATERAL_UTXOS = """

[[chain.custom_utxos]]
ref = [
    "8d910e3a410a353787d50a708e24c6ba2cc2b6b86ec6d8cb5bf9bbec20bfc938",
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
    "8d910e3a410a353787d50a708e24c6ba2cc2b6b86ec6d8cb5bf9bbec20bfc939",
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
    "8d910e3a410a353787d50a708e24c6ba2cc2b6b86ec6d8cb5bf9bbec20bfc93a",
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
    "8d910e3a410a353787d50a708e24c6ba2cc2b6b86ec6d8cb5bf9bbec20bfc93b",
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
    "8d910e3a410a353787d50a708e24c6ba2cc2b6b86ec6d8cb5bf9bbec20bfc93c",
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
    "8d910e3a410a353787d50a708e24c6ba2cc2b6b86ec6d8cb5bf9bbec20bfc93d",
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
    "3d930cc9415a0221ff96f4ce00dd0732ee9d692e3b6231b4dbbda540469cf762",
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

[[chain.custom_utxos]]
ref = [
    "3d930cc9415a0221ff96f4ce00dd0732ee9d692e3b6231b4dbbda540469cf763",
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

[[chain.custom_utxos]]
ref = [
    "3d930cc9415a0221ff96f4ce00dd0732ee9d692e3b6231b4dbbda540469cf764",
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

[[chain.custom_utxos]]
ref = [
    "3d930cc9415a0221ff96f4ce00dd0732ee9d692e3b6231b4dbbda540469cf765",
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
    5,
    245,
    225,
    0,
]

[[chain.custom_utxos]]
ref = [
    "3d930cc9415a0221ff96f4ce00dd0732ee9d692e3b6231b4dbbda540469cf766",
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
    5,
    245,
    225,
    0,
]

[[chain.custom_utxos]]
ref = [
    "3d930cc9415a0221ff96f4ce00dd0732ee9d692e3b6231b4dbbda540469cf767",
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
    5,
    245,
    225,
    0,
]

[[chain.custom_utxos]]
ref = [
    "3d930cc9415a0221ff96f4ce00dd0732ee9d692e3b6231b4dbbda540469cf768",
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
    5,
    245,
    225,
    0,
]

[[chain.custom_utxos]]
ref = [
    "3d930cc9415a0221ff96f4ce00dd0732ee9d692e3b6231b4dbbda540469cf769",
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
    5,
    245,
    225,
    0,
]

[[chain.custom_utxos]]
ref = [
    "3d930cc9415a0221ff96f4ce00dd0732ee9d692e3b6231b4dbbda540469cf76a",
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
    5,
    245,
    225,
    0,
]
"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("tmp", type=Path)
    parser.add_argument("user_address")
    parser.add_argument("grpc_port")
    parser.add_argument("trp_port")
    parser.add_argument("minibf_port")
    parser.add_argument("--mithril-stm-proof-export-bundle", type=Path, default=None)
    parser.add_argument("--proof-name", type=str, default=None)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root
    tmp = args.tmp
    user_address = args.user_address
    grpc_port = args.grpc_port
    trp_port = args.trp_port
    minibf_port = args.minibf_port
    shelley_path = tmp / "shelley.json"
    max_tx_size = int(os.environ.get("DOLOS_MAX_TX_SIZE", "32768"))

    store_path = tmp / "cshell.toml"
    # The local runtime lane must remain independent from whatever provider or
    # wallet state the operator currently keeps under `.tx3/cshell/` for
    # Preview/manual work. Always synthesize a fresh local store from the
    # checked-in devnet template so `trix-local` + `bob` are guaranteed to
    # exist for the scripts that invoke/sign against patched Dolos.
    store_text = CSHELL_TOML
    store_text = store_text.replace(
        "http://localhost:5164/u5c", f"http://localhost:{grpc_port}/u5c"
    )
    store_text = store_text.replace(
        'trp_url = "http://localhost:8164"',
        f'trp_url = "http://localhost:{trp_port}"',
    )
    store_path.write_text(store_text)

    dolos_config_path = tmp / "dolos.toml"
    dolos_text = (root / ".tx3/dolos/dolos.toml").read_text()
    dolos_text = dolos_text.replace(
        'byron_path = "./byron.json"',
        f'byron_path = "{root / ".tx3/dolos/byron.json"}"',
    )
    dolos_text = dolos_text.replace(
        'shelley_path = "./shelley.json"', f'shelley_path = "{shelley_path}"'
    )
    dolos_text = dolos_text.replace(
        'alonzo_path = "./alonzo.json"',
        f'alonzo_path = "{root / ".tx3/dolos/alonzo.json"}"',
    )
    dolos_text = dolos_text.replace(
        'conway_path = "./conway.json"',
        f'conway_path = "{root / ".tx3/dolos/conway.json"}"',
    )
    dolos_text = dolos_text.replace(
        'listen_address = "[::]:5164"', f'listen_address = "[::]:{grpc_port}"', 1
    )
    dolos_text = dolos_text.replace(
        'listen_address = "[::]:3164"', f'listen_address = "[::]:{minibf_port}"', 1
    )
    dolos_text = dolos_text.replace(
        'listen_address = "[::]:8164"', f'listen_address = "[::]:{trp_port}"', 1
    )
    if "magic =" not in dolos_text:
        dolos_text = dolos_text.replace(
            "[chain]\n",
            "[chain]\nmagic = 42\nis_testnet = true\n",
            1,
        )
    if '    "8d910e3a410a353787d50a708e24c6ba2cc2b6b86ec6d8cb5bf9bbec20bfc938",\n    0,' not in dolos_text:
        dolos_text = f"{dolos_text.rstrip()}\n{EXTRA_COLLATERAL_UTXOS}"
    dolos_config_path.write_text(dolos_text)

    shelley = json.loads((root / ".tx3/dolos/shelley.json").read_text())
    protocol_params = shelley.setdefault("protocolParams", {})
    protocol_params["maxTxSize"] = max_tx_size
    shelley_path.write_text(json.dumps(shelley, indent=2))

    data_dir = root / "scripts/data"
    phase1_template_path = data_dir / "phase1_args_raw.json"
    phase2_template_path = data_dir / "phase2_args_raw.json"

    if args.mithril_stm_proof_export_bundle is not None:
        phase1_data, phase2_data = build_phase12_args_from_proof_export_bundle_file(
            args.mithril_stm_proof_export_bundle,
            phase1_template_path,
            phase2_template_path,
            args.proof_name,
        )
    else:
        phase1_data = json.loads(phase1_template_path.read_text())
        phase2_data = json.loads(phase2_template_path.read_text())

    named_payloads = [
        (
            "publish_phase1_reference_script_args_raw.json",
            "publish-phase1-reference-script-args.json",
            json.loads((data_dir / "publish_phase1_reference_script_args_raw.json").read_text()),
        ),
        ("phase1_args_raw.json", "phase1-args.json", phase1_data),
        ("phase2_args_raw.json", "phase2-args.json", phase2_data),
    ]

    for raw_name, out_name, data in named_payloads:
        data["user"] = user_address
        if raw_name == "phase1_args_raw.json" and os.environ.get("PHASE1_PUBLIC_INPUT_2"):
            data["public_input_2"] = os.environ["PHASE1_PUBLIC_INPUT_2"]
        if raw_name == "phase1_args_raw.json" and os.environ.get(
            "PHASE1_STATEMENT_HASH_VALUE"
        ):
            data["statement_hash_value"] = os.environ["PHASE1_STATEMENT_HASH_VALUE"]
        if raw_name == "phase2_args_raw.json" and os.environ.get(
            "PHASE2_PROOF_RECEIPT_STATEMENT_HASH"
        ):
            data["proof_receipt_statement_hash"] = os.environ[
                "PHASE2_PROOF_RECEIPT_STATEMENT_HASH"
            ]
        (tmp / out_name).write_text(json.dumps(data, indent=2))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
