import hashlib
import json
import re
import shutil
import subprocess
import unittest
from pathlib import Path

import cbor2


WORKSPACE_ROOT = Path(__file__).resolve().parents[3]
BRIDGE_ROOT = Path(__file__).resolve().parents[2]
OPERATOR_ROOT = WORKSPACE_ROOT / "zk-bridge-operator"


def blake2b224(data: bytes) -> str:
    return hashlib.blake2b(data, digest_size=28).hexdigest()


def load_phase1_validator() -> dict:
    plutus = json.loads((BRIDGE_ROOT / "plutus.json").read_text())
    return next(
        validator
        for validator in plutus["validators"]
        if validator["title"] == "phase1.phase1.mint"
    )


def load_publish_phase1_script_from_main_tx3() -> bytes:
    text = (BRIDGE_ROOT / "main.tx3").read_text()
    match = re.search(
        r"tx publish_phase1_reference_script.*?script: 0x([0-9a-f]+),",
        text,
        re.S,
    )
    if match is None:
        raise AssertionError("main.tx3 is missing publish_phase1_reference_script")
    return bytes.fromhex(match.group(1))


def load_publish_phase1_reference_script_payload() -> bytes:
    envelope_path = (
        OPERATOR_ROOT
        / "preview_phase12"
        / "publish-phase1-reference-script"
        / "tx-envelope.json"
    )
    envelope = json.loads(envelope_path.read_text())
    tx = cbor2.loads(bytes.fromhex(envelope["tx"]))
    outputs = tx[0][1]
    script_output = next(
        output for output in outputs if isinstance(output, dict) and 3 in output
    )
    script_ref = script_output[3]
    if not isinstance(script_ref, cbor2.CBORTag):
        raise AssertionError("expected the published reference script to be a CBOR tag")
    return script_ref.value
def load_publish_phase1_script_from_trix_tir() -> bytes:
    if shutil.which("trix") is None:
        raise unittest.SkipTest("trix is not installed")

    result = subprocess.run(
        ["trix", "inspect", "tir", "--tx", "publish_phase1_reference_script", "-v"],
        cwd=BRIDGE_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    raw = result.stdout + result.stderr
    start = raw.find("{")
    end = raw.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise AssertionError("trix inspect tir did not emit a JSON payload")

    tir = json.loads(raw[start : end + 1])
    script_bytes = tir["adhoc"][0]["data"]["script"]["Bytes"]
    return bytes(script_bytes)


class PublishPhase1ReferenceScriptTests(unittest.TestCase):
    def test_main_tx3_publish_script_matches_plutus_compiled_code(self) -> None:
        phase1 = load_phase1_validator()
        compiled_code = bytes.fromhex(phase1["compiledCode"])

        self.assertEqual(
            load_publish_phase1_script_from_main_tx3(),
            compiled_code,
            "main.tx3 should embed the exact compiledCode from plutus.json",
        )

    def test_phase1_hash_still_matches_the_wrapped_compiled_code_contract(self) -> None:
        phase1 = load_phase1_validator()
        compiled_code = bytes.fromhex(phase1["compiledCode"])

        expected_phase1_hash = blake2b224(bytes([3]) + compiled_code)
        self.assertEqual(expected_phase1_hash, phase1["hash"])

    def test_trix_tir_keeps_the_raw_compiled_code(self) -> None:
        phase1 = load_phase1_validator()
        compiled_code = bytes.fromhex(phase1["compiledCode"])
        tir_script = load_publish_phase1_script_from_trix_tir()

        self.assertEqual(
            tir_script,
            compiled_code,
            "trix TIR should pass the raw compiledCode bytes into cardano_publish",
        )

    def test_checked_in_preview_publish_artifact_still_documents_the_old_double_wrapped_shape(self) -> None:
        published_payload = load_publish_phase1_reference_script_payload()
        outer_payload = cbor2.loads(published_payload)

        self.assertIsInstance(outer_payload, list)
        self.assertEqual(outer_payload[0], 3)
        self.assertIsInstance(outer_payload[1], bytes)
        self.assertIsInstance(cbor2.loads(outer_payload[1]), bytes)
        self.assertNotEqual(
            blake2b224(bytes([3]) + outer_payload[1]),
            load_phase1_validator()["hash"],
            "the checked-in preview publish artifact should remain stale until it is"
            " regenerated from the current tree",
        )


if __name__ == "__main__":
    unittest.main()
