pragma circom 2.1.9;

include "vendor/blake2s.circom";

// Constrains a signal to [0, 255] by decomposing it into 8 bits.
// ToBits(8) fails to satisfy if the value requires more than 8 bits,
// so this is sufficient to rule out large field elements masquerading as bytes.
template AssertByte() {
    signal input in;
    component b = ToBits(8);
    b.inp <== in;
}

// Applies AssertByte to every element of an N-element array.
template AssertBytes(N) {
    signal input in[N];
    component checks[N];
    for (var i = 0; i < N; i++) {
        checks[i] = AssertByte();
        checks[i].in <== in[i];
    }
}

// Constrains a signal to {0, 1} via the polynomial identity in*(in-1)==0,
// which has exactly those two roots in any field of characteristic > 2.
// Used to validate all selector and direction flags before they are used
// in multiplexers or linear combinations.
template AssertBit() {
    signal input in;
    in * (in - 1) === 0;
}

// 2-to-1 multiplexer for a single field element.
// Uses linear interpolation: out = a + sel*(b-a), which equals a when sel==0
// and b when sel==1 without requiring a conditional branch.
template SelectField() {
    signal input a;
    signal input b;
    signal input sel;
    signal output out;

    component bit = AssertBit();
    bit.in <== sel;
    out <== a + sel * (b - a);
}

// 2-to-1 multiplexer for an array of N bytes.
// Each element uses the same interpolation as SelectField, all gated by a
// single selector bit so the entire array switches atomically.
template SelectBytes(N) {
    signal input a[N];
    signal input b[N];
    signal input sel;
    signal output out[N];

    component bit = AssertBit();
    bit.in <== sel;

    for (var i = 0; i < N; i++) {
        out[i] <== a[i] + sel * (b[i] - a[i]);
    }
}

// Returns 1 if in==0, 0 otherwise.
// Arithmetic circuits cannot branch, so the boolean result is encoded as a
// field element using the modular-inverse trick: inv = 1/in when in != 0,
// and the two constraints pin out to 1 iff in is zero.
template IsZero() {
    signal input in;
    signal output out;
    signal inv;

    inv <-- in != 0 ? 1 / in : 0;
    out <== 1 - in * inv;
    in * out === 0;
    in * inv + out === 1;
}

// Returns 1 if in==K, 0 otherwise.
// Reduces to an IsZero check after shifting by K.
template EqualConst(K) {
    signal input in;
    signal output out;

    component z = IsZero();
    z.in <== in - K;
    out <== z.out;
}

// Enforces that the enabled array forms a contiguous prefix of 1s with no gaps
// (e.g. [1,1,1,0,0] is valid; [1,0,1,0,0] is not).
// When REQUIRE_FIRST==1 the first element must be 1, ruling out the all-zero case.
// This shape is required so a fixed-size circuit can represent variable-length
// Merkle paths: active steps occupy a contiguous prefix, inactive steps pad the rest.
template AssertContiguousEnabled(N, REQUIRE_FIRST) {
    signal input enabled[N];

    // Each flag must be binary before the contiguity check to prevent a prover
    // from smuggling non-boolean values that satisfy the product constraint below.
    component bits[N];
    for (var i = 0; i < N; i++) {
        bits[i] = AssertBit();
        bits[i].in <== enabled[i];
    }

    if (REQUIRE_FIRST == 1 && N > 0) {
        enabled[0] === 1;
    }

    // enabled[i] * (1 - enabled[i-1]) == 0 says: a 1 cannot appear after a 0,
    // which is exactly the no-gap invariant.
    for (var i = 1; i < N; i++) {
        enabled[i] * (1 - enabled[i - 1]) === 0;
    }
}

// Thin wrapper around the vendored Blake2s_bytes that exposes a uniform
// array-in / array-out interface used throughout this file.
template Blake2s256Fixed(INPUT_BYTES) {
    signal input in_b[INPUT_BYTES];
    signal output out_b[32];

    component h = Blake2s_bytes(INPUT_BYTES);
    for (var i = 0; i < INPUT_BYTES; i++) {
        h.inp_bytes[i] <== in_b[i];
    }
    for (var j = 0; j < 32; j++) {
        out_b[j] <== h.hash_bytes[j];
    }
}

