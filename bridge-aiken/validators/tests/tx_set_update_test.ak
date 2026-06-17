use tests/helpers/bridge_fixture
use zk/tx_set_update
use zk/tx_set_update_vk.{tx_set_update_vk}

test tx_set_update_vk_expects_four_packed_public_inputs() {
  tx_set_update_vk().nPublic == 4
}

test tx_set_update_public_inputs_match_exported_fixture() {
  tx_set_update.public_inputs(
    bridge_fixture.final_locking_tx_hash,
    bridge_fixture.final_tx_set_update_root_in,
    bridge_fixture.final_tx_set_update_root_out,
  ) == bridge_fixture.final_tx_set_update_public_inputs()
}
