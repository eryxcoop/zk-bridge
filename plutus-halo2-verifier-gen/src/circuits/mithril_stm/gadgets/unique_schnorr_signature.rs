use midnight_circuits::instructions::{AssertionInstructions, EccInstructions};
use midnight_circuits::types::{AssignedNative, AssignedNativePoint, AssignedScalarOfNativeCurve};
use midnight_proofs::circuit::Layouter;
use midnight_proofs::plonk::Error;
use midnight_zk_stdlib::ZkStdLib;

use super::super::types::{CircuitBase, CircuitCurve};

/// Assigned inputs required to verify one unique Schnorr signature inside the circuit.
pub(crate) struct UniqueSchnorrSignatureInputs<'a> {
    /// Assigned domain-separation tag for signature verification.
    pub(crate) dst_signature: &'a AssignedNative<CircuitBase>,
    /// Assigned fixed generator of the signing curve.
    pub(crate) generator: &'a AssignedNativePoint<CircuitCurve>,
    /// Assigned verification key corresponding to the signer.
    pub(crate) verification_key: &'a AssignedNativePoint<CircuitCurve>,
    /// Assigned response scalar from the unique Schnorr signature.
    pub(crate) response: &'a AssignedScalarOfNativeCurve<CircuitCurve>,
    /// Assigned challenge value in the circuit base field.
    pub(crate) challenge_in_base_field: &'a AssignedNative<CircuitBase>,
    /// Assigned challenge converted into the curve scalar field.
    pub(crate) challenge_as_scalar: &'a AssignedScalarOfNativeCurve<CircuitCurve>,
    /// Assigned hash-to-curve point derived from the public inputs.
    pub(crate) hash: &'a AssignedNativePoint<CircuitCurve>,
    /// Assigned commitment point from the unique Schnorr signature.
    pub(crate) commitment_point: &'a AssignedNativePoint<CircuitCurve>,
}

/// Verifies the unique Schnorr signature constraints for one assigned witness entry.
pub(crate) fn verify_unique_signature(
    std_lib: &ZkStdLib,
    layouter: &mut impl Layouter<CircuitBase>,
    inputs: UniqueSchnorrSignatureInputs<'_>,
) -> Result<(), Error> {
    let cap_r_1 = std_lib.jubjub().msm(
        layouter,
        &[inputs.response.clone(), inputs.challenge_as_scalar.clone()],
        &[inputs.hash.clone(), inputs.commitment_point.clone()],
    )?;

    let cap_r_2 = std_lib.jubjub().msm(
        layouter,
        &[inputs.response.clone(), inputs.challenge_as_scalar.clone()],
        &[inputs.generator.clone(), inputs.verification_key.clone()],
    )?;

    let hx = std_lib.jubjub().x_coordinate(inputs.hash);
    let hy = std_lib.jubjub().y_coordinate(inputs.hash);
    let verification_key_x = std_lib.jubjub().x_coordinate(inputs.verification_key);
    let verification_key_y = std_lib.jubjub().y_coordinate(inputs.verification_key);
    let commitment_point_x = std_lib.jubjub().x_coordinate(inputs.commitment_point);
    let commitment_point_y = std_lib.jubjub().y_coordinate(inputs.commitment_point);
    let cap_r_1_x = std_lib.jubjub().x_coordinate(&cap_r_1);
    let cap_r_1_y = std_lib.jubjub().y_coordinate(&cap_r_1);
    let cap_r_2_x = std_lib.jubjub().x_coordinate(&cap_r_2);
    let cap_r_2_y = std_lib.jubjub().y_coordinate(&cap_r_2);

    let challenge_prime = std_lib.poseidon(
        layouter,
        &[
            inputs.dst_signature.clone(),
            hx,
            hy,
            verification_key_x,
            verification_key_y,
            commitment_point_x.clone(),
            commitment_point_y.clone(),
            cap_r_1_x,
            cap_r_1_y,
            cap_r_2_x,
            cap_r_2_y,
        ],
    )?;

    std_lib.assert_equal(layouter, inputs.challenge_in_base_field, &challenge_prime)
}
