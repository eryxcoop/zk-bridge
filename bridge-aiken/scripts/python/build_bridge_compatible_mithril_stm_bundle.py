#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
from datetime import datetime
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import urlopen

from arg_builder_common import read_json, write_json
from stm_statement_digest import (
    build_statement_projection,
    sync_bridge_aiken_statement_hashes,
)
from tx_snapshot_root import (
    bridge_raw_tx_snapshot_root,
    normalize_midnight_fq_bytes32,
    require_matching_tx_snapshot_roots,
)


DATA_DIR = Path(__file__).resolve().parent.parent / "data"
DEFAULT_AGGREGATOR_ENDPOINT = (
    "https://aggregator.pre-release-preview.api.mithril.network/aggregator"
)


def ascii_hex(text: str) -> str:
    return "0x" + text.encode().hex()


def strip_0x(text: str) -> str:
    return text[2:] if text.startswith("0x") else text


def ensure_hex_bytes(text: str) -> str:
    return "0x" + strip_0x(text)


def fetch_json(url: str) -> dict | list:
    with urlopen(url) as response:
        return json.load(response)


def iso8601_to_unix_nanos_hex(value: str) -> str:
    if not value.endswith("Z"):
        raise ValueError(f"expected UTC timestamp ending in Z, got: {value}")
    main, fractional = value[:-1].split(".", 1)
    dt = datetime.fromisoformat(f"{main}+00:00")
    fractional = (fractional + "000000000")[:9]
    seconds = int(dt.timestamp())
    nanos = seconds * 1_000_000_000 + int(fractional)
    return f"0x{nanos:x}"


def normalize_live_metadata(certificate: dict) -> dict:
    metadata = certificate["metadata"]
    return {
        "network": metadata["network"],
        "protocol_version": metadata["version"],
        "initiated_at": iso8601_to_unix_nanos_hex(metadata["initiated_at"]),
        "sealed_at": iso8601_to_unix_nanos_hex(metadata["sealed_at"]),
    }


def metadata_is_synthetic(metadata: dict | None) -> bool:
    if not isinstance(metadata, dict):
        return True
    if metadata.get("network") == "poc":
        return True
    return metadata.get("initiated_at") in {"0x00", "0x01", "0x02", "0x03"}


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


def fetch_latest_certificate_for_artifact(
    aggregator_endpoint: str,
    artifact_path: str,
    target_epoch: int | str | None = None,
) -> dict:
    if artifact_path == "/artifact/cardano-stake-distributions":
        artifact = fetch_cardano_stake_distribution_artifact(
            aggregator_endpoint,
            target_epoch,
        )
        certificate_hash = artifact["certificate_hash"]
    else:
        artifacts = fetch_json(f"{aggregator_endpoint}{artifact_path}")
        if not isinstance(artifacts, list) or not artifacts:
            raise ValueError(
                f"aggregator did not return any artifacts for {artifact_path}"
            )
        certificate_hash = artifacts[0]["certificate_hash"]
    return fetch_json(f"{aggregator_endpoint}/certificate/{certificate_hash}")


def resolve_metadata(
    preferred_certificate: dict | None,
    fallback_live_certificate: dict,
) -> dict:
    metadata = preferred_certificate.get("metadata") if isinstance(preferred_certificate, dict) else None
    if not metadata_is_synthetic(metadata):
        return metadata
    return normalize_live_metadata(fallback_live_certificate)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("base_bundle", type=Path)
    parser.add_argument("output_bundle", type=Path)
    parser.add_argument("--sd-genesis-bundle", type=Path, default=None)
    parser.add_argument("--sd-standard-bundle", type=Path, default=None)
    parser.add_argument("--tx-snapshot-bundle", type=Path, default=None)
    parser.add_argument("--sd-genesis-proof-export", type=Path, default=None)
    parser.add_argument("--sd-standard-proof-export", type=Path, default=None)
    parser.add_argument("--tx-snapshot-proof-export", type=Path, default=None)
    parser.add_argument(
        "--phase1-template",
        type=Path,
        default=DATA_DIR / "phase1_args_raw.json",
    )
    parser.add_argument(
        "--phase2-template",
        type=Path,
        default=DATA_DIR / "phase2_args_raw.json",
    )
    parser.add_argument(
        "--genesis-fixture",
        type=Path,
        default=DATA_DIR / "mithril_stake_distribution_genesis.json",
    )
    parser.add_argument(
        "--standard-fixture",
        type=Path,
        default=DATA_DIR / "mithril_stake_distribution_standard.json",
    )
    parser.add_argument(
        "--aggregator-endpoint",
        default=os.environ.get(
            "MITHRIL_AGGREGATOR_ENDPOINT", DEFAULT_AGGREGATOR_ENDPOINT
        ),
    )
    return parser.parse_args()


