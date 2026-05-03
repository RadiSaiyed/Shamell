use crate::state::AppState;
use aes_gcm_siv::aead::{Aead, KeyInit, Payload};
use aes_gcm_siv::{Aes256GcmSiv, Nonce};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use getrandom::getrandom;
use sha2::{Digest, Sha256};
use sqlx::Row;
use std::error::Error;
use std::fmt::{self, Display, Formatter};

const PUSH_TOKEN_CIPHERTEXT_PREFIX_V1: &str = "enc:v1:";
const PUSH_TOKEN_CIPHERTEXT_PREFIX_V2: &str = "enc:v2:";
const PUSH_TOKEN_AAD: &[u8] = b"shamell-chat-push-token-v1";
const PUSH_TOKEN_NONCE_SIZE: usize = 12;
const PUSH_TOKEN_LOOKUP_HASH_CONTEXT: &[u8] = b"shamell-chat-push-token-v2:lookup-hash";

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PushTokenLookupCandidates {
    pub primary_storage_value: String,
    pub lookup_hash_value: String,
    pub legacy_plaintext_value: Option<String>,
}

#[derive(Clone)]
pub struct PushTokenProtector {
    key: Option<[u8; 32]>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PushTokenProtectionError {
    InvalidInput(&'static str),
    RandomnessUnavailable,
    EncryptFailed,
    DecryptFailed,
    InvalidStoredValue(&'static str),
    InvalidUtf8,
}

impl Display for PushTokenProtectionError {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidInput(detail) => write!(f, "invalid push token input: {detail}"),
            Self::RandomnessUnavailable => f.write_str("secure randomness unavailable"),
            Self::EncryptFailed => f.write_str("push token encryption failed"),
            Self::DecryptFailed => f.write_str("push token decryption failed"),
            Self::InvalidStoredValue(detail) => {
                write!(f, "invalid stored push token value: {detail}")
            }
            Self::InvalidUtf8 => f.write_str("stored push token is not valid UTF-8"),
        }
    }
}

impl Error for PushTokenProtectionError {}

impl PushTokenProtector {
    pub fn new(key: Option<[u8; 32]>) -> Self {
        Self { key }
    }

    pub fn is_enabled(&self) -> bool {
        self.key.is_some()
    }

    pub fn is_encrypted_storage_value(raw: &str) -> bool {
        raw.starts_with(PUSH_TOKEN_CIPHERTEXT_PREFIX_V1)
            || raw.starts_with(PUSH_TOKEN_CIPHERTEXT_PREFIX_V2)
    }

    pub fn storage_value_for_plaintext(
        &self,
        plaintext: &str,
    ) -> Result<String, PushTokenProtectionError> {
        Self::validate_plaintext(plaintext)?;
        if !self.is_enabled() {
            return Ok(plaintext.to_string());
        }

        let cipher = self.cipher()?;
        let mut nonce_bytes = [0u8; PUSH_TOKEN_NONCE_SIZE];
        getrandom(&mut nonce_bytes).map_err(|_| PushTokenProtectionError::RandomnessUnavailable)?;
        let ciphertext = cipher
            .encrypt(
                Nonce::from_slice(&nonce_bytes),
                Payload {
                    msg: plaintext.as_bytes(),
                    aad: PUSH_TOKEN_AAD,
                },
            )
            .map_err(|_| PushTokenProtectionError::EncryptFailed)?;
        let mut blob = Vec::with_capacity(PUSH_TOKEN_NONCE_SIZE + ciphertext.len());
        blob.extend_from_slice(&nonce_bytes);
        blob.extend_from_slice(&ciphertext);
        Ok(format!(
            "{PUSH_TOKEN_CIPHERTEXT_PREFIX_V2}{}",
            URL_SAFE_NO_PAD.encode(blob)
        ))
    }

