use tests/helpers/burning_tx_data.{
  burning_tx_data_with_incorrect_destination_address,
  burning_tx_data_with_invalid_burning_proof, valid_burning_tx_data_for_tx,
}
use tests/helpers/test_constants
use tests/helpers/unlocking_tx.{
  simple_unlocking_tx, unlocking_tx_with_bigger_amount, unlocking_tx_with_change,
  unlocking_tx_with_change_with_bigger_amount,
  unlocking_tx_with_incorrect_change_output_address,
  unlocking_tx_with_input_redeemers_with_different_tx_id,
  unlocking_tx_without_burning_transactions_set,
}
use unlocking

fn run_unlocking_validator(redeemer, tx) {
  unlocking.unlocking_validator.spend(
    None,
    redeemer,
    test_constants.locked_assets_utxo_ref,
    tx,
  )
}

test accepts_full_unlock() {
  let tx = simple_unlocking_tx()
  run_unlocking_validator(valid_burning_tx_data_for_tx(tx), tx)
}

test accepts_partial_unlock_with_change() {
  let tx = unlocking_tx_with_change()
  run_unlocking_validator(valid_burning_tx_data_for_tx(tx), tx)
}

test rejects_invalid_burning_proof() fail {
  run_unlocking_validator(
    burning_tx_data_with_invalid_burning_proof(),
    simple_unlocking_tx(),
  )
}

test rejects_wrong_destination_address() fail {
  run_unlocking_validator(
    burning_tx_data_with_incorrect_destination_address(),
    simple_unlocking_tx(),
  )
}

test rejects_unlock_amount_exceeding_locked_amount() fail {
  let tx = unlocking_tx_with_bigger_amount()
  run_unlocking_validator(
    valid_burning_tx_data_for_tx(tx),
    simple_unlocking_tx(),
  )
}

test rejects_change_output_to_wrong_address() fail {
  let tx = unlocking_tx_with_incorrect_change_output_address()
  run_unlocking_validator(valid_burning_tx_data_for_tx(tx), tx)
}

test rejects_change_output_with_wrong_amount() fail {
  let tx = unlocking_tx_with_change_with_bigger_amount()
  run_unlocking_validator(valid_burning_tx_data_for_tx(tx), tx)
}

test rejects_missing_used_tx_set_update() fail {
  let tx = unlocking_tx_without_burning_transactions_set()
  run_unlocking_validator(valid_burning_tx_data_for_tx(tx), tx)
}

test rejects_used_tx_set_redeemer_tx_id_mismatch() fail {
  let tx = unlocking_tx_with_input_redeemers_with_different_tx_id()
  run_unlocking_validator(valid_burning_tx_data_for_tx(tx), tx)
}
