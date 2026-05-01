use crate::internal_identity::{
    InternalIdentityVerification, InternalIdentityVerifier, LegacyInternalIdentityVerification,
    INTERNAL_IDENTITY_AUDIENCE_HEADER, INTERNAL_IDENTITY_NONCE_HEADER,
    INTERNAL_IDENTITY_SIG_HEADER, INTERNAL_IDENTITY_SIG_V2_HEADER, INTERNAL_IDENTITY_TS_HEADER,
    INTERNAL_SERVICE_ID_HEADER,
};
use axum::body::{to_bytes, Body};
use axum::http::{header::HeaderName, Request, StatusCode};
use axum::response::{IntoResponse, Response};
use serde::Serialize;
use std::collections::HashMap;
use std::future::Future;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll};
use std::time::{SystemTime, UNIX_EPOCH};
use subtle::ConstantTimeEq;
use tower::{Layer, Service};

const INTERNAL_IDENTITY_REPLAY_CACHE_MAX_ENTRIES: usize = 100_000;

#[derive(Clone)]
pub struct InternalAuthLayer {
    required: bool,
    secret: Option<String>,
    secret_header: HeaderName,
    caller_header: HeaderName,
    allowed_callers: Vec<String>,
    expected_audience: Option<String>,
    identity_verifier: Option<InternalIdentityVerifier>,
    require_identity_v2: bool,
    legacy_secret_fallback: bool,
    body_limit: usize,
    replay_cache: Option<InternalIdentityReplayCache>,
}

impl InternalAuthLayer {
    pub fn new(required: bool, secret: Option<String>) -> Self {
        Self {
            required,
            secret,
            secret_header: HeaderName::from_static("x-internal-secret"),
            caller_header: HeaderName::from_static(INTERNAL_SERVICE_ID_HEADER),
            allowed_callers: Vec::new(),
            expected_audience: None,
            identity_verifier: None,
            require_identity_v2: false,
            legacy_secret_fallback: true,
            body_limit: 1024 * 1024,
            replay_cache: None,
        }
    }

    pub fn with_allowed_callers(mut self, callers: Vec<String>) -> Self {
        let mut out: Vec<String> = Vec::new();
        for raw in callers {
            let caller = raw.trim().to_ascii_lowercase();
            if caller.is_empty() || out.iter().any(|c| c == &caller) {
                continue;
            }
            out.push(caller);
        }
        self.allowed_callers = out;
        self
    }

    pub fn with_expected_audience(mut self, audience: impl AsRef<str>) -> Self {
        let normalized = audience.as_ref().trim().to_ascii_lowercase();
        self.expected_audience = if normalized.is_empty() {
            None
        } else {
            Some(normalized)
        };
        self
    }

    pub fn with_identity_verifier(mut self, verifier: InternalIdentityVerifier) -> Self {
        self.identity_verifier = Some(verifier);
        if self.replay_cache.is_none() {
            self.replay_cache = Some(InternalIdentityReplayCache::default());
        }
        self
    }

    pub fn with_require_identity_v2(mut self, enabled: bool) -> Self {
        self.require_identity_v2 = enabled;
        self
    }

    pub fn with_legacy_secret_fallback(mut self, enabled: bool) -> Self {
        self.legacy_secret_fallback = enabled;
        self
    }

    pub fn with_body_limit(mut self, body_limit: usize) -> Self {
        self.body_limit = body_limit.max(1024);
        self
    }
}

impl<S> Layer<S> for InternalAuthLayer {
    type Service = InternalAuthService<S>;

    fn layer(&self, inner: S) -> Self::Service {
        InternalAuthService {
            inner,
            required: self.required,
            secret: self.secret.clone(),
            secret_header: self.secret_header.clone(),
            caller_header: self.caller_header.clone(),
            allowed_callers: self.allowed_callers.clone(),
            expected_audience: self.expected_audience.clone(),
            identity_verifier: self.identity_verifier.clone(),
            require_identity_v2: self.require_identity_v2,
            legacy_secret_fallback: self.legacy_secret_fallback,
            body_limit: self.body_limit,
            replay_cache: self.replay_cache.clone(),
        }
    }
}

