use aiken/crypto.{VerificationKeyHash}
use aiken/interval
use cardano/address.{from_script, from_verification_key}
use cardano/assets.{PolicyId, Value, from_lovelace}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, placeholder,
}
use two_phase/two_phase_types.{
  Phase1State, Phase2State, ProofReceiptDatum, StatementHash, phase2_state,
}

pub const test_phase1_policy_id: PolicyId =
  #"99999999999999999999999999999999999999999999999999999999"

pub const test_phase2_policy_id: PolicyId =
  #"00112233445566778899aabbccddeeff00112233445566778899aabb"

pub const other_policy_id: PolicyId =
  #"ffeeddccbbaa99887766554433221100ffeeddccbbaa998877665544"

pub const test_signer: VerificationKeyHash =
  #"1234567890abcdef1234567890abcdef1234567890abcdef12345678"

pub const other_signer: VerificationKeyHash =
  #"abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefab"

pub const test_statement_hash: StatementHash =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

pub const test_token_name: ByteArray = #"cafe"

pub const test_proof_receipt_script_hash: PolicyId =
  #"00000000000000000000000000000000000000000000000000000000"

/// Test fixture representing a minimal proof-derived state.
pub fn dummy_phase1_state() -> Phase1State {
  Phase1State {
    rhs_prefix: #"01",
    reduced_hash: #"02",
    x1: #"03",
    x3: #"04",
    x4: #"05",
    v: #"06",
  }
}

/// Test fixture representing a minimal proof-derived state parameterised by reduced_hash.
pub fn dummy_proof_state(reduced_hash: ByteArray) -> Phase1State {
  Phase1State {
    rhs_prefix: #"01",
    reduced_hash,
    x1: #"02",
    x3: #"03",
    x4: #"04",
    v: #"05",
  }
}

/// Test helper that wraps a proof state with recovery metadata.
pub fn dummy_phase2_state(
  reduced_hash: ByteArray,
  phase1_signer: VerificationKeyHash,
  reclaim_after: Int,
  statement_hash: ByteArray,
) -> Phase2State {
  phase2_state(
    dummy_proof_state(reduced_hash),
    phase1_signer,
    reclaim_after,
    statement_hash,
  )
}

/// Test helper for constructing stable output references.
pub fn test_output_reference(output_index: Int) -> OutputReference {
  OutputReference {
    transaction_id: #"1111111111111111111111111111111111111111111111111111111111111111",
    output_index,
  }
}

/// Test helper that creates a phase-2 script output with an inline datum.
pub fn script_output_with_datum(
  phase2_policy_id: PolicyId,
  value: Value,
  datum: Phase2State,
) -> Output {
  Output {
    address: from_script(phase2_policy_id),
    value,
    datum: InlineDatum(datum),
    reference_script: None,
  }
}

/// Test helper that creates a script input owned by the given policy.
pub fn script_input(policy_id: PolicyId, output_index: Int) -> Input {
  Input {
    output_reference: test_output_reference(output_index),
    output: Output {
      address: from_script(policy_id),
      value: from_lovelace(2_000_000),
      datum: NoDatum,
      reference_script: None,
    },
  }
}

/// Test helper that creates a non-script input for negative cases.
pub fn verification_key_input(output_index: Int) -> Input {
  Input {
    output_reference: test_output_reference(output_index),
    output: Output {
      address: from_verification_key(other_signer),
      value: from_lovelace(2_000_000),
      datum: NoDatum,
      reference_script: None,
    },
  }
}

/// Test helper that creates the proof receipt output expected after phase 2.
pub fn proof_receipt_output(value: Value, datum: ProofReceiptDatum) -> Output {
  Output {
    address: from_script(test_proof_receipt_script_hash),
    value,
    datum: InlineDatum(datum),
    reference_script: None,
  }
}

/// Test helper that creates a plain verification-key output.
pub fn verification_key_output() -> Output {
  Output {
    address: from_verification_key(other_signer),
    value: from_lovelace(2_000_000),
    datum: NoDatum,
    reference_script: None,
  }
}

/// Test helper that builds a minimal transaction skeleton for phase-1 checks.
pub fn phase1_test_transaction(
  outputs: List<Output>,
  extra_signatories: List<VerificationKeyHash>,
  mint: Value,
) -> Transaction {
  Transaction { ..placeholder, outputs, extra_signatories, mint }
}

/// Test helper that builds a minimal transaction skeleton for phase-2 checks.
pub fn phase2_test_transaction(
  inputs: List<Input>,
  outputs: List<Output>,
  mint_value: Value,
  validity_range: interval.Interval,
  extra_signatories: List<VerificationKeyHash>,
) -> Transaction {
  Transaction {
    ..placeholder,
    inputs,
    outputs,
    mint: mint_value,
    validity_range,
    extra_signatories,
  }
}