    pub fn lookup_hash_for_plaintext(
        &self,
        plaintext: &str,
    ) -> Result<String, PushTokenProtectionError> {
        Self::validate_plaintext(plaintext)?;
        let mut hasher = Sha256::new();
        hasher.update(PUSH_TOKEN_LOOKUP_HASH_CONTEXT);
        hasher.update([0x00]);
        if let Some(key) = self.key.as_ref() {
            hasher.update([0x01]);
            hasher.update(key);
        } else {
            hasher.update([0x00]);
        }
        hasher.update([0x00]);
        hasher.update(plaintext.as_bytes());
        Ok(hex::encode(hasher.finalize()))
    }

    pub fn lookup_candidates_for_plaintext(
        &self,
        plaintext: &str,
    ) -> Result<PushTokenLookupCandidates, PushTokenProtectionError> {
        let lookup_hash_value = self.lookup_hash_for_plaintext(plaintext)?;
        let primary_storage_value = self.storage_value_for_plaintext(plaintext)?;
        Ok(PushTokenLookupCandidates {
            primary_storage_value,
            lookup_hash_value,
            legacy_plaintext_value: self.is_enabled().then(|| plaintext.to_string()),
        })
    }

    pub fn recover_plaintext_from_storage(
        &self,
        stored: &str,
    ) -> Result<String, PushTokenProtectionError> {
        let Some(payload_b64) = encrypted_payload(stored) else {
            return Ok(stored.to_string());
        };
        let blob = URL_SAFE_NO_PAD
            .decode(payload_b64.as_bytes())
            .map_err(|_| PushTokenProtectionError::InvalidStoredValue("invalid base64 payload"))?;
        if blob.len() <= PUSH_TOKEN_NONCE_SIZE {
            return Err(PushTokenProtectionError::InvalidStoredValue(
                "ciphertext payload too short",
            ));
        }
        let (nonce, ciphertext) = blob.split_at(PUSH_TOKEN_NONCE_SIZE);
        let cipher = self.cipher()?;
        let plaintext = cipher
            .decrypt(
                Nonce::from_slice(nonce),
                Payload {
                    msg: ciphertext,
                    aad: PUSH_TOKEN_AAD,
                },
            )
            .map_err(|_| PushTokenProtectionError::DecryptFailed)?;
        String::from_utf8(plaintext).map_err(|_| PushTokenProtectionError::InvalidUtf8)
    }

    fn cipher(&self) -> Result<Aes256GcmSiv, PushTokenProtectionError> {
        let key = self
            .key
            .as_ref()
            .ok_or(PushTokenProtectionError::InvalidStoredValue(
                "protector key is not configured",
            ))?;
        Aes256GcmSiv::new_from_slice(key.as_slice())
            .map_err(|_| PushTokenProtectionError::InvalidStoredValue("invalid protector key"))
    }

