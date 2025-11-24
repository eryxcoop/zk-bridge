use cardano/address.{Credential, Script}
use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference}

/// This is an `env` file which includes constants needed for the validators 
pub const txs_updater_asset_name: ByteArray = "TxsUpdaterNFT"

pub const txs_updater_policy_id: PolicyId =
  #"459ebee17eba0cccb35b9f9cd7996e50fe851a76311d9c74b42b4389"

pub const txs_updater_spending_script: Credential =
  Script(#"6ff3a8938aa5a23d69afc251af0f617b7b5bdfc8d52e03addaf1ebd4")

pub const txs_updater_unique_mint_utxo_ref: OutputReference =
  OutputReference {
    transaction_id: #"e402f971a5143cb92f28fa7ca98450e641edcbd789458adc6555c227ad3468a5",
    output_index: 1,
  }

pub const unlocked_funds_spending_script: Credential =
  Script(#"cffd6c057a32b6c723397638d517e920cdd67886aca28f5e025b99b2")