// Produces current_b||sibling_b or sibling_b||current_b depending on siblingOnLeft.
// Because circuits evaluate all constraints unconditionally, both orderings are
// built upfront and SelectBytes picks the correct one. This avoids any
// if-else branching that would not be expressible as arithmetic constraints.
template ConcatFixed(CURRENT_BYTES, SIBLING_BYTES) {
    signal input current_b[CURRENT_BYTES];
    signal input sibling_b[SIBLING_BYTES];
    signal input siblingOnLeft;
    signal output out_b[CURRENT_BYTES + SIBLING_BYTES];

    component bit = AssertBit();
    bit.in <== siblingOnLeft;

    signal layoutCurrentFirst_b[CURRENT_BYTES + SIBLING_BYTES];
    signal layoutSiblingFirst_b[CURRENT_BYTES + SIBLING_BYTES];

    // Build current_b||sibling_b.
    for (var i = 0; i < CURRENT_BYTES; i++) {
        layoutCurrentFirst_b[i] <== current_b[i];
    }
    for (var i = 0; i < SIBLING_BYTES; i++) {
        layoutCurrentFirst_b[CURRENT_BYTES + i] <== sibling_b[i];
    }

    // Build sibling_b||current_b.
    for (var i = 0; i < SIBLING_BYTES; i++) {
        layoutSiblingFirst_b[i] <== sibling_b[i];
    }
    for (var i = 0; i < CURRENT_BYTES; i++) {
        layoutSiblingFirst_b[SIBLING_BYTES + i] <== current_b[i];
    }

    // Select the layout that places the sibling on the correct side.
    component pick = SelectBytes(CURRENT_BYTES + SIBLING_BYTES);
    for (var i = 0; i < CURRENT_BYTES + SIBLING_BYTES; i++) {
        pick.a[i] <== layoutCurrentFirst_b[i];
        pick.b[i] <== layoutSiblingFirst_b[i];
    }
    pick.sel <== siblingOnLeft;
    for (var i = 0; i < CURRENT_BYTES + SIBLING_BYTES; i++) {
        out_b[i] <== pick.out[i];
    }
}

// First step of a typed Merkle prefix, where the current value is a raw
// (non-hashed) byte string such as the 64-byte ASCII tx hash.
// The sibling can be either another raw CURRENT_BYTES string (rawSibling_b) if kind==0 or an
// already-hashed 32-byte value (hashSibling_b) if kind==1. Both sibling slots are present in
// the witness; the inactive slot is forced to zero so a prover cannot carry
// arbitrary data through it.
// Output: Blake2s256(current_b || sibling_b) with the order set by siblingOnLeft.
template TypedPrefixFirstStep(CURRENT_BYTES, RAW_SIBLING_BYTES) {
    signal input current_b[CURRENT_BYTES];
    signal input kind;
    signal input rawSibling_b[RAW_SIBLING_BYTES];
    signal input hashSibling_b[32];
    signal input siblingOnLeft;
    signal output out_b[32];

    component kindBit = AssertBit();
    component dirBit = AssertBit();
    kindBit.in <== kind;
    dirBit.in <== siblingOnLeft;

    // Exactly one sibling slot may carry non-zero data. Forcing the unused slot
    // to zero prevents a prover from encoding extra information that could be
    // exploited to produce a collision in the hashed output.
    for (var i = 0; i < RAW_SIBLING_BYTES; i++) {
        rawSibling_b[i] * kind === 0;
    }
    for (var i = 0; i < 32; i++) {
        hashSibling_b[i] * (1 - kind) === 0;
    }

    // Wire each sibling type into its own ConcatFixed so both candidate inputs
    // to Blake2s are fully determined before the hash is computed.
    component rawConcat = ConcatFixed(CURRENT_BYTES, RAW_SIBLING_BYTES);
    for (var i = 0; i < CURRENT_BYTES; i++) {
        rawConcat.current_b[i] <== current_b[i];
    }
    for (var i = 0; i < RAW_SIBLING_BYTES; i++) {
        rawConcat.sibling_b[i] <== rawSibling_b[i];
    }
    rawConcat.siblingOnLeft <== siblingOnLeft;

    component hashConcat = ConcatFixed(CURRENT_BYTES, 32);
    for (var i = 0; i < CURRENT_BYTES; i++) {
        hashConcat.current_b[i] <== current_b[i];
    }
    for (var i = 0; i < 32; i++) {
        hashConcat.sibling_b[i] <== hashSibling_b[i];
    }
    hashConcat.siblingOnLeft <== siblingOnLeft;

    // Hash both candidates unconditionally, then select by kind.
    // Computing both is necessary because circuits have no conditional execution.
    component rawHash = Blake2s256Fixed(CURRENT_BYTES + RAW_SIBLING_BYTES);
    for (var i = 0; i < CURRENT_BYTES + RAW_SIBLING_BYTES; i++) {
        rawHash.in_b[i] <== rawConcat.out_b[i];
    }

    component hashHash = Blake2s256Fixed(CURRENT_BYTES + 32);
    for (var i = 0; i < CURRENT_BYTES + 32; i++) {
        hashHash.in_b[i] <== hashConcat.out_b[i];
    }

    component pick = SelectBytes(32);
    for (var i = 0; i < 32; i++) {
        pick.a[i] <== rawHash.out_b[i];
        pick.b[i] <== hashHash.out_b[i];
    }
    pick.sel <== kind;
    for (var i = 0; i < 32; i++) {
        out_b[i] <== pick.out[i];
    }
}

