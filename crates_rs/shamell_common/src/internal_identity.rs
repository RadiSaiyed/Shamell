use axum::http::Method;
use base64::engine::general_purpose::STANDARD_NO_PAD;
use base64::Engine;
use ed25519_dalek::{Signature, Signer, SigningKey, Verifier, VerifyingKey};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

pub const INTERNAL_SERVICE_ID_HEADER: &str = "x-internal-service-id";
pub const INTERNAL_IDENTITY_AUDIENCE_HEADER: &str = "x-internal-audience";
pub const INTERNAL_IDENTITY_TS_HEADER: &str = "x-internal-identity-ts";
pub const INTERNAL_IDENTITY_SIG_HEADER: &str = "x-internal-identity-sig";
pub const INTERNAL_IDENTITY_SIG_V2_HEADER: &str = "x-internal-identity-sig-v2";
pub const INTERNAL_IDENTITY_NONCE_HEADER: &str = "x-internal-identity-nonce";

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SignedInternalIdentity {
    pub service_id: String,
    pub audience: String,
    pub timestamp: i64,
    pub nonce: String,
    pub signature_b64: String,
    pub signature_v2_b64: String,
}

#[derive(Clone)]
pub struct InternalRequestSigner {
    service_id: String,
    signing_key: SigningKey,
}

#[derive(Clone)]
pub struct InternalIdentityVerifier {
    allowed_keys: HashMap<String, Vec<VerifyingKey>>,
    max_skew_secs: i64,
}

#[derive(Clone, Copy)]
pub struct InternalIdentityVerification<'a> {
    pub service_id: &'a str,
    pub audience: &'a str,
    pub timestamp: i64,
    pub nonce: &'a str,
    pub signature_b64: &'a str,
    pub method: &'a Method,
    pub path_and_query: &'a str,
    pub body: &'a [u8],
}

#[derive(Clone, Copy)]
pub struct LegacyInternalIdentityVerification<'a> {
    pub service_id: &'a str,
    pub timestamp: i64,
    pub nonce: &'a str,
    pub signature_b64: &'a str,
    pub method: &'a Method,
    pub path_and_query: &'a str,
    pub body: &'a [u8],
}

impl InternalRequestSigner {
    pub fn from_seed_base64(service_id: impl AsRef<str>, seed_b64: &str) -> Result<Self, String> {
        let seed = decode_fixed::<32>(seed_b64, "Ed25519 seed")?;
        Self::from_seed_bytes(service_id, seed)
    }

    pub fn from_seed_bytes(service_id: impl AsRef<str>, seed: [u8; 32]) -> Result<Self, String> {
        Ok(Self {
            service_id: normalize_service_id(service_id.as_ref())?,
            signing_key: SigningKey::from_bytes(&seed),
        })
    }

    pub fn service_id(&self) -> &str {
        &self.service_id
    }

    pub fn seed_base64(&self) -> String {
        STANDARD_NO_PAD.encode(self.signing_key.to_bytes())
    }

    pub fn public_key_base64(&self) -> String {
        STANDARD_NO_PAD.encode(self.signing_key.verifying_key().to_bytes())
    }

    pub fn sign(
        &self,
        method: &Method,
        audience: &str,
        path_and_query: &str,
        body: &[u8],
    ) -> Result<SignedInternalIdentity, String> {
        let timestamp = now_unix_secs()?;
        let nonce = Uuid::new_v4().simple().to_string();
        self.sign_at_with_nonce(method, audience, path_and_query, body, timestamp, &nonce)
    }

    pub fn sign_at(
        &self,
        method: &Method,
        audience: &str,
        path_and_query: &str,
        body: &[u8],
        timestamp: i64,
    ) -> Result<SignedInternalIdentity, String> {
        let nonce = Uuid::new_v4().simple().to_string();
        self.sign_at_with_nonce(method, audience, path_and_query, body, timestamp, &nonce)
    }

