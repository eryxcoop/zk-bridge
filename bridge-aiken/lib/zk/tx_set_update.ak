use aiken/collection/list
use aiken/primitive/bytearray
use ak_381/groth16.{Proof}
use bridge/common_types.{MerkleRoot, TxsUpdaterValidatorRedeemer}
use zk/public_input_packing
use zk/tx_set_update_vk.{tx_set_update_vk}
use zk/verification.{Single, ZKInputType, zk_verify}

pub fn raw_digest_to_zk_public_inputs(bytes: ByteArray) -> List<ZKInputType> {
  public_input_packing.raw_digest_to_zk_public_inputs(bytes)
}

pub fn public_inputs(
  tx_id: ByteArray,
  mt_root_in: MerkleRoot,
  mt_root_out: MerkleRoot,
) -> List<ZKInputType> {
  // In the shared Mithril flow, `tx_id` is the canonical Cardano transaction hash.
  list.concat(
    raw_digest_to_zk_public_inputs(tx_id),
    [
      Single(bytearray.to_int_big_endian(mt_root_in)),
      Single(bytearray.to_int_big_endian(mt_root_out)),
    ],
  )
}

pub fn proof_from_redeemer(redeemer: TxsUpdaterValidatorRedeemer) -> Proof {
  Proof {
    piA: redeemer.tx_set_update_proof_pi_a,
    piB: redeemer.tx_set_update_proof_pi_b,
    piC: redeemer.tx_set_update_proof_pi_c,
  }
}

pub fn proof_verifies(
  redeemer: TxsUpdaterValidatorRedeemer,
  mt_root_in: MerkleRoot,
  mt_root_out: MerkleRoot,
) -> Bool {
  zk_verify(
    proof_from_redeemer(redeemer),
    public_inputs(redeemer.tx_id, mt_root_in, mt_root_out),
    tx_set_update_vk(),
  )
}
