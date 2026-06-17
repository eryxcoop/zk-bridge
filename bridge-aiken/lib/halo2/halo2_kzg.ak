use aiken/collection/list.{foldl, last, zip}
use aiken/crypto/bitwise.{State}
use aiken/crypto/bls12_381/g1.{add as add_g1, decompress, scale, zero}
use aiken/crypto/bls12_381/scalar.{Scalar, add, from_int, mul}

fn nth_commitment_set(
  set_index: Int,
  commitment_map: List<List<(ByteArray, List<State<Scalar>>)>>,
) -> List<(ByteArray, List<State<Scalar>>)> {
  when commitment_map is {
    [set, ..rest] ->
      if set_index == 0 {
        set
      } else {
        nth_commitment_set(set_index - 1, rest)
      }
    [] -> []
  }
}

pub fn compute_q_eval_for_set(
  set_index: Int,
  x1_powers: List<State<Scalar>>,
  commitment_map: List<List<(ByteArray, List<State<Scalar>>)>>,
) -> List<State<Scalar>> {
  let selected_set = nth_commitment_set(set_index, commitment_map)

  compute_q_eval_for_entries(x1_powers, selected_set)
}

pub fn compute_q_eval_for_entries(
  x1_powers: List<State<Scalar>>,
  selected_set: List<(ByteArray, List<State<Scalar>>)>,
) -> List<State<Scalar>> {
  compute_q_eval_for_set_inner(x1_powers, selected_set, [])
}

fn compute_q_eval_for_set_inner(
  x1_powers: List<State<Scalar>>,
  selected_set: List<(ByteArray, List<State<Scalar>>)>,
  acc: List<State<Scalar>>,
) -> List<State<Scalar>> {
  when x1_powers is {
    [x1_power, ..rest_powers] ->
      when selected_set is {
        [(_, evals), ..rest_set] ->
          if acc == [] {
            compute_q_eval_for_set_inner(
              rest_powers,
              rest_set,
              scale_evals(evals, x1_power),
            )
          } else {
            compute_q_eval_for_set_inner(
              rest_powers,
              rest_set,
              add_scaled_evals(acc, evals, x1_power),
            )
          }
        [] -> acc
      }
    [] -> acc
  }
}

fn scale_evals(
  evals: List<State<Scalar>>,
  power: State<Scalar>,
) -> List<State<Scalar>> {
  when evals is {
    [eval, ..rest] -> [mul(eval, power), ..scale_evals(rest, power)]
    [] -> []
  }
}

fn add_scaled_evals(
  acc: List<State<Scalar>>,
  evals: List<State<Scalar>>,
  power: State<Scalar>,
) -> List<State<Scalar>> {
  when acc is {
    [left, ..rest_acc] ->
      when evals is {
        [right, ..rest_evals] ->
          [
            add(left, mul(right, power)),
            ..add_scaled_evals(rest_acc, rest_evals, power)
          ]
        [] -> acc
      }
    [] -> scale_evals(evals, power)
  }
}

fn compute_final_comm_without_f(
  x1_powers: List<State<Scalar>>,
  x4_powers: List<State<Scalar>>,
  commitment_map: List<List<(ByteArray, List<State<Scalar>>)>>,
) -> G1Element {
  let final_comm = foldl(
    zip(commitment_map, x4_powers),
    zero,
    fn((commitments_for_set, x4_power), acc) {
      let q_comm = foldl(
        zip(x1_powers, commitments_for_set),
        zero,
        fn((x1_power, (commitment, _)), inner_acc) {
          add_g1(inner_acc, scale(decompress(commitment), x1_power))
        },
      )

      add_g1(acc, scale(q_comm, x4_power))
    },
  )

  final_comm
}

pub fn compute_final_comm_with_f(
  x1_powers: List<State<Scalar>>,
  x4_powers: List<State<Scalar>>,
  f_commitment: ByteArray,
  commitment_map: List<List<(ByteArray, List<State<Scalar>>)>>,
) -> G1Element {
  let final_comm = compute_final_comm_without_f(
    x1_powers,
    x4_powers,
    commitment_map,
  )
  expect Some(x4_power) = last(x4_powers)
  let f_term = scale(decompress(f_commitment), x4_power)
  add_g1(final_comm, f_term)
}

pub fn compute_v(
  f_eval: State<Scalar>,
  x4_powers: List<State<Scalar>>,
  proof_x3_q_evals: List<State<Scalar>>,
) -> State<Scalar> {
  compute_v_inner(x4_powers, proof_x3_q_evals, f_eval, from_int(0))
}

fn compute_v_inner(
  x4_powers: List<State<Scalar>>,
  proof_x3_q_evals: List<State<Scalar>>,
  f_eval: State<Scalar>,
  acc: State<Scalar>,
) -> State<Scalar> {
  when proof_x3_q_evals is {
    [eval, ..rest_evals] ->
      when x4_powers is {
        [power, ..rest_powers] ->
          compute_v_inner(
            rest_powers,
            rest_evals,
            f_eval,
            add(acc, mul(power, eval)),
          )
        [] -> acc
      }
    [] ->
      when x4_powers is {
        [power, ..] -> add(acc, mul(power, f_eval))
        [] -> acc
      }
  }
}
