#!/usr/bin/env python3

from __future__ import annotations

import sys
from pathlib import Path

from arg_builder_common import read_json, write_json
from stm_statement_digest import canonical_statement_hash, required_child


PHASE1_COMPAT_FIELDS = {
    "proof_bytes": "proof_bytes",
    "public_input_1": "public_input_1",
    "public_input_2": "public_input_2",
    "phase1_state_rhs_prefix": "phase1_state_rhs_prefix",
    "phase1_state_reduced_hash": "phase1_state_reduced_hash",
    "phase1_state_x1": "phase1_state_x1",
    "phase1_state_x3": "phase1_state_x3",
    "phase1_state_x4": "phase1_state_x4",
    "phase1_state_v": "phase1_state_v",
    "statement_hash_value": "statement_hash_value",
}

PHASE2_COMPAT_FIELDS = {
    "token_name": "token_name",
    "proof_receipt_statement_hash": "proof_receipt_statement_hash",
    "reduced_redeemer_vanishing_g": "reduced_redeemer_vanishing_g",
    "reduced_redeemer_vanishing_rand": "reduced_redeemer_vanishing_rand",
    "reduced_redeemer_a1": "reduced_redeemer_a1",
    "reduced_redeemer_a2": "reduced_redeemer_a2",
    "reduced_redeemer_a3": "reduced_redeemer_a3",
    "reduced_redeemer_perm_d": "reduced_redeemer_perm_d",
    "reduced_redeemer_lookup_1": "reduced_redeemer_lookup_1",
    "reduced_redeemer_lookup_2": "reduced_redeemer_lookup_2",
    "reduced_redeemer_perm_a": "reduced_redeemer_perm_a",
    "reduced_redeemer_perm_b": "reduced_redeemer_perm_b",
    "reduced_redeemer_perm_c": "reduced_redeemer_perm_c",
    "reduced_redeemer_perm_input_1": "reduced_redeemer_perm_input_1",
    "reduced_redeemer_perm_input_2": "reduced_redeemer_perm_input_2",
    "reduced_redeemer_f_commitment": "reduced_redeemer_f_commitment",
    "reduced_redeemer_pi_term": "reduced_redeemer_pi_term",
}

def build_phase12_args(
    bundle: dict,
    phase1_template: dict,
    phase2_template: dict,
    proof_name: str | None = None,
) -> tuple[dict, dict]:
    if proof_name is None:
        bridge_aiken = bundle.get("bridge_aiken")
        statement = bundle.get("statement")
        bridge_context = "bridge_aiken"
        statement_context = "statement"
    else:
        proofs = bundle.get("proofs")
        if not isinstance(proofs, dict):
            raise ValueError("missing proofs section in Mithril STM proof-export bundle")
        proof_entry = proofs.get(proof_name)
        if not isinstance(proof_entry, dict):
            raise ValueError(f"missing proofs.{proof_name} section in Mithril STM proof-export bundle")
        bridge_aiken = proof_entry.get("bridge_aiken")
        statement = proof_entry.get("statement")
        bridge_context = f"proofs.{proof_name}.bridge_aiken"
        statement_context = f"proofs.{proof_name}.statement"
    if not isinstance(bridge_aiken, dict):
        raise ValueError(f"missing {bridge_context} section in Mithril STM proof-export bundle")
    if not isinstance(statement, dict):
        raise ValueError(f"missing {statement_context} section in Mithril STM proof-export bundle")

    phase1_compat = bridge_aiken.get("phase1")
    phase2_compat = bridge_aiken.get("phase2")
    if not isinstance(phase1_compat, dict):
        raise ValueError(f"missing {bridge_context}.phase1 section in Mithril STM proof-export bundle")
    if not isinstance(phase2_compat, dict):
        raise ValueError(f"missing {bridge_context}.phase2 section in Mithril STM proof-export bundle")

    statement_hash = canonical_statement_hash(statement, statement_context)
    phase1_hash = required_child(
        phase1_compat,
        "statement_hash_value",
        f"{bridge_context}.phase1",
    )
    phase2_hash = required_child(
        phase2_compat,
        "proof_receipt_statement_hash",
        f"{bridge_context}.phase2",
    )
    if phase1_hash != statement_hash:
        raise ValueError(
            f"{bridge_context}.phase1.statement_hash_value must equal {statement_context}.statement_hash"
        )
    if phase2_hash != statement_hash:
        raise ValueError(
            f"{bridge_context}.phase2.proof_receipt_statement_hash must equal {statement_context}.statement_hash"
        )

    phase1_args = dict(phase1_template)
    phase2_args = dict(phase2_template)

    for output_field, compat_field in PHASE1_COMPAT_FIELDS.items():
        phase1_args[output_field] = required_child(
            phase1_compat,
            compat_field,
            f"{bridge_context}.phase1",
        )

    for output_field, compat_field in PHASE2_COMPAT_FIELDS.items():
        phase2_args[output_field] = required_child(
            phase2_compat,
            compat_field,
            f"{bridge_context}.phase2",
        )

    # This field is currently unused by Tx3, but keeping it aligned avoids
    # confusion when inspecting generated args.
    phase1_args["phase1_token_name"] = phase1_args["phase1_state_reduced_hash"]

    return phase1_args, phase2_args


def build_phase12_args_from_proof_export_bundle_file(
    bundle_path: Path,
    phase1_template_path: Path,
    phase2_template_path: Path,
    proof_name: str | None = None,
) -> tuple[dict, dict]:
    bundle = read_json(bundle_path)
    phase1_template = read_json(phase1_template_path)
    phase2_template = read_json(phase2_template_path)
    return build_phase12_args(bundle, phase1_template, phase2_template, proof_name)


def main() -> int:
    if len(sys.argv) not in {6, 7}:
        raise SystemExit(
            "usage: build_phase12_args_from_mithril_proof_export_bundle.py <proof-export-bundle-json> <phase1-template-json> <phase2-template-json> <phase1-out-json> <phase2-out-json> [proof-name]"
        )

    bundle_path = Path(sys.argv[1])
    phase1_template_path = Path(sys.argv[2])
    phase2_template_path = Path(sys.argv[3])
    phase1_out_path = Path(sys.argv[4])
    phase2_out_path = Path(sys.argv[5])
    proof_name = sys.argv[6] if len(sys.argv) == 7 else None

    phase1_args, phase2_args = build_phase12_args_from_proof_export_bundle_file(
        bundle_path,
        phase1_template_path,
        phase2_template_path,
        proof_name,
    )
    write_json(phase1_out_path, phase1_args)
    write_json(phase2_out_path, phase2_args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
