//! Unique Schnorr Signature module
//!
//! This module implements a variant of the Schnorr signature algorithm.
//! Specifically, it extends the classic scheme by appending a deterministic
//! value derived solely from the message and the signing key. This ungrindable
//! value produces a unique, reproducible identification tag for each signature,
//! which can be leveraged in lottery-based schemes such as Mithril multi-signatures.

mod error;
mod jubjub;
mod signature;
mod signing_key;
mod verification_key;

pub(crate) type StmError = super::StmError;
pub(crate) type StmResult<T> = super::StmResult<T>;

pub use error::*;
pub use jubjub::BaseFieldElement;
pub(crate) use jubjub::DOMAIN_SEPARATION_TAG_SIGNATURE;
pub(crate) use jubjub::*;
pub use signature::*;
pub use signing_key::*;
pub use verification_key::*;
