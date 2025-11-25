use aiken/crypto.{Blake2b_224, Hash}
use cardano/address.{Address, VerificationKey}
use cardano/assets.{PolicyId}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
}
use common_types.{TxUpdaterDatum}
use env
use tests/helpers/values.{build_value_with_native_token}

fn generate_txs_updater_mint_tx(
  output_datum: Hash<Blake2b_224, ByteArray>,
  unique_mint_utxo_ref: OutputReference,
  nft_policy_id: PolicyId,
  nft_asset_name: ByteArray,
  nft_amount: Int,
) -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: [
      Input {
        output_reference: unique_mint_utxo_ref,
        output: Output {
          address: Address {
            payment_credential: VerificationKey("some_payment_credential"),
            stake_credential: None,
          },
          value: assets.zero,
          datum: NoDatum,
          reference_script: None,
        },
      },
    ],
    outputs: [
      Output {
        address: Address {
          payment_credential: env.txs_updater_spending_script,
          stake_credential: None,
        },
        value: build_value_with_native_token(
          nft_policy_id,
          nft_asset_name,
          nft_amount,
        ),
        datum: InlineDatum(TxUpdaterDatum { merkle_root: output_datum }),
        reference_script: None,
      },
    ],
  }
}

pub fn valid_txs_updater_mint_tx() -> Transaction {
  generate_txs_updater_mint_tx(
    output_datum: crypto.blake2b_224(""),
    unique_mint_utxo_ref: env.txs_updater_unique_mint_utxo_ref,
    nft_policy_id: env.txs_updater_policy_id,
    nft_asset_name: env.txs_updater_asset_name,
    nft_amount: 1,
  )
}

pub fn txs_updater_mint_tx_with_invalid_datum() -> Transaction {
  generate_txs_updater_mint_tx(
    output_datum: "an_invalid_hash",
    unique_mint_utxo_ref: env.txs_updater_unique_mint_utxo_ref,
    nft_policy_id: env.txs_updater_policy_id,
    nft_asset_name: env.txs_updater_asset_name,
    nft_amount: 1,
  )
}

pub fn txs_updater_mint_tx_for_an_incorrect_utxo() -> Transaction {
  let invalid_utxo_ref: OutputReference =
    OutputReference { transaction_id: "some_tx_id", output_index: 0 }
  generate_txs_updater_mint_tx(
    output_datum: crypto.blake2b_224(""),
    unique_mint_utxo_ref: invalid_utxo_ref,
    nft_policy_id: env.txs_updater_policy_id,
    nft_asset_name: env.txs_updater_asset_name,
    nft_amount: 1,
  )
}

pub fn txs_updater_mint_with_incorrect_nft_policy_id() -> Transaction {
  generate_txs_updater_mint_tx(
    output_datum: crypto.blake2b_224(""),
    unique_mint_utxo_ref: env.txs_updater_unique_mint_utxo_ref,
    nft_policy_id: "an_incorrect_policy_id",
    nft_asset_name: env.txs_updater_asset_name,
    nft_amount: 1,
  )
}

pub fn txs_updater_mint_with_incorrect_nft_asset_name() -> Transaction {
  generate_txs_updater_mint_tx(
    output_datum: crypto.blake2b_224(""),
    unique_mint_utxo_ref: env.txs_updater_unique_mint_utxo_ref,
    nft_policy_id: env.txs_updater_policy_id,
    nft_asset_name: "an_incorrect_asset_name",
    nft_amount: 1,
  )
}

pub fn txs_updater_mint_with_incorrect_nft_asset_amount() -> Transaction {
  generate_txs_updater_mint_tx(
    output_datum: crypto.blake2b_224(""),
    unique_mint_utxo_ref: env.txs_updater_unique_mint_utxo_ref,
    nft_policy_id: env.txs_updater_policy_id,
    nft_asset_name: env.txs_updater_asset_name,
    nft_amount: 2,
  )
}
