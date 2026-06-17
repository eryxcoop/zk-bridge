use ak_381/groth16.{Proof}
use env
use minting.{MintingValidatorRedeemer}
use tests/helpers/actual_bridge_redeemers.{
  actual_bridge_mint_redeemer, actual_bridge_spend_redeemer,
}
use tests/helpers/bridge_fixture
use tests/helpers/test_constants
use utils.{digest_to_bytes_of_string}
use zk/snapshot_membership
use zk/snapshot_membership_vk.{snapshot_membership_vk}
use zk/tx_set_update
use zk/verification.{zk_verify}

fn proof_from_actual_redeemer(redeemer: MintingValidatorRedeemer) -> Proof {
  Proof {
    piA: redeemer.locking_tx_merkle_proof_pi_a,
    piB: redeemer.locking_tx_merkle_proof_pi_b,
    piC: redeemer.locking_tx_merkle_proof_pi_c,
  }
}

fn public_inputs_from_actual_redeemer(redeemer: MintingValidatorRedeemer) {
  snapshot_membership.public_inputs(
    redeemer.locking_tx_hash,
    redeemer.locking_tx_merkle_proof_public_sub_root,
    redeemer.tx_snapshot_certificate_protocol_message_cardano_transactions_merkle_root,
  )
}

test actual_bridge_mint_and_txs_updater_redeemers_share_locking_hash() {
  let mint_redeemer = actual_bridge_mint_redeemer()
  let spend_redeemer = actual_bridge_spend_redeemer()

  spend_redeemer.tx_id == mint_redeemer.locking_tx_hash
}

test actual_bridge_locking_hash_matches_exported_fixture() {
  actual_bridge_mint_redeemer().locking_tx_hash == bridge_fixture.final_locking_tx_hash
}

test actual_bridge_locking_hash_threads_fixture_value_as_canonical_tx_hash() {
  let redeemer = actual_bridge_mint_redeemer()

  redeemer.locking_tx_hash == bridge_fixture.final_locking_tx_hash
}

test actual_bridge_parent_hash_is_threaded_as_raw_digest() {
  let redeemer = actual_bridge_mint_redeemer()

  redeemer.tx_snapshot_certificate_prev_hash == digest_to_bytes_of_string(
    redeemer.parent_certificate_hash,
  )
}

test actual_bridge_snapshot_membership_proof_verifies_directly() {
  let redeemer = actual_bridge_mint_redeemer()

  zk_verify(
    proof_from_actual_redeemer(redeemer),
    public_inputs_from_actual_redeemer(redeemer),
    snapshot_membership_vk(),
  )
}

test actual_bridge_public_inputs_match_exported_fixture() {
  public_inputs_from_actual_redeemer(actual_bridge_mint_redeemer()) == bridge_fixture.final_snapshot_membership_public_inputs()
}

test actual_bridge_tx_set_update_proof_verifies_directly() {
  tx_set_update.proof_verifies(
    actual_bridge_spend_redeemer(),
    test_constants.tx_set_update_fixture_root_in,
    test_constants.tx_set_update_fixture_root_out,
  )
}
