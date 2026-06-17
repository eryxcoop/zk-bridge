use aiken/collection/list
use ak_381/groth16.{Proof}
use zk/public_input_packing
use zk/snapshot_membership_vk.{snapshot_membership_vk}
use zk/verification.{ZKInputType, zk_verify}

pub fn raw_digest_to_zk_public_inputs(bytes: ByteArray) -> List<ZKInputType> {
  public_input_packing.raw_digest_to_zk_public_inputs(bytes)
}

pub fn public_inputs(
  locking_tx_hash: ByteArray,
  sub_root: ByteArray,
  snapshot_root: ByteArray,
) -> List<ZKInputType> {
  // Legacy compatibility name: `locking_tx_hash` now carries the canonical
  // Cardano transaction hash proved by Mithril.
  list.concat(
    raw_digest_to_zk_public_inputs(locking_tx_hash),
    list.concat(
      raw_digest_to_zk_public_inputs(sub_root),
      raw_digest_to_zk_public_inputs(snapshot_root),
    ),
  )
}

pub fn proof_verifies(
  proof: Proof,
  locking_tx_hash: ByteArray,
  sub_root: ByteArray,
  snapshot_root: ByteArray,
) -> Bool {
  // Legacy compatibility name: `locking_tx_hash` is the canonical Cardano tx hash.
  zk_verify(
    proof,
    public_inputs(locking_tx_hash, sub_root, snapshot_root),
    snapshot_membership_vk(),
  )
}