// Subsequent step of a typed Merkle prefix where current_b is already a 32-byte
// hash. Follows the same kind-based sibling selection as TypedPrefixFirstStep,
// but adds an enabled gate: when enabled==0 the step is a no-op and out_b==current_b,
// allowing the caller to chain a fixed number of steps regardless of the actual
// path depth.
// All varying inputs (kind, siblings, direction) are constrained to zero when
// disabled so a prover cannot hide data in inactive steps.
template TypedPrefixHashedStep(RAW_SIBLING_BYTES) {
    signal input current_b[32];
    signal input kind;
    signal input rawSibling_b[RAW_SIBLING_BYTES];
    signal input hashSibling_b[32];
    signal input siblingOnLeft;
    signal input enabled;
    signal output out_b[32];

    component kindBit = AssertBit();
    component dirBit = AssertBit();
    component enabledBit = AssertBit();
    kindBit.in <== kind;
    dirBit.in <== siblingOnLeft;
    enabledBit.in <== enabled;

    // Disabled steps must have all control and data signals set to zero,
    // preventing the prover from smuggling non-zero values through inactive slots.
    kind * (1 - enabled) === 0;
    siblingOnLeft * (1 - enabled) === 0;

    for (var i = 0; i < RAW_SIBLING_BYTES; i++) {
        rawSibling_b[i] * kind === 0;
        rawSibling_b[i] * (1 - enabled) === 0;
    }
    for (var i = 0; i < 32; i++) {
        hashSibling_b[i] * (1 - kind) === 0;
        hashSibling_b[i] * (1 - enabled) === 0;
    }

    // Build both concatenations unconditionally, as in TypedPrefixFirstStep.
    component rawConcat = ConcatFixed(32, RAW_SIBLING_BYTES);
    for (var i = 0; i < 32; i++) {
        rawConcat.current_b[i] <== current_b[i];
    }
    for (var i = 0; i < RAW_SIBLING_BYTES; i++) {
        rawConcat.sibling_b[i] <== rawSibling_b[i];
    }
    rawConcat.siblingOnLeft <== siblingOnLeft;

    component hashConcat = ConcatFixed(32, 32);
    for (var i = 0; i < 32; i++) {
        hashConcat.current_b[i] <== current_b[i];
        hashConcat.sibling_b[i] <== hashSibling_b[i];
    }
    hashConcat.siblingOnLeft <== siblingOnLeft;

    // Compute both candidate hashes, select the one matching kind, then gate
    // the whole result by enabled so disabled steps propagate current_b unchanged.
    component rawHash = Blake2s256Fixed(32 + RAW_SIBLING_BYTES);
    for (var i = 0; i < 32 + RAW_SIBLING_BYTES; i++) {
        rawHash.in_b[i] <== rawConcat.out_b[i];
    }

    component hashHash = Blake2s256Fixed(64);
    for (var i = 0; i < 64; i++) {
        hashHash.in_b[i] <== hashConcat.out_b[i];
    }

    component pickKind = SelectBytes(32);
    for (var i = 0; i < 32; i++) {
        pickKind.a[i] <== rawHash.out_b[i];
        pickKind.b[i] <== hashHash.out_b[i];
    }
    pickKind.sel <== kind;

    // If the step is disabled, pass current_b through so the last entry of the
    // caller's level array always holds the output of the last active step.
    component pickEnabled = SelectBytes(32);
    for (var i = 0; i < 32; i++) {
        pickEnabled.a[i] <== current_b[i];
        pickEnabled.b[i] <== pickKind.out[i];
    }
    pickEnabled.sel <== enabled;
    for (var i = 0; i < 32; i++) {
        out_b[i] <== pickEnabled.out[i];
    }
}

