use aiken/collection/list
use cardano/address.{Address, VerificationKey}
use cardano/assets.{PolicyId, Value}
use cardano/transaction.{Input, Output, OutputReference, Transaction}
use common_types.{BurningTxData}
use env
use validator_aux_functions.{
  find_output_with_value, locking_tx_hash_is_added_to_the_used_txs_set,
}
use zk_verification.{Single, empty_circuit_vk, zk_verify}

/// This proof should verify a circuit that proves that an UTxO with a given `amount`, `asset_name`
/// and `policy_id` was burned in a transaction in the bridge's destination chain. Since this bridge
/// will not have a counter part we are going to use an example circuit for this. The circuit has
/// no constraints and it can be found in `circuits/burning_circuit.circom`.
pub fn burning_zk_proof_is_valid(redeemer: BurningTxData) -> Bool {
  let public_input = redeemer.transferred_amount
  let burning_circuit_vk = burning_tx_verification_circuit_vk()
  zk_verify(
    redeemer.burning_tx_proof,
    [Single(public_input)],
    burning_circuit_vk,
  )
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
    (change_output.address.payment_credential == input.output.address.payment_credential)?,
    assets.match(combined_value, input.output.value, ==)?,
  }
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
  (unlocked_amount < locked_amount)?
}

fn value_for(tx_data: BurningTxData) -> Value {
  assets.from_asset(
    tx_data.transferred_asset_policy_id,
    tx_data.transferred_asset_name,
    tx_data.transferred_amount,
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
  list.any(
    tx.outputs,
    fn(o) {
      change_output_is_well_formed(locked_assets_input, o, burning_tx_value)
    },
  )?
}

validator unlocking_validator {
  spend(_d, redeemer: BurningTxData, own_ref: OutputReference, tx: Transaction) {
    expect Some(locked_assets_input) =
      list.find(tx.inputs, fn(input) { input.output_reference == own_ref })

    expect Some(unlocked_funds_output) =
      find_output_with_value(
        tx,
        value_for(redeemer),
        VerificationKey(redeemer.destination_address_vk),
      )

    let unlocked_token_policy_id = redeemer.transferred_asset_policy_id
    let unlocked_token_asset_name = redeemer.transferred_asset_name
    let unlocked_token_amount = redeemer.transferred_amount
    let burning_tx_value: Value = value_for(redeemer)

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
      locking_tx_hash_is_added_to_the_used_txs_set(
        tx,
        redeemer.tx_id,
        env.burning_txs_updater_policy_id,
        env.burning_txs_updater_asset_name,
      )?,
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

fn burning_tx_verification_circuit_vk() {
  empty_circuit_vk()
}
