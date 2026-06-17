#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import urlopen

from arg_builder_common import read_json
from bridge_zk_fixture import DATA_PATH as BRIDGE_RAW_PATH
from bridge_zk_fixture import load_bridge_zk_fixture
from build_phase12_args_from_mithril_proof_export_bundle import (
    build_phase12_args_from_proof_export_bundle_file,
)
from mithril_stm_proof_export_bundle_certificates import (
    ensure_ascii_hex,
    ensure_bytes_hex,
    load_proof_export_bundle_proofs,
    strip_0x,
)
from stm_statement_digest import canonical_statement_hash
from prepare_mithril_bridge_minting_args import (
    build_bridge_args,
    load_bridge_minting_inputs,
)
from prepare_mithril_stake_distribution_args import build_sd_standard_args_from_certificate
from tx_snapshot_root import tx_snapshot_root, resolve_tx_snapshot_root


ROOT_DIR = Path(__file__).resolve().parent.parent.parent
DATA_DIR = ROOT_DIR / "scripts" / "data"
PHASE1_TEMPLATE_PATH = DATA_DIR / "phase1_args_raw.json"
PHASE2_TEMPLATE_PATH = DATA_DIR / "phase2_args_raw.json"
SNAPSHOT_PATH = DATA_DIR / "mithril_poc_reference_snapshot.json"
REFERENCE_FILES = [
    ROOT_DIR / "main.tx3",
    ROOT_DIR / "plutus.json",
    ROOT_DIR / "env" / "default.ak",
    DATA_DIR / "bridge_mint_raw.json",
    DATA_DIR / "mithril_stake_distribution_genesis.json",
    DATA_DIR / "mithril_stake_distribution_standard.json",
    ROOT_DIR / "validators" / "tests" / "helpers" / "bridge_fixture.ak",
    ROOT_DIR / "validators" / "tests" / "helpers" / "certificates" / "cardano_transactions.ak",
]

DUMMY_USER_ADDRESS = "addr_test1vqxazu4ekxrxlk238wt0e03h3gk44hrlkjvef85gvh2nahcgnmpfc"
DUMMY_PHASE2_HASH = "11" * 32
DUMMY_STAKE_DISTRIBUTION_HASH = "22" * 32
DUMMY_SD_STANDARD_RECEIPT_UTXO = f"{DUMMY_PHASE2_HASH}#0"
DUMMY_SD_SOURCE_UTXO = f'{"55" * 32}#0'
DUMMY_SD_COLLATERAL_UTXO = f'{"66" * 32}#1'
DUMMY_LOCKING_UPDATER_UNIQUE_MINT_UTXO = f'{"33" * 32}#1'
DUMMY_BRIDGE_SOURCE_UTXO = f'{"44" * 32}#2'
DUMMY_OUTPUT_LOVELACE = 3_000_000
DEFAULT_AGGREGATOR_ENDPOINT = (
    "https://aggregator.pre-release-preview.api.mithril.network/aggregator"
)
DEFAULT_MIN_OPEN_API_VERSION = "0.1.61"
DEFAULT_REQUIRED_SIGNED_ENTITY_TYPES = [
    "CardanoStakeDistribution",
    "CardanoTransactions",
]
DEFAULT_EXPECTED_AGGREGATE_SIGNATURE_TYPE = "Concatenation"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("proof_export_bundle", type=Path, nargs="?")
    parser.add_argument(
        "--snapshot",
        type=Path,
        default=SNAPSHOT_PATH,
        help="reference snapshot JSON to compare against",
    )
    parser.add_argument(
        "--write-snapshot",
        action="store_true",
        help="write the current snapshot instead of comparing it",
    )
    parser.add_argument(
        "--refresh-snapshot-on-drift",
        action="store_true",
        help="rewrite the reference snapshot automatically when drift is detected",
    )
    parser.add_argument(
        "--aggregator-endpoint",
        default=os.environ.get(
            "MITHRIL_AGGREGATOR_ENDPOINT", DEFAULT_AGGREGATOR_ENDPOINT
        ),
    )
    parser.add_argument(
        "--min-open-api-version",
        default=os.environ.get(
            "MITHRIL_MIN_OPEN_API_VERSION", DEFAULT_MIN_OPEN_API_VERSION
        ),
    )
    parser.add_argument(
        "--expected-aggregate-signature-type",
        default=os.environ.get(
            "MITHRIL_EXPECTED_AGGREGATE_SIGNATURE_TYPE",
            DEFAULT_EXPECTED_AGGREGATE_SIGNATURE_TYPE,
        ),
    )
    parser.add_argument(
        "--require-signed-entity-type",
        action="append",
        dest="required_signed_entity_types",
        default=None,
    )
    parser.add_argument(
        "--aggregator-only",
        action="store_true",
        help="only validate the live Mithril aggregator compatibility gate",
    )
    return parser.parse_args()


