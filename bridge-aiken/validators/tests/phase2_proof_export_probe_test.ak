use aiken/crypto/bls12_381/scalar.{from_bytes_little_endian}
use aiken/interval
use cardano/assets.{add, from_asset, from_lovelace}
use phase2
use tests/helpers/phase_1_2_test_helpers.{
  phase2_test_transaction, proof_receipt_output, script_input,
  test_output_reference, test_phase2_policy_id, test_signer,
}
use tests/helpers/proof_receipt
use two_phase/phase2_proof_export_fixture as exported_fixture
use two_phase/proof_verifier_phase1.{phase1_verifier}
use two_phase/proof_verifier_phase2.{
  phase2_final_pairing_check_bytes, phase2_right_accumulator_bytes,
  phase2_verifier,
}
use two_phase/two_phase_types.{Phase2State, ProofReceiptDatum, Verify}

test phase1_verifier_matches_proof_export_state() {
  let (state, _redeemer) = phase1_verifier(
    exported_fixture.exported_real_proof,
    from_bytes_little_endian(exported_fixture.exported_public_input_1),
    from_bytes_little_endian(exported_fixture.exported_public_input_2),
  )

  state == exported_fixture.exported_state
}

test phase1_verifier_matches_proof_export_redeemer() {
  let (_state, reduced_redeemer) = phase1_verifier(
    exported_fixture.exported_real_proof,
    from_bytes_little_endian(exported_fixture.exported_public_input_1),
    from_bytes_little_endian(exported_fixture.exported_public_input_2),
  )

  reduced_redeemer == exported_fixture.exported_reduced_redeemer
}

test phase2_verifier_accepts_phase1_output_for_proof_export() {
  let (state, reduced_redeemer) = phase1_verifier(
    exported_fixture.exported_real_proof,
    from_bytes_little_endian(exported_fixture.exported_public_input_1),
    from_bytes_little_endian(exported_fixture.exported_public_input_2),
  )

  phase2_verifier(state, reduced_redeemer)
}

test phase2_right_accumulator_matches_exported_rust_probe() {
  let (state, reduced_redeemer) = phase1_verifier(
    exported_fixture.exported_real_proof,
    from_bytes_little_endian(exported_fixture.exported_public_input_1),
    from_bytes_little_endian(exported_fixture.exported_public_input_2),
  )

  phase2_right_accumulator_bytes(state, reduced_redeemer) == exported_fixture.exported_expected_right_accumulator
}

test phase2_final_pairing_accepts_proof_export() {
  let (state, reduced_redeemer) = phase1_verifier(
    exported_fixture.exported_real_proof,
    from_bytes_little_endian(exported_fixture.exported_public_input_1),
    from_bytes_little_endian(exported_fixture.exported_public_input_2),
  )

  let right_accumulator = phase2_right_accumulator_bytes(
    state,
    reduced_redeemer,
  )
  let right_matches = right_accumulator == exported_fixture.exported_expected_right_accumulator
  let pairing_ok = phase2_final_pairing_check_bytes(
    reduced_redeemer.pi_term,
    right_accumulator,
  )

  trace @"right_matches_exported": right_matches
  trace @"pairing_ok": pairing_ok

  right_matches && pairing_ok
}

test phase2_verifier_equals_direct_final_pairing_check_for_proof_export() {
  let (state, reduced_redeemer) = phase1_verifier(
    exported_fixture.exported_real_proof,
    from_bytes_little_endian(exported_fixture.exported_public_input_1),
    from_bytes_little_endian(exported_fixture.exported_public_input_2),
  )

  let right_accumulator = phase2_right_accumulator_bytes(
    state,
    reduced_redeemer,
  )

  phase2_verifier(state, reduced_redeemer) == phase2_final_pairing_check_bytes(
    reduced_redeemer.pi_term,
    right_accumulator,
  )
}

test phase2_runtime_probe_accepts_proof_export_fixture() {
  let state = exported_fixture.exported_state
  let token_name = state.reduced_hash
  let mint_value = from_asset(test_phase2_policy_id, token_name, 1)
  let receipt_value = from_lovelace(3_000_000)
    |> add(test_phase2_policy_id, token_name, 1)
  let phase2_state = Phase2State {
    proof_state: state,
    phase1_signer: test_signer,
    reclaim_after: 1_700_000_000_000,
    statement_hash: exported_fixture.exported_public_input_2,
  }

  let tx = phase2_test_transaction(
    [script_input(test_phase2_policy_id, 0)],
    [
      proof_receipt_output(
        receipt_value,
        ProofReceiptDatum {
          statement_hash: exported_fixture.exported_public_input_2,
        },
      ),
    ],
    mint_value,
    interval.everything,
    [test_signer],
  )

  phase2.phase2.spend(
    proof_receipt.proof_receipt_spending_script,
    Some(phase2_state),
    Verify(exported_fixture.exported_reduced_redeemer),
    test_output_reference(0),
    tx,
  )
}
