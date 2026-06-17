#!/usr/bin/env python3

import argparse
import json
import os
from decimal import Decimal, ROUND_DOWN
from datetime import datetime
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import urlopen

from arg_builder_common import as_bytes_hex, ascii_bytes_hex, read_json, write_json
from mithril_stm_proof_export_bundle_certificates import (
    certificate_metadata,
    certificate_protocol_message,
    certificate_protocol_parameters,
    ensure_ascii_hex,
    ensure_bytes_hex,
    load_sd_standard_proof,
    prev_hash_to_certificate_bytes,
    stake_distribution_signed_entity_fields,
)
from stm_statement_digest import require_certificate_matches_statement_hash

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
DEFAULT_AGGREGATOR_ENDPOINT = (
    "https://aggregator.pre-release-preview.api.mithril.network/aggregator"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("genesis_out", type=Path)
    parser.add_argument("standard_out", type=Path)
    parser.add_argument("user_address")
    parser.add_argument("sd_standard_receipt_statement_hash")
    parser.add_argument("stake_distribution_output_lovelace", type=int)
    parser.add_argument("sd_standard_receipt_utxo")
    parser.add_argument("stake_distribution_source_utxo")
    parser.add_argument("--proof-export-bundle", type=Path, default=None)
    parser.add_argument(
        "--aggregator-endpoint",
        default=os.environ.get(
            "MITHRIL_AGGREGATOR_ENDPOINT", DEFAULT_AGGREGATOR_ENDPOINT
        ),
    )
    return parser.parse_args()


def fetch_json(url: str) -> dict | list:
    with urlopen(url) as response:
        return json.load(response)


def phi_f_to_hex(value: str | float) -> str:
    normalized = Decimal(str(value))
    fixed = int(
        (normalized * (1 << 24)).to_integral_value(rounding=ROUND_DOWN)
    )
    return format(fixed, "08x")


def iso8601_to_unix_nanos_hex(value: str) -> str:
    if not value.endswith("Z"):
        raise ValueError(f"expected UTC timestamp ending in Z, got: {value}")
    main, fractional = value[:-1].split(".", 1)
    dt = datetime.fromisoformat(f"{main}+00:00")
    fractional = (fractional + "000000000")[:9]
    seconds = int(dt.timestamp())
    nanos = seconds * 1_000_000_000 + int(fractional)
    return format(nanos, "x")


def snark_avk_text_for_epoch(epoch: int) -> str:
    return f"snark-avk-{epoch}"


def live_previous_hash(certificate: dict) -> str:
    previous_hash = certificate.get("previous_hash")
    if previous_hash is not None:
        return previous_hash
    prev_hash = certificate.get("prev_hash")
    if prev_hash is not None:
        return prev_hash
    return ""


def normalize_live_signed_entity(certificate: dict) -> dict:
    payload = certificate.get("signed_entity_type")
    if not isinstance(payload, dict) or not payload:
        return {"kind": "genesis", "epoch": None}

    kind, value = next(iter(payload.items()))
    if "StakeDistribution" in kind:
        epoch = value if isinstance(value, int) else None
        return {"kind": "mithril_stake_distribution", "epoch": epoch}

    return {"kind": kind, "epoch": None}


def normalize_live_certificate(certificate: dict) -> dict:
    metadata = certificate["metadata"]
    parameters = certificate.get("protocol_parameters") or metadata["parameters"]
    message_parts = certificate["protocol_message"]["message_parts"]
    current_epoch = int(message_parts["current_epoch"])

    signature_hex = certificate.get("genesis_signature") or certificate.get(
        "multi_signature"
    )

    normalized = {
        "hash": certificate["hash"],
        "prev_hash": live_previous_hash(certificate),
        "epoch": certificate["epoch"],
        "metadata": {
            "network": metadata["network"],
            "protocol_version": metadata["version"],
            "initiated_at": iso8601_to_unix_nanos_hex(metadata["initiated_at"]),
            "sealed_at": iso8601_to_unix_nanos_hex(metadata["sealed_at"]),
        },
        "protocol_parameters": {
            "k": parameters["k"],
            "m": parameters["m"],
            "phi_f": phi_f_to_hex(parameters["phi_f"]),
        },
        "protocol_message": {
            "next_aggregate_verification_key_text": message_parts[
                "next_aggregate_verification_key"
            ],
            "next_aggregate_verification_key_snark_text": snark_avk_text_for_epoch(
                current_epoch + 1
            ),
            "next_protocol_parameters_text": message_parts["next_protocol_parameters"],
            "current_epoch_text": message_parts["current_epoch"],
        },
        "signed_message": certificate["signed_message"],
        "aggregate_verification_key_text": certificate[
            "aggregate_verification_key"
        ],
        "aggregate_verification_key_snark_text": snark_avk_text_for_epoch(
            current_epoch
        ),
        "signature": {"bytes_hex": signature_hex or ""},
        "signed_entity": normalize_live_signed_entity(certificate),
    }

    cardano_transactions_merkle_root = message_parts.get(
        "cardano_transactions_merkle_root"
    )
    if cardano_transactions_merkle_root is not None:
        normalized["protocol_message"]["cardano_transactions_merkle_root_hex"] = (
            cardano_transactions_merkle_root
        )

    return normalized


def fetch_cardano_stake_distribution_artifact(
    aggregator_endpoint: str,
    target_epoch: int | str | None = None,
) -> dict:
    candidate_paths: list[str] = []
    if target_epoch is not None:
        candidate_paths.append(
            f"/artifact/cardano-stake-distribution/epoch/{target_epoch}"
        )
    candidate_paths.extend(
        [
            "/artifact/cardano-stake-distribution/epoch/latest",
            "/artifact/cardano-stake-distributions",
        ]
    )

    last_error: Exception | None = None
    for path in candidate_paths:
        try:
            payload = fetch_json(f"{aggregator_endpoint}{path}")
        except HTTPError as exc:
            last_error = exc
            if exc.code == 404:
                continue
            raise

        if isinstance(payload, dict):
            return payload
        if isinstance(payload, list) and payload:
            return payload[0]

    if last_error is not None:
        raise last_error
    raise ValueError(
        "aggregator did not return any cardano stake distribution artifacts"
    )


def fetch_live_genesis_and_standard_certificates(
    aggregator_endpoint: str,
    target_epoch: int | str | None = None,
) -> tuple[dict, dict]:
    genesis_certificate = fetch_json(f"{aggregator_endpoint}/certificate/genesis")
    latest_artifact = fetch_cardano_stake_distribution_artifact(
        aggregator_endpoint,
        target_epoch,
    )
    standard_certificate = fetch_json(
        f"{aggregator_endpoint}/certificate/{latest_artifact['certificate_hash']}"
    )

    return (
        normalize_live_certificate(genesis_certificate),
        normalize_live_certificate(standard_certificate),
    )


def build_sd_genesis_args_from_certificate(
    certificate: dict,
    user_address: str,
    stake_distribution_output_lovelace: int,
    stake_distribution_source_utxo: str,
    stake_distribution_collateral_utxo: str,
) -> dict:
    jubjub = read_json(DATA_DIR / "jubjub_schnorr_preview_genesis_raw.json")
    metadata = certificate_metadata(certificate)
    protocol_parameters = certificate_protocol_parameters(certificate)
    protocol_message = certificate_protocol_message(certificate)
    schnorr_signature_hex = (
        int(jubjub["signature_response"]).to_bytes(32, "little").hex()
        + int(jubjub["signature_challenge"]).to_bytes(32, "little").hex()
    )
    dual_verification_key_u_ascii = str(jubjub["verification_key_u"])
    dual_verification_key_v_ascii = str(jubjub["verification_key_v"])
    dual_signature_response_ascii = str(jubjub["signature_response"])
    dual_signature_challenge_ascii = str(jubjub["signature_challenge"])
    return {
        "user": user_address,
        "certificate_hash": ensure_bytes_hex(certificate["hash"]),
        "certificate_prev_hash": ensure_bytes_hex(certificate["prev_hash"]),
        "certificate_epoch": certificate["epoch"],
        "certificate_network": ensure_ascii_hex(metadata["network"]),
        "certificate_protocol_version": ensure_ascii_hex(
            metadata["protocol_version"]
        ),
        "certificate_protocol_parameters_k": protocol_parameters["k"],
        "certificate_protocol_parameters_m": protocol_parameters["m"],
        "certificate_protocol_parameters_phi_f": ensure_bytes_hex(
            protocol_parameters["phi_f"]
        ),
        "certificate_initiated_at": ensure_bytes_hex(metadata["initiated_at"]),
        "certificate_sealed_at": ensure_bytes_hex(metadata["sealed_at"]),
        "certificate_protocol_message_next_aggregate_verification_key": ensure_ascii_hex(
            protocol_message["next_aggregate_verification_key_text"]
        ),
        "certificate_protocol_message_next_aggregate_verification_key_snark": ensure_ascii_hex(
            protocol_message["next_aggregate_verification_key_snark_text"]
        ),
        "certificate_protocol_message_next_protocol_parameters": ensure_ascii_hex(
            protocol_message["next_protocol_parameters_text"]
        ),
        "certificate_protocol_message_current_epoch": ensure_ascii_hex(
            protocol_message["current_epoch_text"]
        ),
        "certificate_signed_message": ensure_ascii_hex(certificate["signed_message"]),
        "certificate_aggregate_verification_key": ensure_ascii_hex(
            certificate["aggregate_verification_key_text"]
        ),
        "certificate_aggregate_verification_key_snark": ensure_ascii_hex(
            certificate["aggregate_verification_key_snark_text"]
        ),
        "certificate_signature": ensure_ascii_hex(certificate["signature"]["bytes_hex"]),
        "certificate_ed25519_signature": ensure_ascii_hex(
            certificate["signature"]["bytes_hex"]
        ),
        "certificate_schnorr_signature": ensure_ascii_hex(schnorr_signature_hex),
        "jubjub_schnorr_proof_pi_a": as_bytes_hex(
            jubjub["jubjub_schnorr_proof"]["piA"]
        ),
        "jubjub_schnorr_proof_pi_b": as_bytes_hex(
            jubjub["jubjub_schnorr_proof"]["piB"]
        ),
        "jubjub_schnorr_proof_pi_c": as_bytes_hex(
            jubjub["jubjub_schnorr_proof"]["piC"]
        ),
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
        "stake_distribution_output_lovelace": stake_distribution_output_lovelace,
        "source_utxo": stake_distribution_source_utxo,
        "collateral_utxo": stake_distribution_collateral_utxo,
    }


def build_sd_standard_args_from_certificate(
    certificate: dict,
    user_address: str,
    sd_standard_statement_hash: str,
    stake_distribution_output_lovelace: int,
    sd_standard_receipt_utxo: str,
    stake_distribution_source_utxo: str,
    stake_distribution_collateral_utxo: str,
) -> dict:
    protocol_parameters = certificate_protocol_parameters(certificate)
    protocol_message = certificate_protocol_message(certificate)
    signed_entity_is_stake_distribution, signed_entity_epoch = (
        stake_distribution_signed_entity_fields(certificate)
    )
    certificate_signed_message = require_certificate_matches_statement_hash(
        {"signed_message": ensure_bytes_hex(certificate["signed_message"])},
        "stake_distribution_standard.certificate",
        sd_standard_statement_hash,
        "stake_distribution_standard.statement",
    )

    cardano_transactions_merkle_root = protocol_message.get(
        "cardano_transactions_merkle_root_hex"
    )
    return {
        "user": user_address,
        "certificate_hash": ensure_bytes_hex(certificate["hash"]),
        "certificate_prev_hash": prev_hash_to_certificate_bytes(
            certificate["prev_hash"]
        ),
        "certificate_epoch": certificate["epoch"],
        "certificate_protocol_parameters_k": protocol_parameters["k"],
        "certificate_protocol_parameters_m": protocol_parameters["m"],
        "certificate_protocol_parameters_phi_f": ensure_bytes_hex(
            protocol_parameters["phi_f"]
        ),
        "certificate_protocol_message_next_aggregate_verification_key": ensure_ascii_hex(
            protocol_message["next_aggregate_verification_key_text"]
        ),
        "certificate_protocol_message_next_aggregate_verification_key_snark": ensure_ascii_hex(
            protocol_message["next_aggregate_verification_key_snark_text"]
        ),
        "certificate_protocol_message_next_protocol_parameters": ensure_ascii_hex(
            protocol_message["next_protocol_parameters_text"]
        ),
        "certificate_protocol_message_current_epoch": ensure_ascii_hex(
            protocol_message["current_epoch_text"]
        ),
        "certificate_protocol_message_cardano_transactions_merkle_root": (
            ensure_bytes_hex(cardano_transactions_merkle_root)
            if cardano_transactions_merkle_root
            else "0x"
        ),
        "certificate_signed_message": certificate_signed_message,
        "certificate_aggregate_verification_key": ensure_ascii_hex(
            certificate["aggregate_verification_key_text"]
        ),
        "certificate_aggregate_verification_key_snark": ensure_ascii_hex(
            certificate["aggregate_verification_key_snark_text"]
        ),
        "certificate_signed_entity_is_stake_distribution": signed_entity_is_stake_distribution,
        "certificate_signed_entity_epoch": signed_entity_epoch,
        "parent_certificate_lovelace": stake_distribution_output_lovelace,
        "parent_certificate_utxo": "__STAKE_DISTRIBUTION_GENESIS_HASH__#0",
        "sd_standard_receipt_utxo": sd_standard_receipt_utxo,
        "source_utxo": stake_distribution_source_utxo,
        "collateral_utxo": stake_distribution_collateral_utxo,
    }


def build_sd_standard_args_from_live_template(
    certificate: dict,
    user_address: str,
    sd_standard_statement_hash: str,
    stake_distribution_output_lovelace: int,
    sd_standard_receipt_utxo: str,
    stake_distribution_source_utxo: str,
    stake_distribution_collateral_utxo: str,
) -> dict:
    protocol_parameters = certificate_protocol_parameters(certificate)
    protocol_message = certificate_protocol_message(certificate)
    signed_entity_is_stake_distribution, signed_entity_epoch = (
        stake_distribution_signed_entity_fields(certificate)
    )
    cardano_transactions_merkle_root = protocol_message.get(
        "cardano_transactions_merkle_root_hex"
    )

    return {
        "user": user_address,
        "certificate_hash": ensure_bytes_hex(certificate["hash"]),
        "certificate_prev_hash": prev_hash_to_certificate_bytes(
            certificate["prev_hash"]
        ),
        "certificate_epoch": certificate["epoch"],
        "certificate_protocol_parameters_k": protocol_parameters["k"],
        "certificate_protocol_parameters_m": protocol_parameters["m"],
        "certificate_protocol_parameters_phi_f": ensure_bytes_hex(
            protocol_parameters["phi_f"]
        ),
        "certificate_protocol_message_next_aggregate_verification_key": ensure_ascii_hex(
            protocol_message["next_aggregate_verification_key_text"]
        ),
        "certificate_protocol_message_next_aggregate_verification_key_snark": ensure_ascii_hex(
            protocol_message["next_aggregate_verification_key_snark_text"]
        ),
        "certificate_protocol_message_next_protocol_parameters": ensure_ascii_hex(
            protocol_message["next_protocol_parameters_text"]
        ),
        "certificate_protocol_message_current_epoch": ensure_ascii_hex(
            protocol_message["current_epoch_text"]
        ),
        "certificate_protocol_message_cardano_transactions_merkle_root": (
            ensure_bytes_hex(cardano_transactions_merkle_root)
            if cardano_transactions_merkle_root
            else "0x"
        ),
        "certificate_signed_message": sd_standard_statement_hash,
        "certificate_aggregate_verification_key": ensure_ascii_hex(
            certificate["aggregate_verification_key_text"]
        ),
        "certificate_aggregate_verification_key_snark": ensure_ascii_hex(
            certificate["aggregate_verification_key_snark_text"]
        ),
        "certificate_signed_entity_is_stake_distribution": signed_entity_is_stake_distribution,
        "certificate_signed_entity_epoch": signed_entity_epoch,
        "parent_certificate_lovelace": stake_distribution_output_lovelace,
        "parent_certificate_utxo": "__STAKE_DISTRIBUTION_GENESIS_HASH__#0",
        "sd_standard_receipt_utxo": sd_standard_receipt_utxo,
        "source_utxo": stake_distribution_source_utxo,
        "collateral_utxo": stake_distribution_collateral_utxo,
    }


def main() -> int:
    args = parse_args()
    genesis_out = args.genesis_out
    standard_out = args.standard_out
    user_address = args.user_address
    sd_standard_statement_hash = args.sd_standard_receipt_statement_hash
    stake_distribution_output_lovelace = args.stake_distribution_output_lovelace
    sd_standard_receipt_utxo = args.sd_standard_receipt_utxo
    stake_distribution_source_utxo = args.stake_distribution_source_utxo
    stake_distribution_collateral_utxo = (
        "0000000000000000000000000000000000000000000000000000000000000000#0"
    )
    live_genesis_certificate = None
    live_standard_certificate = None

    if args.proof_export_bundle is not None:
        sd_standard_certificate = load_sd_standard_proof(args.proof_export_bundle)
        standard_args = build_sd_standard_args_from_certificate(
            sd_standard_certificate,
            user_address,
            sd_standard_statement_hash,
            stake_distribution_output_lovelace,
            sd_standard_receipt_utxo,
            stake_distribution_source_utxo,
            stake_distribution_collateral_utxo,
        )
    else:
        live_genesis_certificate, live_standard_certificate = (
            fetch_live_genesis_and_standard_certificates(args.aggregator_endpoint)
        )
        standard_args = build_sd_standard_args_from_live_template(
            live_standard_certificate,
            user_address,
            sd_standard_statement_hash,
            stake_distribution_output_lovelace,
            sd_standard_receipt_utxo,
            stake_distribution_source_utxo,
            stake_distribution_collateral_utxo,
        )

    if live_genesis_certificate is None:
        live_genesis_certificate, _ = fetch_live_genesis_and_standard_certificates(
            args.aggregator_endpoint
        )

    genesis_args = build_sd_genesis_args_from_certificate(
        live_genesis_certificate,
        user_address,
        stake_distribution_output_lovelace,
        stake_distribution_source_utxo,
        stake_distribution_collateral_utxo,
    )

    write_json(genesis_out, genesis_args)
    write_json(standard_out, standard_args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
