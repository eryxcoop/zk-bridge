use aiken/collection/list
use aiken/collection/pairs
use ak_381/groth16.{SnarkVerificationKey, groth_verify}
use cardano/address.{Address}
use cardano/assets.{PolicyId, Value}
use cardano/transaction.{Input, Output, OutputReference, Spend, Transaction}
use common_types.{BurningTxData, TxsUpdaterValidatorRedeemer, ZK}
use env

/// This proof should verify a circuit that proves that an UTxO with a given `amount`, `asset_name`
/// and `policy_id` was burned in a transaction in the bridge's destination chain. Since this bridge
/// will not have a counter part we are going to use an example circuit for this. The circuit has
/// no constraints and it can be found in `circuits/burning_circuit.circom`.
pub fn burning_zk_proof_is_valid(redeemer: ZK<BurningTxData>) -> Bool {
  let public_input = redeemer.redeemer.transferred_amount
  expect _redeemer = zk_verify_or_fail(redeemer, [Single(public_input)])
  True
}

/// Verifies if the combined value between `burning_tx_value` (i.e., the redeemer's value)
/// and the value found in `change_output` add up to the total of the current locked funds in the contract,
/// and also verifies if the `change_output` continues being locked by this same spending script.
pub fn change_output_is_well_formed(
  input: Input,
  change_output: Output,
  burning_tx_value: Value,
) -> Bool {
  let combined_value =
    assets.zero
      |> assets.merge(change_output.value)
      |> assets.merge(burning_tx_value)
  and {
    // The change adress is this same validator's script hash
    change_output.address.payment_credential == input.output.address.payment_credential,
    assets.match(combined_value, input.output.value, ==),
  }
}

/// This function verifies if the `output` has an spending script corresponding to the `txs_updater` validator.
pub fn output_has_txs_updater_nft(output: Output) -> Bool {
  assets.has_nft_strict(
    output.value,
    env.txs_updater_policy_id,
    env.txs_updater_asset_name,
  )
}

/// This function determines if this transaction unlocks all the funds locked by the
/// `unlocking_validator` spending script.
pub fn tx_has_change(
  locked_funds: Value,
  unlocked_funds: Value,
  asset_name: ByteArray,
  asset_policy_id: PolicyId,
) -> Bool {
  let locked_amount: Int =
    assets.quantity_of(locked_funds, asset_policy_id, asset_name)
  let unlocked_amount: Int =
    assets.quantity_of(unlocked_funds, asset_policy_id, asset_name)
  unlocked_amount < locked_amount
}

/// This function verifies that the `tx_id` used in both redeemers (the one for the
/// `txs_updater_validator` and the one for the `unlocking_validator`) is the same.
fn tx_id_in_both_redeemers_are_equal(
  tx: Transaction,
  tx_updater_input: Input,
  redeemer: ZK<BurningTxData>,
) -> Bool {
  let ZK { redeemer: BurningTxData { tx_id: burning_tx_id, .. }, .. } = redeemer

  expect Some(tx_updater_input_redeemer) =
    pairs.get_first(tx.redeemers, Spend(tx_updater_input.output_reference))
  expect ZK {
    redeemer: TxsUpdaterValidatorRedeemer { tx_id: tx_id_for_updater, .. },
    ..
  }: ZK<TxsUpdaterValidatorRedeemer> = tx_updater_input_redeemer

  (tx_id_for_updater == burning_tx_id)?
}

/// Receives a list of `Input`s and returns the first one that has an output
/// with the `txs_updater` NFT, or `None` if there is no such input.
fn find_input_with_txs_updater_nft(inputs: List<Input>) -> Option<Input> {
  list.find(inputs, fn(input) { output_has_txs_updater_nft(input.output) })
}

/// Receives a list of `Output`s and returns `True` if there is at least one
/// output with the `txs_updater` NFT, or `False` otherwise.
fn exists_an_output_with_txs_updater_nft(outputs: List<Output>) -> Bool {
  list.any(
    outputs,
    // The used_txs_output must have the tx_updater script as its address
    output_has_txs_updater_nft,
  )
}

/// This function finds the first output in the transaction that matches the given address.
fn find_output_of_address(address: Address, tx: Transaction) -> Option<Output> {
  list.find(
    tx.outputs,
    fn(o) { o.address.payment_credential == address.payment_credential },
  )
}

