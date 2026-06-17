#!/usr/bin/env python3

import argparse
from pathlib import Path

from arg_builder_common import as_bytes_hex, ascii_bytes_hex, read_json, write_json


ROOT_DIR = Path(__file__).resolve().parent.parent.parent
DATA_DIR = ROOT_DIR / "scripts" / "data"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("out", type=Path)
    parser.add_argument("user_address")
    parser.add_argument("stake_distribution_output_lovelace", type=int)
    parser.add_argument("source_utxo")
    parser.add_argument("collateral_utxo")
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


def main() -> int:
    args = parse_args()
    genesis = read_json(args.genesis_json)
    dual = read_json(args.dual_fixture_json)

    schnorr_signature_hex = (
        int(dual["signature_response"]).to_bytes(32, "little").hex()
        + int(dual["signature_challenge"]).to_bytes(32, "little").hex()
    )
    dual_verification_key_u_ascii = str(dual["verification_key_u"])
    dual_verification_key_v_ascii = str(dual["verification_key_v"])
    dual_signature_response_ascii = str(dual["signature_response"])
    dual_signature_challenge_ascii = str(dual["signature_challenge"])

    payload = {
        "user": args.user_address,
        "certificate_hash": as_bytes_hex(genesis["hash"]),
        "certificate_prev_hash": ascii_bytes_hex(genesis["prev_hash_text"]),
        "certificate_epoch": genesis["epoch"],
        "certificate_network": ascii_bytes_hex(genesis["network"]),
        "certificate_protocol_version": ascii_bytes_hex(genesis["protocol_version"]),
        "certificate_protocol_parameters_k": genesis["k"],
        "certificate_protocol_parameters_m": genesis["m"],
        "certificate_protocol_parameters_phi_f": as_bytes_hex(genesis["phi_f"]),
        "certificate_initiated_at": as_bytes_hex(genesis["initiated_at"]),
        "certificate_sealed_at": as_bytes_hex(genesis["sealed_at"]),
        "certificate_protocol_message_next_aggregate_verification_key": ascii_bytes_hex(
            genesis["next_aggregate_verification_key_text"]
        ),
        "certificate_protocol_message_next_aggregate_verification_key_snark": ascii_bytes_hex(
            genesis["next_aggregate_verification_key_snark_text"]
        ),
        "certificate_protocol_message_next_protocol_parameters": ascii_bytes_hex(
            genesis["next_protocol_parameters_text"]
        ),
        "certificate_protocol_message_current_epoch": ascii_bytes_hex(
            genesis["current_epoch_text"]
        ),
        "certificate_signed_message": ascii_bytes_hex(genesis["signed_message_text"]),
        "certificate_aggregate_verification_key": ascii_bytes_hex(
            genesis["aggregate_verification_key_text"]
        ),
        "certificate_aggregate_verification_key_snark": ascii_bytes_hex(
            genesis["aggregate_verification_key_snark_text"]
        ),
        "certificate_ed25519_signature": ascii_bytes_hex(genesis["signature_text"]),
        "certificate_schnorr_signature": ascii_bytes_hex(schnorr_signature_hex),
        "jubjub_schnorr_proof_pi_a": as_bytes_hex(dual["jubjub_schnorr_proof"]["piA"]),
        "jubjub_schnorr_proof_pi_b": as_bytes_hex(dual["jubjub_schnorr_proof"]["piB"]),
        "jubjub_schnorr_proof_pi_c": as_bytes_hex(dual["jubjub_schnorr_proof"]["piC"]),
        "dual_jubjub_schnorr_verification_key_u": ascii_bytes_hex(
            dual_verification_key_u_ascii
        ),
        "dual_jubjub_schnorr_verification_key_v": ascii_bytes_hex(
            dual_verification_key_v_ascii
        ),
        "dual_jubjub_schnorr_signature_response": ascii_bytes_hex(
            dual_signature_response_ascii
        ),
        "dual_jubjub_schnorr_signature_challenge": ascii_bytes_hex(
            dual_signature_challenge_ascii
        ),
        "stake_distribution_output_lovelace": args.stake_distribution_output_lovelace,
        "source_utxo": args.source_utxo,
        "collateral_utxo": args.collateral_utxo,
    }

    write_json(args.out, payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
