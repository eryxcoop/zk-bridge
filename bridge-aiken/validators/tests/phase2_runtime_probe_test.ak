use aiken/interval
use cardano/address
use cardano/assets.{add, from_asset, from_lovelace}
use cardano/transaction.{NoDatum, Output}
use phase2
use tests/helpers/phase_1_2_test_helpers.{
  other_signer, phase2_test_transaction, proof_receipt_output, script_input,
  test_output_reference, test_phase2_policy_id, verification_key_input,
}
use tests/helpers/proof_receipt
use two_phase/phase2_fixture
use two_phase/two_phase_types.{ProofReceiptDatum, Verify}

test phase2_validator_accepts_real_fixture_with_minimal_tx_context() {
  let state = phase2_fixture.valid_phase2_state()
  let token_name = state.proof_state.reduced_hash
  let mint_value = from_asset(test_phase2_policy_id, token_name, 1)
  let receipt_value = from_lovelace(phase2_fixture.valid_receipt_lovelace)
    |> add(test_phase2_policy_id, token_name, 1)

  let tx = phase2_test_transaction(
    [script_input(test_phase2_policy_id, 0)],
    [
      proof_receipt_output(
        receipt_value,
        ProofReceiptDatum {
          statement_hash: phase2_fixture.valid_statement_hash,
        },
      ),
    ],
    mint_value,
    interval.everything,
    [state.phase1_signer],
  )

  phase2.phase2.spend(
    proof_receipt.proof_receipt_spending_script,
    Some(state),
    Verify(phase2_fixture.valid_reduced_redeemer),
    test_output_reference(0),
    tx,
  )
}

test phase2_scripts_accept_real_fixture_with_tx2_shape() {
  let state = phase2_fixture.valid_phase2_state()
  let token_name = state.proof_state.reduced_hash
  let mint_value = from_asset(test_phase2_policy_id, token_name, 1)
  let receipt_value = from_lovelace(phase2_fixture.valid_receipt_lovelace)
    |> add(test_phase2_policy_id, token_name, 1)

  let tx = phase2_test_transaction(
    [script_input(test_phase2_policy_id, 0), verification_key_input(1)],
    [
      proof_receipt_output(
        receipt_value,
        ProofReceiptDatum {
          statement_hash: phase2_fixture.valid_statement_hash,
        },
      ),
      Output {
        address: address.from_verification_key(other_signer),
        value: from_lovelace(5_000_000),
        datum: NoDatum,
        reference_script: None,
      },
    ],
    mint_value,
    interval.everything,
    [state.phase1_signer],
  )

  expect _ = phase2.phase2.spend(
    proof_receipt.proof_receipt_spending_script,
    Some(state),
    Verify(phase2_fixture.valid_reduced_redeemer),
    test_output_reference(0),
    tx,
  )

  phase2.phase2.mint(
    proof_receipt.proof_receipt_spending_script,
    token_name,
    test_phase2_policy_id,
    tx,
  )
}
