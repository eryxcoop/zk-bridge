import json
import tempfile
import unittest
from pathlib import Path
from subprocess import CalledProcessError
from unittest import mock

import cbor2

from scripts.python import tx_publish_summary


def make_tx_hex() -> str:
    tx = [
        {
            1: [{0: b"addr", 1: 1}],
            2: 0,
        },
        True,
        True,
        None,
    ]
    return cbor2.dumps(tx).hex()


class CollectSummaryFallbackTests(unittest.TestCase):
    def test_namespaced_phase1_setup_uses_phase1_probe_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            result_path = Path(tmpdir) / "phase1-submit.json"
            result_path.write_text(
                json.dumps({"cbor": make_tx_hex(), "hash": "aa" * 32}),
                encoding="utf-8",
            )

            with (
                mock.patch.object(
                    tx_publish_summary,
                    "simulate",
                    side_effect=CalledProcessError(1, ["aiken"]),
                ),
                mock.patch.object(
                    tx_publish_summary, "eval_with_dolos", return_value=None
                ),
                mock.patch.object(
                    tx_publish_summary,
                    "probe_phase1_mint",
                    return_value={"cpu": 11, "memory": 22},
                ) as phase1_probe,
                mock.patch.object(
                    tx_publish_summary, "probe_bridge_mint", return_value=None
                ) as bridge_probe,
                mock.patch.object(
                    tx_publish_summary, "probe_phase2_runtime", return_value=None
                ) as phase2_probe,
            ):
                summary = tx_publish_summary.collect_summary(
                    "phase1_setup_cardano_transactions",
                    result_path,
                    10_000_000,
                    [],
                )

            self.assertEqual(summary["cpu"], 11)
            self.assertEqual(summary["memory"], 22)
            phase1_probe.assert_called_once_with(result_path)
            bridge_probe.assert_not_called()
            phase2_probe.assert_not_called()


if __name__ == "__main__":
    unittest.main()