// Climbs a Merkle path of pure 32-byte-hash siblings from a starting hash to a
// root. Used for the upper portions of both the sub-tree and master-tree paths,
// where all siblings are already 32-byte digests (no raw-sibling ambiguity).
// Inactive levels (enabled==0) propagate their input unchanged, so root_b always
// equals the output of the last active level regardless of MAX_HEIGHT.
template MerkleUpperPathBlake2s(MAX_HEIGHT) {
    signal input start_b[32];
    signal input siblings_b[MAX_HEIGHT][32];
    signal input siblingOnLeft[MAX_HEIGHT];
    signal input enabled[MAX_HEIGHT];
    signal output root_b[32];

    // Active levels must form a contiguous prefix; the path cannot skip levels.
    component flags = AssertContiguousEnabled(MAX_HEIGHT, 0);
    flags.enabled <== enabled;

    signal level_b[MAX_HEIGHT + 1][32];
    component dirBit[MAX_HEIGHT];
    component concat[MAX_HEIGHT];
    component h[MAX_HEIGHT];
    component pick[MAX_HEIGHT];

    for (var j = 0; j < 32; j++) {
        level_b[0][j] <== start_b[j];
    }

    // At each level: concatenate current hash with sibling in the correct order,
    // hash the 64-byte result with Blake2s, then select between the hash and the
    // pass-through based on enabled. Inactive levels must zero out their sibling
    // to prevent the prover from hiding data there.
    for (var i = 0; i < MAX_HEIGHT; i++) {
        dirBit[i] = AssertBit();
        dirBit[i].in <== siblingOnLeft[i];
        siblingOnLeft[i] * (1 - enabled[i]) === 0;

        concat[i] = ConcatFixed(32, 32);
        for (var j = 0; j < 32; j++) {
            concat[i].current_b[j] <== level_b[i][j];
            concat[i].sibling_b[j] <== siblings_b[i][j];
            siblings_b[i][j] * (1 - enabled[i]) === 0;
        }
        concat[i].siblingOnLeft <== siblingOnLeft[i];

        h[i] = Blake2s256Fixed(64);
        for (var j = 0; j < 64; j++) {
            h[i].in_b[j] <== concat[i].out_b[j];
        }

        pick[i] = SelectBytes(32);
        for (var j = 0; j < 32; j++) {
            pick[i].a[j] <== level_b[i][j];
            pick[i].b[j] <== h[i].out_b[j];
        }
        pick[i].sel <== enabled[i];
        for (var j = 0; j < 32; j++) {
            level_b[i + 1][j] <== pick[i].out[j];
        }
    }

    for (var j = 0; j < 32; j++) {
        root_b[j] <== level_b[MAX_HEIGHT][j];
    }
}

