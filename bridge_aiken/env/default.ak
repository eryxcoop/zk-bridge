use cardano/address.{Credential, Script}
use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference}
use mithril_certificate.{GenesisVerificationKey}

/// This is an `env` file which includes constants needed for the validators
pub const cardano_current_epoch = 1086

// txs_updater_unlocking (i.e., for burning transactions)
pub const burning_txs_updater_asset_name: ByteArray = "TxsUpdaterNFT"

pub const burning_txs_updater_policy_id: PolicyId =
  #"e3629e11a475df98bd7cf97661ae1e701ac27ffa3f8f7878da8a3c10"

pub const burning_txs_updater_spending_script: Credential =
  Script(#"87a50143f0a5f82a0b13a9e9d7ed3be91be4884f348f2701fdfaa3ef")

pub const burning_txs_updater_unique_mint_utxo_ref: OutputReference =
  OutputReference {
    transaction_id: #"e402f971a5143cb92f28fa7ca98450e641edcbd789458adc6555c227ad3468a5",
    output_index: 1,
  }

// txs_updater_minting (i.e., for locking transactions)
pub const locking_txs_updater_asset_name: ByteArray = "TxsUpdaterNFT"

pub const locking_txs_updater_policy_id: PolicyId =
  #"e3629e11a475df98bd7cf97661ae1e701ac27ffa3f8f7878da8a3c10"

pub const locking_txs_updater_spending_script: Credential =
  Script(#"4a0272a1d764b613b0ffd10b56f4a2698863920bb00e5bd3ed919005")

pub const locking_txs_updater_unique_mint_utxo_ref: OutputReference =
  OutputReference {
    transaction_id: #"e402f971a5143cb92f28fa7ca98450e641edcbd789458adc6555c227ad3468a5",
    output_index: 1,
  }

// unlocking validator
pub const unlocked_funds_spending_script: Credential =
  Script(#"6ff9b5e2926e9eb6601647b004bd8ea5c674e5ebab02549c876e55ae")

// stake distribution validator
pub const genesis_verification_key: GenesisVerificationKey =
  GenesisVerificationKey(#"0123456789abcdef")

pub const stake_distribution_spending_script: Credential =
  Script(#"e2f4efe0c77d7f6add29be633560a6c0eefdbda2291408d76350525b")

pub const stake_distribution_asset_policy_id: PolicyId =
  #"9cda26b0dd12e94e240748d5c3d439759e56d6a105e0412b596153b3"

pub const stake_distribution_asset_name: ByteArray = "stake_distribution_asset"

pub const stake_distribution_asset_unique_mint_utxo_ref: OutputReference =
  OutputReference {
    transaction_id: #"84611871a5143cb92f28fa7ca98450e641edcbd789458adc6555c227ade52681",
    output_index: 1,
  }

// transferred asset
pub const transferred_asset_policy_id: PolicyId = "token_policy_id"

pub const transferred_asset_name: ByteArray = "token_asset_name"

// minting validator
pub const bridge_minting_policy_id: PolicyId =
  #"562eb744b49671e3525b976d05bb8f4b66113207766fe165ffb98935"
