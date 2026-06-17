# Halo2 Verifier Profiling Setup

This directory contains tooling for profiling the generated **Aiken** Halo2
verifier.

## Prerequisites

- `nix`
- `jq`
- `xxd`

## Workflow

1. Generate an example verifier:

```bash
cargo run --example atms gwc_kzg
```

2. Build the generated Aiken project:

```bash
cd ../aiken-verifier/aiken_halo2
aiken build
```

3. Run the profiler:

```bash
cd ../../profiling_setup
./profiling.sh
```

## Outputs

- `contract.hex`
- `contract.cbor`
- `script.flat`
- `script2.flat`
- `logs`
- `cpu.svg`
- `mem.svg`
