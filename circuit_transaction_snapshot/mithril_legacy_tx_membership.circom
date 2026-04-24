pragma circom 2.1.9;

/*
The Merkle path from the tx leaf to the master root is split into four segments:

  sub_prefix   — the bottom-most steps of the sub-tree path, where siblings
                 may be raw 64-byte ASCII strings (other tx hashes) or
                 already-hashed 32-byte values; step kind selects which.
  sub_upper    — the remaining steps to the sub-tree root; all siblings are
                 32-byte hashes.
  master_prefix — steps from the master-tree leaf upward; in practice always
                  hash-typed (kind == 1), which the circuit enforces.
  master_upper  — the remaining steps to the master root.

The circuit succeeds iff the recomputed master root equals expected_root.
Public outputs expose the tx hash, sub_root, and master_root as pairs of
128-bit field elements so they can be verified on-chain.
*/

include "mithril_legacy_tx_membership_aux_components.circom";

template MithrilLegacyTxMembership(
    MAX_SUB_PREFIX_LEN,
    MAX_SUB_UPPER_HEIGHT,
    MAX_RANGE_ASCII_BYTES,
    MAX_MASTER_PREFIX_LEN,
    MAX_MASTER_UPPER_HEIGHT
) {
    signal input cardano_tx_hash_b[32];

    signal input sub_prefix_kinds[MAX_SUB_PREFIX_LEN];
    signal input sub_prefix_raw_siblings_b[MAX_SUB_PREFIX_LEN][64];
    signal input sub_prefix_hash_siblings_b[MAX_SUB_PREFIX_LEN][32];
    signal input sub_prefix_sibling_on_left[MAX_SUB_PREFIX_LEN];
    signal input sub_prefix_enabled[MAX_SUB_PREFIX_LEN];

    signal input sub_upper_siblings_b[MAX_SUB_UPPER_HEIGHT][32];
    signal input sub_upper_sibling_on_left[MAX_SUB_UPPER_HEIGHT];
    signal input sub_upper_enabled[MAX_SUB_UPPER_HEIGHT];

    signal input range_ascii_b[MAX_RANGE_ASCII_BYTES];
    signal input range_ascii_len;

    signal input master_prefix_kinds[MAX_MASTER_PREFIX_LEN];
    signal input master_prefix_raw_siblings_b[MAX_MASTER_PREFIX_LEN][64];
    signal input master_prefix_hash_siblings_b[MAX_MASTER_PREFIX_LEN][32];
    signal input master_prefix_sibling_on_left[MAX_MASTER_PREFIX_LEN];
    signal input master_prefix_enabled[MAX_MASTER_PREFIX_LEN];

    signal input master_upper_siblings_b[MAX_MASTER_UPPER_HEIGHT][32];
    signal input master_upper_sibling_on_left[MAX_MASTER_UPPER_HEIGHT];
    signal input master_upper_enabled[MAX_MASTER_UPPER_HEIGHT];

    signal input expected_root_b[32];

    signal cardano_tx_hash_signal_b[32];
    signal sub_root_b[32];
    signal master_root_b[32];

    // Each 32-byte hash is exposed as two 128-bit halves because a BN254
    // field element safely holds at most 31 bytes as a single integer.
    signal output cardano_tx_hash_hi;
    signal output cardano_tx_hash_lo;
    signal output sub_root_hi;
    signal output sub_root_lo;
    signal output master_root_hi;
    signal output master_root_lo;

    // Constrain all public inputs to valid byte ranges so no field-overflow
    // tricks can be used to forge a witness.
    component cardanoTxHashBytes = AssertBytes(32);
    component rangeBytes = AssertBytes(MAX_RANGE_ASCII_BYTES);
    component expectedRootBytes = AssertBytes(32);

    for (var i = 0; i < 32; i++) {
        cardanoTxHashBytes.in[i] <== cardano_tx_hash_b[i];
        cardano_tx_hash_signal_b[i] <== cardano_tx_hash_b[i];
    }
    for (var i = 0; i < MAX_RANGE_ASCII_BYTES; i++) {
        rangeBytes.in[i] <== range_ascii_b[i];
    }
    for (var i = 0; i < 32; i++) {
        expectedRootBytes.in[i] <== expected_root_b[i];
    }

    // The sub-tree leaf is not the raw tx hash bytes but its lowercase-hex
    // ASCII encoding (64 characters). Derive it deterministically from the
    // 32-byte input so the prover cannot supply an arbitrary leaf value.
    signal lockingTxHashAscii_b[64];
    component lockingTxHashToAscii[32];
    for (var i = 0; i < 32; i++) {
        lockingTxHashToAscii[i] = ByteToLowerHexAscii();
        lockingTxHashToAscii[i].in <== cardano_tx_hash_signal_b[i];
        lockingTxHashAscii_b[2 * i] <== lockingTxHashToAscii[i].high;
        lockingTxHashAscii_b[2 * i + 1] <== lockingTxHashToAscii[i].low;
    }

    // Each prefix's enabled flags must form a contiguous block of 1s starting
    // at index 0, with no gaps. This prevents the prover from skipping
    // intermediate Merkle steps while keeping later ones active.
    component subPrefixFlags = AssertContiguousEnabled(MAX_SUB_PREFIX_LEN, 1);
    subPrefixFlags.enabled <== sub_prefix_enabled;

    component masterPrefixFlags = AssertContiguousEnabled(MAX_MASTER_PREFIX_LEN, 1);
    masterPrefixFlags.enabled <== master_prefix_enabled;

    // Constrain every sibling byte in the sub-tree prefix to [0, 255].
    // Without this, a prover could embed large field elements that happen
    // to produce the right hash output through overflow arithmetic.
    component subRawBytes[MAX_SUB_PREFIX_LEN];
    component subHashBytes[MAX_SUB_PREFIX_LEN];
    for (var i = 0; i < MAX_SUB_PREFIX_LEN; i++) {
        subRawBytes[i] = AssertBytes(64);
        subHashBytes[i] = AssertBytes(32);
        for (var j = 0; j < 64; j++) {
            subRawBytes[i].in[j] <== sub_prefix_raw_siblings_b[i][j];
        }
        for (var j = 0; j < 32; j++) {
            subHashBytes[i].in[j] <== sub_prefix_hash_siblings_b[i][j];
        }
    }

    // Same byte-range check for master-tree prefix siblings. Additionally,
    // every enabled master step must be hash-typed (kind == 1): raw-sibling
    // steps have never been observed in the master tree and are disallowed
    // to keep the constraint system tight.
    component masterRawBytes[MAX_MASTER_PREFIX_LEN];
    component masterHashBytes[MAX_MASTER_PREFIX_LEN];
    for (var i = 0; i < MAX_MASTER_PREFIX_LEN; i++) {
        masterRawBytes[i] = AssertBytes(64);
        masterHashBytes[i] = AssertBytes(32);
        for (var j = 0; j < 64; j++) {
            masterRawBytes[i].in[j] <== master_prefix_raw_siblings_b[i][j];
        }
        for (var j = 0; j < 32; j++) {
            masterHashBytes[i].in[j] <== master_prefix_hash_siblings_b[i][j];
        }
        master_prefix_kinds[i] === master_prefix_enabled[i];
    }

    // Walk the sub-tree typed prefix starting from the 64-byte ASCII leaf.
    // The first step is special: it accepts a raw 64-byte sibling (another
    // tx hash) or a 32-byte hash sibling depending on kind. Subsequent steps
    // always start from a 32-byte hash produced by the previous step.
    component subFirst = TypedPrefixFirstStep(64, 64);
    component subStep[MAX_SUB_PREFIX_LEN];
    for (var i = 0; i < 64; i++) {
        subFirst.current_b[i] <== lockingTxHashAscii_b[i];
        subFirst.rawSibling_b[i] <== sub_prefix_raw_siblings_b[0][i];
    }
    for (var i = 0; i < 32; i++) {
        subFirst.hashSibling_b[i] <== sub_prefix_hash_siblings_b[0][i];
    }
    subFirst.kind <== sub_prefix_kinds[0];
    subFirst.siblingOnLeft <== sub_prefix_sibling_on_left[0];

    signal subPrefixLevel_b[MAX_SUB_PREFIX_LEN][32];
    for (var j = 0; j < 32; j++) {
        subPrefixLevel_b[0][j] <== subFirst.out_b[j];
    }

    // Chain the remaining sub-tree prefix steps. Disabled steps (enabled==0)
    // pass their input through unchanged, so the last entry of subPrefixLevel_b
    // always holds the output of the last active step regardless of how many
    // steps the actual path uses.
    for (var i = 1; i < MAX_SUB_PREFIX_LEN; i++) {
        subStep[i] = TypedPrefixHashedStep(64);
        for (var j = 0; j < 32; j++) {
            subStep[i].current_b[j] <== subPrefixLevel_b[i - 1][j];
            subStep[i].hashSibling_b[j] <== sub_prefix_hash_siblings_b[i][j];
        }
        for (var j = 0; j < 64; j++) {
            subStep[i].rawSibling_b[j] <== sub_prefix_raw_siblings_b[i][j];
        }
        subStep[i].kind <== sub_prefix_kinds[i];
        subStep[i].siblingOnLeft <== sub_prefix_sibling_on_left[i];
        subStep[i].enabled <== sub_prefix_enabled[i];
        for (var j = 0; j < 32; j++) {
            subPrefixLevel_b[i][j] <== subStep[i].out_b[j];
        }
    }

    // Continue up the sub-tree through the upper path (pure 32-byte siblings)
    // to reach sub_root_b — the root of the sub-tree that contains the tx.
    component subUpper = MerkleUpperPathBlake2s(MAX_SUB_UPPER_HEIGHT);
    for (var j = 0; j < 32; j++) {
        subUpper.start_b[j] <== subPrefixLevel_b[MAX_SUB_PREFIX_LEN - 1][j];
    }
    for (var i = 0; i < MAX_SUB_UPPER_HEIGHT; i++) {
        subUpper.siblingOnLeft[i] <== sub_upper_sibling_on_left[i];
        subUpper.enabled[i] <== sub_upper_enabled[i];
        for (var j = 0; j < 32; j++) {
            subUpper.siblings_b[i][j] <== sub_upper_siblings_b[i][j];
        }
    }
    for (var j = 0; j < 32; j++) {
        sub_root_b[j] <== subUpper.root_b[j];
    }

    // Compute the master-tree leaf that commits to this sub-tree:
    // Blake2s256(range_ascii_b || sub_root_b). range_ascii_b is the variable-length
    // ASCII string describing the tx-hash range of the sub-tree (e.g.
    // "0000..ffff"), and sub_root_b binds it to the sub-tree we just verified.
    component masterLeaf = MasterLeafHash(MAX_RANGE_ASCII_BYTES);
    for (var i = 0; i < MAX_RANGE_ASCII_BYTES; i++) {
        masterLeaf.range_ascii_b[i] <== range_ascii_b[i];
    }
    for (var j = 0; j < 32; j++) {
        masterLeaf.sub_root_b[j] <== sub_root_b[j];
    }
    masterLeaf.range_ascii_len <== range_ascii_len;

    // Walk the master-tree typed prefix starting from the master leaf.
    // All steps are hash-typed (enforced above), so each step hashes the
    // current 32-byte value with a 32-byte sibling to climb the master tree.
    signal masterPrefixLevel_b[MAX_MASTER_PREFIX_LEN + 1][32];
    for (var j = 0; j < 32; j++) {
        masterPrefixLevel_b[0][j] <== masterLeaf.out_b[j];
    }

    component masterStep[MAX_MASTER_PREFIX_LEN];
    for (var i = 0; i < MAX_MASTER_PREFIX_LEN; i++) {
        masterStep[i] = TypedPrefixHashedStep(64);
        for (var j = 0; j < 32; j++) {
            masterStep[i].current_b[j] <== masterPrefixLevel_b[i][j];
            masterStep[i].hashSibling_b[j] <== master_prefix_hash_siblings_b[i][j];
        }
        for (var j = 0; j < 64; j++) {
            masterStep[i].rawSibling_b[j] <== master_prefix_raw_siblings_b[i][j];
        }
        masterStep[i].kind <== master_prefix_kinds[i];
        masterStep[i].siblingOnLeft <== master_prefix_sibling_on_left[i];
        masterStep[i].enabled <== master_prefix_enabled[i];
        for (var j = 0; j < 32; j++) {
            masterPrefixLevel_b[i + 1][j] <== masterStep[i].out_b[j];
        }
    }

    // Climb the master-tree upper path to reach master_root_b, then assert it
    // equals expected_root_b. This is the core membership check: the proof is
    // valid iff the entire two-level path reconstructs the publicly known root.
    component masterUpper = MerkleUpperPathBlake2s(MAX_MASTER_UPPER_HEIGHT);
    for (var j = 0; j < 32; j++) {
        masterUpper.start_b[j] <== masterPrefixLevel_b[MAX_MASTER_PREFIX_LEN][j];
    }
    for (var i = 0; i < MAX_MASTER_UPPER_HEIGHT; i++) {
        masterUpper.siblingOnLeft[i] <== master_upper_sibling_on_left[i];
        masterUpper.enabled[i] <== master_upper_enabled[i];
        for (var j = 0; j < 32; j++) {
            masterUpper.siblings_b[i][j] <== master_upper_siblings_b[i][j];
        }
    }
    for (var j = 0; j < 32; j++) {
        master_root_b[j] <== masterUpper.root_b[j];
        master_root_b[j] === expected_root_b[j];
    }

    // Pack the three 32-byte hashes into pairs of 128-bit field elements for
    // the public output. Splitting at the 16-byte boundary keeps each half
    // well within the BN254 field size and makes on-chain verification cheap.
    component packCardanoTxHashHi = PackBytesToField(16);
    component packCardanoTxHashLo = PackBytesToField(16);
    component packSubRootHi = PackBytesToField(16);
    component packSubRootLo = PackBytesToField(16);
    component packMasterRootHi = PackBytesToField(16);
    component packMasterRootLo = PackBytesToField(16);

    for (var i = 0; i < 16; i++) {
        packCardanoTxHashHi.in_b[i] <== cardano_tx_hash_signal_b[i];
        packCardanoTxHashLo.in_b[i] <== cardano_tx_hash_signal_b[16 + i];
        packSubRootHi.in_b[i] <== sub_root_b[i];
        packSubRootLo.in_b[i] <== sub_root_b[16 + i];
        packMasterRootHi.in_b[i] <== master_root_b[i];
        packMasterRootLo.in_b[i] <== master_root_b[16 + i];
    }

    cardano_tx_hash_hi <== packCardanoTxHashHi.out;
    cardano_tx_hash_lo <== packCardanoTxHashLo.out;
    sub_root_hi <== packSubRootHi.out;
    sub_root_lo <== packSubRootLo.out;
    master_root_hi <== packMasterRootHi.out;
    master_root_lo <== packMasterRootLo.out;
}
