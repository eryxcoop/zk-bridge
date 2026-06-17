#!/usr/bin/env python3

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path

from arg_builder_common import (
    as_bytes_hex,
    ascii_bytes_hex,
    parse_env_policy_const,
    parse_env_text_const,
    read_json,
    write_json,
)
from bech32 import payment_key_hash_from_address
from bridge_zk_fixture import load_bridge_zk_fixture
from mithril_stm_proof_export_bundle_certificates import (
    certificate_protocol_message,
    certificate_protocol_parameters,
    ensure_ascii_hex,
    ensure_bytes_hex,
    load_sd_standard_proof,
    load_tx_snapshot_proof,
)
from stm_statement_digest import require_certificate_matches_statement_hash
from tx_snapshot_root import resolve_tx_snapshot_root, strip_0x

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
ENV_DEFAULT_PATH = Path(__file__).resolve().parent.parent.parent / "env" / "default.ak"
BRIDGE_NEXT_PROTOCOL_PARAMETERS_TEXT = (
    "b01de82ca7e57c1bf2a56381ce265f378aeea5f1dde7f824b5ba42125c4adad2"
)
@dataclass(frozen=True)
class BridgeMintingInputs:
    genesis_raw: dict
    bridge_raw: dict
    stake_distribution_standard_certificate: dict
    tx_snapshot_certificate: dict
    canonical_tx_snapshot_root: str
    user_address: str
    user_pkh: str
    bridge_policy_hex: str
    transferred_asset_name: str
    tx_snapshot_phase2_hash: str
    tx_snapshot_receipt_statement_hash: str
    stake_distribution_standard_hash: str
    locking_updater_unique_mint_utxo: str
    bridge_source_utxo: str


def bridge_new_merkle_root_hex(bridge_raw: dict) -> str:
    if "new_merkle_root_hex" in bridge_raw:
        return bridge_raw["new_merkle_root_hex"]
    return bridge_raw["new_merkle_root_text"].encode().hex()


def verified_locking_tx_hash_hex(bridge_raw: dict) -> str:
    expected_hash_hex = bridge_raw.get("locking_tx_hash_hex")
    if not isinstance(expected_hash_hex, str) or expected_hash_hex == "":
        raise ValueError("bridge_mint_raw.locking_tx_hash_hex is required")
    return expected_hash_hex


