# Two-Phase Mithril STM Verification

This document describes how the Mithril STM (Halo2 Multi-Open) verifier generated
by our `plutus-halo2-verifier-gen` fork is split
across two transactions on-chain, why the split exists, what each phase
computes, which NFTs are produced, and which downstream validators consume
them.

## Why two phases?

A full Halo2 Multi-Open verification of a Mithril STM proof does not fit inside
a single Cardano transaction's execution-unit limit. The verifier is therefore
partitioned into two transactions:

- **TX1 / phase 1**: runs the first half of the verifier (transcript squeezing,
  Fiat-Shamir challenges, circuit-expression and vanishing evaluation, building
  `commitment_data`, and the **partial G1 accumulator** over the first slice of
  the multi-open linear combination) and locks the intermediate state in a UTxO.
- **TX2 / phase 2**: spends that UTxO, finishes the verifier (the **rest of the
  G1 linear block** + the final pairing check), and mints a *proof receipt* NFT
  that other validators of the bridge can consume as evidence that the Mithril
  statement has been verified on-chain.

### How the MSM (G1 linear block) is split

The expensive part of the Halo2 Multi-Open verifier is one large multi-scalar
multiplication (MSM): a weighted sum of G1 points that, together with the
public-input term, forms the right-hand side of the final pairing check. That
MSM has **58 terms** in total, grouped into rotation "point sets":

- point set 0: **44** terms (`x1Powers = powers(44)`),
- point set 1: 6, point set 2: 3, point set 3: 2,
- the batched `f_commitment`: 1,
- 2 correction terms: `-v·G` and `x3·pi_term`.

The split is drawn **inside point set 0**:

- **Phase 1 computes 17 terms**, the first 17 entries of set 0 (the
  proof-derived commitments: advice, permuted-lookup, permutation commitments),
  folded with powers of `x1` into a single compressed G1 point, `rhs_prefix`.
  See `accumulate_g1_prefix(x1Powers, set_0, 17)` in
  `lib/two_phase/proof_verifier_phase1.ak`.
- **Phase 2 computes the remaining 41 terms** — the set-0 suffix (27: the VK's
  fixed `f*` and permutation `p*` commitments plus `vanishing_g` /
  `vanishing_rand`) + set 1 (6) + set 2 (3) + set 3 (2) + `f_commitment` (1) +
  the 2 correction terms — adds `rhs_prefix`, and runs the pairing. See
  `phase2_right_accumulator_internal` in
  `lib/two_phase/proof_verifier_phase2.ak`.

The boundary (17 / 41) was chosen to balance the execution-unit cost between the
two transactions.

### Fitting the Plutus budget: the split plus on-chain refactors

A single-transaction verifier for this circuit blows past both the
execution-unit (CPU/memory) budget and the transaction-size limit. The first
step happened in `plutus-halo2-verifier-gen`: the generated Halo2 Multi-Open
verifier was made split-friendly by emitting the large MSM as generated,
partitionable code instead of a single opaque helper call (see point 4 of
`plutus-halo2-verifier-gen/PLUTUS_HALO2_VERIFIER_CHANGES.md`). That was only
the starting point. The Aiken verifier in `bridge-aiken` still needed several
manual refactors before both transactions fit.

- **Split the generated verifier into a compact two-phase hand-off.** The
  generated single verifier surface was replaced with two on-chain phases. TX1
  computes only the proof-derived state needed by TX2: `rhs_prefix`, `x1`,
  `x3`, `x4`, `v`, and `reduced_hash`. TX2 receives the 15 remaining G1 points
  as `ReducedRedeemer`, checks
  `blake2b_256(serialize_reduced_redeemer(redeemer)) == reduced_hash`, adds the
  remaining MSM terms, and runs the final pairing. This compact datum /
  redeemer split keeps the phase-2 UTxO from carrying the whole proof.
- **Move the MSM split into dedicated helpers.**
  `lib/halo2/halo2_kzg_split.ak` contains the two-phase MSM helpers and the
  canonical reduced-redeemer serialization. `accumulate_g1` builds a partial G1
  accumulator for a set, while `accumulate_g1_prefix` lets TX1 accumulate the
  first 17 set-0 terms directly instead of first building `take(set_0, 17)` and
  `take(x1Powers, 17)` intermediate lists.
- **Reduce intermediate list allocation in KZG helper code.**
  `compute_q_eval_for_set` and `compute_v` were rewritten away from
  `foldl`/`zip`/`map`/`map2`/`concat` chains into direct recursion. This keeps
  the same arithmetic but reduces intermediate list construction in the hot
  verifier path.
- **Bind the statement directly to the Mithril message digest.** The phase-1
  validator stopped computing a synthetic hash of `(i_1, i_2)` and stores
  `statement_hash = i_2` directly. In the STM circuit used here, `i_2` is
  already the Mithril signed message digest, so the extra `blake2b_256` and
  prefix concatenation were not needed.
