use aiken/interval
use cardano/assets.{add, from_asset, from_lovelace}
use phase2.{
  can_recover_phase2, has_expected_proof_receipt_output,
  is_authorized_phase2_mint,
}
use tests/helpers/phase_1_2_test_helpers.{
  dummy_phase2_state, other_policy_id, other_signer, phase2_test_transaction,
  proof_receipt_output, script_input, test_phase2_policy_id, test_signer,
  test_statement_hash, test_token_name, verification_key_input,
  verification_key_output,
}
use tests/helpers/proof_receipt
use two_phase/two_phase_types.{ProofReceiptDatum}

test phase2_recover_constraints_accept_after_deadline_for_phase1_signer() {
  let state = dummy_phase2_state(
    test_token_name,
    test_signer,
    100,
    test_statement_hash,
  )

  can_recover_phase2(
    state,
    phase2_test_transaction(
      [script_input(test_phase2_policy_id, 0)],
      [],
      from_lovelace(0),
      interval.after(100),
      [test_signer],
    ),
  )
}

test phase2_recover_constraints_reject_before_deadline() {
  let state = dummy_phase2_state(
    test_token_name,
    test_signer,
    100,
    test_statement_hash,
  )

  !can_recover_phase2(
    state,
    phase2_test_transaction(
      [script_input(test_phase2_policy_id, 0)],
      [],
      from_lovelace(0),
      interval.between(10, 90),
      [test_signer],
    ),
  )
}

test phase2_recover_constraints_helper_does_not_check_signature() {
  let state = dummy_phase2_state(
    test_token_name,
    test_signer,
    100,
    test_statement_hash,
  )

  can_recover_phase2(
    state,
    phase2_test_transaction(
      [script_input(test_phase2_policy_id, 0)],
      [],
      from_lovelace(0),
      interval.after(100),
      [other_signer],
    ),
  )
}

test phase2_recover_constraints_reject_if_any_token_is_minted() {
  let state = dummy_phase2_state(
    test_token_name,
    test_signer,
    100,
    test_statement_hash,
  )

  !can_recover_phase2(
    state,
    phase2_test_transaction(
      [script_input(test_phase2_policy_id, 0)],
      [],
      from_asset(test_phase2_policy_id, test_token_name, 1),
      interval.after(100),
      [test_signer],
    ),
  )
}

test phase2_mint_accepts_when_own_script_input_is_spent() {
  is_authorized_phase2_mint(
    test_token_name,
    test_phase2_policy_id,
    phase2_test_transaction(
      [script_input(test_phase2_policy_id, 0), verification_key_input(1)],
      [],
      from_asset(test_phase2_policy_id, test_token_name, 1),
      interval.between(10, 90),
      [],
    ),
  )
}

test phase2_mint_rejects_without_own_script_input() {
  !is_authorized_phase2_mint(
    test_token_name,
    test_phase2_policy_id,
    phase2_test_transaction(
      [verification_key_input(0), script_input(other_policy_id, 1)],
      [],
      from_asset(test_phase2_policy_id, test_token_name, 1),
      interval.between(10, 90),
      [],
    ),
  )
}

test phase2_mint_rejects_non_strict_mint_value() {
  !is_authorized_phase2_mint(
    test_token_name,
    test_phase2_policy_id,
    phase2_test_transaction(
      [script_input(test_phase2_policy_id, 0)],
      [],
      from_asset(test_phase2_policy_id, test_token_name, 1)
        |> add(other_policy_id, #"babe", 1),
      interval.between(10, 90),
      [],
    ),
  )
}

test phase2_receipt_output_accepts_unique_matching_receipt() {
  let state = dummy_phase2_state(
    test_token_name,
    test_signer,
    100,
    test_statement_hash,
  )

  has_expected_proof_receipt_output(
    phase2_test_transaction(
      [],
      [
        proof_receipt_output(
          from_lovelace(2_000_000)
            |> add(test_phase2_policy_id, test_token_name, 1),
          ProofReceiptDatum { statement_hash: test_statement_hash },
        ),
      ],
      from_lovelace(0),
      interval.everything,
      [],
    ),
    test_phase2_policy_id,
    state,
    proof_receipt.proof_receipt_spending_script,
  )
}

test phase2_receipt_output_rejects_missing_receipt() {
  let state = dummy_phase2_state(
    test_token_name,
    test_signer,
    100,
    test_statement_hash,
  )

  !has_expected_proof_receipt_output(
    phase2_test_transaction(
      [],
      [verification_key_output()],
      from_lovelace(0),
      interval.everything,
      [],
    ),
    test_phase2_policy_id,
    state,
    proof_receipt.proof_receipt_spending_script,
  )
}

test phase2_receipt_output_rejects_wrong_statement_hash() {
  let state = dummy_phase2_state(
    test_token_name,
    test_signer,
    100,
    test_statement_hash,
  )

  !has_expected_proof_receipt_output(
    phase2_test_transaction(
      [],
      [
        proof_receipt_output(
          from_lovelace(2_000_000)
            |> add(test_phase2_policy_id, test_token_name, 1),
          ProofReceiptDatum {
            statement_hash: #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          },
        ),
      ],
      from_lovelace(0),
      interval.everything,
      [],
    ),
    test_phase2_policy_id,
    state,
    proof_receipt.proof_receipt_spending_script,
  )
}

test phase2_receipt_output_rejects_multiple_receipts() {
  let state = dummy_phase2_state(
    test_token_name,
    test_signer,
    100,
    test_statement_hash,
  )
  let receipt_value = from_lovelace(2_000_000)
    |> add(test_phase2_policy_id, test_token_name, 1)
  let receipt_datum = ProofReceiptDatum { statement_hash: test_statement_hash }

  !has_expected_proof_receipt_output(
    phase2_test_transaction(
      [],
      [
        proof_receipt_output(receipt_value, receipt_datum),
        proof_receipt_output(receipt_value, receipt_datum),
      ],
      from_lovelace(0),
      interval.everything,
      [],
    ),
    test_phase2_policy_id,
    state,
    proof_receipt.proof_receipt_spending_script,
  )
}

test phase2_receipt_output_rejects_receipt_without_nft() {
  let state = dummy_phase2_state(
    test_token_name,
    test_signer,
    100,
    test_statement_hash,
  )

  !has_expected_proof_receipt_output(
    phase2_test_transaction(
      [],
      [
        proof_receipt_output(
          from_lovelace(2_000_000),
          ProofReceiptDatum { statement_hash: test_statement_hash },
        ),
      ],
      from_lovelace(0),
      interval.everything,
      [],
    ),
    test_phase2_policy_id,
    state,
    proof_receipt.proof_receipt_spending_script,
  )
}