    pub fn sign_at_with_nonce(
        &self,
        method: &Method,
        audience: &str,
        path_and_query: &str,
        body: &[u8],
        timestamp: i64,
        nonce: &str,
    ) -> Result<SignedInternalIdentity, String> {
        let audience = normalize_audience(audience)?;
        let nonce = normalize_nonce(nonce)?;
        let legacy_msg = canonical_message_v1(
            &self.service_id,
            method,
            path_and_query,
            timestamp,
            &nonce,
            body,
        )?;
        let msg_v2 = canonical_message_v2(
            &self.service_id,
            &audience,
            method,
            path_and_query,
            timestamp,
            &nonce,
            body,
        )?;
        let legacy_signature = self.signing_key.sign(&legacy_msg);
        let signature_v2 = self.signing_key.sign(&msg_v2);
        Ok(SignedInternalIdentity {
            service_id: self.service_id.clone(),
            audience,
            timestamp,
            nonce,
            signature_b64: STANDARD_NO_PAD.encode(legacy_signature.to_bytes()),
            signature_v2_b64: STANDARD_NO_PAD.encode(signature_v2.to_bytes()),
        })
    }
}

impl InternalIdentityVerifier {
    pub fn from_public_keys_base64(
        public_keys: Vec<(String, String)>,
        max_skew_secs: i64,
    ) -> Result<Self, String> {
        if max_skew_secs <= 0 {
            return Err("internal identity max skew must be > 0".to_string());
        }
        let mut allowed_keys: HashMap<String, Vec<VerifyingKey>> = HashMap::new();
        for (caller, public_key_b64) in public_keys {
            let caller = normalize_service_id(&caller)?;
            let key_bytes = decode_fixed::<32>(&public_key_b64, "Ed25519 public key")?;
            let verifying_key = VerifyingKey::from_bytes(&key_bytes)
                .map_err(|_| format!("invalid Ed25519 public key for caller {caller}"))?;
            allowed_keys.entry(caller).or_default().push(verifying_key);
        }
        if allowed_keys.is_empty() {
            return Err("at least one internal identity public key is required".to_string());
        }
        Ok(Self {
            allowed_keys,
            max_skew_secs,
        })
    }

    pub fn verify(&self, request: InternalIdentityVerification<'_>) -> Result<String, String> {
        let now = now_unix_secs()?;
        self.verify_at(request, now)
    }

    pub fn verify_at(
        &self,
        request: InternalIdentityVerification<'_>,
        now: i64,
    ) -> Result<String, String> {
        let caller = normalize_service_id(request.service_id)?;
        let audience = normalize_audience(request.audience)?;
        let nonce = normalize_nonce(request.nonce)?;
        let allowed_keys = self
            .allowed_keys
            .get(&caller)
            .ok_or_else(|| "internal caller not recognized".to_string())?;
        let skew = (now - request.timestamp).abs();
        if skew > self.max_skew_secs {
            return Err("internal identity timestamp expired".to_string());
        }
        let signature_bytes = decode_fixed::<64>(request.signature_b64, "Ed25519 signature")?;
        let signature = Signature::from_bytes(&signature_bytes);
        let msg = canonical_message_v2(
            &caller,
            &audience,
            request.method,
            request.path_and_query,
            request.timestamp,
            &nonce,
            request.body,
        )?;
        if allowed_keys
            .iter()
            .any(|key| key.verify(&msg, &signature).is_ok())
        {
            return Ok(caller);
        }
        Err("internal identity signature invalid".to_string())
    }

    pub fn verify_legacy(
        &self,
        request: LegacyInternalIdentityVerification<'_>,
    ) -> Result<String, String> {
        let now = now_unix_secs()?;
        self.verify_legacy_at(request, now)
    }

    pub fn verify_legacy_at(
        &self,
        request: LegacyInternalIdentityVerification<'_>,
        now: i64,
    ) -> Result<String, String> {
        let caller = normalize_service_id(request.service_id)?;
        let nonce = normalize_nonce(request.nonce)?;
        let allowed_keys = self
            .allowed_keys
            .get(&caller)
            .ok_or_else(|| "internal caller not recognized".to_string())?;
        let skew = (now - request.timestamp).abs();
        if skew > self.max_skew_secs {
            return Err("internal identity timestamp expired".to_string());
        }
        let signature_bytes = decode_fixed::<64>(request.signature_b64, "Ed25519 signature")?;
        let signature = Signature::from_bytes(&signature_bytes);
        let msg = canonical_message_v1(
            &caller,
            request.method,
            request.path_and_query,
            request.timestamp,
            &nonce,
            request.body,
        )?;
        if allowed_keys
            .iter()
            .any(|key| key.verify(&msg, &signature).is_ok())
        {
            return Ok(caller);
        }
        Err("internal identity signature invalid".to_string())
    }

