# Fixed Tooling Bugs Still Relevant To The Bridge Runtime

This note now keeps only the external tooling fix that is still required by
the current `bridge-aiken` runtime contract.

As of `2026-06-03`:

- the public `bridge.sh` flows no longer require sibling `../dolos`
- the public `bridge.sh` flows no longer require sibling `../uplc-turbo`
- the bridge runtime is exercised against the installed `dolos 1.2.0`
  binary plus repo-local `.tx3/dolos` scaffolding
- the only remaining sibling source-tree patch still required for verified
  local runs is the `cshell` fix below

## 1. `cshell tx invoke` needed local normalization of namespaced TII `$ref`s

### Current fix location

- file:
  `../cshell-0.14.0/src/tx/common.rs`
- current fix:
  `prepare_invocation(...)` no longer feeds the raw TII JSON directly into
  `Protocol::from_json(...)`
- before parsing, `cshell` now rewrites only these namespaced refs:
  - `https://tx3.land/specs/v1beta0/tii#/$defs/Bytes`
  - `https://tx3.land/specs/v1beta0/tii#/$defs/Address`
  - `https://tx3.land/specs/v1beta0/tii#/$defs/UtxoRef`
  into the legacy refs that the current `tx3-sdk` in `cshell 0.14.0`
  understands:
  - `https://tx3.land/specs/v1beta0/core#Bytes`
  - `https://tx3.land/specs/v1beta0/core#Address`
  - `https://tx3.land/specs/v1beta0/core#UtxoRef`

### Why this mattered for `bridge-aiken`

Once `bridge-aiken` switched its experimental dual-genesis path to the
namespaced TII emitted by current `trix build`, the runtime stopped before
on-chain validation with:

- `cshell tx invoke`
  - `invalid param type`

That failure was not specific to `stake_distribution_dual_genesis_tx`.
A reduced repro in:

- `../tx3_cshell_invalid_param_type_repro`

showed the same error for two tiny transactions:

- `publish_ref_script_repro`
- `plain_transfer_repro`

Both repros used ordinary `UtxoRef`, `Int`, and `Bytes` params, but those
types were referenced through the new namespaced TII schema paths.

### Root cause

The vendored `tx3-sdk` used by `cshell 0.14.0` still recognizes only the
legacy `core#...` schema refs when mapping TII params into CLI argument types.

Current `trix build` emits namespaced refs under:

- `https://tx3.land/specs/v1beta0/tii#/$defs/...`

So the bridge runtime reached `cshell`, parsed the new TII, and then rejected
otherwise-valid params as:

- `invalid param type`

### Regression coverage

- file:
  `../cshell-0.14.0/src/tx/common.rs`
- verified unit tests:
  - `prepare_invocation_accepts_legacy_core_refs`
  - `prepare_invocation_accepts_namespaced_tii_refs`
  - `prepare_invocation_still_rejects_unknown_refs`

### Verified result

Local `cshell` tests were run with:

- `cargo test tx::common -- --nocapture`
- `cargo test -- --nocapture`

Verified outcome:

- the new unit coverage passes
- the wider `cshell` test suite still passes

The standalone repro was then re-run with the patched local binary:

- `publish_ref_script_repro`
- `plain_transfer_repro`

Verified change in behavior:

- neither command fails anymore with:
  - `invalid param type`
- both progress past param parsing and only fail later if no provider is
  running

Finally, the real bridge flow was re-run with:

- `CSHELL_BIN=../cshell-0.14.0/target/debug/cshell ./scripts/bridge.sh genesis_dual_signature ...`

Verified change in behavior:

- the bridge no longer fails at `cshell tx invoke`
- it now reaches actual on-chain script evaluation
- the next remaining blocker moved to mint-validator execution inside
  `stake_distribution_dual_genesis_tx`

### Follow-up after the cshell fix

After the separate bridge-side Aiken modulus fix, the same runtime command now
passes end to end with the patched local `cshell`:

- `CSHELL_BIN=../cshell-0.14.0/target/debug/cshell ./scripts/bridge.sh genesis_dual_signature ...`
- verified tx hash:
  - `72c1c486621b9c4fe9f306e55fc7c12296c67499b34889ea715f75f357a0c38f`

Therefore, this `cshell` fix is now required for the experimental
dual-genesis bridge flow and is a candidate upstream PR for `txpipe/cshell`.
