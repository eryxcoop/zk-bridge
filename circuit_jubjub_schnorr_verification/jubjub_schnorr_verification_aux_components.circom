pragma circom 2.1.9;

/*
Shared auxiliarycomponent s for the standalone Jubjub Schnorr verification
circuit.

Design notes:

1. This first standalone version deliberately works over *algebraic* inputs:
- `message_base`
- `verification_key_(u,v)`
- `signature_response`
- `signature_challenge`

It does NOT yet parse Mithril's byte-level payload inside the circuit.
That byte-level binding is a later integration step.

2. The Schnorr transcript no longer reuses the older variable-width
`Poseidon255(nInputs)` helper from elsewhere in the workspace. The verifier now
uses a dedicated Midnight-compatible sponge helper in:
`midnight_poseidon3_sponge.circom`.

3. The group law here is the twisted-Edwards law on Jubjub with:
- `a = -1`
- `d = EDWARDS_D`

We use the complete affine formulas as polynomial constraints:
    `u3 * (1 + d*u1*u2*v1*v2) = u1*v2 + v1*u2`
    `v3 * (1 - d*u1*u2*v1*v2) = v1*v2 + u1*u2`

This avoids any non-native inversion gadget.
*/

// The Jubjub base field used by Midnight / Mithril is the BLS12-381 scalar
// field:
//
//   q = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001
//
// `circom --prime bls12381` therefore gives us exactly the right native field.
// Circom does not like free-standing top-level `var` declarations, so these
// constants are exposed as tiny functions.
function jubjubEdwardsD() {
    return 0x2a9318e74bfa2b48f5fd9207e6bd7fd4292d7f6d37579d2601065fd6d6343eb1;
}

// Jubjub prime subgroup order:
//   r = 0x0e7db4ea6533afa906673b0101343b00a6682093ccc81082d0970e5ed6f72cb7
//
// This is the modulus of Midnight's Jubjub scalar field.
function jubjubScalarOrder() {
    return 0x0e7db4ea6533afa906673b0101343b00a6682093ccc81082d0970e5ed6f72cb7;
}

// Domain separation tag used by Mithril for Standard Schnorr signatures:
//   "STDS_DST" interpreted as a little-endian 64-bit lane and then lifted to
//   the Jubjub base field via `from_raw([lane, 0, 0, 0])`.
function dstStandardSignature() {
    return 0x535444535f445354;
}

// Prime-order Jubjub subgroup generator used by Mithril upstream.
function generatorU() {
    return 0x3ea5c4673a121ca35ed37ee3b172f5ee04315c657fbe375f512dfea318d56fe5;
}

function generatorV() {
    return 0x57137b83ea6edb4f78f7d30d3f616cb3b9aa6e8e40808413c10cea38d50c55cb;
}

template AssertBit() {
    signal input in;
    in * (in - 1) === 0;
}

// Decompose a field element into `n` bits (little-endian / LSB-first) and
// reconstruct it to avoid underconstrained witnesses.
//
// This is safe only when the caller knows the input fits in `n` bits.
// For this standalone circuit we only apply it to:
// - subgroup scalars (< 2^255)
// - the small quotient in `ReduceBaseFieldToScalar`
template ToBits(n) {
    signal input inp;
    signal output out[n];
    var acc = 0;
    var e2 = 1;
    
    for (var i = 0; i < n; i++) {
        out[i] <-- (inp >> i) & 1;
        out[i] * (out[i] - 1) === 0;
        acc += out[i] * e2;
        e2 = e2 + e2;
    }
    
    acc === inp;
}

template BitsToNum(n) {
    signal input in[n];
    signal output out;
    var e2 = 1;
    var acc = 0;

    for (var i = 0; i < n; i++) {
        acc += in[i] * e2;
        e2 = e2 + e2;
    }

    out <== acc;
}

// Decompose a 128-bit field element into 16 big-endian bytes.
template U128ToBytesBE() {
    signal input inp;
    signal output bytes[16];

    component bits = ToBits(128);
    bits.inp <== inp;

    component bytePacks[16];

    for (var i = 0; i < 16; i++) {
        bytePacks[i] = BitsToNum(8);
        for (var j = 0; j < 8; j++) {
            bytePacks[i].in[j] <== bits.out[i * 8 + j];
        }

        // The least-significant 8 bits correspond to the last byte of the
        // original big-endian packing.
        bytes[15 - i] <== bytePacks[i].out;
    }
}

