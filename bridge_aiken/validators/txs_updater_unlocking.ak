use aiken/collection/list
use aiken/collection/pairs
use cardano/address.{Credential}
use cardano/assets
use cardano/transaction.{
  Output, OutputReference, Spend, Transaction,
}
use common_types.{
  BurningTxData, TxsUpdaterDatum, TxsUpdaterValidatorRedeemer,
}
use env
use txs_updater_common.{find_merkle_root_output, txs_updater_zk_proof_is_valid}

/// This function verifies that the `tx_id` used in both redeemers (the one for the
/// `txs_updater_validator` and the one for the `unlocking_validator`) is the same.
pub fn tx_id_in_both_redeemers_are_equal(
  tx: Transaction,
  redeemer: TxsUpdaterValidatorRedeemer,
) -> Bool {
  let TxsUpdaterValidatorRedeemer {
    tx_id: tx_id_for_updater,
    locked_assets_utxo_ref,
    ..
  } = redeemer

  expect Some(locked_assets_input_redeemer) =
    pairs.get_first(tx.redeemers, Spend(locked_assets_utxo_ref))
  expect BurningTxData { tx_id: burning_tx_id, .. } =
    locked_assets_input_redeemer

  (tx_id_for_updater == burning_tx_id)?
}

validator txs_updater_unlocking_validator_spend(
  unlocked_funds_spending_script: Credential,
) {
  spend(
    datum: Option<TxsUpdaterDatum>,
    redeemer: TxsUpdaterValidatorRedeemer,
    own_ref: OutputReference,
    tx: Transaction,
  ) {
    // This is to ensure that of the two outputs from unlocking/minting transaction, the one with the Merkle root
    // as the datum has the NFT as its asset.
    expect Some(own_input) = transaction.find_input(tx.inputs, own_ref)
    expect Some(TxsUpdaterDatum { merkle_root: old_merkle_root }) = datum
    expect Some((new_merkle_root_output, new_merkle_root)) =
      find_merkle_root_output(tx)

    and {
      // the new output has the NFT representing the updated merkle root
      assets.has_nft_strict(
        new_merkle_root_output.value,
        env.burning_txs_updater_policy_id,
        env.burning_txs_updater_asset_name,
      )?,
      // the new output has this script as its spending script
      (new_merkle_root_output.address.payment_credential == own_input.output.address.payment_credential)?,
      txs_updater_zk_proof_is_valid(old_merkle_root, new_merkle_root, redeemer)?,
      // There's an input that participates in an unlocking/minting action
      list.any(
        tx.inputs,
        fn(i) {
          i.output.address.payment_credential == unlocked_funds_spending_script
        },
      ),
      // verify that the tx_id from the destination chain used in both redeemers is the same
      tx_id_in_both_redeemers_are_equal(tx, redeemer)?,
    }
  }

  else(_) {
    fail
  }
}