def fetch_json(url: str) -> dict:
    with urlopen(url, timeout=20) as response:
        return json.load(response)


def parse_version_tuple(version: str) -> tuple[int, ...]:
    try:
        return tuple(int(part) for part in version.split("."))
    except ValueError as exc:
        raise SystemExit(f"invalid OpenAPI version format {version!r}: {exc}") from exc


def require_protocol_configuration(
    aggregator_endpoint: str,
    target_epoch: int,
    required_signed_entity_types: list[str],
) -> None:
    try:
        protocol_configuration = fetch_json(
            f"{aggregator_endpoint}/protocol-configuration/{target_epoch}"
        )
    except HTTPError as exc:
        raise SystemExit(
            "aggregator did not expose protocol configuration for the target epoch: "
            f"epoch={target_epoch}, endpoint={aggregator_endpoint}, status={exc.code}"
        ) from exc

    protocol_parameters = protocol_configuration.get("protocol_parameters")
    if not isinstance(protocol_parameters, dict):
        raise SystemExit(
            f"aggregator protocol configuration for epoch {target_epoch} is missing protocol_parameters"
        )
    for field in ("k", "m", "phi_f"):
        if field not in protocol_parameters:
            raise SystemExit(
                "aggregator protocol configuration is missing protocol parameter "
                f"{field!r} for epoch {target_epoch}"
            )

    tx_signing_config = protocol_configuration.get("cardano_transactions_signing_config")
    if not isinstance(tx_signing_config, dict):
        raise SystemExit(
            "aggregator protocol configuration is missing "
            f"cardano_transactions_signing_config for epoch {target_epoch}"
        )
    for field in ("security_parameter", "step"):
        if field not in tx_signing_config:
            raise SystemExit(
                "aggregator cardano_transactions_signing_config is missing "
                f"{field!r} for epoch {target_epoch}"
            )

    available_signed_entity_types = protocol_configuration.get(
        "available_signed_entity_types"
    )
    if not isinstance(available_signed_entity_types, list):
        raise SystemExit(
            "aggregator protocol configuration is missing "
            f"available_signed_entity_types for epoch {target_epoch}"
        )
    missing_signed_entity_types = [
        item
        for item in required_signed_entity_types
        if item not in available_signed_entity_types
    ]
    if missing_signed_entity_types:
        raise SystemExit(
            "aggregator protocol configuration is missing required signed entity types "
            f"for epoch {target_epoch}: {missing_signed_entity_types}; "
            f"available={available_signed_entity_types}"
        )


def extract_target_protocol_epochs(
    proof_export_bundle_path: Path | None,
    status_epoch: int,
) -> list[int]:
    if proof_export_bundle_path is None:
        return [status_epoch]

    proof_export_bundle = read_json(proof_export_bundle_path)
    source = proof_export_bundle.get("source")
    if isinstance(source, dict):
        if source.get("source_kind") == "fixture" or source.get(
            "source_id"
        ) == "bridge-aiken-compatible-fixture":
            return [status_epoch]

    candidate_paths = [
        ("certificates.child.signed_entity.epoch", (
            proof_export_bundle.get("certificates", {})
            .get("child", {})
            .get("signed_entity", {})
            .get("epoch")
        )),
        ("proofs.stake_distribution_standard.certificate.signed_entity.epoch", (
            proof_export_bundle.get("proofs", {})
            .get("stake_distribution_standard", {})
            .get("certificate", {})
            .get("signed_entity", {})
            .get("epoch")
        )),
        ("proofs.cardano_transactions.certificate.signed_entity.epoch", (
            proof_export_bundle.get("proofs", {})
            .get("cardano_transactions", {})
            .get("certificate", {})
            .get("signed_entity", {})
            .get("epoch")
        )),
    ]

    epochs: list[int] = []
    for label, value in candidate_paths:
        if value is None:
            continue
        if not isinstance(value, int):
            raise SystemExit(
                f"{label} must be an integer when present, got {value!r}"
            )
        epochs.append(value)

    if not epochs:
        return [status_epoch]

    unique_epochs = sorted(set(epochs))
    if len(unique_epochs) > 1:
        raise SystemExit(
            "proof_export_bundle mixes multiple Mithril target epochs, "
            f"which preflight currently treats as unsupported: {unique_epochs}"
        )

    return unique_epochs


