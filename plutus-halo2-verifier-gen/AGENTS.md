# AGENTS.md

## Proposito

`plutus-halo2-verifier-gen` es el generador Rust del PoC Mithril -> `bridge-aiken`.
Hoy el subrepo es Aiken-only: ya no conserva ni versiona nada del camino
legacy eliminado.

## Mapa rapido

- `src/circuits/`
  - circuitos de ejemplo y `mithril_stm/`
- `src/plutus_gen/`
  - extraccion del verifier + emision Aiken + export del STM proof export
- `src/bin/export_mithril_stm_proof_export.rs`
  - CLI principal para exportar el proof export canónico del PoC
- `src/bin/export_mithril_stm_fixture_bundle.rs`
  - exporta un bundle fixture reproducible
- `src/bin/debug_mithril_stm_split.rs`
  - debug/repro del split `Phase1State + ReducedRedeemer`
- `examples/`
  - ejemplos de generacion de proof/verifier Aiken
- `aiken-verifier/`
  - salida regenerable del generador
- `kzg_params/`
  - parametros KZG inseguros para testing

## Estado operativo importante

- `bridge-aiken` es la fuente de verdad del Aiken on-chain del PoC.
- Este subrepo mantiene la capacidad de regenerar Aiken, pero no versiona
  archivos `.ak` por defecto.
- El STM proof export emitido desde Rust es la pieza canónica de intercambio con
  `bridge-aiken`.

## Flujo Mithril STM actual

Las APIs clave de `src/circuits/mithril_stm/runtime.rs` son:

- `generate_stm_proof(...)`
  - API histórica; hoy delega al modo fixture
- `generate_stm_proof_fixture(...)`
  - genera witness/proof sintéticos reproducibles desde `seed`
- `generate_stm_proof_from_bundle(...)`
  - consume `NormalizedStmBundle`
  - es el camino correcto para integrar con `bridge-aiken`

Los tipos normalizados se reexportan desde
`src/circuits/mithril_stm/mod.rs`.

## STM proof export canónico

La lógica está en `src/plutus_gen/mithril_stm_proof_export.rs`.

Ese módulo:

- valida `NormalizedStmBundle`
- genera la proof STM
- deriva:
  - `public_input_1`
  - `public_input_2`
  - `statement_hash`
  - `Phase1State`
  - `ReducedRedeemer`
- exporta JSON proof exports single-proof (consumidos como intermedios por
  el builder del bundle compatible en `bridge-aiken`).

Contrato operativo importante:

- `public_input_2 == child_certificate.signed_message`
- `statement_hash` es el valor que `bridge-aiken` usa para alinear el
  certificado hijo con la proof
- `bridge_aiken.phase1.statement_hash_value == statement_hash`
- `bridge_aiken.phase2.proof_receipt_statement_hash == statement_hash`
- `bridge_aiken.phase2.token_name == phase1_state.reduced_hash`

## Estado compartido actual del contrato STM

- `src/plutus_gen/mithril_stm_proof_export.rs` sigue siendo la fuente de verdad
  Rust que construye y valida el contrato del STM proof export.
- `bridge-aiken/scripts/python/zk_contract.py` ahora concentra la validación
  Python compartida del mismo contrato del lado consumidor.
- Eso reduce la dispersión en Python, pero el contrato STM/proof export todavía
  existe en dos lenguajes:
  - Rust productor en `plutus-halo2-verifier-gen`
  - Python consumidor en `bridge-aiken`
- Si cambia cualquiera de estas invariantes, revisar ambas superficies en el
  mismo cambio:
  - `statement_hash == public_input_2`
  - `child.signed_message == statement_hash`
  - `bridge_aiken.phase1.statement_hash_value == statement_hash`
  - `bridge_aiken.phase2.proof_receipt_statement_hash == statement_hash`

## Bug importante ya resuelto

El fallo del pairing final no era de curvas ni del split TX1/TX2.

La causa real fue un transcript mismatch:

- Rust estaba generando la proof con `PoseidonState<CircuitBase>`
- Aiken y el verifier on-chain reconstruyen con `CardanoFriendlyBlake2b`

Eso cambiaba los desafíos Fiat-Shamir y hacía fallar el pairing final aunque
`phase1` y el acumulador derecho coincidieran.

