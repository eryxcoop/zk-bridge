use aiken/crypto.{VerificationKeyHash}
use cardano/address.{Address, VerificationKey}
use cardano/transaction.{OutputReference}

/// This is an file which includes constants needed for testing

pub const burning_transaction_id = "tx_id"

pub const locking_transaction_id = "tx_id" // For the same mock proof to work, we made this value equal to `burning_transaction_id`

pub const unlocking_transaction_id = "transaction_id"

pub const chain_a_destination_address_vk: VerificationKeyHash = "a_valid_verification_key"

pub const chain_a_destination_address: Address = Address {
  payment_credential: VerificationKey(chain_a_destination_address_vk),
  stake_credential: None,
}

pub const destination_chain_address = VerificationKey("my_verification_key_in_chain_B")

pub const locked_assets_utxo_ref: OutputReference =
  OutputReference { transaction_id: locking_transaction_id, output_index: 0 }

pub const last_tx_set_updater_output_reference: OutputReference =
  OutputReference { transaction_id: "last_tx_set_updater_id", output_index: 0 }
