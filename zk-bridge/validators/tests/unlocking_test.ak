use tests/helpers/burning_tx_data.{
  burning_tx_data_with_incorrect_destination_address,
  burning_tx_data_with_invalid_burning_proof, valid_burning_tx_data_for_tx,
}
use tests/helpers/test_constants
use tests/helpers/unlocking_tx.{
  simple_unlocking_tx, unlocking_tx_with_bigger_amount, unlocking_tx_with_change,
  unlocking_tx_with_change_with_bigger_ammount,
  unlocking_tx_with_incorrect_change_output_address,
  unlocking_tx_with_input_redeemers_with_different_tx_id,
  unlocking_tx_without_burning_transactions_set,
}
use unlocking

test unlocking_validator_simple_unlocking_tx_test() {
  let tx = simple_unlocking_tx()
  unlocking.unlocking_validator.spend(
    None,
    valid_burning_tx_data_for_tx(tx),
    test_constants.locked_assets_utxo_ref,
    tx,
  )
}

test unlocking_validator_unlocking_tx_with_change_test() {
  let tx = unlocking_tx_with_change()
  unlocking.unlocking_validator.spend(
    None,
    valid_burning_tx_data_for_tx(tx),
    test_constants.locked_assets_utxo_ref,
    tx,
  )
}

test unlocking_validator_invalid_unlocking_proof_test() fail {
  unlocking.unlocking_validator.spend(
    None,
    burning_tx_data_with_invalid_burning_proof(),
    test_constants.locked_assets_utxo_ref,
    simple_unlocking_tx(),
  )
}

test unlocking_validator_incorrect_destination_address_test() fail {
  unlocking.unlocking_validator.spend(
    None,
    burning_tx_data_with_incorrect_destination_address(),
    test_constants.locked_assets_utxo_ref,
    simple_unlocking_tx(),
  )
}

test unlocking_validator_incorrect_amount_test() fail {
  let tx = unlocking_tx_with_bigger_amount()
  unlocking.unlocking_validator.spend(
    None,
    valid_burning_tx_data_for_tx(tx),
    test_constants.locked_assets_utxo_ref,
    simple_unlocking_tx(),
  )
}

test unlocking_validator_with_incorrect_change_address_test() fail {
  let tx = unlocking_tx_with_incorrect_change_output_address()
  unlocking.unlocking_validator.spend(
    None,
    valid_burning_tx_data_for_tx(tx),
    test_constants.locked_assets_utxo_ref,
    tx,
  )
}

test unlocking_validator_incorrect_change_amount_test() fail {
  let tx = unlocking_tx_with_change_with_bigger_ammount()
  unlocking.unlocking_validator.spend(
    None,
    valid_burning_tx_data_for_tx(tx),
    test_constants.locked_assets_utxo_ref,
    tx,
  )
}

test unlocking_transaction_must_spend_its_used_tx_set_test() fail {
  let tx = unlocking_tx_without_burning_transactions_set()
  unlocking.unlocking_validator.spend(
    None,
    valid_burning_tx_data_for_tx(tx),
    test_constants.locked_assets_utxo_ref,
    tx,
  )
}

test unlocking_transaction_redeemers_must_have_same_tx_id() fail {
  let tx = unlocking_tx_with_input_redeemers_with_different_tx_id()
  unlocking.unlocking_validator.spend(
    None,
    valid_burning_tx_data_for_tx(tx),
    test_constants.locked_assets_utxo_ref,
    tx,
  )
}
