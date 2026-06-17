use midnight_circuits::instructions::EccInstructions;
use midnight_circuits::types::{AssignedNative, AssignedNativePoint};
use midnight_proofs::circuit::Layouter;
use midnight_proofs::plonk::Error;
use midnight_zk_stdlib::ZkStdLib;

use super::comparison::lower_than_native;
use super::super::types::{CircuitBase, CircuitCurve};

/// Constrains the current witness to have won the lottery for the assigned index.
pub(crate) fn assert_lottery_won(
    std_lib: &ZkStdLib,
    layouter: &mut impl Layouter<CircuitBase>,
    lottery_prefix: &AssignedNative<CircuitBase>,
    commitment_point: &AssignedNativePoint<CircuitCurve>,
    lottery_index: &AssignedNative<CircuitBase>,
    lottery_target_value: &AssignedNative<CircuitBase>,
) -> Result<(), Error> {
    let commitment_point_x = std_lib.jubjub().x_coordinate(commitment_point);
    let commitment_point_y = std_lib.jubjub().y_coordinate(commitment_point);
    let lottery_evaluation_value = std_lib.poseidon(
        layouter,
        &[
            lottery_prefix.clone(),
            commitment_point_x,
            commitment_point_y,
            lottery_index.clone(),
        ],
    )?;
    let is_less = lower_than_native(
        std_lib,
        layouter,
        lottery_target_value,
        &lottery_evaluation_value,
    )?;
    std_lib.assert_false(layouter, &is_less)
}

/// Constrains the current lottery index to be strictly greater than the previous one.
pub(crate) fn assert_strictly_increasing_lottery_index(
    std_lib: &ZkStdLib,
    layouter: &mut impl Layouter<CircuitBase>,
    previous_lottery_index: &AssignedNative<CircuitBase>,
    lottery_index: &AssignedNative<CircuitBase>,
) -> Result<(), Error> {
    let is_less = std_lib.lower_than(layouter, previous_lottery_index, lottery_index, 32)?;
    std_lib.assert_true(layouter, &is_less)
}

/// Constrains a lottery index to lie in the interval `[0, m)`.
pub(crate) fn assert_lottery_index_in_bounds(
    std_lib: &ZkStdLib,
    layouter: &mut impl Layouter<CircuitBase>,
    lottery_index: &AssignedNative<CircuitBase>,
    m: &AssignedNative<CircuitBase>,
) -> Result<(), Error> {
    let is_less = std_lib.lower_than(layouter, lottery_index, m, 32)?;
    std_lib.assert_true(layouter, &is_less)
}
