//! Shamell's abstraction and utility layer around a future standardized chat protocol engine
//! (target: Signal-style sessions + groups). Phase 0 keeps this minimal and testable.
//!
//! Design goals:
//! - Avoid bespoke protocol crypto in production paths.
//! - Provide deterministic, regression-testable building blocks (e.g. safety numbers).
//! - Keep licensing flexible: do not depend on GPL/AGPL libraries here.
#[derive(Debug, thiserror::Error)]
pub enum SignalError {
    #[error("invalid input: {0}")]
    InvalidInput(&'static str),
    #[error("not implemented")]
    NotImplemented,
}

pub type Result<T> = std::result::Result<T, SignalError>;

/// Signal-style numeric fingerprint / "safety number" generator.
///
/// Notes:
/// - This is **not** message encryption and does not expose plaintext. It's a deterministic
///   display/verification artifact derived from identities.
/// - We intentionally make the output symmetric (A,B) == (B,A) by canonical ordering.
///
/// This is used for key-change detection UX ("verify safety number") during the migration.
pub mod safety_number {
    use super::{Result, SignalError};
    use sha2::{Digest, Sha512};

    pub const DEFAULT_ITERATIONS: usize = 5200;
    const VERSION: u16 = 0;
    type IdentityRef<'a> = (&'a str, &'a [u8]);

    fn iterate_hash(data: &[u8], key: &[u8], count: usize) -> Vec<u8> {
        let mut combined = Vec::with_capacity(data.len() + key.len());
        combined.extend_from_slice(data);
        combined.extend_from_slice(key);

        let mut result = Sha512::digest(&combined).to_vec();
        for _ in 1..count {
            combined.clear();
            combined.extend_from_slice(&result);
            combined.extend_from_slice(key);
            result = Sha512::digest(&combined).to_vec();
        }
        result
    }

    fn get_encoded_chunk(hash: &[u8], offset: usize) -> String {
        let chunk = (hash[offset] as u64) * (1u64 << 32)
            + (hash[offset + 1] as u64) * (1u64 << 24)
            + (hash[offset + 2] as u64) * (1u64 << 16)
            + (hash[offset + 3] as u64) * (1u64 << 8)
            + (hash[offset + 4] as u64);
        let chunk = chunk % 100000;
        format!("{chunk:05}")
    }

    fn display_string_for(identifier: &str, identity_key: &[u8], iterations: usize) -> String {
        let mut bytes = Vec::with_capacity(2 + identity_key.len() + identifier.len());
        bytes.extend_from_slice(&VERSION.to_le_bytes());
        bytes.extend_from_slice(identity_key);
        bytes.extend_from_slice(identifier.as_bytes());

        let output = iterate_hash(&bytes, identity_key, iterations);
        get_encoded_chunk(&output, 0)
            + &get_encoded_chunk(&output, 5)
            + &get_encoded_chunk(&output, 10)
            + &get_encoded_chunk(&output, 15)
            + &get_encoded_chunk(&output, 20)
            + &get_encoded_chunk(&output, 25)
    }

    fn canonical_pair<'a>(
        a_id: &'a str,
        a_key: &'a [u8],
        b_id: &'a str,
        b_key: &'a [u8],
    ) -> (IdentityRef<'a>, IdentityRef<'a>) {
        // Stable ordering so both sides compute the same safety number.
        // We prefer identifier ordering; tie-break by key bytes.
        match a_id.cmp(b_id) {
            std::cmp::Ordering::Less => ((a_id, a_key), (b_id, b_key)),
            std::cmp::Ordering::Greater => ((b_id, b_key), (a_id, a_key)),
            std::cmp::Ordering::Equal => {
                if a_key <= b_key {
                    ((a_id, a_key), (b_id, b_key))
                } else {
                    ((b_id, b_key), (a_id, a_key))
                }
            }
        }
    }

    pub fn safety_number_with_iterations(
        local_identifier: &str,
        local_identity_key: &[u8],
        remote_identifier: &str,
        remote_identity_key: &[u8],
        iterations: usize,
    ) -> Result<String> {
        let local_identifier = local_identifier.trim();
        let remote_identifier = remote_identifier.trim();
        if local_identifier.is_empty() || remote_identifier.is_empty() {
            return Err(SignalError::InvalidInput("empty identifier"));
        }
        if iterations == 0 {
            return Err(SignalError::InvalidInput("iterations must be > 0"));
        }
        if local_identity_key.is_empty() || remote_identity_key.is_empty() {
            return Err(SignalError::InvalidInput("empty identity key"));
        }

        let (a, b) = canonical_pair(
            local_identifier,
            local_identity_key,
            remote_identifier,
            remote_identity_key,
        );
        let a_fp = display_string_for(a.0, a.1, iterations);
        let b_fp = display_string_for(b.0, b.1, iterations);
        Ok(format!("{a_fp}{b_fp}"))
    }

    pub fn safety_number(
        local_identifier: &str,
        local_identity_key: &[u8],
        remote_identifier: &str,
        remote_identity_key: &[u8],
    ) -> Result<String> {
        safety_number_with_iterations(
            local_identifier,
            local_identity_key,
            remote_identifier,
            remote_identity_key,
            DEFAULT_ITERATIONS,
        )
    }
}

/// Phase-0 abstraction point for a future libsignal-backed engine.
///
/// Intentionally incomplete: real session/group primitives will be introduced behind this trait
/// once a vetted, license-compatible implementation is chosen and audited.
pub trait SignalEngine {
    fn backend_name(&self) -> &'static str;
}

pub struct UnimplementedSignalEngine;

impl SignalEngine for UnimplementedSignalEngine {
    fn backend_name(&self) -> &'static str {
        "unimplemented"
    }
}

#[cfg(test)]
mod tests {
    use super::safety_number::{safety_number, safety_number_with_iterations, DEFAULT_ITERATIONS};

    #[test]
    fn safety_number_is_symmetric() {
        let alice_id = "AB12CD34";
        let bob_id = "EF56GH78";
        let alice_key = b"\x05aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        let bob_key = b"\x05bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

        let ab = safety_number(alice_id, alice_key, bob_id, bob_key).expect("safety number");
        let ba = safety_number(bob_id, bob_key, alice_id, alice_key).expect("safety number");
        assert_eq!(ab, ba);
        assert_eq!(ab.len(), 60);
        assert!(ab.chars().all(|c| c.is_ascii_digit()));
    }

    #[test]
    fn safety_number_rejects_empty_inputs() {
        let err = safety_number("", b"k", "B", b"k").expect_err("empty id rejected");
        assert!(matches!(err, super::SignalError::InvalidInput(_)));

        let err = safety_number("A", b"", "B", b"k").expect_err("empty key rejected");
        assert!(matches!(err, super::SignalError::InvalidInput(_)));

        let err = safety_number_with_iterations("A", b"k", "B", b"k", 0)
            .expect_err("bad iterations rejected");
        assert!(matches!(err, super::SignalError::InvalidInput(_)));
    }

    #[test]
    fn safety_number_matches_reference_golden_vector() {
        // This is a deterministic regression test. If this changes, we treat it as a protocol/UX
        // compatibility break and require an explicit migration decision.
        let alice_id = "AB12CD34";
        let bob_id = "EF56GH78";
        let alice_key = b"\x05aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        let bob_key = b"\x05bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

        let fp = safety_number(alice_id, alice_key, bob_id, bob_key).expect("safety number");
        assert_eq!(
            fp,
            "173046012845324248619911109010023170662360669019855543763304"
        );
        assert_eq!(DEFAULT_ITERATIONS, 5200);
    }
}
