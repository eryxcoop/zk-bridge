#!/usr/bin/env python3

import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Optional

ROOT_DIR = Path(__file__).resolve().parents[2]
DOLOS_MANIFEST = ROOT_DIR.parent / "dolos" / "Cargo.toml"


def sort_key(entry):
    txid, index = entry
    return (txid.hex(), index)


def lovelace_amount(output):
    amount = output[1]
    if isinstance(amount, int):
        return amount
    return int(amount[0])


def simple_output_address(outputs):
    for output in outputs:
        if isinstance(output, dict) and 0 in output and 1 in output and 2 not in output:
            return output[0]
    return None


def strip_datum(output):
    if not isinstance(output, dict):
        return output
    sanitized = dict(output)
    sanitized.pop(2, None)
    return sanitized


def simulate(tx_path: Path, inputs_path: Path, outputs_path: Path) -> str:
    return subprocess.check_output(
        ["aiken", "tx", "simulate", str(tx_path), str(inputs_path), str(outputs_path)],
        text=True,
        stderr=subprocess.STDOUT,
    )


def dolos_grpc_endpoint(result_path: Path) -> Optional[str]:
    store_path = result_path.parent / "cshell.toml"
    if not store_path.exists():
        return None

    text = store_path.read_text()
    match = re.search(r'url = "http://localhost:(\d+)/u5c"', text)
    if match is None:
        return None

    return f"http://127.0.0.1:{match.group(1)}"


def eval_with_dolos(result_path: Path) -> Optional[dict]:
    endpoint = dolos_grpc_endpoint(result_path)
    if endpoint is None:
        return None

    if not DOLOS_MANIFEST.exists():
        return None

    try:
        raw = subprocess.check_output(
            [
                "cargo",
                "run",
                "--manifest-path",
                str(DOLOS_MANIFEST),
                "--bin",
                "tx_eval_report",
                "--",
                endpoint,
                str(result_path),
            ],
            text=True,
            stderr=subprocess.STDOUT,
        )
    except subprocess.CalledProcessError:
        return None

    lines = [line.strip() for line in raw.splitlines() if line.strip()]
    if not lines:
        return None

    try:
        report = json.loads(lines[-1])
    except Exception:
        return None

    if report.get("errors"):
        return None

    return {
        "cpu": int(report["cpu"]),
        "memory": int(report["memory"]),
    }


def probe_phase2_runtime() -> Optional[dict]:
    try:
        raw = subprocess.check_output(
            ["aiken", "check", "-m", "tests/phase2_runtime_probe_test"],
            text=True,
            stderr=subprocess.STDOUT,
            cwd=ROOT_DIR,
        )
    except subprocess.CalledProcessError:
        return None

    start = raw.find("{")
    if start == -1:
        return None

    try:
        payload = json.loads(raw[start:])
        test = payload["modules"][0]["tests"][0]
        units = test["execution_units"]
        return {"cpu": int(units["cpu"]), "memory": int(units["mem"])}
    except Exception:
        return None


def probe_bridge_mint(result_path: Path) -> Optional[dict]:
    skip_json = result_path.parent / "bridge-mint-skip.json"
    resolved_input_candidates = [
        result_path.with_suffix(".resolved_inputs"),
        result_path.parent / "bridge-mint-skip.resolved_inputs",
    ]
    resolved_inputs = next(
        (path for path in resolved_input_candidates if path.exists()),
        None,
    )
    if not skip_json.exists() or resolved_inputs is None or not DOLOS_MANIFEST.exists():
        return None

    try:
        raw = subprocess.check_output(
            [
                "cargo",
                "run",
                "--manifest-path",
                str(DOLOS_MANIFEST),
                "--bin",
                "phase2_mint_probe",
                "--",
                str(skip_json),
                str(resolved_inputs),
            ],
            text=True,
            stderr=subprocess.STDOUT,
            cwd=ROOT_DIR,
        )
    except subprocess.CalledProcessError:
        return None

    cpu_match = re.search(r"consumed_budget=\{mem:(\d+),cpu:(\d+)\}", raw)
    if cpu_match is None:
        return None

    return {
        "memory": int(cpu_match.group(1)),
        "cpu": int(cpu_match.group(2)),
    }


def probe_phase1_mint(result_path: Path) -> Optional[dict]:
    resolved_inputs = result_path.with_suffix(".resolved_inputs")
    if not resolved_inputs.exists() or not DOLOS_MANIFEST.exists():
        return None

    try:
        raw = subprocess.check_output(
            [
                "cargo",
                "run",
                "--manifest-path",
                str(DOLOS_MANIFEST),
                "--bin",
                "phase2_mint_probe",
                "--",
                str(result_path),
                str(resolved_inputs),
            ],
            text=True,
            stderr=subprocess.STDOUT,
            cwd=ROOT_DIR,
        )
    except subprocess.CalledProcessError:
        return None

    cpu_match = re.search(r"consumed_budget=\{mem:(\d+),cpu:(\d+)\}", raw)
    if cpu_match is None:
        return None

    return {
        "memory": int(cpu_match.group(1)),
        "cpu": int(cpu_match.group(2)),
    }