/// Receives a transaction, an input that is being unlocked, and the value
/// corresponding to the burning transaction, and verifies if there is a valid
/// change output in the transaction.
fn there_is_a_valid_change_output(
  tx: Transaction,
  locked_assets_input: Input,
  burning_tx_value: Value,
) -> Bool {
  expect Some(_) =
    list.find(
      tx.outputs,
      fn(o) {
        change_output_is_well_formed(locked_assets_input, o, burning_tx_value)
      },
    )
  True
}

validator unlocking_validator {
  spend(
    _d,
    redeemer: ZK<BurningTxData>,
    own_ref: OutputReference,
    tx: Transaction,
  ) {
    expect Some(locked_assets_input) =
      list.find(tx.inputs, fn(input) { input.output_reference == own_ref })

    expect Some(used_txs_input) = find_input_with_txs_updater_nft(tx.inputs)

    let ZK { redeemer: burning_tx_data, proofs: _proofs } = redeemer

    let unlocked_token_policy_id = burning_tx_data.transferred_asset_policy_id
    let unlocked_token_asset_name = burning_tx_data.transferred_asset_name
    let unlocked_token_amount = burning_tx_data.transferred_amount
    let burning_tx_value: Value =
      assets.from_asset(
        unlocked_token_policy_id,
        unlocked_token_asset_name,
        unlocked_token_amount,
      )
    expect exists_an_output_with_txs_updater_nft(tx.outputs)

    expect Some(unlocked_funds_output) =
      find_output_of_address(burning_tx_data.destination_address, tx)

    if tx_has_change(
      locked_assets_input.output.value,
      unlocked_funds_output.value,
      unlocked_token_asset_name,
      unlocked_token_policy_id,
    ) {
      expect
        there_is_a_valid_change_output(
          tx,
          locked_assets_input,
          burning_tx_value,
        )?
    } else {
      // locked funds and unlocked funds values must be equal
      expect
        assets.quantity_of(
          locked_assets_input.output.value,
          unlocked_token_policy_id,
          unlocked_token_asset_name,
        ) == unlocked_token_amount
    }

    and {
      tx_id_in_both_redeemers_are_equal(tx, used_txs_input, redeemer)?,
      burning_zk_proof_is_valid(redeemer)?,
      // unlocked funds match the amount of the burning transaction given in the redeemer
      (assets.quantity_of(
        unlocked_funds_output.value,
        unlocked_token_policy_id,
        unlocked_token_asset_name,
      ) == unlocked_token_amount)?,
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
  zk_redeemer: ZK<BurningTxData>,
  public_inputs: List<ZKInputType>,
) -> ZK<BurningTxData> {
  let vk: SnarkVerificationKey =
    SnarkVerificationKey {
      nPublic: 1,
      vkAlpha: #"85e3f8a13a670514351a68677ea0e2fc51150daeea496b85a34d97751695e26b2ae4f1a5a3b60e17bb7bfd6d474154c5",
      vkBeta: #"b1abf58f58af5981cd24f996e53626a4157eeed4aa814498885b3a547c35d5efb877834602508255c030708552b353e21631f16475e35b977e39a068ac9fb5bc4c25d383139b721da0a878b663c4df52c94a51f7c06a019bb40324713d2bbf0f",
      vkGamma: #"93e02b6052719f607dacd3a088274f65596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e024aa2b2f08f0a91260805272dc51051c6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8",
      vkDelta: #"b824005d651bf6d38362f30967f78a33381fde734ebd5687265d2b250f54aa5b10860c1e0cd522e375a7f04178efe69c0747d9ee650176e8376346111c82fd997c3b16604ef241edd84843e9d84a3fd3833bcb2308b5ce4dfa9f465b18dbec7c",
      vkAlphaBeta: [],
      vkIC: [
        #"b8fcac9bb8eebddd4daf43519eb65d952436f5e98be287e246d70fc27f267379e132a156f6a4a742ece62fbb7c5e220d",
        #"99f6c043cc37650767938eb567327aca0e82fb1dcab833778a6b8d5c8d13a8f53d784e7dfbcba6d3c71b57b908530048",
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
