from pathlib import Path

from arg_builder_common import ascii_bytes_hex, read_json
from stm_statement_digest import (
    canonical_statement_hash,
    required_child,
    require_certificate_matches_statement_hash,
)
from zk_contract import require_certificate_matches_tx_snapshot_root


def strip_0x(value: str) -> str:
    return value[2:] if value.startswith("0x") else value


def ensure_bytes_hex(value: str) -> str:
    return "0x" + strip_0x(value)


def ensure_ascii_hex(value: str) -> str:
    return ascii_bytes_hex(strip_0x(value))


def prev_hash_to_certificate_bytes(value: str) -> str:
    normalized = strip_0x(value)
    if normalized == "":
        return "0x"

    raw = bytes.fromhex(normalized)
    try:
        decoded = raw.decode("ascii")
    except UnicodeDecodeError:
        decoded = None

    if decoded is not None and len(decoded) % 2 == 0 and all(
        char in "0123456789abcdef" for char in decoded
    ):
        return "0x" + normalized

    return ascii_bytes_hex(normalized)

def load_proof_export_bundle(proof_export_bundle_path: Path) -> dict:
    proof_export_bundle = read_json(proof_export_bundle_path)
    if not isinstance(proof_export_bundle, dict):
        raise ValueError("Mithril STM proof-export bundle must be a JSON object")
    if not isinstance(proof_export_bundle.get("proofs"), dict):
        raise ValueError(
            f"missing `proofs` section in Mithril STM proof-export bundle: {proof_export_bundle_path}"
        )
    return proof_export_bundle


def proof_export_bundle_proofs(proof_export_bundle: dict) -> dict:
    proofs = proof_export_bundle.get("proofs")
    if not isinstance(proofs, dict):
        raise ValueError("missing proofs section in Mithril STM proof-export bundle")
    return proofs


def proof_entry(proof_export_bundle: dict, proof_name: str) -> dict:
    proofs = proof_export_bundle_proofs(proof_export_bundle)
    entry = proofs.get(proof_name)
    if not isinstance(entry, dict):
        raise ValueError(f"missing proofs.{proof_name} section in Mithril STM proof-export bundle")
    return entry


def proof_certificate(proof_export_bundle: dict, proof_name: str) -> dict:
    entry = proof_entry(proof_export_bundle, proof_name)
    statement = entry.get("statement")
    if not isinstance(statement, dict):
        raise ValueError(
            f"missing proofs.{proof_name}.statement section in Mithril STM proof-export bundle"
        )
    certificate = entry.get("certificate")
    if not isinstance(certificate, dict):
        raise ValueError(
            f"missing proofs.{proof_name}.certificate section in Mithril STM proof-export bundle"
        )
    statement_context = f"proofs.{proof_name}.statement"
    certificate_context = f"proofs.{proof_name}.certificate"
    statement_hash = canonical_statement_hash(statement, statement_context)
    require_certificate_matches_statement_hash(
        certificate,
        certificate_context,
        statement_hash,
        statement_context,
    )
    if proof_name == "cardano_transactions":
        require_certificate_matches_tx_snapshot_root(certificate, certificate_context)
    return certificate


def load_proof_export_bundle_proofs(proof_export_bundle_path: Path) -> dict[str, dict]:
    proof_export_bundle = load_proof_export_bundle(proof_export_bundle_path)
    return {
        "stake_distribution_genesis": proof_certificate(
            proof_export_bundle, "stake_distribution_genesis"
        ),
        "stake_distribution_standard": proof_certificate(
            proof_export_bundle, "stake_distribution_standard"
        ),
        "cardano_transactions": proof_certificate(proof_export_bundle, "cardano_transactions"),
    }


def load_sd_genesis_proof(proof_export_bundle_path: Path) -> dict:
    return load_proof_export_bundle_proofs(proof_export_bundle_path)["stake_distribution_genesis"]


def load_sd_standard_proof(proof_export_bundle_path: Path) -> dict:
    return load_proof_export_bundle_proofs(proof_export_bundle_path)["stake_distribution_standard"]


def load_tx_snapshot_proof(proof_export_bundle_path: Path) -> dict:
    return load_proof_export_bundle_proofs(proof_export_bundle_path)["cardano_transactions"]
def certificate_protocol_message(certificate: dict) -> dict:
    payload = certificate.get("protocol_message")
    if not isinstance(payload, dict):
        raise ValueError("missing certificate.protocol_message in Mithril STM proof-export bundle")
    return payload


def certificate_protocol_parameters(certificate: dict) -> dict:
    payload = certificate.get("protocol_parameters")
    if not isinstance(payload, dict):
        raise ValueError(
            "missing certificate.protocol_parameters in Mithril STM proof-export bundle"
        )
    return payload


def certificate_metadata(certificate: dict) -> dict:
    payload = certificate.get("metadata")
    if not isinstance(payload, dict):
        raise ValueError("missing certificate.metadata in Mithril STM proof-export bundle")
    return payload


def certificate_signed_entity(certificate: dict) -> dict:
    payload = certificate.get("signed_entity")
    if not isinstance(payload, dict):
        raise ValueError("missing certificate.signed_entity in Mithril STM proof-export bundle")
    return payload


def stake_distribution_signed_entity_fields(certificate: dict) -> tuple[bool, int]:
    signed_entity = certificate_signed_entity(certificate)
    kind = required_child(signed_entity, "kind", "certificate.signed_entity")
    epoch = required_child(signed_entity, "epoch", "certificate.signed_entity")
    return kind == "mithril_stake_distribution", epoch
