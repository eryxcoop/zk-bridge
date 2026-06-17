#!/usr/bin/env python3

import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Replacement:
    pattern: str
    repl: str
    label: str
    flags: int = 0


@dataclass(frozen=True)
class MatchCheck:
    pattern: str
    label: str
    flags: int = 0


def replace_once(text: str, pattern: str, repl: str, label: str, *, flags: int = 0) -> str:
    new_text, count = re.subn(pattern, repl, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f"Failed to update {label}")
    return new_text


def apply_replacements(text: str, replacements: list[Replacement]) -> str:
    for replacement in replacements:
        text = replace_once(
            text,
            replacement.pattern,
            replacement.repl,
            replacement.label,
            flags=replacement.flags,
        )
    return text


def require_match(text: str, pattern: str, label: str, *, flags: int = 0) -> None:
    if re.search(pattern, text, flags=flags) is None:
        raise SystemExit(f"Verification failed for {label}")


def require_matches(text: str, checks: list[MatchCheck]) -> None:
    for check in checks:
        require_match(text, check.pattern, check.label, flags=check.flags)


def parse_env_bytearray_const(env_text: str, name: str) -> str:
    match = re.search(
        rf'pub const {re.escape(name)}: ByteArray =\s*(?:"([^"]+)"|#"([0-9a-f]+)")',
        env_text,
    )
    if not match:
        raise SystemExit(f"Failed to locate {name} in env/default.ak")
    text_value, hex_value = match.groups()
    if hex_value is not None:
        return hex_value
    return text_value.encode().hex()



