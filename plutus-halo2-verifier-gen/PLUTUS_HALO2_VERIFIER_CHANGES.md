# Changes vs. the original version

This document summarizes the work applied to `plutus-halo2-verifier-gen`
relative to its [original version](https://github.com/input-output-hk/plutus-halo2-verifier-gen/tree/main) in order to support the on-chain
verification of the Mithril STM circuit consumed by `bridge-aiken`.

It is not an exhaustive changelog: changes are grouped by area and the
*why* is stated for each group.

The original version is a Halo2-to-Plutus verifier generator with two
backends, an Aiken and a Plinth one, designed for small circuits (simple
multiplication, lookups, ATMS). Our bridge required turning it into a
specialized generator that emits Aiken verifiers for a much larger circuit
and integrating it with `bridge-aiken`.

## 1. Add a new Mithril STM circuit

Our bridge needs to verify on-chain that a Mithril
certificate was signed by a quorum of Cardano signers. The strategy is to
prove the signature with a SNARK off-chain and verify the SNARK on-chain.
The original repository ships some example circuits, but it does not have
this one: the Mithril Halo2 circuit that proves Mithril multi-signature (Stake-
based Threshold Multi-signature) verification simply did not exist.

That's why we added a complete new module under
`src/circuits/mithril_stm/` (`circuit.rs`, `gadgets/`, `crypto/`,
`witness.rs`, `witness_assignments.rs`, `eligibility.rs`, `runtime.rs`,
`types.rs`, `errors.rs`) implementing that circuit end-to-end.

## 2. Remove Plinth verifier logic

The original generator emits both Aiken and Plinth
verifiers. The bridge only consumes Aiken, but every change to the
extraction pipeline, the type model or the templates had to be replicated
on both backends. That doubled the cost of each modification and left
dead code that confused review.

To avoid this extra cost, we removed the entire `plinth-verifier/` subdirectory, the
emitter `src/plutus_gen/emitters/plinth.rs` and the language definition
`src/plutus_gen/extraction/data/languages/plinth.rs`. The subrepo is
Aiken-only.

## 3. Extractor only understood plain Halo2 relations

The Mithril STM circuit is built on top of the
**Midnight** stack (`midnight-circuits`, `midnight-proofs`,
`midnight-curves`, `midnight-zk-stdlib`), not plain `halo2-proofs`. The
original extractor assumed a single relation provider with its own type
shape, so it could not read the VK, queries, commitments or proof steps
from a Midnight relation. On top of that, the real circuit has more
advice columns, more lookups and a richer gate set than the original
toy examples, which surfaced rough edges in the generic types.

To adapt the tool to be able to generate a verifier for the Mithril circuit we
had to make the following changes:

- added `plutus_gen/extraction/midnight.rs`: extractor for Midnight relations.
- added `plutus_gen/extraction/conversion.rs`: conversions between Midnight types
  and the pipeline's generic types.
- adjusted in the `plutus_genextraction` directory:
  - `pcs/{gwc.rs, kzg.rs, mod.rs}`,
  - `data/constants.rs`,
  - `data/extraction_steps/{permutation.rs, vanishing.rs}`.
- adjusted every file under `data/base_types/` (`commitment.rs`,
  `commitment_data.rs`, `evaluation.rs`, `expression.rs`,
  `proof_step.rs`, `rotation_description.rs`) and under
  `data/circuit_types/` (`circuit_expressions.rs`, `circuit_queries.rs`,
  `circuit_representation.rs`, `instantiation_data.rs`).

The Halo2 path was kept working so the original examples still compile.

## 4. Rework the generated Aiken verifier

The original version of `plutus-halo2-verifier-gen` produced verifiers
that were computationally heavy. On top of that, the Mithril STM VK is
much larger than the example VKs. The result was a generated verifier
that could not run inside a Cardano transaction, hitting both the
CPU-budget limit and the transaction-size limit.

The generator renders the Aiken verifier from [Handlebars](https://handlebarsjs.com/)
templates (the `.hbs` files) so adapting the generated output mostly
meant editing those templates. This led to the following changes:

- reworked the existing templates under `aiken-verifier/templates/` to handle
  the larger VK shape and the variable-size circuit:
  - `validator.hbs`: parametrized the redeemer and public inputs. The
    redeemer is now a generated tuple and the NFT-name hash folds a
    variable-length list of instances instead of a fixed set.
  - `verification_h2.hbs`: externalized the MSM into generated code (so it can
    be split across the two phases to meet the Cardano CPU-budget) and made
    instance handling generic (committed instances, variable instance evals,
    plus the circuit's "trash" commitments).
  - `verification_gwc19.hbs`: dropped the `bls_utils` MSM helpers and the
    precomputed `neg_g1_generator`, computing negation/generator inline via
    builtins, and removed a redundant `vanishing_g` re-compression.
- deleted the generic `aiken-verifier/aiken_halo2/` subproject. The
  original repo ships it checked in: a full generic Halo2 Aiken verifier
  (`aiken.toml`, the `lib/*.ak` helpers `bls_utils.ak` (BLS12-381),
  `halo2_kzg.ak` (KZG verification), `lagrange.ak` (Lagrange
  interpolation), `omega_rotations.ak` (rotation roots of unity),
  `transcript.ak` (Fiat-Shamir transcript), and the generated
  `validators/verifier.ak`). The bridge does not use this generic
  verifier, it uses the bridge-specific `mithril-stm/` and
  `mithril-stm-two-phase/` subprojects instead. Since these `.ak` files
  are generator outputs, they can be regenerated on demand via the
  examples (`cargo run --example ...`) rather than versioned.

The template changes here only *enable* the two-phase split: they emit the MSM
as partitionable generated code. The on-chain verifier itself was then split and
hand-refactored in `bridge-aiken` to fit the Plutus execution-unit and
transaction-size limits (compact phase-1 → phase-2 hand-off, split-specific MSM
helpers, batched modular inversion, a tuned split boundary). That work is
documented in `bridge-aiken/2_phase_mithril_stm_verification.md`.

## 5. Add a mithril proof exporter for `bridge-aiken`

The subrepo (Rust, off-chain proof generation) and `bridge-aiken`
(on-chain Aiken verification) share no code: the subrepo writes a *proof
export* to disk and the bridge reads it. That file is the only contract
between them, so it should be a well-defined intermediary rather than a
dump of the generator's internal layout — otherwise any internal refactor
(a renamed field, a changed serialization order) would silently break the
bridge at runtime. A formal exporter plus a JSON Schema make the contract
explicit and validated: the generator's internals can change freely as
long as the export still conforms.

To establish that hand-off we added the following:

- `src/plutus_gen/mithril_stm_proof_export.rs`: definition and serialization
  of the canonical proof export the bridge consumes.
- `src/bin/export_mithril_stm_proof_export.rs`: CLI that produces that
  proof export for a real Mithril STM run.
- `src/bin/export_mithril_stm_fixture_bundle.rs`: reproducible fixture
  bundle used by the bridge end-to-end tests.
- `src/bin/debug_mithril_stm_split.rs`: debugging utility for the
  Phase1State / ReducedRedeemer split.
- `schemas/mithril_stm_proof_export.schema.json` and
  `schemas/mithril_stm_bundle.schema.json`: JSON Schemas validating the
  emitted proof exports.

## 6. Smaller changes accompanying the rework

A handful of supporting edits were needed so the rest of the project
keeps up with the changes above:

- **`Cargo.toml`**: new dependencies (`mithril-stm`, `midnight-circuits`,
  `midnight-proofs`, `midnight-curves`, `midnight-zk-stdlib`, patched
  `blstrs`, `halo2curves`, `ciborium`, `serde_json`, `handlebars`, etc.)
  and a workspace that no longer includes `plinth-verifier`.
- **Examples** (`examples/{atms.rs, atms_with_lookups.rs,
  equations_test.rs, lookup_table.rs, simple_mul.rs}`): adapted to the
  new pipeline signatures so they keep compiling as smoke tests.
- **`.github/` removed**: CI now lives at the monorepo level
  (`cardano-zk-bridge`) and is not duplicated here.
- **`profiling_setup/`**: the script and README were updated to profile
  the STM circuit (much heavier than the original examples).
- **`AGENTS.md` added**: describes the subrepo's current operational
  state (Aiken-only, `.ak` files not versioned by default, etc.).
- **`.gitignore` and `README.md`** updated to reflect the new structure.

## Summary

The work was not a localized add-on to the original: it touched almost
every layer (circuit, extractor, emitter, templates, Aiken verifier,
integration) because the use case shifted from "verify a toy circuit in
Plutus" to "verify Mithril STM on Cardano under a realistic budget". The
changes break down into five major pieces:

1. the **Mithril STM circuit** itself,
2. the **Midnight extractor** the circuit requires,
3. the two generated **Aiken verifiers** (one-phase and two-phase),
4. the **proof exporter** connecting the generator to `bridge-aiken`,
5. the **removal of the Plinth path** to focus the subrepo on Aiken.
