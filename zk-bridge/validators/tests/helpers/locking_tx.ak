use cardano/address.{Address, VerificationKey}
use cardano/transaction.{InlineDatum, Input, NoDatum, Output, Transaction}
use common_types.{LockingTxDatum}
use env
use tests/helpers/test_constants
use tests/helpers/values.{build_value_with_native_token}

pub fn simple_locking_tx() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: [
      Input {
        output_reference: test_constants.locked_assets_utxo_ref,
        output: Output {
          address: Address {
            payment_credential: VerificationKey(
              "my_verification_key_in_chain_A",
            ),
            stake_credential: None,
          },
          value: build_value_with_native_token(
            test_constants.bridge_locked_token_policy_id,
            test_constants.bridge_locked_token_asset_name,
            1,
          ),
          datum: NoDatum,
          reference_script: None,
        },
      },
    ],
    outputs: [locking_tx_output(1)],
  }
}

pub fn locking_tx_output(amount_of_assets: Int) {
  let locking_tx_datum =
    LockingTxDatum {
      bridge_id: "my_bridge_id",
      destination_address: VerificationKey("my_verification_key_in_chain_B"),
    }
  Output {
    address: Address {
      payment_credential: env.unlocked_funds_spending_script,
      stake_credential: None,
    },
    value: build_value_with_native_token(
      test_constants.bridge_locked_token_policy_id,
      test_constants.bridge_locked_token_asset_name,
      amount_of_assets,
    ),
    datum: InlineDatum(locking_tx_datum),
    reference_script: None,
  }
}
