use ak_381/groth16.{Proof}
use bridge/common_types.{TxsUpdaterValidatorRedeemer}
use cardano/transaction.{TransactionId}
use tests/helpers/bridge_fixture
use tests/helpers/test_constants

pub fn simple_txs_updater_redeemer(
  tx_id: TransactionId,
) -> TxsUpdaterValidatorRedeemer {
  let locked_assets_utxo_ref = test_constants.locked_assets_utxo_ref
  TxsUpdaterValidatorRedeemer {
    tx_id,
    locked_assets_utxo_ref_tx_id: locked_assets_utxo_ref.transaction_id,
    locked_assets_utxo_ref_output_index: locked_assets_utxo_ref.output_index,
    tx_set_update_proof_pi_a: a_valid_tx_updater_proof().piA,
    tx_set_update_proof_pi_b: a_valid_tx_updater_proof().piB,
    tx_set_update_proof_pi_c: a_valid_tx_updater_proof().piC,
  }
}

pub fn txs_updater_redeemer_with_invalid_proof(
  burning_tx_id: TransactionId,
) -> TxsUpdaterValidatorRedeemer {
  let locked_assets_utxo_ref = test_constants.locked_assets_utxo_ref
  TxsUpdaterValidatorRedeemer {
    tx_id: burning_tx_id,
    locked_assets_utxo_ref_tx_id: locked_assets_utxo_ref.transaction_id,
    locked_assets_utxo_ref_output_index: locked_assets_utxo_ref.output_index,
    tx_set_update_proof_pi_a: an_invalid_tx_updater_proof().piA,
    tx_set_update_proof_pi_b: an_invalid_tx_updater_proof().piB,
    tx_set_update_proof_pi_c: an_invalid_tx_updater_proof().piC,
  }
}

pub fn a_valid_tx_updater_proof() {
  bridge_fixture.final_tx_set_update_proof()
}

pub fn an_invalid_tx_updater_proof() {
  Proof {
    piA: #"c7f989e99189c616d9715541cb9b297a4094d5edabd22d99e9442f066c07dfc45b8c930268dd9a4d9a8f7654530b892a",
    piB: #"b5357b5d12da7db1016a7b8bec6617eb5bee8dea821d88abb6dd2f0569453c58333744dc2dd93116ae240752798adc6005fb17b83941a91df5e6634f3613e1398d8285bb33897e0b07ec06f44d1a57789ae612937e77356674d9ea3889c95bd9",
    piC: #"823ffd4f02484c09a64ace4e73d543c39741c46c31d462dd06727da5ecdd6feed6e30b6d35097bc8de986d2d854b6535",
  }
}
