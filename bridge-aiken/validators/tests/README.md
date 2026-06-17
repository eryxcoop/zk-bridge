# Validator Test Layout

Keep tests close to the behavior they protect:

- `*_validator_test.ak` covers validator acceptance and rejection behavior.
- `verify_certificate_test.ak` pins the direct Mithril genesis-certificate
  verification contract, including the Ed25519 `GenesisSignature` path used by
  `stake_distribution_genesis_tx`.
- `stake_distribution_validator_test.ak` now also covers the dual genesis path:
  `GenesisDualSignature` + a coherent Mithril test-only Jubjub Groth16
  proof/public-input fixture.
- `bridge_fixture_test.ak` pins the exported end-to-end bridge fixture values.
- `jubjub_schnorr_fixture_test.ak` pins the exported end-to-end Jubjub
  Schnorr fixture imported from the sibling
  `circuit_jubjub_schnorr_verification/` subproject.
- `snapshot_membership_test.ak` covers Groth16 public-input packing and fixture threading.
- `helpers/bridge_fixture.ak` is generated from `scripts/data/bridge_mint_raw.json` through `scripts/python/sync_bridge_zk_fixture.py`; treat that JSON as the runtime-side source of truth for the shared bridge fixture bytes.
- `helpers/jubjub_schnorr_fixture.ak` is generated from
  `scripts/data/jubjub_schnorr_raw.json` through
  `scripts/python/jubjub_schnorr_fixture.py`; treat that JSON as the
  bridge-side source of truth for the exported Jubjub Schnorr proof bytes and
  public inputs.
- `helpers/coherent_dual_genesis_fixture.ak` is the honest dual-genesis test
  fixture:
  - Ed25519 half from Mithril's deterministic test signer
  - Schnorr half from Mithril's deterministic test signer over the same digest
  - Groth16 proof generated from that same Schnorr witness
  - use this fixture when the test needs the whole dual object to be coherent,
    not just the standalone Jubjub proof bytes.
- `locking_tx_hash` / `locking_tx_hash_hex` remain legacy compatibility names in the
  fixture layer, but now carry the canonical Cardano transaction hash.
- The `cardano_transactions` test fixture and the runtime bridge fixture are expected to stay aligned on the same tx snapshot root; preflight and fixture-sync checks now enforce that shared root contract.
- `helpers/certificates/cardano_transactions.ak` must keep its `CardanoTransactionsMerkleRoot` aligned with both `scripts/data/bridge_mint_raw.json` and `helpers/bridge_fixture.ak`; if it drifts, the Python fixture-alignment checks should fail before the wider runtime flow starts.
- `phase*_runtime_probe_test.ak` executes real proof fixtures and should stay separate from lightweight unit-style validator-shape tests.
- `helpers/` contains fixture builders only; avoid putting executable tests there.

Prefer names shaped as `accepts_<case>` or `rejects_<case>`. If a helper is only needed by one module, keep it local to that test file instead of exporting it from `helpers/`.
