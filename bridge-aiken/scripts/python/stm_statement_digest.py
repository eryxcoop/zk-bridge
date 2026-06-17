from __future__ import annotations

from zk_contract import (
    canonical_statement_hash,
    certificate_signed_message,
    require_certificate_matches_statement_hash,
    required_child,
)


def sync_bridge_aiken_statement_hashes(bridge_aiken: dict, statement_hash: str) -> dict:
    phase1 = dict(bridge_aiken["phase1"])
    phase2 = dict(bridge_aiken["phase2"])

    if "public_input_2" in phase1:
        phase1["public_input_2"] = statement_hash
    if "statement_hash_value" in phase1:
        phase1["statement_hash_value"] = statement_hash
    if "proof_receipt_statement_hash" in phase2:
        phase2["proof_receipt_statement_hash"] = statement_hash

    return {
        "phase1": phase1,
        "phase2": phase2,
    }


def build_statement_projection(statement_hash: str, public_input_1: str | None = None) -> dict:
    projection = {
        "statement_hash": statement_hash,
        "public_input_2": statement_hash,
    }
    if public_input_1 is not None:
        projection["public_input_1"] = public_input_1
    return projection
