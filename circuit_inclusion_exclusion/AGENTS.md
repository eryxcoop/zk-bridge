# AGENTS.md

Estado operativo vigente de `circuit_inclusion_exclusion`.

## Scope actual del directorio

- `tx_set_update.rs`
  modelo canónico Rust del SMT y helpers del statement packed.
- `tx_set_update.circom`
  circuito Circom que prueba ausencia/presencia en el SMT.
- `tx_set_update_main.circom`
  fija la instanciación compilada: `component main = TxSetUpdate()`.

## Estado operativo

- la curva activa sigue siendo `bls12381`
- `cargo test --lib -- --nocapture` pasa en este directorio
- `cargo test --test groth16_offline -- --nocapture` pasa en este directorio
- `scripts/run_e2e_test.sh` pasa con `verified=true`
- el fixture final canónico sigue en:
  - `circuit_build/groth16_sample_proof`
- el flujo local sigue siendo:
  - `scripts/build_circuit.sh`
  - `scripts/run_e2e_test.sh`
- los `circuit_build/test_runs/` históricos fueron podados; no deben
  considerarse artifacts vigentes

## Contrato público actual

El statement público bridge-facing sigue siendo:

- `tx_id`
- `mt_root_in`
- `mt_root_out`

Public inputs del circuito:

- `public_inputs[0] = tx_id_hi`
- `public_inputs[1] = tx_id_lo`
- `public_inputs[2] = mt_root_in`
- `public_inputs[3] = mt_root_out`

Para el flujo compartido con Mithril, `tx_id` debe tratarse como el hash
canónico de la transacción Cardano.

## Operador compartido

Este directorio ya no es dueño del operador Mithril. El binario compartido
vive ahora en:

- `../zk-bridge-operator/`

Ese operador genera dos pruebas para el mismo hash canónico:

- snapshot membership (`../circuit_transaction_snapshot`)
- tx-set-update (`this directory`)

Cuando el operador compartido ejecuta `tx prove <tx>`, el bundle exportado por
este crate queda en:

- `proven_transactions/<tx>/tx_set_update/input.json`
- `proven_transactions/<tx>/tx_set_update/proof.json`
- `proven_transactions/<tx>/tx_set_update/public.json`
- `proven_transactions/<tx>/tx_set_update/packed_public_inputs.json`
- `proven_transactions/<tx>/tx_set_update/verify.log`
- `proven_transactions/<tx>/tx_set_update/proof_summary.json`
- `proven_transactions/<tx>/tx_set_update/tx_set_update_vk.ak`

Artefactos canónicos de lectura rápida:

- `packed_public_inputs.json`
- `proof_summary.json`

Validación real ya comprobada en esta sesión:

- `zk-bridge-operator tx prove 601c6513db4646317449e575104044e53f9e7db721fa7424782a83889961b6be`
- el bundle `tx_set_update/proof_summary.json` resultante queda con
  `verified=true`

## Próximos pasos

- Mantener este circuito alineado con el `cardano_tx_hash` canónico usado por
  el operador compartido.
- Si cambia el shape packed del statement, actualizar este archivo y el
  `README.md` del directorio en el mismo commit.
