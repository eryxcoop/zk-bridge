use aiken/cbor.{serialise}
use aiken/crypto.{sha3_256}
use cardano/address.{Address, PaymentCredential, VerificationKey}
use cardano/assets.{PolicyId, from_asset, from_lovelace}
use cardano/transaction.{
  InlineDatum, Input, Mint, NoDatum, Output, OutputReference, ScriptPurpose,
  Spend, Transaction,
}
use common_types.{TxsUpdaterDatum}
use env
use tests/helpers/certificates.{
  parent_of_simple_cardano_transactions_certificate,
}
use tests/helpers/locking_tx.{simple_locking_tx}
use tests/helpers/minting_redeemer.{simple_minting_validator_redeemer}
use tests/helpers/stake_distribution_tx.{sd_certificate_to_stake_output}
use tests/helpers/test_constants
use tests/helpers/txs_updater_redeemer.{simple_txs_updater_redeemer}
use tests/helpers/values.{build_value_with_native_token}

// An input that is unrelated to any bridge, it is used for testing purposes
fn some_unrelated_input() {
  Input {
    output_reference: OutputReference {
      transaction_id: "other_tx_id",
      output_index: 0,
    },
    output: some_unrelated_output(),
  }
}

fn some_unrelated_output() {
  Output {
    address: Address {
      payment_credential: VerificationKey("some_credential"),
      stake_credential: None,
    },
    value: from_lovelace(1000000),
    datum: NoDatum,
    reference_script: None,
  }
}

// An input that contains a locking txs set UTXO
fn locking_txs_set_input() {
  Input {
    output_reference: test_constants.last_tx_set_updater_output_reference,
    output: Output {
      address: Address {
        payment_credential: env.locking_txs_updater_spending_script,
        stake_credential: None,
      },
      value: build_value_with_native_token(
        env.locking_txs_updater_policy_id,
        env.locking_txs_updater_asset_name,
        1,
      ),
      datum: InlineDatum("old_merkle_root"),
      reference_script: None,
    },
  }
}

pub fn generate_minting_tx(
  inputs: List<Input>,
  outputs: List<Output>,
  reference_inputs: List<Input>,
  transferred_asset_policy_id: PolicyId,
) -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs,
    outputs,
    mint: from_asset(
      transferred_asset_policy_id,
      env.transferred_asset_name,
      1,
    ),
    reference_inputs,
    redeemers: redeemers_for_transaction(),
  }
}

// Un UTxO que representa un certificado de Mithril de stake distribution para la época de la transacción `locking_tx`. Estos se van generando una vez por época según el Stake Distribution Validator.
fn reference_input_with_sd_certificate(certificate) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: "some_tx_id",
      output_index: 0,
    },
    output: sd_certificate_to_stake_output(
      certificate,
      env.stake_distribution_spending_script,
    ),
  }
}

fn simple_minting_output(minted_amount: Int) -> Output {
  Output {
    address: Address {
      payment_credential: test_constants.destination_chain_address,
      stake_credential: None,
    },
    value: build_value_with_native_token(
      env.transferred_asset_policy_id,
      env.transferred_asset_name,
      minted_amount,
    ),
    datum: NoDatum,
    reference_script: None,
  }
}

fn simple_tx_updater_output() -> Output {
  tx_updater_output_with(
    env.locking_txs_updater_policy_id,
    env.locking_txs_updater_asset_name,
    1,
    env.locking_txs_updater_spending_script,
  )
}

fn tx_updater_output_with(
  new_nft_policy_id: PolicyId,
  new_nft_asset_name: ByteArray,
  new_nft_asset_amount: Int,
  new_nft_spending_script: PaymentCredential,
) -> Output {
  Output {
    address: Address {
      payment_credential: new_nft_spending_script,
      stake_credential: None,
    },
    value: build_value_with_native_token(
      new_nft_policy_id,
      new_nft_asset_name,
      new_nft_asset_amount,
    ),
    datum: InlineDatum(TxsUpdaterDatum { merkle_root: "new" }),
    reference_script: None,
  }
}

pub fn simple_minting_tx() -> Transaction {
  generate_minting_tx(
    [locking_txs_set_input()],
    [simple_tx_updater_output(), simple_minting_output(1)],
    [
      reference_input_with_sd_certificate(
        parent_of_simple_cardano_transactions_certificate(),
      ),
    ],
    env.transferred_asset_policy_id,
  )
}

pub fn simple_minting_tx_with_many_outputs() -> Transaction {
  generate_minting_tx(
    [locking_txs_set_input(), some_unrelated_input()],
    [
      some_unrelated_output(),
      simple_tx_updater_output(),
      simple_minting_output(1),
    ],
    [
      reference_input_with_sd_certificate(
        parent_of_simple_cardano_transactions_certificate(),
      ),
    ],
    env.transferred_asset_policy_id,
  )
}

pub fn simple_minting_tx_with_many_reference_inputs() -> Transaction {
  generate_minting_tx(
    [locking_txs_set_input()],
    [simple_tx_updater_output(), simple_minting_output(1)],
    [
      some_unrelated_input(),
      reference_input_with_sd_certificate(
        parent_of_simple_cardano_transactions_certificate(),
      ),
    ],
    env.transferred_asset_policy_id,
  )
}

pub fn simple_minting_tx_with_many_inputs() -> Transaction {
  generate_minting_tx(
    [some_unrelated_input(), locking_txs_set_input()],
    [simple_tx_updater_output(), simple_minting_output(1)],
    [
      reference_input_with_sd_certificate(
        parent_of_simple_cardano_transactions_certificate(),
      ),
    ],
    env.transferred_asset_policy_id,
  )
}

pub fn minting_tx_without_tx_updater_nft() -> Transaction {
  generate_minting_tx(
    [some_unrelated_input()],
    [simple_tx_updater_output(), simple_minting_output(1)],
    [
      reference_input_with_sd_certificate(
        parent_of_simple_cardano_transactions_certificate(),
      ),
    ],
    env.transferred_asset_policy_id,
  )
}

pub fn minting_tx_with_an_incorrect_mint_value() -> Transaction {
  generate_minting_tx(
    [locking_txs_set_input()],
    [simple_tx_updater_output(), simple_minting_output(1)],
    [
      reference_input_with_sd_certificate(
        parent_of_simple_cardano_transactions_certificate(),
      ),
    ],
    "an_invalid_policy_id",
  )
}

fn redeemers_for_transaction() -> Pairs<ScriptPurpose, Data> {
  let locking_tx = simple_locking_tx()
  let locking_tx_id = sha3_256(serialise(locking_tx))
  let minting_redeemer_data: Data = simple_minting_validator_redeemer()

  let txs_updater_data: Data = simple_txs_updater_redeemer(locking_tx_id)
  [
    Pair(
      Spend(test_constants.last_tx_set_updater_output_reference),
      txs_updater_data,
    ),
    Pair(Mint(env.bridge_minting_policy_id), minting_redeemer_data),
  ]
}
