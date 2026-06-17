import json
import re
from pathlib import Path


def as_bytes_hex(raw_hex: str) -> str:
    return "0x" + raw_hex


def ascii_bytes_hex(text: str) -> str:
    return "0x" + text.encode().hex()


def read_json(path: Path) -> dict:
    return json.loads(path.read_text())


def write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2))


def parse_env_const(env_text: str, name: str, type_name: str, literal_prefix: str) -> str:
    pattern = re.compile(
        rf'pub const {re.escape(name)}:\s*{re.escape(type_name)}\s*=\s*'
        rf'{re.escape(literal_prefix)}"([^"]+)"'
    )
    match = pattern.search(env_text)
    if match is None:
        raise ValueError(
            f"Could not find env constant {name!r} with type {type_name!r}"
        )
    return match.group(1)


def parse_env_text_const(env_text: str, name: str) -> str:
    return parse_env_const(
        env_text=env_text,
        name=name,
        type_name="ByteArray",
        literal_prefix="",
    )


def parse_env_policy_const(env_text: str, name: str) -> str:
    return parse_env_const(
        env_text=env_text,
        name=name,
        type_name="PolicyId",
        literal_prefix="#",
    )
