use aiken/collection/list
use aiken/option
use bridge/common_types.{
  MerkleRoot, TxsUpdaterDatum, TxsUpdaterValidatorRedeemer,
}
use cardano/assets.{PolicyId}
use cardano/transaction.{InlineDatum, Output, Transaction}
use zk/tx_set_update

/// This funciton searches for an output in a `Transaction` that has a datum of type
/// `TxsUpdaterDatum`, and returns both the output and the `merkle_root` contained
/// in the datum.
pub fn find_merkle_root_output(tx: Transaction) -> Option<(Output, MerkleRoot)> {
  let found_output: Option<Output> =
    list.find(
      tx.outputs,
      fn(o) {
        when o.datum is {
          InlineDatum(raw) ->
            if raw is TxsUpdaterDatum { merkle_root: _ }: TxsUpdaterDatum {
              True
            } else {
              False
            }
          _ -> False
        }
      },
    )
  option.map(
    found_output,
    fn(o) {
      expect InlineDatum(raw) = o.datum
      expect new_datum: TxsUpdaterDatum = raw
      let TxsUpdaterDatum { merkle_root: new_merkle_root } = new_datum
      (o, new_merkle_root)
    },
  )
}

/// This function returns the `Output`
/// that has an empty merkle root in an `InlineDatum`,
/// if it exists, or `None` if it doesn't.
fn find_empty_merkle_root_output(
  tx: Transaction,
  initial_merkle_root: MerkleRoot,
) -> Option<Output> {
  list.find(
    tx.outputs,
    fn(o) {
      when o.datum is {
        InlineDatum(raw) ->
          if raw is TxsUpdaterDatum { merkle_root }: TxsUpdaterDatum {
            (merkle_root == initial_merkle_root)?
          } else {
            False
          }
        _ -> False
      }
    },
  )
}

/// This proof verifies that `redeemer.tx_id` is absent from the tree rooted at
/// `old_merkle_root`, and that the tree rooted at `new_merkle_root` is the
/// result of adding that transaction id.
pub fn txs_updater_zk_proof_is_valid(
  old_merkle_root: MerkleRoot,
  new_merkle_root: MerkleRoot,
  redeemer: TxsUpdaterValidatorRedeemer,
) -> Bool {
  tx_set_update.proof_verifies(redeemer, old_merkle_root, new_merkle_root)
}

validator txs_updater_validator_mint(
  txs_updater_asset_name: ByteArray,
  initial_merkle_root: MerkleRoot,
) {
  mint(_r, policy_id: PolicyId, tx: Transaction) {
    expect Some(empty_merkle_root_output) =
      find_empty_merkle_root_output(tx, initial_merkle_root)

    assets.has_nft_strict(
      empty_merkle_root_output.value,
      policy_id,
      txs_updater_asset_name,
    )?
  }

  else(_) {
    fail
  }
}