#[derive(Clone)]
pub struct InternalAuthService<S> {
    inner: S,
    required: bool,
    secret: Option<String>,
    secret_header: HeaderName,
    caller_header: HeaderName,
    allowed_callers: Vec<String>,
    expected_audience: Option<String>,
    identity_verifier: Option<InternalIdentityVerifier>,
    require_identity_v2: bool,
    legacy_secret_fallback: bool,
    body_limit: usize,
    replay_cache: Option<InternalIdentityReplayCache>,
}

#[derive(Serialize)]
struct ErrorBody<'a> {
    detail: &'a str,
}

impl<S> Service<Request<Body>> for InternalAuthService<S>
where
    S: Service<Request<Body>, Response = Response> + Clone + Send + 'static,
    S::Future: Send + 'static,
    S::Error: Send + 'static,
{
    type Response = Response;
    type Error = S::Error;
    type Future = Pin<Box<dyn Future<Output = Result<Response, S::Error>> + Send>>;

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, req: Request<Body>) -> Self::Future {
        let required = self.required;
        let secret = self.secret.clone();
        let secret_header = self.secret_header.clone();
        let caller_header = self.caller_header.clone();
        let allowed_callers = self.allowed_callers.clone();
        let expected_audience = self.expected_audience.clone();
        let identity_verifier = self.identity_verifier.clone();
        let require_identity_v2 = self.require_identity_v2;
        let legacy_secret_fallback = self.legacy_secret_fallback;
        let body_limit = self.body_limit;
        let replay_cache = self.replay_cache.clone();
        let mut inner = self.inner.clone();

        Box::pin(async move {
            if !required {
                return inner.call(req).await;
            }

            let Some(verifier) = identity_verifier else {
                let Some(secret) = secret.filter(|s| !s.trim().is_empty()) else {
                    let body = axum::Json(ErrorBody {
                        detail: "internal auth not configured",
                    });
                    return Ok((StatusCode::SERVICE_UNAVAILABLE, body).into_response());
                };
                if !authorize_legacy_secret(
                    req.headers(),
                    &secret,
                    &secret_header,
                    &caller_header,
                    &allowed_callers,
                ) {
                    let body = axum::Json(ErrorBody {
                        detail: "internal auth required",
                    });
                    return Ok((StatusCode::UNAUTHORIZED, body).into_response());
                }
                return inner.call(req).await;
            };

            let (parts, body) = req.into_parts();
            let body_bytes = match to_bytes(body, body_limit).await {
                Ok(bytes) => bytes,
                Err(_) => {
                    let body = axum::Json(ErrorBody {
                        detail: "internal request body too large",
                    });
                    return Ok((StatusCode::PAYLOAD_TOO_LARGE, body).into_response());
                }
            };

            let path_and_query = parts
                .uri
                .path_and_query()
                .map(|v| v.as_str())
                .unwrap_or(parts.uri.path());
            let verified_caller = verify_identity(IdentityVerificationContext {
                parts: &parts,
                body_bytes: &body_bytes,
                verifier: &verifier,
                allowed_callers: &allowed_callers,
                expected_audience: expected_audience.as_deref(),
                require_identity_v2,
                path_and_query,
                replay_cache: replay_cache.as_ref(),
            });
            if verified_caller.is_ok() {
                return inner
                    .call(Request::from_parts(parts, Body::from(body_bytes)))
                    .await;
            }

            if legacy_secret_fallback {
                let Some(secret) = secret.filter(|s| !s.trim().is_empty()) else {
                    let body = axum::Json(ErrorBody {
                        detail: "internal identity required",
                    });
                    return Ok((StatusCode::UNAUTHORIZED, body).into_response());
                };
                if authorize_legacy_secret(
                    &parts.headers,
                    &secret,
                    &secret_header,
                    &caller_header,
                    &allowed_callers,
                ) {
                    return inner
                        .call(Request::from_parts(parts, Body::from(body_bytes)))
                        .await;
                }
            }

            let body = axum::Json(ErrorBody {
                detail: "internal identity required",
            });
            Ok((StatusCode::UNAUTHORIZED, body).into_response())
        })
    }
}

struct IdentityVerificationContext<'a> {
    parts: &'a axum::http::request::Parts,
    body_bytes: &'a [u8],
    verifier: &'a InternalIdentityVerifier,
    allowed_callers: &'a [String],
    expected_audience: Option<&'a str>,
    require_identity_v2: bool,
    path_and_query: &'a str,
    replay_cache: Option<&'a InternalIdentityReplayCache>,
}

