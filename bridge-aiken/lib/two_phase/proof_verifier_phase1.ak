// Phase 1 verifier for the two-phase Mithril STM Halo2 Multi-Open verifier.
//
// Parses the full proof, derives Fiat-Shamir challenges, evaluates circuit
// expressions, computes vanishing, builds commitment_data, computes the
// prefix of the G1 linear block (first 17 entries of set 0), and
// pre-computes v.  Returns the Phase1State datum for TX2 consumption.

use aiken/builtin.{blake2b_256}
use aiken/collection/list.{foldl, last, take, zip}
use aiken/crypto/bitwise.{State}
use aiken/crypto/bls12_381/g1.{
  add as addG1, compress, decompress, scale as scaleG1,
}
use aiken/crypto/bls12_381/scalar.{
  Scalar, add, from_int, mul, neg, scale, sub, to_bytes_little_endian,
}
use halo2/bls_utils.{inner_product, recip_eea}
use halo2/halo2_kzg.{
  compute_q_eval_for_entries, compute_q_eval_for_set, compute_v,
}
use halo2/halo2_kzg_split.{
  accumulate_g1_prefix, serialize_reduced_redeemer,
  serialize_reduced_redeemer_fields,
}
use halo2/lagrange.{lagrange_evaluation, lagrange_polynomial_basis}
use halo2/omega_rotations.{powers, rotate_omega, rotate_omegas}
use halo2/transcript.{
  common_point, common_scalar, construct_transcript, read_point, read_scalar,
  squeeze_challenge,
}
use halo2/verifier_key.{
  barycentric_weight, blinding_factors, f10_commitment, f11_commitment,
  f12_commitment, f13_commitment, f14_commitment, f15_commitment, f16_commitment,
  f17_commitment, f18_commitment, f19_commitment, f1_commitment, f20_commitment,
  f21_commitment, f22_commitment, f2_commitment, f3_commitment, f4_commitment,
  f5_commitment, f6_commitment, f7_commitment, f8_commitment, f9_commitment,
  omega, omega_inv, p10_commitment, p1_commitment, p2_commitment, p3_commitment,
  p4_commitment, p5_commitment, p6_commitment, p7_commitment, p8_commitment,
  p9_commitment, transcript_rep,
}
use two_phase/two_phase_types.{Phase1State, ReducedRedeemer}

fn inverse_vanishing_product(
  points: List<State<Scalar>>,
  eval_point: State<Scalar>,
) -> State<Scalar> {
  recip_eea(
    foldl(
      points,
      from_int(1),
      fn(point, acc) { mul(acc, sub(eval_point, point)) },
    ),
  )
}

fn q_eval_term(
  points: List<State<Scalar>>,
  evals: List<State<Scalar>>,
  q_eval_on_point: State<Scalar>,
  eval_point: State<Scalar>,
) -> State<Scalar> {
  let r_eval = lagrange_evaluation(zip(points, evals), eval_point)
  let denominator = inverse_vanishing_product(points, eval_point)
  mul(sub(q_eval_on_point, r_eval), denominator)
}

fn scaled_quintic(coeff: State<Scalar>, value: State<Scalar>) -> State<Scalar> {
  let value_sq = mul(value, value)
  mul(coeff, mul(value, mul(value_sq, value_sq)))
}

type VanishingLagrangeTerms {
  last_evaluation: State<Scalar>,
  evaluation_at_0: State<Scalar>,
  sum_of_evaluation_for_blinding_factors: State<Scalar>,
}

// TX1 only needs three aggregates from the fixed 8-point vanishing window.
// Computing them directly avoids building the rotations, denominator, inverse,
// and basis lists on the hot path.
fn phase1_vanishing_lagrange_terms(
  x: State<Scalar>,
  xn: State<Scalar>,
) -> VanishingLagrangeTerms {
  let scalarOne = from_int(1)
  let common = mul(sub(xn, scalarOne), barycentric_weight)

  let omega_inv_1 = omega_inv
  let omega_inv_2 = mul(omega_inv_1, omega_inv)
  let omega_inv_3 = mul(omega_inv_2, omega_inv)
  let omega_inv_4 = mul(omega_inv_3, omega_inv)
  let omega_inv_5 = mul(omega_inv_4, omega_inv)
  let omega_inv_6 = mul(omega_inv_5, omega_inv)
  let omega_inv_7 = mul(omega_inv_6, omega_inv)

  let denominator_0 = sub(x, omega_inv_7)
  let denominator_1 = sub(x, omega_inv_6)
  let denominator_2 = sub(x, omega_inv_5)
  let denominator_3 = sub(x, omega_inv_4)
  let denominator_4 = sub(x, omega_inv_3)
  let denominator_5 = sub(x, omega_inv_2)
  let denominator_6 = sub(x, omega_inv_1)
  let denominator_7 = sub(x, scalarOne)

  let prefix_0 = denominator_0
  let prefix_1 = mul(prefix_0, denominator_1)
  let prefix_2 = mul(prefix_1, denominator_2)
  let prefix_3 = mul(prefix_2, denominator_3)
  let prefix_4 = mul(prefix_3, denominator_4)
  let prefix_5 = mul(prefix_4, denominator_5)
  let prefix_6 = mul(prefix_5, denominator_6)
  let prefix_7 = mul(prefix_6, denominator_7)

  let product_inverse = recip_eea(prefix_7)

  let inverse_7 = mul(prefix_6, product_inverse)
  let inverse_prefix_6 = mul(denominator_7, product_inverse)
  let inverse_6 = mul(prefix_5, inverse_prefix_6)
  let inverse_prefix_5 = mul(denominator_6, inverse_prefix_6)
  let inverse_5 = mul(prefix_4, inverse_prefix_5)
  let inverse_prefix_4 = mul(denominator_5, inverse_prefix_5)
  let inverse_4 = mul(prefix_3, inverse_prefix_4)
  let inverse_prefix_3 = mul(denominator_4, inverse_prefix_4)
  let inverse_3 = mul(prefix_2, inverse_prefix_3)
  let inverse_prefix_2 = mul(denominator_3, inverse_prefix_3)
  let inverse_2 = mul(prefix_1, inverse_prefix_2)
  let inverse_prefix_1 = mul(denominator_2, inverse_prefix_2)
  let inverse_1 = mul(prefix_0, inverse_prefix_1)
  let inverse_0 = mul(denominator_1, inverse_prefix_1)

  let last_evaluation = mul(mul(common, inverse_0), omega_inv_7)
  let evaluation_1 = mul(mul(common, inverse_1), omega_inv_6)
  let evaluation_2 = mul(mul(common, inverse_2), omega_inv_5)
  let evaluation_3 = mul(mul(common, inverse_3), omega_inv_4)
  let evaluation_4 = mul(mul(common, inverse_4), omega_inv_3)
  let evaluation_5 = mul(mul(common, inverse_5), omega_inv_2)
  let evaluation_6 = mul(mul(common, inverse_6), omega_inv_1)
  let evaluation_at_0 = mul(common, inverse_7)
  let sum_of_evaluation_for_blinding_factors =
    add(
      add(add(evaluation_1, evaluation_2), add(evaluation_3, evaluation_4)),
      add(evaluation_5, evaluation_6),
    )

  VanishingLagrangeTerms {
    last_evaluation,
    evaluation_at_0,
    sum_of_evaluation_for_blinding_factors,
  }
}

// The instance polynomial is only consumed against [i_1, i_2], so the third
// basis term from rotate_omegas(0, 2) is always dropped by inner_product(zip).
fn phase1_instance_eval_2(
  x: State<Scalar>,
  xn: State<Scalar>,
  i_1: State<Scalar>,
  i_2: State<Scalar>,
) -> State<Scalar> {
  let scalarOne = from_int(1)
  let common = mul(sub(xn, scalarOne), barycentric_weight)
  let denominator_0 = sub(x, scalarOne)
  let denominator_1 = sub(x, omega)
  let product_inverse = recip_eea(mul(denominator_0, denominator_1))
  let inverse_0 = mul(denominator_1, product_inverse)
  let inverse_1 = mul(denominator_0, product_inverse)
  let basis_0 = mul(common, inverse_0)
  let basis_1 = mul(mul(common, inverse_1), omega)

  add(mul(basis_0, i_1), mul(basis_1, i_2))
}