// Computes the master-tree leaf hash: Blake2s256(range_ascii_b[0..len] || sub_root_b).
// range_ascii_b has a variable length declared by range_ascii_len, but circuits
// require fixed-size inputs. The solution is to hash every possible prefix length
// in parallel and select the result whose length matches range_ascii_len via a
// one-hot multiplexer, at the cost of MAX_RANGE_ASCII_BYTES+1 Blake2s invocations.
template MasterLeafHash(MAX_RANGE_ASCII_BYTES) {
    signal input range_ascii_b[MAX_RANGE_ASCII_BYTES];
    signal input range_ascii_len;
    signal input sub_root_b[32];
    signal output out_b[32];

    // Build a one-hot indicator for each possible length (0..MAX_RANGE_ASCII_BYTES).
    // lenMatch[i]==1 iff range_ascii_len==i.
    component eqLen[MAX_RANGE_ASCII_BYTES + 1];
    signal lenMatch[MAX_RANGE_ASCII_BYTES + 1];
    signal lenMatchPrefix[MAX_RANGE_ASCII_BYTES + 1];

    for (var i = 0; i < MAX_RANGE_ASCII_BYTES + 1; i++) {
        eqLen[i] = EqualConst(i);
        eqLen[i].in <== range_ascii_len;
        lenMatch[i] <== eqLen[i].out;
    }

    // Prefix-sum of the one-hot flags must equal exactly 1, ensuring
    // range_ascii_len is in the valid range [0, MAX_RANGE_ASCII_BYTES].
    lenMatchPrefix[0] <== lenMatch[0];
    for (var i = 1; i < MAX_RANGE_ASCII_BYTES + 1; i++) {
        lenMatchPrefix[i] <== lenMatchPrefix[i - 1] + lenMatch[i];
    }
    lenMatchPrefix[MAX_RANGE_ASCII_BYTES] === 1;

    // Bytes at index >= range_ascii_len must be zero. The prefix sum turns the
    // one-hot vector into a step function: usedByte[i]==1 for i < len, 0 for i >= len.
    // Multiplying range_ascii_b[i] by (1-usedByte[i]) forces unused bytes to zero,
    // preventing a length-extension where the prover appends extra data.
    signal usedByte[MAX_RANGE_ASCII_BYTES];
    for (var i = 0; i < MAX_RANGE_ASCII_BYTES; i++) {
        usedByte[i] <== 1 - lenMatchPrefix[i];
        range_ascii_b[i] * (1 - usedByte[i]) === 0;
    }

    // Hash range_ascii_b[0..len] || sub_root_b for every possible prefix length.
    // Each hasher receives exactly len range_ascii_b bytes followed by 32 sub_root_b bytes.
    component hashers[MAX_RANGE_ASCII_BYTES + 1];
    signal candidateHashes_b[MAX_RANGE_ASCII_BYTES + 1][32];
    signal chosenHashes_b[MAX_RANGE_ASCII_BYTES + 1][32];

    for (var len = 0; len < MAX_RANGE_ASCII_BYTES + 1; len++) {
        hashers[len] = Blake2s256Fixed(32 + len);
        for (var i = 0; i < len; i++) {
            hashers[len].in_b[i] <== range_ascii_b[i];
        }
        for (var j = 0; j < 32; j++) {
            hashers[len].in_b[len + j] <== sub_root_b[j];
        }
        for (var j = 0; j < 32; j++) {
            candidateHashes_b[len][j] <== hashers[len].out_b[j];
        }
    }

    // Accumulate the correct hash using the one-hot selector: at each step,
    // if lenMatch[len]==1 the running value is replaced with candidateHashes_b[len],
    // otherwise it remains unchanged. After all steps the final entry holds
    // exactly the hash corresponding to the declared length.
    for (var j = 0; j < 32; j++) {
        chosenHashes_b[0][j] <== candidateHashes_b[0][j];
    }

    for (var len = 1; len < MAX_RANGE_ASCII_BYTES + 1; len++) {
        for (var j = 0; j < 32; j++) {
            chosenHashes_b[len][j] <== chosenHashes_b[len - 1][j] + lenMatch[len] * (candidateHashes_b[len][j] - chosenHashes_b[len - 1][j]);
        }
    }

    for (var j = 0; j < 32; j++) {
        out_b[j] <== chosenHashes_b[MAX_RANGE_ASCII_BYTES][j];
    }
}

