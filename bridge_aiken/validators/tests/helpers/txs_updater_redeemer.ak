use ak_381/groth16.{Proof}
use cardano/transaction.{TransactionId}
use common_types.{TxsUpdaterValidatorRedeemer}
use tests/helpers/test_constants

pub fn simple_txs_updater_redeemer(
  tx_id: TransactionId,
) -> TxsUpdaterValidatorRedeemer {
  TxsUpdaterValidatorRedeemer {
    tx_id: tx_id,
    locked_assets_utxo_ref: test_constants.locked_assets_utxo_ref,
    tx_set_update_proof: a_valid_tx_updater_proof(),
  }
}

pub fn txs_updater_redeemer_with_invalid_proof(
  burning_tx_id: TransactionId,
) -> TxsUpdaterValidatorRedeemer {
  TxsUpdaterValidatorRedeemer {
    tx_id: burning_tx_id,
    locked_assets_utxo_ref: test_constants.locked_assets_utxo_ref,
    tx_set_update_proof: an_invalid_tx_updater_proof(),
  }
}

pub fn a_valid_tx_updater_proof() {
  Proof {
    piA: #"a862d2cae764bf193d6fa64c7e05f2fec6f46f9f417dd1957665bc818675375888a6e15f6f0a09d67bb99f4067fd6324",
    piB: #"952ca8befbda701ca81af6e2f57e12ed95ee20303d1c94896fd915fb2b1a422e2f9564587ddf6147a9aa682676d415441615d330dcd7f8a20acc67267934956ea5215665e52899044af2dadc9c59dd08d2e613b8a2a47a44dfe450d7d008a9c0",
    piC: #"a0885491cf118b98c133be1126e92300b25eb77a9e29e0fcd2daec75c50fd324f2e8d19e36ef5d36c6fa7735b0a5bb9f",
  }
}

pub fn an_invalid_tx_updater_proof() {
  Proof {
    piA: #"c7f989e99189c616d9715541cb9b297a4094d5edabd22d99e9442f066c07dfc45b8c930268dd9a4d9a8f7654530b892a",
    piB: #"b5357b5d12da7db1016a7b8bec6617eb5bee8dea821d88abb6dd2f0569453c58333744dc2dd93116ae240752798adc6005fb17b83941a91df5e6634f3613e1398d8285bb33897e0b07ec06f44d1a57789ae612937e77356674d9ea3889c95bd9",
    piC: #"823ffd4f02484c09a64ace4e73d543c39741c46c31d462dd06727da5ecdd6feed6e30b6d35097bc8de986d2d854b6535",
  }
}
