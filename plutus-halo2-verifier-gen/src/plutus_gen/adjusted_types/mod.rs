use blake2b_simd::{Params, State};
use blstrs::{G1Projective, Scalar};
// CHANGED vs upstream: added for Midnight support — `ff` traits are needed to
// hash/sample the Midnight scalar via its byte representation.
use ff::{FromUniformBytes, PrimeField};
// CHANGED vs upstream: the halo2 transcript traits are now imported under
// `Halo2*` aliases so the Midnight equivalents (below) can coexist. The STM
// circuit is built on the Midnight stack, so the same Cardano-friendly Blake2b
// transcript must implement both trait families.
use halo2_proofs::transcript::{
    Hashable as Halo2Hashable, Sampleable as Halo2Sampleable,
    TranscriptHash as Halo2TranscriptHash,
};
// CHANGED vs upstream: added — Midnight curve/transcript types so this transcript
// can be reused with the Midnight proving stack.
use midnight_curves::{Fq as MidnightScalar, G1Projective as MidnightG1Projective};
use midnight_proofs::transcript::{
    Hashable as MidnightHashable, Sampleable as MidnightSampleable,
    TranscriptHash as MidnightTranscriptHash,
};
use std::io;
use std::io::Read;

/// Prefix when squeezing challenges from the transcript
const BLAKE2B_PREFIX_CHALLENGE: u8 = 0;

/// Prefix when updating state with prover's messages
const BLAKE2B_PREFIX_COMMON: u8 = 1;

/// Cardano-compatible transcript implementation and related traits for
/// Fiat-Shamir transformation.
// CHANGED vs upstream: added `Clone` to the derive — the Midnight transcript
// machinery requires the hash state to be cloneable.
#[derive(Clone, Debug)]
pub struct CardanoFriendlyBlake2b {
    state: State,
}

/// Cardano-compatible transcript hash for Fiat-Shamir transformation.
///
/// This differs from halo2's default `blake2b_simd::State` implementation:
/// - Uses 32-byte outputs (blake2b-256) instead of 64-byte, since Plutus only
///   exposes `blake2b_256` builtin
/// - Unkeyed hash (no domain separator key), as Plutus doesn't support keyed
///   blake2b
///
/// The prefix bytes (0x00 for squeeze, 0x01 for absorb) match halo2's domain separation scheme.
// CHANGED vs upstream: trait renamed to the `Halo2TranscriptHash` alias (the impl
// body is unchanged); the Midnight counterpart is implemented just below.
impl Halo2TranscriptHash for CardanoFriendlyBlake2b {
    type Input = Vec<u8>;
    type Output = Vec<u8>;

    fn init() -> Self {
        Self {
            state: Params::new().hash_length(32).to_state(),
        }
    }
    fn absorb(&mut self, input: &Self::Input) {
        self.state.update(&[BLAKE2B_PREFIX_COMMON]);
        self.state.update(input);
    }

    fn squeeze(&mut self) -> Self::Output {
        self.state.update(&[BLAKE2B_PREFIX_CHALLENGE]);
        let result = self.state.finalize();
        let result = result.as_bytes();

        // Re-hashing the result to get 32 extra bytes for more randomness for
        // sampling challenges.
        let mut state = Params::new().hash_length(32).to_state();
        state.update(result);
        let digest = state.finalize();
        let re_hash = digest.as_bytes();

        let mut padded_result: [u8; 64] = [0; 64];
        padded_result[..32].copy_from_slice(result);
        padded_result[32..].copy_from_slice(re_hash);
        padded_result.to_vec()
    }
}

// NEW vs upstream: mirror of the Halo2 transcript hash for the Midnight stack.
// It simply delegates to the Halo2 impl, so both stacks share byte-for-byte
// identical Fiat-Shamir behavior.
impl MidnightTranscriptHash for CardanoFriendlyBlake2b {
    type Input = Vec<u8>;
    type Output = Vec<u8>;

    fn init() -> Self {
        <Self as Halo2TranscriptHash>::init()
    }

    fn absorb(&mut self, input: &Self::Input) {
        <Self as Halo2TranscriptHash>::absorb(self, input)
    }