Estado correcto actual:

- el flujo STM usa `CardanoFriendlyBlake2b`
- existe una regresión que prueba “Blake2b acepta, Poseidon rechaza”
- `bridge-aiken` ya verifica end-to-end el proof export real del PoC

Documento explicativo:

- `/MITHRIL_STM_TRANSCRIPT_BUG.md`

## Comandos utiles

Smoke tests principales:

```bash
cargo test mithril_stm --lib
cargo test mithril_stm_proof_export --lib
```

Exportar bundle fixture:

```bash
cargo run --bin export_mithril_stm_fixture_bundle -- --output /tmp/mithril_stm_bundle.json
```

Exportar proof export canónico:

```bash
cargo run --bin export_mithril_stm_proof_export -- \
  --input /tmp/mithril_stm_bundle.json \
  --output /tmp/mithril_stm_proof_export.json
```

Validar un bridge-compatible bundle (modo `--check` aplicado por proof
entry):

```bash
cargo run --bin export_mithril_stm_proof_export -- --check /tmp/bridge-compatible-mithril-stm-bundle.json
```

Debug del split phase1/phase2:

```bash
cargo run --bin debug_mithril_stm_split -- \
  --bundle /tmp/mithril_stm_bundle.json \
  --proof_export /tmp/mithril_stm_proof_export.json
```

## Cuando tocar que

- Si cambia el witness o serialización STM:
  - mirar `src/circuits/mithril_stm/runtime.rs`
- Si cambia el contrato del proof export:
  - mirar `src/plutus_gen/mithril_stm_proof_export.rs`
- Si cambia la extracción/emisión del verifier Aiken:
  - mirar `src/plutus_gen/extraction/`
  - mirar `src/plutus_gen/emitters/aiken.rs`

## Recordatorios

- `mithril-stm` usa CBOR versionado en tipos como `MerkleTree` y
  `SingleSignature`; no asumir layouts legacy.
- No reintroducir archivos `.ak` versionados en este subrepo salvo que haya una
  razón operativa muy concreta.
- Si algo deja de verificar en `bridge-aiken`, volver a chequear primero:
  - transcript usado por la proof
  - `statement_hash`
  - igualdad entre `public_input_2` y `child.signed_message`
- La etapa 7 del PoC quedó verificada desde `bridge-aiken` con un runner
  integrado (`scripts/run_mithril_poc.sh`) que consume un proof export emitido
  desde este subrepo y cierra hasta `bridge_mint_tx`.

## 2026-04-14 - Dependencia portable de mithril-stm

- `Cargo.toml` dejó de depender de un checkout local en
  `/home/lorenzo/Desktop/mithril/mithril-stm`.
- La dependencia quedó pinneada al repo oficial:
  - `mithril-stm = { git = "https://github.com/input-output-hk/mithril.git", rev = "c0641158f7807e298b1815576502047f8fdf8d93", package = "mithril-stm", features = ["future_snark"] }`
- Motivo:
  - el exportador `export_mithril_stm_fixture_bundle` debía funcionar en
    cualquier workspace sin exigir un clon sibling/manual de Mithril.
- Verificado con:
  - `cargo check`
  - `cargo run --bin export_mithril_stm_fixture_bundle -- --output /tmp/bridge-compatible-mithril-stm-base-bundle.json`

## 2026-04-14 - Build reproducible across machines

- Se fijaron versiones exactas para evitar drift de la familia `midnight-*`:
  - `midnight-circuits = "=6.0.0"`
  - `midnight-curves = "=0.2.0"`
  - `midnight-proofs = "=0.7.0"`
  - `midnight-zk-stdlib = "=1.0.0"`
- Motivo:
  - con rangos semver abiertos, otra máquina resolvía `midnight-circuits 6.1.0`
    y `mithril-stm` fallaba con `E0061` en `ForeignEccChip::new(...)`.
- Además `Cargo.lock` dejó de estar ignorado:
  - este subrepo expone bins ejecutados por `bridge-aiken`, así que el lockfile
    debe viajar con el repo.
- Verificado también en una copia temporal sin `Cargo.lock`:
  - `cargo generate-lockfile`
  - `cargo tree -i midnight-circuits`
  - siguió resolviendo `midnight-circuits v6.0.0`
