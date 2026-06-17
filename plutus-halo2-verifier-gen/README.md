# Plutus Halo2 Verifier

A Rust tool that generates **Aiken** verifiers for Halo2 circuits and for the
Midnight/Mithril STM PoC used by `bridge-aiken`.

This repository is proof-of-concept code intended for research and local
experimentation. It is not production ready.

## What It Does

- defines example Halo2 circuits in Rust
- generates proving/verifying keys and example proofs
- extracts verifier structure from Halo2 or Midnight relations
- emits Aiken verifier code and verifier-key constants
- exports Mithril STM proof exports consumed by `bridge-aiken`

## Main Areas

- `src/circuits/`
  Rust circuits, including `mithril_stm`
- `src/plutus_gen/`
  extraction + Aiken emission pipeline
- `aiken-verifier/`
  generated Aiken project, templates, and submitter tooling
- `examples/`
  example circuits such as `simple_mul`, `lookup_table`, `atms`, and
  `atms_with_lookups`

## Build Prerequisites

- Rust / Cargo
- Aiken toolchain for the generated Aiken project

Build the generated Aiken verifier with:

```bash
cd aiken-verifier/aiken_halo2
aiken check
aiken build
```

## Running Examples

Examples generate proofs and Aiken verifier artifacts:

```bash
cargo run --example simple_mul
cargo run --example simple_mul gwc_kzg
cargo run --example atms
cargo run --example atms gwc_kzg
cargo run --example atms_with_lookups
cargo run --example atms_with_lookups gwc_kzg
cargo run --example lookup_table
```

Typical outputs:

- `aiken-verifier/aiken_halo2/lib/proof_verifier.ak`
- `aiken-verifier/aiken_halo2/lib/verifier_key.ak`
- `aiken-verifier/submitter/serialized_proof.hex`
- `aiken-verifier/submitter/serialized_public_input.hex`

## Mithril STM

The repository also contains the Mithril STM integration used for the
`bridge-aiken` PoC.

Useful commands:

```bash
cargo test mithril_stm --lib
cargo run --bin export_mithril_stm_proof_export -- --help
```

The stage-5 bridge-compatible builder lives in `bridge-aiken`:

```bash
bridge-aiken/scripts/build_bridge_compatible_mithril_stm_proof_export_bundle.sh /tmp/bridge-compatible-mithril-stm-bundle.json
```

## Profiling

`profiling_setup/` now documents and profiles only the generated Aiken
verifier path.
