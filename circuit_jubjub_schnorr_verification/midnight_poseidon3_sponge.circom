pragma circom 2.1.9;

/*
Midnight-compatible Poseidon transcript helper for `midnight_curves::Fq`.

Why this exists: Mithril's Jubjub Schnorr uses `PoseidonChip<JubjubBase>`,
which is a fixed sponge with:
  - WIDTH = 3
  - RATE = 2
  - NB_FULL_ROUNDS = 8
  - NB_PARTIAL_ROUNDS = 60
  - an explicit `input_len` domain separator in the capacity lane
  - chunked absorption over 2 inputs at a time

This file mirrors the *fixed-size HashCPU* behavior used upstream:

    let mut register = [0, 0, input_len];
    for chunk in inputs.chunks(2) {
        register[0] += chunk[0];
        if chunk.len() > 1 { register[1] += chunk[1]; }
        permutation(register);
    }
    output = register[0]

The round schedule also mirrors Midnight's shifted-round implementation:
    - add ROUND_CONSTANTS[0] before the permutation starts
    - each round applies the S-box first, then the linear layer
    - the linear layer adds ROUND_CONSTANTS[round + 1]
    - except the very last round, which adds `[0, 0, 0]`
    - partial rounds exponentiate only the last lane (`state[2]`)
*/

include "midnight_poseidon3_constants.circom";

function midnightPoseidonWidth() {
    return 3;
}

function midnightPoseidonRate() {
    return 2;
}

function midnightPoseidonFullRounds() {
    return 8;
}

function midnightPoseidonPartialRounds() {
    return 60;
}

template MidnightPoseidonX5() {
    signal input in;
    signal output out;

    signal in2;
    signal in4;

    in2 <== in * in;
    in4 <== in2 * in2;
    out <== in4 * in;
}

template MidnightPoseidon3FullRound(roundIndex, useZeroConstants) {
    signal input in[3];
    signal output out[3];

    var RC[68][3] = midnightPoseidon3RoundConstants();
    var MDS[3][3] = midnightPoseidon3Mds();

    component sbox[3];

    for (var i = 0; i < 3; i++) {
        sbox[i] = MidnightPoseidonX5();
        sbox[i].in <== in[i];
    }

    for (var row = 0; row < 3; row++) {
        var constant = useZeroConstants ? 0 : RC[roundIndex + 1][row];
        out[row] <== constant
            + MDS[row][0] * sbox[0].out
            + MDS[row][1] * sbox[1].out
            + MDS[row][2] * sbox[2].out;
    }
}

template MidnightPoseidon3PartialRound(roundIndex) {
    signal input in[3];
    signal output out[3];

    var RC[68][3] = midnightPoseidon3RoundConstants();
    var MDS[3][3] = midnightPoseidon3Mds();

    component sbox = MidnightPoseidonX5();
    sbox.in <== in[2];

    for (var row = 0; row < 3; row++) {
        out[row] <== RC[roundIndex + 1][row]
            + MDS[row][0] * in[0]
            + MDS[row][1] * in[1]
            + MDS[row][2] * sbox.out;
    }
}

template MidnightPoseidon3Permutation() {
    signal input state_in[3];
    signal output state_out[3];

    var RC[68][3] = midnightPoseidon3RoundConstants();

    signal after_initial_constants[3];
    for (var i = 0; i < 3; i++) {
        after_initial_constants[i] <== state_in[i] + RC[0][i];
    }

    component first_full_rounds[4];
    for (var round = 0; round < 4; round++) {
        first_full_rounds[round] = MidnightPoseidon3FullRound(round, 0);
        for (var lane = 0; lane < 3; lane++) {
            if (round == 0) {
                first_full_rounds[round].in[lane] <== after_initial_constants[lane];
            } else {
                first_full_rounds[round].in[lane] <== first_full_rounds[round - 1].out[lane];
            }
        }
    }

    component partial_rounds[60];
    for (var round = 0; round < 60; round++) {
        partial_rounds[round] = MidnightPoseidon3PartialRound(4 + round);
        for (var lane = 0; lane < 3; lane++) {
            if (round == 0) {
                partial_rounds[round].in[lane] <== first_full_rounds[3].out[lane];
            } else {
                partial_rounds[round].in[lane] <== partial_rounds[round - 1].out[lane];
            }
        }
    }

    component second_full_rounds[4];
    for (var round = 0; round < 4; round++) {
        second_full_rounds[round] = MidnightPoseidon3FullRound(64 + round, round == 3 ? 1 : 0);
        for (var lane = 0; lane < 3; lane++) {
            if (round == 0) {
                second_full_rounds[round].in[lane] <== partial_rounds[59].out[lane];
            } else {
                second_full_rounds[round].in[lane] <== second_full_rounds[round - 1].out[lane];
            }
        }
    }

    for (var i = 0; i < 3; i++) {
        state_out[i] <== second_full_rounds[3].out[i];
    }
}

template MidnightPoseidonFixedSponge(nInputs, nChunks) {
    signal input in[nInputs];
    signal output out;

    signal absorb_state[nChunks][3];
    component permutation[nChunks];

    for (var chunk = 0; chunk < nChunks; chunk++) {
        var leftIndex = chunk * 2;
        var rightIndex = leftIndex + 1;

        permutation[chunk] = MidnightPoseidon3Permutation();

        if (chunk == 0) {
            absorb_state[chunk][0] <== in[leftIndex];
            if (rightIndex < nInputs) {
                absorb_state[chunk][1] <== in[rightIndex];
            } else {
                absorb_state[chunk][1] <== 0;
            }
            absorb_state[chunk][2] <== nInputs;
        } else {
            absorb_state[chunk][0] <== permutation[chunk - 1].state_out[0] + in[leftIndex];
            if (rightIndex < nInputs) {
                absorb_state[chunk][1] <== permutation[chunk - 1].state_out[1] + in[rightIndex];
            } else {
                absorb_state[chunk][1] <== permutation[chunk - 1].state_out[1];
            }
            absorb_state[chunk][2] <== permutation[chunk - 1].state_out[2];
        }

        for (var lane = 0; lane < 3; lane++) {
            permutation[chunk].state_in[lane] <== absorb_state[chunk][lane];
        }
    }

    out <== permutation[nChunks - 1].state_out[0];
}
