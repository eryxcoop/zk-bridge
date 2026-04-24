# AGENTS.md

Estado operativo vigente de `zk-bridge-operator`.

## Scope actual del directorio

Este crate aloja el operador compartido de circuitos zk para el repo.

Responsabilidades actuales:

- sync de certificados Mithril de stake distribution
- verificación de proof + certificate chain para `transaction_hash` canónico
- orquestación del proof de:
  - `../../circuit_transaction_snapshot`
  - `../../circuit_inclusion_exclusion`

## Contrato de artifacts vigente

Todos los paths relativos se resuelven desde `zk-bridge-operator/`
salvo override explícito por CLI.

Comandos expuestos:

- `relayer sync-certificates`
- `tx prove <transaction-hash>`

`relayer sync-certificates` escribe:

- `certificates/index.json`
- `certificates/aggregator_features.json`
- `certificates/aggregator_status.json`
- `certificates/<certificate-hash>.json`

`index.json` resume:

- `aggregator_url`
- `genesis_hash`
- `latest_recent_hashes`
- `stored_hashes`

`tx prove <tx>` escribe metadata top-level en:

- `tx_artifacts/<tx>/aggregator_features.json`
- `tx_artifacts/<tx>/aggregator_status.json`
- `tx_artifacts/<tx>/proof_response.json`
- `tx_artifacts/<tx>/certificate.json`
- `tx_artifacts/<tx>/snapshot.json` si existe snapshot asociado
- `tx_artifacts/<tx>/manifest.json`

`manifest.json` resume:

- `aggregator_url`
- `transaction_hash`
- `proof_certificate_hash`
- `latest_block_number`
- `verified`
- `snapshot_hash`

Además `tx prove` produce dos bundles por circuito:

- `tx_artifacts/<tx>/snapshot_membership/`
- `tx_artifacts/<tx>/tx_set_update/`

Cada bundle exporta el mismo shape:

- `input.json`
- `proof.json`
- `public.json`
- `packed_public_inputs.json`
- `verify.log`
- `fixture_summary.json`
- `<circuit>_vk.ak`

Nombres del VK:

- `snapshot_membership_vk.ak`
- `tx_set_update_vk.ak`

Artifacts canónicos a mirar primero:

- `manifest.json` para el resumen del operador
- `packed_public_inputs.json` para el statement público packed
- `fixture_summary.json` para el proof bundle y valores públicos decodificados

## Reglas de diseño vigentes

- La fuente canónica de identidad de transacción para este operador es el
  `transaction_hash` real de Cardano.
- No reintroducir en este crate un flujo que trate de probar membership de un
  digest bridge-derived distinto del hash real certificado por Mithril.
- Si el operador necesita producir varios proofs para la misma transacción,
  todos deben derivar del mismo `transaction_hash` canónico.

## Checks de referencia

- `cargo test --manifest-path ../zk-bridge-operator/Cargo.toml`
- `cargo run --manifest-path ../zk-bridge-operator/Cargo.toml -- --help`

Validación real ya confirmada:

- `cargo run --manifest-path ../zk-bridge-operator/Cargo.toml -- --tx-artifacts-dir /tmp/zk-circuit-operator-smoke --force tx prove 601c6513db4646317449e575104044e53f9e7db721fa7424782a83889961b6be`

Resultados esperados en ese flujo:

- `snapshot_membership/fixture_summary.json` con `verified=true`
- `tx_set_update/fixture_summary.json` con `verified=true`
- `manifest.json` con `verified=true`

Smoke de runtime documentado en:

- `../bridge-aiken/scripts/tests/run_ci_jobs_locally.sh`

Ese smoke espera que `tx prove <tx>` deje al menos:

- `tx_artifacts/<tx>/manifest.json`
- `tx_artifacts/<tx>/snapshot_membership/fixture_summary.json`
- `tx_artifacts/<tx>/tx_set_update/fixture_summary.json`

Y que `relayer sync-certificates` use el layout:

- `certificates/index.json`
- `certificates/aggregator_features.json`
- `certificates/aggregator_status.json`
- `certificates/<certificate-hash>.json`

## Dependencias de ownership

- `circuit_transaction_snapshot` es dueño del proof de snapshot-membership
- `circuit_inclusion_exclusion` es dueño del proof de tx-set-update
- este crate sólo orquesta y verifica; no debe duplicar la lógica del circuito
  más de lo necesario

## Nota de debugging importante

En una sesión anterior se aisló un bug histórico del circuito de snapshot:

- primer commit bueno: `7496637`
- primer commit malo: `d60c429`

La causa fue un mismatch entre nombres de inputs del `.circom` (`*_b`) y las
claves emitidas por Rust. Si `tx prove` vuelve a fallar sólo en
`snapshot_membership` con `public_inputs` en cero o `verified=false`, revisar
primero el contrato de nombres de `circuit_transaction_snapshot/input.json`
antes de tocar este crate o `ark-circom`.
