# AGENTS.md

Estado operativo vigente de `circuit_transaction_snapshot`.

## Scope actual del directorio

- `mithril_legacy_tx_membership.rs`
  modela el witness canónico del circuito y el packing del statement público.
- `mithril_legacy_tx_membership.circom`
  implementa el circuito de membership sobre esa witness.
- `mithril_legacy_tx_membership_main.circom`
  fija la instanciación compilada actual.

## Estado operativo

- la curva activa sigue siendo `bls12381`
- `cargo test --lib` pasa en este directorio
- `cargo test --test groth16_offline -- --nocapture` pasa en este directorio
- `scripts/run_e2e_test.sh` vuelve a pasar con `verified=true`
- el flujo recomendado sigue siendo:
  - `scripts/build_groth16_artifacts.sh`
  - `scripts/run_e2e_test.sh`
- `tests/groth16_offline.rs` sigue delegando al helper compartido
  `../zk-circuits-common/groth16_offline_test_helper.rs`
- el fixture canónico retenido sigue siendo:
  - `groth16_artifacts/final_fixture`
- los `groth16_artifacts/test_runs/` históricos fueron podados y ya no deben
  tratarse como source of truth

## Statement actual del circuito

La entrada compilada sigue siendo:

- `component main = MithrilLegacyTxMembership(10, 32, 32, 1, 32)`

Parámetros fijos:

- `MAX_SUB_PREFIX_LEN = 10`
- `MAX_SUB_UPPER_HEIGHT = 32`
- `MAX_RANGE_ASCII_BYTES = 32`
- `MAX_MASTER_PREFIX_LEN = 1`
- `MAX_MASTER_UPPER_HEIGHT = 32`

### Witness privado actual

Los `signal input` relevantes son:

- `cardano_tx_hash_b[32]`
- `sub_prefix_*`
- `sub_upper_*_b`
- `range_ascii_b[*]`
- `master_prefix_*`
- `master_upper_*_b`
- `expected_root_b[32]`

Observaciones:

- el contrato Circom real usa sufijo `_b` en los arrays de bytes
- el leaf del sub-tree ahora se deriva del `cardano_tx_hash` real
- este crate ya no reconstruye un `locking_tx_hash` bridge-derived
- `expected_root_b[32]` sigue entrando como witness privado mientras el circuito
  también expone `master_root[32]` y fuerza `master_root == expected_root`
- el prefijo master actual sigue restringido a pasos `hash-only`

### Hallazgo histórico importante

Se identificó y revalidó el corte exacto del bug que dejaba este circuito en
`verified=false` con `public_inputs` en cero:

- primer commit bueno: `7496637`
- primer commit malo: `d60c429`

La causa exacta fue un desfasaje entre el contrato Circom y el normalizador
Rust:

- en `d60c429` el `.circom` renombró varios inputs a `*_b`
- `mithril_legacy_tx_membership.rs` siguió exportando las claves viejas sin
  `_b`

El fix correcto ya aplicado en este árbol fue:

- actualizar `LegacyTxCircuitWitness::to_circom_inputs()` para emitir las
  claves `*_b` que el circuito realmente consume

No volver a "arreglar" este circuito tocando `ark-circom` o el exporter
compartido si reaparece un síntoma parecido; primero revisar siempre el
contrato de nombres entre `.circom` e `input.json`.

### Statement público actual

El statement público expone `6` field elements packed:

- `cardano_tx_hash_hi`
- `cardano_tx_hash_lo`
- `sub_root_hi`
- `sub_root_lo`
- `master_root_hi`
- `master_root_lo`

Orden exacto:

- índice `0`: `cardano_tx_hash_hi`
- índice `1`: `cardano_tx_hash_lo`
- índice `2`: `sub_root_hi`
- índice `3`: `sub_root_lo`
- índice `4`: `master_root_hi`
- índice `5`: `master_root_lo`

Conclusión operativa:

- hoy el circuito publica semánticamente
  `cardano_tx_hash + sub_root + snapshot_root`
- `packed_public_inputs.json` es el artifact canónico exportado

## Operador compartido

El operador Mithril ya no vive en este crate. La superficie compartida ahora
está en:

- `../zk-bridge-operator/`

Ese operador debe tratar a este circuito como el dueño del proof de membership
sobre el hash real de Cardano.

Cuando el operador compartido ejecuta `tx prove <tx>`, el bundle exportado por
este crate queda en:

- `tx_artifacts/<tx>/snapshot_membership/input.json`
- `tx_artifacts/<tx>/snapshot_membership/proof.json`
- `tx_artifacts/<tx>/snapshot_membership/public.json`
- `tx_artifacts/<tx>/snapshot_membership/packed_public_inputs.json`
- `tx_artifacts/<tx>/snapshot_membership/verify.log`
- `tx_artifacts/<tx>/snapshot_membership/fixture_summary.json`
- `tx_artifacts/<tx>/snapshot_membership/snapshot_membership_vk.ak`

Artefactos canónicos de lectura rápida:

- `packed_public_inputs.json`
- `fixture_summary.json`

Validación real ya comprobada en esta sesión:

- `zk-bridge-operator tx prove 601c6513db4646317449e575104044e53f9e7db721fa7424782a83889961b6be`
- el bundle `snapshot_membership/fixture_summary.json` resultante queda con
  `verified=true`

## Próximos pasos

- Si cambia el contrato público packed, actualizar este archivo, el `README.md`
  y el exporter en el mismo commit.
- Si se vuelve a introducir cualquier digest bridge-derived en este crate,
  dejar explícita la justificación y no mezclarlo con el `cardano_tx_hash`
  canónico.

## Circuito experimental

También existe:

- `mithril_lagrange_tx_membership_experimental.circom`

Estado esperado de ese archivo:

- debe converger hacia `cardano_tx_hash` como identidad canónica
- debe converger hacia el shape público packed
  `cardano_tx_hash + sub_root + snapshot_root`
- no debe presentarse como compatible con `tx prove` hasta que exista un
  normalizador/exporter y un witness contract alineado con el operador
- cualquier hash `MockMidnightPoseidon*` debe documentarse explícitamente como
  placeholder criptográfico
