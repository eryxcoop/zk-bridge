use aiken/collection/list
use aiken/crypto
use aiken/option
use aiken/primitive/bytearray
use ak_381/groth16.{SnarkVerificationKey}
use cardano/assets.{PolicyId}
use cardano/transaction.{
  InlineDatum, Output, OutputReference, Transaction,
}
use common_types.{
  MerkleRoot, TxsUpdaterDatum, TxsUpdaterValidatorRedeemer,
}
use zk_verification.{Single, zk_verify}

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
fn find_empty_merkle_root_output(tx: Transaction) -> Option<Output> {
  list.find(
    tx.outputs,
    fn(o) {
      when o.datum is {
        InlineDatum(raw) ->
          if raw is TxsUpdaterDatum { merkle_root }: TxsUpdaterDatum {
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

/// This proof should verify that `tx_id` is not in the merkle_tree represented by `old_merkle_root`,
/// and that the merkle tree represented by `new_merkle_root` is the result of adding `tx_id` to the
/// old merkle tree. For this milestone, the circuit used is an example circuit that can be found
/// in `circuits/tx_updater_example.circom`.
pub fn txs_updater_zk_proof_is_valid(
  old_merkle_root: MerkleRoot,
  new_merkle_root: MerkleRoot,
  redeemer: TxsUpdaterValidatorRedeemer,
) -> Bool {
  let tx_id = redeemer.tx_id
  let tx_id_int = bytearray.to_int_big_endian(tx_id)
  let old_merkle_root_int = bytearray.to_int_big_endian(old_merkle_root)
  let new_merkle_root_int = bytearray.to_int_big_endian(new_merkle_root)

  let tx_update_circuit_vk = tx_set_update_verification_circuit_vk()

  zk_verify(
    redeemer.tx_set_update_proof,
    [
      Single(tx_id_int),
      Single(old_merkle_root_int),
      Single(new_merkle_root_int),
    ],
    tx_update_circuit_vk,
  )
}

fn tx_set_update_verification_circuit_vk() {
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
}

validator txs_updater_validator_mint(unique_mint_utxo_ref: OutputReference, txs_updater_asset_name: ByteArray) {
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
        txs_updater_asset_name,
      )?,
    }
  }

  else(_) {
    fail
  }
}