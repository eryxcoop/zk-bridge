#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path

from arg_builder_common import parse_env_policy_const, parse_env_text_const, read_json, write_json
from bech32 import payment_key_hash_from_address
from bridge_zk_fixture import (
    DATA_PATH,
    OUTPUT_PATH,
    check_bridge_fixture,
    load_bridge_zk_fixture,
    write_bridge_fixture,
)
from check_test_fixture_alignment import check_fixture_alignment
from tx_snapshot_root import resolve_tx_snapshot_root

ROOT_DIR = Path(__file__).resolve().parent.parent.parent
REPO_ROOT = ROOT_DIR.parent
ENV_DEFAULT_PATH = ROOT_DIR / "env" / "default.ak"
CTS_DIR = REPO_ROOT / "circuit_transaction_snapshot"
CIE_DIR = REPO_ROOT / "circuit_inclusion_exclusion"
LOCKING_TX_BUILDER_DIR = ROOT_DIR / "tools" / "build_canonical_locking_tx"
DEFAULT_USER_ADDRESS = "addr_test1vqxazu4ekxrxlk238wt0e03h3gk44hrlkjvef85gvh2nahcgnmpfc"


def cargo_locked_args(crate_dir: Path) -> list[str]:
    return ["--locked"] if (crate_dir / "Cargo.lock").exists() else []


def _strip_0x(value: str) -> str:
    return value[2:] if value.startswith("0x") else value


def copy_generated_vk(source: Path, destination: Path) -> None:
    text = source.read_text()
    if not text.endswith("\n"):
        text += "\n"
    destination.write_text(text)


def derive_canonical_locking_tx(bridge_raw: dict) -> dict:
    """Builds the bridge's canonical minimal locking-transaction body with
    `tools/build_canonical_locking_tx` and returns its `tx_hash_hex`,
    `body_cbor_hex` and `datum_cbor_hex`.

    The transaction hash is *derived* from the body fields here so it can never
    drift from what the on-chain validator recomputes; the bridged asset
    `(policy, name)` and the datum `bridge_id` come from `env/default.ak`.
    """
    env_text = ENV_DEFAULT_PATH.read_text()
    asset_name_text = parse_env_text_const(env_text, "transferred_asset_name")
    spec = {
        "input_tx_id_hex": _strip_0x(bridge_raw["locking_tx_input_output_reference_tx_id_hex"]),
        "input_index": bridge_raw["locking_tx_input_output_reference_output_index"],
        "output_address_hex": _strip_0x(bridge_raw["locking_tx_output_address_hex"]),
        "output_lovelace": bridge_raw["locking_tx_output_lovelace"],
        "asset_policy_id_hex": parse_env_policy_const(env_text, "transferred_asset_policy_id"),
        "asset_name_hex": asset_name_text.encode().hex(),
        "asset_amount": bridge_raw["bridge_asset_amount"],
        "bridge_id_hex": parse_env_policy_const(env_text, "bridge_minting_policy_id"),
        "destination_vkh_hex": _strip_0x(
            bridge_raw["actual_locking_tx_destination_payment_credential_hex"]
        ),
        "fee": bridge_raw["locking_tx_fee"],
    }
    cmd = [
        "cargo",
        "run",
        *cargo_locked_args(LOCKING_TX_BUILDER_DIR),
        "--quiet",
        "--manifest-path",
        str(LOCKING_TX_BUILDER_DIR / "Cargo.toml"),
        "--",
        "-",
    ]
    env = dict(os.environ)
    if not env.get("RUSTFLAGS"):
        env["RUSTFLAGS"] = "-Awarnings"
    proc = subprocess.run(
        cmd,
        cwd=LOCKING_TX_BUILDER_DIR,
        input=json.dumps(spec),
        capture_output=True,
        text=True,
        check=True,
        env=env,
    )
    return json.loads(proc.stdout)


def run(cmd: list[str], cwd: Path, stdout_path: Path | None = None) -> None:
    stdout_handle = None
    try:
        if stdout_path is not None:
            stdout_path.parent.mkdir(parents=True, exist_ok=True)
            stdout_handle = stdout_path.open("w")
        env = dict(os.environ)
        if not env.get("RUSTFLAGS"):
            env["RUSTFLAGS"] = "-Awarnings"
        subprocess.run(cmd, cwd=cwd, check=True, stdout=stdout_handle, env=env)
    finally:
        if stdout_handle is not None:
            stdout_handle.close()