def bridge_aiken_templates(
    bundle: dict,
    phase1_template_path: Path,
    phase2_template_path: Path,
    proof_export_path: Path | None = None,
) -> dict:
    if proof_export_path is not None:
        proof_export = read_json(proof_export_path)
        if "bridge_aiken" in proof_export:
            return proof_export["bridge_aiken"]
    if "bridge_aiken" in bundle:
        return bundle["bridge_aiken"]
    return {
        "phase1": read_json(phase1_template_path),
        "phase2": read_json(phase2_template_path),
    }


def build_parent_certificate(genesis: dict, signed_message: str | None = None) -> dict:
    return {
        "kind": "genesis",
        "hash": "0x" + genesis["hash"],
        "prev_hash": "0x",
        "epoch": genesis["epoch"],
        "metadata": {
            "network": genesis["network"],
            "protocol_version": genesis["protocol_version"],
            "initiated_at": "0x" + genesis["initiated_at"],
            "sealed_at": "0x" + genesis["sealed_at"],
        },
        "protocol_parameters": {
            "k": genesis["k"],
            "m": genesis["m"],
            "phi_f": "0x" + genesis["phi_f"],
        },
        "protocol_message": {
            "current_epoch_text": genesis["current_epoch_text"],
            "next_aggregate_verification_key_text": genesis[
                "next_aggregate_verification_key_text"
            ],
            "next_aggregate_verification_key_snark_text": genesis[
                "next_aggregate_verification_key_snark_text"
            ],
            "next_protocol_parameters_text": genesis["next_protocol_parameters_text"],
            "cardano_transactions_merkle_root_hex": None,
        },
        "signed_message": signed_message or ("0x" + genesis["signed_message_text"]),
        "aggregate_verification_key_text": genesis["aggregate_verification_key_text"],
        "aggregate_verification_key_snark_text": genesis[
            "aggregate_verification_key_snark_text"
        ],
        "signature": {
            "type": "genesis",
            "bytes_hex": "0x" + genesis["signature_text"],
        },
        "signed_entity": {
            "kind": "genesis",
            "epoch": None,
            "block_number": None,
        },
    }


def build_child_certificate(
    standard: dict,
    signed_message: str,
    metadata: dict,
) -> dict:
    return {
        "kind": "standard",
        "hash": "0x" + standard["hash"],
        "prev_hash": ascii_hex(standard["prev_hash_text"]),
        "epoch": standard["epoch"],
        "metadata": metadata,
        "protocol_parameters": {
            "k": standard["k"],
            "m": standard["m"],
            "phi_f": "0x" + standard["phi_f"],
        },
        "protocol_message": {
            "current_epoch_text": standard["current_epoch_text"],
            "next_aggregate_verification_key_text": standard[
                "next_aggregate_verification_key_text"
            ],
            "next_aggregate_verification_key_snark_text": standard[
                "next_aggregate_verification_key_snark_text"
            ],
            "next_protocol_parameters_text": standard["next_protocol_parameters_text"],
            "cardano_transactions_merkle_root_hex": None,
        },
        "signed_message": signed_message,
        "aggregate_verification_key_text": standard["aggregate_verification_key_text"],
        "aggregate_verification_key_snark_text": standard[
            "aggregate_verification_key_snark_text"
        ],
        # The bridge validators do not consume the full Mithril multisignature;
        # they only need the reduced chained fields plus signed_entity metadata.
        "signature": {
            "type": "multi",
            "bytes_hex": "0x",
        },
        "signed_entity": {
            "kind": "mithril_stake_distribution",
            "epoch": standard["signed_entity_epoch"],
            "block_number": None,
        },
    }


