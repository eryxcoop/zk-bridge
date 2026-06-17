from __future__ import annotations


def strip_0x(value: str) -> str:
    return value[2:] if value.startswith("0x") else value


def ensure_0x(value: str) -> str:
    return value if value.startswith("0x") else f"0x{value}"


def required_child(payload: dict, field: str, context: str):
    if field not in payload:
        raise ValueError(f"missing {context}.{field}")
    return payload[field]


def packed_digest_halves(raw_hex: str) -> tuple[str, str]:
    value = int(strip_0x(raw_hex), 16)
    hi = value >> 128
    lo = value & ((1 << 128) - 1)
    return str(hi), str(lo)


def canonical_statement_hash(statement: dict, context: str) -> str:
    statement_hash = required_child(statement, "statement_hash", context)
    public_input_2 = required_child(statement, "public_input_2", context)
    if statement_hash != public_input_2:
        raise ValueError(
            f"{context}.statement_hash must equal {context}.public_input_2"
        )
    return statement_hash


def certificate_signed_message(certificate: dict, context: str) -> str:
    return required_child(certificate, "signed_message", context)


def require_certificate_matches_statement_hash(
    certificate: dict,
    certificate_context: str,
    statement_hash: str,
    statement_context: str,
) -> str:
    signed_message = certificate_signed_message(certificate, certificate_context)
    if signed_message != statement_hash:
        raise ValueError(
            f"{certificate_context}.signed_message must equal {statement_context}.statement_hash"
        )
    return signed_message


def tx_snapshot_certificate_root(certificate: dict, context: str) -> str:
    protocol_message = certificate.get("protocol_message")
    if not isinstance(protocol_message, dict):
        raise ValueError(f"missing {context}.protocol_message")
    root = protocol_message.get("cardano_transactions_merkle_root_hex")
    if not isinstance(root, str) or root == "":
        raise ValueError(
            f"missing {context}.protocol_message.cardano_transactions_merkle_root_hex"
        )
    return ensure_0x(root)


def require_certificate_matches_tx_snapshot_root(
    certificate: dict,
    context: str,
) -> str:
    root = tx_snapshot_certificate_root(certificate, context)
    signed_message = ensure_0x(certificate_signed_message(certificate, context))
    if signed_message != root:
        raise ValueError(
            f"{context}.signed_message must equal {context}.protocol_message.cardano_transactions_merkle_root_hex"
        )
    return root


def require_matching_hex_values(
    expected_value: str,
    actual_value: str,
    *,
    expected_label: str,
    actual_label: str,
) -> str:
    normalized_expected = ensure_0x(expected_value)
    normalized_actual = ensure_0x(actual_value)
    if normalized_expected != normalized_actual:
        raise ValueError(
            f"{actual_label} drifted from {expected_label}: expected {normalized_expected}, got {normalized_actual}"
        )
    return normalized_expected


def validate_snapshot_membership_fixture(data: dict) -> None:
    packed = data["packed_public_inputs"]

    locking_tx_hi, locking_tx_lo = packed_digest_halves(data["locking_tx_hash_hex"])
    if packed["cardano_tx_hash_hi"] != locking_tx_hi or packed["cardano_tx_hash_lo"] != locking_tx_lo:
        raise ValueError("packed_public_inputs.cardano_tx_hash_* does not match locking_tx_hash_hex")

    sub_root_hi, sub_root_lo = packed_digest_halves(
        data["locking_tx_merkle_proof_public_sub_root_hex"]
    )
    if packed["sub_root_hi"] != sub_root_hi or packed["sub_root_lo"] != sub_root_lo:
        raise ValueError(
            "packed_public_inputs.sub_root_* does not match locking_tx_merkle_proof_public_sub_root_hex"
        )

    snapshot_root_hi, snapshot_root_lo = packed_digest_halves(
        data["tx_snapshot_certificate_protocol_message_cardano_transactions_merkle_root_text"]
    )
    if packed["snapshot_root_hi"] != snapshot_root_hi or packed["snapshot_root_lo"] != snapshot_root_lo:
        raise ValueError(
            "packed_public_inputs.snapshot_root_* does not match tx_snapshot_certificate_protocol_message_cardano_transactions_merkle_root_text"
        )


def validate_tx_set_update_fixture(data: dict) -> None:
    packed = data["tx_set_update_packed_public_inputs"]

    tx_id_hi, tx_id_lo = packed_digest_halves(data["locking_tx_hash_hex"])
    if packed["tx_id_hi"] != tx_id_hi or packed["tx_id_lo"] != tx_id_lo:
        raise ValueError("tx_set_update_packed_public_inputs.tx_id_* does not match locking_tx_hash_hex")

    root_in = str(int(data["tx_set_update_old_merkle_root_hex"], 16))
    root_out = str(int(data["new_merkle_root_hex"], 16))
    if packed["mt_root_in"] != root_in:
        raise ValueError(
            "tx_set_update_packed_public_inputs.mt_root_in does not match tx_set_update_old_merkle_root_hex"
        )
    if packed["mt_root_out"] != root_out:
        raise ValueError(
            "tx_set_update_packed_public_inputs.mt_root_out does not match new_merkle_root_hex"
        )


def validate_bridge_zk_fixture_contract(data: dict) -> None:
    validate_snapshot_membership_fixture(data)
    validate_tx_set_update_fixture(data)
