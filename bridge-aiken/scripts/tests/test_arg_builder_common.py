import sys
import unittest
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT_DIR / "python"))

from arg_builder_common import parse_env_policy_const, parse_env_text_const


class ArgBuilderCommonTest(unittest.TestCase):
    def test_parse_env_text_const_accepts_inline_and_multiline_literals(self) -> None:
        inline = 'pub const transferred_asset_name: ByteArray = "token_asset_name"\n'
        multiline = 'pub const transferred_asset_name: ByteArray =\n  "token_asset_name"\n'

        self.assertEqual(
            parse_env_text_const(inline, "transferred_asset_name"),
            "token_asset_name",
        )
        self.assertEqual(
            parse_env_text_const(multiline, "transferred_asset_name"),
            "token_asset_name",
        )

    def test_parse_env_policy_const_accepts_inline_and_multiline_literals(self) -> None:
        inline = (
            'pub const bridge_minting_policy_id: PolicyId = '
            '#"9cfe5407375903c8b063f255859299aa499bfe674bea18b5f4353f0f"\n'
        )
        multiline = (
            'pub const bridge_minting_policy_id: PolicyId =\n'
            '  #"9cfe5407375903c8b063f255859299aa499bfe674bea18b5f4353f0f"\n'
        )

        self.assertEqual(
            parse_env_policy_const(inline, "bridge_minting_policy_id"),
            "9cfe5407375903c8b063f255859299aa499bfe674bea18b5f4353f0f",
        )
        self.assertEqual(
            parse_env_policy_const(multiline, "bridge_minting_policy_id"),
            "9cfe5407375903c8b063f255859299aa499bfe674bea18b5f4353f0f",
        )


if __name__ == "__main__":
    unittest.main()
