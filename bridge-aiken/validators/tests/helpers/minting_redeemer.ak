use ak_381/groth16.{Proof}
use bridge/common_types.{LockingTxSourceOutputReference}
use cardano/address.{PaymentCredential}
use cardano/transaction.{Transaction}
use minting.{MintingValidatorRedeemer}
use mithril/reduced_mithril_certificate.{
  ReducedMithrilCertificate, reduced_mithril_certificate_from_certificate,
}
use tests/helpers/bridge_fixture
use tests/helpers/bridge_locking_tx
use tests/helpers/certificates/cardano_transactions.{
  parent_of_simple_cardano_transactions_certificate,
  simple_cardano_transactions_certificate,
}
use tests/helpers/locking_tx.{simple_locking_tx}
use tests/helpers/test_constants

type LockingTxRedeemerFields {
  input_output_reference: LockingTxSourceOutputReference,
  output_address: ByteArray,
  output_lovelace: Int,
  destination_payment_credential: ByteArray,
  asset_amount: Int,
  fee: Int,
  hash: ByteArray,
}

// The canonical locking-transaction body fields come from the regenerated
// `bridge_fixture` (single source of truth, derived from the off-chain pallas
// builder), so the redeemer's `locking_tx_hash` matches both the on-chain
// reconstruction and the membership proof. The `_locking_tx` argument is kept
// for call-site compatibility but no longer drives the body fields.
pub fn generate_minting_validator_redeemer(
  _locking_tx: Transaction,
  merkle_proof: Proof,
  fixed_tx_hash: Option<ByteArray>,
  destination_address: PaymentCredential,
) -> MintingValidatorRedeemer {
  let locking_tx_fields =
    LockingTxRedeemerFields {
      input_output_reference: bridge_fixture.actual_locking_tx_input_output_reference,
      output_address: bridge_fixture.actual_locking_tx_output_address,
      output_lovelace: bridge_fixture.actual_locking_tx_output_lovelace,
      destination_payment_credential: bridge_locking_tx.payment_credential_bytes(
        destination_address,
      ),
      asset_amount: bridge_fixture.actual_locking_tx_asset_amount,
      fee: bridge_fixture.actual_locking_tx_fee,
      // Legacy compatibility field name: this now carries the canonical
      // Cardano tx hash expected by the refreshed circuit fixture.
      hash: bridge_fixture.final_locking_tx_hash,
    }

  let certificate =
    reduced_mithril_certificate_from_certificate(
      simple_cardano_transactions_certificate(),
    )
  let parent_certificate =
    reduced_mithril_certificate_from_certificate(
      parent_of_simple_cardano_transactions_certificate(),
    )

  minting_redeemer_from_certificates(
    certificate,
    parent_certificate,
    merkle_proof,
    fixed_tx_hash,
    locking_tx_fields,
  )
}

fn minting_redeemer_from_certificates(
  certificate: ReducedMithrilCertificate,
  parent_certificate: ReducedMithrilCertificate,
  merkle_proof: Proof,
  fixed_tx_hash: Option<ByteArray>,
  locking_fields: LockingTxRedeemerFields,
) -> MintingValidatorRedeemer {
  MintingValidatorRedeemer {
    tx_snapshot_certificate_hash: certificate.hash,
    tx_snapshot_certificate_prev_hash: certificate.prev_hash,
    tx_snapshot_certificate_epoch: certificate.epoch,
    tx_snapshot_certificate_protocol_parameters_k: certificate.protocol_parameters.k,
    tx_snapshot_certificate_protocol_parameters_m: certificate.protocol_parameters.m,
    tx_snapshot_certificate_protocol_parameters_phi_f: certificate.protocol_parameters.phi_f,
    tx_snapshot_certificate_protocol_message_next_aggregate_verification_key: certificate.protocol_message_next_aggregate_verification_key,
    tx_snapshot_certificate_protocol_message_next_aggregate_verification_key_snark: certificate.protocol_message_next_aggregate_verification_key_snark,
    tx_snapshot_certificate_protocol_message_next_protocol_parameters: certificate.protocol_message_next_protocol_parameters,
    tx_snapshot_certificate_protocol_message_current_epoch: certificate.protocol_message_current_epoch,
    tx_snapshot_certificate_protocol_message_cardano_transactions_merkle_root: bridge_fixture.final_snapshot_root,
    tx_snapshot_certificate_signed_message: certificate.signed_message,
    tx_snapshot_certificate_aggregate_verification_key: certificate.aggregate_verification_key,
    tx_snapshot_certificate_aggregate_verification_key_snark: certificate.aggregate_verification_key_snark,
    tx_snapshot_certificate_signed_entity_is_stake_distribution: certificate.signed_entity_is_stake_distribution,
    tx_snapshot_certificate_signed_entity_epoch: certificate.signed_entity_epoch,
    parent_certificate_hash: parent_certificate.hash,
    parent_certificate_epoch: parent_certificate.epoch,
    parent_certificate_protocol_parameters_k: parent_certificate.protocol_parameters.k,
    parent_certificate_protocol_parameters_m: parent_certificate.protocol_parameters.m,
    parent_certificate_protocol_parameters_phi_f: parent_certificate.protocol_parameters.phi_f,
    parent_certificate_next_aggregate_verification_key_snark: parent_certificate.protocol_message_next_aggregate_verification_key_snark,
    parent_certificate_aggregate_verification_key_snark: parent_certificate.aggregate_verification_key_snark,
    locking_tx_merkle_proof_public_sub_root: bridge_fixture.final_sub_root,
    locking_tx_merkle_proof_pi_a: merkle_proof.piA,
    locking_tx_merkle_proof_pi_b: merkle_proof.piB,
    locking_tx_merkle_proof_pi_c: merkle_proof.piC,
    // Legacy compatibility field name: this now carries canonical Cardano tx hash bytes.
    locking_tx_hash: when fixed_tx_hash is {
      Some(h) -> h
      None -> locking_fields.hash
    },
    locking_tx_input_output_reference_tx_id: locking_fields.input_output_reference.transaction_id,
    locking_tx_input_output_reference_output_index: locking_fields.input_output_reference.output_index,
    locking_tx_output_address: locking_fields.output_address,
    locking_tx_output_lovelace: locking_fields.output_lovelace,
    locking_tx_destination_payment_credential: locking_fields.destination_payment_credential,
    locking_tx_asset_amount: locking_fields.asset_amount,
    locking_tx_fee: locking_fields.fee,
  }
}

