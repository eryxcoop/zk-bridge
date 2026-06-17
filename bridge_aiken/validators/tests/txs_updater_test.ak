use common_types.{TxsUpdaterDatum}
use env
use tests/helpers/minting_tx.{
  simple_minting_tx,
  minting_tx_with_an_incorrect_mint_value,
}
use tests/helpers/test_constants
use tests/helpers/txs_updater_mint.{
  txs_updater_mint_tx_for_an_incorrect_utxo,
  txs_updater_mint_tx_with_invalid_datum,
  txs_updater_mint_with_incorrect_nft_asset_amount,
  txs_updater_mint_with_incorrect_nft_asset_name,
  txs_updater_mint_with_incorrect_nft_policy_id, valid_txs_updater_mint_tx,
}
use tests/helpers/txs_updater_redeemer.{
  simple_txs_updater_redeemer, txs_updater_redeemer_with_invalid_proof,
}
use tests/helpers/unlocking_tx.{
  simple_unlocking_tx, unlocking_tx_with_incorrect_txs_updater_nft_amount,
  unlocking_tx_with_incorrect_txs_updater_policy_id_output,
  unlocking_tx_with_input_redeemers_with_different_tx_id,
  unlocking_tx_with_output_with_incorrect_txs_updater_asset_name,
}
use txs_updater_common
use txs_updater_minting
use txs_updater_unlocking

test txs_updater_validator_spend_test() {
  txs_updater_unlocking.txs_updater_unlocking_validator_spend.spend(
    env.unlocked_funds_spending_script,
    Some(TxsUpdaterDatum { merkle_root: "old" }),
    simple_txs_updater_redeemer(test_constants.burning_transaction_id),
    test_constants.last_tx_set_updater_output_reference,
    simple_unlocking_tx(),
  )
}

test txs_updater_validator_invalid_proof_test() fail {
  txs_updater_unlocking.txs_updater_unlocking_validator_spend.spend(
    env.unlocked_funds_spending_script,
    Some(TxsUpdaterDatum { merkle_root: "old" }),
    txs_updater_redeemer_with_invalid_proof(
      test_constants.burning_transaction_id,
    ),
    test_constants.last_tx_set_updater_output_reference,
    simple_unlocking_tx(),
  )
}

test txs_updater_validator_output_with_incorrect_nft_token_name_test() fail {
  txs_updater_unlocking.txs_updater_unlocking_validator_spend.spend(
    env.unlocked_funds_spending_script,
    Some(TxsUpdaterDatum { merkle_root: "old" }),
    simple_txs_updater_redeemer(test_constants.burning_transaction_id),
    test_constants.last_tx_set_updater_output_reference,
    unlocking_tx_with_output_with_incorrect_txs_updater_asset_name(),
  )
}

test txs_updater_validator_output_with_incorrect_nft_policy_id_test() fail {
  txs_updater_unlocking.txs_updater_unlocking_validator_spend.spend(
    env.unlocked_funds_spending_script,
    Some(TxsUpdaterDatum { merkle_root: "old" }),
    simple_txs_updater_redeemer(test_constants.burning_transaction_id),
    test_constants.last_tx_set_updater_output_reference,
    unlocking_tx_with_incorrect_txs_updater_policy_id_output(),
  )
}

test txs_updater_validator_nft_amount_must_be_one() fail {
  txs_updater_unlocking.txs_updater_unlocking_validator_spend.spend(
    env.unlocked_funds_spending_script,
    Some(TxsUpdaterDatum { merkle_root: "old" }),
    simple_txs_updater_redeemer(test_constants.burning_transaction_id),
    test_constants.last_tx_set_updater_output_reference,
    unlocking_tx_with_incorrect_txs_updater_nft_amount(),
  )
}

test unlocking_transaction_redeemers_must_have_same_tx_id() fail {
  txs_updater_unlocking.txs_updater_unlocking_validator_spend.spend(
    env.unlocked_funds_spending_script,
    Some(TxsUpdaterDatum { merkle_root: "old" }),
    simple_txs_updater_redeemer("another_transaction_id"),
    test_constants.last_tx_set_updater_output_reference,
    unlocking_tx_with_input_redeemers_with_different_tx_id(),
  )
}

test txs_updater_mint_test() {
  txs_updater_common.txs_updater_validator_mint.mint(
    env.burning_txs_updater_unique_mint_utxo_ref,
    env.burning_txs_updater_asset_name,
    None,
    env.burning_txs_updater_policy_id,
    valid_txs_updater_mint_tx(),
  )
}

test txs_updater_mint_must_have_an_empty_merkle_root_output() fail {
  txs_updater_common.txs_updater_validator_mint.mint(
    env.burning_txs_updater_unique_mint_utxo_ref,
    env.burning_txs_updater_asset_name,
    None,
    env.burning_txs_updater_policy_id,
    txs_updater_mint_tx_with_invalid_datum(),
  )
}

test txs_updater_mint_must_consume_specified_utxo_ref() fail {
  txs_updater_common.txs_updater_validator_mint.mint(
    env.burning_txs_updater_unique_mint_utxo_ref,
    env.burning_txs_updater_asset_name,
    None,
    env.burning_txs_updater_policy_id,
    txs_updater_mint_tx_for_an_incorrect_utxo(),
  )
}

test txs_updater_mint_output_must_have_correct_policy_id_test() fail {
  txs_updater_common.txs_updater_validator_mint.mint(
    env.burning_txs_updater_unique_mint_utxo_ref,
    env.burning_txs_updater_asset_name,
    None,
    env.burning_txs_updater_policy_id,
    txs_updater_mint_with_incorrect_nft_policy_id(),
  )
}

test txs_updater_mint_output_must_have_correct_asset_name_test() fail {
  txs_updater_common.txs_updater_validator_mint.mint(
    env.burning_txs_updater_unique_mint_utxo_ref,
    env.burning_txs_updater_asset_name,
    None,
    env.burning_txs_updater_policy_id,
    txs_updater_mint_with_incorrect_nft_asset_name(),
  )
}

test txs_updater_mint_output_must_have_correct_asset_amount_test() fail {
  txs_updater_common.txs_updater_validator_mint.mint(
    env.burning_txs_updater_unique_mint_utxo_ref,
    env.burning_txs_updater_asset_name,
    None,
    env.burning_txs_updater_policy_id,
    txs_updater_mint_with_incorrect_nft_asset_amount(),
  )
}

test txs_updater_for_minting_tx() {
  txs_updater_minting.txs_updater_minting_validator_spend.spend(
    Some(TxsUpdaterDatum { merkle_root: "old" }),
    simple_txs_updater_redeemer(test_constants.locking_transaction_id),
    test_constants.last_tx_set_updater_output_reference,
    simple_minting_tx(),
  )
}

test txs_updater_for_minting_tx_must_be_minting_transferred_tokens() fail {
  txs_updater_minting.txs_updater_minting_validator_spend.spend(
    Some(TxsUpdaterDatum { merkle_root: "old" }),
    simple_txs_updater_redeemer(test_constants.locking_transaction_id),
    test_constants.last_tx_set_updater_output_reference,
    minting_tx_with_an_incorrect_mint_value(),
  )
}
