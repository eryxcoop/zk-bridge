// Split-specific helpers for the two-phase Halo2 Multi-Open verifier.
//
// These functions complement halo2_kzg.ak with partial-accumulator
// construction and reduced-redeemer serialisation.

use aiken/crypto/bitwise.{State}
use aiken/crypto/bls12_381/g1.{add as add_g1, decompress, scale, zero}
use aiken/crypto/bls12_381/scalar.{Scalar}
use aiken/primitive/bytearray
use two_phase/two_phase_types.{ReducedRedeemer}

/// Compute the G1 accumulator for a list of (commitment, evals) entries
/// weighted by x1 powers.  This is the inner loop of
/// `compute_final_comm_without_f` restricted to a single point-set slice.
pub fn accumulate_g1(
  x1_powers: List<State<Scalar>>,
  entries: List<(ByteArray, List<State<Scalar>>)>,
) -> G1Element {
  accumulate_g1_inner(x1_powers, entries, zero)
}

pub fn accumulate_g1_prefix(
  x1_powers: List<State<Scalar>>,
  entries: List<(ByteArray, List<State<Scalar>>)>,
  remaining: Int,
) -> G1Element {
  accumulate_g1_prefix_inner(x1_powers, entries, remaining, zero)
}

fn accumulate_g1_inner(
  x1_powers: List<State<Scalar>>,
  entries: List<(ByteArray, List<State<Scalar>>)>,
  acc: G1Element,
) -> G1Element {
  when x1_powers is {
    [x1_power, ..rest_powers] ->
      when entries is {
        [(commitment, _), ..rest_entries] ->
          accumulate_g1_inner(
            rest_powers,
            rest_entries,
            add_g1(acc, scale(decompress(commitment), x1_power)),
          )
        _ -> acc
      }
    _ -> acc
  }
}

fn accumulate_g1_prefix_inner(
  x1_powers: List<State<Scalar>>,
  entries: List<(ByteArray, List<State<Scalar>>)>,
  remaining: Int,
  acc: G1Element,
) -> G1Element {
  if remaining <= 0 {
    acc
  } else {
    when x1_powers is {
      [x1_power, ..rest_powers] ->
        when entries is {
          [(commitment, _), ..rest_entries] ->
            accumulate_g1_prefix_inner(
              rest_powers,
              rest_entries,
              remaining - 1,
              add_g1(acc, scale(decompress(commitment), x1_power)),
            )
          _ -> acc
        }
      _ -> acc
    }
  }
}

/// Canonical serialisation of a ReducedRedeemer for hash binding.
/// All 15 fields are concatenated in declaration order.
fn concat_pair(left: ByteArray, right: ByteArray) -> ByteArray {
  bytearray.concat(left, right)
}

fn concat_quartet(
  a: ByteArray,
  b: ByteArray,
  c: ByteArray,
  d: ByteArray,
) -> ByteArray {
  concat_pair(concat_pair(a, b), concat_pair(c, d))
}

pub fn serialize_reduced_redeemer_fields(
  vanishing_g: ByteArray,
  vanishing_rand: ByteArray,
  a1: ByteArray,
  a2: ByteArray,
  a3: ByteArray,
  perm_d: ByteArray,
  lookup_1: ByteArray,
  lookup_2: ByteArray,
  perm_a: ByteArray,
  perm_b: ByteArray,
  perm_c: ByteArray,
  perm_input_1: ByteArray,
  perm_input_2: ByteArray,
  f_commitment: ByteArray,
  pi_term: ByteArray,
) -> ByteArray {
  let chunk_1 = concat_quartet(vanishing_g, vanishing_rand, a1, a2)
  let chunk_2 = concat_quartet(a3, perm_d, lookup_1, lookup_2)
  let chunk_3 = concat_quartet(perm_a, perm_b, perm_c, perm_input_1)
  let chunk_4 = concat_pair(concat_pair(perm_input_2, f_commitment), pi_term)
  concat_pair(concat_pair(chunk_1, chunk_2), concat_pair(chunk_3, chunk_4))
}

pub fn serialize_reduced_redeemer(r: ReducedRedeemer) -> ByteArray {
  serialize_reduced_redeemer_fields(
    r.vanishing_g,
    r.vanishing_rand,
    r.a1,
    r.a2,
    r.a3,
    r.perm_d,
    r.lookup_1,
    r.lookup_2,
    r.perm_a,
    r.perm_b,
    r.perm_c,
    r.perm_input_1,
    r.perm_input_2,
    r.f_commitment,
    r.pi_term,
  )
}