    fn squeeze(&mut self) -> Self::Output {
        <Self as Halo2TranscriptHash>::squeeze(self)
    }
}

/// Standard implementation for Scalar hashing, done as in halo2
// CHANGED vs upstream: the `Scalar`/`G1Projective` impls below are unchanged
// except for the `Halo2*` trait aliases (see the imports). The Midnight scalar
// and point impls that follow them are new.
impl Halo2Hashable<CardanoFriendlyBlake2b> for Scalar {
    fn to_input(&self) -> <CardanoFriendlyBlake2b as Halo2TranscriptHash>::Input {
        <Scalar as Halo2Hashable<State>>::to_input(self)
    }

    fn to_bytes(&self) -> Vec<u8> {
        <Scalar as Halo2Hashable<State>>::to_bytes(self)
    }

    fn read(buffer: &mut impl Read) -> io::Result<Self> {
        <Scalar as Halo2Hashable<State>>::read(buffer)
    }
}

/// Standard implementation for Scalar sampling, done as in halo2
impl Halo2Sampleable<CardanoFriendlyBlake2b> for Scalar {
    fn sample(hash_output: <CardanoFriendlyBlake2b as Halo2TranscriptHash>::Output) -> Self {
        <Scalar as Halo2Sampleable<State>>::sample(hash_output)
    }
}

/// Standard implementation for G1Projective hashing, done as in halo2
impl Halo2Hashable<CardanoFriendlyBlake2b> for G1Projective {
    fn to_input(&self) -> <CardanoFriendlyBlake2b as Halo2TranscriptHash>::Input {
        <G1Projective as Halo2Hashable<State>>::to_input(self)
    }

    fn to_bytes(&self) -> Vec<u8> {
        <G1Projective as Halo2Hashable<State>>::to_bytes(self)
    }

    fn read(buffer: &mut impl Read) -> io::Result<Self> {
        <G1Projective as Halo2Hashable<State>>::read(buffer)
    }
}

// NEW vs upstream: Midnight scalar/point hashing and sampling, so the Midnight
// proof's scalars and BLS12-381 commitments can be absorbed into and squeezed
// from this Cardano-friendly transcript. Encodings go through the Midnight types'
// own `repr`/`GroupEncoding`, and sampling uses 64-byte uniform reduction.
impl MidnightHashable<CardanoFriendlyBlake2b> for MidnightScalar {
    fn to_input(&self) -> Vec<u8> {
        self.to_repr().to_vec()
    }

    fn to_bytes(&self) -> Vec<u8> {
        self.to_repr().to_vec()
    }

    fn read(buffer: &mut impl Read) -> io::Result<Self> {
        let mut bytes = <Self as PrimeField>::Repr::default();
        buffer.read_exact(bytes.as_mut())?;
        Option::from(Self::from_repr(bytes))
            .ok_or_else(|| io::Error::other("Invalid BLS12-381 scalar encoding in proof"))
    }
}

impl MidnightSampleable<CardanoFriendlyBlake2b> for MidnightScalar {
    fn sample(
        hash_output: <CardanoFriendlyBlake2b as MidnightTranscriptHash>::Output,
    ) -> Self {
        assert!(hash_output.len() <= 64);
        let mut bytes = [0u8; 64];
        bytes[..hash_output.len()].copy_from_slice(&hash_output);
        MidnightScalar::from_uniform_bytes(&bytes)
    }
}

impl MidnightHashable<CardanoFriendlyBlake2b> for MidnightG1Projective {
    fn to_input(&self) -> Vec<u8> {
        use group::GroupEncoding;

        GroupEncoding::to_bytes(self).as_ref().to_vec()
    }

    fn to_bytes(&self) -> Vec<u8> {
        use group::GroupEncoding;

        GroupEncoding::to_bytes(self).as_ref().to_vec()
    }

    fn read(buffer: &mut impl Read) -> io::Result<Self> {
        use group::GroupEncoding;

        let mut bytes = <Self as GroupEncoding>::Repr::default();
        buffer.read_exact(bytes.as_mut())?;
        Option::from(Self::from_bytes(&bytes))
            .ok_or_else(|| io::Error::other("Invalid BLS12-381 point encoding in proof"))
    }
}
