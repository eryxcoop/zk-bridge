use aiken/collection/pairs
use cardano/assets
use cardano/transaction.{
  Mint, Output, OutputReference, Transaction,
}
use common_types.{
  TxsUpdaterDatum, TxsUpdaterValidatorRedeemer,
}
use env
use minting.{MintingValidatorRedeemer}
use txs_updater_common.{find_merkle_root_output, txs_updater_zk_proof_is_valid}

/// This function verifies that the `tx_id` used in both redeemers (the one for the
/// `txs_updater_validator` and the one for the `minting_validator`) is the same.
pub fn tx_id_in_both_redeemers_are_equal(
  tx: Transaction,
  redeemer: TxsUpdaterValidatorRedeemer,
) -> Bool {
  let TxsUpdaterValidatorRedeemer {
    tx_id: tx_id_for_updater,
    ..
  } = redeemer

  expect Some(locked_assets_input_redeemer) =
    pairs.get_first(tx.redeemers, Mint(env.bridge_minting_policy_id))
  expect MintingValidatorRedeemer {
    locking_tx_input_output_reference: OutputReference {
      transaction_id: locking_tx_id,
      ..
    },
    ..
  } = locked_assets_input_redeemer

  (tx_id_for_updater == locking_tx_id)?
}

/// This function verifies that the transaction is indeed minting tokens for the `PolicyId` and name
/// corresponding to the bridged assets (which should happen atomically in the minting validator).
fn bridge_tokens_are_being_minted(tx: Transaction) -> Bool {
  assets.quantity_of(tx.mint, env.transferred_asset_policy_id, env.transferred_asset_name) > 0
}

validator txs_updater_minting_validator_spend {
  spend(
    datum: Option<TxsUpdaterDatum>,
    redeemer: TxsUpdaterValidatorRedeemer,
    own_ref: OutputReference,
    tx: Transaction,
  ) {
    // This is to ensure that of the two outputs from minting transaction, the one with the Merkle root
    // as the datum has the NFT as its asset.
    expect Some(own_input) = transaction.find_input(tx.inputs, own_ref)
    expect Some(TxsUpdaterDatum { merkle_root: old_merkle_root }) = datum
    expect Some((new_merkle_root_output, new_merkle_root)) =
      find_merkle_root_output(tx)

    and {
      // the new output has the NFT representing the updated merkle root
      assets.has_nft_strict(
        new_merkle_root_output.value,
        env.locking_txs_updater_policy_id,
        env.locking_txs_updater_asset_name,
      )?,
      // the new output has this script as its spending script
      (new_merkle_root_output.address.payment_credential == own_input.output.address.payment_credential)?,
      txs_updater_zk_proof_is_valid(old_merkle_root, new_merkle_root, redeemer)?,
      bridge_tokens_are_being_minted(tx)?,
      // verify that the tx_id from the source chain used in both redeemers is the same
      tx_id_in_both_redeemers_are_equal(tx, redeemer)?,
    }
  }

  else(_) {
    fail
  }
}
