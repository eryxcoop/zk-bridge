use cardano/address.{Address, Credential, Script}
use cardano/assets.{add, from_lovelace}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use env
use mithril/certificate_signature.{
  GenesisDualSignature, GenesisSignature, MultiSignature,
}
use mithril/mithril_certificate.{MithrilCertificate}
use stake_distribution.{
  StakeDistributionAssetDatum, certificate_state_from_certificate,
}
use tests/helpers/certificates/stake_distribution_certificates.{
  parent_of_simple_sd_certificate, preview_dual_genesis_certificate,
  proof_export_compatible_sd_certificate, simple_genesis_certificate,
  simple_sd_certificate,
}
use tests/helpers/certificates/stake_distribution_negative_certificates.{
  parent_of_standard_sd_certificate_with_incorrect_parent_hash,
  standard_sd_certificate_with_incorrect_aggregate_verification_key,
  standard_sd_certificate_with_incorrect_epoch_chaining,
  standard_sd_certificate_with_incorrect_parent_hash,
  standard_sd_certificate_with_incorrect_protocol_parameters,
  standard_sd_certificate_with_incorrect_signed_entity_type,
}
use tests/helpers/proof_receipt
use tests/helpers/values.{build_value_with_native_token}
use two_phase/two_phase_types.{ProofReceiptDatum}

pub fn sd_certificate_to_stake_output(
  certificate: MithrilCertificate,
  certificate_utxo_spending_script: Credential,
) {
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
    datum: InlineDatum(
      StakeDistributionAssetDatum {
        certificate: certificate_state_from_certificate(certificate),
      },
    ),
    reference_script: None,
  }
}

fn phase2_proof_receipt_input(statement_hash: ByteArray) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: #"cccccc",
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

fn generate_stake_distribution_tx_for_genesis_certificate(
  genesis_certificate: MithrilCertificate,
  certificate_utxo_spending_script: Credential,
) -> Transaction {
  Transaction {
    ..transaction.placeholder,
    mint: build_value_with_native_token(
      env.stake_distribution_asset_policy_id,
      env.stake_distribution_asset_name,
      1,
    ),
    outputs: [
      sd_certificate_to_stake_output(
        genesis_certificate,
        certificate_utxo_spending_script,
      ),
    ],
  }
}

fn generate_stake_distribution_tx_for_standard_certificate(
  certificate: MithrilCertificate,
  parent_certificate: MithrilCertificate,
  certificate_utxo_spending_script: Credential,
  proof_receipt_statement_hash: Option<ByteArray>,
) -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: when proof_receipt_statement_hash is {
      Some(statement_hash) ->
        [
          phase2_proof_receipt_input(statement_hash),
          Input {
            output_reference: OutputReference {
              transaction_id: #"bbbbbb",
              output_index: 0,
            },
            output: sd_certificate_to_stake_output(
              parent_certificate,
              env.stake_distribution_spending_script,
            ),
          },
        ]
      None ->
        [
          Input {
            output_reference: OutputReference {
              transaction_id: #"bbbbbb",
              output_index: 0,
            },
            output: sd_certificate_to_stake_output(
              parent_certificate,
              env.stake_distribution_spending_script,
            ),
          },
        ]
    },
    outputs: [
      sd_certificate_to_stake_output(
        certificate,
        certificate_utxo_spending_script,
      ),
    ],
  }
}

fn generate_stake_distribution_tx(
  certificate: MithrilCertificate,
  parent_certificate: Option<MithrilCertificate>,
  certificate_utxo_spending_script: Credential,
  proof_receipt_statement_hash: Option<ByteArray>,
) -> Transaction {
  when certificate.signature is {
    GenesisSignature { .. } -> {
      expect None = parent_certificate
      generate_stake_distribution_tx_for_genesis_certificate(
        certificate,
        certificate_utxo_spending_script,
      )
    }
    GenesisDualSignature { .. } -> {
      expect None = parent_certificate
      generate_stake_distribution_tx_for_genesis_certificate(
        certificate,
        certificate_utxo_spending_script,
      )
    }
    MultiSignature { .. } -> {
      expect Some(parent_certificate) = parent_certificate
      generate_stake_distribution_tx_for_standard_certificate(
        certificate,
        parent_certificate,
        certificate_utxo_spending_script,
        proof_receipt_statement_hash,
      )
    }
  }
}

pub fn simple_stake_distribution_tx_for_genesis_certificate() -> Transaction {
  generate_stake_distribution_tx(
    simple_genesis_certificate(),
    None,
    env.stake_distribution_spending_script,
    None,
  )
}

pub fn preview_stake_distribution_tx_for_dual_genesis_certificate() -> Transaction {
  generate_stake_distribution_tx(
    preview_dual_genesis_certificate(),
    None,
    env.stake_distribution_spending_script,
    None,
  )
}

pub fn stake_distribution_tx_for_genesis_certificate_with_parent_certificate() -> Transaction {
  let parent_certificate: MithrilCertificate = simple_sd_certificate()
  generate_stake_distribution_tx(
    simple_genesis_certificate(),
    Some(parent_certificate),
    env.stake_distribution_spending_script,
    None,
  )
}

pub fn stake_distribution_tx_for_genesis_certificate_without_phase2_receipt() -> Transaction {
  generate_stake_distribution_tx_for_genesis_certificate(
    simple_genesis_certificate(),
    env.stake_distribution_spending_script,
  )
}

