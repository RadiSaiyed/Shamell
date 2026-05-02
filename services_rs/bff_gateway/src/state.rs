use axum::http::Method;
use ipnet::IpNet;
use reqwest::Client;
use serde_json::Value;
use shamell_common::internal_identity::{
    InternalRequestSigner, INTERNAL_IDENTITY_AUDIENCE_HEADER, INTERNAL_IDENTITY_NONCE_HEADER,
    INTERNAL_IDENTITY_SIG_HEADER, INTERNAL_IDENTITY_SIG_V2_HEADER, INTERNAL_IDENTITY_TS_HEADER,
    INTERNAL_SERVICE_ID_HEADER,
};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

use crate::auth::AuthRuntime;

pub const DEFAULT_GEO_LOOKUP_BASE_URL: &str = "https://nominatim.openstreetmap.org";

// In-process caches for short-lived auth/payments resolution. Each cache:
//
// - Is keyed by a normalised string (account_id, geo cache_key).
// - Stores `expires_at: Instant` per entry; `cached_*` returns None for
//   expired entries and lazily removes them on the read path.
// - Has a hard size cap; on insert, expired entries are pruned via
//   `retain(...)` first, and if still at capacity the oldest-expiring
//   entry is evicted (`min_by_key` over the map -- O(n) but `n` is
//   bounded by the cap below).
// - Has a separate, shorter TTL for "negative" results (account with no
//   roles, geo lookup that returned nothing) to avoid hammering the
//   upstream when a misconfigured client retries in a tight loop.
//
// The eviction is intentionally NOT a true LRU; a true LRU buys little
// here because the workload is dominated by auth-resolve hits with
// stable working set << cap. If profiling later shows the O(n)
// eviction matters, migrate to the `lru` crate -- the public method
// surface (`cached_*` / `remember_*`) is small enough to swap in
// place. See services_rs/bff_gateway/REFACTORING.md.

/// Wallet ID stays cached for 5 minutes after a successful resolve.
/// Wallet IDs are immutable per account, so the only invalidation
/// pressure is account deletion, which is rare and tolerated to be
/// up to TTL stale.
const WALLET_RESOLUTION_CACHE_TTL_SECS: u64 = 300;
/// Roles change on operator action. 2 minutes is short enough that a
/// promotion/demotion lands within a meeting, long enough to absorb
/// load on the roles upstream during a steady state.
const ACCOUNT_ROLES_CACHE_TTL_SECS: u64 = 120;
/// Empty-roles negative cache: tests use 1s for fast assertions; prod
/// uses 15s to keep a misconfigured-client retry storm off the
/// upstream without making correct grants take long to materialise.
#[cfg(test)]
const ACCOUNT_ROLES_EMPTY_CACHE_TTL_SECS: u64 = 1;
#[cfg(not(test))]
const ACCOUNT_ROLES_EMPTY_CACHE_TTL_SECS: u64 = 15;
/// Cache size caps. Tests use 4 to make the cap eviction path easy
/// to assert on; prod uses 10_000 which fits the working set of
/// authenticated users for the BFF's instance footprint.
#[cfg(test)]
const WALLET_RESOLUTION_CACHE_MAX_ENTRIES: usize = 4;
#[cfg(not(test))]
const WALLET_RESOLUTION_CACHE_MAX_ENTRIES: usize = 10_000;
#[cfg(test)]
const ACCOUNT_ROLES_CACHE_MAX_ENTRIES: usize = 4;
#[cfg(not(test))]
const ACCOUNT_ROLES_CACHE_MAX_ENTRIES: usize = 10_000;

#[derive(Debug)]
pub struct WalletResolutionCacheEntry {
    wallet_id: String,
    expires_at: Instant,
}

#[derive(Debug)]
pub struct GeoLookupCacheEntry {
    value: Value,
    expires_at: Instant,
}

#[derive(Debug)]
pub struct AccountRolesCacheEntry {
    roles: Vec<String>,
    expires_at: Instant,
}

#[derive(Clone, Debug)]
pub struct WorkforceAccessConfig {
    pub oidc_issuer_url: Option<String>,
    pub oidc_client_id: Option<String>,
    pub oidc_audience: Option<String>,
    pub oidc_jwks_url: Option<String>,
    pub cloudflare_access_team_domain: Option<String>,
    pub cloudflare_access_audiences: Vec<String>,
    pub session_ttl_secs: i64,
    pub break_glass_session_ttl_secs: i64,
}