def load_bridge_minting_inputs(
    user_address: str,
    tx_snapshot_phase2_hash: str,
    tx_snapshot_receipt_statement_hash: str,
    stake_distribution_standard_hash: str,
    locking_updater_unique_mint_utxo: str,
    bridge_source_utxo: str,
    proof_export_bundle_path: Path | None,
) -> BridgeMintingInputs:
    genesis_raw = read_json(DATA_DIR / "locking_txs_updater_genesis_raw.json")
    bridge_raw = load_bridge_zk_fixture(DATA_DIR / "bridge_mint_raw.json")
    canonical_tx_snapshot_root = resolve_tx_snapshot_root(
        bridge_raw,
        proof_export_bundle_path,
    )
    if proof_export_bundle_path is not None:
        stake_distribution_standard_certificate = load_sd_standard_proof(
            proof_export_bundle_path
        )
        tx_snapshot_certificate = load_tx_snapshot_proof(proof_export_bundle_path)
    else:
        stake_distribution_standard_certificate = read_json(
            DATA_DIR / "mithril_stake_distribution_standard.json"
        )
        tx_snapshot_certificate = {
            "hash": bridge_raw["child_certificate_hash_text"],
            "epoch": stake_distribution_standard_certificate["epoch"],
            "protocol_parameters": {
                "k": stake_distribution_standard_certificate["k"],
                "m": stake_distribution_standard_certificate["m"],
                "phi_f": "0x" + stake_distribution_standard_certificate["phi_f"],
            },
            "protocol_message": {
                "current_epoch_text": stake_distribution_standard_certificate[
                    "current_epoch_text"
                ],
                "next_aggregate_verification_key_text": bridge_raw[
                    "child_certificate_next_aggregate_verification_key_text"
                ],
                "next_aggregate_verification_key_snark_text": bridge_raw[
                    "child_certificate_next_aggregate_verification_key_snark_text"
                ],
                "next_protocol_parameters_text": BRIDGE_NEXT_PROTOCOL_PARAMETERS_TEXT,
                "cardano_transactions_merkle_root_hex": strip_0x(
                    canonical_tx_snapshot_root
                ),
            },
            "signed_message": strip_0x(canonical_tx_snapshot_root),
            "aggregate_verification_key_text": stake_distribution_standard_certificate[
                "aggregate_verification_key_text"
            ],
            "aggregate_verification_key_snark_text": stake_distribution_standard_certificate[
                "aggregate_verification_key_snark_text"
            ],
        }
    user_pkh = payment_key_hash_from_address(user_address)
    env_text = ENV_DEFAULT_PATH.read_text()
    bridge_policy_hex = parse_env_policy_const(env_text, "bridge_minting_policy_id")
    transferred_asset_name = parse_env_text_const(env_text, "transferred_asset_name")

    return BridgeMintingInputs(
        genesis_raw=genesis_raw,
        bridge_raw=bridge_raw,
        stake_distribution_standard_certificate=stake_distribution_standard_certificate,
        tx_snapshot_certificate=tx_snapshot_certificate,
        canonical_tx_snapshot_root=canonical_tx_snapshot_root,
        user_address=user_address,
        user_pkh=user_pkh,
        bridge_policy_hex=bridge_policy_hex,
        transferred_asset_name=transferred_asset_name,
        tx_snapshot_phase2_hash=tx_snapshot_phase2_hash,
        tx_snapshot_receipt_statement_hash=tx_snapshot_receipt_statement_hash,
        stake_distribution_standard_hash=stake_distribution_standard_hash,
        locking_updater_unique_mint_utxo=locking_updater_unique_mint_utxo,
        bridge_source_utxo=bridge_source_utxo,
    )


def bridge_locking_tx_args(inputs: BridgeMintingInputs) -> dict:
    bridge_raw = inputs.bridge_raw
    locking_tx_input_output_reference_tx_id = ascii_bytes_hex(
        bridge_raw["locking_tx_input_output_reference_tx_id_text"]
    )
    locking_tx_input_output_reference_output_index = bridge_raw[
        "locking_tx_input_output_reference_output_index"
    ]
    locking_tx_input_payment_credential = ascii_bytes_hex(
        bridge_raw["locking_tx_input_payment_credential_text"]
    )
    locking_tx_ada_amount = bridge_raw["locking_tx_ada_amount"]
    locking_tx_hash_value = as_bytes_hex(
        verified_locking_tx_hash_hex(bridge_raw),
    )
    return {
        "locking_tx_hash": locking_tx_hash_value,
        "locking_tx_input_output_reference_tx_id": locking_tx_input_output_reference_tx_id,
        "locking_tx_input_output_reference_output_index": locking_tx_input_output_reference_output_index,
        "locking_tx_input_payment_credential": locking_tx_input_payment_credential,
        "locking_tx_input_datum": "0x",
        "locking_tx_destination_payment_credential": "0x" + inputs.user_pkh,
        "locking_tx_asset_amount": bridge_raw["bridge_asset_amount"],
        "locking_tx_ada_amount": locking_tx_ada_amount,
    }


def build_genesis_args(inputs: BridgeMintingInputs) -> dict:
    genesis_raw = inputs.genesis_raw
    return {
        "user": inputs.user_address,
        "locking_txs_updater_output_lovelace": genesis_raw[
            "locking_txs_updater_output_lovelace"
        ],
        "bridge_collateral_lovelace": 20000000,
        "unique_mint_source_utxo": inputs.locking_updater_unique_mint_utxo,
        "collateral_utxo": f"{inputs.tx_snapshot_phase2_hash}#1",
    }


