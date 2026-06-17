use bridge/common_types.{TxsUpdaterDatum}
use env
use tests/helpers/minting_tx.{
  minting_tx_with_an_incorrect_mint_value,
  simple_minting_tx_with_fixed_locking_tx_hash,
}
use tests/helpers/test_constants
use tests/helpers/txs_updater_mint.{
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

fn run_txs_updater_mint(tx) {
  txs_updater_common.txs_updater_validator_mint.mint(
    env.burning_txs_updater_asset_name,
    env.burning_txs_updater_initial_merkle_root,
    None,
    env.burning_txs_updater_policy_id,
    tx,
  )
}

fn run_txs_updater_unlocking_spend(redeemer, tx) {
  txs_updater_unlocking.txs_updater_unlocking_validator_spend.spend(
    env.unlocked_funds_spending_script,
    Some(
      TxsUpdaterDatum {
        merkle_root: test_constants.tx_set_update_fixture_root_in,
      },
    ),
    redeemer,
    test_constants.last_tx_set_updater_output_reference,
    tx,
  )
}

fn run_txs_updater_minting_spend(redeemer, tx) {
  txs_updater_minting.txs_updater_minting_validator_spend.spend(
    env.locking_txs_updater_policy_id,
    Some(
      TxsUpdaterDatum {
        merkle_root: test_constants.tx_set_update_fixture_root_in,
      },
    ),
    redeemer,
    test_constants.last_tx_set_updater_output_reference,
    tx,
  )
}

test accepts_unlocking_update() {
  run_txs_updater_unlocking_spend(
    simple_txs_updater_redeemer(test_constants.burning_transaction_id),
    simple_unlocking_tx(),
  )
}

test rejects_unlocking_update_with_invalid_proof() fail {
  run_txs_updater_unlocking_spend(
    txs_updater_redeemer_with_invalid_proof(
      test_constants.burning_transaction_id,
    ),
    simple_unlocking_tx(),
  )
}

test rejects_unlocking_update_with_wrong_nft_asset_name() fail {
  run_txs_updater_unlocking_spend(
    simple_txs_updater_redeemer(test_constants.burning_transaction_id),
    unlocking_tx_with_output_with_incorrect_txs_updater_asset_name(),
  )
}

test rejects_unlocking_update_with_wrong_nft_policy() fail {
  run_txs_updater_unlocking_spend(
    simple_txs_updater_redeemer(test_constants.burning_transaction_id),
    unlocking_tx_with_incorrect_txs_updater_policy_id_output(),
  )
}

test rejects_unlocking_update_with_non_singleton_nft() fail {
  run_txs_updater_unlocking_spend(
    simple_txs_updater_redeemer(test_constants.burning_transaction_id),
    unlocking_tx_with_incorrect_txs_updater_nft_amount(),
  )
}

test rejects_unlocking_update_when_redeemer_tx_ids_differ() fail {
  run_txs_updater_unlocking_spend(
    simple_txs_updater_redeemer("another_transaction_id"),
    unlocking_tx_with_input_redeemers_with_different_tx_id(),
  )
}

test accepts_initial_mint() {
  run_txs_updater_mint(valid_txs_updater_mint_tx())
}

test rejects_initial_mint_without_empty_merkle_root_output() fail {
  run_txs_updater_mint(txs_updater_mint_tx_with_invalid_datum())
}

test rejects_initial_mint_with_wrong_nft_policy() fail {
  run_txs_updater_mint(txs_updater_mint_with_incorrect_nft_policy_id())
}

test rejects_initial_mint_with_wrong_nft_asset_name() fail {
  run_txs_updater_mint(txs_updater_mint_with_incorrect_nft_asset_name())
}

test rejects_initial_mint_with_non_singleton_nft() fail {
  run_txs_updater_mint(txs_updater_mint_with_incorrect_nft_asset_amount())
}

test accepts_locking_update_when_bridge_mints_tokens() {
  run_txs_updater_minting_spend(
    simple_txs_updater_redeemer(test_constants.locking_transaction_id),
    simple_minting_tx_with_fixed_locking_tx_hash(
      test_constants.locking_transaction_id,
    ),
  )
}

test rejects_locking_update_when_bridge_mints_no_tokens() fail {
  run_txs_updater_minting_spend(
    simple_txs_updater_redeemer(test_constants.locking_transaction_id),
    minting_tx_with_an_incorrect_mint_value(),
  )
}