def collect_summary(
    label: str,
    result_path: Path,
    fallback_reference_lovelace: int,
    previous_result_paths: list[Path],
) -> dict:
    result = json.loads(result_path.read_text())
    tx_size = len(bytes.fromhex(result["cbor"]))
    summary = {
        "label": label,
        "hash": result["hash"],
        "tx_size": tx_size,
        "cpu": None,
        "memory": None,
    }

    try:
        import cbor2
    except Exception:
        return summary

    try:
        tx_bytes = bytes.fromhex(result["cbor"])
        tx = cbor2.loads(tx_bytes)
        body = tx[0]

        known_outputs = {}
        for previous_path in previous_result_paths:
            if not previous_path.exists():
                continue
            previous_result = json.loads(previous_path.read_text())
            previous_tx = cbor2.loads(bytes.fromhex(previous_result["cbor"]))
            known_outputs[bytes.fromhex(previous_result["hash"])] = previous_tx[0][1]

        user_address = simple_output_address(body[1])
        if user_address is None:
            for outputs in known_outputs.values():
                user_address = simple_output_address(outputs)
                if user_address is not None:
                    break

        normal_inputs = sorted((list(entry) for entry in body.get(0, set())), key=sort_key)
        reference_inputs = sorted(
            (list(entry) for entry in body.get(18, set())),
            key=sort_key,
        )
        sim_inputs = normal_inputs + reference_inputs

        resolved_outputs = []
        for txid, index in sim_inputs:
            outputs = known_outputs.get(txid)
            if outputs is not None and index < len(outputs):
                resolved_outputs.append(outputs[index])
                continue

            if label == "phase1_setup":
                input_amount = int(body[2]) + sum(
                    lovelace_amount(output) for output in body[1]
                )
                resolved_outputs.append({0: user_address, 1: input_amount})
                continue

            if user_address is not None and index == 0:
                resolved_outputs.append({0: user_address, 1: fallback_reference_lovelace})
                continue

            raise RuntimeError(f"missing resolved output for {txid.hex()}#{index}")

        tx_path = result_path.with_suffix(".tx")
        inputs_path = result_path.with_suffix(".sim_inputs")
        outputs_path = result_path.with_suffix(".resolved_inputs")
        tx_path.write_text(result["cbor"])
        inputs_path.write_text(cbor2.dumps(sim_inputs).hex())
        outputs_path.write_text(cbor2.dumps(resolved_outputs).hex())

        try:
            raw = simulate(tx_path, inputs_path, outputs_path)
        except subprocess.CalledProcessError as err:
            if label != "bridge_mint_tx":
                raise

            candidate_outputs = []
            candidate_outputs.append([strip_datum(output) for output in resolved_outputs])
            for index, output in enumerate(resolved_outputs):
                if not isinstance(output, dict) or 2 not in output:
                    continue
                variant = list(resolved_outputs)
                variant[index] = strip_datum(output)
                candidate_outputs.append(variant)

            raw = None
            for candidate in candidate_outputs:
                outputs_path.write_text(cbor2.dumps(candidate).hex())
                try:
                    raw = simulate(tx_path, inputs_path, outputs_path)
                    break
                except subprocess.CalledProcessError:
                    continue

            if raw is None:
                raise err

        start = raw.rfind("\n[")
        if start != -1:
            start += 1
        else:
            start = raw.find("[")
        if start == -1:
            raise RuntimeError("aiken simulation output did not contain JSON budgets")
        budgets = json.loads(raw[start:])
        summary["cpu"] = sum(int(item["cpu"]) for item in budgets)
        summary["memory"] = sum(int(item["mem"]) for item in budgets)
    except Exception:
        fallback = eval_with_dolos(result_path)
        if fallback is None and (
            label == "phase2_verify" or label.startswith("phase2_verify_")
        ):
            fallback = probe_phase2_runtime()
        if fallback is None and label.startswith("phase1_setup"):
            fallback = probe_phase1_mint(result_path)
        if fallback is None and label == "bridge_mint_tx":
            fallback = probe_bridge_mint(result_path)
        if fallback is None:
            return summary
        summary["cpu"] = fallback["cpu"]
        summary["memory"] = fallback["memory"]
        return summary

    return summary


def main() -> int:
    if len(sys.argv) < 4:
        raise SystemExit(
            "usage: tx_publish_summary.py <label> <result-json> <fallback-reference-lovelace> [previous-result-json ...]"
        )

    label = sys.argv[1]
    result_path = Path(sys.argv[2])
    fallback_reference_lovelace = int(sys.argv[3])
    previous_result_paths = [Path(arg) for arg in sys.argv[4:]]

    summary = collect_summary(
        label,
        result_path,
        fallback_reference_lovelace,
        previous_result_paths,
    )

    print(f"{label} txSize: {summary['tx_size']} bytes")
    if summary["cpu"] is None:
        print(f"{label} aiken cpu: unavailable")
    else:
        print(f"{label} aiken cpu: {summary['cpu']}")

    if summary["memory"] is None:
        print(f"{label} aiken memory: unavailable")
    else:
        print(f"{label} aiken memory: {summary['memory']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