def validate_aggregator_compatibility(
    aggregator_endpoint: str,
    min_open_api_version: str,
    expected_aggregate_signature_type: str,
    required_signed_entity_types: list[str],
) -> dict:
    features = fetch_json(f"{aggregator_endpoint}/")
    status = fetch_json(f"{aggregator_endpoint}/status")

    open_api_version = features.get("open_api_version")
    if not isinstance(open_api_version, str) or not open_api_version:
        raise SystemExit(
            f"aggregator {aggregator_endpoint} did not expose a valid open_api_version"
        )
    if parse_version_tuple(open_api_version) < parse_version_tuple(
        min_open_api_version
    ):
        raise SystemExit(
            "aggregator OpenAPI version is too old for bridge-aiken preflight: "
            f"got {open_api_version}, need at least {min_open_api_version}"
        )

    capabilities = features.get("capabilities")
    if not isinstance(capabilities, dict):
        raise SystemExit(
            f"aggregator {aggregator_endpoint} did not expose a capabilities object"
        )

    aggregate_signature_type = capabilities.get("aggregate_signature_type")
    if aggregate_signature_type != expected_aggregate_signature_type:
        raise SystemExit(
            "aggregator aggregate_signature_type mismatch: "
            f"got {aggregate_signature_type!r}, expected {expected_aggregate_signature_type!r}"
        )

    signed_entity_types = capabilities.get("signed_entity_types")
    if not isinstance(signed_entity_types, list):
        raise SystemExit(
            f"aggregator {aggregator_endpoint} did not expose a signed_entity_types list"
        )
    missing_signed_entity_types = [
        item for item in required_signed_entity_types if item not in signed_entity_types
    ]
    if missing_signed_entity_types:
        raise SystemExit(
            "aggregator is missing required signed entity types: "
            f"{missing_signed_entity_types}; available={signed_entity_types}"
        )

    status_epoch = status.get("epoch")
    if not isinstance(status_epoch, int):
        raise SystemExit(
            f"aggregator {aggregator_endpoint} did not expose an integer status epoch"
        )

    return status


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_snapshot(proof_export_bundle_path: Path) -> dict:
    proof_export_bundle = read_json(proof_export_bundle_path)
    bridge_raw = load_bridge_zk_fixture(BRIDGE_RAW_PATH)
    proof_export_bundle_snapshot_root = tx_snapshot_root(proof_export_bundle_path)
    bridge_snapshot_root = resolve_tx_snapshot_root(bridge_raw, proof_export_bundle_path)

    files = {
        str(path.relative_to(ROOT_DIR)): sha256_file(path) for path in REFERENCE_FILES
    }

    return {
        "proof_export_bundle": {
            "source_id": proof_export_bundle["source_bundle"]["source_id"],
            "statement_hash": proof_export_bundle["statement"]["statement_hash"],
            "parent_certificate_hash": proof_export_bundle["certificates"]["parent"]["hash"],
            "child_certificate_hash": proof_export_bundle["certificates"]["child"]["hash"],
            "child_signed_message": proof_export_bundle["certificates"]["child"]["signed_message"],
        },
        "bridge_fixture": {
            "locking_tx_hash_hex": bridge_raw["locking_tx_hash_hex"],
            "new_merkle_root_hex": bridge_raw["new_merkle_root_hex"],
            "snapshot_root_hex": strip_0x(bridge_snapshot_root),
        },
        "tx_snapshot_root": {
            "proof_export_bundle_hex": proof_export_bundle_snapshot_root,
            "bridge_fixture_hex": bridge_snapshot_root,
        },
        "files": files,
    }


def compare_snapshot(expected: dict, actual: dict) -> list[str]:
    if expected == actual:
        return []

    mismatches: list[str] = []

    for section_name in sorted(set(expected) | set(actual)):
        expected_section = expected.get(section_name)
        actual_section = actual.get(section_name)
        if expected_section == actual_section:
            continue

        if isinstance(expected_section, dict) and isinstance(actual_section, dict):
            for key in sorted(set(expected_section) | set(actual_section)):
                if expected_section.get(key) != actual_section.get(key):
                    mismatches.append(
                        f"{section_name}.{key}: expected {expected_section.get(key)!r}, "
                        f"got {actual_section.get(key)!r}"
                    )
            continue

        mismatches.append(
            f"{section_name}: expected {expected_section!r}, got {actual_section!r}"
        )

    return mismatches