fn verify_identity(ctx: IdentityVerificationContext<'_>) -> Result<String, String> {
    let parts = ctx.parts;
    let caller = parts
        .headers
        .get(INTERNAL_SERVICE_ID_HEADER)
        .and_then(|v| v.to_str().ok())
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .ok_or_else(|| "missing internal caller".to_string())?;
    let timestamp = parts
        .headers
        .get(INTERNAL_IDENTITY_TS_HEADER)
        .and_then(|v| v.to_str().ok())
        .map(str::trim)
        .ok_or_else(|| "missing internal identity timestamp".to_string())?
        .parse::<i64>()
        .map_err(|_| "invalid internal identity timestamp".to_string())?;
    let nonce = parts
        .headers
        .get(INTERNAL_IDENTITY_NONCE_HEADER)
        .and_then(|v| v.to_str().ok())
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .ok_or_else(|| "missing internal identity nonce".to_string())?;
    let audience = parts
        .headers
        .get(INTERNAL_IDENTITY_AUDIENCE_HEADER)
        .and_then(|v| v.to_str().ok())
        .map(str::trim)
        .filter(|v| !v.is_empty());
    let signature_v2 = parts
        .headers
        .get(INTERNAL_IDENTITY_SIG_V2_HEADER)
        .and_then(|v| v.to_str().ok())
        .map(str::trim)
        .filter(|v| !v.is_empty());
    let caller = match (audience, signature_v2) {
        (Some(audience), Some(signature_v2)) => {
            let caller = ctx.verifier.verify(InternalIdentityVerification {
                service_id: caller,
                audience,
                timestamp,
                nonce,
                signature_b64: signature_v2,
                method: &parts.method,
                path_and_query: ctx.path_and_query,
                body: ctx.body_bytes,
            })?;
            if let Some(expected_audience) = ctx.expected_audience {
                if audience.trim().to_ascii_lowercase() != expected_audience {
                    return Err("internal identity audience mismatch".to_string());
                }
            }
            caller
        }
        (None, None) => {
            if ctx.require_identity_v2 {
                return Err("internal identity v2 required".to_string());
            }
            let legacy_signature = parts
                .headers
                .get(INTERNAL_IDENTITY_SIG_HEADER)
                .and_then(|v| v.to_str().ok())
                .map(str::trim)
                .filter(|v| !v.is_empty())
                .ok_or_else(|| "missing internal identity signature".to_string())?;
            ctx.verifier
                .verify_legacy(LegacyInternalIdentityVerification {
                    service_id: caller,
                    timestamp,
                    nonce,
                    signature_b64: legacy_signature,
                    method: &parts.method,
                    path_and_query: ctx.path_and_query,
                    body: ctx.body_bytes,
                })?
        }
        _ => return Err("internal identity audience headers incomplete".to_string()),
    };
    if let Some(replay_cache) = ctx.replay_cache {
        replay_cache.check_and_store(&caller, nonce, ctx.verifier.max_skew_secs())?;
    }
    if !ctx.allowed_callers.is_empty() && !ctx.allowed_callers.iter().any(|c| c == &caller) {
        return Err("internal caller not allowed".to_string());
    }
    Ok(caller)
}

fn authorize_legacy_secret(
    headers: &axum::http::HeaderMap,
    secret: &str,
    secret_header: &HeaderName,
    caller_header: &HeaderName,
    allowed_callers: &[String],
) -> bool {
    let provided = headers
        .get(secret_header)
        .and_then(|v| v.to_str().ok())
        .map(|s| s.trim())
        .unwrap_or("");
    if provided.is_empty() || provided.as_bytes().ct_eq(secret.as_bytes()).unwrap_u8() != 1 {
        return false;
    }
    if allowed_callers.is_empty() {
        return true;
    }
    let caller = headers
        .get(caller_header)
        .and_then(|v| v.to_str().ok())
        .map(str::trim)
        .map(str::to_ascii_lowercase)
        .unwrap_or_default();
    !caller.is_empty() && allowed_callers.iter().any(|c| c == &caller)
}

#[derive(Clone)]
struct InternalIdentityReplayCache {
    entries: Arc<Mutex<HashMap<String, i64>>>,
    max_entries: usize,
}

