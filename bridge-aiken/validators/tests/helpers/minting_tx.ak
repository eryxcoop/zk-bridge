use bridge/common_types.{TxsUpdaterDatum}
use cardano/address.{Address, PaymentCredential, VerificationKey}
use cardano/assets.{PolicyId, add, from_asset, from_lovelace}
use cardano/transaction.{
  InlineDatum, Input, Mint, NoDatum, Output, OutputReference, ScriptPurpose,
  Spend, Transaction,
}
use env
use tests/helpers/certificates/cardano_transactions.{
  parent_of_simple_cardano_transactions_certificate,
  simple_cardano_transactions_certificate,
}
use tests/helpers/certificates/stake_distribution_certificates.{
  simple_sd_certificate,
}
use tests/helpers/locking_tx.{simple_locking_tx}
use tests/helpers/minting_redeemer.{
  a_valid_minting_proof, generate_minting_validator_redeemer,
  simple_minting_validator_redeemer,
  valid_snapshot_membership_minting_redeemer,
}
use tests/helpers/proof_receipt
use tests/helpers/stake_distribution_tx.{sd_certificate_to_stake_output}
use tests/helpers/test_constants
use tests/helpers/txs_updater_redeemer.{simple_txs_updater_redeemer}
use tests/helpers/values.{build_value_with_native_token}
use two_phase/two_phase_types.{ProofReceiptDatum}

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
      datum: InlineDatum(
        TxsUpdaterDatum {
          merkle_root: env.locking_txs_updater_initial_merkle_root,
        },
      ),
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
    mint: from_asset(transferred_asset_policy_id, env.transferred_asset_name, 1),
    reference_inputs,
    redeemers: redeemers_for_transaction(),
  }
}

// Stake-distribution validator output for the locking transaction's epoch.
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

fn phase2_receipt_input(statement_hash: ByteArray) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: "phase2_receipt_tx_id",
      output_index: 0,
    },
    output: Output {
      address: Address {
        payment_credential: proof_receipt.proof_receipt_spending_script,
        stake_credential: None,
      },
      value: from_lovelace(2_000_000)
        |> add(env.phase2_asset_policy_id, "phase2_receipt", 1),
      datum: InlineDatum(ProofReceiptDatum { statement_hash }),
      reference_script: None,
    },
  }
}

fn simple_phase2_receipt_input() -> Input {
  phase2_receipt_input(simple_cardano_transactions_certificate().signed_message)
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
    datum: InlineDatum(
      TxsUpdaterDatum {
        merkle_root: test_constants.tx_set_update_fixture_root_out,
      },
    ),
    reference_script: None,
  }
}

fn simple_minting_inputs() -> List<Input> {
  [locking_txs_set_input(), simple_phase2_receipt_input()]
}

fn simple_minting_outputs() -> List<Output> {
  [simple_tx_updater_output(), simple_minting_output(1)]
}

fn simple_reference_inputs() -> List<Input> {
  [
    reference_input_with_sd_certificate(
      parent_of_simple_cardano_transactions_certificate(),
    ),
  ]
}

pub fn simple_minting_tx() -> Transaction {
  generate_minting_tx(
    simple_minting_inputs(),
    simple_minting_outputs(),
    simple_reference_inputs(),
    env.transferred_asset_policy_id,
  )
}

pub fn simple_minting_tx_with_many_outputs() -> Transaction {
  generate_minting_tx(
    [
      locking_txs_set_input(),
      simple_phase2_receipt_input(),
      some_unrelated_input(),
    ],
    [
      some_unrelated_output(),
      simple_tx_updater_output(),
      simple_minting_output(1),
    ],
    simple_reference_inputs(),
    env.transferred_asset_policy_id,
  )
}

pub fn simple_minting_tx_with_many_reference_inputs() -> Transaction {
  generate_minting_tx(
    simple_minting_inputs(),
    simple_minting_outputs(),
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
    [
      some_unrelated_input(),
      locking_txs_set_input(),
      simple_phase2_receipt_input(),
    ],
    simple_minting_outputs(),
    simple_reference_inputs(),
    env.transferred_asset_policy_id,
  )
}