// Reconstruct Mithril's algebraic `message_base` from a split 32-byte digest.
//
// The digest halves are packed the same way as the other circuits in this
// workspace:
// - `digest_hi` = first 16 digest bytes as one big-endian u128
// - `digest_low` = last 16 digest bytes as one big-endian u128
//
// Mithril then interprets the full 32-byte digest as a little-endian integer
// before reducing it into the Jubjub base field. Since this circuit already
// runs over that exact native field, reconstructing the little-endian digest as
// a field element automatically gives the reduced `message_base`.
template DigestHiLoToMessageBase() {
    signal input digest_hi;
    signal input digest_low;
    signal output message_base;

    component hiBytes = U128ToBytesBE();
    component lowBytes = U128ToBytesBE();
    hiBytes.inp <== digest_hi;
    lowBytes.inp <== digest_low;

    signal digest_bytes[32];
    for (var i = 0; i < 16; i++) {
        digest_bytes[i] <== hiBytes.bytes[i];
        digest_bytes[i + 16] <== lowBytes.bytes[i];
    }

    signal acc[33];
    acc[0] <== 0;
    var coeff = 1;
    for (var i = 0; i < 32; i++) {
        acc[i + 1] <== acc[i] + digest_bytes[i] * coeff;
        coeff = coeff * 256;
    }

    message_base <== acc[32];
}

// Select one of two field elements using a boolean selector.
// - If `selector = 0`, output `whenZero`.
// - If `selector = 1`, output `whenOne`.
template SelectField() {
    signal input selector;
    signal input whenZero;
    signal input whenOne;
    signal output out;
    
    component assertBit = AssertBit();
    assertBit.in <== selector;
    
    out <== whenZero + selector * (whenOne - whenZero);
}

// Select one of two Jubjub points using a boolean selector.
template SelectPoint() {
    signal input selector;
    signal input whenZero_u;
    signal input whenZero_v;
    signal input whenOne_u;
    signal input whenOne_v;
    signal output out_u;
    signal output out_v;
    
    component selU = SelectField();
    component selV = SelectField();
    
    selU.selector <== selector;
    selU.whenZero <== whenZero_u;
    selU.whenOne <== whenOne_u;
    out_u <== selU.out;
    
    selV.selector <== selector;
    selV.whenZero <== whenZero_v;
    selV.whenOne <== whenOne_v;
    out_v <== selV.out;
}

// Constrain that `(u, v)` lies on the Jubjub twisted Edwards curve:
//   `v^2 - u^2 = 1 + d*u^2*v^2`
template AssertPointOnCurve() {
    signal input u;
    signal input v;
    
    signal uu;
    signal vv;
    signal lhs;
    signal rhs;
    signal uuvv;
    
    uu <== u * u;
    vv <== v * v;
    uuvv <== uu * vv;
    lhs <== vv - uu;
    rhs <== 1 + jubjubEdwardsD() * uuvv;
    
    lhs === rhs;
}

// Affine point addition on Jubjub, expressed without inversions by treating the
// output point as a witness constrained by the complete Edwards equations.
//
// For valid subgroup points the complete formulas are:
// `u3 = (u1*v2 + v1*u2) / (1 + d*u1*u2*v1*v2)`
// `v3 = (v1*v2 + u1*u2) / (1 - d*u1*u2*v1*v2)`
// and we encode them as polynomial equalities.
template JubjubPointAdd() {
    signal input p_u;
    signal input p_v;
    signal input q_u;
    signal input q_v;
    signal output out_u;
    signal output out_v;
    signal r_u;
    signal r_v;
    
    signal puqu;
    signal pvpq;
    signal uvuv;
    signal puqv;
    signal pvqu;
    signal pvpv;
    signal puqu_again;
    signal num_u;
    signal num_v;
    signal den_u;
    signal den_v;
    
    puqu <== p_u * q_u;
    pvpq <== p_v * q_v;
    uvuv <== puqu * pvpq;
    
    puqv <== p_u * q_v;
    pvqu <== p_v * q_u;
    num_u <== puqv + pvqu;
    
    pvpv <== p_v * q_v;
    puqu_again <== p_u * q_u;
    num_v <== pvpv + puqu_again;
    
    den_u <== 1 + jubjubEdwardsD() * uvuv;
    den_v <== 1 - jubjubEdwardsD() * uvuv;
    
    r_u <-- num_u / den_u;
    r_v <-- num_v / den_v;
    r_u * den_u === num_u;
    r_v * den_v === num_v;
    out_u <== r_u;
    out_v <== r_v;
}