pub fn phase1_verifier(
  proof: Data,
  i_1: State<Scalar>,
  i_2: State<Scalar>,
) -> (Phase1State, ReducedRedeemer) {
  let scalarZero = from_int(0)
  let scalarOne = from_int(1)
  let scalarDelta =
    from_int(0x8634d0aa021aaf843cab354fabb0062f6502437c6a09c006c083479590189d7)

  let transcript = construct_transcript(proof, transcript_rep)

  let transcript = common_point(f15_commitment, transcript)

  let transcript = common_scalar(from_int(2), transcript)
  let transcript = common_scalar(i_1, transcript)
  let transcript = common_scalar(i_2, transcript)

  let (a1, transcript) = read_point(transcript)
  let (a2, transcript) = read_point(transcript)
  let (a3, transcript) = read_point(transcript)
  let (a4, transcript) = read_point(transcript)
  let (a5, transcript) = read_point(transcript)
  let (a6, transcript) = read_point(transcript)
  let (a7, transcript) = read_point(transcript)
  let (a8, transcript) = read_point(transcript)
  let (a9, transcript) = read_point(transcript)
  let (theta, transcript) = squeeze_challenge(transcript)
  let (permuted_input_1, transcript) = read_point(transcript)
  let (permuted_table_1, transcript) = read_point(transcript)
  let (permuted_input_2, transcript) = read_point(transcript)
  let (permuted_table_2, transcript) = read_point(transcript)
  let (beta, transcript) = squeeze_challenge(transcript)
  let (gamma, transcript) = squeeze_challenge(transcript)
  let (permutations_committed_a, transcript) = read_point(transcript)
  let (permutations_committed_b, transcript) = read_point(transcript)
  let (permutations_committed_c, transcript) = read_point(transcript)
  let (permutations_committed_d, transcript) = read_point(transcript)
  let (lookup_commitment_1, transcript) = read_point(transcript)
  let (lookup_commitment_2, transcript) = read_point(transcript)
  let (trash_challenge, transcript) = squeeze_challenge(transcript)
  let (trash_commitment_1, transcript) = read_point(transcript)
  let (vanishing_rand, transcript) = read_point(transcript)
  let (y, transcript) = squeeze_challenge(transcript)
  let (vanishing_split_1, transcript) = read_point(transcript)
  let vanishing_split_1 = decompress(vanishing_split_1)
  let (vanishing_split_2, transcript) = read_point(transcript)
  let vanishing_split_2 = decompress(vanishing_split_2)
  let (vanishing_split_3, transcript) = read_point(transcript)
  let vanishing_split_3 = decompress(vanishing_split_3)
  let (vanishing_split_4, transcript) = read_point(transcript)
  let vanishing_split_4 = decompress(vanishing_split_4)
  let (x, transcript) = squeeze_challenge(transcript)
  let (instance_eval_1, transcript) = read_scalar(transcript)
  let (advice_eval_1, transcript) = read_scalar(transcript)
  let (advice_eval_2, transcript) = read_scalar(transcript)
  let (advice_eval_3, transcript) = read_scalar(transcript)
  let (advice_eval_4, transcript) = read_scalar(transcript)
  let (advice_eval_5, transcript) = read_scalar(transcript)
  let (advice_eval_6, transcript) = read_scalar(transcript)
  let (advice_eval_7, transcript) = read_scalar(transcript)
  let (advice_eval_8, transcript) = read_scalar(transcript)
  let (advice_eval_9, transcript) = read_scalar(transcript)
  let (advice_eval_10, transcript) = read_scalar(transcript)
  let (advice_eval_11, transcript) = read_scalar(transcript)
  let (advice_eval_12, transcript) = read_scalar(transcript)
  let (fixed_eval_1, transcript) = read_scalar(transcript)
  let (fixed_eval_2, transcript) = read_scalar(transcript)
  let (fixed_eval_3, transcript) = read_scalar(transcript)
  let (fixed_eval_4, transcript) = read_scalar(transcript)
  let (fixed_eval_5, transcript) = read_scalar(transcript)
  let (fixed_eval_6, transcript) = read_scalar(transcript)
  let (fixed_eval_7, transcript) = read_scalar(transcript)
  let (fixed_eval_8, transcript) = read_scalar(transcript)
  let (fixed_eval_9, transcript) = read_scalar(transcript)
  let (fixed_eval_10, transcript) = read_scalar(transcript)
  let (fixed_eval_11, transcript) = read_scalar(transcript)
  let (fixed_eval_12, transcript) = read_scalar(transcript)
  let (fixed_eval_13, transcript) = read_scalar(transcript)
  let (fixed_eval_14, transcript) = read_scalar(transcript)
  let (fixed_eval_15, transcript) = read_scalar(transcript)
  let (fixed_eval_16, transcript) = read_scalar(transcript)
  let (fixed_eval_17, transcript) = read_scalar(transcript)
  let (fixed_eval_18, transcript) = read_scalar(transcript)
  let (fixed_eval_19, transcript) = read_scalar(transcript)
  let (fixed_eval_20, transcript) = read_scalar(transcript)
  let (fixed_eval_21, transcript) = read_scalar(transcript)
  let (fixed_eval_22, transcript) = read_scalar(transcript)
  let (random_eval, transcript) = read_scalar(transcript)
  let (permutation_common_1, transcript) = read_scalar(transcript)
  let (permutation_common_2, transcript) = read_scalar(transcript)
  let (permutation_common_3, transcript) = read_scalar(transcript)
  let (permutation_common_4, transcript) = read_scalar(transcript)
  let (permutation_common_5, transcript) = read_scalar(transcript)
  let (permutation_common_6, transcript) = read_scalar(transcript)
  let (permutation_common_7, transcript) = read_scalar(transcript)
  let (permutation_common_8, transcript) = read_scalar(transcript)
  let (permutation_common_9, transcript) = read_scalar(transcript)
  let (permutation_common_10, transcript) = read_scalar(transcript)
  let (permutations_evaluated_a_1, transcript) = read_scalar(transcript)
  let (permutations_evaluated_a_2, transcript) = read_scalar(transcript)
  let (permutations_evaluated_a_3, transcript) = read_scalar(transcript)
  let (permutations_evaluated_b_1, transcript) = read_scalar(transcript)
  let (permutations_evaluated_b_2, transcript) = read_scalar(transcript)
  let (permutations_evaluated_b_3, transcript) = read_scalar(transcript)
  let (permutations_evaluated_c_1, transcript) = read_scalar(transcript)
  let (permutations_evaluated_c_2, transcript) = read_scalar(transcript)
  let (permutations_evaluated_c_3, transcript) = read_scalar(transcript)
  let (permutations_evaluated_d_1, transcript) = read_scalar(transcript)
  let (permutations_evaluated_d_2, transcript) = read_scalar(transcript)
  let (product_eval_1, transcript) = read_scalar(transcript)
  let (product_next_eval_1, transcript) = read_scalar(transcript)
  let (permuted_input_eval_1, transcript) = read_scalar(transcript)
  let (permuted_input_inv_eval_1, transcript) = read_scalar(transcript)
  let (permuted_table_eval_1, transcript) = read_scalar(transcript)
  let (product_eval_2, transcript) = read_scalar(transcript)
  let (product_next_eval_2, transcript) = read_scalar(transcript)
  let (permuted_input_eval_2, transcript) = read_scalar(transcript)
  let (permuted_input_inv_eval_2, transcript) = read_scalar(transcript)
  let (permuted_table_eval_2, transcript) = read_scalar(transcript)
  let (trash_eval_1, transcript) = read_scalar(transcript)
  let (x1, transcript) = squeeze_challenge(transcript)
  let (x2, transcript) = squeeze_challenge(transcript)
  let (f_commitment, transcript) = read_point(transcript)
  let (x3, transcript) = squeeze_challenge(transcript)
  let (q_eval_on_x3_1, transcript) = read_scalar(transcript)
  let (q_eval_on_x3_2, transcript) = read_scalar(transcript)
  let (q_eval_on_x3_3, transcript) = read_scalar(transcript)
  let (q_eval_on_x3_4, transcript) = read_scalar(transcript)
  let (x4, transcript) = squeeze_challenge(transcript)
  let (pi_term, _) = read_point(transcript)

  let n = 16384
  let xn = scale(x, n)
  let x_chop = scale(x, n - 1)

  let x_prev = rotate_omega(omega, omega_inv, x, -1)
  let x_current = rotate_omega(omega, omega_inv, x, 0)
  let x_next = rotate_omega(omega, omega_inv, x, 1)
  let x_last = rotate_omega(omega, omega_inv, x, -(blinding_factors + 1))

  let vanishing_lagrange_terms = phase1_vanishing_lagrange_terms(x, xn)
  let last_evaluation = vanishing_lagrange_terms.last_evaluation
  let evaluation_at_0 = vanishing_lagrange_terms.evaluation_at_0
  let sum_of_evaluation_for_blinding_factors =
    vanishing_lagrange_terms.sum_of_evaluation_for_blinding_factors
  let active_rows =
    sub(scalarOne, add(last_evaluation, sum_of_evaluation_for_blinding_factors))

  // -----------------------------------------------------------------------------------------------
  let instance_eval_2 = phase1_instance_eval_2(x, xn, i_1, i_2)

  let gate_eq1 =
    mul(
      fixed_eval_14,
      add(
        add(
          add(
            add(
              add(
                add(
                  add(
                    add(fixed_eval_10, mul(fixed_eval_2, advice_eval_1)),
                    mul(fixed_eval_3, advice_eval_2),
                  ),
                  mul(fixed_eval_4, advice_eval_3),
                ),
                mul(fixed_eval_5, advice_eval_4),
              ),
              mul(fixed_eval_6, advice_eval_5),
            ),
            mul(fixed_eval_7, advice_eval_6),
          ),
          mul(mul(fixed_eval_8, advice_eval_1), advice_eval_2),
        ),
        mul(mul(fixed_eval_9, advice_eval_1), advice_eval_3),
      ),
    )
  let gate_eq2 =
    mul(
      fixed_eval_15,
      add(
        add(add(advice_eval_2, advice_eval_3), neg(advice_eval_4)),
        neg(advice_eval_5),
      ),
    )
  let gate_eq3 =
    mul(
      fixed_eval_16,
      add(add(advice_eval_1, fixed_eval_2), neg(advice_eval_6)),
    )
  let gate_eq4 =
    mul(
      fixed_eval_16,
      add(add(advice_eval_2, fixed_eval_3), neg(advice_eval_7)),
    )
  let gate_eq5 =
    mul(
      fixed_eval_16,
      add(add(advice_eval_3, fixed_eval_4), neg(advice_eval_8)),
    )
  let gate_eq6 =
    mul(
      fixed_eval_18,
      add(
        mul(
          advice_eval_6,
          add(
            scalarOne,
            mul(
              mul(
                from_int(
                  0x2a9318e74bfa2b48f5fd9207e6bd7fd4292d7f6d37579d2601065fd6d6343eb1,
                ),
                advice_eval_11,
              ),
              mul(advice_eval_10, advice_eval_10),
            ),
          ),
        ),
        neg(
          add(
            mul(advice_eval_9, advice_eval_10),
            mul(advice_eval_9, advice_eval_10),
          ),
        ),
      ),
    )
  let gate_eq7 =
    mul(
      fixed_eval_18,
      add(
        mul(
          advice_eval_7,
          add(
            scalarOne,
            neg(
              mul(
                mul(
                  from_int(
                    0x2a9318e74bfa2b48f5fd9207e6bd7fd4292d7f6d37579d2601065fd6d6343eb1,
                  ),
                  advice_eval_11,
                ),
                mul(advice_eval_10, advice_eval_10),
              ),
            ),
          ),
        ),
        neg(add(mul(advice_eval_10, advice_eval_10), advice_eval_11)),
      ),
    )
  let gate_eq8 =
    mul(
      fixed_eval_18,
      add(mul(advice_eval_9, advice_eval_9), neg(advice_eval_11)),
    )
  let gate_eq9 =
    mul(
      fixed_eval_19,
      add(
        mul(
          advice_eval_9,
          add(
            scalarOne,
            mul(
              mul(
                advice_eval_5,
                from_int(
                  0x2a9318e74bfa2b48f5fd9207e6bd7fd4292d7f6d37579d2601065fd6d6343eb1,
                ),
              ),
              advice_eval_12,
            ),
          ),
        ),
        neg(
          add(
            advice_eval_1,
            mul(
              advice_eval_5,
              add(
                add(
                  mul(advice_eval_1, advice_eval_4),
                  mul(advice_eval_3, advice_eval_2),
                ),
                neg(advice_eval_1),
              ),
            ),
          ),
        ),
      ),
    )
  let gate_eq10 =
    mul(
      fixed_eval_19,
      add(
        mul(
          advice_eval_10,
          add(
            scalarOne,
            neg(
              mul(
                mul(
                  advice_eval_5,
                  from_int(
                    0x2a9318e74bfa2b48f5fd9207e6bd7fd4292d7f6d37579d2601065fd6d6343eb1,
                  ),
                ),
                advice_eval_12,
              ),
            ),
          ),
        ),
        neg(
          add(
            advice_eval_2,
            mul(
              advice_eval_5,
              add(
                add(
                  mul(advice_eval_2, advice_eval_4),
                  mul(advice_eval_1, advice_eval_3),
                ),
                neg(advice_eval_2),
              ),
            ),
          ),
        ),
      ),
    )
  let gate_eq11 =
    mul(
      fixed_eval_19,
      add(
        advice_eval_12,
        neg(
          mul(
            mul(mul(advice_eval_1, advice_eval_2), advice_eval_3),
            advice_eval_4,
          ),
        ),
      ),
    )
  let gate_eq12 =
    mul(
      fixed_eval_20,
      add(
        add(
          mul(advice_eval_2, advice_eval_2),
          neg(mul(advice_eval_1, advice_eval_1)),
        ),
        neg(
          add(
            scalarOne,
            mul(
              mul(
                from_int(
                  0x2a9318e74bfa2b48f5fd9207e6bd7fd4292d7f6d37579d2601065fd6d6343eb1,
                ),
                mul(advice_eval_1, advice_eval_1),
              ),
              mul(advice_eval_2, advice_eval_2),
            ),
          ),
        ),
      ),
    )
  let gate_eq13 =
    mul(
      fixed_eval_21,
      add(
        mul(advice_eval_1, mul(advice_eval_1, advice_eval_1)),
        neg(advice_eval_4),
      ),
    )
  let gate_eq14 =
    mul(
      fixed_eval_21,
      add(
        mul(advice_eval_2, mul(advice_eval_2, advice_eval_2)),
        neg(advice_eval_5),
      ),
    )
  let gate_eq15 =
    mul(
      fixed_eval_21,
      add(
        mul(advice_eval_3, mul(advice_eval_3, advice_eval_3)),
        neg(advice_eval_9),
      ),
    )
  let gate_eq16 =
    mul(
      fixed_eval_21,
      add(
        add(
          add(
            add(fixed_eval_7, neg(advice_eval_6)),
            mul(
              from_int(
                0x1b8114c381b922fd5d6d241210e2d8a68ad5744053ba9e776118de4107b51ace,
              ),
              mul(mul(advice_eval_1, advice_eval_1), advice_eval_4),
            ),
          ),
          mul(
            from_int(
              0x3df32e4cc4cb2ed20e5d21899cf5331775990ccaec4c09b4e3717213fcc0d763,
            ),
            mul(mul(advice_eval_2, advice_eval_2), advice_eval_5),
          ),
        ),
        mul(
          from_int(
            0x3f05c4df7a6664dabe258779bf548eb4007f33601591080b3ecd34aea0e1edc1,
          ),
          mul(mul(advice_eval_3, advice_eval_3), advice_eval_9),
        ),
      ),
    )
  let gate_eq17 =
    mul(
      fixed_eval_21,
      add(
        add(
          add(
            add(fixed_eval_8, neg(advice_eval_7)),
            mul(
              from_int(
                0x404d21073985d14e432a4ad76d3fae06ca74314b950fe7b1d7f501cd31a8b374,
              ),
              mul(mul(advice_eval_1, advice_eval_1), advice_eval_4),
            ),
          ),
          mul(
            from_int(
              0xb2cc8704264c6bd81bc620e9e524d4b73e9b2317679422ff7fa1603955649f1,
            ),
            mul(mul(advice_eval_2, advice_eval_2), advice_eval_5),
          ),
        ),
        mul(
          from_int(
            0xfdf664da55059fa5a9388c641035d496d0bb519834348b4e2a8fc8c637f1a1f,
          ),
          mul(mul(advice_eval_3, advice_eval_3), advice_eval_9),
        ),
      ),
    )
  let gate_eq18 =
    mul(
      fixed_eval_21,
      add(
        add(
          add(
            add(fixed_eval_9, neg(advice_eval_8)),
            mul(
              from_int(
                0x5e1d3dbecda6214343e24a47f45c5d033197ad01b65a730af95dc57e90c49140,
              ),
              mul(mul(advice_eval_1, advice_eval_1), advice_eval_4),
            ),
          ),
          mul(
            from_int(
              0x6bd72f9cfc53af9d931896e77ea5c61244cb6d5fae8954f37dc7b9002f5aa78a,
            ),
            mul(mul(advice_eval_2, advice_eval_2), advice_eval_5),
          ),
        ),
        mul(
          from_int(
            0x4997c5aa3a5fa07bcaf880a9054bef831effbd9cd58e46d9bb4fb88ef99de0db,
          ),
          mul(mul(advice_eval_3, advice_eval_3), advice_eval_9),
        ),
      ),
    )

  let lookup_table_eq =
    add(mul(add(mul(scalarZero, theta), fixed_eval_12), theta), fixed_eval_13)
  let lookup_input_eq_base =
    mul(add(mul(scalarZero, theta), fixed_eval_11), theta)

  let lookup_input_eq1 =
    add(lookup_input_eq_base, mul(fixed_eval_17, advice_eval_2))
  let lookup_input_eq2 =
    add(lookup_input_eq_base, mul(fixed_eval_17, advice_eval_3))

  let lookup_expression_1_1 =
    mul(evaluation_at_0, sub(scalarOne, product_eval_1))
  let lookup_expression_2_1 =
    mul(
      last_evaluation,
      sub(mul(product_eval_1, product_eval_1), product_eval_1),
    )
  let lookup_left_1 =
    mul(
      mul(product_next_eval_1, add(permuted_input_eval_1, beta)),
      add(permuted_table_eval_1, gamma),
    )
  let lookup_right_1 =
    mul(
      mul(product_eval_1, add(lookup_input_eq1, beta)),
      add(lookup_table_eq, gamma),
    )
  let lookup_expression_3_1 =
    mul(sub(lookup_left_1, lookup_right_1), active_rows)
  let lookup_expression_4_1 =
    mul(evaluation_at_0, sub(permuted_input_eval_1, permuted_table_eval_1))
  let lookup_expression_5_1 =
    mul(
      mul(
        sub(permuted_input_eval_1, permuted_table_eval_1),
        sub(permuted_input_eval_1, permuted_input_inv_eval_1),
      ),
      active_rows,
    )

  let lookup_expression_1_2 =
    mul(evaluation_at_0, sub(scalarOne, product_eval_2))
  let lookup_expression_2_2 =
    mul(
      last_evaluation,
      sub(mul(product_eval_2, product_eval_2), product_eval_2),
    )
  let lookup_left_2 =
    mul(
      mul(product_next_eval_2, add(permuted_input_eval_2, beta)),
      add(permuted_table_eval_2, gamma),
    )
  let lookup_right_2 =
    mul(
      mul(product_eval_2, add(lookup_input_eq2, beta)),
      add(lookup_table_eq, gamma),
    )
  let lookup_expression_3_2 =
    mul(sub(lookup_left_2, lookup_right_2), active_rows)
  let lookup_expression_4_2 =
    mul(evaluation_at_0, sub(permuted_input_eval_2, permuted_table_eval_2))
  let lookup_expression_5_2 =
    mul(
      mul(
        sub(permuted_input_eval_2, permuted_table_eval_2),
        sub(permuted_input_eval_2, permuted_input_inv_eval_2),
      ),
      active_rows,
    )

  let trash_expression_1 =
    add(
      add(
        mul(
          add(
            mul(
              add(
                mul(
                  add(
                    mul(
                      add(
                        mul(
                          add(
                            mul(
                              add(
                                mul(
                                  add(
                                    mul(from_int(0x0), trash_challenge),
                                    add(
                                      add(fixed_eval_7, neg(advice_eval_6)),
                                      add(
                                        add(
                                          add(
                                            add(
                                              add(
                                                add(
                                                  add(
                                                    mul(
                                                      from_int(
                                                        0x590ba402032e82eb1f660ef09796c5686345a5054ed96dae8e2d233633788771,
                                                      ),
                                                      advice_eval_1,
                                                    ),
                                                    mul(
                                                      from_int(
                                                        0x52f789e4afc3801f7411102ee2f47cc5954a744e71cac98e75ea962a55a0a76f,
                                                      ),
                                                      advice_eval_2,
                                                    ),
                                                  ),
                                                  scaled_quintic(
                                                    from_int(
                                                      0x3509dd2fe3aac0080783557fec090fb1cb4b2b0901253c55282024331d1fe1a8,
                                                    ),
                                                    advice_eval_3,
                                                  ),
                                                ),
                                                scaled_quintic(
                                                  from_int(
                                                    0x333f8046ece5579cbd6872449c57f2703dfc8864cfadc06d587ff104a0d0c1f2,
                                                  ),
                                                  advice_eval_4,
                                                ),
                                              ),
                                              scaled_quintic(
                                                from_int(
                                                  0x412c98232b6ab8a47aa76ee814ef7ec6261987c9802f2cfc490e007951a60ca5,
                                                ),
                                                advice_eval_5,
                                              ),
                                            ),
                                            scaled_quintic(
                                              from_int(
                                                0x53fded36d490ba6b05a5d10fd99ffe5456baec6a6a8753199d5ebdc33c99790e,
                                              ),
                                              advice_eval_9,
                                            ),
                                          ),
                                          scaled_quintic(
                                            from_int(
                                              0x6ccb1c7d87f3c12a2bde4e68ac7f1e8b03481ba15d7f88f9a7f9b8310dd6d34,
                                            ),
                                            advice_eval_10,
                                          ),
                                        ),
                                        scaled_quintic(
                                          from_int(
                                            0x3f05c4df7a6664dabe258779bf548eb4007f33601591080b3ecd34aea0e1edc1,
                                          ),
                                          advice_eval_11,
                                        ),
                                      ),
                                    ),
                                  ),
                                  trash_challenge,
                                ),
                                add(
                                  add(fixed_eval_8, neg(advice_eval_7)),
                                  add(
                                    add(
                                      add(
                                        add(
                                          add(
                                            add(
                                              add(
                                                mul(
                                                  from_int(
                                                    0x5b1fc262a28cbb8bf75d9b1a6edaa74591ec24cd9a209512213cec3a3c0f1a5d,
                                                  ),
                                                  advice_eval_1,
                                                ),
                                                mul(
                                                  from_int(
                                                    0x4d0ea7f9c3fda06d9535b0fdafd8338bd47c2200b284fa71a325ff41ac358028,
                                                  ),
                                                  advice_eval_2,
                                                ),
                                              ),
                                              scaled_quintic(
                                                from_int(
                                                  0x26cc223e16f47c20e17cc6069605fa5a8af05ea4f6eb36029a641d23b818eb10,
                                                ),
                                                advice_eval_3,
                                              ),
                                            ),
                                            scaled_quintic(
                                              from_int(
                                                0x31e823a45e567484c1544e310c0fa5cd66547a8f0dde659ac61698c30e838d25,
                                              ),
                                              advice_eval_4,
                                            ),
                                          ),
                                          scaled_quintic(
                                            from_int(
                                              0x275a20361ea91992193920270d3e2d1f6361880ac0a439c64bef815d4469ba85,
                                            ),
                                            advice_eval_5,
                                          ),
                                        ),
                                        scaled_quintic(
                                          from_int(
                                            0x5f3a15bab4ce4097b1edc3a25002694b92395ce355a8a12fe557459d9633f701,
                                          ),
                                          advice_eval_9,
                                        ),
                                      ),
                                      scaled_quintic(
                                        from_int(
                                          0x301cf56f9b4577112cc4241cddf6484aaadedbf1bbd0f2351adf2e41c2fb2ecd,
                                        ),
                                        advice_eval_10,
                                      ),
                                    ),
                                    scaled_quintic(
                                      from_int(
                                        0xfdf664da55059fa5a9388c641035d496d0bb519834348b4e2a8fc8c637f1a1f,
                                      ),
                                      advice_eval_11,
                                    ),
                                  ),
                                ),
                              ),
                              trash_challenge,
                            ),
                            add(
                              add(fixed_eval_9, neg(advice_eval_4)),
                              add(
                                add(
                                  mul(
                                    from_int(
                                      0x5e1d3dbecda6214343e24a47f45c5d033197ad01b65a730af95dc57e90c49140,
                                    ),
                                    advice_eval_1,
                                  ),
                                  mul(
                                    from_int(
                                      0x6bd72f9cfc53af9d931896e77ea5c61244cb6d5fae8954f37dc7b9002f5aa78a,
                                    ),
                                    advice_eval_2,
                                  ),
                                ),
                                scaled_quintic(
                                  from_int(
                                    0x4997c5aa3a5fa07bcaf880a9054bef831effbd9cd58e46d9bb4fb88ef99de0db,
                                  ),
                                  advice_eval_3,
                                ),
                              ),
                            ),
                          ),
                          trash_challenge,
                        ),
                        add(
                          add(fixed_eval_10, neg(advice_eval_5)),
                          add(
                            add(
                              add(
                                mul(
                                  from_int(
                                    0x222e83e70453dfee19b402e9fa8dfe2c4987b034d0be3ceb478b3022e97934c1,
                                  ),
                                  advice_eval_1,
                                ),
                                mul(
                                  from_int(
                                    0x26c2cc87f95726b28f33ca03409a460ec987cfe12adae32769e3565865d07191,
                                  ),
                                  advice_eval_2,
                                ),
                              ),
                              scaled_quintic(
                                from_int(
                                  0x4382d0938a760120dd6cef8f3b90a0c38abae475e3d21e39365472b76d780272,
                                ),
                                advice_eval_3,
                              ),
                            ),
                            scaled_quintic(
                              from_int(
                                0x4997c5aa3a5fa07bcaf880a9054bef831effbd9cd58e46d9bb4fb88ef99de0db,
                              ),
                              advice_eval_4,
                            ),
                          ),
                        ),
                      ),
                      trash_challenge,
                    ),
                    add(
                      add(fixed_eval_2, neg(advice_eval_9)),
                      add(
                        add(
                          add(
                            add(
                              mul(
                                from_int(
                                  0x726df1506749848155630b86ae25a82b281ecd050fe3a52d85a181fa87202e4b,
                                ),
                                advice_eval_1,
                              ),
                              mul(
                                from_int(
                                  0x24822e1af9aa2887c912c87eb0f20bd332330e7e55cd784de67cb407a9f05520,
                                ),
                                advice_eval_2,
                              ),
                            ),
                            scaled_quintic(
                              from_int(
                                0x4e5280109d8f96b8bfb543a6b1af25fb56a9db616af85a90eedc558e3eb1ea29,
                              ),
                              advice_eval_3,
                            ),
                          ),
                          scaled_quintic(
                            from_int(
                              0x4382d0938a760120dd6cef8f3b90a0c38abae475e3d21e39365472b76d780272,
                            ),
                            advice_eval_4,
                          ),
                        ),
                        scaled_quintic(
                          from_int(
                            0x4997c5aa3a5fa07bcaf880a9054bef831effbd9cd58e46d9bb4fb88ef99de0db,
                          ),
                          advice_eval_5,
                        ),
                      ),
                    ),
                  ),
                  trash_challenge,
                ),
                add(
                  add(fixed_eval_3, neg(advice_eval_10)),
                  add(
                    add(
                      add(
                        add(
                          add(
                            mul(
                              from_int(
                                0x2f5908b169c6cf1bd26dcf0f9e5105481f5164f3ece0582bf3098312167751a7,
                              ),
                              advice_eval_1,
                            ),
                            mul(
                              from_int(
                                0x23a6684b942d726a22e4d5b8d8ff83aeaa773f62600184efe5d033d7c7c6e827,
                              ),
                              advice_eval_2,
                            ),
                          ),
                          scaled_quintic(
                            from_int(
                              0x1981b4b33d6a9dab957b351d981d3323e65da39493af5bc01f7e8ffe17f98d4e,
                            ),
                            advice_eval_3,
                          ),
                        ),
                        scaled_quintic(
                          from_int(
                            0x4e5280109d8f96b8bfb543a6b1af25fb56a9db616af85a90eedc558e3eb1ea29,
                          ),
                          advice_eval_4,
                        ),
                      ),
                      scaled_quintic(
                        from_int(
                          0x4382d0938a760120dd6cef8f3b90a0c38abae475e3d21e39365472b76d780272,
                        ),
                        advice_eval_5,
                      ),
                    ),
                    mul(
                      from_int(
                        0x4997c5aa3a5fa07bcaf880a9054bef831effbd9cd58e46d9bb4fb88ef99de0db,
                      ),
                      mul(
                        advice_eval_9,
                        mul(
                          mul(advice_eval_9, advice_eval_9),
                          mul(advice_eval_9, advice_eval_9),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              trash_challenge,
            ),
            add(
              add(fixed_eval_4, neg(advice_eval_11)),
              add(
                add(
                  add(
                    add(
                      add(
                        add(
                          mul(
                            from_int(
                              0x6d05a41959f539a7fc9ec0972ea1e3dbb6fc67dd51daf3414f7fbbb091c7274a,
                            ),
                            advice_eval_1,
                          ),
                          mul(
                            from_int(
                              0x27e7119226c42a6d19c1541904b99ae40685511ed2e078964b74594d38340849,
                            ),
                            advice_eval_2,
                          ),
                        ),
                        scaled_quintic(
                          from_int(
                            0xd94c46a8456352aa44d7a885ab59e3a36664e6fb25e826f8a4cd79822f0533,
                          ),
                          advice_eval_3,
                        ),
                      ),
                      scaled_quintic(
                        from_int(
                          0x1981b4b33d6a9dab957b351d981d3323e65da39493af5bc01f7e8ffe17f98d4e,
                        ),
                        advice_eval_4,
                      ),
                    ),
                    scaled_quintic(
                      from_int(
                        0x4e5280109d8f96b8bfb543a6b1af25fb56a9db616af85a90eedc558e3eb1ea29,
                      ),
                      advice_eval_5,
                    ),
                  ),
                  scaled_quintic(
                    from_int(
                      0x4382d0938a760120dd6cef8f3b90a0c38abae475e3d21e39365472b76d780272,
                    ),
                    advice_eval_9,
                  ),
                ),
                scaled_quintic(
                  from_int(
                    0x4997c5aa3a5fa07bcaf880a9054bef831effbd9cd58e46d9bb4fb88ef99de0db,
                  ),
                  advice_eval_10,
                ),
              ),
            ),
          ),
          trash_challenge,
        ),
        add(
          add(fixed_eval_5, neg(advice_eval_8)),
          add(
            add(
              add(
                add(
                  add(
                    add(
                      add(
                        mul(
                          from_int(
                            0x70d8f2a733a64d650faccc9b1c2a766a9544bb3ff1a11ee73cb43947ef386633,
                          ),
                          advice_eval_1,
                        ),
                        mul(
                          from_int(
                            0x40fa389feb2522bb934881ac9ed749aee2296502af592418c6b5675c0f560261,
                          ),
                          advice_eval_2,
                        ),
                      ),
                      scaled_quintic(
                        from_int(
                          0x1f61345b652161410c5e29f51e301ae56342af824bc110649393d2b911c50d3e,
                        ),
                        advice_eval_3,
                      ),
                    ),
                    scaled_quintic(
                      from_int(
                        0xd94c46a8456352aa44d7a885ab59e3a36664e6fb25e826f8a4cd79822f0533,
                      ),
                      advice_eval_4,
                    ),
                  ),
                  scaled_quintic(
                    from_int(
                      0x1981b4b33d6a9dab957b351d981d3323e65da39493af5bc01f7e8ffe17f98d4e,
                    ),
                    advice_eval_5,
                  ),
                ),
                scaled_quintic(
                  from_int(
                    0x4e5280109d8f96b8bfb543a6b1af25fb56a9db616af85a90eedc558e3eb1ea29,
                  ),
                  advice_eval_9,
                ),
              ),
              scaled_quintic(
                from_int(
                  0x4382d0938a760120dd6cef8f3b90a0c38abae475e3d21e39365472b76d780272,
                ),
                advice_eval_10,
              ),
            ),
            scaled_quintic(
              from_int(
                0x4997c5aa3a5fa07bcaf880a9054bef831effbd9cd58e46d9bb4fb88ef99de0db,
              ),
              advice_eval_11,
            ),
          ),
        ),
      ),
      neg(mul(add(scalarOne, neg(fixed_eval_22)), trash_eval_1)),
    )

  let term_1 =
    mul(evaluation_at_0, add(scalarOne, neg(permutations_evaluated_a_1)))
  let term_2 =
    mul(
      last_evaluation,
      add(
        mul(permutations_evaluated_d_1, permutations_evaluated_d_1),
        neg(permutations_evaluated_d_1),
      ),
    )
  let term_3 =
    mul(
      add(permutations_evaluated_b_1, neg(permutations_evaluated_a_3)),
      evaluation_at_0,
    )
  let term_4 =
    mul(
      add(permutations_evaluated_c_1, neg(permutations_evaluated_b_3)),
      evaluation_at_0,
    )
  let term_5 =
    mul(
      add(permutations_evaluated_d_1, neg(permutations_evaluated_c_3)),
      evaluation_at_0,
    )

  let left1 = add(add(fixed_eval_1, mul(beta, permutation_common_1)), gamma)
  //part of set a
  let left2 = add(add(advice_eval_1, mul(beta, permutation_common_2)), gamma)
  //part of set a
  let left3 = add(add(advice_eval_2, mul(beta, permutation_common_3)), gamma)
  //part of set a
  let left4 = add(add(advice_eval_3, mul(beta, permutation_common_4)), gamma)
  //part of set b
  let left5 = add(add(advice_eval_4, mul(beta, permutation_common_5)), gamma)
  //part of set b
  let left6 = add(add(advice_eval_5, mul(beta, permutation_common_6)), gamma)
  //part of set b
  let left7 = add(add(instance_eval_1, mul(beta, permutation_common_7)), gamma)
  //part of set c
  let left8 = add(add(instance_eval_2, mul(beta, permutation_common_8)), gamma)
  //part of set c
  let left9 = add(add(advice_eval_9, mul(beta, permutation_common_9)), gamma)
  //part of set c
  let left10 = add(add(advice_eval_10, mul(beta, permutation_common_10)), gamma)

  //part of set d
  let left_set1 = mul(permutations_evaluated_a_2, mul(mul(left1, left2), left3))
  let left_set2 = mul(permutations_evaluated_b_2, mul(mul(left4, left5), left6))
  let left_set3 = mul(permutations_evaluated_c_2, mul(mul(left7, left8), left9))
  let left_set4 = mul(permutations_evaluated_d_2, left10)

  let right1 =
    add(add(fixed_eval_1, mul(mul(beta, x), scale(scalarDelta, 0))), gamma)
  //part of set a
  let right2 =
    add(add(advice_eval_1, mul(mul(beta, x), scale(scalarDelta, 1))), gamma)
  //part of set a
  let right3 =
    add(add(advice_eval_2, mul(mul(beta, x), scale(scalarDelta, 2))), gamma)
  //part of set a
  let right4 =
    add(add(advice_eval_3, mul(mul(beta, x), scale(scalarDelta, 3))), gamma)
  //part of set b
  let right5 =
    add(add(advice_eval_4, mul(mul(beta, x), scale(scalarDelta, 4))), gamma)
  //part of set b
  let right6 =
    add(add(advice_eval_5, mul(mul(beta, x), scale(scalarDelta, 5))), gamma)
  //part of set b
  let right7 =
    add(add(instance_eval_1, mul(mul(beta, x), scale(scalarDelta, 6))), gamma)
  //part of set c
  let right8 =
    add(add(instance_eval_2, mul(mul(beta, x), scale(scalarDelta, 7))), gamma)
  //part of set c
  let right9 =
    add(add(advice_eval_9, mul(mul(beta, x), scale(scalarDelta, 8))), gamma)
  //part of set c
  let right10 =
    add(add(advice_eval_10, mul(mul(beta, x), scale(scalarDelta, 9))), gamma)

  //part of set d
  let right_set1 =
    mul(permutations_evaluated_a_1, mul(mul(right1, right2), right3))
  let right_set2 =
    mul(permutations_evaluated_b_1, mul(mul(right4, right5), right6))
  let right_set3 =
    mul(permutations_evaluated_c_1, mul(mul(right7, right8), right9))
  let right_set4 = mul(permutations_evaluated_d_1, right10)

  let permutations1 =
    mul(
      sub(left_set1, right_set1),
      sub(
        scalarOne,
        add(last_evaluation, sum_of_evaluation_for_blinding_factors),
      ),
    )
  let permutations2 =
    mul(
      sub(left_set2, right_set2),
      sub(
        scalarOne,
        add(last_evaluation, sum_of_evaluation_for_blinding_factors),
      ),
    )
  let permutations3 =
    mul(
      sub(left_set3, right_set3),
      sub(
        scalarOne,
        add(last_evaluation, sum_of_evaluation_for_blinding_factors),
      ),
    )
  let permutations4 =
    mul(
      sub(left_set4, right_set4),
      sub(
        scalarOne,
        add(last_evaluation, sum_of_evaluation_for_blinding_factors),
      ),
    )

  //      expressions for vanishing polynomial
  let expression1 = gate_eq1
  let expression2 = gate_eq2
  let expression3 = gate_eq3
  let expression4 = gate_eq4
  let expression5 = gate_eq5
  let expression6 = gate_eq6
  let expression7 = gate_eq7
  let expression8 = gate_eq8
  let expression9 = gate_eq9
  let expression10 = gate_eq10
  let expression11 = gate_eq11
  let expression12 = gate_eq12
  let expression13 = gate_eq13
  let expression14 = gate_eq14
  let expression15 = gate_eq15
  let expression16 = gate_eq16
  let expression17 = gate_eq17
  let expression18 = gate_eq18
  let expression19 = term_1
  let expression20 = term_2
  let expression21 = term_3
  let expression22 = term_4
  let expression23 = term_5
  let expression24 = permutations1
  let expression25 = permutations2
  let expression26 = permutations3
  let expression27 = permutations4
  let expression28 = lookup_expression_1_1
  let expression29 = lookup_expression_2_1
  let expression30 = lookup_expression_3_1
  let expression31 = lookup_expression_4_1
  let expression32 = lookup_expression_5_1
  let expression33 = lookup_expression_1_2
  let expression34 = lookup_expression_2_2
  let expression35 = lookup_expression_3_2
  let expression36 = lookup_expression_4_2
  let expression37 = lookup_expression_5_2
  let expression38 = trash_expression_1

  let hEval =
    add(
      mul(
        add(
          mul(
            add(
              mul(
                add(
                  mul(
                    add(
                      mul(
                        add(
                          mul(
                            add(
                              mul(
                                add(
                                  mul(
                                    add(
                                      mul(
                                        add(
                                          mul(
                                            add(
                                              mul(
                                                add(
                                                  mul(
                                                    add(
                                                      mul(
                                                        add(
                                                          mul(
                                                            add(
                                                              mul(
                                                                add(
                                                                  mul(
                                                                    add(
                                                                      mul(
                                                                        add(
                                                                          mul(
                                                                            add(
                                                                              mul(
                                                                                add(
                                                                                  mul(
                                                                                    add(
                                                                                      mul(
                                                                                        add(
                                                                                          mul(
                                                                                            add(
                                                                                              mul(
                                                                                                add(
                                                                                                  mul(
                                                                                                    add(
                                                                                                      mul(
                                                                                                        add(
                                                                                                          mul(
                                                                                                            add(
                                                                                                              mul(
                                                                                                                add(
                                                                                                                  mul(
                                                                                                                    add(
                                                                                                                      mul(
                                                                                                                        add(
                                                                                                                          mul(
                                                                                                                            add(
                                                                                                                              mul(
                                                                                                                                add(
                                                                                                                                  mul(
                                                                                                                                    add(
                                                                                                                                      mul(
                                                                                                                                        add(
                                                                                                                                          mul(
                                                                                                                                            add(
                                                                                                                                              mul(
                                                                                                                                                add(
                                                                                                                                                  mul(
                                                                                                                                                    add(
                                                                                                                                                      mul(
                                                                                                                                                        expression1,
                                                                                                                                                        y,
                                                                                                                                                      ),
                                                                                                                                                      expression2,
                                                                                                                                                    ),
                                                                                                                                                    y,
                                                                                                                                                  ),
                                                                                                                                                  expression3,
                                                                                                                                                ),
                                                                                                                                                y,
                                                                                                                                              ),
                                                                                                                                              expression4,
                                                                                                                                            ),
                                                                                                                                            y,
                                                                                                                                          ),
                                                                                                                                          expression5,
                                                                                                                                        ),
                                                                                                                                        y,
                                                                                                                                      ),
                                                                                                                                      expression6,
                                                                                                                                    ),
                                                                                                                                    y,
                                                                                                                                  ),
                                                                                                                                  expression7,
                                                                                                                                ),
                                                                                                                                y,
                                                                                                                              ),
                                                                                                                              expression8,
                                                                                                                            ),
                                                                                                                            y,
                                                                                                                          ),
                                                                                                                          expression9,
                                                                                                                        ),
                                                                                                                        y,
                                                                                                                      ),
                                                                                                                      expression10,
                                                                                                                    ),
                                                                                                                    y,
                                                                                                                  ),
                                                                                                                  expression11,
                                                                                                                ),
                                                                                                                y,
                                                                                                              ),
                                                                                                              expression12,
                                                                                                            ),
                                                                                                            y,
                                                                                                          ),
                                                                                                          expression13,
                                                                                                        ),
                                                                                                        y,
                                                                                                      ),
                                                                                                      expression14,
                                                                                                    ),
                                                                                                    y,
                                                                                                  ),
                                                                                                  expression15,
                                                                                                ),
                                                                                                y,
                                                                                              ),
                                                                                              expression16,
                                                                                            ),
                                                                                            y,
                                                                                          ),
                                                                                          expression17,
                                                                                        ),
                                                                                        y,
                                                                                      ),
                                                                                      expression18,
                                                                                    ),
                                                                                    y,
                                                                                  ),
                                                                                  expression19,
                                                                                ),
                                                                                y,
                                                                              ),
                                                                              expression20,
                                                                            ),
                                                                            y,
                                                                          ),
                                                                          expression21,
                                                                        ),
                                                                        y,
                                                                      ),
                                                                      expression22,
                                                                    ),
                                                                    y,
                                                                  ),
                                                                  expression23,
                                                                ),
                                                                y,
                                                              ),
                                                              expression24,
                                                            ),
                                                            y,
                                                          ),
                                                          expression25,
                                                        ),
                                                        y,
                                                      ),
                                                      expression26,
                                                    ),
                                                    y,
                                                  ),
                                                  expression27,
                                                ),
                                                y,
                                              ),
                                              expression28,
                                            ),
                                            y,
                                          ),
                                          expression29,
                                        ),
                                        y,
                                      ),
                                      expression30,
                                    ),
                                    y,
                                  ),
                                  expression31,
                                ),
                                y,
                              ),
                              expression32,
                            ),
                            y,
                          ),
                          expression33,
                        ),
                        y,
                      ),
                      expression34,
                    ),
                    y,
                  ),
                  expression35,
                ),
                y,
              ),
              expression36,
            ),
            y,
          ),
          expression37,
        ),
        y,
      ),
      expression38,
    )

  let inverted = recip_eea(sub(xn, scalarOne))
  // recip is inverse of the number mod bls12_381_field_prime
  let vanishing_s = mul(hEval, inverted)

  // vanishing split IS PASSED IN REVERSE ORDER!!!
  // this is MSM done for h-commitments
  let hCommitment1 = vanishing_split_4
  let hCommitment2 = addG1(scaleG1(hCommitment1, x_chop), vanishing_split_3)
  let hCommitment3 = addG1(scaleG1(hCommitment2, x_chop), vanishing_split_2)
  let vanishing_g = addG1(scaleG1(hCommitment3, x_chop), vanishing_split_1)

  let vanishing_g = compress(vanishing_g)

  let set_0 =
    [
      (f15_commitment, [instance_eval_1]), (a4, [advice_eval_4]),
      (a5, [advice_eval_5]), (a6, [advice_eval_9]), (a7, [advice_eval_10]),
      (a8, [advice_eval_11]), (a9, [advice_eval_12]),
      (permuted_table_1, [permuted_table_eval_1]),
      (permuted_table_2, [permuted_table_eval_2]),
      (trash_commitment_1, [trash_eval_1]), (f10_commitment, [fixed_eval_1]),
      (f5_commitment, [fixed_eval_2]), (f6_commitment, [fixed_eval_3]),
      (f7_commitment, [fixed_eval_4]), (f8_commitment, [fixed_eval_5]),
      (f9_commitment, [fixed_eval_6]), (f1_commitment, [fixed_eval_7]),
      (f2_commitment, [fixed_eval_8]), (f3_commitment, [fixed_eval_9]),
      (f4_commitment, [fixed_eval_10]), (f11_commitment, [fixed_eval_11]),
      (f12_commitment, [fixed_eval_12]), (f13_commitment, [fixed_eval_13]),
      (f14_commitment, [fixed_eval_14]), (f15_commitment, [fixed_eval_15]),
      (f16_commitment, [fixed_eval_16]), (f17_commitment, [fixed_eval_17]),
      (f18_commitment, [fixed_eval_18]), (f19_commitment, [fixed_eval_19]),
      (f20_commitment, [fixed_eval_20]), (f21_commitment, [fixed_eval_21]),
      (f22_commitment, [fixed_eval_22]), (p1_commitment, [permutation_common_1]),
      (p2_commitment, [permutation_common_2]),
      (p3_commitment, [permutation_common_3]),
      (p4_commitment, [permutation_common_4]),
      (p5_commitment, [permutation_common_5]),
      (p6_commitment, [permutation_common_6]),
      (p7_commitment, [permutation_common_7]),
      (p8_commitment, [permutation_common_8]),
      (p9_commitment, [permutation_common_9]),
      (p10_commitment, [permutation_common_10]), (vanishing_g, [vanishing_s]),
      (vanishing_rand, [random_eval]),
    ]
  let set_1 =
    [
      (a1, [advice_eval_1, advice_eval_6]), (a2, [advice_eval_2, advice_eval_7]),
      (a3, [advice_eval_3, advice_eval_8]),
      (
        permutations_committed_d,
        [permutations_evaluated_d_1, permutations_evaluated_d_2],
      ), (lookup_commitment_1, [product_eval_1, product_next_eval_1]),
      (lookup_commitment_2, [product_eval_2, product_next_eval_2]),
    ]
  let set_2 =
    [
      (
        permutations_committed_a,
        [
          permutations_evaluated_a_1, permutations_evaluated_a_2,
          permutations_evaluated_a_3,
        ],
      ),
      (
        permutations_committed_b,
        [
          permutations_evaluated_b_1, permutations_evaluated_b_2,
          permutations_evaluated_b_3,
        ],
      ),
      (
        permutations_committed_c,
        [
          permutations_evaluated_c_1, permutations_evaluated_c_2,
          permutations_evaluated_c_3,
        ],
      ),
    ]
  let set_3 =
    [
      (permuted_input_1, [permuted_input_eval_1, permuted_input_inv_eval_1]),
      (permuted_input_2, [permuted_input_eval_2, permuted_input_inv_eval_2]),
    ]

  // ── Phase 1 specific: prefix accumulator + v + datum ──────────────
  let x1Powers = powers(44, x1)
  let x4Powers = powers(5, x4)

  // Prefix G1 accumulator: first 17 entries of set 0
  // (split rebalanced from 23 to 17 to equalize TX1/TX2 cost)
  let rhs_prefix_g1 = accumulate_g1_prefix(x1Powers, set_0, 17)
  let rhs_prefix = compress(rhs_prefix_g1)

  // Compute q_eval for each rotation set
  let evals_1 = compute_q_eval_for_entries(x1Powers, set_0)
  let term_1 = q_eval_term([x_current], evals_1, q_eval_on_x3_1, x3)
  let evals_2 = compute_q_eval_for_entries(x1Powers, set_1)
  let term_2 = q_eval_term([x_current, x_next], evals_2, q_eval_on_x3_2, x3)
  let evals_3 = compute_q_eval_for_entries(x1Powers, set_2)
  let term_3 =
    q_eval_term([x_current, x_next, x_last], evals_3, q_eval_on_x3_3, x3)
  let evals_4 = compute_q_eval_for_entries(x1Powers, set_3)
  let term_4 = q_eval_term([x_current, x_prev], evals_4, q_eval_on_x3_4, x3)
  let f_eval =
    add(mul(add(mul(add(mul(term_4, x2), term_3), x2), term_2), x2), term_1)
  let v =
    compute_v(
      f_eval,
      x4Powers,
      [q_eval_on_x3_1, q_eval_on_x3_2, q_eval_on_x3_3, q_eval_on_x3_4],
    )

  // Construct ReducedRedeemer (all fields are compressed G1 ByteArrays)
  let reduced_redeemer =
    ReducedRedeemer {
      vanishing_g,
      vanishing_rand,
      a1,
      a2,
      a3,
      perm_d: permutations_committed_d,
      lookup_1: lookup_commitment_1,
      lookup_2: lookup_commitment_2,
      perm_a: permutations_committed_a,
      perm_b: permutations_committed_b,
      perm_c: permutations_committed_c,
      perm_input_1: permuted_input_1,
      perm_input_2: permuted_input_2,
      f_commitment,
      pi_term,
    }

  let reduced_hash = blake2b_256(serialize_reduced_redeemer(reduced_redeemer))

  let state =
    Phase1State {
      rhs_prefix,
      reduced_hash,
      x1: to_bytes_little_endian(x1),
      x3: to_bytes_little_endian(x3),
      x4: to_bytes_little_endian(x4),
      v: to_bytes_little_endian(v),
    }

  (state, reduced_redeemer)
}

pub fn phase1_verifier_state(
  proof: Data,
  i_1: State<Scalar>,
  i_2: State<Scalar>,
) -> Phase1State {
  let scalarZero = from_int(0)
  let scalarOne = from_int(1)
  let scalarDelta =
    from_int(0x8634d0aa021aaf843cab354fabb0062f6502437c6a09c006c083479590189d7)

  let transcript = construct_transcript(proof, transcript_rep)

  let transcript = common_point(f15_commitment, transcript)

  let transcript = common_scalar(from_int(2), transcript)
  let transcript = common_scalar(i_1, transcript)
  let transcript = common_scalar(i_2, transcript)

  let (a1, transcript) = read_point(transcript)
  let (a2, transcript) = read_point(transcript)
  let (a3, transcript) = read_point(transcript)
  let (a4, transcript) = read_point(transcript)
  let (a5, transcript) = read_point(transcript)
  let (a6, transcript) = read_point(transcript)
  let (a7, transcript) = read_point(transcript)
  let (a8, transcript) = read_point(transcript)
  let (a9, transcript) = read_point(transcript)
  let (theta, transcript) = squeeze_challenge(transcript)
  let (permuted_input_1, transcript) = read_point(transcript)
  let (permuted_table_1, transcript) = read_point(transcript)
  let (permuted_input_2, transcript) = read_point(transcript)
  let (permuted_table_2, transcript) = read_point(transcript)
  let (beta, transcript) = squeeze_challenge(transcript)
  let (gamma, transcript) = squeeze_challenge(transcript)
  let (permutations_committed_a, transcript) = read_point(transcript)
  let (permutations_committed_b, transcript) = read_point(transcript)
  let (permutations_committed_c, transcript) = read_point(transcript)
  let (permutations_committed_d, transcript) = read_point(transcript)
  let (lookup_commitment_1, transcript) = read_point(transcript)
  let (lookup_commitment_2, transcript) = read_point(transcript)
  let (trash_challenge, transcript) = squeeze_challenge(transcript)
  let (trash_commitment_1, transcript) = read_point(transcript)
  let (vanishing_rand, transcript) = read_point(transcript)
  let (y, transcript) = squeeze_challenge(transcript)
  let (vanishing_split_1, transcript) = read_point(transcript)
  let vanishing_split_1 = decompress(vanishing_split_1)
  let (vanishing_split_2, transcript) = read_point(transcript)
  let vanishing_split_2 = decompress(vanishing_split_2)
  let (vanishing_split_3, transcript) = read_point(transcript)
  let vanishing_split_3 = decompress(vanishing_split_3)
  let (vanishing_split_4, transcript) = read_point(transcript)
  let vanishing_split_4 = decompress(vanishing_split_4)
  let (x, transcript) = squeeze_challenge(transcript)
  let (instance_eval_1, transcript) = read_scalar(transcript)
  let (advice_eval_1, transcript) = read_scalar(transcript)
  let (advice_eval_2, transcript) = read_scalar(transcript)
  let (advice_eval_3, transcript) = read_scalar(transcript)
  let (advice_eval_4, transcript) = read_scalar(transcript)
  let (advice_eval_5, transcript) = read_scalar(transcript)
  let (advice_eval_6, transcript) = read_scalar(transcript)
  let (advice_eval_7, transcript) = read_scalar(transcript)
  let (advice_eval_8, transcript) = read_scalar(transcript)
  let (advice_eval_9, transcript) = read_scalar(transcript)
  let (advice_eval_10, transcript) = read_scalar(transcript)
  let (advice_eval_11, transcript) = read_scalar(transcript)
  let (advice_eval_12, transcript) = read_scalar(transcript)
  let (fixed_eval_1, transcript) = read_scalar(transcript)
  let (fixed_eval_2, transcript) = read_scalar(transcript)
  let (fixed_eval_3, transcript) = read_scalar(transcript)
  let (fixed_eval_4, transcript) = read_scalar(transcript)
  let (fixed_eval_5, transcript) = read_scalar(transcript)
  let (fixed_eval_6, transcript) = read_scalar(transcript)
  let (fixed_eval_7, transcript) = read_scalar(transcript)
  let (fixed_eval_8, transcript) = read_scalar(transcript)
  let (fixed_eval_9, transcript) = read_scalar(transcript)
  let (fixed_eval_10, transcript) = read_scalar(transcript)
  let (fixed_eval_11, transcript) = read_scalar(transcript)
  let (fixed_eval_12, transcript) = read_scalar(transcript)
  let (fixed_eval_13, transcript) = read_scalar(transcript)
  let (fixed_eval_14, transcript) = read_scalar(transcript)
  let (fixed_eval_15, transcript) = read_scalar(transcript)
  let (fixed_eval_16, transcript) = read_scalar(transcript)
  let (fixed_eval_17, transcript) = read_scalar(transcript)
  let (fixed_eval_18, transcript) = read_scalar(transcript)
  let (fixed_eval_19, transcript) = read_scalar(transcript)
  let (fixed_eval_20, transcript) = read_scalar(transcript)
  let (fixed_eval_21, transcript) = read_scalar(transcript)
  let (fixed_eval_22, transcript) = read_scalar(transcript)
  let (random_eval, transcript) = read_scalar(transcript)
  let (permutation_common_1, transcript) = read_scalar(transcript)
  let (permutation_common_2, transcript) = read_scalar(transcript)
  let (permutation_common_3, transcript) = read_scalar(transcript)
  let (permutation_common_4, transcript) = read_scalar(transcript)
  let (permutation_common_5, transcript) = read_scalar(transcript)
  let (permutation_common_6, transcript) = read_scalar(transcript)
  let (permutation_common_7, transcript) = read_scalar(transcript)
  let (permutation_common_8, transcript) = read_scalar(transcript)
  let (permutation_common_9, transcript) = read_scalar(transcript)
  let (permutation_common_10, transcript) = read_scalar(transcript)
  let (permutations_evaluated_a_1, transcript) = read_scalar(transcript)
  let (permutations_evaluated_a_2, transcript) = read_scalar(transcript)
  let (permutations_evaluated_a_3, transcript) = read_scalar(transcript)
  let (permutations_evaluated_b_1, transcript) = read_scalar(transcript)
  let (permutations_evaluated_b_2, transcript) = read_scalar(transcript)
  let (permutations_evaluated_b_3, transcript) = read_scalar(transcript)
  let (permutations_evaluated_c_1, transcript) = read_scalar(transcript)
  let (permutations_evaluated_c_2, transcript) = read_scalar(transcript)
  let (permutations_evaluated_c_3, transcript) = read_scalar(transcript)
  let (permutations_evaluated_d_1, transcript) = read_scalar(transcript)
  let (permutations_evaluated_d_2, transcript) = read_scalar(transcript)
  let (product_eval_1, transcript) = read_scalar(transcript)
  let (product_next_eval_1, transcript) = read_scalar(transcript)
  let (permuted_input_eval_1, transcript) = read_scalar(transcript)
  let (permuted_input_inv_eval_1, transcript) = read_scalar(transcript)
  let (permuted_table_eval_1, transcript) = read_scalar(transcript)
  let (product_eval_2, transcript) = read_scalar(transcript)
  let (product_next_eval_2, transcript) = read_scalar(transcript)
  let (permuted_input_eval_2, transcript) = read_scalar(transcript)
  let (permuted_input_inv_eval_2, transcript) = read_scalar(transcript)
  let (permuted_table_eval_2, transcript) = read_scalar(transcript)
  let (trash_eval_1, transcript) = read_scalar(transcript)
  let (x1, transcript) = squeeze_challenge(transcript)
  let (x2, transcript) = squeeze_challenge(transcript)
  let (f_commitment, transcript) = read_point(transcript)
  let (x3, transcript) = squeeze_challenge(transcript)
  let (q_eval_on_x3_1, transcript) = read_scalar(transcript)
  let (q_eval_on_x3_2, transcript) = read_scalar(transcript)
  let (q_eval_on_x3_3, transcript) = read_scalar(transcript)
  let (q_eval_on_x3_4, transcript) = read_scalar(transcript)
  let (x4, transcript) = squeeze_challenge(transcript)
  let (pi_term, _) = read_point(transcript)

  let n = 16384
  let xn = scale(x, n)
  let x_chop = scale(x, n - 1)

  let x_prev = rotate_omega(omega, omega_inv, x, -1)
  let x_current = rotate_omega(omega, omega_inv, x, 0)
  let x_next = rotate_omega(omega, omega_inv, x, 1)
  let x_last = rotate_omega(omega, omega_inv, x, -(blinding_factors + 1))

  let vanishing_lagrange_terms = phase1_vanishing_lagrange_terms(x, xn)
  let last_evaluation = vanishing_lagrange_terms.last_evaluation
  let evaluation_at_0 = vanishing_lagrange_terms.evaluation_at_0
  let sum_of_evaluation_for_blinding_factors =
    vanishing_lagrange_terms.sum_of_evaluation_for_blinding_factors
  let active_rows =
    sub(scalarOne, add(last_evaluation, sum_of_evaluation_for_blinding_factors))

  // -----------------------------------------------------------------------------------------------
  let instance_eval_2 = phase1_instance_eval_2(x, xn, i_1, i_2)

  let gate_eq1 =
    mul(
      fixed_eval_14,
      add(
        add(
          add(
            add(
              add(
                add(
                  add(
                    add(fixed_eval_10, mul(fixed_eval_2, advice_eval_1)),
                    mul(fixed_eval_3, advice_eval_2),
                  ),
                  mul(fixed_eval_4, advice_eval_3),
                ),
                mul(fixed_eval_5, advice_eval_4),
              ),
              mul(fixed_eval_6, advice_eval_5),
            ),
            mul(fixed_eval_7, advice_eval_6),
          ),
          mul(mul(fixed_eval_8, advice_eval_1), advice_eval_2),
        ),
        mul(mul(fixed_eval_9, advice_eval_1), advice_eval_3),
      ),
    )
  let gate_eq2 =
    mul(
      fixed_eval_15,
      add(
        add(add(advice_eval_2, advice_eval_3), neg(advice_eval_4)),
        neg(advice_eval_5),
      ),
    )
  let gate_eq3 =
    mul(
      fixed_eval_16,
      add(add(advice_eval_1, fixed_eval_2), neg(advice_eval_6)),
    )
  let gate_eq4 =
    mul(
      fixed_eval_16,
      add(add(advice_eval_2, fixed_eval_3), neg(advice_eval_7)),
    )
  let gate_eq5 =
    mul(
      fixed_eval_16,
      add(add(advice_eval_3, fixed_eval_4), neg(advice_eval_8)),
    )
  let gate_eq6 =
    mul(
      fixed_eval_18,
      add(
        mul(
          advice_eval_6,
          add(
            scalarOne,
            mul(
              mul(
                from_int(
                  0x2a9318e74bfa2b48f5fd9207e6bd7fd4292d7f6d37579d2601065fd6d6343eb1,
                ),
                advice_eval_11,
              ),
              mul(advice_eval_10, advice_eval_10),
            ),
          ),
        ),
        neg(
          add(
            mul(advice_eval_9, advice_eval_10),
            mul(advice_eval_9, advice_eval_10),
          ),
        ),
      ),
    )
  let gate_eq7 =
    mul(
      fixed_eval_18,
      add(
        mul(
          advice_eval_7,
          add(
            scalarOne,
            neg(
              mul(
                mul(
                  from_int(
                    0x2a9318e74bfa2b48f5fd9207e6bd7fd4292d7f6d37579d2601065fd6d6343eb1,
                  ),
                  advice_eval_11,
                ),
                mul(advice_eval_10, advice_eval_10),
              ),
            ),
          ),
        ),
        neg(add(mul(advice_eval_10, advice_eval_10), advice_eval_11)),
      ),
    )
  let gate_eq8 =
    mul(
      fixed_eval_18,
      add(mul(advice_eval_9, advice_eval_9), neg(advice_eval_11)),
    )
  let gate_eq9 =
    mul(
      fixed_eval_19,
      add(
        mul(
          advice_eval_9,
          add(
            scalarOne,
            mul(
              mul(
                advice_eval_5,
                from_int(
                  0x2a9318e74bfa2b48f5fd9207e6bd7fd4292d7f6d37579d2601065fd6d6343eb1,
                ),
              ),
              advice_eval_12,
            ),
          ),
        ),
        neg(
          add(
            advice_eval_1,
            mul(
              advice_eval_5,
              add(
                add(
                  mul(advice_eval_1, advice_eval_4),
                  mul(advice_eval_3, advice_eval_2),
                ),
                neg(advice_eval_1),
              ),
            ),
          ),
        ),
      ),
    )
  let gate_eq10 =
    mul(
      fixed_eval_19,
      add(
        mul(
          advice_eval_10,
          add(
            scalarOne,
            neg(
              mul(
                mul(
                  advice_eval_5,
                  from_int(
                    0x2a9318e74bfa2b48f5fd9207e6bd7fd4292d7f6d37579d2601065fd6d6343eb1,
                  ),
                ),
                advice_eval_12,
              ),
            ),
          ),
        ),
        neg(
          add(
            advice_eval_2,
            mul(
              advice_eval_5,
              add(
                add(
                  mul(advice_eval_2, advice_eval_4),
                  mul(advice_eval_1, advice_eval_3),
                ),
                neg(advice_eval_2),
              ),
            ),
          ),
        ),
      ),
    )
  let gate_eq11 =
    mul(
      fixed_eval_19,
      add(
        advice_eval_12,
        neg(
          mul(
            mul(mul(advice_eval_1, advice_eval_2), advice_eval_3),
            advice_eval_4,
          ),
        ),
      ),
    )
  let gate_eq12 =
    mul(
      fixed_eval_20,
      add(
        add(
          mul(advice_eval_2, advice_eval_2),
          neg(mul(advice_eval_1, advice_eval_1)),
        ),
        neg(
          add(
            scalarOne,
            mul(
              mul(
                from_int(
                  0x2a9318e74bfa2b48f5fd9207e6bd7fd4292d7f6d37579d2601065fd6d6343eb1,
                ),
                mul(advice_eval_1, advice_eval_1),
              ),
              mul(advice_eval_2, advice_eval_2),
            ),
          ),
        ),
      ),
    )
  let gate_eq13 =
    mul(
      fixed_eval_21,
      add(
        mul(advice_eval_1, mul(advice_eval_1, advice_eval_1)),
        neg(advice_eval_4),
      ),
    )
  let gate_eq14 =
    mul(
      fixed_eval_21,
      add(
        mul(advice_eval_2, mul(advice_eval_2, advice_eval_2)),
        neg(advice_eval_5),
      ),
    )
  let gate_eq15 =
    mul(
      fixed_eval_21,
      add(
        mul(advice_eval_3, mul(advice_eval_3, advice_eval_3)),
        neg(advice_eval_9),
      ),
    )
  let gate_eq16 =
    mul(
      fixed_eval_21,
      add(
        add(
          add(
            add(fixed_eval_7, neg(advice_eval_6)),
            mul(
              from_int(
                0x1b8114c381b922fd5d6d241210e2d8a68ad5744053ba9e776118de4107b51ace,
              ),
              mul(mul(advice_eval_1, advice_eval_1), advice_eval_4),
            ),
          ),
          mul(
            from_int(
              0x3df32e4cc4cb2ed20e5d21899cf5331775990ccaec4c09b4e3717213fcc0d763,
            ),
            mul(mul(advice_eval_2, advice_eval_2), advice_eval_5),
          ),
        ),
        mul(
          from_int(
            0x3f05c4df7a6664dabe258779bf548eb4007f33601591080b3ecd34aea0e1edc1,
          ),
          mul(mul(advice_eval_3, advice_eval_3), advice_eval_9),
        ),
      ),
    )
  let gate_eq17 =
    mul(
      fixed_eval_21,
      add(
        add(
          add(
            add(fixed_eval_8, neg(advice_eval_7)),
            mul(
              from_int(
                0x404d21073985d14e432a4ad76d3fae06ca74314b950fe7b1d7f501cd31a8b374,
              ),
              mul(mul(advice_eval_1, advice_eval_1), advice_eval_4),
            ),
          ),
          mul(
            from_int(
              0xb2cc8704264c6bd81bc620e9e524d4b73e9b2317679422ff7fa1603955649f1,
            ),
            mul(mul(advice_eval_2, advice_eval_2), advice_eval_5),
          ),
        ),
        mul(
          from_int(
            0xfdf664da55059fa5a9388c641035d496d0bb519834348b4e2a8fc8c637f1a1f,
          ),
          mul(mul(advice_eval_3, advice_eval_3), advice_eval_9),
        ),
      ),
    )
  let gate_eq18 =
    mul(
      fixed_eval_21,
      add(
        add(
          add(
            add(fixed_eval_9, neg(advice_eval_8)),
            mul(
              from_int(
                0x5e1d3dbecda6214343e24a47f45c5d033197ad01b65a730af95dc57e90c49140,
              ),
              mul(mul(advice_eval_1, advice_eval_1), advice_eval_4),
            ),
          ),
          mul(
            from_int(
              0x6bd72f9cfc53af9d931896e77ea5c61244cb6d5fae8954f37dc7b9002f5aa78a,
            ),
            mul(mul(advice_eval_2, advice_eval_2), advice_eval_5),
          ),
        ),
        mul(
          from_int(
            0x4997c5aa3a5fa07bcaf880a9054bef831effbd9cd58e46d9bb4fb88ef99de0db,
          ),
          mul(mul(advice_eval_3, advice_eval_3), advice_eval_9),
        ),
      ),
    )

  let lookup_table_eq =
    add(mul(add(mul(scalarZero, theta), fixed_eval_12), theta), fixed_eval_13)
  let lookup_input_eq_base =
    mul(add(mul(scalarZero, theta), fixed_eval_11), theta)

  let lookup_input_eq1 =
    add(lookup_input_eq_base, mul(fixed_eval_17, advice_eval_2))
  let lookup_input_eq2 =
    add(lookup_input_eq_base, mul(fixed_eval_17, advice_eval_3))

  let lookup_expression_1_1 =
    mul(evaluation_at_0, sub(scalarOne, product_eval_1))
  let lookup_expression_2_1 =
    mul(
      last_evaluation,
      sub(mul(product_eval_1, product_eval_1), product_eval_1),
    )
  let lookup_left_1 =
    mul(
      mul(product_next_eval_1, add(permuted_input_eval_1, beta)),
      add(permuted_table_eval_1, gamma),
    )
  let lookup_right_1 =
    mul(
      mul(product_eval_1, add(lookup_input_eq1, beta)),
      add(lookup_table_eq, gamma),
    )
  let lookup_expression_3_1 =
    mul(sub(lookup_left_1, lookup_right_1), active_rows)
  let lookup_expression_4_1 =
    mul(evaluation_at_0, sub(permuted_input_eval_1, permuted_table_eval_1))
  let lookup_expression_5_1 =
    mul(
      mul(
        sub(permuted_input_eval_1, permuted_table_eval_1),
        sub(permuted_input_eval_1, permuted_input_inv_eval_1),
      ),
      active_rows,
    )

  let lookup_expression_1_2 =
    mul(evaluation_at_0, sub(scalarOne, product_eval_2))
  let lookup_expression_2_2 =
    mul(
      last_evaluation,
      sub(mul(product_eval_2, product_eval_2), product_eval_2),
    )
  let lookup_left_2 =
    mul(
      mul(product_next_eval_2, add(permuted_input_eval_2, beta)),
      add(permuted_table_eval_2, gamma),
    )
  let lookup_right_2 =
    mul(
      mul(product_eval_2, add(lookup_input_eq2, beta)),
      add(lookup_table_eq, gamma),
    )
  let lookup_expression_3_2 =
    mul(sub(lookup_left_2, lookup_right_2), active_rows)
  let lookup_expression_4_2 =
    mul(evaluation_at_0, sub(permuted_input_eval_2, permuted_table_eval_2))
  let lookup_expression_5_2 =
    mul(
      mul(
        sub(permuted_input_eval_2, permuted_table_eval_2),
        sub(permuted_input_eval_2, permuted_input_inv_eval_2),
      ),
      active_rows,
    )

  let trash_expression_1 =
    add(
      add(
        mul(
          add(
            mul(
              add(
                mul(
                  add(
                    mul(
                      add(
                        mul(
                          add(
                            mul(
                              add(
                                mul(
                                  add(
                                    mul(from_int(0x0), trash_challenge),
                                    add(
                                      add(fixed_eval_7, neg(advice_eval_6)),
                                      add(
                                        add(
                                          add(
                                            add(
                                              add(
                                                add(
                                                  add(
                                                    mul(
                                                      from_int(
                                                        0x590ba402032e82eb1f660ef09796c5686345a5054ed96dae8e2d233633788771,
                                                      ),
                                                      advice_eval_1,
                                                    ),
                                                    mul(
                                                      from_int(
                                                        0x52f789e4afc3801f7411102ee2f47cc5954a744e71cac98e75ea962a55a0a76f,
                                                      ),
                                                      advice_eval_2,
                                                    ),
                                                  ),
                                                  scaled_quintic(
                                                    from_int(
                                                      0x3509dd2fe3aac0080783557fec090fb1cb4b2b0901253c55282024331d1fe1a8,
                                                    ),
                                                    advice_eval_3,
                                                  ),
                                                ),
                                                scaled_quintic(
                                                  from_int(
                                                    0x333f8046ece5579cbd6872449c57f2703dfc8864cfadc06d587ff104a0d0c1f2,
                                                  ),
                                                  advice_eval_4,
                                                ),
                                              ),
                                              scaled_quintic(
                                                from_int(
                                                  0x412c98232b6ab8a47aa76ee814ef7ec6261987c9802f2cfc490e007951a60ca5,
                                                ),
                                                advice_eval_5,
                                              ),
                                            ),
                                            scaled_quintic(
                                              from_int(
                                                0x53fded36d490ba6b05a5d10fd99ffe5456baec6a6a8753199d5ebdc33c99790e,
                                              ),
                                              advice_eval_9,
                                            ),
                                          ),
                                          scaled_quintic(
                                            from_int(
                                              0x6ccb1c7d87f3c12a2bde4e68ac7f1e8b03481ba15d7f88f9a7f9b8310dd6d34,
                                            ),
                                            advice_eval_10,
                                          ),
                                        ),
                                        scaled_quintic(
                                          from_int(
                                            0x3f05c4df7a6664dabe258779bf548eb4007f33601591080b3ecd34aea0e1edc1,
                                          ),
                                          advice_eval_11,
                                        ),
                                      ),
                                    ),
                                  ),
                                  trash_challenge,
                                ),
                                add(
                                  add(fixed_eval_8, neg(advice_eval_7)),
                                  add(
                                    add(
                                      add(
                                        add(
                                          add(
                                            add(
                                              add(
                                                mul(
                                                  from_int(
                                                    0x5b1fc262a28cbb8bf75d9b1a6edaa74591ec24cd9a209512213cec3a3c0f1a5d,
                                                  ),
                                                  advice_eval_1,
                                                ),
                                                mul(
                                                  from_int(
                                                    0x4d0ea7f9c3fda06d9535b0fdafd8338bd47c2200b284fa71a325ff41ac358028,
                                                  ),
                                                  advice_eval_2,
                                                ),
                                              ),
                                              scaled_quintic(
                                                from_int(
                                                  0x26cc223e16f47c20e17cc6069605fa5a8af05ea4f6eb36029a641d23b818eb10,
                                                ),
                                                advice_eval_3,
                                              ),
                                            ),
                                            scaled_quintic(
                                              from_int(
                                                0x31e823a45e567484c1544e310c0fa5cd66547a8f0dde659ac61698c30e838d25,
                                              ),
                                              advice_eval_4,
                                            ),
                                          ),
                                          scaled_quintic(
                                            from_int(
                                              0x275a20361ea91992193920270d3e2d1f6361880ac0a439c64bef815d4469ba85,
                                            ),
                                            advice_eval_5,
                                          ),
                                        ),
                                        scaled_quintic(
                                          from_int(
                                            0x5f3a15bab4ce4097b1edc3a25002694b92395ce355a8a12fe557459d9633f701,
                                          ),
                                          advice_eval_9,
                                        ),
                                      ),
                                      scaled_quintic(
                                        from_int(
                                          0x301cf56f9b4577112cc4241cddf6484aaadedbf1bbd0f2351adf2e41c2fb2ecd,
                                        ),
                                        advice_eval_10,
                                      ),
                                    ),
                                    scaled_quintic(
                                      from_int(
                                        0xfdf664da55059fa5a9388c641035d496d0bb519834348b4e2a8fc8c637f1a1f,
                                      ),
                                      advice_eval_11,
                                    ),
                                  ),
                                ),
                              ),
                              trash_challenge,
                            ),
                            add(
                              add(fixed_eval_9, neg(advice_eval_4)),
                              add(
                                add(
                                  mul(
                                    from_int(
                                      0x5e1d3dbecda6214343e24a47f45c5d033197ad01b65a730af95dc57e90c49140,
                                    ),
                                    advice_eval_1,
                                  ),
                                  mul(
                                    from_int(
                                      0x6bd72f9cfc53af9d931896e77ea5c61244cb6d5fae8954f37dc7b9002f5aa78a,
                                    ),
                                    advice_eval_2,
                                  ),
                                ),
                                scaled_quintic(
                                  from_int(
                                    0x4997c5aa3a5fa07bcaf880a9054bef831effbd9cd58e46d9bb4fb88ef99de0db,
                                  ),
                                  advice_eval_3,
                                ),
                              ),
                            ),
                          ),
                          trash_challenge,
                        ),
                        add(
                          add(fixed_eval_10, neg(advice_eval_5)),
                          add(
                            add(
                              add(
                                mul(
                                  from_int(
                                    0x222e83e70453dfee19b402e9fa8dfe2c4987b034d0be3ceb478b3022e97934c1,
                                  ),
                                  advice_eval_1,
                                ),
                                mul(
                                  from_int(
                                    0x26c2cc87f95726b28f33ca03409a460ec987cfe12adae32769e3565865d07191,
                                  ),
                                  advice_eval_2,
                                ),
                              ),
                              scaled_quintic(
                                from_int(
                                  0x4382d0938a760120dd6cef8f3b90a0c38abae475e3d21e39365472b76d780272,
                                ),
                                advice_eval_3,
                              ),
                            ),
                            scaled_quintic(
                              from_int(
                                0x4997c5aa3a5fa07bcaf880a9054bef831effbd9cd58e46d9bb4fb88ef99de0db,
                              ),
                              advice_eval_4,
                            ),
                          ),
                        ),
                      ),
                      trash_challenge,
                    ),
                    add(
                      add(fixed_eval_2, neg(advice_eval_9)),
                      add(
                        add(
                          add(
                            add(
                              mul(
                                from_int(
                                  0x726df1506749848155630b86ae25a82b281ecd050fe3a52d85a181fa87202e4b,
                                ),
                                advice_eval_1,
                              ),
                              mul(
                                from_int(
                                  0x24822e1af9aa2887c912c87eb0f20bd332330e7e55cd784de67cb407a9f05520,
                                ),
                                advice_eval_2,
                              ),
                            ),
                            scaled_quintic(
                              from_int(
                                0x4e5280109d8f96b8bfb543a6b1af25fb56a9db616af85a90eedc558e3eb1ea29,
                              ),
                              advice_eval_3,
                            ),
                          ),
                          scaled_quintic(
                            from_int(
                              0x4382d0938a760120dd6cef8f3b90a0c38abae475e3d21e39365472b76d780272,
                            ),
                            advice_eval_4,
                          ),
                        ),
                        scaled_quintic(
                          from_int(
                            0x4997c5aa3a5fa07bcaf880a9054bef831effbd9cd58e46d9bb4fb88ef99de0db,
                          ),
                          advice_eval_5,
                        ),
                      ),
                    ),
                  ),
                  trash_challenge,
                ),
                add(
                  add(fixed_eval_3, neg(advice_eval_10)),
                  add(
                    add(
                      add(
                        add(
                          add(
                            mul(
                              from_int(
                                0x2f5908b169c6cf1bd26dcf0f9e5105481f5164f3ece0582bf3098312167751a7,
                              ),
                              advice_eval_1,
                            ),
                            mul(
                              from_int(
                                0x23a6684b942d726a22e4d5b8d8ff83aeaa773f62600184efe5d033d7c7c6e827,
                              ),
                              advice_eval_2,
                            ),
                          ),
                          scaled_quintic(
                            from_int(
                              0x1981b4b33d6a9dab957b351d981d3323e65da39493af5bc01f7e8ffe17f98d4e,
                            ),
                            advice_eval_3,
                          ),
                        ),
                        scaled_quintic(
                          from_int(
                            0x4e5280109d8f96b8bfb543a6b1af25fb56a9db616af85a90eedc558e3eb1ea29,
                          ),
                          advice_eval_4,
                        ),
                      ),
                      scaled_quintic(
                        from_int(
                          0x4382d0938a760120dd6cef8f3b90a0c38abae475e3d21e39365472b76d780272,
                        ),
                        advice_eval_5,
                      ),
                    ),
                    mul(
                      from_int(
                        0x4997c5aa3a5fa07bcaf880a9054bef831effbd9cd58e46d9bb4fb88ef99de0db,
                      ),
                      mul(
                        advice_eval_9,
                        mul(
                          mul(advice_eval_9, advice_eval_9),
                          mul(advice_eval_9, advice_eval_9),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              trash_challenge,
            ),
            add(
              add(fixed_eval_4, neg(advice_eval_11)),
              add(
                add(
                  add(
                    add(
                      add(
                        add(
                          mul(
                            from_int(
                              0x6d05a41959f539a7fc9ec0972ea1e3dbb6fc67dd51daf3414f7fbbb091c7274a,
                            ),
                            advice_eval_1,
                          ),
                          mul(
                            from_int(
                              0x27e7119226c42a6d19c1541904b99ae40685511ed2e078964b74594d38340849,
                            ),
                            advice_eval_2,
                          ),
                        ),
                        scaled_quintic(
                          from_int(
                            0xd94c46a8456352aa44d7a885ab59e3a36664e6fb25e826f8a4cd79822f0533,
                          ),
                          advice_eval_3,
                        ),
                      ),
                      scaled_quintic(
                        from_int(
                          0x1981b4b33d6a9dab957b351d981d3323e65da39493af5bc01f7e8ffe17f98d4e,
                        ),
                        advice_eval_4,
                      ),
                    ),
                    scaled_quintic(
                      from_int(
                        0x4e5280109d8f96b8bfb543a6b1af25fb56a9db616af85a90eedc558e3eb1ea29,
                      ),
                      advice_eval_5,
                    ),
                  ),
                  scaled_quintic(
                    from_int(
                      0x4382d0938a760120dd6cef8f3b90a0c38abae475e3d21e39365472b76d780272,
                    ),
                    advice_eval_9,
                  ),
                ),
                scaled_quintic(
                  from_int(
                    0x4997c5aa3a5fa07bcaf880a9054bef831effbd9cd58e46d9bb4fb88ef99de0db,
                  ),
                  advice_eval_10,
                ),
              ),
            ),
          ),
          trash_challenge,
        ),
        add(
          add(fixed_eval_5, neg(advice_eval_8)),
          add(
            add(
              add(
                add(
                  add(
                    add(
                      add(
                        mul(
                          from_int(
                            0x70d8f2a733a64d650faccc9b1c2a766a9544bb3ff1a11ee73cb43947ef386633,
                          ),
                          advice_eval_1,
                        ),
                        mul(
                          from_int(
                            0x40fa389feb2522bb934881ac9ed749aee2296502af592418c6b5675c0f560261,
                          ),
                          advice_eval_2,
                        ),
                      ),
                      scaled_quintic(
                        from_int(
                          0x1f61345b652161410c5e29f51e301ae56342af824bc110649393d2b911c50d3e,
                        ),
                        advice_eval_3,
                      ),
                    ),
                    scaled_quintic(
                      from_int(
                        0xd94c46a8456352aa44d7a885ab59e3a36664e6fb25e826f8a4cd79822f0533,
                      ),
                      advice_eval_4,
                    ),
                  ),
                  scaled_quintic(
                    from_int(
                      0x1981b4b33d6a9dab957b351d981d3323e65da39493af5bc01f7e8ffe17f98d4e,
                    ),
                    advice_eval_5,
                  ),
                ),
                scaled_quintic(
                  from_int(
                    0x4e5280109d8f96b8bfb543a6b1af25fb56a9db616af85a90eedc558e3eb1ea29,
                  ),
                  advice_eval_9,
                ),
              ),
              scaled_quintic(
                from_int(
                  0x4382d0938a760120dd6cef8f3b90a0c38abae475e3d21e39365472b76d780272,
                ),
                advice_eval_10,
              ),
            ),
            scaled_quintic(
              from_int(
                0x4997c5aa3a5fa07bcaf880a9054bef831effbd9cd58e46d9bb4fb88ef99de0db,
              ),
              advice_eval_11,
            ),
          ),
        ),
      ),
      neg(mul(add(scalarOne, neg(fixed_eval_22)), trash_eval_1)),
    )

  let term_1 =
    mul(evaluation_at_0, add(scalarOne, neg(permutations_evaluated_a_1)))
  let term_2 =
    mul(
      last_evaluation,
      add(
        mul(permutations_evaluated_d_1, permutations_evaluated_d_1),
        neg(permutations_evaluated_d_1),
      ),
    )
  let term_3 =
    mul(
      add(permutations_evaluated_b_1, neg(permutations_evaluated_a_3)),
      evaluation_at_0,
    )
  let term_4 =
    mul(
      add(permutations_evaluated_c_1, neg(permutations_evaluated_b_3)),
      evaluation_at_0,
    )
  let term_5 =
    mul(
      add(permutations_evaluated_d_1, neg(permutations_evaluated_c_3)),
      evaluation_at_0,
    )

  let left1 = add(add(fixed_eval_1, mul(beta, permutation_common_1)), gamma)
  //part of set a
  let left2 = add(add(advice_eval_1, mul(beta, permutation_common_2)), gamma)
  //part of set a
  let left3 = add(add(advice_eval_2, mul(beta, permutation_common_3)), gamma)
  //part of set a
  let left4 = add(add(advice_eval_3, mul(beta, permutation_common_4)), gamma)
  //part of set b
  let left5 = add(add(advice_eval_4, mul(beta, permutation_common_5)), gamma)
  //part of set b
  let left6 = add(add(advice_eval_5, mul(beta, permutation_common_6)), gamma)
  //part of set b
  let left7 = add(add(instance_eval_1, mul(beta, permutation_common_7)), gamma)
  //part of set c
  let left8 = add(add(instance_eval_2, mul(beta, permutation_common_8)), gamma)
  //part of set c
  let left9 = add(add(advice_eval_9, mul(beta, permutation_common_9)), gamma)
  //part of set c
  let left10 = add(add(advice_eval_10, mul(beta, permutation_common_10)), gamma)

  //part of set d
  let left_set1 = mul(permutations_evaluated_a_2, mul(mul(left1, left2), left3))
  let left_set2 = mul(permutations_evaluated_b_2, mul(mul(left4, left5), left6))
  let left_set3 = mul(permutations_evaluated_c_2, mul(mul(left7, left8), left9))
  let left_set4 = mul(permutations_evaluated_d_2, left10)

  let right1 =
    add(add(fixed_eval_1, mul(mul(beta, x), scale(scalarDelta, 0))), gamma)
  //part of set a
  let right2 =
    add(add(advice_eval_1, mul(mul(beta, x), scale(scalarDelta, 1))), gamma)
  //part of set a
  let right3 =
    add(add(advice_eval_2, mul(mul(beta, x), scale(scalarDelta, 2))), gamma)
  //part of set a
  let right4 =
    add(add(advice_eval_3, mul(mul(beta, x), scale(scalarDelta, 3))), gamma)
  //part of set b
  let right5 =
    add(add(advice_eval_4, mul(mul(beta, x), scale(scalarDelta, 4))), gamma)
  //part of set b
  let right6 =
    add(add(advice_eval_5, mul(mul(beta, x), scale(scalarDelta, 5))), gamma)
  //part of set b
  let right7 =
    add(add(instance_eval_1, mul(mul(beta, x), scale(scalarDelta, 6))), gamma)
  //part of set c
  let right8 =
    add(add(instance_eval_2, mul(mul(beta, x), scale(scalarDelta, 7))), gamma)
  //part of set c
  let right9 =
    add(add(advice_eval_9, mul(mul(beta, x), scale(scalarDelta, 8))), gamma)
  //part of set c
  let right10 =
    add(add(advice_eval_10, mul(mul(beta, x), scale(scalarDelta, 9))), gamma)

  //part of set d
  let right_set1 =
    mul(permutations_evaluated_a_1, mul(mul(right1, right2), right3))
  let right_set2 =
    mul(permutations_evaluated_b_1, mul(mul(right4, right5), right6))
  let right_set3 =
    mul(permutations_evaluated_c_1, mul(mul(right7, right8), right9))
  let right_set4 = mul(permutations_evaluated_d_1, right10)

  let permutations1 =
    mul(
      sub(left_set1, right_set1),
      sub(
        scalarOne,
        add(last_evaluation, sum_of_evaluation_for_blinding_factors),
      ),
    )
  let permutations2 =
    mul(
      sub(left_set2, right_set2),
      sub(
        scalarOne,
        add(last_evaluation, sum_of_evaluation_for_blinding_factors),
      ),
    )
  let permutations3 =
    mul(
      sub(left_set3, right_set3),
      sub(
        scalarOne,
        add(last_evaluation, sum_of_evaluation_for_blinding_factors),
      ),
    )
  let permutations4 =
    mul(
      sub(left_set4, right_set4),
      sub(
        scalarOne,
        add(last_evaluation, sum_of_evaluation_for_blinding_factors),
      ),
    )

  //      expressions for vanishing polynomial
  let expression1 = gate_eq1
  let expression2 = gate_eq2
  let expression3 = gate_eq3
  let expression4 = gate_eq4
  let expression5 = gate_eq5
  let expression6 = gate_eq6
  let expression7 = gate_eq7
  let expression8 = gate_eq8
  let expression9 = gate_eq9
  let expression10 = gate_eq10
  let expression11 = gate_eq11
  let expression12 = gate_eq12
  let expression13 = gate_eq13
  let expression14 = gate_eq14
  let expression15 = gate_eq15
  let expression16 = gate_eq16
  let expression17 = gate_eq17
  let expression18 = gate_eq18
  let expression19 = term_1
  let expression20 = term_2
  let expression21 = term_3
  let expression22 = term_4
  let expression23 = term_5
  let expression24 = permutations1
  let expression25 = permutations2
  let expression26 = permutations3
  let expression27 = permutations4
  let expression28 = lookup_expression_1_1
  let expression29 = lookup_expression_2_1
  let expression30 = lookup_expression_3_1
  let expression31 = lookup_expression_4_1
  let expression32 = lookup_expression_5_1
  let expression33 = lookup_expression_1_2
  let expression34 = lookup_expression_2_2
  let expression35 = lookup_expression_3_2
  let expression36 = lookup_expression_4_2
  let expression37 = lookup_expression_5_2
  let expression38 = trash_expression_1

  let hEval =
    add(
      mul(
        add(
          mul(
            add(
              mul(
                add(
                  mul(
                    add(
                      mul(
                        add(
                          mul(
                            add(
                              mul(
                                add(
                                  mul(
                                    add(
                                      mul(
                                        add(
                                          mul(
                                            add(
                                              mul(
                                                add(
                                                  mul(
                                                    add(
                                                      mul(
                                                        add(
                                                          mul(
                                                            add(
                                                              mul(
                                                                add(
                                                                  mul(
                                                                    add(
                                                                      mul(
                                                                        add(
                                                                          mul(
                                                                            add(
                                                                              mul(
                                                                                add(
                                                                                  mul(
                                                                                    add(
                                                                                      mul(
                                                                                        add(
                                                                                          mul(
                                                                                            add(
                                                                                              mul(
                                                                                                add(
                                                                                                  mul(
                                                                                                    add(
                                                                                                      mul(
                                                                                                        add(
                                                                                                          mul(
                                                                                                            add(
                                                                                                              mul(
                                                                                                                add(
                                                                                                                  mul(
                                                                                                                    add(
                                                                                                                      mul(
                                                                                                                        add(
                                                                                                                          mul(
                                                                                                                            add(
                                                                                                                              mul(
                                                                                                                                add(
                                                                                                                                  mul(
                                                                                                                                    add(
                                                                                                                                      mul(
                                                                                                                                        add(
                                                                                                                                          mul(
                                                                                                                                            add(
                                                                                                                                              mul(
                                                                                                                                                add(
                                                                                                                                                  mul(
                                                                                                                                                    add(
                                                                                                                                                      mul(
                                                                                                                                                        expression1,
                                                                                                                                                        y,
                                                                                                                                                      ),
                                                                                                                                                      expression2,
                                                                                                                                                    ),
                                                                                                                                                    y,
                                                                                                                                                  ),
                                                                                                                                                  expression3,
                                                                                                                                                ),
                                                                                                                                                y,
                                                                                                                                              ),
                                                                                                                                              expression4,
                                                                                                                                            ),
                                                                                                                                            y,
                                                                                                                                          ),
                                                                                                                                          expression5,
                                                                                                                                        ),
                                                                                                                                        y,
                                                                                                                                      ),
                                                                                                                                      expression6,
                                                                                                                                    ),
                                                                                                                                    y,
                                                                                                                                  ),
                                                                                                                                  expression7,
                                                                                                                                ),
                                                                                                                                y,
                                                                                                                              ),
                                                                                                                              expression8,
                                                                                                                            ),
                                                                                                                            y,
                                                                                                                          ),
                                                                                                                          expression9,
                                                                                                                        ),
                                                                                                                        y,
                                                                                                                      ),
                                                                                                                      expression10,
                                                                                                                    ),
                                                                                                                    y,
                                                                                                                  ),
                                                                                                                  expression11,
                                                                                                                ),
                                                                                                                y,
                                                                                                              ),
                                                                                                              expression12,
                                                                                                            ),
                                                                                                            y,
                                                                                                          ),
                                                                                                          expression13,
                                                                                                        ),
                                                                                                        y,
                                                                                                      ),
                                                                                                      expression14,
                                                                                                    ),
                                                                                                    y,
                                                                                                  ),
                                                                                                  expression15,
                                                                                                ),
                                                                                                y,
                                                                                              ),
                                                                                              expression16,
                                                                                            ),
                                                                                            y,
                                                                                          ),
                                                                                          expression17,
                                                                                        ),
                                                                                        y,
                                                                                      ),
                                                                                      expression18,
                                                                                    ),
                                                                                    y,
                                                                                  ),
                                                                                  expression19,
                                                                                ),
                                                                                y,
                                                                              ),
                                                                              expression20,
                                                                            ),
                                                                            y,
                                                                          ),
                                                                          expression21,
                                                                        ),
                                                                        y,
                                                                      ),
                                                                      expression22,
                                                                    ),
                                                                    y,
                                                                  ),
                                                                  expression23,
                                                                ),
                                                                y,
                                                              ),
                                                              expression24,
                                                            ),
                                                            y,
                                                          ),
                                                          expression25,
                                                        ),
                                                        y,
                                                      ),
                                                      expression26,
                                                    ),
                                                    y,
                                                  ),
                                                  expression27,
                                                ),
                                                y,
                                              ),
                                              expression28,
                                            ),
                                            y,
                                          ),
                                          expression29,
                                        ),
                                        y,
                                      ),
                                      expression30,
                                    ),
                                    y,
                                  ),
                                  expression31,
                                ),
                                y,
                              ),
                              expression32,
                            ),
                            y,
                          ),
                          expression33,
                        ),
                        y,
                      ),
                      expression34,
                    ),
                    y,
                  ),
                  expression35,
                ),
                y,
              ),
              expression36,
            ),
            y,
          ),
          expression37,
        ),
        y,
      ),
      expression38,
    )

  let inverted = recip_eea(sub(xn, scalarOne))
  // recip is inverse of the number mod bls12_381_field_prime
  let vanishing_s = mul(hEval, inverted)

  // vanishing split IS PASSED IN REVERSE ORDER!!!
  // this is MSM done for h-commitments
  let hCommitment1 = vanishing_split_4
  let hCommitment2 = addG1(scaleG1(hCommitment1, x_chop), vanishing_split_3)
  let hCommitment3 = addG1(scaleG1(hCommitment2, x_chop), vanishing_split_2)
  let vanishing_g = addG1(scaleG1(hCommitment3, x_chop), vanishing_split_1)

  let vanishing_g = compress(vanishing_g)

  // commitment_data stores compressed points
  let commitment_data =
    [
      [
        (f15_commitment, [instance_eval_1]), (a4, [advice_eval_4]),
        (a5, [advice_eval_5]), (a6, [advice_eval_9]), (a7, [advice_eval_10]),
        (a8, [advice_eval_11]), (a9, [advice_eval_12]),
        (permuted_table_1, [permuted_table_eval_1]),
        (permuted_table_2, [permuted_table_eval_2]),
        (trash_commitment_1, [trash_eval_1]), (f10_commitment, [fixed_eval_1]),
        (f5_commitment, [fixed_eval_2]), (f6_commitment, [fixed_eval_3]),
        (f7_commitment, [fixed_eval_4]), (f8_commitment, [fixed_eval_5]),
        (f9_commitment, [fixed_eval_6]), (f1_commitment, [fixed_eval_7]),
        (f2_commitment, [fixed_eval_8]), (f3_commitment, [fixed_eval_9]),
        (f4_commitment, [fixed_eval_10]), (f11_commitment, [fixed_eval_11]),
        (f12_commitment, [fixed_eval_12]), (f13_commitment, [fixed_eval_13]),
        (f14_commitment, [fixed_eval_14]), (f15_commitment, [fixed_eval_15]),
        (f16_commitment, [fixed_eval_16]), (f17_commitment, [fixed_eval_17]),
        (f18_commitment, [fixed_eval_18]), (f19_commitment, [fixed_eval_19]),
        (f20_commitment, [fixed_eval_20]), (f21_commitment, [fixed_eval_21]),
        (f22_commitment, [fixed_eval_22]),
        (p1_commitment, [permutation_common_1]),
        (p2_commitment, [permutation_common_2]),
        (p3_commitment, [permutation_common_3]),
        (p4_commitment, [permutation_common_4]),
        (p5_commitment, [permutation_common_5]),
        (p6_commitment, [permutation_common_6]),
        (p7_commitment, [permutation_common_7]),
        (p8_commitment, [permutation_common_8]),
        (p9_commitment, [permutation_common_9]),
        (p10_commitment, [permutation_common_10]), (vanishing_g, [vanishing_s]),
        (vanishing_rand, [random_eval]),
      ],
      [
        (a1, [advice_eval_1, advice_eval_6]),
        (a2, [advice_eval_2, advice_eval_7]),
        (a3, [advice_eval_3, advice_eval_8]),
        (
          permutations_committed_d,
          [permutations_evaluated_d_1, permutations_evaluated_d_2],
        ), (lookup_commitment_1, [product_eval_1, product_next_eval_1]),
        (lookup_commitment_2, [product_eval_2, product_next_eval_2]),
      ],
      [
        (
          permutations_committed_a,
          [
            permutations_evaluated_a_1, permutations_evaluated_a_2,
            permutations_evaluated_a_3,
          ],
        ),
        (
          permutations_committed_b,
          [
            permutations_evaluated_b_1, permutations_evaluated_b_2,
            permutations_evaluated_b_3,
          ],
        ),
        (
          permutations_committed_c,
          [
            permutations_evaluated_c_1, permutations_evaluated_c_2,
            permutations_evaluated_c_3,
          ],
        ),
      ],
      [
        (permuted_input_1, [permuted_input_eval_1, permuted_input_inv_eval_1]),
        (permuted_input_2, [permuted_input_eval_2, permuted_input_inv_eval_2]),
      ],
    ]

  // ── Phase 1 specific: prefix accumulator + v + datum ──────────────
  let x1Powers = powers(44, x1)
  let x4Powers = powers(5, x4)

  // Prefix G1 accumulator: first 17 entries of set 0
  // (split rebalanced from 23 to 17 to equalize TX1/TX2 cost)
  expect [set_0, ..] = commitment_data
  let rhs_prefix_g1 = accumulate_g1_prefix(x1Powers, set_0, 17)
  let rhs_prefix = compress(rhs_prefix_g1)

  // Compute q_eval for each rotation set
  let evals_1 = compute_q_eval_for_set(0, x1Powers, commitment_data)
  let term_1 = q_eval_term([x_current], evals_1, q_eval_on_x3_1, x3)
  let evals_2 = compute_q_eval_for_set(1, x1Powers, commitment_data)
  let term_2 = q_eval_term([x_current, x_next], evals_2, q_eval_on_x3_2, x3)
  let evals_3 = compute_q_eval_for_set(2, x1Powers, commitment_data)
  let term_3 =
    q_eval_term([x_current, x_next, x_last], evals_3, q_eval_on_x3_3, x3)
  let evals_4 = compute_q_eval_for_set(3, x1Powers, commitment_data)
  let term_4 = q_eval_term([x_current, x_prev], evals_4, q_eval_on_x3_4, x3)
  let f_eval =
    add(mul(add(mul(add(mul(term_4, x2), term_3), x2), term_2), x2), term_1)
  let v =
    compute_v(
      f_eval,
      x4Powers,
      [q_eval_on_x3_1, q_eval_on_x3_2, q_eval_on_x3_3, q_eval_on_x3_4],
    )

  let reduced_hash =
    blake2b_256(
      serialize_reduced_redeemer_fields(
        vanishing_g,
        vanishing_rand,
        a1,
        a2,
        a3,
        permutations_committed_d,
        lookup_commitment_1,
        lookup_commitment_2,
        permutations_committed_a,
        permutations_committed_b,
        permutations_committed_c,
        permuted_input_1,
        permuted_input_2,
        f_commitment,
        pi_term,
      ),
    )

  Phase1State {
    rhs_prefix,
    reduced_hash,
    x1: to_bytes_little_endian(x1),
    x3: to_bytes_little_endian(x3),
    x4: to_bytes_little_endian(x4),
    v: to_bytes_little_endian(v),
  }
}

test phase1_vanishing_lagrange_terms_matches_generic_basis() {
  let x =
    from_int(0x27267acdcdde9716fe9323b98bc0930dd54e5dc1f0b5c59dfcdd83f92eb5f2e4)
  let xn =
    from_int(0x704a1af8e8913f64ae2432b58446ec9a9a591f7ddce6fef2461e745176248f64)
  let rotations = rotate_omegas(omega, omega_inv, -(blinding_factors + 1), 0)
  let evaluations =
    lagrange_polynomial_basis(x, xn, barycentric_weight, rotations)
  expect [last_evaluation, ..rest] = evaluations
  let evaluation_for_blinding_factors = take(rest, blinding_factors)
  expect Some(evaluation_at_0) = last(rest)
  let sum_of_evaluation_for_blinding_factors =
    foldl(
      evaluation_for_blinding_factors,
      from_int(0),
      fn(e, acc) { add(e, acc) },
    )

  let optimized = phase1_vanishing_lagrange_terms(x, xn)

  expect optimized.last_evaluation == last_evaluation
  expect optimized.evaluation_at_0 == evaluation_at_0
  expect
    optimized.sum_of_evaluation_for_blinding_factors == sum_of_evaluation_for_blinding_factors
}

test phase1_instance_eval_2_matches_generic_basis() {
  let x =
    from_int(0x27267acdcdde9716fe9323b98bc0930dd54e5dc1f0b5c59dfcdd83f92eb5f2e4)
  let xn =
    from_int(0x704a1af8e8913f64ae2432b58446ec9a9a591f7ddce6fef2461e745176248f64)
  let i_1 =
    from_int(0x18f6d4dba2f0f7f1d68be54e77fb1cb0fa41d0d79d9c52d23d90f06a4121a17c)
  let i_2 =
    from_int(0x2f56b71b69226cc2c7bcc3c7784bb3e2b1fa7f57ac4c65451ed3c0a6921e0f84)
  let generic =
    inner_product(
      lagrange_polynomial_basis(
        x,
        xn,
        barycentric_weight,
        rotate_omegas(omega, omega_inv, 0, 2),
      ),
      [i_1, i_2],
    )

  expect phase1_instance_eval_2(x, xn, i_1, i_2) == generic
}