pub fn stake_distribution_tx_for_genesis_certificate_with_phase2_receipt_as_reference_input() -> Transaction {
  Transaction {
    ..generate_stake_distribution_tx_for_genesis_certificate(
      simple_genesis_certificate(),
      env.stake_distribution_spending_script,
    ),
    inputs: [],
    reference_inputs: [
      phase2_proof_receipt_input(simple_genesis_certificate().signed_message),
    ],
  }
}

pub fn simple_stake_distribution_tx() -> Transaction {
  generate_stake_distribution_tx(
    simple_sd_certificate(),
    Some(parent_of_simple_sd_certificate()),
    env.stake_distribution_spending_script,
    Some(simple_sd_certificate().signed_message),
  )
}

pub fn proof_export_compatible_stake_distribution_tx() -> Transaction {
  generate_stake_distribution_tx(
    proof_export_compatible_sd_certificate(),
    Some(parent_of_simple_sd_certificate()),
    env.stake_distribution_spending_script,
    Some(proof_export_compatible_sd_certificate().signed_message),
  )
}

pub fn stake_distribution_transaction_without_parent_certificate_hash() -> Transaction {
  generate_stake_distribution_tx(
    simple_sd_certificate(),
    None,
    env.stake_distribution_spending_script,
    Some(simple_sd_certificate().signed_message),
  )
}

pub fn stake_distribution_tx_new_certificate_with_different_spending_script() -> Transaction {
  generate_stake_distribution_tx(
    simple_sd_certificate(),
    Some(parent_of_simple_sd_certificate()),
    Script("some_different_spending_script"),
    Some(simple_sd_certificate().signed_message),
  )
}

pub fn stake_distribution_tx_without_phase2_receipt() -> Transaction {
  Transaction {
    ..generate_stake_distribution_tx(
      simple_sd_certificate(),
      Some(parent_of_simple_sd_certificate()),
      env.stake_distribution_spending_script,
      Some(simple_sd_certificate().signed_message),
    ),
    inputs: [
      Input {
        output_reference: OutputReference {
          transaction_id: #"bbbbbb",
          output_index: 0,
        },
        output: sd_certificate_to_stake_output(
          parent_of_simple_sd_certificate(),
          env.stake_distribution_spending_script,
        ),
      },
    ],
  }
}

pub fn stake_distribution_tx_with_phase2_receipt_as_reference_input() -> Transaction {
  Transaction {
    ..generate_stake_distribution_tx(
      simple_sd_certificate(),
      Some(parent_of_simple_sd_certificate()),
      env.stake_distribution_spending_script,
      None,
    ),
    reference_inputs: [
      phase2_proof_receipt_input(simple_sd_certificate().signed_message),
    ],
  }
}

pub fn stake_distribution_tx_with_incorrect_phase2_statement_hash() -> Transaction {
  generate_stake_distribution_tx(
    simple_sd_certificate(),
    Some(parent_of_simple_sd_certificate()),
    env.stake_distribution_spending_script,
    Some(#"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
  )
}

pub fn stake_distribution_tx_for_certificate_with_incorrect_parent_certificate_hash() -> Transaction {
  generate_stake_distribution_tx(
    standard_sd_certificate_with_incorrect_parent_hash(),
    Some(parent_of_standard_sd_certificate_with_incorrect_parent_hash()),
    env.stake_distribution_spending_script,
    Some(standard_sd_certificate_with_incorrect_parent_hash().signed_message),
  )
}

pub fn stake_distribution_tx_for_certificate_with_incorrect_epoch_chaining() -> Transaction {
  generate_stake_distribution_tx(
    standard_sd_certificate_with_incorrect_epoch_chaining(),
    Some(parent_of_simple_sd_certificate()),
    env.stake_distribution_spending_script,
    Some(standard_sd_certificate_with_incorrect_epoch_chaining().signed_message),
  )
}

pub fn stake_distribution_tx_for_sd_certificate_with_incorrect_aggregate_verification_key() -> Transaction {
  generate_stake_distribution_tx(
    standard_sd_certificate_with_incorrect_aggregate_verification_key(),
    Some(parent_of_simple_sd_certificate()),
    env.stake_distribution_spending_script,
    Some(
      standard_sd_certificate_with_incorrect_aggregate_verification_key().signed_message,
    ),
  )
}

/// `ProtocolParameters` that do not match to the `NextProtocolParameters` of its parent certificate
pub fn stake_distribution_tx_for_sd_certificate_with_incorrect_protocol_parameters() -> Transaction {
  generate_stake_distribution_tx(
    standard_sd_certificate_with_incorrect_protocol_parameters(),
    Some(parent_of_simple_sd_certificate()),
    env.stake_distribution_spending_script,
    Some(
      standard_sd_certificate_with_incorrect_protocol_parameters().signed_message,
    ),
  )
}

/// `SignedEntityType` different from `MithrilStakeDistribution`
pub fn stake_distribution_tx_for_sd_certificate_with_incorrect_signed_entity_type() -> Transaction {
  generate_stake_distribution_tx(
    standard_sd_certificate_with_incorrect_signed_entity_type(),
    Some(parent_of_simple_sd_certificate()),
    env.stake_distribution_spending_script,
    Some(
      standard_sd_certificate_with_incorrect_signed_entity_type().signed_message,
    ),
  )
}