pub fn minting_tx_without_tx_updater_nft() -> Transaction {
  generate_minting_tx(
    [some_unrelated_input(), simple_phase2_receipt_input()],
    simple_minting_outputs(),
    simple_reference_inputs(),
    env.transferred_asset_policy_id,
  )
}

pub fn minting_tx_with_an_incorrect_mint_value() -> Transaction {
  generate_minting_tx(
    simple_minting_inputs(),
    simple_minting_outputs(),
    simple_reference_inputs(),
    "an_invalid_policy_id",
  )
}

pub fn minting_tx_without_phase2_receipt() -> Transaction {
  generate_minting_tx(
    [locking_txs_set_input()],
    simple_minting_outputs(),
    [
      reference_input_with_sd_certificate(
        parent_of_simple_cardano_transactions_certificate(),
      ),
    ],
    env.transferred_asset_policy_id,
  )
}

pub fn minting_tx_with_phase2_receipt_as_reference_input() -> Transaction {
  generate_minting_tx(
    [locking_txs_set_input()],
    simple_minting_outputs(),
    [
      reference_input_with_sd_certificate(
        parent_of_simple_cardano_transactions_certificate(),
      ),
      phase2_receipt_input(
        simple_cardano_transactions_certificate().signed_message,
      ),
    ],
    env.transferred_asset_policy_id,
  )
}

pub fn minting_tx_with_incorrect_phase2_statement_hash() -> Transaction {
  generate_minting_tx(
    [
      locking_txs_set_input(),
      phase2_receipt_input(
        #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      ),
    ],
    simple_minting_outputs(),
    [
      reference_input_with_sd_certificate(
        parent_of_simple_cardano_transactions_certificate(),
      ),
    ],
    env.transferred_asset_policy_id,
  )
}

pub fn minting_tx_with_incorrect_parent_certificate() -> Transaction {
  generate_minting_tx(
    simple_minting_inputs(),
    simple_minting_outputs(),
    [reference_input_with_sd_certificate(simple_sd_certificate())],
    env.transferred_asset_policy_id,
  )
}

fn redeemers_for_transaction() -> Pairs<ScriptPurpose, Data> {
  let minting_redeemer = simple_minting_validator_redeemer()
  let locking_tx_id = minting_redeemer.locking_tx_hash
  let minting_redeemer_data: Data = minting_redeemer

  let txs_updater_data: Data = simple_txs_updater_redeemer(locking_tx_id)
  [
    Pair(
      Spend(test_constants.last_tx_set_updater_output_reference),
      txs_updater_data,
    ),
    Pair(Mint(env.bridge_minting_policy_id), minting_redeemer_data),
  ]
}

pub fn simple_minting_tx_with_fixed_locking_tx_hash(
  locking_tx_hash: ByteArray,
) -> Transaction {
  let locking_tx = simple_locking_tx()
  let minting_redeemer_data: Data = generate_minting_validator_redeemer(
    locking_tx,
    a_valid_minting_proof(),
    Some(locking_tx_hash),
    test_constants.destination_chain_address,
  )
  let txs_updater_redeemer_data: Data = simple_txs_updater_redeemer(
    locking_tx_hash,
  )

  Transaction {
    ..simple_minting_tx(),
    redeemers: [
      Pair(
        Spend(test_constants.last_tx_set_updater_output_reference),
        txs_updater_redeemer_data,
      ),
      Pair(Mint(env.bridge_minting_policy_id), minting_redeemer_data),
    ],
  }
}

pub fn simple_minting_tx_with_mismatched_txs_updater_tx_id() -> Transaction {
  let minting_redeemer_data: Data = valid_snapshot_membership_minting_redeemer()
  let txs_updater_redeemer_data: Data = simple_txs_updater_redeemer(
    "another_transaction_id",
  )

  Transaction {
    ..simple_minting_tx(),
    redeemers: [
      Pair(
        Spend(test_constants.last_tx_set_updater_output_reference),
        txs_updater_redeemer_data,
      ),
      Pair(Mint(env.bridge_minting_policy_id), minting_redeemer_data),
    ],
  }
}