    fn validate_plaintext(plaintext: &str) -> Result<(), PushTokenProtectionError> {
        if plaintext.trim().is_empty() {
            return Err(PushTokenProtectionError::InvalidInput(
                "token must not be blank",
            ));
        }
        if Self::is_encrypted_storage_value(plaintext) {
            return Err(PushTokenProtectionError::InvalidInput(
                "reserved encrypted storage prefix",
            ));
        }
        Ok(())
    }
}

fn encrypted_payload(stored: &str) -> Option<&str> {
    if let Some(stripped) = stored.strip_prefix(PUSH_TOKEN_CIPHERTEXT_PREFIX_V2) {
        return Some(stripped);
    }
    stored.strip_prefix(PUSH_TOKEN_CIPHERTEXT_PREFIX_V1)
}

pub async fn backfill_legacy_push_tokens(state: &AppState) -> Result<u64, String> {
    let push_tokens = state.table("push_tokens");
    let rows = sqlx::query(&format!(
        "SELECT token, token_lookup_hash FROM {push_tokens}"
    ))
    .fetch_all(&state.pool)
    .await
    .map_err(|e| format!("load push tokens for backfill failed: {e}"))?;

    let mut updated = 0u64;
    for row in rows {
        let raw_token: String = row
            .try_get("token")
            .map_err(|e| format!("read stored push token failed: {e}"))?;
        let stored_lookup_hash: Option<String> = row
            .try_get("token_lookup_hash")
            .map_err(|e| format!("read stored push token lookup hash failed: {e}"))?;
        let plaintext = if PushTokenProtector::is_encrypted_storage_value(&raw_token) {
            if !state.push_token_protector.is_enabled() {
                raw_token.clone()
            } else {
                state
                    .push_token_protector
                    .recover_plaintext_from_storage(&raw_token)
                    .map_err(|e| format!("decrypt stored push token failed: {e}"))?
            }
        } else {
            raw_token.clone()
        };
        let encrypted = if state.push_token_protector.is_enabled()
            && !raw_token.starts_with(PUSH_TOKEN_CIPHERTEXT_PREFIX_V2)
        {
            state
                .push_token_protector
                .storage_value_for_plaintext(&plaintext)
                .map_err(|e| format!("encrypt legacy push token failed: {e}"))?
        } else {
            raw_token.clone()
        };
        let lookup_hash = state
            .push_token_protector
            .lookup_hash_for_plaintext(&plaintext)
            .map_err(|e| format!("derive push token lookup hash failed: {e}"))?;
        if encrypted == raw_token && stored_lookup_hash.as_deref() == Some(lookup_hash.as_str()) {
            continue;
        }
        let result = sqlx::query(&format!(
            "UPDATE {push_tokens} SET token=$1, token_lookup_hash=$2 WHERE token=$3"
        ))
        .bind(&encrypted)
        .bind(&lookup_hash)
        .bind(&raw_token)
        .execute(&state.pool)
        .await
        .map_err(|e| format!("persist protected push token failed: {e}"))?;
        updated += result.rows_affected();
    }

    Ok(updated)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn push_token_ciphertext_round_trip_is_randomized_and_recoverable() {
        let protector = PushTokenProtector::new(Some([9u8; 32]));
        let token = "fcm-registration-token-123456";
        let ciphertext_a = protector
            .storage_value_for_plaintext(token)
            .expect("ciphertext");
        let ciphertext_b = protector
            .storage_value_for_plaintext(token)
            .expect("ciphertext");
        assert_ne!(ciphertext_a, ciphertext_b);
        assert_ne!(ciphertext_a, token);
        assert!(PushTokenProtector::is_encrypted_storage_value(
            &ciphertext_a
        ));
        assert_eq!(
            protector
                .recover_plaintext_from_storage(&ciphertext_a)
                .expect("round trip"),
            token
        );
    }

    #[test]
    fn push_token_lookup_hash_is_stable_for_same_plaintext() {
        let protector = PushTokenProtector::new(Some([9u8; 32]));
        let token = "fcm-registration-token-123456";
        let hash_a = protector
            .lookup_hash_for_plaintext(token)
            .expect("lookup hash");
        let hash_b = protector
            .lookup_hash_for_plaintext(token)
            .expect("lookup hash");
        assert_eq!(hash_a, hash_b);
        assert_eq!(hash_a.len(), 64);
    }

    #[test]
    fn lookup_candidates_include_legacy_plaintext_during_rollout() {
        let protector = PushTokenProtector::new(Some([9u8; 32]));
        let token = "fcm-registration-token-123456";
        let candidates = protector
            .lookup_candidates_for_plaintext(token)
            .expect("lookup candidates");
        assert_ne!(candidates.primary_storage_value, token);
        assert_eq!(candidates.lookup_hash_value.len(), 64);
        assert_eq!(candidates.legacy_plaintext_value.as_deref(), Some(token));
    }

    #[test]
    fn recover_plaintext_accepts_legacy_raw_storage_value() {
        let protector = PushTokenProtector::new(Some([9u8; 32]));
        let token = "legacy-fcm-token";
        assert_eq!(
            protector
                .recover_plaintext_from_storage(token)
                .expect("legacy plaintext passthrough"),
            token
        );
    }
}