def write_snapshot(snapshot_path: Path, snapshot: dict) -> None:
    snapshot_path.write_text(json.dumps(snapshot, indent=2, sort_keys=True) + "\n")


def raise_snapshot_drift(snapshot_path: Path, mismatches: list[str]) -> None:
    details = "\n".join(f"- {entry}" for entry in mismatches)
    raise SystemExit(
        "canonical reference snapshot is stale for the current repo state:\n"
        f"- snapshot file: {snapshot_path}\n"
        "- this usually means the canonical bridge flow inputs or derived fixtures changed\n"
        "- refresh the snapshot after confirming the new state is intended\n"
        f"drift details:\n{details}"
    )


def require_equal(label: str, actual, expected) -> None:
    if actual != expected:
        raise SystemExit(f"{label} drifted: expected {expected!r}, got {actual!r}")


def validate_proof_export_bundle_usage(proof_export_bundle_path: Path) -> None:
    proof_export_bundle = read_json(proof_export_bundle_path)
    statement_hash = canonical_statement_hash(proof_export_bundle["statement"], "statement")
    certificates = proof_export_bundle.get("certificates")
    if not isinstance(certificates, dict):
        raise SystemExit("missing certificates section in Mithril STM proof_export_bundle")
    parent_certificate = certificates.get("parent")
    child_certificate = certificates.get("child")
    if not isinstance(parent_certificate, dict):
        raise SystemExit("missing certificates.parent section in Mithril STM proof_export_bundle")
    if not isinstance(child_certificate, dict):
        raise SystemExit("missing certificates.child section in Mithril STM proof_export_bundle")
    proof_certificates = load_proof_export_bundle_proofs(proof_export_bundle_path)
    sd_standard_statement_hash = canonical_statement_hash(
        proof_export_bundle["proofs"]["stake_distribution_standard"]["statement"],
        "proofs.stake_distribution_standard.statement",
    )
    tx_snapshot_statement_hash = canonical_statement_hash(
        proof_export_bundle["proofs"]["cardano_transactions"]["statement"],
        "proofs.cardano_transactions.statement",
    )
    resolved_snapshot_root = resolve_tx_snapshot_root(
        load_bridge_zk_fixture(BRIDGE_RAW_PATH),
        proof_export_bundle_path,
    )

    phase1_args, phase2_args = build_phase12_args_from_proof_export_bundle_file(
        proof_export_bundle_path,
        PHASE1_TEMPLATE_PATH,
        PHASE2_TEMPLATE_PATH,
    )
    require_equal(
        "phase1 statement_hash_value",
        phase1_args["statement_hash_value"],
        statement_hash,
    )
    require_equal(
        "phase2 proof_receipt_statement_hash",
        phase2_args["proof_receipt_statement_hash"],
        statement_hash,
    )

    standard_args = build_sd_standard_args_from_certificate(
        proof_certificates["stake_distribution_standard"],
        DUMMY_USER_ADDRESS,
        sd_standard_statement_hash,
        DUMMY_OUTPUT_LOVELACE,
        DUMMY_SD_STANDARD_RECEIPT_UTXO,
        DUMMY_SD_SOURCE_UTXO,
        DUMMY_SD_COLLATERAL_UTXO,
    )
    require_equal(
        "stake_distribution certificate_signed_message",
        standard_args["certificate_signed_message"],
        sd_standard_statement_hash,
    )
    require_equal(
        "stake_distribution certificate_hash",
        standard_args["certificate_hash"],
        ensure_bytes_hex(proof_certificates["stake_distribution_standard"]["hash"]),
    )

    bridge_inputs = load_bridge_minting_inputs(
        user_address=DUMMY_USER_ADDRESS,
        tx_snapshot_phase2_hash=DUMMY_PHASE2_HASH,
        tx_snapshot_receipt_statement_hash=tx_snapshot_statement_hash,
        stake_distribution_standard_hash=DUMMY_STAKE_DISTRIBUTION_HASH,
        locking_updater_unique_mint_utxo=DUMMY_LOCKING_UPDATER_UNIQUE_MINT_UTXO,
        bridge_source_utxo=DUMMY_BRIDGE_SOURCE_UTXO,
        proof_export_bundle_path=proof_export_bundle_path,
    )
    bridge_args = build_bridge_args(bridge_inputs)

    require_equal(
        "bridge tx_snapshot_certificate_signed_message",
        bridge_args["tx_snapshot_certificate_signed_message"],
        tx_snapshot_statement_hash,
    )
    require_equal(
        "bridge tx_snapshot root",
        bridge_args["tx_snapshot_certificate_protocol_message_cardano_transactions_merkle_root"],
        resolved_snapshot_root,
    )
    require_equal(
        "bridge parent_certificate_hash",
        bridge_args["parent_certificate_hash"],
        standard_args["certificate_hash"],
    )
    require_equal(
        "bridge parent_certificate_epoch",
        bridge_args["parent_certificate_epoch"],
        standard_args["certificate_epoch"],
    )
    require_equal(
        "bridge tx_snapshot_certificate_prev_hash",
        bridge_args["tx_snapshot_certificate_prev_hash"],
        ensure_ascii_hex(child_certificate["hash"]),
    )
    require_equal(
        "proof_export_bundle child signed_message",
        child_certificate["signed_message"],
        statement_hash,
    )
    require_equal(
        "proof_export_bundle statement.public_input_2",
        proof_export_bundle["statement"]["public_input_2"],
        statement_hash,
    )
    require_equal(
        "proof_export_bundle parent hash",
        parent_certificate["hash"],
        proof_export_bundle["certificates"]["parent"]["hash"],
    )
    require_equal(
        "bridge fixture locking_tx_hash",
        strip_0x(bridge_args["locking_tx_hash"]),
        load_bridge_zk_fixture()["locking_tx_hash_hex"],
    )

    for proof_name, certificate in proof_certificates.items():
        proof_phase1_args, proof_phase2_args = build_phase12_args_from_proof_export_bundle_file(
            proof_export_bundle_path,
            PHASE1_TEMPLATE_PATH,
            PHASE2_TEMPLATE_PATH,
            proof_name,
        )
        proof_statement_hash = canonical_statement_hash(
            proof_export_bundle["proofs"][proof_name]["statement"],
            f"proofs.{proof_name}.statement",
        )
        require_equal(
            f"{proof_name} phase1 statement_hash_value",
            proof_phase1_args["statement_hash_value"],
            proof_statement_hash,
        )
        require_equal(
            f"{proof_name} phase2 proof_receipt_statement_hash",
            proof_phase2_args["proof_receipt_statement_hash"],
            proof_statement_hash,
        )
        require_equal(
            f"{proof_name} certificate signed_message",
            ensure_bytes_hex(certificate["signed_message"]),
            proof_statement_hash,
        )

    proof_statement_hashes = {
        proof_name: canonical_statement_hash(
            proof_export_bundle["proofs"][proof_name]["statement"],
            f"proofs.{proof_name}.statement",
        )
        for proof_name in proof_certificates
    }
    if len(set(proof_statement_hashes.values())) != len(proof_statement_hashes):
        raise SystemExit(
            f"proof statement hashes must be unique, got: {proof_statement_hashes}"
        )


