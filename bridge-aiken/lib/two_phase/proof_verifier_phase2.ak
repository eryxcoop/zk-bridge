// Phase 2 verifier for the two-phase Mithril STM Halo2 Multi-Open verifier.
//
// Consumes the Phase1State datum and ReducedRedeemer to complete the
// remaining G1 linear combination and final pairing check.

use aiken/builtin.{blake2b_256}
use aiken/collection/list.{drop}
use aiken/crypto/bls12_381/g1.{
  add as addG1, compress, decompress, scale as scaleG1,
}
use aiken/crypto/bls12_381/g2.{generator as generatorG2}
use aiken/crypto/bls12_381/pairing.{final_exponentiation, miller_loop}
use aiken/crypto/bls12_381/scalar.{from_bytes_little_endian}
use halo2/halo2_kzg_split.{accumulate_g1, serialize_reduced_redeemer}
use halo2/omega_rotations.{powers}
use halo2/verifier_key.{
  f11_commitment, f12_commitment, f13_commitment, f14_commitment, f15_commitment,
  f16_commitment, f17_commitment, f18_commitment, f19_commitment, f20_commitment,
  f21_commitment, f22_commitment, f2_commitment, f3_commitment, f4_commitment,
  g2_const, neg_g1_generator, p10_commitment, p1_commitment, p2_commitment,
  p3_commitment, p4_commitment, p5_commitment, p6_commitment, p7_commitment,
  p8_commitment, p9_commitment,
}
use two_phase/two_phase_types.{Phase1State, ReducedRedeemer}

fn phase2_right_accumulator_internal(
  state: Phase1State,
  redeemer: ReducedRedeemer,
) -> G1Element {
  // 1. Verify hash binding (fail fast on tampered redeemer)
  expect blake2b_256(serialize_reduced_redeemer(redeemer)) == state.reduced_hash

  // 2. Deserialize scalars from datum
  let x1 = from_bytes_little_endian(state.x1)
  let x3 = from_bytes_little_endian(state.x3)
  let x4 = from_bytes_little_endian(state.x4)
  let v = from_bytes_little_endian(state.v)

  // 3. Decompress rhs_prefix from datum
  let rhs_prefix_g1 = decompress(state.rhs_prefix)

  // 4. Compute x1Powers and x4Powers
  let x1_powers = powers(44, x1)
  let x4_powers = powers(5, x4)
  expect [_x4p0, x4p1, x4p2, x4p3, x4p4] = x4_powers

  // 5a. Set 0 suffix (indices 17-43): VK constants + redeemer points
  //     Split rebalanced from 23 to 17 to equalize TX1/TX2 cost.
  let set_0_suffix = [
    (f2_commitment, []),
    (f3_commitment, []),
    (f4_commitment, []),
    (f11_commitment, []),
    (f12_commitment, []),
    (f13_commitment, []),
    (f14_commitment, []),
    (f15_commitment, []),
    (f16_commitment, []),
    (f17_commitment, []),
    (f18_commitment, []),
    (f19_commitment, []),
    (f20_commitment, []),
    (f21_commitment, []),
    (f22_commitment, []),
    (p1_commitment, []),
    (p2_commitment, []),
    (p3_commitment, []),
    (p4_commitment, []),
    (p5_commitment, []),
    (p6_commitment, []),
    (p7_commitment, []),
    (p8_commitment, []),
    (p9_commitment, []),
    (p10_commitment, []),
    (redeemer.vanishing_g, []),
    (redeemer.vanishing_rand, []),
  ]
  let x1_powers_suffix = drop(x1_powers, 17)
  let set_0_suffix_sum = accumulate_g1(x1_powers_suffix, set_0_suffix)

  // 5b. Set 1 (6 entries), scaled by x4^1
  let set_1_entries = [
    (redeemer.a1, []),
    (redeemer.a2, []),
    (redeemer.a3, []),
    (redeemer.perm_d, []),
    (redeemer.lookup_1, []),
    (redeemer.lookup_2, []),
  ]
  let set_1_sum = scaleG1(accumulate_g1(x1_powers, set_1_entries), x4p1)

  // 5c. Set 2 (3 entries), scaled by x4^2
  let set_2_entries = [
    (redeemer.perm_a, []),
    (redeemer.perm_b, []),
    (redeemer.perm_c, []),
  ]
  let set_2_sum = scaleG1(accumulate_g1(x1_powers, set_2_entries), x4p2)

  // 5d. Set 3 (2 entries), scaled by x4^3
  let set_3_entries = [(redeemer.perm_input_1, []), (redeemer.perm_input_2, [])]
  let set_3_sum = scaleG1(accumulate_g1(x1_powers, set_3_entries), x4p3)

  // 5e. f_commitment term, scaled by x4^4
  let f_term = scaleG1(decompress(redeemer.f_commitment), x4p4)

  // 6. Combine all G1 contributions
  let suffix_total = addG1(
    set_0_suffix_sum,
    addG1(set_1_sum, addG1(set_2_sum, addG1(set_3_sum, f_term))),
  )
  let final_com = addG1(rhs_prefix_g1, suffix_total)

  // 7. Compute correction: v_term + pi_term_scaled
  let v_term = scaleG1(decompress(neg_g1_generator), v)
  let pi_term_g1 = decompress(redeemer.pi_term)
  let pi_term_scaled = scaleG1(pi_term_g1, x3)
  let correction = addG1(v_term, pi_term_scaled)

  // 8. Compute er
  addG1(final_com, correction)
}

pub fn phase2_right_accumulator_bytes(
  state: Phase1State,
  redeemer: ReducedRedeemer,
) -> ByteArray {
  compress(phase2_right_accumulator_internal(state, redeemer))
}

fn phase2_final_pairing_check_internal(el: G1Element, er: G1Element) -> Bool {
  let g2 = generatorG2
  let ml_l = miller_loop(el, g2_const)
  let ml_r = miller_loop(er, g2)
  final_exponentiation(ml_l, ml_r)
}

pub fn phase2_final_pairing_check_bytes(
  pi_term: ByteArray,
  right_accumulator: ByteArray,
) -> Bool {
  let el = decompress(pi_term)
  let er = decompress(right_accumulator)
  phase2_final_pairing_check_internal(el, er)
}

pub fn phase2_verifier(state: Phase1State, redeemer: ReducedRedeemer) -> Bool {
  let er = phase2_right_accumulator_internal(state, redeemer)
  let el = decompress(redeemer.pi_term)
  // 9. Final pairing check
  phase2_final_pairing_check_internal(el, er)
}
