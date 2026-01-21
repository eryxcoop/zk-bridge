use cardano/address.{Address, Script}
use cardano/assets.{PolicyId}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, ScriptPurpose, Spend, Transaction,
}
use common_types.{MerkleRoot, TxsUpdaterDatum}
use env
use tests/helpers/burning_tx_data.{valid_unlocking_redeemer}
use tests/helpers/locking_tx.{locking_tx_output}
use tests/helpers/test_constants
use tests/helpers/txs_updater_redeemer.{simple_txs_updater_redeemer}
use tests/helpers/values.{build_value_with_native_token}

fn burning_tx_updater_output(
  asset_name: ByteArray,
  asset_ammount: Int,
  policy_id: PolicyId,
  mk_root: MerkleRoot,
) {
  Output {
    address: Address {
      payment_credential: Script(policy_id),
      stake_credential: None,
    },
    value: build_value_with_native_token(policy_id, asset_name, asset_ammount),
    datum: InlineDatum(TxsUpdaterDatum { merkle_root: mk_root }),
    reference_script: None,
  }
}

fn burning_tx_set_updater_input() -> Input {
  Input {
    output_reference: test_constants.last_tx_set_updater_output_reference,
    output: burning_tx_updater_output(
      env.burning_txs_updater_asset_name,
      1,
      env.burning_txs_updater_policy_id,
      "old",
    ),
  }
}

fn locking_assets_input(amount_of_assets: Int) -> Input {
  Input {
    output_reference: test_constants.locked_assets_utxo_ref,
    output: locking_tx_output(amount_of_assets),
  }
}

fn redeemers_for_transaction(unlocked_amount: Int) -> Pairs<ScriptPurpose, Data> {
  let unlocking_redeemer_data: Data =
    valid_unlocking_redeemer(
      test_constants.burning_transaction_id,
      unlocked_amount,
      test_constants.chain_a_destination_address_vk,
    )
  let txs_updater_data: Data =
    simple_txs_updater_redeemer(test_constants.burning_transaction_id)
  [
    Pair(
      Spend(test_constants.last_tx_set_updater_output_reference),
      txs_updater_data,
    ),
    Pair(Spend(test_constants.locked_assets_utxo_ref), unlocking_redeemer_data),
  ]
}

fn generate_unlocking_tx_without_change(
  locked_amount: Int,
  txs_updater_asset_name: ByteArray,
  txs_updater_policy_id: PolicyId,
  txs_updater_amount: Int,
  unlocked_amount: Int,
) -> Transaction {
  Transaction {
    ..transaction.placeholder,
    id: test_constants.unlocking_transaction_id,
    inputs: [
      burning_tx_set_updater_input(),
      locking_assets_input(amount_of_assets: locked_amount),
    ],
    outputs: [
      burning_tx_updater_output(
        txs_updater_asset_name,
        txs_updater_amount,
        txs_updater_policy_id,
        "new",
      ),
      Output {
        address: test_constants.chain_a_destination_address,
        value: build_value_with_native_token(
          env.transferred_asset_policy_id,
          env.transferred_asset_name,
          unlocked_amount,
        ),
        datum: NoDatum,
        reference_script: None,
      },
    ],
    redeemers: redeemers_for_transaction(unlocked_amount),
  }
}

fn generate_unlocking_tx_with_change(
  change_output_address: Address,
  locked_amount: Int,
  unlocked_amount: Int,
  change_amount: Int,
) -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: [
      burning_tx_set_updater_input(),
      locking_assets_input(amount_of_assets: locked_amount),
    ],
    outputs: [
      burning_tx_updater_output(
        env.burning_txs_updater_asset_name,
        1,
        env.burning_txs_updater_policy_id,
        "new",
      ),
      Output {
        address: test_constants.chain_a_destination_address,
        value: build_value_with_native_token(
          env.transferred_asset_policy_id,
          env.transferred_asset_name,
          unlocked_amount,
        ),
        datum: NoDatum,
        reference_script: None,
      },
      Output {
        address: change_output_address,
        value: build_value_with_native_token(
          env.transferred_asset_policy_id,
          env.transferred_asset_name,
          change_amount,
        ),
        datum: NoDatum,
        reference_script: None,
      },
    ],
    redeemers: redeemers_for_transaction(unlocked_amount),
  }
}

pub fn simple_unlocking_tx() -> Transaction {
  generate_unlocking_tx_without_change(
    locked_amount: 3,
    txs_updater_asset_name: env.burning_txs_updater_asset_name,
    txs_updater_policy_id: env.burning_txs_updater_policy_id,
    txs_updater_amount: 1,
    unlocked_amount: 3,
  )
}

