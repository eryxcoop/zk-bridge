use common_types.{TxUpdaterDatum}
use env
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
use txs_updater

test txs_updater_validator_spend_test() {
  txs_updater.txs_updater_validator_spend.spend(
    Some(TxUpdaterDatum { merkle_root: "old" }),
    simple_txs_updater_redeemer(test_constants.burning_transaction_id),
    test_constants.last_tx_set_updater_output_reference,
    simple_unlocking_tx(),
  )
}

test txs_updater_validator_invalid_proof_test() fail {
  txs_updater.txs_updater_validator_spend.spend(
    Some(TxUpdaterDatum { merkle_root: "old" }),
    txs_updater_redeemer_with_invalid_proof(
      test_constants.burning_transaction_id,
    ),
    test_constants.last_tx_set_updater_output_reference,
    simple_unlocking_tx(),
  )
}

test txs_updater_validator_output_with_incorrect_nft_token_name_test() fail {
  txs_updater.txs_updater_validator_spend.spend(
    Some(TxUpdaterDatum { merkle_root: "old" }),
    simple_txs_updater_redeemer(test_constants.burning_transaction_id),
    test_constants.last_tx_set_updater_output_reference,
    unlocking_tx_with_output_with_incorrect_txs_updater_asset_name(),
  )
}

test txs_updater_validator_output_with_incorrect_nft_policy_id_test() fail {
  txs_updater.txs_updater_validator_spend.spend(
    Some(TxUpdaterDatum { merkle_root: "old" }),
    simple_txs_updater_redeemer(test_constants.burning_transaction_id),
    test_constants.last_tx_set_updater_output_reference,
    unlocking_tx_with_incorrect_txs_updater_policy_id_output(),
  )
}

test txs_updater_validator_nft_amount_must_be_one() fail {
  txs_updater.txs_updater_validator_spend.spend(
    Some(TxUpdaterDatum { merkle_root: "old" }),
    simple_txs_updater_redeemer(test_constants.burning_transaction_id),
    test_constants.last_tx_set_updater_output_reference,
    unlocking_tx_with_incorrect_txs_updater_nft_amount(),
  )
}

test unlocking_transaction_redeemers_must_have_same_tx_id() fail {
  txs_updater.txs_updater_validator_spend.spend(
    Some(TxUpdaterDatum { merkle_root: "old" }),
    simple_txs_updater_redeemer("another_transaction_id"),
    test_constants.last_tx_set_updater_output_reference,
    unlocking_tx_with_input_redeemers_with_different_tx_id(),
  )
}

test txs_updater_mint_test() {
  txs_updater.txs_updater_validator_mint.mint(
    env.txs_updater_unique_mint_utxo_ref,
    None,
    env.txs_updater_policy_id,
    valid_txs_updater_mint_tx(),
  )
}

test txs_updater_mint_must_have_an_empty_merkle_root_output() fail {
  txs_updater.txs_updater_validator_mint.mint(
    env.txs_updater_unique_mint_utxo_ref,
    None,
    env.txs_updater_policy_id,
    txs_updater_mint_tx_with_invalid_datum(),
  )
}

test txs_updater_mint_must_consume_specified_utxo_ref() fail {
  txs_updater.txs_updater_validator_mint.mint(
    env.txs_updater_unique_mint_utxo_ref,
    None,
    env.txs_updater_policy_id,
    txs_updater_mint_tx_for_an_incorrect_utxo(),
  )
}

test txs_updater_mint_output_must_have_correct_policy_id_test() fail {
  txs_updater.txs_updater_validator_mint.mint(
    env.txs_updater_unique_mint_utxo_ref,
    None,
    env.txs_updater_policy_id,
    txs_updater_mint_with_incorrect_nft_policy_id(),
  )
}

test txs_updater_mint_output_must_have_correct_asset_name_test() fail {
  txs_updater.txs_updater_validator_mint.mint(
    env.txs_updater_unique_mint_utxo_ref,
    None,
    env.txs_updater_policy_id,
    txs_updater_mint_with_incorrect_nft_asset_name(),
  )
}

test txs_updater_mint_output_must_have_correct_asset_amount_test() fail {
  txs_updater.txs_updater_validator_mint.mint(
    env.txs_updater_unique_mint_utxo_ref,
    None,
    env.txs_updater_policy_id,
    txs_updater_mint_with_incorrect_nft_asset_amount(),
  )
}