def build_bridge_args(inputs: BridgeMintingInputs) -> dict:
    bridge_raw = inputs.bridge_raw
    standard = inputs.stake_distribution_standard_certificate
    tx_snapshot_certificate = inputs.tx_snapshot_certificate
    standard_protocol_parameters = certificate_protocol_parameters(standard) if "protocol_parameters" in standard else None
    standard_protocol_message = certificate_protocol_message(standard) if "protocol_message" in standard else None
    tx_snapshot_protocol_parameters = (
        certificate_protocol_parameters(tx_snapshot_certificate)
        if "protocol_parameters" in tx_snapshot_certificate
        else None
    )
    tx_snapshot_protocol_message = (
        certificate_protocol_message(tx_snapshot_certificate)
        if "protocol_message" in tx_snapshot_certificate
        else None
    )
    standard_hash = (
        ensure_bytes_hex(standard["hash"])
        if "protocol_parameters" in standard
        else as_bytes_hex(standard["hash"])
    )
    standard_prev_hash_ascii = (
        ensure_ascii_hex(standard["hash"])
        if "protocol_parameters" in standard
        else ascii_bytes_hex(standard["hash"])
    )
    standard_epoch = standard["epoch"]
    standard_k = (
        standard_protocol_parameters["k"]
        if standard_protocol_parameters is not None
        else standard["k"]
    )
    standard_m = (
        standard_protocol_parameters["m"]
        if standard_protocol_parameters is not None
        else standard["m"]
    )
    standard_phi_f = (
        ensure_bytes_hex(standard_protocol_parameters["phi_f"])
        if standard_protocol_parameters is not None
        else as_bytes_hex(standard["phi_f"])
    )
    standard_current_epoch = (
        ensure_ascii_hex(standard_protocol_message["current_epoch_text"])
        if standard_protocol_message is not None
        else ascii_bytes_hex(standard["current_epoch_text"])
    )
    standard_aggregate_verification_key = (
        ensure_ascii_hex(standard["aggregate_verification_key_text"])
        if standard_protocol_parameters is not None
        else ascii_bytes_hex(standard["aggregate_verification_key_text"])
    )
    standard_aggregate_verification_key_snark = (
        ensure_ascii_hex(standard["aggregate_verification_key_snark_text"])
        if standard_protocol_parameters is not None
        else ascii_bytes_hex(standard["aggregate_verification_key_snark_text"])
    )
    standard_next_aggregate_verification_key_snark = (
        ensure_ascii_hex(
            standard_protocol_message["next_aggregate_verification_key_snark_text"]
        )
        if standard_protocol_message is not None
        else ascii_bytes_hex(standard["next_aggregate_verification_key_snark_text"])
    )
    tx_snapshot_hash = (
        ensure_bytes_hex(tx_snapshot_certificate["hash"])
        if "protocol_parameters" in tx_snapshot_certificate
        else ascii_bytes_hex(tx_snapshot_certificate["hash"])
    )
    tx_snapshot_epoch = tx_snapshot_certificate["epoch"]
    tx_snapshot_k = (
        tx_snapshot_protocol_parameters["k"]
        if tx_snapshot_protocol_parameters is not None
        else tx_snapshot_certificate["k"]
    )
    tx_snapshot_m = (
        tx_snapshot_protocol_parameters["m"]
        if tx_snapshot_protocol_parameters is not None
        else tx_snapshot_certificate["m"]
    )
    tx_snapshot_phi_f = (
        ensure_bytes_hex(tx_snapshot_protocol_parameters["phi_f"])
        if tx_snapshot_protocol_parameters is not None
        else as_bytes_hex(tx_snapshot_certificate["phi_f"])
    )
    tx_snapshot_current_epoch = (
        ensure_ascii_hex(tx_snapshot_protocol_message["current_epoch_text"])
        if tx_snapshot_protocol_message is not None
        else ascii_bytes_hex(tx_snapshot_certificate["current_epoch_text"])
    )
    tx_snapshot_next_aggregate_verification_key = (
        ensure_ascii_hex(
            tx_snapshot_protocol_message["next_aggregate_verification_key_text"]
        )
        if tx_snapshot_protocol_message is not None
        else ascii_bytes_hex(
            tx_snapshot_certificate["next_aggregate_verification_key_text"]
        )
    )
    tx_snapshot_next_aggregate_verification_key_snark = (
        ensure_ascii_hex(
            tx_snapshot_protocol_message["next_aggregate_verification_key_snark_text"]
        )
        if tx_snapshot_protocol_message is not None
        else ascii_bytes_hex(
            tx_snapshot_certificate["next_aggregate_verification_key_snark_text"]
        )
    )
    tx_snapshot_next_protocol_parameters = (
        ensure_ascii_hex(tx_snapshot_protocol_message["next_protocol_parameters_text"])
        if tx_snapshot_protocol_message is not None
        else ascii_bytes_hex(tx_snapshot_certificate["next_protocol_parameters_text"])
    )
    tx_snapshot_merkle_root = as_bytes_hex(strip_0x(inputs.canonical_tx_snapshot_root))
    tx_snapshot_signed_message = (
        ensure_bytes_hex(tx_snapshot_certificate["signed_message"])
        if "protocol_parameters" in tx_snapshot_certificate
        else as_bytes_hex(tx_snapshot_certificate["signed_message"])
    )
    tx_snapshot_aggregate_verification_key = (
        ensure_ascii_hex(tx_snapshot_certificate["aggregate_verification_key_text"])
        if "protocol_parameters" in tx_snapshot_certificate
        else ascii_bytes_hex(tx_snapshot_certificate["aggregate_verification_key_text"])
    )
    tx_snapshot_aggregate_verification_key_snark = (
        ensure_ascii_hex(tx_snapshot_certificate["aggregate_verification_key_snark_text"])
        if "protocol_parameters" in tx_snapshot_certificate
        else ascii_bytes_hex(
            tx_snapshot_certificate["aggregate_verification_key_snark_text"]
        )
    )
    require_certificate_matches_statement_hash(
        {"signed_message": tx_snapshot_signed_message},
        "cardano_transactions.certificate",
        inputs.tx_snapshot_receipt_statement_hash,
        "cardano_transactions.statement",
    )
    bridge_args = {
        "user": inputs.user_address,
        "locking_txs_updater_utxo": "__LOCKING_TXS_UPDATER_GENESIS_HASH__#0",
        "source_utxo": inputs.bridge_source_utxo,
        "stake_distribution_utxo": f"{inputs.stake_distribution_standard_hash}#0",
        "tx_snapshot_receipt_utxo": f"{inputs.tx_snapshot_phase2_hash}#0",
        "locking_txs_updater_spend_reference_script_utxo": "__LOCKING_TXS_UPDATER_SPEND_REFERENCE_SCRIPT_HASH__#0",
        "bridge_minting_reference_script_utxo": "__BRIDGE_MINTING_REFERENCE_SCRIPT_HASH__#0",
        "collateral_utxo": f"{inputs.tx_snapshot_phase2_hash}#1",
        "bridge_asset_amount": bridge_raw["bridge_asset_amount"],
        "bridge_output_lovelace": bridge_raw["bridge_output_lovelace"],
        "locking_txs_updater_output_lovelace": bridge_raw[
            "locking_txs_updater_output_lovelace"
        ],
        "new_merkle_root": as_bytes_hex(bridge_new_merkle_root_hex(bridge_raw)),
        "tx_snapshot_certificate_hash": tx_snapshot_hash,
        "tx_snapshot_certificate_prev_hash": standard_prev_hash_ascii,
        "tx_snapshot_certificate_epoch": tx_snapshot_epoch,
        "tx_snapshot_certificate_protocol_parameters_k": tx_snapshot_k,
        "tx_snapshot_certificate_protocol_parameters_m": tx_snapshot_m,
        "tx_snapshot_certificate_protocol_parameters_phi_f": tx_snapshot_phi_f,
        "tx_snapshot_certificate_protocol_message_next_aggregate_verification_key": tx_snapshot_next_aggregate_verification_key,
        "tx_snapshot_certificate_protocol_message_next_aggregate_verification_key_snark": tx_snapshot_next_aggregate_verification_key_snark,
        "tx_snapshot_certificate_protocol_message_next_protocol_parameters": tx_snapshot_next_protocol_parameters,
        "tx_snapshot_certificate_protocol_message_current_epoch": tx_snapshot_current_epoch,
        "tx_snapshot_certificate_protocol_message_cardano_transactions_merkle_root": tx_snapshot_merkle_root,
        "tx_snapshot_certificate_signed_message": tx_snapshot_signed_message,
        "tx_snapshot_certificate_aggregate_verification_key": tx_snapshot_aggregate_verification_key,
        "tx_snapshot_certificate_aggregate_verification_key_snark": tx_snapshot_aggregate_verification_key_snark,
        "tx_snapshot_certificate_signed_entity_is_stake_distribution": False,
        "tx_snapshot_certificate_signed_entity_epoch": tx_snapshot_epoch,
        "parent_certificate_hash": standard_hash,
        "parent_certificate_epoch": standard_epoch,
        "parent_certificate_protocol_parameters_k": standard_k,
        "parent_certificate_protocol_parameters_m": standard_m,
        "parent_certificate_protocol_parameters_phi_f": standard_phi_f,
        "parent_certificate_next_aggregate_verification_key_snark": standard_next_aggregate_verification_key_snark,
        "parent_certificate_aggregate_verification_key_snark": standard_aggregate_verification_key_snark,
        "locking_tx_merkle_proof_public_sub_root": as_bytes_hex(
            bridge_raw["locking_tx_merkle_proof_public_sub_root_hex"]
        ),
        "locking_tx_merkle_proof_pi_a": as_bytes_hex(
            bridge_raw["minting_merkle_proof"]["piA"]
        ),
        "locking_tx_merkle_proof_pi_b": as_bytes_hex(
            bridge_raw["minting_merkle_proof"]["piB"]
        ),
        "locking_tx_merkle_proof_pi_c": as_bytes_hex(
            bridge_raw["minting_merkle_proof"]["piC"]
        ),
        **bridge_locking_tx_args(inputs),
        "tx_set_update_proof_pi_a": as_bytes_hex(bridge_raw["tx_set_update_proof"]["piA"]),
        "tx_set_update_proof_pi_b": as_bytes_hex(bridge_raw["tx_set_update_proof"]["piB"]),
        "tx_set_update_proof_pi_c": as_bytes_hex(bridge_raw["tx_set_update_proof"]["piC"]),
    }
    return bridge_args


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("genesis_out", type=Path)
    parser.add_argument("bridge_out", type=Path)
    parser.add_argument("user_address")
    parser.add_argument("tx_snapshot_phase2_hash")
    parser.add_argument("tx_snapshot_receipt_statement_hash")
    parser.add_argument("stake_distribution_standard_hash")
    parser.add_argument("locking_updater_unique_mint_utxo")
    parser.add_argument("bridge_source_utxo")
    parser.add_argument("--proof-export-bundle", type=Path, default=None)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    genesis_out = args.genesis_out
    bridge_out = args.bridge_out
    inputs = load_bridge_minting_inputs(
        user_address=args.user_address,
        tx_snapshot_phase2_hash=args.tx_snapshot_phase2_hash,
        tx_snapshot_receipt_statement_hash=args.tx_snapshot_receipt_statement_hash,
        stake_distribution_standard_hash=args.stake_distribution_standard_hash,
        locking_updater_unique_mint_utxo=args.locking_updater_unique_mint_utxo,
        bridge_source_utxo=args.bridge_source_utxo,
        proof_export_bundle_path=args.proof_export_bundle,
    )

    write_json(genesis_out, build_genesis_args(inputs))
    write_json(bridge_out, build_bridge_args(inputs))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