- **Keep production validators free of test-only code.** Test constants and
  helper functions were moved out of `validators/phase1.ak` and
  `validators/phase2.ak`. This did not change the cryptographic algorithm, but
  it reduced production validator size/noise.
- **Make TX1 use a state-only verifier path.** The main memory reduction came
  from making the phase-1 mint policy call `phase1_verifier_state` instead of
  the full `phase1_verifier` surface. TX1 no longer builds and returns a
  `ReducedRedeemer`; it computes only the `Phase1State` that must be locked for
  TX2.
- **Hash reduced-redeemer fields without materializing the redeemer.**
  `serialize_reduced_redeemer_fields` lets phase 1 compute `reduced_hash` from
  the individual proof points already in scope, avoiding construction of the
  full `ReducedRedeemer` record on the state-only path.
- **Specialize the Lagrange and instance evaluations used by phase 1.** Phase 1
  computes the exact vanishing-window aggregates it needs through
  `phase1_vanishing_lagrange_terms`, and computes the two-public-input instance
  evaluation through `phase1_instance_eval_2`. These replace generic
  rotation/basis list construction where TX1 only needs fixed aggregates.
- **Batch scalar inversions with Montgomery's trick.** The specialized
  vanishing-window evaluation multiplies the 8 denominators into prefix
  products, inverts the final product once with `recip_eea`, and walks the
  prefixes back to recover each inverse. One scalar inversion replaces eight.
- **Tune the split boundary.** The resulting verifier keeps the 17 / 41 split
  of the G1 linear block, chosen to balance the execution-unit cost of TX1 and
  TX2 so that neither transaction dominates the budget.

Both phases share the data types defined in
`lib/two_phase/two_phase_types.ak` (`Phase1State`, `Phase2State`,
`ReducedRedeemer`, `ProofReceiptDatum`, `Phase2Redeemer`).

## End-to-end flow

```
            +-----------------------------+
            |        Off-chain prover      |
            |  (Halo2 Multi-Open prover)   |
            +--------------+--------------+
                           |
                           v
        TX1 (phase1 mint policy)
        - input:  user UTxO + signer
        - mint:   1 NFT @ phase1 policy, name = reduced_hash
        - output: phase2 script UTxO with Phase2State datum
                  carrying { Phase1State, phase1_signer,
                             reclaim_after, statement_hash }
                           |
                           v
        TX2 (phase2 spend + phase2 mint)
        - input:   the phase2 UTxO  (must be signed by phase1_signer)
        - spend:   Verify(reduced_redeemer) -> phase2_verifier
                   OR Recover (after reclaim_after, no mint)
        - mint:    1 NFT @ phase2 policy, name = reduced_hash
        - output:  proof_receipt script UTxO with
                   ProofReceiptDatum { statement_hash } + the NFT
                           |
                           v
        Downstream consumers (stake_distribution, minting)
        - reference / spend the proof receipt
        - read statement_hash from its datum
        - feed it into Mithril certificate verification
```

## NFTs produced

Two distinct NFTs are minted along the way:

- **Phase-1 NFT** (minted in TX1, policy = phase-1 mint policy,
  `asset_name = reduced_hash`). It is created by TX1 and locked into the
  phase-2 script output. Its only purpose is to bind the phase-2 UTxO to the
  exact proof data committed in phase 1; it is never read outside the TX1 →
  TX2 pair.

- **Proof receipt NFT** (minted in TX2, policy = phase-2 policy,
  `asset_name = reduced_hash`). It is deposited at the proof-receipt script
  address together with an inline datum `ProofReceiptDatum { statement_hash }`.
  This NFT + datum is the evidence that a Mithril STM proof has been verified
  on-chain for that particular statement hash.

In both cases `asset_name = reduced_hash`, which is the `blake2b_256` of the
serialised `ReducedRedeemer`. This ties phase 1, phase 2, and the receipt to
the same proof object end-to-end.

## Where the proof receipt is used

The proof receipt is the bridge between the Mithril STM verifier and the rest
of the bridge logic. Two validators consume it:

- **`validators/stake_distribution.ak`**, `stake_distribution_validator_spend`
  (line ~235): when rotating the stake-distribution certificate, the
  transaction must consume a phase-2 receipt. The validator reads the
  receipt's `statement_hash` (via `proof_receipt.statement_hash`) and uses it
  as the Mithril signed message that the new certificate must match against
  the parent certificate stored in the input datum.

- **`validators/minting.ak`**, `minting_validator` (line ~129): when minting
  bridge tokens, the validator pulls the receipt's `statement_hash` and
  feeds it into the Mithril certificate check, alongside a Merkle membership
  proof that the locking transaction is included in the snapshot certified
  by that statement. The proved `locking_tx_hash` is the canonical Cardano
  transaction id (`blake2b_256(tx_body_CBOR)`) of the locking transaction,
  not a bridge-specific digest. The validator reconstructs the canonical
  minimal locking transaction body from the redeemer, hashes it on-chain, and
  requires that hash to match the proved snapshot leaf. This makes the mint
  cryptographically depend on the actual locked amount and destination, not
  only on redeemer fields that are internally consistent.

