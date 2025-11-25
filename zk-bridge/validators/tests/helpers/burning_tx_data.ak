use ak_381/groth16.{Proof}
use cardano/address.{Address, VerificationKey}
use cardano/assets
use cardano/transaction.{Output, Transaction, TransactionId}
use common_types.{BurningTxData, ZK}
use tests/helpers/test_constants

pub fn valid_burning_proof() -> Proof {
  Proof {
    piA: #"85350182c43571b846bf45797a75d464638e3519cb2568ddf67225d02623cb5051355deb5f56d118c4aac5a0644b784d",
    piB: #"999da27b69ec440a8cfb2ab2ca3fd0a288a91d7e071d996288eddd9377ef4190c146bd5329e72693d1bb13a0208334eb0e962d51de9cb3f6719fe949aa6f1cf33d06a16afa6c81da463bd2034a4517c6f9261f304616dcabcf07af8063bf17c7",
    piC: #"93cbb04962cc51aa1aad3c440370a52b9b14242a54f62440571e129839bb8d6b0aa5973151f2b087d0d35dbbc37c6db7",
  }
}

pub fn invalid_burning_proof() -> Proof {
  Proof {
    piA: #"8eb4cba7e81626eb17c8ee8ec1b653ef2f7f12a512a143ea51085846e43a472c24aa9f8b28f05daf587f37b2f3c3a8e3",
    piB: #"923bc682560ab5811cea8a1e8d545eb17db61b400653b994a670c22c886bb0e3111e88662097d70a0a538131e333ab98033078661d0d5bb80aba07ad55c1d39b90bb63756af73d9a413d09e823743dfbe31e258fc881e967a541a804c8ed7312",
    piC: #"ace71f537ddb1fd1bc8c0b435ca4b3f5694b97deba29422b785a8cb64987650f0d2b2196ea3a97b2514a01a685c5b63b",
  }
}

pub fn valid_burning_tx_data_for_tx(
  unlocking_tx: Transaction,
) -> ZK<BurningTxData> {
  expect [_used_txs_output, unlocked_funds_output, ..] = unlocking_tx.outputs
  let Output { address: destination_address, value, .. } = unlocked_funds_output

  let amount_to_unlock =
    assets.quantity_of(
      value,
      test_constants.bridge_locked_token_policy_id,
      test_constants.bridge_locked_token_asset_name,
    )

  ZK {
    redeemer: BurningTxData {
      tx_id: test_constants.burning_transaction_id,
      transferred_amount: amount_to_unlock,
      transferred_asset_name: test_constants.bridge_locked_token_asset_name,
      transferred_asset_policy_id: test_constants.bridge_locked_token_policy_id,
      destination_address,
    },
    proofs: [valid_burning_proof()],
  }
}

pub fn valid_unlocking_redeemer(
  burning_tx_id: TransactionId,
  amount_to_unlock: Int,
  destination_address: Address,
) {
  ZK {
    redeemer: BurningTxData {
      tx_id: burning_tx_id,
      transferred_amount: amount_to_unlock,
      transferred_asset_name: test_constants.bridge_locked_token_asset_name,
      transferred_asset_policy_id: test_constants.bridge_locked_token_policy_id,
      destination_address,
    },
    proofs: [valid_burning_proof()],
  }
}

pub fn burning_tx_data_with_invalid_burning_proof() -> ZK<BurningTxData> {
  ZK {
    redeemer: BurningTxData {
      tx_id: test_constants.burning_transaction_id,
      transferred_amount: 3,
      transferred_asset_name: test_constants.bridge_locked_token_asset_name,
      transferred_asset_policy_id: test_constants.bridge_locked_token_policy_id,
      destination_address: test_constants.chain_a_destination_address,
    },
    proofs: [invalid_burning_proof()],
  }
}

pub fn burning_tx_data_with_incorrect_destination_address() -> ZK<BurningTxData> {
  ZK {
    redeemer: BurningTxData {
      tx_id: test_constants.burning_transaction_id,
      transferred_amount: 3,
      transferred_asset_name: test_constants.bridge_locked_token_asset_name,
      transferred_asset_policy_id: test_constants.bridge_locked_token_asset_name,
      destination_address: Address {
        payment_credential: VerificationKey("an_incorrect_vk"),
        stake_credential: None,
      },
    },
    proofs: [valid_burning_proof()],
  }
}