// Encodes a variable-length byte field with a two-byte CBOR-style length prefix
// [0x00, len], producing an (MAX_BYTES + 2)-byte output.
// len is constrained to [0, MAX_BYTES] and bytes at index >= len are forced to
// zero, so the encoding is canonical: there is exactly one valid witness for any
// given (data_b, len) pair.
template FixedLenPrefixedField(MAX_BYTES) {
    signal input data_b[MAX_BYTES];
    signal input len;
    signal output out_b[MAX_BYTES + 2];

    component lenByte = AssertByte();
    lenByte.in <== len;

    // One-hot over all valid lengths; the sum must be exactly 1, confirming
    // len is in [0, MAX_BYTES] and not an out-of-range field element.
    component eqs[MAX_BYTES + 1];
    var eqSum = 0;
    for (var i = 0; i <= MAX_BYTES; i++) {
        eqs[i] = EqualConst(i);
        eqs[i].in <== len;
        eqSum += eqs[i].out;
    }
    eqSum === 1;

    component dataBytes = AssertBytes(MAX_BYTES);
    dataBytes.in <== data_b;

    // For each byte position i, if len <= i (i.e. any eqs[j] with j <= i is 1)
    // then data_b[i] must be zero. The nested loop checks all such j for each i,
    // ensuring no trailing non-zero bytes can follow the declared length.
    for (var i = 0; i < MAX_BYTES; i++) {
        for (var j = 0; j <= i; j++) {
            data_b[i] * eqs[j].out === 0;
        }
    }

    // Prepend the two-byte header and copy the data payload.
    out_b[0] <== 0;
    out_b[1] <== len;
    for (var i = 0; i < MAX_BYTES; i++) {
        out_b[i + 2] <== data_b[i];
    }
}

// Maps a 4-bit nibble (0-15) to its lowercase hex ASCII code.
// Digits 0-9 map to ASCII 48-57 ('0'-'9'); letters a-f map to ASCII 97-102 ('a'-'f').
// A one-hot accumulator builds both the output value and the range check
// (eqSum===1) in a single loop, avoiding a separate bounds assertion.
template NibbleToLowerHexAscii() {
    signal input in;
    signal output out;

    // Range-check: ToBits(4) fails if in >= 16.
    component bits = ToBits(4);
    bits.inp <== in;

    // For each possible nibble value i, eqs[i].out is 1 iff in==i.
    // ascii accumulates the weighted sum: exactly one term is non-zero,
    // contributing the correct ASCII code for the matching value.
    component eqs[16];
    var ascii = 0;
    var eqSum = 0;
    for (var i = 0; i < 16; i++) {
        eqs[i] = EqualConst(i);
        eqs[i].in <== in;
        eqSum += eqs[i].out;
        ascii += (i < 10 ? 48 + i : 87 + i) * eqs[i].out;
    }

    eqSum === 1;
    out <== ascii;
}

// Converts a single byte to two lowercase hex ASCII characters (high nibble first).
// Splits the byte into its two nibbles via bit decomposition, then delegates
// each nibble to NibbleToLowerHexAscii. The bit layout from ToBits is LSB-first,
// so bits 0-3 form the low nibble and bits 4-7 form the high nibble.
template ByteToLowerHexAscii() {
    signal input in;
    signal output high;
    signal output low;

    component bits = ToBits(8);
    bits.inp <== in;

    signal lowNibble;
    signal highNibble;

    // Reconstruct nibbles as integers from the LSB-first bit decomposition.
    lowNibble <== bits.out[0] + 2 * bits.out[1] + 4 * bits.out[2] + 8 * bits.out[3];
    highNibble <== bits.out[4] + 2 * bits.out[5] + 4 * bits.out[6] + 8 * bits.out[7];

    component highAscii = NibbleToLowerHexAscii();
    highAscii.in <== highNibble;
    high <== highAscii.out;

    component lowAscii = NibbleToLowerHexAscii();
    lowAscii.in <== lowNibble;
    low <== lowAscii.out;
}

// Packs BYTES_LEN bytes into a single field element using big-endian base-256
// encoding (Horner's method). Caller is responsible for ensuring the result
// fits within the field — this template is only safe for BYTES_LEN <= 31 on BN254.
template PackBytesToField(BYTES_LEN) {
    signal input in_b[BYTES_LEN];
    signal output out;

    signal acc[BYTES_LEN + 1];
    acc[0] <== 0;

    // Each iteration shifts the accumulator left by one byte (multiply by 256)
    // and appends the next byte, building the big-endian integer incrementally.
    for (var i = 0; i < BYTES_LEN; i++) {
        acc[i + 1] <== acc[i] * 256 + in_b[i];
    }

    out <== acc[BYTES_LEN];
}