#[derive(Clone, Debug)]
pub struct DirectWebAccessConfig {
    pub allowed_origins: Vec<String>,
    pub allowed_client_cidrs: Vec<IpNet>,
    pub account_id: Option<String>,
    pub phone: Option<String>,
    pub device_id: Option<String>,
}

#[derive(Clone, Debug)]
pub struct DirectWebLaunchConfig {
    pub signing_secret: String,
    pub allowed_redirect_origins: Vec<String>,
    pub max_ttl_secs: i64,
}

#[derive(Clone)]
pub struct AppState {
    pub env_name: String,
    pub allowed_origins: Vec<String>,
    pub payments_base_url: String,
    pub payments_internal_secret: Option<String>,
    pub fee_wallet_account_id: Option<String>,
    pub fee_wallet_phone: Option<String>,
    pub chat_base_url: String,
    pub chat_internal_secret: Option<String>,
    pub internal_service_id: String,
    pub internal_request_signer: Option<InternalRequestSigner>,
    pub enforce_route_authz: bool,
    pub role_header_secret: Option<String>,
    pub upstream_timeout_secs: u64,
    pub max_upstream_body_bytes: usize,
    pub expose_upstream_errors: bool,
    pub accept_legacy_session_cookie: bool,
    pub allow_legacy_contact_invite_chat_device_fallback: bool,
    pub auth_device_login_web_enabled: bool,
    pub workforce_access: Option<WorkforceAccessConfig>,
    pub direct_web_access: Option<DirectWebAccessConfig>,
    pub direct_web_launch: Option<DirectWebLaunchConfig>,
    pub geo_lookup_base_url: String,
    pub http: Client,
    pub auth: Option<AuthRuntime>,
    pub wallet_resolution_cache: Arc<RwLock<HashMap<String, WalletResolutionCacheEntry>>>,
    pub geo_lookup_cache: Arc<RwLock<HashMap<String, GeoLookupCacheEntry>>>,
    pub account_roles_cache: Arc<RwLock<HashMap<String, AccountRolesCacheEntry>>>,
}

impl AppState {
    pub fn should_send_legacy_internal_secret(&self) -> bool {
        self.internal_request_signer.is_none()
    }

    pub fn build_upstream_url(
        &self,
        base_url: &str,
        path: &str,
        query: &[(String, String)],
    ) -> Result<(String, String), String> {
        if !path.starts_with('/') || path.starts_with("//") {
            return Err(format!("invalid upstream path {path}"));
        }
        if path.chars().any(|ch| ch.is_ascii_control()) {
            return Err(format!("invalid upstream path {path}"));
        }
        if query.iter().any(|(key, value)| {
            key.chars().any(|ch| ch.is_ascii_control())
                || value.chars().any(|ch| ch.is_ascii_control())
        }) {
            return Err(format!("invalid upstream query for path {path}"));
        }
        let mut url = reqwest::Url::parse(&format!("{}{}", base_url.trim_end_matches('/'), path))
            .map_err(|_| format!("invalid upstream url for path {path}"))?;
        if !query.is_empty() {
            let mut pairs = url.query_pairs_mut();
            for (key, value) in query {
                pairs.append_pair(key, value);
            }
        }
        let path_and_query = match url.query() {
            Some(query) => format!("{}?{query}", url.path()),
            None => url.path().to_string(),
        };
        Ok((url.to_string(), path_and_query))
    }

    pub fn apply_internal_identity_headers(
        &self,
        mut req: reqwest::RequestBuilder,
        method: &Method,
        audience: &str,
        path_and_query: &str,
        body: &[u8],
    ) -> Result<reqwest::RequestBuilder, String> {
        if let Some(signer) = &self.internal_request_signer {
            let signed = signer.sign(method, audience, path_and_query, body)?;
            req = req
                .header(INTERNAL_SERVICE_ID_HEADER, signed.service_id)
                .header(INTERNAL_IDENTITY_SIG_HEADER, signed.signature_b64)
                .header(INTERNAL_IDENTITY_AUDIENCE_HEADER, signed.audience)
                .header(INTERNAL_IDENTITY_TS_HEADER, signed.timestamp.to_string())
                .header(INTERNAL_IDENTITY_NONCE_HEADER, signed.nonce)
                .header(INTERNAL_IDENTITY_SIG_V2_HEADER, signed.signature_v2_b64);
        } else {
            let caller = self.internal_service_id.trim();
            if !caller.is_empty() {
                req = req.header(INTERNAL_SERVICE_ID_HEADER, caller);
            }
        }
        Ok(req)
    }

