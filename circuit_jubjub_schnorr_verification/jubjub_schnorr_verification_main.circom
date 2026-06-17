pragma circom 2.1.9;

/*
Thin wrapper used by later Groth16 build scripts.

Keeping a separate `*_main.circom` matches the structure already used by the
other Circom subprojects in this workspace.
*/

include "jubjub_schnorr_verification.circom";

component main = VerifyJubjubStandardSchnorr();
