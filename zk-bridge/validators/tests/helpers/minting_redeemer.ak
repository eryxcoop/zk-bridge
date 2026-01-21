use aiken/cbor.{serialise}
use aiken/crypto.{Hash, Sha3_256, sha3_256}
use ak_381/groth16.{Proof}
use cardano/address.{Address, PaymentCredential}
use cardano/assets.{lovelace_of}
use cardano/transaction.{Datum, Input, Output, OutputReference, Transaction}
use minting.{MintingValidatorRedeemer}
use tests/helpers/certificates.{simple_cardano_transactions_certificate}
use tests/helpers/locking_tx.{simple_locking_tx}
use tests/helpers/test_constants

pub fn generate_minting_validator_redeemer(
  locking_tx: Transaction,
  mithril_proof: Proof,
  merkle_proof: Proof,
  fixed_tx_hash: Option<ByteArray>,
  destination_address: PaymentCredential,
) -> MintingValidatorRedeemer {
  expect [locking_tx_input] = locking_tx.inputs
  expect [locking_tx_output] = locking_tx.outputs
  let locking_tx_input_output_reference: OutputReference =
    locking_tx_input.output_reference
  let locking_tx_input_payment_credential: PaymentCredential =
    locking_tx_input.output.address.payment_credential
  let locking_tx_input_datum: Datum = locking_tx_input.output.datum

  let locking_tx_ada_amount = lovelace_of(locking_tx_output.value)

  let locking_tx_hash: Hash<Sha3_256, Transaction> =
    sha3_256(serialise(locking_tx))

  MintingValidatorRedeemer {
    tx_snapshot_certificate: simple_cardano_transactions_certificate(),
    locking_tx_mithril_proof: mithril_proof,
    locking_tx_merkle_proof: merkle_proof,
    locking_tx_hash: when fixed_tx_hash is {
      Some(h) -> h
      None -> locking_tx_hash
    },
    locking_tx_input_output_reference,
    locking_tx_input_payment_credential,
    locking_tx_input_datum,
    locking_tx_destination_address: destination_address,
    locking_tx_ada_amount,
  }
}

pub fn simple_minting_validator_redeemer() -> MintingValidatorRedeemer {
  generate_minting_validator_redeemer(
    simple_locking_tx(),
    a_valid_mithril_certificate_proof(),
    a_valid_minting_proof(),
    None,
    test_constants.destination_chain_address,
  )
}

pub fn minting_validator_redeemer_with_incorrect_locking_tx_hash() -> MintingValidatorRedeemer {
  generate_minting_validator_redeemer(
    simple_locking_tx(),
    a_valid_mithril_certificate_proof(),
    a_valid_minting_proof(),
    Some("incorrect_locking_tx_hash"),
    test_constants.destination_chain_address,
  )
}

pub fn minting_validator_redeemer_with_invalid_merkle_proof() -> MintingValidatorRedeemer {
  generate_minting_validator_redeemer(
    simple_locking_tx(),
    a_valid_mithril_certificate_proof(),
    an_invalid_minting_proof(),
    None,
    test_constants.destination_chain_address,
  )
}

pub fn minting_validator_redeemer_with_invalid_mithril_proof() -> MintingValidatorRedeemer {
  generate_minting_validator_redeemer(
    simple_locking_tx(),
    an_invalid_mithril_certificate_proof(),
    a_valid_minting_proof(),
    None,
    test_constants.destination_chain_address,
  )
}

fn a_valid_minting_proof() {
  Proof {
    piA: #"844828e5a38592cdcd0b486af0306dff05c9d06d7477d75b4a4f05c4bccf67025d185b8083eb1333dd3123d76d3bbb1b",
    piB: #"90829737d8859dfefb24c2819537e2e492dd59eb4891b6ff0ab5538aaf7dc41cdc11876f616de31795c5310fcc06f4ea11640ab99bcafac2321cc2858dc4266dec3c8ccbc1490af9d5dca7c1cfbb9fcb6cb427ccc5a5d282ab3af0b0987c8e2c",
    piC: #"8dc6b20de8728bd12b9bb4f743de29afe974acd9f27d00071ded36e69564d8a5f3ebcf1ddb3df3989bbf055e58b235c9",
  }
}

fn an_invalid_minting_proof() {
  Proof {
    piA: #"ffffffcae764bf193d6fa64c7e05f2fec6f46f9f417dd1957665bc818675375888a6e15f6f0a09d67bb99f4067fd6324",
    piB: #"ffffffbefbda701ca81af6e2f57e12ed95ee20303d1c94896fd915fb2b1a422e2f9564587ddf6147a9aa682676d415441615d330dcd7f8a20acc67267934956ea5215665e52899044af2dadc9c59dd08d2e613b8a2a47a44dfe450d7d008a9c0",
    piC: #"ffffff91cf118b98c133be1126e92300b25eb77a9e29e0fcd2daec75c50fd324f2e8d19e36ef5d36c6fa7735b0a5bb9f",
  }
}

fn a_valid_mithril_certificate_proof() {
  Proof {
    piA: #"8f24f2c09798df276236295608a009b7c86a63ce28220ccbf9fb3e00871a70be057ff583c74d24a47a02654ad1802de5",
    piB: #"b11880dfe2b2d5dd9aae12be311192eee74a3b79a9053d89cbf7ac0e8cbdfb7a58840636579da3b9bcbe68039996d50e04713884f8835f4a8ea5b7ffa67682beecd6a4807058527971034a5c7199f765d9bb8a22e140fcedb525baffb1b95102",
    piC: #"8920fbc8919dbaeb00878cb3447eb1e441760a081a50eb0f60545744153744d1e403351704f2bedee4f78fc4f28eb8e0",
  }
}

fn an_invalid_mithril_certificate_proof() {
  Proof {
    piA: #"fffffff09798df276236295608a009b7c86a63ce28220ccbf9fb3e00871a70be057ff583c74d24a47a02654ad1802de5",
    piB: #"ffffffffe2b2d5dd9aae12be311192eee74a3b79a9053d89cbf7ac0e8cbdfb7a58840636579da3b9bcbe68039996d50e04713884f8835f4a8ea5b7ffa67682beecd6a4807058527971034a5c7199f765d9bb8a22e140fcedb525baffb1b95102",
    piC: #"fffffff8919dbaeb00878cb3447eb1e441760a081a50eb0f60545744153744d1e403351704f2bedee4f78fc4f28eb8e0",
  }
}
