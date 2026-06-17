use midnight_circuits::instructions::{BinaryInstructions, EqualityInstructions};
use midnight_circuits::types::{AssignedBit, AssignedNative};
use midnight_proofs::circuit::Layouter;
use midnight_proofs::plonk::Error;
use midnight_zk_stdlib::ZkStdLib;

use super::comparison_helpers::decompose_unsafe;
use super::super::types::CircuitBase;

/// Compares two assigned 255-bit values and returns a bit witnessing whether `x < y`.
pub(super) fn lower_than_native(
    std_lib: &ZkStdLib,
    layouter: &mut impl Layouter<CircuitBase>,
    x: &AssignedNative<CircuitBase>,
    y: &AssignedNative<CircuitBase>,
) -> Result<AssignedBit<CircuitBase>, Error> {
    let (x_low_assigned, x_high_assigned) = decompose_unsafe(std_lib, layouter, x)?;
    let (y_low_assigned, y_high_assigned) = decompose_unsafe(std_lib, layouter, y)?;

    let is_equal_high = std_lib.is_equal(layouter, &x_high_assigned, &y_high_assigned)?;
    let is_less_low = std_lib.lower_than(layouter, &x_low_assigned, &y_low_assigned, 127)?;
    let is_less_high = std_lib.lower_than(layouter, &x_high_assigned, &y_high_assigned, 128)?;

    let low_less = std_lib.and(layouter, &[is_equal_high, is_less_low])?;
    std_lib.or(layouter, &[is_less_high, low_less])
}