impl Default for InternalIdentityReplayCache {
    fn default() -> Self {
        Self {
            entries: Arc::new(Mutex::new(HashMap::new())),
            max_entries: INTERNAL_IDENTITY_REPLAY_CACHE_MAX_ENTRIES,
        }
    }
}

impl InternalIdentityReplayCache {
    #[cfg(test)]
    fn with_max_entries(max_entries: usize) -> Self {
        Self {
            entries: Arc::new(Mutex::new(HashMap::new())),
            max_entries: max_entries.max(1),
        }
    }

    fn check_and_store(&self, caller: &str, nonce: &str, ttl_secs: i64) -> Result<(), String> {
        let now = current_unix_secs()?;
        let cutoff = now.saturating_sub(ttl_secs.max(1));
        let max_entries = self.max_entries.max(1);
        let mut entries = self
            .entries
            .lock()
            .map_err(|_| "internal identity replay cache unavailable".to_string())?;
        entries.retain(|_, seen_at| *seen_at >= cutoff);
        let key = format!("{caller}:{nonce}");
        if entries.contains_key(&key) {
            return Err("internal identity replay detected".to_string());
        }
        if entries.len() >= max_entries {
            // Bound replay cache growth under nonce-flood traffic while still
            // preserving replay checks for the freshest nonce window.
            let caller_prefix = format!("{caller}:");
            let oldest_same_caller = entries
                .iter()
                .filter(|(candidate, _)| candidate.starts_with(&caller_prefix))
                .min_by_key(|(_, seen_at)| *seen_at)
                .map(|(candidate, _)| candidate.clone());
            let oldest_global = entries
                .iter()
                .min_by_key(|(_, seen_at)| *seen_at)
                .map(|(candidate, _)| candidate.clone());
            if let Some(oldest_key) = oldest_same_caller.or(oldest_global) {
                entries.remove(&oldest_key);
            }
        }
        entries.insert(key, now);
        Ok(())
    }
}

fn current_unix_secs() -> Result<i64, String> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| "system time before unix epoch".to_string())?;
    Ok(now.as_secs() as i64)
}

#[cfg(test)]
mod tests {
    use super::{
        verify_identity, IdentityVerificationContext, InternalIdentityReplayCache,
        INTERNAL_IDENTITY_AUDIENCE_HEADER, INTERNAL_IDENTITY_NONCE_HEADER,
        INTERNAL_IDENTITY_SIG_V2_HEADER, INTERNAL_IDENTITY_TS_HEADER, INTERNAL_SERVICE_ID_HEADER,
    };
    use crate::internal_identity::{InternalIdentityVerifier, InternalRequestSigner};
    use axum::body::Body;
    use axum::http::{header::HeaderName, HeaderValue, Method, Request};
    use std::time::Duration;

    fn v2_request_parts_without_legacy_signature(
        method: Method,
        path_and_query: &str,
        body: &[u8],
        audience: &str,
    ) -> (axum::http::request::Parts, InternalIdentityVerifier) {
        let signer = InternalRequestSigner::from_seed_bytes("bff", [7u8; 32]).expect("signer");
        let signed = signer
            .sign(&method, audience, path_and_query, body)
            .expect("signed identity");
        let verifier = InternalIdentityVerifier::from_public_keys_base64(
            vec![("bff".to_string(), signer.public_key_base64())],
            30,
        )
        .expect("verifier");

        let req = Request::builder()
            .method(method)
            .uri(path_and_query)
            .body(Body::empty())
            .expect("request");
        let (mut parts, _) = req.into_parts();
        parts.headers.insert(
            HeaderName::from_static(INTERNAL_SERVICE_ID_HEADER),
            HeaderValue::from_str(&signed.service_id).expect("service id header"),
        );
        parts.headers.insert(
            HeaderName::from_static(INTERNAL_IDENTITY_TS_HEADER),
            HeaderValue::from_str(&signed.timestamp.to_string()).expect("timestamp header"),
        );
        parts.headers.insert(
            HeaderName::from_static(INTERNAL_IDENTITY_NONCE_HEADER),
            HeaderValue::from_str(&signed.nonce).expect("nonce header"),
        );
        parts.headers.insert(
            HeaderName::from_static(INTERNAL_IDENTITY_AUDIENCE_HEADER),
            HeaderValue::from_str(&signed.audience).expect("audience header"),
        );
        parts.headers.insert(
            HeaderName::from_static(INTERNAL_IDENTITY_SIG_V2_HEADER),
            HeaderValue::from_str(&signed.signature_v2_b64).expect("v2 signature header"),
        );
        (parts, verifier)
    }