def main() -> int:
    if len(sys.argv) != 10:
        raise SystemExit(
            "usage: sync_phase_scripts_to_tx3.py <plutus-json> <applied-phase2-plutus-json> <applied-stake-mint-plutus-json> <applied-stake-spend-plutus-json> <applied-locking-txs-updater-mint-plutus-json> <applied-locking-txs-updater-spend-plutus-json> <applied-bridge-minting-plutus-json> <main-tx3> <env-default>"
        )

    plutus_path = Path(sys.argv[1])
    applied_phase2_plutus_path = Path(sys.argv[2])
    applied_stake_plutus_path = Path(sys.argv[3])
    applied_stake_spend_plutus_path = Path(sys.argv[4])
    applied_locking_txs_updater_plutus_path = Path(sys.argv[5])
    applied_locking_txs_updater_spend_plutus_path = Path(sys.argv[6])
    applied_bridge_minting_plutus_path = Path(sys.argv[7])
    main_tx3_path = Path(sys.argv[8])
    env_default_path = Path(sys.argv[9])

    plutus = json.loads(plutus_path.read_text())
    validators = {entry["title"]: entry for entry in plutus["validators"]}
    applied_phase2_plutus = json.loads(applied_phase2_plutus_path.read_text())
    applied_phase2_validators = {
        entry["title"]: entry for entry in applied_phase2_plutus["validators"]
    }
    applied_stake_plutus = json.loads(applied_stake_plutus_path.read_text())
    applied_stake_validators = {
        entry["title"]: entry for entry in applied_stake_plutus["validators"]
    }
    applied_stake_spend_plutus = json.loads(applied_stake_spend_plutus_path.read_text())
    applied_stake_spend_validators = {
        entry["title"]: entry for entry in applied_stake_spend_plutus["validators"]
    }
    applied_locking_txs_updater_plutus = json.loads(
        applied_locking_txs_updater_plutus_path.read_text()
    )
    applied_locking_txs_updater_validators = {
        entry["title"]: entry
        for entry in applied_locking_txs_updater_plutus["validators"]
    }
    applied_locking_txs_updater_spend_plutus = json.loads(
        applied_locking_txs_updater_spend_plutus_path.read_text()
    )
    applied_locking_txs_updater_spend_validators = {
        entry["title"]: entry
        for entry in applied_locking_txs_updater_spend_plutus["validators"]
    }
    applied_bridge_minting_plutus = json.loads(
        applied_bridge_minting_plutus_path.read_text()
    )
    applied_bridge_minting_validators = {
        entry["title"]: entry for entry in applied_bridge_minting_plutus["validators"]
    }
    scope = os.environ.get("SYNC_SCOPE", "all")
    valid_scopes = {"all", "phase12", "stake_distribution", "bridge"}
    if scope not in valid_scopes:
        raise SystemExit(f"Unsupported SYNC_SCOPE={scope!r}; expected one of {sorted(valid_scopes)}")

    sync_phase12 = scope in {"all", "phase12"}
    sync_stake_distribution = scope in {"all", "stake_distribution"}
    sync_bridge = scope in {"all", "bridge"}

    bridge_minting_title = os.environ.get(
        "BRIDGE_MINTING_VALIDATOR_TITLE",
        "minting.minting_validator.mint",
    )

    required_titles = [
        "phase1.phase1.mint",
        "proof_receipt.proof_receipt_validator.spend",
        bridge_minting_title,
        "stake_distribution.stake_distribution_validator_mint.mint",
        "stake_distribution.stake_distribution_validator_spend.spend",
        "txs_updater_minting.txs_updater_minting_validator_spend.spend",
    ]
    missing = [title for title in required_titles if title not in validators]
    if missing:
        raise SystemExit(f"Missing validators in {plutus_path}: {', '.join(missing)}")

    phase1 = validators["phase1.phase1.mint"]
    proof_receipt = validators["proof_receipt.proof_receipt_validator.spend"]
    phase2_spend = applied_phase2_validators["phase2.phase2.spend"]
    phase2_mint = applied_phase2_validators["phase2.phase2.mint"]
    minting = applied_bridge_minting_validators[bridge_minting_title]
    stake_distribution_mint = applied_stake_validators[
        "stake_distribution.stake_distribution_validator_mint.mint"
    ]
    stake_distribution_spend = applied_stake_spend_validators[
        "stake_distribution.stake_distribution_validator_spend.spend"
    ]
    locking_txs_updater_mint = applied_locking_txs_updater_validators[
        "txs_updater_common.txs_updater_validator_mint.mint"
    ]
    locking_txs_updater_spend = applied_locking_txs_updater_spend_validators[
        "txs_updater_minting.txs_updater_minting_validator_spend.spend"
    ]

    if phase2_spend["hash"] != phase2_mint["hash"]:
        raise SystemExit("phase2 spend/mint hashes diverged; refusing to sync")

    if phase2_spend["compiledCode"] != phase2_mint["compiledCode"]:
        raise SystemExit("phase2 spend/mint compiledCode diverged; refusing to sync")

    text = main_tx3_path.read_text()
    env_text = env_default_path.read_text()

    if sync_phase12:
        text = apply_replacements(
            text,
            [
                Replacement(
                    r"policy Phase1 = 0x[0-9a-f]+;",
                    f"policy Phase1 = 0x{phase1['hash']};",
                    "policy Phase1",
                ),
                Replacement(
                    r"policy Phase2 = 0x[0-9a-f]+;",
                    f"policy Phase2 = 0x{phase2_spend['hash']};",
                    "policy Phase2",
                ),
                Replacement(
                    r"policy ProofReceipt = 0x[0-9a-f]+;",
                    f"policy ProofReceipt = 0x{proof_receipt['hash']};",
                    "policy ProofReceipt",
                ),
                Replacement(
                    r"(tx publish_phase1_reference_script.*?cardano::publish \{\s*to: User,\s*amount: Ada\(reference_script_lovelace\),\s*version: 3,\s*script: )0x[0-9a-f]+(,\s*\n  \}\s*\n)",
                    rf"\g<1>0x{phase1['compiledCode']}\2",
                    "publish_phase1_reference_script script",
                    re.S,
                ),
                Replacement(
                    r"phase1_nft: AnyAsset\(0x[0-9a-f]+, phase1_state_reduced_hash, 1\),",
                    f"phase1_nft: AnyAsset(0x{phase1['hash']}, phase1_state_reduced_hash, 1),",
                    "phase1_setup phase1_nft",
                ),
                Replacement(
                    r"phase2_policy_id: 0x[0-9a-f]+,",
                    f"phase2_policy_id: 0x{phase2_spend['hash']},",
                    "phase1_setup phase2_policy_id",
                ),
                Replacement(
                    r"phase1_nft: AnyAsset\(0x[0-9a-f]+, token_name, 1\),",
                    f"phase1_nft: AnyAsset(0x{phase1['hash']}, token_name, 1),",
                    "phase2_verify phase1_nft",
                ),
                Replacement(
                    r"phase2_nft: AnyAsset\(0x[0-9a-f]+, token_name, 1\),",
                    f"phase2_nft: AnyAsset(0x{phase2_spend['hash']}, token_name, 1),",
                    "phase2_verify phase2_nft",
                ),
                Replacement(
                    r"(tx phase2_verify.*?cardano::plutus_witness \{\s*version: 3,\s*script: )0x[0-9a-f]+(,\s*\n  \}\s*\n\})",
                    rf"\g<1>0x{phase2_spend['compiledCode']}\2",
                    "phase2_verify witness",
                    re.S,
                ),
            ],
        )
        env_text = apply_replacements(
            env_text,
            [
                Replacement(
                    r'(pub const phase2_asset_policy_id: PolicyId =\s*\n\s*#")[0-9a-f]+(")',
                    rf"\g<1>{phase2_spend['hash']}\2",
                    "env phase2_asset_policy_id",
                ),
            ],
        )

    if sync_stake_distribution:
        text = apply_replacements(
            text,
            [
                Replacement(
                    r"policy StakeDistributionMint = 0x[0-9a-f]+;",
                    f"policy StakeDistributionMint = 0x{stake_distribution_mint['hash']};",
                    "policy StakeDistributionMint",
                ),
                Replacement(
                    r"policy StakeDistributionSpend = 0x[0-9a-f]+;",
                    f"policy StakeDistributionSpend = 0x{stake_distribution_spend['hash']};",
                    "policy StakeDistributionSpend",
                ),
                Replacement(
                    r'asset StakeDistributionNFT =\s*\n\s*0x[0-9a-f]+\."stake_distribution_asset";',
                    f'asset StakeDistributionNFT =\n  0x{stake_distribution_mint["hash"]}."stake_distribution_asset";',
                    "asset StakeDistributionNFT",
                ),
                Replacement(
                    r"(tx stake_distribution_genesis_tx.*?cardano::plutus_witness \{\s*version: 3,\s*script: )0x[0-9a-f]+(,\s*\n  \}\s*\n\})",
                    rf"\g<1>0x{stake_distribution_mint['compiledCode']}\2",
                    "stake_distribution_genesis_tx witness",
                    re.S,
                ),
                Replacement(
                    r"(tx stake_distribution_dual_genesis_tx.*?cardano::plutus_witness \{\s*version: 3,\s*script: )0x[0-9a-f]+(,\s*\n  \}\s*\n\})",
                    rf"\g<1>0x{stake_distribution_mint['compiledCode']}\2",
                    "stake_distribution_dual_genesis_tx witness",
                    re.S,
                ),
                Replacement(
                    r"(tx stake_distribution_standard_tx.*?cardano::plutus_witness \{\s*version: 3,\s*script: )0x[0-9a-f]+(,\s*\n  \}\s*\n\s*cardano::plutus_witness \{)",
                    rf"\g<1>0x{stake_distribution_spend['compiledCode']}\2",
                    "stake_distribution_standard_tx witness",
                    re.S,
                ),
                Replacement(
                    r"(tx stake_distribution_standard_tx.*?cardano::plutus_witness \{\s*version: 3,\s*script: 0x[0-9a-f]+,\s*\n  \}\s*\n\n  cardano::plutus_witness \{\s*version: 3,\s*script: )0x[0-9a-f]+(,\s*\n  \}\s*\n\})",
                    rf"\g<1>0x{proof_receipt['compiledCode']}\2",
                    "stake_distribution_standard_tx proof_receipt witness",
                    re.S,
                ),
            ],
        )
        env_text = apply_replacements(
            env_text,
            [
                Replacement(
                    r'(pub const stake_distribution_spending_script: Credential =\s*\n\s*Script\(#")[0-9a-f]+("\))',
                    rf"\g<1>{stake_distribution_spend['hash']}\2",
                    "env stake_distribution_spending_script",
                ),
                Replacement(
                    r'(pub const stake_distribution_asset_policy_id: PolicyId =\s*\n\s*#")[0-9a-f]+(")',
                    rf"\g<1>{stake_distribution_mint['hash']}\2",
                    "env stake_distribution_asset_policy_id",
                ),
            ],
        )

    if sync_bridge:
        locking_txs_updater_initial_merkle_root_hex = parse_env_bytearray_const(
            env_text,
            "locking_txs_updater_initial_merkle_root",
        )
        text = apply_replacements(
            text,
            [
                Replacement(
                    r"policy BridgeMinting = 0x[0-9a-f]+;",
                    f"policy BridgeMinting = 0x{minting['hash']};",
                    "policy BridgeMinting",
                ),
                Replacement(
                    r"policy LockingTxsUpdaterMint = 0x[0-9a-f]+;",
                    f"policy LockingTxsUpdaterMint = 0x{locking_txs_updater_mint['hash']};",
                    "policy LockingTxsUpdaterMint",
                ),
                Replacement(
                    r"policy LockingTxsUpdaterSpend = 0x[0-9a-f]+;",
                    f"policy LockingTxsUpdaterSpend = 0x{locking_txs_updater_spend['hash']};",
                    "policy LockingTxsUpdaterSpend",
                ),
                Replacement(
                    r'asset LockingTxsUpdaterNFT =\s*\n\s*0x[0-9a-f]+\."TxsUpdaterNFT";',
                    f'asset LockingTxsUpdaterNFT =\n  0x{locking_txs_updater_mint["hash"]}."TxsUpdaterNFT";',
                    "asset LockingTxsUpdaterNFT",
                ),
                Replacement(
                    r'asset BridgedAsset =\s*\n\s*0x[0-9a-f]+\."token_asset_name";',
                    f'asset BridgedAsset =\n  0x{minting["hash"]}."token_asset_name";',
                    "asset BridgedAsset",
                ),
                Replacement(
                    r"(tx minting_txs_updater_seed_tx.*?empty_merkle_root: )0x[0-9a-f]+(,)",
                    rf"\g<1>0x{locking_txs_updater_initial_merkle_root_hex}\2",
                    "minting_txs_updater_seed_tx empty_merkle_root",
                    re.S,
                ),
                Replacement(
                    r"(tx minting_txs_updater_seed_tx.*?cardano::plutus_witness \{\s*version: 3,\s*script: )0x[0-9a-f]+(,\s*\n  \}\s*\n\})",
                    rf"\g<1>0x{locking_txs_updater_mint['compiledCode']}\2",
                    "minting_txs_updater_seed_tx witness",
                    re.S,
                ),
                Replacement(
                    r"(tx publish_minting_txs_updater_spend_reference_script.*?cardano::publish \{\s*to: User,\s*amount: Ada\(reference_script_lovelace\),\s*version: 3,\s*script: )0x[0-9a-f]+(,\s*\n  \}\s*\n)",
                    rf"\g<1>0x{locking_txs_updater_spend['compiledCode']}\2",
                    "publish_minting_txs_updater_spend_reference_script script",
                    re.S,
                ),
                Replacement(
                    r"(tx publish_bridge_minting_reference_script.*?cardano::publish \{\s*to: User,\s*amount: Ada\(reference_script_lovelace\),\s*version: 3,\s*script: )0x[0-9a-f]+(,\s*\n  \}\s*\n)",
                    rf"\g<1>0x{minting['compiledCode']}\2",
                    "publish_bridge_minting_reference_script script",
                    re.S,
                ),
                Replacement(
                    r"(tx bridge_mint_tx.*?cardano::plutus_witness \{\s*version: 3,\s*script: )0x[0-9a-f]+(,\s*\n  \}\s*\n\})",
                    rf"\g<1>0x{proof_receipt['compiledCode']}\2",
                    "bridge_mint_tx proof_receipt witness",
                    re.S,
                ),
            ],
        )
        env_text = apply_replacements(
            env_text,
            [
                Replacement(
                    r'(pub const locking_txs_updater_policy_id: PolicyId =\s*\n\s*#")[0-9a-f]+(")',
                    rf"\g<1>{locking_txs_updater_mint['hash']}\2",
                    "env locking_txs_updater_policy_id",
                ),
                Replacement(
                    r'(pub const locking_txs_updater_spending_script: Credential =\s*\n\s*Script\(#")[0-9a-f]+("\))',
                    rf"\g<1>{locking_txs_updater_spend['hash']}\2",
                    "env locking_txs_updater_spending_script",
                ),
                Replacement(
                    r'(pub const bridge_minting_policy_id: PolicyId =\s*#")[0-9a-f]+(")',
                    rf"\g<1>{minting['hash']}\2",
                    "env bridge_minting_policy_id",
                ),
                Replacement(
                    r'(pub const transferred_asset_policy_id: PolicyId =\s*#")[0-9a-f]+(")',
                    rf"\g<1>{minting['hash']}\2",
                    "env transferred_asset_policy_id",
                ),
            ],
        )

    main_tx3_path.write_text(text)
    env_default_path.write_text(env_text)

    verified_main = main_tx3_path.read_text()
    verified_env = env_default_path.read_text()
    if sync_bridge:
        require_matches(
            verified_main,
            [
                MatchCheck(
                    rf"policy BridgeMinting = 0x{minting['hash']};",
                    "main BridgeMinting policy",
                ),
                MatchCheck(
                    rf"policy LockingTxsUpdaterMint = 0x{locking_txs_updater_mint['hash']};",
                    "main LockingTxsUpdaterMint policy",
                ),
                MatchCheck(
                    rf"policy LockingTxsUpdaterSpend = 0x{locking_txs_updater_spend['hash']};",
                    "main LockingTxsUpdaterSpend policy",
                ),
                MatchCheck(
                    rf'asset BridgedAsset =\s*\n\s*0x{minting["hash"]}\."token_asset_name";',
                    "main BridgedAsset asset",
                    re.S,
                ),
                MatchCheck(
                    rf'asset LockingTxsUpdaterNFT =\s*\n\s*0x{locking_txs_updater_mint["hash"]}\."TxsUpdaterNFT";',
                    "main LockingTxsUpdaterNFT asset",
                    re.S,
                ),
                MatchCheck(
                    rf"tx minting_txs_updater_seed_tx.*?empty_merkle_root: 0x{locking_txs_updater_initial_merkle_root_hex},",
                    "main minting_txs_updater_seed_tx empty_merkle_root",
                    re.S,
                ),
                MatchCheck(
                    rf"tx publish_minting_txs_updater_spend_reference_script.*?cardano::publish \{{\s*to: User,\s*amount: Ada\(reference_script_lovelace\),\s*version: 3,\s*script: 0x{locking_txs_updater_spend['compiledCode']},\s*\n  \}}",
                    "main publish_minting_txs_updater_spend_reference_script",
                    re.S,
                ),
                MatchCheck(
                    rf"tx publish_bridge_minting_reference_script.*?cardano::publish \{{\s*to: User,\s*amount: Ada\(reference_script_lovelace\),\s*version: 3,\s*script: 0x{minting['compiledCode']},\s*\n  \}}",
                    "main publish_bridge_minting_reference_script",
                    re.S,
                ),
            ],
        )
        require_matches(
            verified_env,
            [
                MatchCheck(
                    rf'pub const locking_txs_updater_policy_id: PolicyId =\s*\n\s*#"{locking_txs_updater_mint["hash"]}"',
                    "env locking_txs_updater_policy_id",
                    re.S,
                ),
                MatchCheck(
                    rf'pub const locking_txs_updater_spending_script: Credential =\s*\n\s*Script\(#"{locking_txs_updater_spend["hash"]}"\)',
                    "env locking_txs_updater_spending_script",
                    re.S,
                ),
                MatchCheck(
                    rf'pub const bridge_minting_policy_id: PolicyId =\s*#"{minting["hash"]}"',
                    "env bridge_minting_policy_id",
                ),
                MatchCheck(
                    rf'pub const transferred_asset_policy_id: PolicyId =\s*#"{minting["hash"]}"',
                    "env transferred_asset_policy_id",
                ),
            ],
        )

    if sync_phase12:
        require_matches(
            verified_main,
            [
                MatchCheck(
                    rf"policy Phase1 = 0x{phase1['hash']};",
                    "main Phase1 policy",
                ),
                MatchCheck(
                    rf"policy Phase2 = 0x{phase2_spend['hash']};",
                    "main Phase2 policy",
                ),
                MatchCheck(
                    rf"policy ProofReceipt = 0x{proof_receipt['hash']};",
                    "main ProofReceipt policy",
                ),
            ],
        )
        require_matches(
            verified_env,
            [
                MatchCheck(
                    rf'pub const phase2_asset_policy_id: PolicyId =\s*\n\s*#"{phase2_spend["hash"]}"',
                    "env phase2_asset_policy_id",
                    re.S,
                ),
            ],
        )
        print(f"Phase1 hash: {phase1['hash']}")
        print(f"Phase2 hash: {phase2_spend['hash']}")
    if sync_stake_distribution:
        require_matches(
            verified_env,
            [
                MatchCheck(
                    rf'pub const stake_distribution_spending_script: Credential =\s*\n\s*Script\(#"{stake_distribution_spend["hash"]}"\)',
                    "env stake_distribution_spending_script",
                    re.S,
                ),
                MatchCheck(
                    rf'pub const stake_distribution_asset_policy_id: PolicyId =\s*\n\s*#"{stake_distribution_mint["hash"]}"',
                    "env stake_distribution_asset_policy_id",
                    re.S,
                ),
            ],
        )
        print(f"StakeDistribution mint hash: {stake_distribution_mint['hash']}")
        print(f"StakeDistribution spend hash: {stake_distribution_spend['hash']}")
    if sync_bridge:
        print(f"BridgeMinting hash: {minting['hash']}")
        print(f"LockingTxsUpdater mint hash: {locking_txs_updater_mint['hash']}")
        print(f"LockingTxsUpdater spend hash: {locking_txs_updater_spend['hash']}")
    print(f"Updated: {main_tx3_path}")
    print(f"Updated: {env_default_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
