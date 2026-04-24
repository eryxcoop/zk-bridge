pragma circom 2.1.9;

/*
Experimental Lagrange-style Cardano transaction membership circuit.

This file is intentionally standalone and is not wired into the current repo
flows. It exists as a design/implementation experiment for a future
Lagrange-compatible transaction membership circuit while preserving useful
legacy semantics from `mithril_legacy_tx_membership.circom`.

What does not changed compared to the legacy circuit:

- the transaction identity is the real Cardano `cardano_tx_hash`
- public digest packing still uses 16-byte big-endian halves
- the public statement is shaped to converge toward
  `cardano_tx_hash + sub_root + snapshot_root`

What changes in this experiment:

- the membership proof is modeled as a single Merkle path:
`leaf + leaf_index + siblings[MAX_DEPTH]`.
- there is no recursive `sub-tree + master-tree` structure.
- there is no `range_ascii`, no typed prefix, and no MMR/MKMap flattening.
- the computed leaf hash is surfaced as `sub_root`
- the computed root is surfaced as `snapshot_root`

Hashing note:

- the Merkle hash used here is intentionally MOCKED.
- `MockMidnightPoseidon*` now uses `Poseidon255` over field elements as a
  structural placeholder.
- the real function that should replace it is the Midnight Poseidon variant
used by Mithril's `future_snark` path, optimized for `bls12-381`.
- this file is therefore shape-compatible with the intended design, but not
cryptographically compatible with the real Lagrange/Midnight tree yet.
- this file is also not `tx prove` compatible yet because the circuit inputs
  and path model do not match the live Mithril proof normalizer/exporter

Circuit inputs:

- `cardano_tx_hash[32]`
- `leaf_index`
- `siblings[MAX_DEPTH][2]`
- `expected_root[2]`

Circuit outputs exposed by `signal output`:

- `cardano_tx_hash_hi`
- `cardano_tx_hash_lo`
- `sub_root_hi`
- `sub_root_lo`
- `snapshot_root_hi`
- `snapshot_root_lo`

Compiled experimental entrypoint:

component main = MithrilLagrangeTxMembershipExperimental(32);
*/

include "sha256_bytes.circom";
include "../circuit_inclusion_exclusion/vendor/poseidon255.circom";

// Decomposes a field element into its n least significant bits.
// Used to extract the left/right direction at each level of the Merkle path
// from the leaf index.
template ToBits(n) {
    signal input inp;
    signal output out[n];

    var sum = 0;
    for (var i = 0; i < n; i++) {
        out[i] <-- (inp >> i) & 1;
        out[i] * (1 - out[i]) === 0;
        sum += (1 << i) * out[i];
    }

    inp === sum;
}

// Constrains a single signal to be in the range [0, 255].
template AssertByte() {
    signal input in;
    component b = ToBits(8);
    b.inp <== in;
}

// Constrains an array of N signals to each be in the range [0, 255].
template AssertBytes(N) {
    signal input in[N];
    component checks[N];

    for (var i = 0; i < N; i++) {
        checks[i] = AssertByte();
        checks[i].in <== in[i];
    }
}

// Constrains a signal to be 0 or 1.
template AssertBit() {
    signal input in;
    in * (in - 1) === 0;
}

// Packs an array of bytes into a single field element by interpreting them
// as a big-endian integer. Used to convert byte arrays into field elements
// before hashing with Poseidon.
template PackBytesToField(BYTES_LEN) {
    signal input in[BYTES_LEN];
    signal output out;

    signal acc[BYTES_LEN + 1];
    acc[0] <== 0;

    for (var i = 0; i < BYTES_LEN; i++) {
        acc[i + 1] <== acc[i] * 256 + in[i];
    }

    out <== acc[BYTES_LEN];
}

// Computes a mocked Lagrange-style digest of a 32-byte value, producing a
// (hi, lo) pair of field elements. The input bytes are split into two 16-byte
// halves, each packed into a field element, and then hashed with Poseidon255.
// This is a placeholder for the real Midnight Poseidon hash that Mithril will
// use in its future_snark scheme.
template MockMidnightPoseidonDigest32FromBytes() {
    signal input in[32];
    signal output hi;
    signal output lo;

    component bytes = AssertBytes(32);
    bytes.in <== in;

    component packHi = PackBytesToField(16);
    component packLo = PackBytesToField(16);
    for (var i = 0; i < 16; i++) {
        packHi.in[i] <== in[i];
        packLo.in[i] <== in[16 + i];
    }

    component hHi = Poseidon255(2);
    component hLo = Poseidon255(2);

    hHi.in[0] <== packHi.out;
    hHi.in[1] <== packLo.out;
    hLo.in[0] <== packLo.out;
    hLo.in[1] <== packHi.out;

    hi <== hHi.out;
    lo <== hLo.out;
}

