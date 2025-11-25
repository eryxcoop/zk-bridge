use cardano/address.{Address, VerificationKey}
use cardano/transaction.{OutputReference}

/// This is an file which includes constants needed for testing
pub const bridge_locked_token_policy_id =
  #"5d549554095c29cff93f6426e1fc3e7e0491465d3d0716479d52747d"

pub const bridge_locked_token_asset_name = "mock_asset_name"

pub const burning_transaction_id = "tx_id"

pub const unlocking_transaction_id = "transaction_id"

pub const chain_a_destination_address =
  Address {
    payment_credential: VerificationKey("a_valid_verification_key"),
    stake_credential: None,
  }

pub const locked_assets_utxo_ref: OutputReference =
  OutputReference { transaction_id: "locked_funds_tx_id", output_index: 0 }

pub const last_tx_set_updater_output_reference: OutputReference =
  OutputReference { transaction_id: "last_tx_set_updater_id", output_index: 0 }