pub fn simple_minting_validator_redeemer() -> MintingValidatorRedeemer {
  generate_minting_validator_redeemer(
    simple_locking_tx(),
    a_valid_minting_proof(),
    None,
    test_constants.destination_chain_address,
  )
}

pub fn valid_snapshot_membership_minting_redeemer() -> MintingValidatorRedeemer {
  generate_minting_validator_redeemer(
    simple_locking_tx(),
    a_valid_minting_proof(),
    Some(bridge_fixture.final_locking_tx_hash),
    test_constants.destination_chain_address,
  )
}

pub fn minting_validator_redeemer_with_incorrect_locking_tx_hash() -> MintingValidatorRedeemer {
  generate_minting_validator_redeemer(
    simple_locking_tx(),
    a_valid_minting_proof(),
    Some("incorrect_locking_tx_hash"),
    test_constants.destination_chain_address,
  )
}

/// Keeps the proved `locking_tx_hash` but tampers with a body field
/// (`output_lovelace`), so the on-chain canonical reconstruction hashes to a
/// different value and the body-hash binding must reject it.
pub fn minting_validator_redeemer_with_tampered_locking_body() -> MintingValidatorRedeemer {
  MintingValidatorRedeemer {
    ..valid_snapshot_membership_minting_redeemer(),
    locking_tx_output_lovelace: 9_999_999,
  }
}

pub fn minting_validator_redeemer_with_invalid_merkle_proof() -> MintingValidatorRedeemer {
  generate_minting_validator_redeemer(
    simple_locking_tx(),
    an_invalid_minting_proof(),
    Some(bridge_fixture.final_locking_tx_hash),
    test_constants.destination_chain_address,
  )
}

pub fn minting_validator_redeemer_with_invalid_snapshot_root() -> MintingValidatorRedeemer {
  MintingValidatorRedeemer {
    ..valid_snapshot_membership_minting_redeemer(),
    tx_snapshot_certificate_protocol_message_cardano_transactions_merkle_root: #"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
  }
}

pub fn minting_validator_redeemer_with_invalid_sub_root() -> MintingValidatorRedeemer {
  MintingValidatorRedeemer {
    ..valid_snapshot_membership_minting_redeemer(),
    locking_tx_merkle_proof_public_sub_root: #"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
  }
}

pub fn minting_validator_redeemer_with_incorrect_parent_certificate() -> MintingValidatorRedeemer {
  MintingValidatorRedeemer {
    ..valid_snapshot_membership_minting_redeemer(),
    parent_certificate_hash: #"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
  }
}

pub fn a_valid_minting_proof() {
  bridge_fixture.final_snapshot_membership_proof()
}

fn an_invalid_minting_proof() {
  Proof {
    piA: #"ffffffcae764bf193d6fa64c7e05f2fec6f46f9f417dd1957665bc818675375888a6e15f6f0a09d67bb99f4067fd6324",
    piB: #"ffffffbefbda701ca81af6e2f57e12ed95ee20303d1c94896fd915fb2b1a422e2f9564587ddf6147a9aa682676d415441615d330dcd7f8a20acc67267934956ea5215665e52899044af2dadc9c59dd08d2e613b8a2a47a44dfe450d7d008a9c0",
    piC: #"ffffff91cf118b98c133be1126e92300b25eb77a9e29e0fcd2daec75c50fd324f2e8d19e36ef5d36c6fa7735b0a5bb9f",
  }
}
