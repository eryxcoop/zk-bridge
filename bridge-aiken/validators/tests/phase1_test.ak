use cardano/assets.{add, from_lovelace}
use phase1.{has_expected_phase2_output, phase1_signer_from}
use tests/helpers/phase_1_2_test_helpers.{
  dummy_phase1_state, other_signer, phase1_test_transaction,
  script_output_with_datum, test_phase1_policy_id, test_phase2_policy_id,
  test_signer, test_statement_hash, verification_key_output,
}
use two_phase/two_phase_types.{Phase2State}

test phase1_setup_accepts_single_matching_phase2_output() {
  let expected_state = Phase2State {
    proof_state: dummy_phase1_state(),
    phase1_signer: test_signer,
    reclaim_after: 100,
    statement_hash: test_statement_hash,
  }
  let mint_value = from_lovelace(0)
    |> add(test_phase1_policy_id, expected_state.proof_state.reduced_hash, 1)

  and {
    phase1_signer_from(
      phase1_test_transaction([], [test_signer], from_lovelace(0)),
    ) == Some(test_signer),
    has_expected_phase2_output(
      phase1_test_transaction(
        [
          script_output_with_datum(
            test_phase2_policy_id,
            mint_value,
            expected_state,
          ),
        ],
        [],
        mint_value,
      ),
      test_phase1_policy_id,
      test_phase2_policy_id,
      expected_state,
    ),
  }
}

test phase1_setup_rejects_missing_unique_signer() {
  phase1_signer_from(phase1_test_transaction([], [], from_lovelace(0))) == None
}

test phase1_setup_rejects_multiple_signers() {
  phase1_signer_from(
    phase1_test_transaction([], [test_signer, other_signer], from_lovelace(0)),
  ) == None
}

test phase1_setup_rejects_missing_phase2_output() {
  let expected_state = Phase2State {
    proof_state: dummy_phase1_state(),
    phase1_signer: test_signer,
    reclaim_after: 100,
    statement_hash: test_statement_hash,
  }
  let mint_value = from_lovelace(0)
    |> add(test_phase1_policy_id, expected_state.proof_state.reduced_hash, 1)

  !has_expected_phase2_output(
    phase1_test_transaction([verification_key_output()], [], mint_value),
    test_phase1_policy_id,
    test_phase2_policy_id,
    expected_state,
  )
}

test phase1_setup_rejects_wrong_phase2_datum() {
  let expected_state = Phase2State {
    proof_state: dummy_phase1_state(),
    phase1_signer: test_signer,
    reclaim_after: 100,
    statement_hash: test_statement_hash,
  }
  let wrong_state = Phase2State {
    proof_state: dummy_phase1_state(),
    phase1_signer: other_signer,
    reclaim_after: 100,
    statement_hash: test_statement_hash,
  }
  let mint_value = from_lovelace(0)
    |> add(test_phase1_policy_id, expected_state.proof_state.reduced_hash, 1)
  let output_value = from_lovelace(2_000_000)
    |> add(test_phase1_policy_id, expected_state.proof_state.reduced_hash, 1)

  !has_expected_phase2_output(
    phase1_test_transaction(
      [
        script_output_with_datum(
          test_phase2_policy_id,
          output_value,
          wrong_state,
        ),
      ],
      [],
      mint_value,
    ),
    test_phase1_policy_id,
    test_phase2_policy_id,
    expected_state,
  )
}

test phase1_setup_rejects_multiple_phase2_outputs() {
  let expected_state = Phase2State {
    proof_state: dummy_phase1_state(),
    phase1_signer: test_signer,
    reclaim_after: 100,
    statement_hash: test_statement_hash,
  }
  let mint_value = from_lovelace(0)
    |> add(test_phase1_policy_id, expected_state.proof_state.reduced_hash, 1)
  let output_value = from_lovelace(2_000_000)
    |> add(test_phase1_policy_id, expected_state.proof_state.reduced_hash, 1)

  !has_expected_phase2_output(
    phase1_test_transaction(
      [
        script_output_with_datum(
          test_phase2_policy_id,
          output_value,
          expected_state,
        ),
        script_output_with_datum(
          test_phase2_policy_id,
          output_value,
          expected_state,
        ),
      ],
      [],
      mint_value,
    ),
    test_phase1_policy_id,
    test_phase2_policy_id,
    expected_state,
  )
}

test phase1_setup_rejects_phase2_output_without_the_minted_nft() {
  let expected_state = Phase2State {
    proof_state: dummy_phase1_state(),
    phase1_signer: test_signer,
    reclaim_after: 100,
    statement_hash: test_statement_hash,
  }

  !has_expected_phase2_output(
    phase1_test_transaction(
      [
        script_output_with_datum(
          test_phase2_policy_id,
          from_lovelace(2_000_000),
          expected_state,
        ),
      ],
      [],
      from_lovelace(0),
    ),
    test_phase1_policy_id,
    test_phase2_policy_id,
    expected_state,
  )
}
