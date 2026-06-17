Vendored from `txpipe/dolos` `v1.2.0`.

Source path in Dolos:
`crates/cardano/src/include/devnet/`

These files are kept here so the local Tx3/Dolos bootstrap can recreate
`.tx3/dolos/` without depending on an external sibling checkout.

Canonical role split:
- `scripts/data/dolos-devnet/`
  - checked-in source of truth for the four genesis templates
- `.tx3/dolos/`
  - regenerable runtime scaffold populated by
    `scripts/python/bootstrap_tx3_scaffolding.py`
