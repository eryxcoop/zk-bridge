# Mithril Readme

## On the architecture change of sending Mithril Verification Key as a parameter

Currently we're hard-coding the Mithril circuit verification key in the bridge validator. This doesn't account for the possiblity
that the Mithril certificate changes, for example, because of a version update. If this happens, none of the new certificates that
Mithril creates can be validated by the bridge code, rendering it useless.

In order to fix this we need a mechanism to update the Mithril verification key once the bridge is deployed. We propose that,
instead of hard-coding it, the certificate's verification key should be a parameter for the transactions. This opens a new vector
of attack by sending a proof that validates trivially so, to avoid this, the verification key's authenticity should be validated somehow.

We think that the easiest way to achieve this is to upload it to the blockchain and to import it in the transactions
in the same way that the stake distribution is managed, i.e. mantaining its identity via an NFT. We have yet to analyze
if this can be done without additional trust assumptions, also because it depends on the mechanisms that Mithril provides,
or not, to sign their protocol versions.

## Stake Distribution Size Reduction

The stake-distribution standard update keeps the reduced Mithril certificate in
the redeemer and stores only a compact chaining state in the emitted UTxO
datum.

This split is intentional:

- The redeemer carries the certificate data that the validator needs to check
  the new update itself: `hash`, `prev_hash`, `epoch`, protocol parameters, the
  protocol-message entries used by the chaining rules, the signed message, the
  aggregate verification key, and the signed-entity classification.
- The datum stores only the state that future transactions must inherit from
  the current certificate: the certificate hash, epoch, protocol parameters,
  current aggregate verification key, and next aggregate verification key.

The large multisignature payload and other metadata that are not consumed by
the on-chain standard-update validation are deliberately excluded from both the
standard redeemer and the datum. The multisignature was the dominant size cost
in the previous design, and it was duplicated because the transaction carried
the same certificate both in the redeemer and again in the inline datum.

With the current design, the standard transaction still validates against the
new certificate contents at spend time, but the persisted UTxO remains small
and only keeps the minimum state needed for the next certificate in the chain.

### Lagrange-Oriented Reduced State

The reduced certificate model is intentionally aligned with the upcoming
Lagrange / `future_snark` Mithril branch rather than with the currently
published Pythagoras-era API payloads.

This means the reduced state keeps both:

- the current `aggregate_verification_key_snark`
- the next `NextSnarkAggregateVerificationKey` announced in the protocol
  message

The standard-certificate chaining rules are then expressed in terms of those
SNARK AVKs:

- if the child certificate stays in the same epoch, its
  `aggregate_verification_key_snark` must equal the parent's current one
- if the child certificate advances by one epoch, its
  `aggregate_verification_key_snark` must equal the parent's announced
  `NextSnarkAggregateVerificationKey`

The older aggregate verification key is still carried in the reduced
redeemer/state because it is part of the reduced certificate shape we expose to
transactions, but the on-chain chaining rule that matters for Lagrange is the
SNARK AVK branch.

### Phase-1 Statement Hash

The phase-1 receipt is now designed to line up with the Lagrange STM circuit.

For this circuit family, the second public input is the Mithril signed
message. Because of that, `phase1.hash_public_inputs(i_1, i_2)` no longer
builds a synthetic hash over both public inputs. Instead, it uses `i_2`
directly as the receipt statement hash.

This gives the later transactions a direct equality check between:

- the `statement_hash` carried by the phase-2 receipt
- the `signed_message` carried by the reduced certificate redeemer

That alignment is what lets the certificate-update transactions consume a real
SNARK-era Mithril signed message without having to translate between two
different hashing conventions or inflate the digest into a larger textual
representation.

### Runtime Integration Note

The verified runtime flow no longer models a single reusable phase-2 receipt.

Today the integration is based on:

- 2 Halo2-backed `phase2_verify` receipts
- a separate Aiken-native genesis-certificate path for
  `stake_distribution_genesis_tx`
- a published reference script for `proof_receipt`
- the receipt UTxOs for:
  - `stake_distribution_standard`
  - `cardano_transactions`
  consumed as normal inputs by the downstream transactions that still need
  them on-chain

This is the main architectural change that made the workflow closer to a real
UTxO flow and removed the earlier "single receipt reused everywhere" model.

### Genesis Certificate Verification

The `stake_distribution_genesis_tx` lane is not supposed to reuse the Halo2
verifier path.

Its trust anchor is the dedicated Aiken mint validator in
`validators/stake_distribution.ak`, which validates a Mithril genesis
certificate against the hardcoded Mithril genesis verification key from
`env/default.ak`.

Concretely:

- the genesis certificate is authenticated by checking its
  `GenesisSignature` with Ed25519 against Mithril's published genesis
  verification key for the target network
- `stake_distribution_genesis_tx` no longer requires a `phase2` receipt input
- the later `stake_distribution_standard_tx` updates then chain from that
  genesis-authenticated parent state using the reduced-certificate Aiken path

### How The Certificate Chain Is Preserved

The certificate chain is still enforced transaction by transaction even though
the full standard certificate is no longer stored in the datum.

The genesis transaction creates the first stake-distribution UTxO with the NFT
and a reduced datum containing the state that future certificates must inherit:
the certificate hash, epoch, protocol parameters, the current aggregate
verification keys, and the next aggregate verification keys announced by the
protocol message.

Each standard certificate update must then spend that previous
stake-distribution UTxO. The validator reads the parent state from the input
datum, reads the new reduced certificate from the redeemer, and reconstructs
the exact reduced state that must be written into the new output datum.

The chain link is enforced by checking:

- the new certificate `prev_hash` matches the digest of the parent hash
- the new epoch is either the same epoch or exactly one more than the parent
- the SNARK aggregate verification key matches either the current parent key or
  the parent's announced next SNARK key, depending on the epoch transition
- the protocol parameters either remain unchanged or match the hash announced by
  the parent protocol message
- the signed message matches the statement hash proven by the consumed phase-2
  receipt input
- the stake-distribution NFT is preserved from the consumed parent UTxO to the
  newly created child UTxO

Because every update must consume the parent UTxO, prove these parent-to-child
relations, and recreate the unique NFT-bearing output with the new reduced
state, the certificate chain remains continuous on-chain without persisting the
full certificate payload.