// Variable-base scalar multiplication using a simple double-and-add chain.
//
// Bits are consumed LSB-first, matching the witness decomposition produced by
// `ToBits(255)`.
template JubjubScalarMulVar(nBits) {
    signal input point_u;
    signal input point_v;
    signal input scalar;
    signal output out_u;
    signal output out_v;
    
    component scalarBits = ToBits(nBits);
    scalarBits.inp <== scalar;
    
    signal acc_u[nBits + 1];
    signal acc_v[nBits + 1];
    signal base_u[nBits + 1];
    signal base_v[nBits + 1];
    
    component adders[nBits];
    component doublers[nBits];
    component selectors[nBits];
    
    acc_u[0] <== 0;
    acc_v[0] <== 1;
    base_u[0] <== point_u;
    base_v[0] <== point_v;
    
    for (var i = 0; i < nBits; i++) {
        adders[i] = JubjubPointAdd();
        adders[i].p_u <== acc_u[i];
        adders[i].p_v <== acc_v[i];
        adders[i].q_u <== base_u[i];
        adders[i].q_v <== base_v[i];
        
        selectors[i] = SelectPoint();
        selectors[i].selector <== scalarBits.out[i];
        selectors[i].whenZero_u <== acc_u[i];
        selectors[i].whenZero_v <== acc_v[i];
        selectors[i].whenOne_u <== adders[i].out_u;
        selectors[i].whenOne_v <== adders[i].out_v;
        
        acc_u[i + 1] <== selectors[i].out_u;
        acc_v[i + 1] <== selectors[i].out_v;
        
        doublers[i] = JubjubPointAdd();
        doublers[i].p_u <== base_u[i];
        doublers[i].p_v <== base_v[i];
        doublers[i].q_u <== base_u[i];
        doublers[i].q_v <== base_v[i];
        
        base_u[i + 1] <== doublers[i].out_u;
        base_v[i + 1] <== doublers[i].out_v;
    }
    
    out_u <== acc_u[nBits];
    out_v <== acc_v[nBits];
}

// Reduce a Jubjub base-field element into the Jubjub scalar field modulo `r`.
//
// This matches the role of Mithril's `ScalarFieldElement::from_base_field(...)`
// in the verification path.
//
// Because `0 <= base < q` and `q = 8*r + rem_q`, then
// the quotient of `base / r` is guaranteed to lie in `[0, 8]`. We exploit that to
// avoid a full division gadget: witness a tiny `quotient` and constrain
// `base = quotient * r + scalar` with `quotient ∈ {0..8}`.
//  
// We intentionally do NOT force `scalar < r` here, since any representative
// congruent modulo `r` yields the same subgroup scalar multiplication result.
template ConstrainBaseReducedToScalar() {
    signal input base;
    signal input scalar;
    signal input quotient;
    
    component qBits = ToBits(4);
    qBits.inp <== quotient;
    qBits.out[3] * qBits.out[2] === 0;
    qBits.out[3] * qBits.out[1] === 0;
    qBits.out[3] * qBits.out[0] === 0;
    
    base === quotient * jubjubScalarOrder() + scalar;
}


// Constrain that a point lies in the prime-order subgroup by checking
// `[r]P = identity`, where `r` is the Jubjub subgroup order.
template AssertPrimeOrderSubgroup() {
    signal input u;
    signal input v;
    
    component subgroupMul = JubjubScalarMulVar(255);
    subgroupMul.point_u <== u;
    subgroupMul.point_v <== v;
    subgroupMul.scalar <== jubjubScalarOrder();
    
    subgroupMul.out_u === 0;
    subgroupMul.out_v === 1;
}
    
