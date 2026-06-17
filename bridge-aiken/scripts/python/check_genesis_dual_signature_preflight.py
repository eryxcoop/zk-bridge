#!/usr/bin/env python3

import argparse
import re
from pathlib import Path

from arg_builder_common import read_json


ROOT_DIR = Path(__file__).resolve().parent.parent.parent
DATA_DIR = ROOT_DIR / "scripts" / "data"
ENV_DEFAULT_PATH = ROOT_DIR / "env" / "default.ak"
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--genesis-json",
        type=Path,
        default=DATA_DIR / "mithril_stake_distribution_genesis.json",
    )
    parser.add_argument(
        "--dual-fixture-json",
        type=Path,
        default=DATA_DIR / "jubjub_schnorr_preview_genesis_raw.json",
    )
    return parser.parse_args()


def require_hex_32(label: str, value: str) -> bytes:
    if not re.fullmatch(r"[0-9a-f]{64}", value):
        raise SystemExit(f"{label} must be 64 lowercase hex chars, got: {value!r}")
    return bytes.fromhex(value)


def parse_env_int(name: str) -> int:
    pattern = re.compile(rf"pub const {re.escape(name)}:\s*Int\s*=\s*([0-9]+)")
    text = ENV_DEFAULT_PATH.read_text()
    match = pattern.search(text)
    if match is None:
        raise SystemExit(f"could not find Int env constant {name!r} in {ENV_DEFAULT_PATH}")
    return int(match.group(1))


def main() -> int:
    args = parse_args()
    genesis = read_json(args.genesis_json)
    dual = read_json(args.dual_fixture_json)

    signed_message_bytes = require_hex_32(
        "genesis.signed_message_text", genesis["signed_message_text"]
    )
    expected_digest_hi = int.from_bytes(signed_message_bytes[:16], "big")
    expected_digest_low = int.from_bytes(signed_message_bytes[16:], "big")
    actual_digest_hi = int(dual["digest_hi"])
    actual_digest_low = int(dual["digest_low"])
    if actual_digest_hi != expected_digest_hi:
        raise SystemExit(
            "dual genesis digest_hi drifted from the preview genesis signed_message: "
            f"expected {expected_digest_hi}, got {actual_digest_hi}"
        )
    if actual_digest_low != expected_digest_low:
        raise SystemExit(
            "dual genesis digest_low drifted from the preview genesis signed_message: "
            f"expected {expected_digest_low}, got {actual_digest_low}"
        )

    expected_vk_u = parse_env_int("genesis_schnorr_verification_key_u")
    expected_vk_v = parse_env_int("genesis_schnorr_verification_key_v")
    actual_vk_u = int(dual["verification_key_u"])
    actual_vk_v = int(dual["verification_key_v"])
    if actual_vk_u != expected_vk_u:
        raise SystemExit(
            f"dual genesis verification_key_u drifted: expected {expected_vk_u}, got {actual_vk_u}"
        )
    if actual_vk_v != expected_vk_v:
        raise SystemExit(
            f"dual genesis verification_key_v drifted: expected {expected_vk_v}, got {actual_vk_v}"
        )

    if dual.get("curve") != "bls12381":
        raise SystemExit(f"expected curve=bls12381, got {dual.get('curve')!r}")
    if dual.get("protocol") != "groth16":
        raise SystemExit(f"expected protocol=groth16, got {dual.get('protocol')!r}")
    if int(dual.get("public_inputs", 0)) != 6:
        raise SystemExit(f"expected 6 public inputs, got {dual.get('public_inputs')!r}")
    if dual.get("verified") is not True:
        raise SystemExit("expected dual genesis fixture to be marked verified=true")

    packed = dual.get("packed_public_inputs")
    if not isinstance(packed, dict):
        raise SystemExit("missing packed_public_inputs in dual genesis fixture")
    for key in (
        "digest_hi",
        "digest_low",
        "verification_key_u",
        "verification_key_v",
        "signature_response",
        "signature_challenge",
    ):
        if str(packed.get(key)) != str(dual.get(key)):
            raise SystemExit(
                f"packed_public_inputs.{key} drifted from top-level value: "
                f"{packed.get(key)!r} vs {dual.get(key)!r}"
            )

    proof = dual.get("jubjub_schnorr_proof")
    if not isinstance(proof, dict):
        raise SystemExit("missing jubjub_schnorr_proof in dual genesis fixture")
    for key in ("piA", "piB", "piC"):
        value = proof.get(key)
        if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]+", value):
            raise SystemExit(f"expected lowercase hex proof field for {key}, got {value!r}")

    print(f"genesis signed_message: {genesis['signed_message_text']}")
    print(f"expected digest_hi:     {expected_digest_hi}")
    print(f"expected digest_low:    {expected_digest_low}")
    print(f"dual fixture path:      {args.dual_fixture_json}")
    print("dual genesis preflight JSON checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