    pub async fn cached_wallet_id_for_account(&self, account_id: &str) -> Option<String> {
        let normalized = account_id.trim().to_ascii_lowercase();
        if normalized.is_empty() {
            return None;
        }

        let now = Instant::now();
        {
            let cache = self.wallet_resolution_cache.read().await;
            if let Some(entry) = cache.get(&normalized) {
                if entry.expires_at > now {
                    return Some(entry.wallet_id.clone());
                }
            } else {
                return None;
            }
        }

        let mut cache = self.wallet_resolution_cache.write().await;
        if let Some(entry) = cache.get(&normalized) {
            if entry.expires_at > now {
                return Some(entry.wallet_id.clone());
            }
        }
        cache.remove(&normalized);
        None
    }

    pub async fn remember_wallet_id_for_account(&self, account_id: &str, wallet_id: &str) {
        let normalized_account = account_id.trim().to_ascii_lowercase();
        let normalized_wallet = wallet_id.trim().to_string();
        if normalized_account.is_empty() || normalized_wallet.is_empty() {
            return;
        }

        let now = Instant::now();
        let expires_at = now + Duration::from_secs(WALLET_RESOLUTION_CACHE_TTL_SECS);
        let mut cache = self.wallet_resolution_cache.write().await;
        cache.retain(|_, entry| entry.expires_at > now);

        if !cache.contains_key(&normalized_account)
            && cache.len() >= WALLET_RESOLUTION_CACHE_MAX_ENTRIES
        {
            if let Some(oldest_key) = cache
                .iter()
                .min_by_key(|(_, entry)| entry.expires_at)
                .map(|(key, _)| key.clone())
            {
                cache.remove(&oldest_key);
            }
        }

        cache.insert(
            normalized_account,
            WalletResolutionCacheEntry {
                wallet_id: normalized_wallet,
                expires_at,
            },
        );
    }

    pub async fn cached_geo_lookup_json(&self, cache_key: &str) -> Option<Value> {
        let normalized_key = cache_key.trim();
        if normalized_key.is_empty() {
            return None;
        }

        let now = Instant::now();
        {
            let cache = self.geo_lookup_cache.read().await;
            if let Some(entry) = cache.get(normalized_key) {
                if entry.expires_at > now {
                    return Some(entry.value.clone());
                }
            } else {
                return None;
            }
        }

        let mut cache = self.geo_lookup_cache.write().await;
        if let Some(entry) = cache.get(normalized_key) {
            if entry.expires_at > now {
                return Some(entry.value.clone());
            }
        }
        cache.remove(normalized_key);
        None
    }

    pub async fn remember_geo_lookup_json(
        &self,
        cache_key: &str,
        value: &Value,
        ttl: Duration,
        max_entries: usize,
    ) {
        let normalized_key = cache_key.trim();
        if normalized_key.is_empty() || ttl.is_zero() || max_entries == 0 {
            return;
        }

        let now = Instant::now();
        let expires_at = now + ttl;
        let mut cache = self.geo_lookup_cache.write().await;
        cache.retain(|_, entry| entry.expires_at > now);

        if !cache.contains_key(normalized_key) && cache.len() >= max_entries {
            if let Some(oldest_key) = cache
                .iter()
                .min_by_key(|(_, entry)| entry.expires_at)
                .map(|(key, _)| key.clone())
            {
                cache.remove(&oldest_key);
            }
        }

        cache.insert(
            normalized_key.to_string(),
            GeoLookupCacheEntry {
                value: value.clone(),
                expires_at,
            },
        );
    }

