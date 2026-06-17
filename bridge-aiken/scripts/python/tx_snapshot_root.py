#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path

from arg_builder_common import read_json
from mithril_stm_proof_export_bundle_certificates import load_tx_snapshot_proof
from zk_contract import (
    ensure_0x,
    require_certificate_matches_tx_snapshot_root as require_certificate_matches_tx_snapshot_root_contract,
    require_matching_hex_values as require_matching_hex_values_contract,
    tx_snapshot_certificate_root as tx_snapshot_certificate_root_contract,
)

MIDNIGHT_FQ_MODULUS = int(
    "73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001",
    16,
)


def strip_0x(value: str) -> str:
    return value[2:] if value.startswith("0x") else value


def bridge_raw_tx_snapshot_root(bridge_raw: dict) -> str:
    return ensure_0x(
        bridge_raw["tx_snapshot_certificate_protocol_message_cardano_transactions_merkle_root_text"]
    )


def normalize_midnight_fq_bytes32(value: str) -> str:
    raw = bytes.fromhex(strip_0x(value))
    normalized = int.from_bytes(raw, "little") % MIDNIGHT_FQ_MODULUS
    return "0x" + normalized.to_bytes(32, "little").hex()


def tx_snapshot_certificate_root(certificate: dict) -> str:
    return tx_snapshot_certificate_root_contract(certificate, "tx snapshot certificate")


def validate_tx_snapshot_certificate(certificate: dict, context: str) -> str:
    return require_certificate_matches_tx_snapshot_root_contract(certificate, context)


def tx_snapshot_root(proof_export_bundle_path: Path) -> str:
    certificate = load_tx_snapshot_proof(proof_export_bundle_path)
    return validate_tx_snapshot_certificate(
        certificate,
        "proofs.cardano_transactions.certificate",
    )


def require_matching_tx_snapshot_roots(
    expected_root: str,
    actual_root: str,
    *,
    expected_label: str,
    actual_label: str,
) -> str:
    return require_matching_hex_values_contract(
        expected_root,
        actual_root,
        expected_label=expected_label,
        actual_label=actual_label,
    )


def resolve_tx_snapshot_root(
    bridge_raw: dict,
    proof_export_bundle_path: Path | None,
) -> str:
    bridge_root = bridge_raw_tx_snapshot_root(bridge_raw)
    if proof_export_bundle_path is None:
        return bridge_root

    root = tx_snapshot_root(proof_export_bundle_path)
    return require_matching_tx_snapshot_roots(
        root,
        normalize_midnight_fq_bytes32(bridge_root),
        expected_label="tx snapshot root",
        actual_label="normalized bridge fixture tx snapshot root",
    )