pub fn unlocking_tx_with_output_with_incorrect_txs_updater_asset_name() -> Transaction {
  generate_unlocking_tx_without_change(
    locked_amount: 3,
    txs_updater_asset_name: "incorrect_txs_updater_asset_name",
    txs_updater_policy_id: env.burning_txs_updater_policy_id,
    txs_updater_amount: 1,
    unlocked_amount: 3,
  )
}

pub fn unlocking_tx_with_incorrect_txs_updater_policy_id_output() -> Transaction {
  generate_unlocking_tx_without_change(
    locked_amount: 3,
    txs_updater_asset_name: env.burning_txs_updater_asset_name,
    txs_updater_policy_id: "incorrect_txs_updater_policy_id",
    txs_updater_amount: 1,
    unlocked_amount: 3,
  )
}

pub fn unlocking_tx_with_incorrect_txs_updater_nft_amount() -> Transaction {
  generate_unlocking_tx_without_change(
    locked_amount: 3,
    txs_updater_asset_name: env.burning_txs_updater_asset_name,
    txs_updater_policy_id: env.burning_txs_updater_policy_id,
    txs_updater_amount: 2,
    unlocked_amount: 3,
  )
}

pub fn unlocking_tx_with_bigger_amount() -> Transaction {
  generate_unlocking_tx_without_change(
    locked_amount: 3,
    txs_updater_asset_name: env.burning_txs_updater_asset_name,
    txs_updater_policy_id: env.burning_txs_updater_policy_id,
    txs_updater_amount: 1,
    unlocked_amount: 4,
  )
}

pub fn unlocking_tx_without_burning_transactions_set() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: [locking_assets_input(amount_of_assets: 1)],
    outputs: [
      burning_tx_updater_output(
        env.burning_txs_updater_asset_name,
        3,
        env.burning_txs_updater_policy_id,
        "new",
      ),
      Output {
        address: test_constants.chain_a_destination_address,
        value: build_value_with_native_token(
          env.transferred_asset_policy_id,
          env.transferred_asset_name,
          1,
        ),
        datum: NoDatum,
        reference_script: None,
      },
    ],
  }
}

pub fn unlocking_tx_with_change() -> Transaction {
  generate_unlocking_tx_with_change(
    change_output_address: Address {
      payment_credential: env.unlocked_funds_spending_script,
      stake_credential: None,
    },
    locked_amount: 4,
    unlocked_amount: 3,
    change_amount: 1,
  )
}

pub fn unlocking_tx_with_change_with_bigger_ammount() -> Transaction {
  generate_unlocking_tx_with_change(
    change_output_address: Address {
      payment_credential: env.unlocked_funds_spending_script,
      stake_credential: None,
    },
    locked_amount: 4,
    unlocked_amount: 3,
    change_amount: 2,
  )
}

pub fn unlocking_tx_with_incorrect_change_output_address() -> Transaction {
  generate_unlocking_tx_with_change(
    change_output_address: address.from_script("invalid_payment_credential"),
    locked_amount: 3,
    unlocked_amount: 2,
    change_amount: 1,
  )
}

pub fn unlocking_tx_with_input_redeemers_with_different_tx_id() -> Transaction {
  let unlocked_amount: Int = 3
  let redeemers = {
    let unlocking_redeemer_data: Data =
      valid_unlocking_redeemer(
        "some_transaction_id",
        unlocked_amount,
        test_constants.chain_a_destination_address_vk,
      )
    let txs_updater_data: Data =
      simple_txs_updater_redeemer("another_transaction_id")
    [
      Pair(
        Spend(test_constants.last_tx_set_updater_output_reference),
        txs_updater_data,
      ),
      Pair(
        Spend(test_constants.locked_assets_utxo_ref),
        unlocking_redeemer_data,
      ),
    ]
  }
  Transaction {
    ..transaction.placeholder,
    id: test_constants.unlocking_transaction_id,
    inputs: [
      burning_tx_set_updater_input(),
      locking_assets_input(amount_of_assets: unlocked_amount),
    ],
    outputs: [
      burning_tx_updater_output(
        env.burning_txs_updater_asset_name,
        1,
        env.burning_txs_updater_policy_id,
        "new",
      ),
      Output {
        address: test_constants.chain_a_destination_address,
        value: build_value_with_native_token(
          env.transferred_asset_policy_id,
          env.transferred_asset_name,
          unlocked_amount,
        ),
        datum: NoDatum,
        reference_script: None,
      },
    ],
    redeemers,
  }
}