    pub async fn cached_roles_for_account(&self, account_id: &str) -> Option<Vec<String>> {
        let normalized = account_id.trim().to_ascii_lowercase();
        if normalized.is_empty() {
            return None;
        }

        let now = Instant::now();
        {
            let cache = self.account_roles_cache.read().await;
            if let Some(entry) = cache.get(&normalized) {
                if entry.expires_at > now {
                    return Some(entry.roles.clone());
                }
            } else {
                return None;
            }
        }

        let mut cache = self.account_roles_cache.write().await;
        if let Some(entry) = cache.get(&normalized) {
            if entry.expires_at > now {
                return Some(entry.roles.clone());
            }
        }
        cache.remove(&normalized);
        None
    }

    pub async fn remember_roles_for_account(&self, account_id: &str, roles: &[String]) {
        let normalized_account = account_id.trim().to_ascii_lowercase();
        if normalized_account.is_empty() {
            return;
        }

        let now = Instant::now();
        let ttl_secs = if roles.is_empty() {
            ACCOUNT_ROLES_EMPTY_CACHE_TTL_SECS
        } else {
            ACCOUNT_ROLES_CACHE_TTL_SECS
        };
        let expires_at = now + Duration::from_secs(ttl_secs);
        let mut cache = self.account_roles_cache.write().await;
        cache.retain(|_, entry| entry.expires_at > now);

        if !cache.contains_key(&normalized_account)
            && cache.len() >= ACCOUNT_ROLES_CACHE_MAX_ENTRIES
        {
            if let Some(oldest_key) = cache
                .iter()
                .min_by_key(|(_, entry)| entry.expires_at)
                .map(|(key, _)| key.clone())
            {
                cache.remove(&oldest_key);
            }
        }

        cache.insert(
            normalized_account,
            AccountRolesCacheEntry {
                roles: roles.to_vec(),
                expires_at,
            },
        );
    }

