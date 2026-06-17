use anyhow::anyhow;
use mithril_stm::LotteryIndex;
use num_bigint::BigInt;
use num_integer::Integer;
use num_rational::Ratio;
use num_traits::{Num, One};

use super::crypto::{
    BaseFieldElement, DOMAIN_SEPARATION_TAG_LOTTERY, UniqueSchnorrSignature,
    compute_poseidon_digest,
};
use super::StmResult;

/// Modulus of the Jubjub base field as a hexadecimal number.
const JUBJUB_BASE_FIELD_MODULUS: &str =
    "73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001";
/// Number of iterations used by the Taylor approximations copied from Mithril.
const TAYLOR_EXPANSION_ITERATIONS: usize = 30;

pub(crate) fn compute_target_value_for_snark_lottery(
    phi_f: f64,
    stake: u64,
    total_stake: u64,
) -> StmResult<BaseFieldElement> {
    if total_stake == 0 {
        return Err(anyhow!("total_stake must be non-zero"));
    }

    if (phi_f - 1.0).abs() < f64::EPSILON {
        return Ok(&BaseFieldElement::default() - &BaseFieldElement::get_one());
    }

    let phi_f_ratio_int: Ratio<i64> = Ratio::approximate_float(phi_f)
        .ok_or_else(|| anyhow!("phi_f must be finite and non-NaN"))?;
    let phi_f_ratio = Ratio::new_raw(
        BigInt::from(*phi_f_ratio_int.numer()),
        BigInt::from(*phi_f_ratio_int.denom()),
    );
    let ln_one_minus_phi_f = ln_1p_taylor_expansion(
        TAYLOR_EXPANSION_ITERATIONS,
        phi_f_ratio.numer(),
        phi_f_ratio.denom(),
    );

    Ok(compute_target_value_for_snark_lottery_given_ln_approximation(
        &ln_one_minus_phi_f,
        stake,
        total_stake,
    ))
}

pub(crate) fn compute_winning_lottery_indices(
    m: u64,
    msg: &[BaseFieldElement],
    signature: &UniqueSchnorrSignature,
    lottery_target_value: BaseFieldElement,
) -> StmResult<Vec<LotteryIndex>> {
    let lottery_prefix = compute_lottery_prefix(msg);
    let winning_indices = (0..m)
        .filter(|&index| {
            matches!(
                check_lottery_for_index(signature, index, m, lottery_prefix, lottery_target_value),
                Ok(true)
            )
        })
        .collect::<Vec<_>>();

    if winning_indices.is_empty() {
        return Err(anyhow!("lottery lost"));
    }

    Ok(winning_indices)
}

pub(crate) fn compute_lottery_prefix(
    message_as_base_field_element: &[BaseFieldElement],
) -> BaseFieldElement {
    let mut prefix = vec![DOMAIN_SEPARATION_TAG_LOTTERY];
    prefix.extend_from_slice(message_as_base_field_element);
    compute_poseidon_digest(&prefix)
}

fn check_lottery_for_index(
    signature: &UniqueSchnorrSignature,
    lottery_index: LotteryIndex,
    m: u64,
    prefix: BaseFieldElement,
    target: BaseFieldElement,
) -> StmResult<bool> {
    if lottery_index >= m {
        return Err(anyhow!("lottery index {lottery_index} is out of bounds for m={m}"));
    }

    let lottery_index_as_base_field_element = BaseFieldElement::from(lottery_index);
    let (commitment_point_x, commitment_point_y) = signature.commitment_point.get_coordinates();
    let lottery_evaluation = compute_poseidon_digest(&[
        prefix,
        commitment_point_x,
        commitment_point_y,
        lottery_index_as_base_field_element,
    ]);

    Ok(lottery_evaluation <= target)
}

fn compute_target_value_for_snark_lottery_given_ln_approximation(
    ln_one_minus_phi_f: &Ratio<BigInt>,
    stake: u64,
    total_stake: u64,
) -> BaseFieldElement {
    let modulus = BigInt::from_str_radix(JUBJUB_BASE_FIELD_MODULUS, 16)
        .expect("hardcoded Jubjub modulus is valid");
    let stake_ratio = Ratio::new_raw(BigInt::from(stake), BigInt::from(total_stake));

    let exp_ln_one_minus_phi_f_stake_ratio = compute_exponential_taylor_expansion(
        ln_one_minus_phi_f,
        &stake_ratio,
        TAYLOR_EXPANSION_ITERATIONS,
    );

    let modulus_ratio = Ratio::from(modulus);
    let target_as_ratio =
        modulus_ratio.clone() - modulus_ratio * exp_ln_one_minus_phi_f_stake_ratio;

    let (target_as_int, _) = target_as_ratio.numer().div_rem(target_as_ratio.denom());

    let (_, mut bytes) = target_as_int.to_bytes_le();
    bytes.resize(32, 0);
    BaseFieldElement::from_bytes(&bytes)
        .expect("target computation always stays below the Jubjub modulus")
}

fn compute_exponential_taylor_expansion(
    c: &Ratio<BigInt>,
    w: &Ratio<BigInt>,
    iterations: usize,
) -> Ratio<BigInt> {
    let cw = c * w;
    let (num, denom, _) = exponential_approximation(0, iterations, cw.numer(), cw.denom());
    Ratio::new_raw(num, denom)
}

fn exponential_approximation(
    first_term: usize,
    last_term: usize,
    a: &BigInt,
    b: &BigInt,
) -> (BigInt, BigInt, BigInt) {
    if last_term - first_term == 1 {
        if first_term == 0 {
            return (BigInt::one(), BigInt::one(), BigInt::one());
        }
        return (a.clone(), b * BigInt::from(first_term), a.clone());
    }

    let middle = (first_term + last_term) / 2;
    let (numerator_left, denominator_left, auxiliary_value_left) =
        exponential_approximation(first_term, middle, a, b);
    let (numerator_right, denominator_right, auxiliary_value_right) =
        exponential_approximation(middle, last_term, a, b);

    let numerator =
        &numerator_left * &denominator_right + &auxiliary_value_left * &numerator_right;
    let denominator = &denominator_left * &denominator_right;
    let auxiliary_value = auxiliary_value_left * auxiliary_value_right;

    (numerator, denominator, auxiliary_value)
}

fn ln_1p_taylor_expansion(iterations: usize, a: &BigInt, b: &BigInt) -> Ratio<BigInt> {
    let mut numerator = a.clone();
    let mut denominator = b.clone();
    let mut accumulator = Ratio::new_raw(a.clone(), b.clone());

    for i in 2..(iterations + 1) {
        numerator *= a;
        denominator *= b;
        accumulator += Ratio::new_raw(numerator.clone(), denominator.clone() * i);
    }

    -accumulator
}
