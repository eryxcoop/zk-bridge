use midnight_circuits::{hash::poseidon::PoseidonChip, instructions::hash::HashCPU};
use midnight_curves::Fq as JubjubBase;

use super::BaseFieldElement;

/// Domain Separation Tag (DST) for the Poseidon hash used in signature contexts.
pub(crate) const DOMAIN_SEPARATION_TAG_SIGNATURE: BaseFieldElement =
    BaseFieldElement(JubjubBase::from_raw([
        0x5349_474E_5F44_5354, // "SIGN_DST" (ASCII), little-endian u64
        0,
        0,
        0,
    ]));

/// Domain Separation Tag (DST) for the lottery check. It is used as a prefix when computing
/// the eligibility value of a signature.
// TODO: remove this allow dead_code directive when function is called or future_snark is activated
#[allow(dead_code)]
pub const DOMAIN_SEPARATION_TAG_LOTTERY: BaseFieldElement =
    BaseFieldElement(JubjubBase::from_raw([
        0x4C4F_5454_5F44_5354, // "LOTT_DST" (ASCII), little-endian u64
        0,
        0,
        0,
    ]));

/// Computes a Poseidon digest over the provided base field elements.
/// Returns a base field element as the digest.
pub(crate) fn compute_poseidon_digest(input: &[BaseFieldElement]) -> BaseFieldElement {
    let poseidon_input: Vec<JubjubBase> = input.iter().map(|i| i.0).collect();

    BaseFieldElement(PoseidonChip::<JubjubBase>::hash(&poseidon_input))
}
