pragma circom 2.1.9;

/*
Standalone algebraic verifier for Mithril's Standard Schnorr signature over
Jubjub.
- it verifies the *algebraic* Schnorr relation
- it already checks curve membership and prime-order subgroup membership
- it already recomputes the Poseidon challenge
- but it still expects the signature/key/message_component `s` as native field
  elements rather than parsing the full Mithril byte payload inside the circuit

Public statement:
- `digest_hi`
- `digest_low`
- `verification_key_u`
- `verification_key_v`
- `signature_response`
- `signature_challenge`

Private witness:
- `challenge_scalar`
- `challenge_quotient`
- all intermediate points of scalar multiplication and point addition

Security note: The signature is only meaningful if the public inputs are later
bound to the exact Mithril certificate fields consumed by the bridge.
*/

include "jubjub_schnorr_verification_aux_components.circom";
include "midnight_poseidon3_sponge.circom";

template VerifyJubjubStandardSchnorr() {
    // Public algebraic inputs.
    // - `digest_hi` / `digest_low` are the exact 32 digest bytes split into two
    //   128-bit limbs, matching the packing style already used by the other
    //   circuits in this workspace.
    // - the circuit reconstructs `message_base` internally from those digest
    //   bytes, using Mithril's little-endian interpretation.
    // - `verification_key_(u,v)` are the affine coordinates of the Jubjub public
    //   key.  
    // - `signature_response` is the scalar-field response_component encoded as a
    //   field element. 
    // - `signature_challenge` is the base-field challenge_component.
    signal input digest_hi;
    signal input digest_low;
    signal input verification_key_u;
    signal input verification_key_v;
    signal input signature_response;
    signal input signature_challenge;
    signal input challenge_scalar;
    signal input challenge_quotient;
    
    // Public outputs mirror the inputs so a Groth16 wrapper can expose a stable
    // statement without depending on Circom's private-input plumbing.
    signal output digest_hi_out;
    signal output digest_low_out;
    signal output verification_key_u_out;
    signal output verification_key_v_out;
    signal output signature_response_out;
    signal output signature_challenge_out;

    component digestToMessageBase = DigestHiLoToMessageBase();
    digestToMessageBase.digest_hi <== digest_hi;
    digestToMessageBase.digest_low <== digest_low;

    signal message_base;
    message_base <== digestToMessageBase.message_base;
    
    // Step 1: ensure the verification key is actually a Jubjub point.
    component onCurve = AssertPointOnCurve();
    onCurve.u <== verification_key_u;
    onCurve.v <== verification_key_v;
    
    // Step 2: ensure the verification key is in the prime-order subgroup.
    // This matters because the Schnorr relation is only sound over the subgroup of
    // order `r`.
    component subgroup = AssertPrimeOrderSubgroup();
    subgroup.u <== verification_key_u;
    subgroup.v <== verification_key_v;
    
    // Step 3: reinterpret the base-field challenge as a scalar modulo `r`,
    // matching Mithril's `ScalarFieldElement::from_base_field(...)`.
    component challengeScalar = ConstrainBaseReducedToScalar();
    challengeScalar.base <== signature_challenge;
    challengeScalar.scalar <== challenge_scalar;
    challengeScalar.quotient <== challenge_quotient;
    
    // Step 4: compute response * G.
    component responseMul = JubjubScalarMulVar(255);
    responseMul.point_u <== generatorU();
    responseMul.point_v <== generatorV();
    responseMul.scalar <== signature_response;
    
    component challengeMul = JubjubScalarMulVar(255);
    challengeMul.point_u <== verification_key_u;
    challengeMul.point_v <== verification_key_v;
    challengeMul.scalar <== challenge_scalar;
    
    // Step 6: recompute the random point: R' = response * G + challenge * VK
    component randomPoint = JubjubPointAdd();
    randomPoint.p_u <== responseMul.out_u;
    randomPoint.p_v <== responseMul.out_v;
    randomPoint.q_u <== challengeMul.out_u;
    randomPoint.q_v <== challengeMul.out_v;
    
    // Step 7: recompute the challenge with Midnight's fixed-size Poseidon
    // sponge transcript, which is what Mithril calls through
    // `PoseidonChip<JubjubBase>::hash(&points_coordinates)`.
    //
    // Unlike the older `Poseidon255(nInputs)` helper, this transcript:
    // - uses a fixed WIDTH=3 / RATE=2 sponge
    // - places `input_len` in the capacity lane
    // - absorbs the six transcript elements in three chunks of two
    // - uses Midnight's own round constants and MDS matrix
    component poseidon = MidnightPoseidonFixedSponge(6, 3);
    poseidon.in[0] <== dstStandardSignature();
    poseidon.in[1] <== verification_key_u;
    poseidon.in[2] <== verification_key_v;
    poseidon.in[3] <== randomPoint.out_u;
    poseidon.in[4] <== randomPoint.out_v;
    poseidon.in[5] <== message_base;
    
    // Step 8: signature is valid iff the recomputed challenge matches the public challenge.
    poseidon.out === signature_challenge;
    
    // Re-expose the statement as public outputs.
    digest_hi_out <== digest_hi;
    digest_low_out <== digest_low;
    verification_key_u_out <== verification_key_u;
    verification_key_v_out <== verification_key_v;
    signature_response_out <== signature_response;
    signature_challenge_out <== signature_challenge;
}
