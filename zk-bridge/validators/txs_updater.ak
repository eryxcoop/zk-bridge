use aiken/collection/list
use aiken/collection/pairs
use aiken/crypto
use aiken/option
use aiken/primitive/bytearray
use ak_381/groth16.{SnarkVerificationKey, groth_verify}
use cardano/assets.{PolicyId}
use cardano/transaction.{
  InlineDatum, Output, OutputReference, Spend, Transaction,
}
use common_types.{
  BurningTxData, MerkleRoot, TxUpdaterDatum, TxsUpdaterValidatorRedeemer, ZK,
}
use env

/// This funciton searches for an output in a `Transaction` that has a datum of type
/// `TxUpdaterDatum`, and returns both the output and the `merkle_root` contained
/// in the datum.
pub fn find_merkle_root_output(tx: Transaction) -> Option<(Output, MerkleRoot)> {
  let found_output: Option<Output> =
    list.find(
      tx.outputs,
      fn(o) {
        when o.datum is {
          InlineDatum(raw) ->
            if raw is TxUpdaterDatum { merkle_root: _ }: TxUpdaterDatum {
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
      expect new_datum: TxUpdaterDatum = raw
      let TxUpdaterDatum { merkle_root: new_merkle_root } = new_datum
      (o, new_merkle_root)
    },
  )
}

/// This proof should verify that `tx_id` is not in the merkle_tree represented by `old_merkle_root`,
/// and that the merkle tree represented by `new_merkle_root` is the result of adding `tx_id` to the
/// old merkle tree. For this milestone, the circuit used is an example circuit that can be found
/// in `circuits/tx_updater_example.circom`.
pub fn txs_updater_zk_proof_is_valid(
  old_merkle_root: MerkleRoot,
  new_merkle_root: MerkleRoot,
  redeemer: ZK<TxsUpdaterValidatorRedeemer>,
) -> Bool {
  let tx_id = redeemer.redeemer.tx_id
  let tx_id_int = bytearray.to_int_big_endian(tx_id)
  let old_merkle_root_int = bytearray.to_int_big_endian(old_merkle_root)
  let new_merkle_root_int = bytearray.to_int_big_endian(new_merkle_root)

  expect _redeemer =
    zk_verify_or_fail(
      redeemer,
      [
        Single(tx_id_int),
        Single(old_merkle_root_int),
        Single(new_merkle_root_int),
      ],
    )
  True
}

/// This function verifies that the `tx_id` used in both redeemers (the one for the
/// `txs_updater_validator` and the one for the `unlocking_validator`) is the same.
pub fn tx_id_in_both_redeemers_are_equal(
  tx: Transaction,
  redeemer: ZK<TxsUpdaterValidatorRedeemer>,
) -> Bool {
  let ZK {
    redeemer: TxsUpdaterValidatorRedeemer {
      tx_id: tx_id_for_updater,
      locked_assets_utxo_ref,
    },
    ..
  } = redeemer

  expect Some(locked_assets_input_redeemer) =
    pairs.get_first(tx.redeemers, Spend(locked_assets_utxo_ref))
  expect ZK { redeemer: BurningTxData { tx_id: burning_tx_id, .. }, .. }: ZK<
    BurningTxData,
  > = locked_assets_input_redeemer

  (tx_id_for_updater == burning_tx_id)?
}

/// This function returns the `Output`
/// that has an empty merkle root in an `InlineDatum`,
/// if it exists, or `None` if it doesn't.
pub fn find_empty_merkle_root_output(tx: Transaction) -> Option<Output> {
  list.find(
    tx.outputs,
    fn(o) {
      when o.datum is {
        InlineDatum(raw) ->
          if raw is TxUpdaterDatum { merkle_root }: TxUpdaterDatum {
            // the original merkle root must be empty
            (merkle_root == crypto.blake2b_224(""))?
          } else {
            False
          }
        _ -> False
      }
    },
  )
}

validator txs_updater_validator_spend {
  spend(
    datum: Option<TxUpdaterDatum>,
    redeemer: ZK<TxsUpdaterValidatorRedeemer>,
    own_ref: OutputReference,
    tx: Transaction,
  ) {
    // This is to ensure that of the two outputs from unlocking_tx, the one with the Merkle root
    // as the datum has the NFT as its asset.
    expect Some(own_input) = transaction.find_input(tx.inputs, own_ref)
    expect Some(TxUpdaterDatum { merkle_root: old_merkle_root }) = datum
    expect Some((new_merkle_root_output, new_merkle_root)) =
      find_merkle_root_output(tx)

    and {
      // the new output has the NFT representing the updated merkle root
      assets.has_nft_strict(
        new_merkle_root_output.value,
        env.txs_updater_policy_id,
        env.txs_updater_asset_name,
      )?,
      // the new output has this script as its spending script
      (new_merkle_root_output.address.payment_credential == own_input.output.address.payment_credential)?,
      txs_updater_zk_proof_is_valid(old_merkle_root, new_merkle_root, redeemer)?,
      // There's an input that participates in an unlocking action
      list.any(
        tx.inputs,
        fn(i) {
          i.output.address.payment_credential == env.unlocked_funds_spending_script
        },
      ),
      // verify that the tx_id from the destinatino chain used in both redeemers is the same
      tx_id_in_both_redeemers_are_equal(tx, redeemer)?,
    }
  }

  else(_) {
    fail
  }
}

validator txs_updater_validator_mint(unique_mint_utxo_ref: OutputReference) {
  mint(_r, policy_id: PolicyId, tx: Transaction) {
    expect Some(empty_merkle_root_output) = find_empty_merkle_root_output(tx)

    // txs_updater_validator.mint` should be only possible to execute once
    let is_output_consumed =
      list.any(
        tx.inputs,
        fn(input) { input.output_reference == unique_mint_utxo_ref },
      )

    and {
      is_output_consumed?,
      // We could also use `mint` for this part
      assets.has_nft_strict(
        empty_merkle_root_output.value,
        policy_id,
        env.txs_updater_asset_name,
      )?,
    }
  }

  else(_) {
    fail
  }
}

// This code is autogenerated by our tool [aiken-zk](https://github.com/eryxcoop/cardano-zk-aiken). The code performs a Groth16
// verification of a ZK proof given in the redeemer. The verification key is generated by aiken-zk for a circuit given as an input.
// In this case the circuit used  can be found in `milestone_3_deliverables/circuits/txs_updater_circuit.circom`
type ZKInputType {
  Single(Int)
  Many(List<Int>)
}

fn zk_verify_or_fail(
  zk_redeemer: ZK<TxsUpdaterValidatorRedeemer>,
  public_inputs: List<ZKInputType>,
) -> ZK<TxsUpdaterValidatorRedeemer> {
  let vk: SnarkVerificationKey =
    SnarkVerificationKey {
      nPublic: 3,
      vkAlpha: #"85e3f8a13a670514351a68677ea0e2fc51150daeea496b85a34d97751695e26b2ae4f1a5a3b60e17bb7bfd6d474154c5",
      vkBeta: #"b1abf58f58af5981cd24f996e53626a4157eeed4aa814498885b3a547c35d5efb877834602508255c030708552b353e21631f16475e35b977e39a068ac9fb5bc4c25d383139b721da0a878b663c4df52c94a51f7c06a019bb40324713d2bbf0f",
      vkGamma: #"93e02b6052719f607dacd3a088274f65596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e024aa2b2f08f0a91260805272dc51051c6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8",
      vkDelta: #"b824005d651bf6d38362f30967f78a33381fde734ebd5687265d2b250f54aa5b10860c1e0cd522e375a7f04178efe69c0747d9ee650176e8376346111c82fd997c3b16604ef241edd84843e9d84a3fd3833bcb2308b5ce4dfa9f465b18dbec7c",
      vkAlphaBeta: [],
      vkIC: [
        #"af1ca9d68a382928932cd5f1a3dde62489556f42da0c24e6d11191c1b187f147a206da840166e28f1ae73edee0c8b912",
        #"aba434215d34bebf3100b82fb68eaa69328cc6431a26ecc8ef81bffced149a5f7e193587789a1a0c6745b3e963c1989e",
        #"87db49b3c35ae1d3f5b767abf48ca5b73d17c81ad5c50419386a09415e7eba5b7bf50e5d3d2976ec11c31ad4f2ec3477",
        #"90a329df57ec041ae4f90e3cbda605c1d476cb038703d2aaf158d5dca80d27d38b8a946355785ef341fb4fc14c1454e1",
      ],
    }

  expect Some(proof) = list.head(zk_redeemer.proofs)

  let flattened_public_inputs: List<Int> =
    list.flat_map(
      public_inputs,
      fn(item) {
        when item is {
          Single(x) -> [x]
          Many(xs) -> xs
        }
      },
    )

  if !groth_verify(vk, proof, flattened_public_inputs) {
    fail Void
  } else {
    Void
  }

  expect Some(proofs) = list.tail(zk_redeemer.proofs)
  ZK { redeemer: zk_redeemer.redeemer, proofs }
}
