use aiken/collection/list
use mithril/reduced_mithril_certificate.{
  reduced_mithril_certificate_from_certificate,
}
use tests/helpers/bridge_fixture
use tests/helpers/certificates/cardano_transactions.{
  simple_cardano_transactions_certificate,
}
use tests/helpers/minting_redeemer.{
  simple_minting_validator_redeemer, valid_snapshot_membership_minting_redeemer,
}
use zk/public_input_packing
use zk/snapshot_membership
use zk/snapshot_membership_vk.{snapshot_membership_vk}

test reduced_certificate_keeps_cardano_transactions_merkle_root() {
  let reduced = reduced_mithril_certificate_from_certificate(
    simple_cardano_transactions_certificate(),
  )

  reduced.protocol_message_cardano_transactions_merkle_root == bridge_fixture.final_snapshot_root
}

test minting_redeemer_threads_cardano_transactions_merkle_root() {
  let reduced = reduced_mithril_certificate_from_certificate(
    simple_cardano_transactions_certificate(),
  )
  let redeemer = simple_minting_validator_redeemer()

  redeemer.tx_snapshot_certificate_protocol_message_cardano_transactions_merkle_root == reduced.protocol_message_cardano_transactions_merkle_root
}

test minting_redeemer_threads_snapshot_sub_root() {
  simple_minting_validator_redeemer().locking_tx_merkle_proof_public_sub_root == bridge_fixture.final_sub_root
}

test raw_digest_to_zk_public_inputs_packs_locking_hash_into_two_fields() {
  snapshot_membership.raw_digest_to_zk_public_inputs(
    bridge_fixture.final_locking_tx_hash,
  ) == list.take(bridge_fixture.final_snapshot_membership_public_inputs(), 2)
}

test shared_public_input_packing_matches_snapshot_membership_wrapper() {
  public_input_packing.raw_digest_to_zk_public_inputs(
    bridge_fixture.final_locking_tx_hash,
  ) == snapshot_membership.raw_digest_to_zk_public_inputs(
    bridge_fixture.final_locking_tx_hash,
  )
}

test raw_digest_to_zk_public_inputs_packs_snapshot_root_into_two_fields() {
  snapshot_membership.raw_digest_to_zk_public_inputs(
    bridge_fixture.final_snapshot_root,
  ) == list.drop(bridge_fixture.final_snapshot_membership_public_inputs(), 4)
}

test snapshot_membership_vk_expects_six_packed_public_inputs() {
  snapshot_membership_vk().nPublic == 6
}

test minting_redeemer_threads_final_fixture_proof() {
  let redeemer = simple_minting_validator_redeemer()
  let proof = bridge_fixture.final_snapshot_membership_proof()

  and {
    redeemer.locking_tx_merkle_proof_pi_a == proof.piA,
    redeemer.locking_tx_merkle_proof_pi_b == proof.piB,
    redeemer.locking_tx_merkle_proof_pi_c == proof.piC,
  }
}

test snapshot_membership_public_inputs_match_circuit_order() {
  let reduced = reduced_mithril_certificate_from_certificate(
    simple_cardano_transactions_certificate(),
  )
  let redeemer = valid_snapshot_membership_minting_redeemer()

  snapshot_membership.public_inputs(
    redeemer.locking_tx_hash,
    redeemer.locking_tx_merkle_proof_public_sub_root,
    reduced.protocol_message_cardano_transactions_merkle_root,
  ) == bridge_fixture.final_snapshot_membership_public_inputs()
}