def maybe_check_fixture_alignment(
    *,
    skip_test_fixture_alignment: bool,
    data_path: Path,
    bridge_fixture_path: Path,
) -> None:
    if skip_test_fixture_alignment:
        return
    check_fixture_alignment(data_path=data_path, bridge_fixture_path=bridge_fixture_path)


def sync_bridge_fixture_helper(data_path: Path, output_path: Path) -> None:
    load_bridge_zk_fixture(data_path)
    write_bridge_fixture(output_path, data_path)


def export_snapshot_fixture(locking_hash_hex: str, work_dir: Path) -> dict:
    snapshot_dir = (work_dir / "snapshot").resolve()
    input_path = snapshot_dir / "input.json"
    summary_path = snapshot_dir / "proof_summary.json"

    cmd = [
        "cargo",
        "run",
        *cargo_locked_args(CTS_DIR),
        "--quiet",
        "--release",
        "--manifest-path",
        str(CTS_DIR / "Cargo.toml"),
        "--bin",
        "generate_test_witness_for_circuit",
        "--",
        "--tx-hash-hex",
        locking_hash_hex,
    ]
    run(cmd, cwd=CTS_DIR, stdout_path=input_path)

    export_cmd = [
        "cargo",
        "run",
        *cargo_locked_args(CTS_DIR),
        "--quiet",
        "--release",
        "--manifest-path",
        str(CTS_DIR / "Cargo.toml"),
        "--bin",
        "arkworks_circom_fixture_export",
        "--",
        str(input_path),
        str(snapshot_dir),
    ]
    run(export_cmd, cwd=CTS_DIR)
    return read_json(summary_path)


def export_tx_set_update_fixture(locking_hash_hex: str, work_dir: Path) -> dict:
    tx_set_update_dir = (work_dir / "tx-set-update").resolve()
    input_path = tx_set_update_dir / "input.json"
    summary_path = tx_set_update_dir / "proof_summary.json"
    cmd = [
        "cargo",
        "run",
        *cargo_locked_args(CIE_DIR),
        "--quiet",
        "--release",
        "--manifest-path",
        str(CIE_DIR / "Cargo.toml"),
        "--bin",
        "generate_test_witness_for_circuit",
        "--",
        "--tx-id-hex",
        locking_hash_hex,
    ]
    run(cmd, cwd=CIE_DIR, stdout_path=input_path)

    export_cmd = [
        "cargo",
        "run",
        *cargo_locked_args(CIE_DIR),
        "--quiet",
        "--release",
        "--manifest-path",
        str(CIE_DIR / "Cargo.toml"),
        "--bin",
        "arkworks_circom_fixture_export",
        "--",
        str(input_path),
        str(tx_set_update_dir),
    ]
    run(export_cmd, cwd=CIE_DIR)
    return read_json(summary_path)


