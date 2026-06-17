use aiken/collection/list
use bridge/common_types.{TxsUpdaterDatum, TxsUpdaterValidatorRedeemer}
use cardano/assets.{PolicyId}
use cardano/transaction.{Mint, Output, OutputReference, Transaction}
use env
use minting.{MintingValidatorRedeemer}
use txs_updater_common.{find_merkle_root_output, txs_updater_zk_proof_is_valid}

fn find_bridge_mint_redeemer(
  tx: Transaction,
) -> Option<(PolicyId, MintingValidatorRedeemer)> {
  list.find_map(
    tx.redeemers,
    fn(entry) {
      let Pair(script_purpose, raw_redeemer) = entry
      when script_purpose is {
        Mint(policy_id) ->
          if raw_redeemer is MintingValidatorRedeemer {
            Some((policy_id, raw_redeemer))
          } else {
            None
          }
        _ -> None
      }
    },
  )
}

/// This function verifies that the `tx_id` used in both redeemers (the one for the
/// `txs_updater_validator` and the one for the `minting_validator`) is the same.
pub fn tx_id_in_both_redeemers_are_equal(
  tx: Transaction,
  redeemer: TxsUpdaterValidatorRedeemer,
) -> Bool {
  let TxsUpdaterValidatorRedeemer { tx_id: tx_id_for_updater, .. } = redeemer

  expect Some((_, locked_assets_input_redeemer)) = find_bridge_mint_redeemer(tx)
  let MintingValidatorRedeemer { locking_tx_hash, .. } =
    locked_assets_input_redeemer

  (tx_id_for_updater == locking_tx_hash)?
}

/// This function verifies that the transaction is indeed minting tokens for the `PolicyId` and name
/// corresponding to the bridged assets (which should happen atomically in the minting validator).
fn bridge_tokens_are_being_minted(tx: Transaction) -> Bool {
  expect Some((bridge_policy_id, _)) = find_bridge_mint_redeemer(tx)
  assets.quantity_of(tx.mint, bridge_policy_id, env.transferred_asset_name) > 0
}

validator txs_updater_minting_validator_spend(
  locking_txs_updater_policy_id: PolicyId,
) {
  spend(
    datum: Option<TxsUpdaterDatum>,
    redeemer: TxsUpdaterValidatorRedeemer,
    own_ref: OutputReference,
    tx: Transaction,
  ) {
    expect Some(own_input) = transaction.find_input(tx.inputs, own_ref)
    expect Some(TxsUpdaterDatum { merkle_root: old_merkle_root }) = datum
    expect Some((new_merkle_root_output, new_merkle_root)) =
      find_merkle_root_output(tx)
    and {
      assets.has_nft_strict(
        new_merkle_root_output.value,
        locking_txs_updater_policy_id,
        env.locking_txs_updater_asset_name,
      )?,
      (new_merkle_root_output.address.payment_credential == own_input.output.address.payment_credential)?,
      txs_updater_zk_proof_is_valid(old_merkle_root, new_merkle_root, redeemer)?,
      bridge_tokens_are_being_minted(tx)?,
      tx_id_in_both_redeemers_are_equal(tx, redeemer)?,
    }
  }

  else(_) {
    fail
  }
}
