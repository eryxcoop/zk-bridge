# Stage 0 fixtures

These files complete **stage 0** of the plan in
[`../README.md`](../README.md).

They provide canonical vectors for:

- one valid Jubjub Schnorr verification case
- several negative cases derived from it

## Provenance

The valid tuple is derived from deterministic upstream Mithril STM test vectors:

- `mithril-stm/src/signature_scheme/schnorr_signature/verification_key.rs`
  - `golden` bytes for `SchnorrVerificationKey`
- `mithril-stm/src/signature_scheme/schnorr_signature/standard_signature.rs`
  - `golden` bytes for `StandardSchnorrSignature`

Important subtlety:

- Mithril's `StandardSchnorrSignature::golden_value()` signs a
  `BaseFieldElement::try_from([0u8; 32])`
- `BaseFieldElement::try_from(bytes)` first computes `sha256(bytes)` and then
  reduces the 32-byte digest into the Jubjub base field

Therefore the canonical `sha256_digest_hex` used here is:

- `sha256(0x00 * 32)`

That makes these fixtures directly usable for the planned genesis-oriented
statement:

- circuit input = `sha256_digest`
- circuit internally reduces digest -> `BaseFieldElement`

## Files

- `valid_deterministic_vector.json`
  - canonical valid tuple
- `negative_vectors.json`
  - digest/signature/key mutations and an explicit torsion-point case