def refresh_bridge_fixture(
    data_path: Path,
    output_path: Path,
    work_dir: Path,
    user_address: str,
    *,
    skip_test_fixture_alignment: bool,
) -> None:
    bridge_raw = read_json(data_path)
    canonical = derive_canonical_locking_tx(bridge_raw)
    locking_hash_hex = canonical["tx_hash_hex"]
    snapshot_summary = export_snapshot_fixture(locking_hash_hex, work_dir)
    tx_set_summary = export_tx_set_update_fixture(snapshot_summary["cardano_tx_hash_hex"], work_dir)

    # The arkworks export regenerates the (deterministic local-fixture) verifying
    # keys alongside each proof; copy them next to the validators so the
    # committed VK always matches the committed proof.
    copy_generated_vk(
        work_dir / "snapshot" / "snapshot_membership_vk.ak",
        ROOT_DIR / "lib" / "zk" / "snapshot_membership_vk.ak",
    )
    copy_generated_vk(
        work_dir / "tx-set-update" / "tx_set_update_vk.ak",
        ROOT_DIR / "lib" / "zk" / "tx_set_update_vk.ak",
    )

    updated = dict(bridge_raw)
    updated["locking_tx_hash_hex"] = snapshot_summary["cardano_tx_hash_hex"]
    updated["locking_tx_body_cbor_hex"] = canonical["body_cbor_hex"]
    updated["locking_tx_datum_cbor_hex"] = canonical["datum_cbor_hex"]
    updated["locking_tx_merkle_proof_public_sub_root_hex"] = snapshot_summary[
        "locking_tx_merkle_proof_public_sub_root_hex"
    ]
    updated["tx_snapshot_certificate_protocol_message_cardano_transactions_merkle_root_text"] = snapshot_summary[
        "tx_snapshot_certificate_protocol_message_cardano_transactions_merkle_root_hex"
    ]
    updated["packed_public_inputs"] = snapshot_summary["packed_public_inputs"]
    updated["minting_merkle_proof"] = snapshot_summary["minting_merkle_proof"]
    updated["new_merkle_root_hex"] = tx_set_summary["mt_root_out_hex"]
    updated["tx_set_update_packed_public_inputs"] = tx_set_summary["packed_public_inputs"]
    updated["tx_set_update_old_merkle_root_hex"] = tx_set_summary["mt_root_in_hex"]
    updated["tx_set_update_proof"] = tx_set_summary["tx_set_update_proof"]

    write_json(data_path, updated)
    load_bridge_zk_fixture(data_path)
    write_bridge_fixture(output_path, data_path)
    check_bridge_fixture(output_path, data_path)
    maybe_check_fixture_alignment(
        skip_test_fixture_alignment=skip_test_fixture_alignment,
        data_path=data_path,
        bridge_fixture_path=output_path,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--regenerate", action="store_true")
    mode.add_argument("--fix-drift", action="store_true")
    parser.add_argument(
        "--work-dir",
        type=Path,
        default=ROOT_DIR / "run_outputs" / "bridge-zk-fixture" / "latest",
    )
    parser.add_argument("--user-address", default=DEFAULT_USER_ADDRESS)
    parser.add_argument("--data", type=Path, default=DATA_PATH)
    parser.add_argument("--output", type=Path, default=OUTPUT_PATH)
    parser.add_argument("--proof-export-bundle", type=Path, default=None)
    parser.add_argument("--skip-test-fixture-alignment", action="store_true")
    args = parser.parse_args()

    bridge_raw = read_json(args.data)
    fixture_hash_hex = bridge_raw["locking_tx_hash_hex"]
    drifted = False

    if args.check:
        if args.proof_export_bundle is not None:
            resolve_tx_snapshot_root(bridge_raw, args.proof_export_bundle)
        # The canonical locking-tx body (and therefore its hash) bakes in the
        # bridged asset policy and datum `bridge_id`, both of which equal the
        # bridge minting policy id from env. When that hash changes (e.g. the
        # minting validator was recompiled), the committed body/hash drift from
        # what the on-chain validator now reconstructs, so the fixture must be
        # refreshed. `check_bridge_fixture` only proves the helper matches the
        # data file, so detect the env drift explicitly here.
        canonical = derive_canonical_locking_tx(bridge_raw)
        if (
            _strip_0x(fixture_hash_hex) != _strip_0x(canonical["tx_hash_hex"])
            or _strip_0x(bridge_raw["locking_tx_body_cbor_hex"])
            != _strip_0x(canonical["body_cbor_hex"])
            or _strip_0x(bridge_raw["locking_tx_datum_cbor_hex"])
            != _strip_0x(canonical["datum_cbor_hex"])
        ):
            raise SystemExit(
                "Bridge zk fixture drifted from env policy hashes; "
                "run sync_bridge_zk_fixture.py --fix-drift to regenerate it"
            )
        sync_bridge_fixture_helper(args.data, args.output)
        check_bridge_fixture(args.output, args.data)
        maybe_check_fixture_alignment(
            skip_test_fixture_alignment=args.skip_test_fixture_alignment,
            data_path=args.data,
            bridge_fixture_path=args.output,
        )
        return 0

    if args.fix_drift:
        refresh_bridge_fixture(
            args.data,
            args.output,
            args.work_dir,
            args.user_address,
            skip_test_fixture_alignment=args.skip_test_fixture_alignment,
        )
        if args.proof_export_bundle is not None:
            print(
                "Bridge zk fixture refreshed; runtime bundle is expected to be rebuilt by the caller to match the updated fixture."
            )
        else:
            print(
                "Bridge zk fixture now treats locking_tx_hash_hex as the canonical Cardano tx hash."
            )
        return 0

    if args.regenerate:
        refresh_bridge_fixture(
            args.data,
            args.output,
            args.work_dir,
            args.user_address,
            skip_test_fixture_alignment=args.skip_test_fixture_alignment,
        )
        if args.proof_export_bundle is not None:
            print(
                "Bridge zk fixture regenerated; rebuild the runtime bundle if you need it aligned to the refreshed fixture."
            )
        maybe_check_fixture_alignment(
            skip_test_fixture_alignment=args.skip_test_fixture_alignment,
            data_path=args.data,
            bridge_fixture_path=args.output,
        )
        print(f"Bridge zk fixture regenerated at: {args.data}")
        print(f"Generated helper refreshed at: {args.output}")
        return 0

    write_bridge_fixture(args.output, args.data)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