def build_tx_snapshot_certificate(
    standard_certificate: dict,
    bridge_raw: dict,
    signed_message: str,
    metadata: dict,
) -> dict:
    standard_hash = strip_0x(standard_certificate["hash"])
    standard_epoch = standard_certificate["epoch"]
    standard_protocol_parameters = standard_certificate["protocol_parameters"]
    standard_protocol_message = standard_certificate["protocol_message"]
    return {
        "kind": "standard",
        "hash": ascii_hex(bridge_raw["child_certificate_hash_text"]),
        "prev_hash": ascii_hex(standard_hash),
        "epoch": standard_epoch,
        "metadata": metadata,
        "protocol_parameters": {
            "k": standard_protocol_parameters["k"],
            "m": standard_protocol_parameters["m"],
            "phi_f": standard_protocol_parameters["phi_f"],
        },
        "protocol_message": {
            "current_epoch_text": standard_protocol_message["current_epoch_text"],
            "next_aggregate_verification_key_text": bridge_raw[
                "child_certificate_next_aggregate_verification_key_text"
            ],
            "next_aggregate_verification_key_snark_text": bridge_raw[
                "child_certificate_next_aggregate_verification_key_snark_text"
            ],
            "next_protocol_parameters_text": (
                "b01de82ca7e57c1bf2a56381ce265f378aeea5f1dde7f824b5ba42125c4adad2"
            ),
            "cardano_transactions_merkle_root_hex": strip_0x(signed_message),
        },
        "signed_message": signed_message,
        "aggregate_verification_key_text": standard_certificate[
            "aggregate_verification_key_text"
        ],
        "aggregate_verification_key_snark_text": standard_certificate[
            "aggregate_verification_key_snark_text"
        ],
        "signature": {
            "type": "multi",
            "bytes_hex": "0x",
        },
        "signed_entity": {
            "kind": "cardano_transactions",
            "epoch": standard_epoch,
            "block_number": None,
        },
    }


def build_proof_entry(
    proof_name: str,
    certificate: dict,
    bridge_aiken: dict,
) -> dict:
    proof_statement = ensure_hex_bytes(certificate["signed_message"])
    synced_bridge_aiken = sync_bridge_aiken_statement_hashes(bridge_aiken, proof_statement)
    return {
        "proof_name": proof_name,
        "statement": build_statement_projection(proof_statement),
        "bridge_aiken": synced_bridge_aiken,
        "proof_receipt": {
            "statement_hash": proof_statement,
            "source": "proof-specific-statement",
        },
        "certificate": certificate,
    }


