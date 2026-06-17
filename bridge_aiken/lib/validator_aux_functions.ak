use aiken/collection/list
use aiken/collection/pairs
use aiken/crypto.{Hash, Sha3_256}
use cardano/address.{PaymentCredential}
use cardano/assets.{PolicyId, Value}
use cardano/transaction.{Input, Output, Spend, Transaction, TransactionId}
use common_types.{TxsUpdaterValidatorRedeemer}
// use env

/// This function verifies if the `output` has an spending script corresponding to the `txs_updater` validator.
pub fn output_has_txs_updater_nft(output: Output, txs_updater_policy_id: PolicyId, txs_updater_asset_name: ByteArray) -> Bool {
  assets.has_nft_strict(
    output.value,
    txs_updater_policy_id,
    txs_updater_asset_name,
  )
}

/// This function finds an output that has a given value (ignoring ADA) and a 
/// payment address. 
pub fn find_output_with_value(
  tx: Transaction,
  expected_value: Value,
  expected_payment_credential: PaymentCredential,
) -> Option<Output> {
  list.find(
    tx.outputs,
    fn(o) {
      and {
        o.address.payment_credential == expected_payment_credential,
        assets.match(assets.without_lovelace(o.value), expected_value, ==),
      }
    },
  )
}

/// Checks that the transaction contains an input with the `tx_updater` NFT and that the transaction hash used to update the used txs 
/// set is equal to the one being used to claim the tokens from the bridge 
pub fn locking_tx_hash_is_added_to_the_used_txs_set(
  tx: Transaction,
  tx_id: TransactionId,
  txs_updater_policy_id: PolicyId,
  txs_updater_asset_name: ByteArray,
) {
  expect Some(used_txs_input) = find_input_with_txs_updater_nft(tx.inputs, txs_updater_policy_id, txs_updater_asset_name)
  tx_id_in_both_redeemers_are_equal(tx, used_txs_input, tx_id)?
}

/// Receives a list of `Input`s and returns the first one that has an output
/// with the `txs_updater` NFT, or `None` if there is no such input.
fn find_input_with_txs_updater_nft(inputs: List<Input>, txs_updater_policy_id: PolicyId, txs_updater_asset_name: ByteArray) -> Option<Input> {
  list.find(inputs, fn(input) { output_has_txs_updater_nft(input.output, txs_updater_policy_id, txs_updater_asset_name) })
}

/// This function verifies that the `tx_id` used in both redeemers (the one for the
/// `txs_updater_validator` and the one for the `unlocking_validator` or `minting_validator`) is the same.
fn tx_id_in_both_redeemers_are_equal(
  tx: Transaction,
  tx_updater_input: Input,
  redeemed_tx_id: Hash<Sha3_256, Transaction>,
) -> Bool {
  expect Some(tx_updater_input_redeemer) =
    pairs.get_first(tx.redeemers, Spend(tx_updater_input.output_reference))
  expect TxsUpdaterValidatorRedeemer { tx_id: tx_id_for_updater, .. } =
    tx_updater_input_redeemer

  (tx_id_for_updater == redeemed_tx_id)?
}
