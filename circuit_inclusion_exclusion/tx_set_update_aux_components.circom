pragma circom 2.1.9;

include "vendor/poseidon255.circom";

// Packs 16 bytes (big-endian) into a single field element for public output.
template Pack16Bytes() {
    signal input in_b[16];
    signal output out;
    signal acc[17];

    acc[0] <== 0;
    for (var i = 0; i < 16; i++) {
        acc[i + 1] <== acc[i] * 256 + in_b[i];
    }
    out <== acc[16];
}

// Enforces that `in` is a valid bit (0 or 1).
template AssertBit() {
    signal input in;
    in * (in - 1) === 0;
}

// Decomposes `inp` into n bits (LSB-first) and reconstructs it as a soundness check,
// preventing underconstrained witnesses from assigning arbitrary bit values.
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

// Enforces that `in` is in [0, 255] by decomposing it into 8 bits.
template AssertByte() {
    signal input in;
    component bits = ToBits(8);
    bits.inp <== in;
}

/*
 * SparseMerkleRoot — recomputes the SMT root given a leaf value, the path
 * (bit-indexed by tx_id), and the sibling nodes along that path.
 *
 * Traversal runs leaf-to-root: level 0 is the leaf, level HEIGHT is the root.
 * The path arrays use root-to-leaf indexing, so at traversal level `level`
 * the relevant sibling is path_values[HEIGHT-1-level].
 *
 * At each level, path_indexes[depth] selects whether the current node is the
 * left child (index=0) or right child (index=1), placing the sibling on the
 * opposite side before hashing with Poseidon255.
 */
template SparseMerkleRoot(HEIGHT) {
    signal input leaf;
    signal input path_indexes[HEIGHT];
    signal input path_values[HEIGHT];
    signal output root;

    signal current[HEIGHT + 1];
    signal left[HEIGHT];
    signal right[HEIGHT];

    component hashers[HEIGHT];

    current[0] <== leaf;

    // Walk from leaf to root, hashing current node with its sibling at each level.
    for (var level = 0; level < HEIGHT; level++) {
        var depth = HEIGHT - 1 - level;
        hashers[level] = Poseidon255(2);

        // If path_indexes[depth] == 1: current is right child, sibling is left.
        // If path_indexes[depth] == 0: current is left child, sibling is right.
        left[level]  <== current[level] + path_indexes[depth] * (path_values[depth] - current[level]);
        right[level] <== path_values[depth] + path_indexes[depth] * (current[level] - path_values[depth]);

        hashers[level].in[0] <== left[level];
        hashers[level].in[1] <== right[level];

        current[level + 1] <== hashers[level].out;
    }

    root <== current[HEIGHT];
}
