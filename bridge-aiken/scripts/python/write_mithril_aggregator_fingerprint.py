#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import shlex
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import urlopen

DEFAULT_AGGREGATOR_ENDPOINT = (
    "https://aggregator.pre-release-preview.api.mithril.network/aggregator"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("output_json", type=Path)
    parser.add_argument(
        "--aggregator-endpoint",
        default=os.environ.get(
            "MITHRIL_AGGREGATOR_ENDPOINT", DEFAULT_AGGREGATOR_ENDPOINT
        ),
    )
    return parser.parse_args()


def fetch_json(url: str) -> dict:
    with urlopen(url) as response:
        return json.load(response)


def shell_assignment(name: str, value: str) -> str:
    return f"{name}={shlex.quote(value)}"


def main() -> int:
    args = parse_args()
    features = fetch_json(f"{args.aggregator_endpoint}/")
    status = fetch_json(f"{args.aggregator_endpoint}/status")

    capabilities = features.get("capabilities", {})
    signed_entity_types = capabilities.get("signed_entity_types", [])
    prover = capabilities.get("cardano_transactions_prover", {})

    payload = {
        "aggregator_endpoint": args.aggregator_endpoint,
        "fetched_at_utc": datetime.now(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "open_api_version": features.get("open_api_version"),
        "documentation_url": features.get("documentation_url"),
        "signed_entity_types": signed_entity_types,
        "aggregate_signature_type": capabilities.get("aggregate_signature_type"),
        "max_hashes_allowed_by_request": prover.get("max_hashes_allowed_by_request"),
        "epoch": status.get("epoch"),
        "cardano_network": status.get("cardano_network"),
        "cardano_era": status.get("cardano_era"),
        "mithril_era": status.get("mithril_era"),
        "cardano_node_version": status.get("cardano_node_version"),
        "aggregator_node_version": status.get("aggregator_node_version"),
        "protocol": status.get("protocol"),
        "next_protocol": status.get("next_protocol"),
        "total_signers": status.get("total_signers"),
        "total_next_signers": status.get("total_next_signers"),
        "total_stakes_signers": status.get("total_stakes_signers"),
        "total_next_stakes_signers": status.get("total_next_stakes_signers"),
        "total_cardano_spo": status.get("total_cardano_spo"),
        "total_cardano_stake": status.get("total_cardano_stake"),
        "features": features,
        "status": status,
    }

    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(json.dumps(payload, indent=2) + "\n")

    env_lines = [
        shell_assignment(
            "MITHRIL_AGGREGATOR_FINGERPRINT_PATH", str(args.output_json)
        ),
        shell_assignment("MITHRIL_AGGREGATOR_ENDPOINT", payload["aggregator_endpoint"]),
        shell_assignment(
            "MITHRIL_AGGREGATOR_FETCHED_AT_UTC", payload["fetched_at_utc"]
        ),
        shell_assignment(
            "MITHRIL_AGGREGATOR_OPEN_API_VERSION",
            str(payload["open_api_version"] or ""),
        ),
        shell_assignment(
            "MITHRIL_AGGREGATOR_DOCUMENTATION_URL",
            str(payload["documentation_url"] or ""),
        ),
        shell_assignment("MITHRIL_AGGREGATOR_EPOCH", str(payload["epoch"] or "")),
        shell_assignment(
            "MITHRIL_AGGREGATOR_CARDANO_NETWORK",
            str(payload["cardano_network"] or ""),
        ),
        shell_assignment(
            "MITHRIL_AGGREGATOR_CARDANO_ERA", str(payload["cardano_era"] or "")
        ),
        shell_assignment(
            "MITHRIL_AGGREGATOR_MITHRIL_ERA", str(payload["mithril_era"] or "")
        ),
        shell_assignment(
            "MITHRIL_AGGREGATOR_CARDANO_NODE_VERSION",
            str(payload["cardano_node_version"] or ""),
        ),
        shell_assignment(
            "MITHRIL_AGGREGATOR_NODE_VERSION",
            str(payload["aggregator_node_version"] or ""),
        ),
        shell_assignment(
            "MITHRIL_AGGREGATOR_PROTOCOL_JSON",
            json.dumps(payload["protocol"] or {}, separators=(",", ":")),
        ),
        shell_assignment(
            "MITHRIL_AGGREGATOR_NEXT_PROTOCOL_JSON",
            json.dumps(payload["next_protocol"] or {}, separators=(",", ":")),
        ),
        shell_assignment(
            "MITHRIL_AGGREGATOR_TOTAL_SIGNERS",
            str(payload["total_signers"] or ""),
        ),
        shell_assignment(
            "MITHRIL_AGGREGATOR_TOTAL_NEXT_SIGNERS",
            str(payload["total_next_signers"] or ""),
        ),
        shell_assignment(
            "MITHRIL_AGGREGATOR_TOTAL_STAKES_SIGNERS",
            str(payload["total_stakes_signers"] or ""),
        ),
        shell_assignment(
            "MITHRIL_AGGREGATOR_TOTAL_NEXT_STAKES_SIGNERS",
            str(payload["total_next_stakes_signers"] or ""),
        ),
        shell_assignment(
            "MITHRIL_AGGREGATOR_TOTAL_CARDANO_SPO",
            str(payload["total_cardano_spo"] or ""),
        ),
        shell_assignment(
            "MITHRIL_AGGREGATOR_TOTAL_CARDANO_STAKE",
            str(payload["total_cardano_stake"] or ""),
        ),
        shell_assignment(
            "MITHRIL_AGGREGATOR_SIGNED_ENTITY_TYPES",
            ",".join(str(item) for item in signed_entity_types),
        ),
        shell_assignment(
            "MITHRIL_AGGREGATOR_SIGNED_ENTITY_TYPES_JSON",
            json.dumps(signed_entity_types, separators=(",", ":")),
        ),
        shell_assignment(
            "MITHRIL_AGGREGATOR_AGGREGATE_SIGNATURE_TYPE",
            str(payload["aggregate_signature_type"] or ""),
        ),
        shell_assignment(
            "MITHRIL_AGGREGATOR_MAX_HASHES_ALLOWED_BY_REQUEST",
            str(payload["max_hashes_allowed_by_request"] or ""),
        ),
    ]
    print("\n".join(env_lines))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