    pub fn max_skew_secs(&self) -> i64 {
        self.max_skew_secs
    }
}

pub fn parse_public_keys_csv(raw: &str) -> Result<Vec<(String, String)>, String> {
    let mut out = Vec::new();
    for item in raw.split(',') {
        let trimmed = item.trim();
        if trimmed.is_empty() {
            continue;
        }
        let (caller, public_key_b64) = trimmed
            .split_once('=')
            .ok_or_else(|| "must use caller=base64_public_key entries".to_string())?;
        let caller = normalize_service_id(caller)?;
        let public_key_b64 = public_key_b64.trim();
        if public_key_b64.is_empty() {
            return Err(format!("missing public key for caller {caller}"));
        }
        let _ = decode_fixed::<32>(public_key_b64, "Ed25519 public key")
            .map_err(|_| format!("invalid Ed25519 public key for caller {caller}"))?;
        out.push((caller, public_key_b64.to_string()));
    }
    Ok(out)
}

fn normalize_service_id(raw: &str) -> Result<String, String> {
    let caller = raw.trim().to_ascii_lowercase();
    if caller.is_empty()
        || caller.len() > 64
        || !caller
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'))
    {
        return Err("service id must be 1..64 [A-Za-z0-9-_.]".to_string());
    }
    Ok(caller)
}

fn normalize_audience(raw: &str) -> Result<String, String> {
    normalize_service_id(raw)
}

fn normalize_nonce(raw: &str) -> Result<String, String> {
    let nonce = raw.trim().to_ascii_lowercase();
    if nonce.len() < 16 || nonce.len() > 64 || !nonce.chars().all(|c| c.is_ascii_alphanumeric()) {
        return Err("internal identity nonce must be 16..64 ascii alnum".to_string());
    }
    Ok(nonce)
}

fn decode_fixed<const N: usize>(raw: &str, label: &str) -> Result<[u8; N], String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Err(format!("{label} must not be empty"));
    }
    let decoded = STANDARD_NO_PAD
        .decode(trimmed)
        .or_else(|_| base64::engine::general_purpose::STANDARD.decode(trimmed))
        .map_err(|_| format!("{label} must be base64"))?;
    let bytes: [u8; N] = decoded
        .as_slice()
        .try_into()
        .map_err(|_| format!("{label} must decode to {N} bytes"))?;
    Ok(bytes)
}

fn canonical_message_v1(
    service_id: &str,
    method: &Method,
    path_and_query: &str,
    timestamp: i64,
    nonce: &str,
    body: &[u8],
) -> Result<Vec<u8>, String> {
    if !path_and_query.starts_with('/') {
        return Err("internal identity path must start with '/'".to_string());
    }
    let body_hash = STANDARD_NO_PAD.encode(Sha256::digest(body));
    Ok(format!(
        "shamell-internal-v1\n{service_id}\n{}\n{path_and_query}\n{timestamp}\n{nonce}\n{body_hash}",
        method.as_str().to_ascii_uppercase()
    )
    .into_bytes())
}

fn canonical_message_v2(
    service_id: &str,
    audience: &str,
    method: &Method,
    path_and_query: &str,
    timestamp: i64,
    nonce: &str,
    body: &[u8],
) -> Result<Vec<u8>, String> {
    if !path_and_query.starts_with('/') {
        return Err("internal identity path must start with '/'".to_string());
    }
    let body_hash = STANDARD_NO_PAD.encode(Sha256::digest(body));
    Ok(format!(
        "shamell-internal-v2\n{service_id}\n{audience}\n{}\n{path_and_query}\n{timestamp}\n{nonce}\n{body_hash}",
        method.as_str().to_ascii_uppercase()
    )
    .into_bytes())
}

fn now_unix_secs() -> Result<i64, String> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| "system time before unix epoch".to_string())?;
    Ok(now.as_secs() as i64)
}
