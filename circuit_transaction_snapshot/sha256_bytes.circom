pragma circom 2.1.9;

include "vendor/circomlib_sha256/sha256.circom";

template Sha256Bytes(INPUT_BYTES) {
    signal input in[INPUT_BYTES];
    signal output out[32];

    component unpack[INPUT_BYTES];
    signal bits[INPUT_BYTES * 8];

    for (var j = 0; j < INPUT_BYTES; j++) {
        unpack[j] = ToBits(8);
        unpack[j].inp <== in[j];
        for (var i = 0; i < 8; i++) {
            bits[j * 8 + i] <== unpack[j].out[7 - i];
        }
    }

    component sha = Sha256(INPUT_BYTES * 8);
    for (var i = 0; i < INPUT_BYTES * 8; i++) {
        sha.in[i] <== bits[i];
    }

    for (var byteIndex = 0; byteIndex < 32; byteIndex++) {
        var sum = 0;
        for (var bitIndex = 0; bitIndex < 8; bitIndex++) {
            sum += sha.out[byteIndex * 8 + bitIndex] * (1 << (7 - bitIndex));
        }
        out[byteIndex] <== sum;
    }
}