    pub async fn forget_roles_for_account(&self, account_id: &str) {
        let normalized_account = account_id.trim().to_ascii_lowercase();
        if normalized_account.is_empty() {
            return;
        }

        self.account_roles_cache
            .write()
            .await
            .remove(&normalized_account);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn mk_state() -> AppState {
        AppState {
            env_name: "test".to_string(),
            allowed_origins: Vec::new(),
            payments_base_url: "https://payments.example".to_string(),
            payments_internal_secret: None,
            fee_wallet_account_id: None,
            fee_wallet_phone: None,
            chat_base_url: "https://chat.example".to_string(),
            chat_internal_secret: None,
            internal_service_id: "bff".to_string(),
            internal_request_signer: None,
            enforce_route_authz: true,
            role_header_secret: None,
            upstream_timeout_secs: 12,
            max_upstream_body_bytes: 1024 * 1024,
            expose_upstream_errors: false,
            accept_legacy_session_cookie: false,
            allow_legacy_contact_invite_chat_device_fallback: false,
            auth_device_login_web_enabled: false,
            workforce_access: None,
            direct_web_access: None,
            direct_web_launch: None,
            geo_lookup_base_url: DEFAULT_GEO_LOOKUP_BASE_URL.to_string(),
            http: Client::new(),
            auth: None,
            wallet_resolution_cache: Arc::new(RwLock::new(HashMap::new())),
            geo_lookup_cache: Arc::new(RwLock::new(HashMap::new())),
            account_roles_cache: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    #[test]
    fn build_upstream_url_rejects_non_absolute_or_schemeless_paths() {
        let state = mk_state();
        assert!(state
            .build_upstream_url("https://payments.example", "users", &[])
            .is_err());
        assert!(state
            .build_upstream_url("https://payments.example", "//users", &[])
            .is_err());
    }

    #[test]
    fn build_upstream_url_rejects_control_characters() {
        let state = mk_state();
        assert!(state
            .build_upstream_url("https://payments.example", "/favorites/\nvisible", &[])
            .is_err());
        assert!(state
            .build_upstream_url(
                "https://payments.example",
                "/favorites/visible",
                &[("owner".to_string(), "wallet\t1".to_string())],
            )
            .is_err());
    }

    #[test]
    fn build_upstream_url_encodes_query_and_preserves_path_for_signing() {
        let state = mk_state();
        let (url, path_and_query) = state
            .build_upstream_url(
                "https://payments.example",
                "/favorites/fav%2Fid",
                &[("owner_wallet_id".to_string(), "wallet owner".to_string())],
            )
            .expect("valid upstream url");
        assert_eq!(
            path_and_query,
            "/favorites/fav%2Fid?owner_wallet_id=wallet+owner"
        );
        assert_eq!(
            url,
            "https://payments.example/favorites/fav%2Fid?owner_wallet_id=wallet+owner"
        );
    }

    #[tokio::test]
    async fn cached_wallet_id_for_account_drops_expired_entries() {
        let state = mk_state();
        state.wallet_resolution_cache.write().await.insert(
            "acct_expired".to_string(),
            WalletResolutionCacheEntry {
                wallet_id: "wallet_expired".to_string(),
                expires_at: Instant::now() - Duration::from_secs(1),
            },
        );

        assert_eq!(
            state.cached_wallet_id_for_account("acct_expired").await,
            None
        );
        assert!(!state
            .wallet_resolution_cache
            .read()
            .await
            .contains_key("acct_expired"));
    }

    #[tokio::test]
    async fn remember_wallet_id_for_account_caps_cache_size() {
        let state = mk_state();
        {
            let now = Instant::now();
            let mut cache = state.wallet_resolution_cache.write().await;
            for idx in 0..WALLET_RESOLUTION_CACHE_MAX_ENTRIES {
                cache.insert(
                    format!("acct_{idx}"),
                    WalletResolutionCacheEntry {
                        wallet_id: format!("wallet_{idx}"),
                        expires_at: now + Duration::from_secs((idx + 1) as u64),
                    },
                );
            }
        }

        state
            .remember_wallet_id_for_account("acct_new", "wallet_new")
            .await;

        let cache = state.wallet_resolution_cache.read().await;
        assert_eq!(cache.len(), WALLET_RESOLUTION_CACHE_MAX_ENTRIES);
        assert!(!cache.contains_key("acct_0"));
        assert!(cache.contains_key("acct_new"));
    }

    #[tokio::test]
    async fn cached_roles_for_account_drops_expired_entries() {
        let state = mk_state();
        state.account_roles_cache.write().await.insert(
            "acct_expired".to_string(),
            AccountRolesCacheEntry {
                roles: vec!["ride_driver".to_string()],
                expires_at: Instant::now() - Duration::from_secs(1),
            },
        );

        assert_eq!(state.cached_roles_for_account("acct_expired").await, None);
        assert!(!state
            .account_roles_cache
            .read()
            .await
            .contains_key("acct_expired"));
    }

    #[tokio::test]
    async fn remember_roles_for_account_caps_cache_size() {
        let state = mk_state();
        {
            let now = Instant::now();
            let mut cache = state.account_roles_cache.write().await;
            for idx in 0..ACCOUNT_ROLES_CACHE_MAX_ENTRIES {
                cache.insert(
                    format!("acct_{idx}"),
                    AccountRolesCacheEntry {
                        roles: vec![format!("role_{idx}")],
                        expires_at: now + Duration::from_secs((idx + 1) as u64),
                    },
                );
            }
        }

        state
            .remember_roles_for_account("acct_new", &[String::from("ride_driver")])
            .await;

        let cache = state.account_roles_cache.read().await;
        assert_eq!(cache.len(), ACCOUNT_ROLES_CACHE_MAX_ENTRIES);
        assert!(!cache.contains_key("acct_0"));
        assert!(cache.contains_key("acct_new"));
    }

    #[tokio::test]
    async fn remember_roles_for_account_empty_entries_expire_quickly() {
        let state = mk_state();

        state.remember_roles_for_account("acct_empty", &[]).await;
        assert_eq!(
            state.cached_roles_for_account("acct_empty").await,
            Some(vec![])
        );

        tokio::time::sleep(Duration::from_millis(1100)).await;

        assert_eq!(state.cached_roles_for_account("acct_empty").await, None);
    }

    #[tokio::test]
    async fn forget_roles_for_account_removes_cached_entry() {
        let state = mk_state();

        state
            .remember_roles_for_account("acct_forget", &[String::from("ops")])
            .await;
        assert_eq!(
            state.cached_roles_for_account("acct_forget").await,
            Some(vec![String::from("ops")])
        );

        state.forget_roles_for_account("acct_forget").await;

        assert_eq!(state.cached_roles_for_account("acct_forget").await, None);
    }
}
