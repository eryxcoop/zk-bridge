use cardano/address.{Address, Credential, Script, VerificationKey}
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
}
use certificate_signature.{GenesisSignature, MultiSignature}
use env
use mithril_certificate.{MithrilCertificate}
use stake_distribution.{StakeDistributionAssetDatum}
use tests/helpers/certificates.{
  parent_of_simple_sd_certificate,
  parent_of_standard_sd_certificate_with_incorrect_parent_hash,
  simple_genesis_certificate, simple_sd_certificate,
  standard_sd_certificate_with_incorrect_epoch_chaining,
  standard_sd_certificate_with_incorrect_parent_hash,
  standard_sd_certificate_with_incorrect_protocol_parameters,
  standard_sd_certificate_with_incorrect_signed_entity_type,
  standard_sd_certificate_with_incorrect_aggregate_verification_key,
}
use tests/helpers/values.{build_value_with_native_token}

pub fn sd_certificate_to_stake_output(certificate: MithrilCertificate, certificate_utxo_spending_script: Credential) {
  Output {
    address: Address {
      payment_credential: certificate_utxo_spending_script,
      stake_credential: None,
    },
    value: build_value_with_native_token(
      env.stake_distribution_asset_policy_id,
      env.stake_distribution_asset_name,
      1,
    ),
    datum: InlineDatum(StakeDistributionAssetDatum { certificate }),
    reference_script: None,
  }
}

fn generate_stake_distribution_tx_for_genesis_certificate(
  genesis_certificate: MithrilCertificate,
  unique_mint_utxo_ref: OutputReference,
  certificate_utxo_spending_script: Credential,
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
    mint: build_value_with_native_token(
      env.stake_distribution_asset_policy_id,
      env.stake_distribution_asset_name,
      1,
    ),
    outputs: [sd_certificate_to_stake_output(genesis_certificate, certificate_utxo_spending_script)],
  }
}

fn generate_stake_distribution_tx_for_standard_certificate(
  certificate: MithrilCertificate,
  parent_certificate: MithrilCertificate,
  certificate_utxo_spending_script: Credential,
) -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: [
      Input {
        output_reference: OutputReference {
          transaction_id: #"bbbbbb",
          output_index: 0,
        },
        output: sd_certificate_to_stake_output(parent_certificate, env.stake_distribution_spending_script),
      },
    ],
    outputs: [sd_certificate_to_stake_output(certificate, certificate_utxo_spending_script)],
  }
}

fn generate_stake_distribution_tx(
  certificate: MithrilCertificate,
  parent_certificate: Option<MithrilCertificate>,
  unique_mint_utxo_ref: Option<OutputReference>,
  certificate_utxo_spending_script: Credential,
) -> Transaction {
  when certificate.signature is {
    GenesisSignature { .. } -> {
      expect None = parent_certificate
      expect Some(unique_mint_utxo_ref) = unique_mint_utxo_ref
      generate_stake_distribution_tx_for_genesis_certificate(certificate, unique_mint_utxo_ref, certificate_utxo_spending_script)
    }
    MultiSignature { .. } -> {
      expect Some(parent_certificate) = parent_certificate
      expect None = unique_mint_utxo_ref
      generate_stake_distribution_tx_for_standard_certificate(
        certificate,
        parent_certificate,
        certificate_utxo_spending_script,
      )
    }
  }
}

pub fn simple_stake_distribution_tx_for_genesis_certificate() -> Transaction {
  generate_stake_distribution_tx(
    simple_genesis_certificate(),
    None,
    Some(env.stake_distribution_asset_unique_mint_utxo_ref),
    env.stake_distribution_spending_script,
  )
}

pub fn stake_distribution_tx_for_genesis_certificate_with_parent_certificate() -> Transaction {
  let parent_certificate: MithrilCertificate = simple_sd_certificate()
  generate_stake_distribution_tx(
    simple_genesis_certificate(),
    Some(parent_certificate),
    Some(env.stake_distribution_asset_unique_mint_utxo_ref),
    env.stake_distribution_spending_script,
  )
}

pub fn stake_distribution_tx_for_genesis_certificate_with_different_utxo_ref() -> Transaction {
  let invalid_utxo_ref: OutputReference =
    OutputReference { transaction_id: "some_tx_id", output_index: 0 }
  generate_stake_distribution_tx(
    simple_genesis_certificate(),
    None,
    Some(invalid_utxo_ref),
    env.stake_distribution_spending_script,
  )
}

pub fn simple_stake_distribution_tx() -> Transaction {
  generate_stake_distribution_tx(
    simple_sd_certificate(),
    Some(parent_of_simple_sd_certificate()),
    None,
    env.stake_distribution_spending_script,
  )
}

pub fn stake_distribution_transaction_without_parent_certificate_hash() -> Transaction {
  generate_stake_distribution_tx(simple_sd_certificate(), None, None, env.stake_distribution_spending_script)
}

pub fn stake_distribution_tx_new_certificate_with_different_spending_script() -> Transaction {
  generate_stake_distribution_tx(
    simple_sd_certificate(),
    Some(parent_of_simple_sd_certificate()),
    None,
    Script("some_different_spending_script"),
  )
}

pub fn stake_distribution_tx_for_certificate_with_incorrect_parent_certificate_hash() -> Transaction {
  generate_stake_distribution_tx(
    standard_sd_certificate_with_incorrect_parent_hash(),
    Some(parent_of_standard_sd_certificate_with_incorrect_parent_hash()),
    None,
    env.stake_distribution_spending_script,
  )
}

pub fn stake_distribution_tx_for_certificate_with_incorrect_epoch_chaining() -> Transaction {
  generate_stake_distribution_tx(
    standard_sd_certificate_with_incorrect_epoch_chaining(),
    Some(parent_of_simple_sd_certificate()),
    None,
    env.stake_distribution_spending_script,
  )
}

pub fn stake_distribution_tx_for_sd_certificate_with_incorrect_aggregate_verification_key() -> Transaction {
  generate_stake_distribution_tx(
    standard_sd_certificate_with_incorrect_aggregate_verification_key(),
    Some(parent_of_simple_sd_certificate()),
    None,
    env.stake_distribution_spending_script,
  )
}

/// `ProtocolParameters` that do not match to the `NextProtocolParameters` of its parent certificate
pub fn stake_distribution_tx_for_sd_certificate_with_incorrect_protocol_parameters() -> Transaction {
  generate_stake_distribution_tx(
    standard_sd_certificate_with_incorrect_protocol_parameters(),
    Some(parent_of_simple_sd_certificate()),
    None,
    env.stake_distribution_spending_script,
  )
}

/// `SignedEntityType` different from `MithrilStakeDistribution`
pub fn stake_distribution_tx_for_sd_certificate_with_incorrect_signed_entity_type() -> Transaction {
  generate_stake_distribution_tx(
    standard_sd_certificate_with_incorrect_signed_entity_type(),
    Some(parent_of_simple_sd_certificate()),
    None,
    env.stake_distribution_spending_script,
  )
}