def main() -> int:
    args = parse_args()
    bundle = read_json(args.base_bundle)
    sd_genesis_bundle = read_json(args.sd_genesis_bundle or args.base_bundle)
    sd_standard_bundle = read_json(args.sd_standard_bundle or args.base_bundle)
    tx_snapshot_bundle = read_json(args.tx_snapshot_bundle or args.base_bundle)
    genesis = read_json(args.genesis_fixture)
    standard = read_json(args.standard_fixture)
    bridge_raw = read_json(DATA_DIR / "bridge_mint_raw.json")

    statement = bundle["statement"]
    sd_genesis_statement = sd_genesis_bundle["statement"]
    sd_standard_statement = sd_standard_bundle["statement"]
    tx_snapshot_statement = tx_snapshot_bundle["statement"]
    sd_standard_source_certificate = sd_standard_bundle["certificates"]["child"]
    tx_snapshot_child_certificate = tx_snapshot_bundle["certificates"]["child"]
    live_sd_standard_certificate = fetch_latest_certificate_for_artifact(
        args.aggregator_endpoint,
        "/artifact/cardano-stake-distributions",
        standard["signed_entity_epoch"],
    )
    live_tx_snapshot_certificate = fetch_latest_certificate_for_artifact(
        args.aggregator_endpoint,
        "/artifact/cardano-transactions",
    )
    bridge_aiken = bridge_aiken_templates(
        bundle,
        args.phase1_template,
        args.phase2_template,
    )
    sd_genesis_bridge_aiken = bridge_aiken_templates(
        sd_genesis_bundle,
        args.phase1_template,
        args.phase2_template,
        args.sd_genesis_proof_export,
    )
    sd_standard_bridge_aiken = bridge_aiken_templates(
        sd_standard_bundle,
        args.phase1_template,
        args.phase2_template,
        args.sd_standard_proof_export,
    )
    tx_snapshot_bridge_aiken = bridge_aiken_templates(
        tx_snapshot_bundle,
        args.phase1_template,
        args.phase2_template,
        args.tx_snapshot_proof_export,
    )
    signed_message = statement["public_input_2_signed_message"]
    parent_certificate = build_parent_certificate(
        genesis,
        ensure_hex_bytes(sd_genesis_statement["public_input_2_signed_message"]),
    )
    standard_certificate = build_child_certificate(
        standard,
        signed_message,
        resolve_metadata(sd_standard_source_certificate, live_sd_standard_certificate),
    )
    proof_standard_certificate = build_child_certificate(
        standard,
        ensure_hex_bytes(sd_standard_statement["public_input_2_signed_message"]),
        resolve_metadata(sd_standard_source_certificate, live_sd_standard_certificate),
    )
    require_matching_tx_snapshot_roots(
        normalize_midnight_fq_bytes32(bridge_raw_tx_snapshot_root(bridge_raw)),
        ensure_hex_bytes(tx_snapshot_child_certificate["signed_message"]),
        expected_label="normalized bridge fixture tx snapshot root",
        actual_label="tx-snapshot bundle child signed_message",
    )
    tx_snapshot_certificate = build_tx_snapshot_certificate(
        proof_standard_certificate,
        bridge_raw,
        ensure_hex_bytes(tx_snapshot_statement["public_input_2_signed_message"]),
        resolve_metadata(tx_snapshot_child_certificate, live_tx_snapshot_certificate),
    )

    bundle["source"] = {
        "source_id": "bridge-aiken-compatible-fixture",
        "source_kind": "fixture",
        "network": genesis["network"],
        "generated_at": None,
        "notes": (
            "Synthetic STM witness plus bridge-aiken Mithril certificate fixtures "
            "aligned to the same proof statement"
        ),
    }
    # Emit the provenance header shared with the proof-export schema, so the
    # bridge flows can read `source_bundle.source_id` to identify and log which
    # bundle is being consumed.
    bundle["source_bundle"] = {
        "bundle_schema_version": bundle.get("schema_version", "1.0.0"),
        "bundle_kind": bundle.get("bundle_kind", "mithril_stm_bundle"),
        "source_id": bundle["source"]["source_id"],
    }
    bundle["statement"] = {
        **statement,
        **build_statement_projection(
            signed_message,
            public_input_1=statement["public_input_1_merkle_root"],
        ),
    }
    bundle["bridge_aiken"] = sync_bridge_aiken_statement_hashes(
        bridge_aiken,
        signed_message,
    )
    bundle["certificates"] = {
        "parent": parent_certificate,
        "child": standard_certificate,
    }
    bundle["proofs"] = {
        "stake_distribution_genesis": build_proof_entry(
            "stake_distribution_genesis",
            parent_certificate,
            sd_genesis_bridge_aiken,
        ),
        "stake_distribution_standard": build_proof_entry(
            "stake_distribution_standard",
            proof_standard_certificate,
            sd_standard_bridge_aiken,
        ),
        "cardano_transactions": build_proof_entry(
            "cardano_transactions",
            tx_snapshot_certificate,
            tx_snapshot_bridge_aiken,
        ),
    }

    write_json(args.output_bundle, bundle)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