    #[test]
    fn replay_cache_rejects_duplicate_nonce() {
        let cache = InternalIdentityReplayCache::with_max_entries(8);
        cache
            .check_and_store("bff", "nonce-1", 30)
            .expect("first nonce should be accepted");
        let err = cache
            .check_and_store("bff", "nonce-1", 30)
            .expect_err("duplicate nonce must be rejected");
        assert_eq!(err, "internal identity replay detected");
    }

    #[test]
    fn replay_cache_evicts_oldest_entry_when_capacity_reached() {
        let cache = InternalIdentityReplayCache::with_max_entries(2);
        cache
            .check_and_store("bff", "nonce-oldest", 300)
            .expect("oldest nonce should be accepted");
        std::thread::sleep(Duration::from_millis(1100));
        cache
            .check_and_store("bff", "nonce-middle", 300)
            .expect("middle nonce should be accepted");
        std::thread::sleep(Duration::from_millis(1100));
        cache
            .check_and_store("bff", "nonce-newest", 300)
            .expect("newest nonce should be accepted");

        let err = cache
            .check_and_store("bff", "nonce-middle", 300)
            .expect_err("non-evicted nonce should still be replay-blocked");
        assert_eq!(err, "internal identity replay detected");
        cache
            .check_and_store("bff", "nonce-oldest", 300)
            .expect("evicted oldest nonce should be accepted again");
    }

    #[test]
    fn replay_cache_prefers_same_caller_eviction_before_global_eviction() {
        let cache = InternalIdentityReplayCache::with_max_entries(2);
        cache
            .check_and_store("bff", "nonce-1", 300)
            .expect("first bff nonce should be accepted");
        std::thread::sleep(Duration::from_millis(1100));
        cache
            .check_and_store("payments", "nonce-1", 300)
            .expect("payments nonce should be accepted");
        std::thread::sleep(Duration::from_millis(1100));
        cache
            .check_and_store("bff", "nonce-2", 300)
            .expect("new bff nonce should be accepted");

        let payments_replay = cache
            .check_and_store("payments", "nonce-1", 300)
            .expect_err("other caller nonce should remain replay-blocked");
        assert_eq!(payments_replay, "internal identity replay detected");
        cache
            .check_and_store("bff", "nonce-1", 300)
            .expect("older same-caller nonce should have been evicted");
    }

    #[test]
    fn verify_identity_accepts_v2_headers_without_legacy_signature() {
        let body = br#"{"ok":true}"#;
        let method = Method::POST;
        let path_and_query = "/internal/security/alerts?source=test";
        let (parts, verifier) =
            v2_request_parts_without_legacy_signature(method.clone(), path_and_query, body, "bff");

        let caller = verify_identity(IdentityVerificationContext {
            parts: &parts,
            body_bytes: body,
            verifier: &verifier,
            allowed_callers: &["bff".to_string()],
            expected_audience: Some("bff"),
            require_identity_v2: true,
            path_and_query,
            replay_cache: None,
        })
        .expect("v2 headers should be sufficient without legacy signature");
        assert_eq!(caller, "bff");
    }

    #[test]
    fn verify_identity_rejects_partial_v2_headers_without_legacy_signature() {
        let body = br#"{"ok":true}"#;
        let method = Method::POST;
        let path_and_query = "/internal/security/alerts?source=test";
        let (mut parts, verifier) =
            v2_request_parts_without_legacy_signature(method, path_and_query, body, "bff");
        parts
            .headers
            .remove(HeaderName::from_static(INTERNAL_IDENTITY_SIG_V2_HEADER));

        let err = verify_identity(IdentityVerificationContext {
            parts: &parts,
            body_bytes: body,
            verifier: &verifier,
            allowed_callers: &["bff".to_string()],
            expected_audience: Some("bff"),
            require_identity_v2: false,
            path_and_query,
            replay_cache: None,
        })
        .expect_err("partial v2 headers must be rejected");
        assert_eq!(err, "internal identity audience headers incomplete");
    }
}
