pragma circom 2.1.9;

/*
Transaction-set sparse Merkle update circuit.

Parameters:
- tree height: 256 (one level per bit of the 32-byte tx_id)
- internal hash: Poseidon255(left_fe, right_fe)  [BLS12-381, arity 2]
- empty leaf:   field element 0
- present leaf: field element 1
- path: tx_id big-endian bits, ordered root-to-leaf
- mt_path_values[0] is the sibling closest to the root;
  mt_path_values[255] is the sibling closest to the leaf

Public outputs (4 field elements):
  [0] tx_id_hi       — tx_id bytes [0..15] packed big-endian
  [1] tx_id_lo       — tx_id bytes [16..31] packed big-endian
  [2] mt_root_in_out — old SMT root (tx_id must be absent)
  [3] mt_root_out_out — new SMT root (tx_id must be present)

The Poseidon255 circom template is vendored from:
  https://github.com/jmagan/poseidon-bls12381-circom
Parameters: t=3, N_F=8, N_P=56, S-box x^5, 128-bit security over BLS12-381.
The corresponding Rust implementation lives in `tx_set_update.rs`.
*/

include "tx_set_update_aux_components.circom";

template TxSetUpdate() {
    var HEIGHT = 256;

    // tx_id is still represented as 32 bytes for the packed public outputs.
    signal input tx_id_b[32];

    // Roots and path values are native field elements (not byte arrays).
    signal input mt_root_in;
    signal input mt_root_out;
    signal input mt_path_indexes[HEIGHT];
    signal input mt_path_values[HEIGHT];

    // Public outputs: tx_id packed as hi/lo, roots as field elements.
    signal output tx_id_hi;
    signal output tx_id_lo;
    signal output mt_root_in_out;
    signal output mt_root_out_out;

    // ── Input validation ────────────────────────────────────────────────────
    // Enforce that every tx_id byte is in [0,255] and extract its bits.
    // The big-endian bits are also constrained to equal the path indexes,
    // tying the Merkle path to this specific transaction ID and preventing a
    // valid path for a different key from being substituted.

    component txIdByteChecks[32];
    component txIdBits[32];

    for (var byte = 0; byte < 32; byte++) {
        txIdByteChecks[byte] = AssertByte();
        txIdByteChecks[byte].in <== tx_id_b[byte];

        txIdBits[byte] = ToBits(8);
        txIdBits[byte].inp <== tx_id_b[byte];
    }

    // Enforce that mt_path_indexes == big-endian bits of tx_id (root-to-leaf order).
    component pathIndexBits[HEIGHT];
    for (var depth = 0; depth < HEIGHT; depth++) {
        pathIndexBits[depth] = AssertBit();
        pathIndexBits[depth].in <== mt_path_indexes[depth];

        var txByte    = depth \ 8;
        var bitInByte = 7 - (depth % 8);
        mt_path_indexes[depth] === txIdBits[txByte].out[bitInByte];
    }

    // ── SMT membership proofs ───────────────────────────────────────────────
    // Prove non-membership (leaf=0) against mt_root_in: tx_id was not yet used.
    // Prove membership (leaf=1) against mt_root_out: tx_id is now marked used.
    // Both proofs share the same path, so they describe the same leaf slot before
    // and after the update — ensuring the transition is atomic and correctly scoped.

    component inPath  = SparseMerkleRoot(HEIGHT);
    component outPath = SparseMerkleRoot(HEIGHT);

    inPath.leaf  <== 0;
    outPath.leaf <== 1;

    for (var depth = 0; depth < HEIGHT; depth++) {
        inPath.path_indexes[depth]  <== mt_path_indexes[depth];
        outPath.path_indexes[depth] <== mt_path_indexes[depth];

        inPath.path_values[depth]  <== mt_path_values[depth];
        outPath.path_values[depth] <== mt_path_values[depth];
    }

    inPath.root  === mt_root_in;
    outPath.root === mt_root_out;

    // ── Public output packing ───────────────────────────────────────────────
    // Pack tx_id and roots into field elements consumed by the Groth16 verifier.

    component packTxHi = Pack16Bytes();
    component packTxLo = Pack16Bytes();

    for (var i = 0; i < 16; i++) {
        packTxHi.in_b[i] <== tx_id_b[i];
        packTxLo.in_b[i] <== tx_id_b[16 + i];
    }

    tx_id_hi        <== packTxHi.out;
    tx_id_lo        <== packTxLo.out;
    mt_root_in_out  <== mt_root_in;
    mt_root_out_out <== mt_root_out;
}