def main() -> int:
    args = parse_args()
    required_signed_entity_types = (
        args.required_signed_entity_types
        if args.required_signed_entity_types is not None
        else list(DEFAULT_REQUIRED_SIGNED_ENTITY_TYPES)
    )

    status = validate_aggregator_compatibility(
        args.aggregator_endpoint,
        args.min_open_api_version,
        args.expected_aggregate_signature_type,
        required_signed_entity_types,
    )

    target_epochs = extract_target_protocol_epochs(
        args.proof_export_bundle,
        status["epoch"],
    )
    for target_epoch in target_epochs:
        require_protocol_configuration(
            args.aggregator_endpoint,
            target_epoch,
            required_signed_entity_types,
        )

    if args.aggregator_only:
        return 0

    if args.proof_export_bundle is None:
        raise SystemExit(
            "proof_export_bundle is required unless --aggregator-only is used"
        )

    snapshot = build_snapshot(args.proof_export_bundle)

    if args.write_snapshot:
        write_snapshot(args.snapshot, snapshot)
        return 0

    validate_proof_export_bundle_usage(args.proof_export_bundle)
    mismatches = compare_snapshot(read_json(args.snapshot), snapshot)
    if mismatches:
        if args.refresh_snapshot_on_drift:
            write_snapshot(args.snapshot, snapshot)
            print(
                "Canonical reference snapshot refreshed for current repo state:",
                args.snapshot,
            )
            return 0
        raise_snapshot_drift(args.snapshot, mismatches)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