The shared lookup helpers all live in `lib/two_phase/proof_receipt.ak`:
`find_phase2_input` (locate the receipt input by script credential + policy
id), `statement_hash` (extract `statement_hash` from the receipt datum), and
`has_input` (existence check).

---

# Validator details

The remainder of this document describes what each validator computes and
enforces in detail.

## Phase 1 — `validators/phase1.ak`

Phase 1 is implemented as a **mint policy**.

### What it computes

`proof_verifier_phase1.phase1_verifier(proof, i_1, i_2)` runs the first half
of the Halo2 Multi-Open verifier and produces a `Phase1State` containing:

- `rhs_prefix`: compressed G1 partial accumulator (48 bytes) — the sum of the
  **first 17 MSM terms** of point set 0 (see "How the MSM is split" above).
- `reduced_hash`: `blake2b_256` of the serialised `ReducedRedeemer` that
  phase 2 will later have to provide. This binds phase 2 to the exact proof
  data committed to in phase 1.
- `x1`, `x3`, `x4`: transcript challenges (32-byte little-endian scalars).
- `v`: precomputed blinding scalar (32 bytes).

`i_1` and `i_2` are the two public inputs of the STM circuit. In the upcoming
SNARK-based Mithril era, `i_2` is the signed message digest itself, so the
phase-1 validator stores `statement_hash = i_2` directly in the phase-2 datum.

### What the on-chain validator enforces

Given the redeemer `Phase1Redeemer { proof, i_1, i_2, phase2_policy_id, reclaim_after }`,
the policy succeeds iff:

1. The transaction has exactly one entry in `extra_signatories`. That signer
   is recorded in the phase-2 datum as `phase1_signer` and becomes the only
   party allowed to finalize phase 2 or to reclaim the UTxO after the
   timeout.
2. The transaction mints exactly one NFT under this policy whose
   `asset_name = reduced_hash`.
3. The transaction creates exactly one output to the phase-2 script address,
   that output contains the freshly minted NFT, and its inline datum is the
   expected `Phase2State { proof_state, phase1_signer, reclaim_after, statement_hash = i_2 }`.

## Phase 2 — `validators/phase2.ak`

Phase 2 is **both** a spend validator and a mint policy. The script hash and
the mint policy id intentionally coincide: the spend branch can recover its
own policy id from the consumed input, and the mint branch fails unless an
input from this same script is being spent (`spends_own_script_input`).
This couples minting the proof receipt to executing the spend branch.

The validator is parameterized by `proof_receipt_spending_script: PaymentCredential`,
the script credential where the proof receipt UTxO must be sent.

### Spend branch — `Verify(reduced_redeemer)`

This is the success path. It enforces:

1. `state.phase1_signer` is in `extra_signatories` (only the original phase-1
   signer can finalize).
2. `phase2_verifier(state.proof_state, reduced_redeemer)` succeeds. This
   completes the linear block of the Halo2 verifier: the **remaining 41 MSM
   terms** (set-0 suffix + sets 1/2/3 + `f_commitment` + the `-v·G` and
   `x3·pi_term` corrections), added to `rhs_prefix` from phase 1. It also executes
   the final pairing check. It also re-checks the hash binding
   `blake2b_256(serialize_reduced_redeemer(redeemer)) == state.reduced_hash`
   so the redeemer points match what phase 1 committed to.
3. The transaction mints exactly one NFT under this policy with
   `asset_name = state.proof_state.reduced_hash` (so the proof receipt NFT is
   bound to the same proof data committed in phase 1).
4. The transaction creates exactly one output at `proof_receipt_spending_script`
   that contains the minted NFT and carries
   `InlineDatum(ProofReceiptDatum { statement_hash: state.statement_hash })`.

### Spend branch — `Recover`

Timed-recovery path. It succeeds iff `tx.validity_range` lies entirely after
`state.reclaim_after` and the transaction performs no minting. Combined with
the universal check that `state.phase1_signer` signs the transaction, this
lets the original signer reclaim the UTxO after the deadline if phase 2 was
never finalized.

### Mint branch

Authorised iff the redeemer is the asset name being minted, the transaction
mints exactly that single NFT, and at least one input under this policy's
script is being spent. This forces minting to happen jointly with the
`Verify` spend.

## The proof receipt validator — `validators/proof_receipt.ak`

A trivial spend validator that always succeeds. Its only role is to provide a
known script credential where proof receipts live; the real checks happen at
the consumers, which read the receipt's datum and verify that the NFT belongs
to the phase-2 policy.
