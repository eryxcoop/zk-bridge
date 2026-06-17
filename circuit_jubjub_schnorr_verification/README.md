# Jubjub Standard Schnorr Circuit

This circuit proves the algebraic validity of a Mithril genesis
`StandardSchnorrSignature` over Jubjub.
It is the bridge's experimental Groth16 path for the Schnorr half of Mithril's
dual genesis certificate flow. Without it, the bridge would have to either
trust off-chain Schnorr verification or implement Jubjub arithmetic directly in
Aiken, which was already ruled out as too expensive.

## How the Mithril Statement Works

For the dual-genesis flow, Mithril signs a Jubjub base-field message derived
from:

1. `rigid_preimage`
2. `sha256(rigid_preimage)`
3. reduction of that 32-byte digest into the Jubjub base field

The Schnorr verifier then checks:

- the verification key is a valid Jubjub point
- the verification key is in the prime-order subgroup
- `R' = response * G + challenge_as_scalar * VK`
- `challenge' = Poseidon(DST, VK.u, VK.v, R'.u, R'.v, message_base)`
- `challenge' == challenge`

This circuit currently proves that algebraic relation directly.

## Current Status

The circuit is implemented and wired into the local Groth16 toolchain.

Current entrypoint:

```circom
component main = VerifyJubjubStandardSchnorr();
```

Current witness shape:

- `message_base`
- `verification_key_u`
- `verification_key_v`
- `signature_response`
- `signature_challenge`
- `challenge_scalar`
- `challenge_quotient`

Important limitation:

- the circuit does **not** yet parse the Mithril byte payload inside Circom
- the final byte-level binding from `sha256(rigid_preimage)` to the bridge
  statement is still pending

So this circuit should be treated as a validated algebraic verifier, not yet as
the final production-ready byte-level statement contract.

## Circuit Inputs

To generate a proof, the prover currently supplies the following private inputs:

- `message_base` - the Jubjub base-field element that Mithril signs
- `verification_key_u` - affine `u` coordinate of the Jubjub verification key
- `verification_key_v` - affine `v` coordinate of the Jubjub verification key
- `signature_response` - Schnorr response component
- `signature_challenge` - Schnorr challenge component in the Jubjub base field
- `challenge_scalar` - scalar-field reinterpretation of `signature_challenge`
- `challenge_quotient` - quotient used by the base-to-scalar reduction check

The canonical witness used by the local test flow lives in:

- `examples/valid_algebraic_statement.json`

The canonical upstream-oriented vectors live in:

- `fixtures/valid_deterministic_vector.json`
- `fixtures/negative_vectors.json`

## Circuit Outputs

The circuit currently exposes `6` public output signals.

The bridge-facing statement intentionally does **not** expose the raw
`message_base` as a single field element anymore. Instead, it re-exposes that
algebraic value split into two limbs:

- `message_base_hi` - the upper 127 bits of `message_base`
- `message_base_low` - the lower 128 bits of `message_base`
- `verification_key_u`
- `verification_key_v`
- `signature_response`
- `signature_challenge`

Output ordering (as exported in `public.json`):

- index 0: `message_base_hi`
- index 1: `message_base_low`
- index 2: `verification_key_u`
- index 3: `verification_key_v`
- index 4: `signature_response`
- index 5: `signature_challenge`

`packed_public_inputs.json` keeps the same statement in named form and
reconstructs the two `message_base` limbs from the current algebraic witness.

## Transcript Compatibility

The circuit no longer relies on the older variable-width `Poseidon255(nInputs)`
helper used elsewhere in the workspace.

Instead, it uses the dedicated Midnight-compatible sponge implementation in:

- `midnight_poseidon3_constants.circom`
- `midnight_poseidon3_sponge.circom`

This matters because Mithril's Jubjub Schnorr transcript uses a fixed
WIDTH=3 / RATE=2 sponge with an explicit input-length lane, not the older
variable-width Poseidon contract.

That transcript alignment was the key fix that made the canonical upstream
vector validate end-to-end in this subproject.

## Local Testing Flow

These commands compile the circuit, generate a proof from the canonical local
witness, and verify that it passes:

```bash
bash scripts/build_circuit.sh
bash scripts/run_e2e_test.sh
cargo test --manifest-path Cargo.toml
```

If everything ran correctly, the canonical local artifacts should appear under:

- `circuit_build/`

The end-to-end fixture flow writes:

- `circuit_build/final_fixture/proof.json`
- `circuit_build/final_fixture/public.json`
- `circuit_build/final_fixture/packed_public_inputs.json`
- `circuit_build/final_fixture/proof_summary.json`
- `circuit_build/final_fixture/jubjub_schnorr_verification_vk.ak`

The summary should confirm:

- `curve=bls12381`
- `protocol=groth16`
- `public_inputs=6`
- `verified=true`

The offline regression suite currently covers:

- valid proof
- invalid digest / message base
- invalid response
- invalid challenge
- invalid verification key
- torsion / non-prime-order verification key
- the canonical upstream deterministic vector

## Bridge Export Flow

This circuit can export a bridge-consumable fixture into `bridge-aiken`:

```bash
bash scripts/export_to_bridge_aiken.sh
```

That flow updates:

- `bridge-aiken/scripts/data/jubjub_schnorr_raw.json`
- `bridge-aiken/validators/tests/helpers/jubjub_schnorr_fixture.ak`
- `bridge-aiken/lib/zk/jubjub_schnorr_verification_vk.ak`

On the Aiken side, the local wrapper lives in:

- `bridge-aiken/lib/zk/jubjub_schnorr_verification.ak`

## Security Note

The current bridge-side contract is still an intermediate stage.

Today the public statement proves:

- the trusted Jubjub verification key coordinates
- the response/challenge halves of the Schnorr signature
- the algebraic `message_base`, split into `message_base_hi` and
  `message_base_low`

It does **not** yet prove the full byte-level identity:

- `signed_message == sha256(rigid_preimage)`
- and `message_base == reduce_to_jubjub_base_field(signed_message)`

The intended final direction remains:

- expose the certified digest byte-for-byte as packed public inputs
- reconstruct the digest-derived `message_base` inside the circuit
- bind the final bridge statement directly to the certificate payload consumed
  on-chain

Until that is done, this project should be understood as the validated Groth16
scaffold for the Jubjub Schnorr relation, with an improved packed public
statement shape, but not yet as the final byte-level bridge statement.
