# AGENTS.md

Estado vigente de `zk-bridge-operator`.

## Scope actual

Este crate cubre:

- sync de certificados Mithril
- `tx prove <transaction-hash>`
- comandos Preview del operador para:
  - reference scripts
  - `phase1_setup` / `phase2_verify`
  - stake distribution
  - bridge seed txs
  - `bridge_mint_tx`

El viejo flow de `publish_proof_receipt_reference_script` ya no forma parte del crate.

## Reglas operativas

- no hardcodear tx hashes o UTxOs históricos dentro de los comandos
- si un valor cambia run a run, debe venir de:
  - flags CLI
  - Mithril bundle actual
  - estado persistido bajo `preview_phase12/`
  - lookups on-chain
- `bridge_mint_tx` en `--skip-submit` requiere siempre un receipt on-chain real

## Defaults vigentes

Bridge reference scripts:

- `publish_minting_txs_updater_spend_reference_script`
  - `reference_script_lovelace = 40000000`
- `publish_bridge_minting_reference_script`
  - `reference_script_lovelace = 40000000`

Bridge seed txs:

- `locking_txs_updater_seed_tx`
  - `seed_output_lovelace = 10000000`
- `minting_txs_updater_seed_tx`
  - `locking_txs_updater_output_lovelace = 3000000`
  - `bridge_collateral_lovelace = 20000000`

## Corridas verificadas en esta sesión

Reference scripts:

- `publish_minting_txs_updater_spend_reference_script`
  - `66147eb8db6233c5dab80f7ac841d69ded3877031fc59b9590154295ca4c9514`
- `publish_bridge_minting_reference_script`
  - `681e3886faa891060831eb01c871246c38b111f460d418fa0eaf800c250094a0`

Seed txs:

- `locking_txs_updater_seed_tx`
  - `6a33f2c4ea7f19c70d39ad9a1c7382614b67be7255f226871c18cb7f02354b10`
- `minting_txs_updater_seed_tx`
  - `3f5a468f5955f40dbf421b22ba05cf35a0a6f201c555c0409a53e9c3fd816603`

`cardano_transactions` lane:

- `phase1_setup_cardano_transactions`
  - `a77266e76856ccca06c66fa4cd94f431a83c740795aa993f26cca5440a2fc59a`
- `phase2_verify_cardano_transactions`
  - `7d189d5850e58a04322284f68da39518671a27dac4034118ab9cb6d072c05d85`
- `bridge_mint_tx`
  - `fb1f0159ed0870b6b0b86b9db1e661942a2179381f157c7a5a432c3db89d5e23`

Standalone `bridge_mint_tx` test:

- `signed_skip_submit`
  - `cccdf32a60e0e9929ca419729ddf397046a0371f5fc45a53c5b44b2d44b8fd08`

En las corridas submitteadas de arriba se verificó `valid_contract = true`.

## Fixes operator-side ya incorporados

- detección dinámica de índices de redeemers para patch de budgets
- los sidecars exactos de simulación incluyen `reference inputs`
- para medición spend/mint:
  - el primer budget simulado se toma como `spend`
  - el último budget simulado se toma como `mint`

## Paths útiles

- artifacts CLI rápidos:
  - `.omx/tmp/preview-operator-cli/`
- inventario canónico persistido de éxitos on-chain:
  - `preview_phase12/successful-onchain-txs.json`

Política actual para `preview_phase12/`:

- no retener artifacts reproducibles
- regenerarlos on demand con los comandos del operador
- conservar sólo el inventario JSON de tx hashes exitosos on-chain

## Contrato de outputs no-Preview

`relayer sync-certificates` escribe:

- `certificates/index.json`
- `certificates/aggregator_features.json`
- `certificates/aggregator_status.json`
- `certificates/<certificate-hash>.json`

`tx prove <transaction-hash>` escribe:

- `tx_artifacts/<tx>/manifest.json`
- `tx_artifacts/<tx>/snapshot_membership/`
- `tx_artifacts/<tx>/tx_set_update/`

## Mantenimiento

- si un doc interno queda en tensión con el código actual, priorizar el código
- evitar volver a crecer `README.md` / `AGENTS.md` como bitácora larga de debugging
- documentar sólo:
  - superficie vigente
  - defaults vigentes
  - hashes verificados útiles
  - reglas operativas que hoy siguen siendo relevantes