// Merges two (hi, lo) Poseidon digests into a single parent digest, selecting
// left/right order based on current_is_right. This is one step of the Merkle
// path: given the current node and its sibling, it produces the parent node.
// Domain separation between hi and lo is achieved by reversing the input order
// in the second Poseidon call.
template MockMidnightPoseidonDigest32Merge() {
    signal input current[2];
    signal input sibling[2];
    signal input current_is_right;
    signal output out[2];

    component bit = AssertBit();
    bit.in <== current_is_right;

    signal left[2];
    signal right[2];

    for (var i = 0; i < 2; i++) {
        left[i] <== current[i] + current_is_right * (sibling[i] - current[i]);
        right[i] <== sibling[i] + current_is_right * (current[i] - sibling[i]);
    }

    component hHi = Poseidon255(4);
    component hLo = Poseidon255(4);

    hHi.in[0] <== left[0];
    hHi.in[1] <== left[1];
    hHi.in[2] <== right[0];
    hHi.in[3] <== right[1];

    // Domain separation by reversing the pair order in the second sponge.
    hLo.in[0] <== right[0];
    hLo.in[1] <== right[1];
    hLo.in[2] <== left[0];
    hLo.in[3] <== left[1];

    out[0] <== hHi.out;
    out[1] <== hLo.out;
}

// Verifies a Merkle path of depth MAX_DEPTH. Starting from the leaf, it walks
// up the tree by merging the current node with its sibling at each level. The
// direction (left or right) at each level is determined by the corresponding
// bit of the leaf index. The final result is the recomputed root.
template MerklePathMockMidnightPoseidon(MAX_DEPTH) {
    signal input leaf[2];
    signal input leaf_index;
    signal input siblings[MAX_DEPTH][2];
    signal output root[2];

    // Decompose the leaf index into bits to determine left/right at each level.
    component indexBits = ToBits(MAX_DEPTH);
    indexBits.inp <== leaf_index;

    signal level[MAX_DEPTH + 1][2];
    component steps[MAX_DEPTH];

    for (var j = 0; j < 2; j++) {
        level[0][j] <== leaf[j];
    }

    for (var i = 0; i < MAX_DEPTH; i++) {
        steps[i] = MockMidnightPoseidonDigest32Merge();
        for (var k = 0; k < 2; k++) {
            steps[i].current[k] <== level[i][k];
            steps[i].sibling[k] <== siblings[i][k];
        }
        steps[i].current_is_right <== indexBits.out[i];
        for (var m = 0; m < 2; m++) {
            level[i + 1][m] <== steps[i].out[m];
        }
    }

    for (var m = 0; m < 2; m++) {
        root[m] <== level[MAX_DEPTH][m];
    }
}

// Main circuit. Proves that a Cardano transaction identified by cardano_tx_hash
// is a leaf in a Merkle tree whose root matches expected_root.
//
// The circuit:
// 1. Hashes cardano_tx_hash into a (hi, lo) field element pair to produce sub_root,
//    preserving the same public output shape as the legacy circuit.
// 2. Walks the Merkle path from sub_root up to the tree root using the supplied
//    siblings and leaf_index.
// 3. Asserts that the recomputed root matches expected_root.
// 4. Exposes cardano_tx_hash, sub_root, and snapshot_root as packed public outputs.
template MithrilLagrangeTxMembershipExperimental(MAX_DEPTH) {
    signal input cardano_tx_hash[32];

    signal input leaf_index;
    signal input siblings[MAX_DEPTH][2];
    signal input expected_root[2];

    signal cardano_tx_hash_signal[32];
    signal sub_root[2];
    signal snapshot_root[2];

    signal output cardano_tx_hash_hi;
    signal output cardano_tx_hash_lo;
    signal output sub_root_hi;
    signal output sub_root_lo;
    signal output snapshot_root_hi;
    signal output snapshot_root_lo;

    // Constrain all tx hash bytes to [0, 255].
    component cardanoTxHashBytes = AssertBytes(32);
    cardanoTxHashBytes.in <== cardano_tx_hash;

    for (var i = 0; i < 32; i++) {
        cardano_tx_hash_signal[i] <== cardano_tx_hash[i];
    }

    // Hash the transaction hash bytes into a (hi, lo) field element pair.
    // This becomes the leaf of the Merkle tree and is also exposed as sub_root,
    // keeping the same public output shape as the legacy circuit.
    component deriveSubRoot = MockMidnightPoseidonDigest32FromBytes();
    deriveSubRoot.in <== cardano_tx_hash_signal;
    sub_root[0] <== deriveSubRoot.hi;
    sub_root[1] <== deriveSubRoot.lo;

    // Walk the Merkle path from the leaf up to the root.
    component path = MerklePathMockMidnightPoseidon(MAX_DEPTH);
    path.leaf <== sub_root;
    path.leaf_index <== leaf_index;
    path.siblings <== siblings;

    // Pack the transaction hash bytes into two field elements for the public output.
    component packCardanoTxHashHi = PackBytesToField(16);
    component packCardanoTxHashLo = PackBytesToField(16);

    for (var h = 0; h < 16; h++) {
        packCardanoTxHashHi.in[h] <== cardano_tx_hash_signal[h];
        packCardanoTxHashLo.in[h] <== cardano_tx_hash_signal[16 + h];
    }

    // Assert that the recomputed root matches the expected root from the certificate.
    snapshot_root[0] <== path.root[0];
    snapshot_root[1] <== path.root[1];
    snapshot_root[0] === expected_root[0];
    snapshot_root[1] === expected_root[1];

    cardano_tx_hash_hi <== packCardanoTxHashHi.out;
    cardano_tx_hash_lo <== packCardanoTxHashLo.out;
    sub_root_hi <== sub_root[0];
    sub_root_lo <== sub_root[1];
    snapshot_root_hi <== snapshot_root[0];
    snapshot_root_lo <== snapshot_root[1];
}

component main = MithrilLagrangeTxMembershipExperimental(32);
