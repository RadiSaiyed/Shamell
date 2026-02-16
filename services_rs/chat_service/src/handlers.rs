use crate::error::{ApiError, ApiResult};
use crate::models::*;
use crate::state::AppState;
use axum::extract::{Path, Query, State};
use axum::http::HeaderMap;
use axum::response::sse::{Event, Sse};
use axum::response::IntoResponse;
use base64::engine::general_purpose::{STANDARD, URL_SAFE, URL_SAFE_NO_PAD};
use base64::Engine;
use chrono::{DateTime, Duration, SecondsFormat, Utc};
use ed25519_dalek::{Signature as Ed25519Signature, Verifier, VerifyingKey};
use futures_util::StreamExt;
use regex::Regex;
use serde_json::json;
use sha2::{Digest, Sha256};
use sqlx::{PgPool, Row};
use std::collections::HashSet;
use std::convert::Infallible;
use std::sync::{Arc, OnceLock};
use std::time::Duration as StdDuration;
use subtle::ConstantTimeEq;
use uuid::Uuid;

const FCM_ENDPOINT: &str = "https://fcm.googleapis.com/fcm/send";
const PROTOCOL_V1_LEGACY: &str = "v1_legacy";
const PROTOCOL_V2_LIBSIGNAL: &str = "v2_libsignal";
const PUSH_TYPE_CHAT_WAKEUP: &str = "chat_wakeup";
const SIGNED_PREKEY_SIG_ALG_ED25519: &str = "ed25519";
const KEY_REGISTER_SIG_CONTEXT: &str = "shamell-key-register-v1";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ChatProtocolVersion {
    V1Legacy,
    V2Libsignal,
}

impl ChatProtocolVersion {
    fn as_str(self) -> &'static str {
        match self {
            Self::V1Legacy => PROTOCOL_V1_LEGACY,
            Self::V2Libsignal => PROTOCOL_V2_LIBSIGNAL,
        }
    }
}

#[derive(Debug, serde::Serialize)]
pub struct HealthOut {
    pub status: &'static str,
    pub env: String,
    pub service: &'static str,
    pub version: &'static str,
}

pub async fn health(State(state): State<AppState>) -> axum::Json<HealthOut> {
    axum::Json(HealthOut {
        status: "ok",
        env: state.env_name.clone(),
        service: "Chat API",
        version: env!("CARGO_PKG_VERSION"),
    })
}

#[derive(Debug, serde::Deserialize)]
pub struct InboxParams {
    pub device_id: String,
    pub since_iso: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, serde::Deserialize)]
pub struct GroupInboxParams {
    pub device_id: String,
    pub since_iso: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, serde::Deserialize)]
pub struct ListGroupsParams {
    pub device_id: String,
}

#[derive(Debug, serde::Deserialize)]
pub struct GroupMembersParams {
    pub device_id: String,
}

#[derive(Debug, serde::Deserialize)]
pub struct KeyEventsParams {
    pub device_id: String,
    pub limit: Option<i64>,
}

fn device_id_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"^[A-Za-z0-9_-]{4,24}$").expect("valid regex"))
}

fn is_reserved_device_id(device_id: &str) -> bool {
    // Prevent collisions with action routes under /devices/*.
    // Expand this list whenever new static /devices/<action> routes are added.
    const RESERVED: &[&str] = &["register"];
    RESERVED
        .iter()
        .any(|w| device_id.trim().eq_ignore_ascii_case(w))
}

fn is_valid_device_id(device_id: &str) -> bool {
    device_id_re().is_match(device_id) && !is_reserved_device_id(device_id)
}

fn mailbox_token_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"^[A-Za-z0-9_-]{32,256}$").expect("valid regex"))
}

fn group_id_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"^[A-Za-z0-9_-]{4,36}$").expect("valid regex"))
}

fn is_valid_group_id(group_id: &str) -> bool {
    group_id_re().is_match(group_id.trim())
}

fn now_iso() -> String {
    Utc::now().to_rfc3339_opts(SecondsFormat::Secs, true)
}

fn parse_iso8601(raw: &str) -> Result<DateTime<Utc>, ApiError> {
    let s = raw.trim();
    if s.is_empty() {
        return Err(ApiError::bad_request("invalid since"));
    }
    let s = s.replace('Z', "+00:00");
    let parsed =
        DateTime::parse_from_rfc3339(&s).map_err(|_| ApiError::bad_request("invalid since"))?;
    Ok(parsed.with_timezone(&Utc))
}

fn canonical_iso(raw: &str) -> Result<String, ApiError> {
    Ok(parse_iso8601(raw)?.to_rfc3339_opts(SecondsFormat::Secs, true))
}

fn parse_protocol_version(raw: Option<&str>) -> Result<ChatProtocolVersion, ApiError> {
    let normalized = raw
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_ascii_lowercase);
    match normalized.as_deref() {
        None | Some(PROTOCOL_V1_LEGACY) => Ok(ChatProtocolVersion::V1Legacy),
        Some(PROTOCOL_V2_LIBSIGNAL) => Ok(ChatProtocolVersion::V2Libsignal),
        Some(_) => Err(ApiError::bad_request("invalid protocol_version")),
    }
}

fn parse_row_protocol_version(raw: Option<&str>) -> ChatProtocolVersion {
    match raw
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_ascii_lowercase)
        .as_deref()
    {
        Some(PROTOCOL_V2_LIBSIGNAL) => ChatProtocolVersion::V2Libsignal,
        _ => ChatProtocolVersion::V1Legacy,
    }
}

fn validate_protocol_write(
    chat_protocol_v2_enabled: bool,
    chat_protocol_v1_write_enabled: bool,
    chat_protocol_require_v2_for_groups: bool,
    version: ChatProtocolVersion,
    is_group: bool,
) -> Result<(), ApiError> {
    if version == ChatProtocolVersion::V2Libsignal && !chat_protocol_v2_enabled {
        return Err(ApiError::bad_request("protocol v2 disabled"));
    }
    if version == ChatProtocolVersion::V1Legacy && !chat_protocol_v1_write_enabled {
        return Err(ApiError::bad_request("protocol v1 writes disabled"));
    }
    if is_group
        && chat_protocol_require_v2_for_groups
        && version != ChatProtocolVersion::V2Libsignal
    {
        return Err(ApiError::bad_request(
            "group messages require protocol_version v2_libsignal",
        ));
    }
    Ok(())
}

fn require_v2_only_key_registration(
    chat_protocol_v2_enabled: bool,
    v2_only: Option<bool>,
) -> ApiResult<bool> {
    if !chat_protocol_v2_enabled {
        return Err(ApiError::bad_request("protocol v2 disabled"));
    }
    if v2_only != Some(true) {
        return Err(ApiError::bad_request("v2_only=true required"));
    }
    Ok(true)
}

fn is_strict_v2_bundle_eligible(
    protocol_floor: &str,
    supports_v2: bool,
    v2_only: bool,
    identity_key_b64: &str,
    identity_signing_pubkey_b64: Option<&str>,
    signed_prekey_id: i64,
    signed_prekey_b64: &str,
    signed_prekey_sig_b64: &str,
) -> bool {
    if protocol_floor.trim() != PROTOCOL_V2_LIBSIGNAL {
        return false;
    }
    if !supports_v2 || !v2_only {
        return false;
    }
    if signed_prekey_id <= 0 {
        return false;
    }
    if normalize_key_material(identity_key_b64, "identity_key_b64", 16, 8192).is_err() {
        return false;
    }
    let Some(signing_pubkey) = identity_signing_pubkey_b64.map(str::trim) else {
        return false;
    };
    if signing_pubkey.is_empty()
        || normalize_key_material(signing_pubkey, "identity_signing_pubkey_b64", 16, 8192).is_err()
    {
        return false;
    }
    if normalize_key_material(signed_prekey_b64, "signed_prekey_b64", 16, 8192).is_err() {
        return false;
    }
    if normalize_key_material(signed_prekey_sig_b64, "signed_prekey_sig_b64", 16, 8192).is_err() {
        return false;
    }
    true
}

fn normalize_key_material(
    raw: &str,
    field: &str,
    min_len: usize,
    max_len: usize,
) -> Result<String, ApiError> {
    let trimmed = raw.trim();
    if trimmed.len() < min_len || trimmed.len() > max_len {
        return Err(ApiError::bad_request(format!("invalid {field}")));
    }
    let valid_chars = trimmed
        .bytes()
        .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'+' | b'/' | b'=' | b'-' | b'_'));
    if !valid_chars {
        return Err(ApiError::bad_request(format!("invalid {field}")));
    }
    Ok(trimmed.to_string())
}

fn normalize_prekey_batch(prekeys: &[OneTimePrekeyIn]) -> Result<Vec<(i64, String)>, ApiError> {
    if prekeys.is_empty() || prekeys.len() > 500 {
        return Err(ApiError::bad_request("invalid prekeys"));
    }
    let mut seen: HashSet<i64> = HashSet::with_capacity(prekeys.len());
    let mut out = Vec::with_capacity(prekeys.len());
    for p in prekeys {
        if p.key_id <= 0 || !seen.insert(p.key_id) {
            return Err(ApiError::bad_request("invalid prekeys"));
        }
        let key_b64 = normalize_key_material(&p.key_b64, "prekeys.key_b64", 16, 8192)?;
        out.push((p.key_id, key_b64));
    }
    Ok(out)
}

fn normalize_mailbox_token(raw: &str) -> Result<String, ApiError> {
    let token = raw.trim().to_string();
    if !mailbox_token_re().is_match(&token) {
        return Err(ApiError::bad_request("invalid mailbox_token"));
    }
    Ok(token)
}

fn issue_secret_token_hex(bytes_len: usize) -> String {
    let mut bytes = vec![0_u8; bytes_len];
    getrandom::getrandom(&mut bytes).expect("getrandom");
    hex::encode(bytes)
}

fn ensure_mailbox_api_enabled(state: &AppState) -> ApiResult<()> {
    if state.chat_mailbox_api_enabled {
        return Ok(());
    }
    Err(ApiError::not_found("not found"))
}

async fn is_device_v2_only(state: &AppState, device_id: &str) -> Result<bool, ApiError> {
    let chat_device_protocol_state = state.table("chat_device_protocol_state");
    let row = sqlx::query(&format!(
        "SELECT v2_only FROM {chat_device_protocol_state} WHERE device_id=$1 LIMIT 1"
    ))
    .bind(device_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;
    let Some(row) = row else {
        return Ok(false);
    };
    let v2_only_i: i64 = row.try_get("v2_only").unwrap_or(0);
    Ok(v2_only_i != 0)
}

async fn group_has_v2_only_members(state: &AppState, group_id: &str) -> Result<bool, ApiError> {
    let group_members = state.table("group_members");
    let chat_device_protocol_state = state.table("chat_device_protocol_state");
    let row = sqlx::query(&format!(
        "SELECT 1 as one FROM {group_members} gm \
         JOIN {chat_device_protocol_state} ps ON ps.device_id=gm.device_id \
         WHERE gm.group_id=$1 AND ps.v2_only=1 LIMIT 1"
    ))
    .bind(group_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;
    Ok(row.is_some())
}

async fn enforce_no_protocol_downgrade_direct(
    state: &AppState,
    sender_id: &str,
    recipient_id: &str,
    version: ChatProtocolVersion,
) -> Result<(), ApiError> {
    if version != ChatProtocolVersion::V1Legacy {
        return Ok(());
    }
    if is_device_v2_only(state, sender_id).await? || is_device_v2_only(state, recipient_id).await? {
        audit_chat_security_blocked(
            "chat_protocol_downgrade",
            "direct_v1_legacy_rejected",
            Some(sender_id),
            Some(recipient_id),
            None,
        );
        return Err(ApiError::bad_request("protocol downgrade rejected"));
    }
    Ok(())
}

async fn enforce_no_protocol_downgrade_group(
    state: &AppState,
    group_id: &str,
    sender_id: &str,
    version: ChatProtocolVersion,
) -> Result<(), ApiError> {
    if version != ChatProtocolVersion::V1Legacy {
        return Ok(());
    }
    if is_device_v2_only(state, sender_id).await?
        || group_has_v2_only_members(state, group_id).await?
    {
        audit_chat_security_blocked(
            "chat_protocol_downgrade",
            "group_v1_legacy_rejected",
            Some(sender_id),
            None,
            Some(group_id),
        );
        return Err(ApiError::bad_request("protocol downgrade rejected"));
    }
    Ok(())
}

fn sha256_hex(s: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(s.as_bytes());
    let out = hasher.finalize();
    hex::encode(out)
}

fn hash_prefix_12(raw: &str) -> String {
    let digest = sha256_hex(raw);
    digest.chars().take(12).collect()
}

fn audit_chat_security_blocked(
    event: &'static str,
    reason: &str,
    actor_device_id: Option<&str>,
    target_device_id: Option<&str>,
    group_id: Option<&str>,
) {
    let actor_hash = actor_device_id.map(hash_prefix_12).unwrap_or_default();
    let target_hash = target_device_id.map(hash_prefix_12).unwrap_or_default();
    let group_hash = group_id.map(hash_prefix_12).unwrap_or_default();
    tracing::warn!(
        security_event = event,
        outcome = "blocked",
        reason = reason,
        actor_device_hash = actor_hash,
        target_device_hash = target_hash,
        group_hash = group_hash,
        "chat security policy rejected request"
    );
}

fn decode_b64_any(raw: &str) -> Option<Vec<u8>> {
    let s = raw.trim();
    if s.is_empty() {
        return None;
    }
    STANDARD
        .decode(s)
        .ok()
        .or_else(|| URL_SAFE.decode(s).ok())
        .or_else(|| URL_SAFE_NO_PAD.decode(s).ok())
}

fn key_register_signature_message(
    device_id: &str,
    identity_key_b64: &str,
    signed_prekey_id: i64,
    signed_prekey_b64: &str,
) -> Vec<u8> {
    format!(
        "{KEY_REGISTER_SIG_CONTEXT}\n{}\n{}\n{}\n{}\n",
        device_id.trim(),
        identity_key_b64.trim(),
        signed_prekey_id,
        signed_prekey_b64.trim()
    )
    .into_bytes()
}

fn verify_signed_prekey_signature(
    device_id: &str,
    identity_key_b64: &str,
    signed_prekey_id: i64,
    signed_prekey_b64: &str,
    identity_signing_pubkey_b64: &str,
    signed_prekey_sig_b64: &str,
) -> ApiResult<()> {
    let pk_bytes = decode_b64_any(identity_signing_pubkey_b64)
        .ok_or_else(|| ApiError::bad_request("invalid identity_signing_pubkey_b64"))?;
    let pk_arr: [u8; 32] = pk_bytes
        .as_slice()
        .try_into()
        .map_err(|_| ApiError::bad_request("invalid identity_signing_pubkey_b64"))?;
    let verify_key = VerifyingKey::from_bytes(&pk_arr)
        .map_err(|_| ApiError::bad_request("invalid identity_signing_pubkey_b64"))?;

    let sig_bytes = decode_b64_any(signed_prekey_sig_b64)
        .ok_or_else(|| ApiError::bad_request("invalid signed_prekey_sig_b64"))?;
    let sig_arr: [u8; 64] = sig_bytes
        .as_slice()
        .try_into()
        .map_err(|_| ApiError::bad_request("invalid signed_prekey_sig_b64"))?;
    let sig = Ed25519Signature::from_bytes(&sig_arr);

    let msg = key_register_signature_message(
        device_id,
        identity_key_b64,
        signed_prekey_id,
        signed_prekey_b64,
    );
    verify_key
        .verify(&msg, &sig)
        .map_err(|_| ApiError::bad_request("invalid signed_prekey signature"))?;
    Ok(())
}

fn fp_for_key(public_key_b64: &str) -> Option<String> {
    let raw = decode_b64_any(public_key_b64)?;
    let mut hasher = Sha256::new();
    hasher.update(&raw);
    let out = hasher.finalize();
    let hex = hex::encode(out);
    Some(hex.chars().take(16).collect())
}

fn header_str(headers: &HeaderMap, name: &str) -> String {
    headers
        .get(name)
        .and_then(|v| v.to_str().ok())
        .map(|s| s.trim().to_string())
        .unwrap_or_default()
}

async fn device_exists(pool: &PgPool, devices: &str, device_id: &str) -> Result<bool, ApiError> {
    let row = sqlx::query(&format!("SELECT 1 as one FROM {devices} WHERE id=$1"))
        .bind(device_id)
        .fetch_optional(pool)
        .await
        .map_err(|_| ApiError::internal("database error"))?;
    Ok(row.is_some())
}

async fn require_device_actor(
    state: &AppState,
    headers: &HeaderMap,
    pool: &PgPool,
) -> ApiResult<Option<String>> {
    if !state.enforce_device_auth {
        return Ok(None);
    }

    let actor = header_str(headers, "x-chat-device-id");
    let token = header_str(headers, "x-chat-device-token");
    if actor.is_empty() || token.is_empty() {
        return Err(ApiError::unauthorized("chat device auth required"));
    }
    if !is_valid_device_id(&actor) {
        return Err(ApiError::unauthorized("invalid chat device id"));
    }

    let device_auth = state.table("device_auth");
    let row = sqlx::query(&format!(
        "SELECT token_hash FROM {device_auth} WHERE device_id=$1"
    ))
    .bind(&actor)
    .fetch_optional(pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?
    .ok_or_else(|| ApiError::unauthorized("unknown chat device auth"))?;
    let stored: String = row.try_get("token_hash").unwrap_or_default();
    let provided = sha256_hex(&token);

    if provided.as_bytes().ct_eq(stored.as_bytes()).unwrap_u8() != 1 {
        return Err(ApiError::unauthorized("invalid chat device token"));
    }

    Ok(Some(actor))
}

async fn enforce_device_actor(
    state: &AppState,
    headers: &HeaderMap,
    pool: &PgPool,
    device_id: &str,
) -> ApiResult<Option<String>> {
    let actor = require_device_actor(state, headers, pool).await?;
    if let Some(a) = &actor {
        if a != device_id {
            return Err(ApiError::forbidden("device auth mismatch"));
        }
    }
    Ok(actor)
}

pub async fn purge_expired(state: &AppState) -> Result<(), ApiError> {
    let now = now_iso();
    let messages = state.table("messages");
    let group_messages = state.table("group_messages");
    let chat_mailboxes = state.table("chat_mailboxes");
    let chat_mailbox_messages = state.table("chat_mailbox_messages");

    let _ = sqlx::query(&format!(
        "DELETE FROM {messages} WHERE expire_at IS NOT NULL AND expire_at < $1"
    ))
    .bind(&now)
    .execute(&state.pool)
    .await;
    let _ = sqlx::query(&format!(
        "DELETE FROM {group_messages} WHERE expire_at IS NOT NULL AND expire_at < $1"
    ))
    .bind(&now)
    .execute(&state.pool)
    .await;

    // Mailbox transport retention:
    // - delete expired mailbox messages (expire_at)
    // - delete consumed mailbox messages after a short retention window
    // - delete inactive mailboxes (and their messages) after a short retention window
    let _ = sqlx::query(&format!(
        "DELETE FROM {chat_mailbox_messages} WHERE expire_at IS NOT NULL AND expire_at < $1"
    ))
    .bind(&now)
    .execute(&state.pool)
    .await;

    if state.chat_mailbox_consumed_retention_secs > 0 {
        let cutoff = (Utc::now() - Duration::seconds(state.chat_mailbox_consumed_retention_secs))
            .to_rfc3339_opts(SecondsFormat::Secs, true);
        let _ = sqlx::query(&format!(
            "DELETE FROM {chat_mailbox_messages} \
             WHERE consumed_at IS NOT NULL AND TRIM(consumed_at)<>'' AND consumed_at < $1"
        ))
        .bind(&cutoff)
        .execute(&state.pool)
        .await;
    }

    if state.chat_mailbox_inactive_retention_secs > 0 {
        let cutoff = (Utc::now() - Duration::seconds(state.chat_mailbox_inactive_retention_secs))
            .to_rfc3339_opts(SecondsFormat::Secs, true);
        // Delete messages for old inactive mailboxes first to prevent orphans.
        let _ = sqlx::query(&format!(
            "DELETE FROM {chat_mailbox_messages} m USING {chat_mailboxes} b \
             WHERE m.token_hash=b.token_hash \
               AND b.active=0 \
               AND COALESCE(NULLIF(TRIM(b.rotated_at),''), b.created_at) < $1"
        ))
        .bind(&cutoff)
        .execute(&state.pool)
        .await;
        let _ = sqlx::query(&format!(
            "DELETE FROM {chat_mailboxes} \
             WHERE active=0 AND COALESCE(NULLIF(TRIM(rotated_at),''), created_at) < $1"
        ))
        .bind(&cutoff)
        .execute(&state.pool)
        .await;
    }
    Ok(())
}

async fn blocked_peers(state: &AppState, device_id: &str) -> HashSet<String> {
    let contact_rules = state.table("contact_rules");
    let rows = sqlx::query(&format!(
        "SELECT peer_id FROM {contact_rules} WHERE device_id=$1 AND blocked=1"
    ))
    .bind(device_id)
    .fetch_all(&state.pool)
    .await
    .unwrap_or_default();
    let mut out = HashSet::with_capacity(rows.len());
    for r in rows {
        if let Ok(peer) = r.try_get::<String, _>("peer_id") {
            out.insert(peer);
        }
    }
    out
}

async fn hidden_peers(state: &AppState, device_id: &str) -> HashSet<String> {
    let contact_rules = state.table("contact_rules");
    let rows = sqlx::query(&format!(
        "SELECT peer_id FROM {contact_rules} WHERE device_id=$1 AND hidden=1"
    ))
    .bind(device_id)
    .fetch_all(&state.pool)
    .await
    .unwrap_or_default();
    let mut out = HashSet::with_capacity(rows.len());
    for r in rows {
        if let Ok(peer) = r.try_get::<String, _>("peer_id") {
            out.insert(peer);
        }
    }
    out
}

async fn has_hidden(state: &AppState, device_id: &str) -> bool {
    let contact_rules = state.table("contact_rules");
    let row = sqlx::query(&format!(
        "SELECT 1 as one FROM {contact_rules} WHERE device_id=$1 AND hidden=1 LIMIT 1"
    ))
    .bind(device_id)
    .fetch_optional(&state.pool)
    .await
    .ok()
    .flatten();
    row.is_some()
}

async fn is_blocked(state: &AppState, device_id: &str, peer_id: Option<&str>) -> bool {
    let contact_rules = state.table("contact_rules");
    let sql = if peer_id.is_some() {
        format!(
            "SELECT 1 as one FROM {contact_rules} WHERE device_id=$1 AND peer_id=$2 AND blocked=1 LIMIT 1"
        )
    } else {
        format!("SELECT 1 as one FROM {contact_rules} WHERE device_id=$1 AND blocked=1 LIMIT 1")
    };
    let mut q = sqlx::query(&sql).bind(device_id);
    if let Some(p) = peer_id {
        q = q.bind(p);
    }
    q.fetch_optional(&state.pool).await.ok().flatten().is_some()
}

async fn is_muted(state: &AppState, device_id: &str, peer_id: Option<&str>) -> bool {
    let contact_rules = state.table("contact_rules");
    let sql = if peer_id.is_some() {
        format!(
            "SELECT 1 as one FROM {contact_rules} WHERE device_id=$1 AND peer_id=$2 AND muted=1 LIMIT 1"
        )
    } else {
        format!("SELECT 1 as one FROM {contact_rules} WHERE device_id=$1 AND muted=1 LIMIT 1")
    };
    let mut q = sqlx::query(&sql).bind(device_id);
    if let Some(p) = peer_id {
        q = q.bind(p);
    }
    q.fetch_optional(&state.pool).await.ok().flatten().is_some()
}

async fn is_group_member(state: &AppState, group_id: &str, device_id: &str) -> bool {
    let group_members = state.table("group_members");
    sqlx::query(&format!(
        "SELECT 1 as one FROM {group_members} WHERE group_id=$1 AND device_id=$2 LIMIT 1"
    ))
    .bind(group_id)
    .bind(device_id)
    .fetch_optional(&state.pool)
    .await
    .ok()
    .flatten()
    .is_some()
}

async fn is_group_admin(state: &AppState, group_id: &str, device_id: &str) -> bool {
    let group_members = state.table("group_members");
    let row = sqlx::query(&format!(
        "SELECT role FROM {group_members} WHERE group_id=$1 AND device_id=$2 LIMIT 1"
    ))
    .bind(group_id)
    .bind(device_id)
    .fetch_optional(&state.pool)
    .await
    .ok()
    .flatten();
    let Some(row) = row else {
        return false;
    };
    let role: String = row.try_get("role").unwrap_or_default();
    role.trim().eq_ignore_ascii_case("admin")
}

async fn group_member_ids(state: &AppState, group_id: &str) -> Vec<String> {
    let group_members = state.table("group_members");
    let rows = sqlx::query(&format!(
        "SELECT device_id FROM {group_members} WHERE group_id=$1"
    ))
    .bind(group_id)
    .fetch_all(&state.pool)
    .await
    .unwrap_or_default();
    let mut out = Vec::with_capacity(rows.len());
    for r in rows {
        if let Ok(did) = r.try_get::<String, _>("device_id") {
            out.push(did);
        }
    }
    out
}

async fn notify_recipient(state: AppState, recipient_id: String, sender_id: Option<String>) {
    let Some(server_key) = state
        .fcm_server_key
        .clone()
        .filter(|s| !s.trim().is_empty())
    else {
        return;
    };

    // Respect global hidden mode: if the recipient has any hidden peers, do not send push.
    if has_hidden(&state, &recipient_id).await {
        return;
    }

    // Respect mutes (Shamell-like).
    if let Some(sid) = sender_id.as_deref() {
        if is_muted(&state, &recipient_id, Some(sid)).await {
            return;
        }
    }

    let push_tokens = state.table("push_tokens");
    let rows = match sqlx::query(&format!(
        "SELECT token FROM {push_tokens} WHERE device_id=$1"
    ))
    .bind(&recipient_id)
    .fetch_all(&state.pool)
    .await
    {
        Ok(r) => r,
        Err(_) => return,
    };
    if rows.is_empty() {
        return;
    }

    let headers = [("Authorization", format!("key={server_key}"))];

    for r in rows {
        let tok: String = match r.try_get("token") {
            Ok(v) => v,
            Err(_) => continue,
        };

        let data = build_push_data();

        let payload = json!({
            "to": tok,
            "priority": "high",
            "content_available": true,
            "data": data,
        });

        let req = state
            .http
            .post(FCM_ENDPOINT)
            .header("Content-Type", "application/json");

        let req = headers.iter().fold(req, |r, (k, v)| r.header(*k, v));

        let _ = req.json(&payload).send().await;
    }
}

fn build_push_data() -> serde_json::Map<String, serde_json::Value> {
    let mut data = serde_json::Map::new();
    data.insert("type".to_string(), json!(PUSH_TYPE_CHAT_WAKEUP));
    data.insert("wakeup".to_string(), json!(true));
    data
}

async fn notify_group(state: AppState, group_id: String, sender_id: String) {
    let Some(server_key) = state
        .fcm_server_key
        .clone()
        .filter(|s| !s.trim().is_empty())
    else {
        return;
    };
    drop(server_key); // only used to decide if we do push at all

    let members = group_member_ids(&state, &group_id).await;
    for did in members {
        if did == sender_id {
            continue;
        }
        // Respect group mute for recipient.
        let group_prefs = state.table("group_prefs");
        let muted = sqlx::query(&format!(
            "SELECT 1 as one FROM {group_prefs} WHERE device_id=$1 AND group_id=$2 AND muted=1 LIMIT 1"
        ))
        .bind(&did)
        .bind(&group_id)
        .fetch_optional(&state.pool)
        .await
        .ok()
        .flatten()
        .is_some();
        if muted {
            continue;
        }
        // Best-effort: respect blocks against sender
        if is_blocked(&state, &did, Some(&sender_id)).await {
            continue;
        }
        notify_recipient(state.clone(), did, Some(sender_id.clone())).await;
    }
}

pub async fn register(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<RegisterReq>,
) -> ApiResult<axum::Json<DeviceRegisterOut>> {
    let did = body.device_id.trim().to_string();
    if !is_valid_device_id(&did) {
        return Err(ApiError::bad_request("invalid device id"));
    }
    let pk = normalize_key_material(&body.public_key_b64, "public_key_b64", 32, 255)?;
    let name = body.name.as_ref().map(|s| s.trim().to_string());
    if let Some(n) = &name {
        if n.len() > 120 {
            return Err(ApiError::bad_request("invalid name"));
        }
    }

    let devices = state.table("devices");
    let device_auth = state.table("device_auth");
    let device_key_events = state.table("device_key_events");

    let mut tx = state
        .pool
        .begin()
        .await
        .map_err(|_| ApiError::internal("database error"))?;

    let existing = sqlx::query(&format!(
        "SELECT public_key,key_version,name FROM {devices} WHERE id=$1"
    ))
    .bind(&did)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| ApiError::internal("database error"))?;

    let created_at = now_iso();

    // Token issuance helper (matches Python: secrets.token_hex(32)).
    let issue_token = || -> String {
        let mut bytes = [0u8; 32];
        getrandom::getrandom(&mut bytes).expect("getrandom");
        hex::encode(bytes)
    };

    let issued_token: Option<String> = None;

    if let Some(row) = existing {
        let old_key: String = row.try_get("public_key").unwrap_or_default();
        let cur_ver: i64 = row.try_get("key_version").unwrap_or(0);

        let auth_row = sqlx::query(&format!(
            "SELECT token_hash FROM {device_auth} WHERE device_id=$1"
        ))
        .bind(&did)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| ApiError::internal("database error"))?;

        if auth_row.is_some() {
            enforce_device_actor(&state, &headers, &state.pool, &did).await?;
        } else {
            return Err(ApiError::unauthorized("device auth bootstrap disabled"));
        }

        // Key rotation event.
        if !pk.is_empty() && !old_key.is_empty() && pk != old_key {
            let next_ver = cur_ver + 1;
            let old_fp = fp_for_key(&old_key);
            let new_fp = fp_for_key(&pk);
            let _ = sqlx::query(&format!(
                "INSERT INTO {device_key_events} (device_id, version, old_key_fp, new_key_fp, created_at) VALUES ($1,$2,$3,$4,$5)"
            ))
            .bind(&did)
            .bind(next_ver)
            .bind(old_fp)
            .bind(new_fp)
            .bind(&created_at)
            .execute(&mut *tx)
            .await;
            let _ = sqlx::query(&format!(
                "UPDATE {devices} SET public_key=$1, key_version=$2, name=$3 WHERE id=$4"
            ))
            .bind(&pk)
            .bind(next_ver)
            .bind(&name)
            .bind(&did)
            .execute(&mut *tx)
            .await;
        } else {
            let _ = sqlx::query(&format!(
                "UPDATE {devices} SET public_key=$1, name=$2 WHERE id=$3"
            ))
            .bind(if pk.is_empty() { &old_key } else { &pk })
            .bind(&name)
            .bind(&did)
            .execute(&mut *tx)
            .await;
        }

        tx.commit()
            .await
            .map_err(|_| ApiError::internal("database error"))?;

        // Reload for response.
        let row = sqlx::query(&format!(
            "SELECT public_key,key_version,name FROM {devices} WHERE id=$1"
        ))
        .bind(&did)
        .fetch_one(&state.pool)
        .await
        .map_err(|_| ApiError::internal("database error"))?;
        let public_key: String = row.try_get("public_key").unwrap_or_default();
        let key_version: i64 = row.try_get("key_version").unwrap_or(0);
        let name_db: Option<String> = row.try_get("name").ok();

        return Ok(axum::Json(DeviceRegisterOut {
            device_id: did,
            public_key_b64: public_key,
            name: name_db,
            key_version,
            auth_token: issued_token,
        }));
    }

    // Create device + issue initial token.
    let token = issue_token();
    let digest = sha256_hex(&token);

    sqlx::query(&format!(
        "INSERT INTO {devices} (id, public_key, key_version, name, created_at) VALUES ($1,$2,$3,$4,$5)"
    ))
    .bind(&did)
    .bind(&pk)
    .bind(0_i64)
    .bind(&name)
    .bind(&created_at)
    .execute(&mut *tx)
    .await
    .map_err(|_| ApiError::internal("database error"))?;

    sqlx::query(&format!(
        "INSERT INTO {device_auth} (device_id, token_hash, rotated_at) VALUES ($1,$2,$3)"
    ))
    .bind(&did)
    .bind(&digest)
    .bind(&created_at)
    .execute(&mut *tx)
    .await
    .map_err(|_| ApiError::internal("database error"))?;

    tx.commit()
        .await
        .map_err(|_| ApiError::internal("database error"))?;

    Ok(axum::Json(DeviceRegisterOut {
        device_id: did,
        public_key_b64: pk,
        name,
        key_version: 0,
        auth_token: Some(token),
    }))
}

pub async fn get_device(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(device_id): Path<String>,
) -> ApiResult<axum::Json<DeviceOut>> {
    let actor = require_device_actor(&state, &headers, &state.pool).await?;
    let Some(_actor) = actor else {
        return Err(ApiError::unauthorized("chat device auth required"));
    };
    let device_id = device_id.trim().to_string();
    if !is_valid_device_id(&device_id) {
        // Fail closed and avoid hitting the DB for obviously-invalid ids.
        return Err(ApiError::not_found("not found"));
    }
    let devices = state.table("devices");
    let row = sqlx::query(&format!(
        "SELECT id,public_key,key_version,name FROM {devices} WHERE id=$1"
    ))
    .bind(&device_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?
    .ok_or_else(|| ApiError::not_found("not found"))?;
    let id: String = row.try_get("id").unwrap_or_default();
    let public_key: String = row.try_get("public_key").unwrap_or_default();
    let key_version: i64 = row.try_get("key_version").unwrap_or(0);
    let name: Option<String> = row.try_get("name").ok();
    Ok(axum::Json(DeviceOut {
        device_id: id,
        public_key_b64: public_key,
        name,
        key_version,
    }))
}

pub async fn register_keys(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<KeyRegisterReq>,
) -> ApiResult<axum::Json<KeyRegisterOut>> {
    let did = body.device_id.trim().to_string();
    if !is_valid_device_id(&did) {
        return Err(ApiError::bad_request("invalid device id"));
    }
    let v2_only =
        match require_v2_only_key_registration(state.chat_protocol_v2_enabled, body.v2_only) {
            Ok(v2_only) => v2_only,
            Err(err) => {
                let reason = if state.chat_protocol_v2_enabled {
                    "v2_only_required"
                } else {
                    "protocol_v2_disabled"
                };
                audit_chat_security_blocked(
                    "chat_key_register_policy",
                    reason,
                    Some(&did),
                    None,
                    None,
                );
                return Err(err);
            }
        };
    if body.signed_prekey_id <= 0 {
        return Err(ApiError::bad_request("invalid signed_prekey_id"));
    }
    let identity_key_b64 =
        normalize_key_material(&body.identity_key_b64, "identity_key_b64", 32, 8192)?;
    let identity_signing_pubkey_raw = body
        .identity_signing_pubkey_b64
        .as_deref()
        .ok_or_else(|| ApiError::bad_request("identity_signing_pubkey_b64 required"))?;
    let identity_signing_pubkey_b64 = normalize_key_material(
        identity_signing_pubkey_raw,
        "identity_signing_pubkey_b64",
        32,
        8192,
    )?;
    let signed_prekey_b64 =
        normalize_key_material(&body.signed_prekey_b64, "signed_prekey_b64", 16, 8192)?;
    let signed_prekey_sig_b64 = normalize_key_material(
        &body.signed_prekey_sig_b64,
        "signed_prekey_sig_b64",
        16,
        8192,
    )?;
    let signed_prekey_sig_alg = body
        .signed_prekey_sig_alg
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_ascii_lowercase)
        .ok_or_else(|| ApiError::bad_request("signed_prekey_sig_alg required"))?;
    if signed_prekey_sig_alg != SIGNED_PREKEY_SIG_ALG_ED25519 {
        return Err(ApiError::bad_request(
            "signed_prekey_sig_alg must be ed25519",
        ));
    }
    verify_signed_prekey_signature(
        &did,
        &identity_key_b64,
        body.signed_prekey_id,
        &signed_prekey_b64,
        &identity_signing_pubkey_b64,
        &signed_prekey_sig_b64,
    )?;

    enforce_device_actor(&state, &headers, &state.pool, &did).await?;

    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &did).await? {
        return Err(ApiError::not_found("unknown device"));
    }

    let protocol_floor = PROTOCOL_V2_LIBSIGNAL;
    let now = now_iso();

    let chat_identity_keys = state.table("chat_identity_keys");
    let chat_signed_prekeys = state.table("chat_signed_prekeys");
    let chat_device_protocol_state = state.table("chat_device_protocol_state");
    let mut tx = state
        .pool
        .begin()
        .await
        .map_err(|_| ApiError::internal("database error"))?;

    sqlx::query(&format!(
        "INSERT INTO {chat_identity_keys} (device_id,identity_key_b64,identity_signing_key_b64,updated_at) VALUES ($1,$2,$3,$4) \
         ON CONFLICT (device_id) DO UPDATE SET identity_key_b64=EXCLUDED.identity_key_b64, identity_signing_key_b64=EXCLUDED.identity_signing_key_b64, updated_at=EXCLUDED.updated_at"
    ))
    .bind(&did)
    .bind(&identity_key_b64)
    .bind(&identity_signing_pubkey_b64)
    .bind(&now)
    .execute(&mut *tx)
    .await
    .map_err(|_| ApiError::internal("database error"))?;

    sqlx::query(&format!(
        "INSERT INTO {chat_signed_prekeys} (device_id,key_id,public_key_b64,signature_b64,updated_at) VALUES ($1,$2,$3,$4,$5) \
         ON CONFLICT (device_id) DO UPDATE SET key_id=EXCLUDED.key_id, public_key_b64=EXCLUDED.public_key_b64, signature_b64=EXCLUDED.signature_b64, updated_at=EXCLUDED.updated_at"
    ))
    .bind(&did)
    .bind(body.signed_prekey_id)
    .bind(&signed_prekey_b64)
    .bind(&signed_prekey_sig_b64)
    .bind(&now)
    .execute(&mut *tx)
    .await
    .map_err(|_| ApiError::internal("database error"))?;

    sqlx::query(&format!(
        "INSERT INTO {chat_device_protocol_state} (device_id,protocol_floor,supports_v2,v2_only,updated_at) VALUES ($1,$2,$3,$4,$5) \
         ON CONFLICT (device_id) DO UPDATE SET protocol_floor=EXCLUDED.protocol_floor, supports_v2=EXCLUDED.supports_v2, v2_only=EXCLUDED.v2_only, updated_at=EXCLUDED.updated_at"
    ))
    .bind(&did)
    .bind(protocol_floor)
    .bind(1_i64)
    .bind(if v2_only { 1_i64 } else { 0_i64 })
    .bind(&now)
    .execute(&mut *tx)
    .await
    .map_err(|_| ApiError::internal("database error"))?;

    tx.commit()
        .await
        .map_err(|_| ApiError::internal("database error"))?;

    Ok(axum::Json(KeyRegisterOut {
        device_id: did,
        identity_key_b64,
        identity_signing_pubkey_b64,
        signed_prekey_id: body.signed_prekey_id,
        signed_prekey_b64,
        signed_prekey_sig_b64,
        signed_prekey_sig_alg,
        supports_v2: true,
        v2_only,
        updated_at: now,
    }))
}

pub async fn upload_prekeys(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<PrekeysUploadReq>,
) -> ApiResult<axum::Json<PrekeysUploadOut>> {
    let did = body.device_id.trim().to_string();
    if !is_valid_device_id(&did) {
        return Err(ApiError::bad_request("invalid device id"));
    }
    let normalized_prekeys = normalize_prekey_batch(&body.prekeys)?;
    enforce_device_actor(&state, &headers, &state.pool, &did).await?;

    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &did).await? {
        return Err(ApiError::not_found("unknown device"));
    }

    let chat_one_time_prekeys = state.table("chat_one_time_prekeys");
    let now = now_iso();
    let mut tx = state
        .pool
        .begin()
        .await
        .map_err(|_| ApiError::internal("database error"))?;

    for (key_id, key_b64) in &normalized_prekeys {
        sqlx::query(&format!(
            "INSERT INTO {chat_one_time_prekeys} (device_id,key_id,key_b64,created_at,consumed_at) VALUES ($1,$2,$3,$4,NULL) \
             ON CONFLICT (device_id,key_id) DO UPDATE SET key_b64=EXCLUDED.key_b64, created_at=EXCLUDED.created_at, consumed_at=NULL"
        ))
        .bind(&did)
        .bind(*key_id)
        .bind(key_b64)
        .bind(&now)
        .execute(&mut *tx)
        .await
        .map_err(|_| ApiError::internal("database error"))?;
    }

    tx.commit()
        .await
        .map_err(|_| ApiError::internal("database error"))?;

    let count_row = sqlx::query(&format!(
        "SELECT COUNT(*) as count FROM {chat_one_time_prekeys} WHERE device_id=$1 AND consumed_at IS NULL"
    ))
    .bind(&did)
    .fetch_one(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;
    let available: i64 = count_row.try_get("count").unwrap_or(0);

    Ok(axum::Json(PrekeysUploadOut {
        device_id: did,
        uploaded: normalized_prekeys.len() as i64,
        available,
    }))
}

pub async fn get_key_bundle(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(device_id): Path<String>,
) -> ApiResult<axum::Json<KeyBundleOut>> {
    let target_id = device_id.trim().to_string();
    if !is_valid_device_id(&target_id) {
        return Err(ApiError::bad_request("invalid device id"));
    }
    let actor = require_device_actor(&state, &headers, &state.pool)
        .await?
        .ok_or_else(|| ApiError::unauthorized("chat device auth required"))?;
    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &target_id).await? {
        return Err(ApiError::not_found("unknown device"));
    }

    let chat_identity_keys = state.table("chat_identity_keys");
    let chat_signed_prekeys = state.table("chat_signed_prekeys");
    let chat_one_time_prekeys = state.table("chat_one_time_prekeys");
    let chat_device_protocol_state = state.table("chat_device_protocol_state");
    let now = now_iso();
    let mut tx = state
        .pool
        .begin()
        .await
        .map_err(|_| ApiError::internal("database error"))?;

    let row = sqlx::query(&format!(
        "SELECT i.identity_key_b64,i.identity_signing_key_b64,s.key_id,s.public_key_b64,s.signature_b64,\
         COALESCE(ps.protocol_floor,$2) as protocol_floor,\
         COALESCE(ps.supports_v2,0) as supports_v2,\
         COALESCE(ps.v2_only,0) as v2_only \
         FROM {chat_identity_keys} i \
         JOIN {chat_signed_prekeys} s ON s.device_id=i.device_id \
         LEFT JOIN {chat_device_protocol_state} ps ON ps.device_id=i.device_id \
         WHERE i.device_id=$1"
    ))
    .bind(&target_id)
    .bind(PROTOCOL_V1_LEGACY)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| ApiError::internal("database error"))?
    .ok_or_else(|| ApiError::not_found("bundle unavailable"))?;

    let identity_key_b64: String = row.try_get("identity_key_b64").unwrap_or_default();
    let identity_signing_pubkey_b64: Option<String> = row.try_get("identity_signing_key_b64").ok();
    let signed_prekey_id: i64 = row.try_get("key_id").unwrap_or(0);
    let signed_prekey_b64: String = row.try_get("public_key_b64").unwrap_or_default();
    let signed_prekey_sig_b64: String = row.try_get("signature_b64").unwrap_or_default();
    let protocol_floor: String = row
        .try_get("protocol_floor")
        .unwrap_or(PROTOCOL_V1_LEGACY.to_string());
    let supports_v2_i: i64 = row.try_get("supports_v2").unwrap_or(0);
    let v2_only_i: i64 = row.try_get("v2_only").unwrap_or(0);
    let supports_v2 = supports_v2_i != 0;
    let v2_only = v2_only_i != 0;

    if !is_strict_v2_bundle_eligible(
        &protocol_floor,
        supports_v2,
        v2_only,
        &identity_key_b64,
        identity_signing_pubkey_b64.as_deref(),
        signed_prekey_id,
        &signed_prekey_b64,
        &signed_prekey_sig_b64,
    ) {
        let _ = tx.rollback().await;
        audit_chat_security_blocked(
            "chat_key_bundle_policy",
            "strict_v2_bundle_required",
            Some(&actor),
            Some(&target_id),
            None,
        );
        // Keep response generic to avoid exposing policy-state details.
        return Err(ApiError::not_found("bundle unavailable"));
    }

    let consumed = sqlx::query(&format!(
        "WITH picked AS (\
            SELECT device_id,key_id,key_b64 FROM {chat_one_time_prekeys} \
            WHERE device_id=$1 AND consumed_at IS NULL \
            ORDER BY created_at ASC \
            LIMIT 1 \
            FOR UPDATE SKIP LOCKED\
         ) \
         UPDATE {chat_one_time_prekeys} otk \
         SET consumed_at=$2 \
         FROM picked \
         WHERE otk.device_id=picked.device_id AND otk.key_id=picked.key_id \
         RETURNING picked.key_id as key_id,picked.key_b64 as key_b64"
    ))
    .bind(&target_id)
    .bind(&now)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| ApiError::internal("database error"))?;

    tx.commit()
        .await
        .map_err(|_| ApiError::internal("database error"))?;

    let one_time_prekey_id: Option<i64> = consumed.as_ref().and_then(|r| r.try_get("key_id").ok());
    let one_time_prekey_b64: Option<String> =
        consumed.as_ref().and_then(|r| r.try_get("key_b64").ok());

    Ok(axum::Json(KeyBundleOut {
        device_id: target_id,
        identity_key_b64,
        identity_signing_pubkey_b64,
        signed_prekey_id,
        signed_prekey_b64,
        signed_prekey_sig_b64,
        one_time_prekey_id,
        one_time_prekey_b64,
        protocol_floor: protocol_floor.trim().to_string(),
        supports_v2,
        v2_only,
    }))
}

pub async fn send_message(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<SendReq>,
) -> ApiResult<axum::Json<MsgOut>> {
    let sender_id = body.sender_id.trim().to_string();
    let recipient_id = body.recipient_id.trim().to_string();
    let protocol_version = parse_protocol_version(body.protocol_version.as_deref())?;
    validate_protocol_write(
        state.chat_protocol_v2_enabled,
        state.chat_protocol_v1_write_enabled,
        state.chat_protocol_require_v2_for_groups,
        protocol_version,
        false,
    )?;
    enforce_device_actor(&state, &headers, &state.pool, &sender_id).await?;

    if sender_id.is_empty()
        || recipient_id.is_empty()
        || !is_valid_device_id(&sender_id)
        || !is_valid_device_id(&recipient_id)
    {
        return Err(ApiError::bad_request("invalid sender/recipient"));
    }
    if sender_id == recipient_id {
        return Err(ApiError::bad_request("invalid sender/recipient"));
    }

    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &sender_id).await?
        || !device_exists(&state.pool, &devices, &recipient_id).await?
    {
        return Err(ApiError::not_found("unknown device"));
    }
    enforce_no_protocol_downgrade_direct(&state, &sender_id, &recipient_id, protocol_version)
        .await?;

    if is_blocked(&state, &recipient_id, Some(&sender_id)).await {
        return Err(ApiError::forbidden("blocked by recipient"));
    }

    // Fail-closed: require ciphertext envelope for direct messages.
    // Also validate key/ciphertext material to avoid database constraint errors
    // and to reduce DoS surface (oversized/invalid payloads).
    let sender_pubkey_b64 =
        normalize_key_material(&body.sender_pubkey_b64, "sender_pubkey_b64", 32, 255)?;
    let sender_dh_pub_b64 = body
        .sender_dh_pub_b64
        .as_deref()
        .map(|s| normalize_key_material(s, "sender_dh_pub_b64", 16, 255))
        .transpose()?;
    let (nonce_b64, box_b64) = parse_required_direct_ciphertext(&body.nonce_b64, &body.box_b64)?;
    let key_id = body
        .key_id
        .as_deref()
        .map(|s| normalize_key_material(s, "key_id", 1, 64))
        .transpose()?;
    let prev_key_id = body
        .prev_key_id
        .as_deref()
        .map(|s| normalize_key_material(s, "prev_key_id", 1, 64))
        .transpose()?;

    let messages = state.table("messages");
    let existed = sqlx::query(&format!(
        "SELECT id,sender_id,recipient_id,protocol_version,sender_pubkey,sender_dh_pub,nonce_b64,box_b64,created_at,delivered_at,read_at,expire_at,sealed_sender,sender_hint,key_id,prev_key_id FROM {messages} WHERE sender_id=$1 AND recipient_id=$2 AND nonce_b64=$3 AND box_b64=$4 LIMIT 1"
    ))
    .bind(&sender_id)
    .bind(&recipient_id)
    .bind(&nonce_b64)
    .bind(&box_b64)
    .fetch_optional(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;
    if let Some(r) = existed {
        let row_protocol = parse_row_protocol_version(
            r.try_get::<Option<String>, _>("protocol_version")
                .ok()
                .flatten()
                .as_deref(),
        );
        let sealed_sender: i64 = r.try_get("sealed_sender").unwrap_or(0);
        let sender_hint: Option<String> = r.try_get("sender_hint").ok();
        let key_id: Option<String> = r.try_get("key_id").ok();
        let prev_key_id: Option<String> = r.try_get("prev_key_id").ok();
        return Ok(axum::Json(MsgOut {
            id: r.try_get("id").unwrap_or_default(),
            sender_id: if sealed_sender != 0 {
                None
            } else {
                Some(r.try_get("sender_id").unwrap_or_default())
            },
            recipient_id: r.try_get("recipient_id").unwrap_or_default(),
            protocol_version: row_protocol.as_str().to_string(),
            sender_pubkey_b64: if sealed_sender != 0 {
                None
            } else {
                Some(r.try_get("sender_pubkey").unwrap_or_default())
            },
            sender_dh_pub_b64: r.try_get("sender_dh_pub").ok(),
            nonce_b64: r.try_get("nonce_b64").unwrap_or_default(),
            box_b64: r.try_get("box_b64").unwrap_or_default(),
            created_at: r.try_get("created_at").ok(),
            delivered_at: r.try_get("delivered_at").ok(),
            read_at: r.try_get("read_at").ok(),
            expire_at: r.try_get("expire_at").ok(),
            sealed_sender: sealed_sender != 0,
            sender_hint: sender_hint.clone(),
            sender_fingerprint: sender_hint,
            key_id,
            prev_key_id,
        }));
    }

    let expire_at = match body.expire_after_seconds {
        Some(secs) if secs > 0 => {
            if !(10..=7 * 24 * 3600).contains(&secs) {
                return Err(ApiError::bad_request("invalid expire_after_seconds"));
            }
            Some((Utc::now() + Duration::seconds(secs)).to_rfc3339_opts(SecondsFormat::Secs, true))
        }
        _ => None,
    };

    let sealed_sender = require_sealed_sender_flag(body.sealed_sender)?;
    let sender_hint_norm = body
        .sender_hint
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|s| normalize_key_material(s, "sender_hint", 4, 64))
        .transpose()?;
    let sender_fp = body
        .sender_fingerprint
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|s| normalize_key_material(s, "sender_fingerprint", 4, 64))
        .transpose()?;
    // DB only has sender_hint. If a client only provides sender_fingerprint, persist it as the hint.
    let hint = sender_hint_norm.clone().or_else(|| sender_fp.clone());

    let mid = Uuid::new_v4().to_string();
    let created_at = now_iso();
    sqlx::query(&format!(
        "INSERT INTO {messages} (id,sender_id,recipient_id,protocol_version,sender_pubkey,sender_dh_pub,nonce_b64,box_b64,created_at,expire_at,sealed_sender,sender_hint,key_id,prev_key_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)"
    ))
    .bind(&mid)
    .bind(&sender_id)
    .bind(&recipient_id)
    .bind(protocol_version.as_str())
    .bind(&sender_pubkey_b64)
    .bind(sender_dh_pub_b64.as_deref())
    .bind(&nonce_b64)
    .bind(&box_b64)
    .bind(&created_at)
    .bind(&expire_at)
    .bind(if sealed_sender { 1_i64 } else { 0_i64 })
    .bind(&hint)
    .bind(key_id.as_deref())
    .bind(prev_key_id.as_deref())
    .execute(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;

    // Best-effort push notification.
    let push_state = state.clone();
    let push_recipient_id = recipient_id.clone();
    let push_sender_id = sender_id.clone();
    tokio::spawn(async move {
        notify_recipient(push_state, push_recipient_id, Some(push_sender_id)).await;
    });

    Ok(axum::Json(MsgOut {
        id: mid,
        sender_id: if sealed_sender { None } else { Some(sender_id) },
        recipient_id,
        protocol_version: protocol_version.as_str().to_string(),
        sender_pubkey_b64: if sealed_sender {
            None
        } else {
            Some(sender_pubkey_b64)
        },
        sender_dh_pub_b64: if sealed_sender {
            None
        } else {
            sender_dh_pub_b64
        },
        nonce_b64,
        box_b64,
        created_at: Some(created_at),
        delivered_at: None,
        read_at: None,
        expire_at,
        sealed_sender,
        sender_hint: hint.clone().or_else(|| sender_fp.clone()),
        sender_fingerprint: sender_fp.or(hint),
        key_id,
        prev_key_id,
    }))
}

pub async fn inbox(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(params): Query<InboxParams>,
) -> ApiResult<axum::Json<Vec<MsgOut>>> {
    let device_id = params.device_id.trim().to_string();
    if !is_valid_device_id(&device_id) {
        return Err(ApiError::not_found("not found"));
    }
    enforce_device_actor(&state, &headers, &state.pool, &device_id).await?;
    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &device_id).await? {
        return Err(ApiError::not_found("unknown device"));
    }
    let device_v2_only = is_device_v2_only(&state, &device_id).await?;

    purge_expired(&state).await?;

    let blocked = blocked_peers(&state, &device_id).await;
    let hidden = hidden_peers(&state, &device_id).await;

    let limit = params.limit.unwrap_or(50).clamp(1, 200);
    // Hardening: never allow clients to downgrade sealed-sender views.
    // (Even if legacy rows exist, the server must not reveal sender identifiers.)
    let sealed_view = true;

    let messages = state.table("messages");
    let mut sql = format!(
        "SELECT id,sender_id,recipient_id,protocol_version,sender_pubkey,sender_dh_pub,nonce_b64,box_b64,created_at,delivered_at,read_at,expire_at,sealed_sender,sender_hint,key_id,prev_key_id FROM {messages} WHERE recipient_id=$1"
    );
    if !state.chat_protocol_v1_read_enabled || device_v2_only {
        sql.push_str(&format!(
            " AND COALESCE(protocol_version,'{PROTOCOL_V1_LEGACY}') <> '{PROTOCOL_V1_LEGACY}'"
        ));
    }
    let mut binds: Vec<String> = Vec::new();
    if let Some(since) = params.since_iso.as_deref() {
        let since = canonical_iso(since)?;
        sql.push_str(" AND created_at >= $2");
        binds.push(since);
        sql.push_str(" AND (expire_at IS NULL OR expire_at >= $3)");
    } else {
        sql.push_str(" AND (expire_at IS NULL OR expire_at >= $2)");
    }
    sql.push_str(&format!(" ORDER BY created_at DESC LIMIT {limit}"));

    let now = now_iso();
    let mut q = sqlx::query(&sql).bind(&device_id);
    if binds.len() == 1 {
        q = q.bind(&binds[0]).bind(&now);
    } else {
        q = q.bind(&now);
    }

    let rows = q
        .fetch_all(&state.pool)
        .await
        .map_err(|_| ApiError::internal("database error"))?;

    let mut out: Vec<MsgOut> = Vec::with_capacity(rows.len());
    let mut deliver_ids: Vec<String> = Vec::new();
    for r in rows {
        let sender_id: String = r.try_get("sender_id").unwrap_or_default();
        if blocked.contains(&sender_id) || hidden.contains(&sender_id) {
            continue;
        }
        let protocol_version = parse_row_protocol_version(
            r.try_get::<Option<String>, _>("protocol_version")
                .ok()
                .flatten()
                .as_deref(),
        );
        let delivered_at: Option<String> = r.try_get("delivered_at").ok();
        if delivered_at.as_deref().unwrap_or("").trim().is_empty() {
            deliver_ids.push(r.try_get("id").unwrap_or_default());
        }
        let sealed_flag: i64 = r.try_get("sealed_sender").unwrap_or(0);
        let redact_sender = should_redact_sender(sealed_flag, sealed_view);
        let sender_hint: Option<String> = r.try_get("sender_hint").ok();
        out.push(MsgOut {
            id: r.try_get("id").unwrap_or_default(),
            sender_id: if redact_sender { None } else { Some(sender_id) },
            recipient_id: r.try_get("recipient_id").unwrap_or_default(),
            protocol_version: protocol_version.as_str().to_string(),
            sender_pubkey_b64: if redact_sender {
                None
            } else {
                Some(r.try_get("sender_pubkey").unwrap_or_default())
            },
            sender_dh_pub_b64: r.try_get("sender_dh_pub").ok(),
            nonce_b64: r.try_get("nonce_b64").unwrap_or_default(),
            box_b64: r.try_get("box_b64").unwrap_or_default(),
            created_at: r.try_get("created_at").ok(),
            delivered_at: delivered_at.clone().filter(|s| !s.trim().is_empty()),
            read_at: r.try_get("read_at").ok(),
            expire_at: r.try_get("expire_at").ok(),
            sealed_sender: redact_sender,
            sender_hint: sender_hint.clone(),
            sender_fingerprint: sender_hint,
            key_id: r.try_get("key_id").ok(),
            prev_key_id: r.try_get("prev_key_id").ok(),
        });
    }

    if !deliver_ids.is_empty() {
        let delivered_at = now_iso();
        for mid in deliver_ids {
            let _ = sqlx::query(&format!(
                "UPDATE {messages} SET delivered_at=$1 WHERE id=$2 AND (delivered_at IS NULL OR delivered_at='')"
            ))
            .bind(&delivered_at)
            .bind(&mid)
            .execute(&state.pool)
            .await;
        }
    }

    Ok(axum::Json(out))
}

pub async fn stream(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(params): Query<InboxParams>,
) -> ApiResult<impl IntoResponse> {
    let device_id = params.device_id.trim().to_string();
    if !is_valid_device_id(&device_id) {
        return Err(ApiError::not_found("not found"));
    }
    enforce_device_actor(&state, &headers, &state.pool, &device_id).await?;
    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &device_id).await? {
        return Err(ApiError::not_found("unknown device"));
    }
    let device_v2_only = is_device_v2_only(&state, &device_id).await?;

    // Hardening: never allow clients to downgrade sealed-sender views.
    let sealed_view = true;

    let state_clone = state.clone();
    let device_id_clone = device_id.clone();
    let messages = state.table("messages");
    let read_filter = if state.chat_protocol_v1_read_enabled && !device_v2_only {
        String::new()
    } else {
        format!(" AND COALESCE(protocol_version,'{PROTOCOL_V1_LEGACY}') <> '{PROTOCOL_V1_LEGACY}'")
    };
    let last_seen = Arc::new(tokio::sync::Mutex::new(now_iso()));

    let stream = tokio_stream::wrappers::IntervalStream::new(tokio::time::interval(
        StdDuration::from_secs(1),
    ))
    .then(move |_| {
        let state = state_clone.clone();
        let device_id = device_id_clone.clone();
        let messages = messages.clone();
        let read_filter = read_filter.clone();
        let last_seen = last_seen.clone();
        async move {
            let last = { last_seen.lock().await.clone() };
            let _ = purge_expired(&state).await;
            let blocked = blocked_peers(&state, &device_id).await;
            let hidden = hidden_peers(&state, &device_id).await;
            let now = now_iso();

            let rows = sqlx::query(&format!(
                "SELECT id,sender_id,recipient_id,protocol_version,sender_pubkey,sender_dh_pub,nonce_b64,box_b64,created_at,delivered_at,read_at,expire_at,sealed_sender,sender_hint,key_id,prev_key_id FROM {messages} WHERE recipient_id=$1 AND created_at >= $2 AND (expire_at IS NULL OR expire_at >= $3){read_filter} ORDER BY created_at ASC LIMIT 100"
            ))
            .bind(&device_id)
            .bind(&last)
            .bind(&now)
            .fetch_all(&state.pool)
            .await
            .unwrap_or_default();

            let mut events: Vec<Event> = Vec::new();
            let mut deliver_ids: Vec<String> = Vec::new();
            let mut new_last: Option<String> = None;
            for r in rows {
                let sender_id: String = r.try_get("sender_id").unwrap_or_default();
                if blocked.contains(&sender_id) || hidden.contains(&sender_id) {
                    continue;
                }
                let created_at: String = r.try_get("created_at").unwrap_or_default();
                if !created_at.trim().is_empty() {
                    new_last = Some(created_at.clone());
                }
                let delivered_at: Option<String> = r.try_get("delivered_at").ok();
                if delivered_at.as_deref().unwrap_or("").trim().is_empty() {
                    deliver_ids.push(r.try_get("id").unwrap_or_default());
                }
                let sealed_flag: i64 = r.try_get("sealed_sender").unwrap_or(0);
                let redact_sender = should_redact_sender(sealed_flag, sealed_view);
                let sender_hint: Option<String> = r.try_get("sender_hint").ok();
                let protocol_version = parse_row_protocol_version(
                    r.try_get::<Option<String>, _>("protocol_version")
                        .ok()
                        .flatten()
                        .as_deref(),
                );
                let payload = json!({
                    "id": r.try_get::<String,_>("id").unwrap_or_default(),
                    "sender_id": if redact_sender { serde_json::Value::Null } else { json!(sender_id) },
                    "recipient_id": r.try_get::<String,_>("recipient_id").unwrap_or_default(),
                    "protocol_version": protocol_version.as_str(),
                    "nonce_b64": r.try_get::<String,_>("nonce_b64").unwrap_or_default(),
                    "box_b64": r.try_get::<String,_>("box_b64").unwrap_or_default(),
                    "sender_pubkey_b64": if redact_sender { serde_json::Value::Null } else { json!(r.try_get::<String,_>("sender_pubkey").unwrap_or_default()) },
                    "sender_dh_pub_b64": r.try_get::<Option<String>,_>("sender_dh_pub").ok().flatten(),
                    "created_at": created_at,
                    "delivered_at": delivered_at.clone(),
                    "read_at": r.try_get::<Option<String>,_>("read_at").ok().flatten(),
                    "expire_at": r.try_get::<Option<String>,_>("expire_at").ok().flatten(),
                    "sealed_sender": redact_sender,
                    "sender_hint": sender_hint.clone(),
                    "sender_fingerprint": sender_hint,
                    "key_id": r.try_get::<Option<String>,_>("key_id").ok().flatten(),
                    "prev_key_id": r.try_get::<Option<String>,_>("prev_key_id").ok().flatten(),
                });
                events.push(Event::default().data(payload.to_string()));
            }

            if let Some(nl) = new_last {
                *last_seen.lock().await = nl;
            }

            if !deliver_ids.is_empty() {
                let delivered_at = now_iso();
                for mid in deliver_ids {
                    let _ = sqlx::query(&format!(
                        "UPDATE {messages} SET delivered_at=$1 WHERE id=$2 AND (delivered_at IS NULL OR delivered_at='')"
                    ))
                    .bind(&delivered_at)
                    .bind(&mid)
                    .execute(&state.pool)
                    .await;
                }
            }

            events
        }
    })
    .flat_map(tokio_stream::iter)
    .map(Ok::<Event, Infallible>);

    Ok(Sse::new(stream).keep_alive(
        axum::response::sse::KeepAlive::new()
            .interval(StdDuration::from_secs(15))
            .text("keep-alive"),
    ))
}

pub async fn mark_read(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(mid): Path<String>,
    axum::Json(body): axum::Json<ReadReq>,
) -> ApiResult<axum::Json<serde_json::Value>> {
    let mid = mid.trim().to_string();
    if mid.len() != 36 || Uuid::parse_str(&mid).is_err() {
        return Err(ApiError::not_found("not found"));
    }
    let messages = state.table("messages");
    let row = sqlx::query(&format!(
        "SELECT id,recipient_id FROM {messages} WHERE id=$1"
    ))
    .bind(&mid)
    .fetch_optional(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?
    .ok_or_else(|| ApiError::not_found("not found"))?;
    let recipient_id: String = row.try_get("recipient_id").unwrap_or_default();

    let actor = require_device_actor(&state, &headers, &state.pool).await?;
    if let Some(a) = &actor {
        if a != &recipient_id {
            return Err(ApiError::forbidden("not recipient"));
        }
    }
    if let Some(claimed) = body
        .device_id
        .as_deref()
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
    {
        if claimed != recipient_id {
            return Err(ApiError::forbidden("not recipient"));
        }
    }

    let read_at = now_iso();
    sqlx::query(&format!("UPDATE {messages} SET read_at=$1 WHERE id=$2"))
        .bind(&read_at)
        .bind(&mid)
        .execute(&state.pool)
        .await
        .map_err(|_| ApiError::internal("database error"))?;

    Ok(axum::Json(
        json!({"ok": true, "id": mid, "read_at": read_at}),
    ))
}

pub async fn register_push_token(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(device_id): Path<String>,
    axum::Json(body): axum::Json<PushTokenReq>,
) -> ApiResult<axum::Json<serde_json::Value>> {
    let device_id = device_id.trim().to_string();
    if !is_valid_device_id(&device_id) {
        return Err(ApiError::not_found("not found"));
    }
    enforce_device_actor(&state, &headers, &state.pool, &device_id).await?;

    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &device_id).await? {
        return Err(ApiError::not_found("unknown device"));
    }

    let tok = body.token.trim().to_string();
    if tok.len() < 8 || tok.len() > 512 {
        return Err(ApiError::bad_request("invalid token"));
    }
    let platform = body
        .platform
        .as_deref()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());
    if let Some(p) = &platform {
        if p.len() > 30 {
            return Err(ApiError::bad_request("invalid platform"));
        }
    }

    let now = now_iso();
    let push_tokens = state.table("push_tokens");
    sqlx::query(&format!(
        "INSERT INTO {push_tokens} (token, device_id, platform, created_at, last_seen_at) VALUES ($1,$2,$3,$4,$5) \
         ON CONFLICT(token) DO UPDATE SET device_id=excluded.device_id, platform=excluded.platform, last_seen_at=excluded.last_seen_at"
    ))
    .bind(&tok)
    .bind(&device_id)
    .bind(&platform)
    .bind(&now)
    .bind(&now)
    .execute(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;

    Ok(axum::Json(
        json!({"ok": true, "token": tok, "platform": platform.unwrap_or_else(|| "unknown".to_string())}),
    ))
}

pub async fn issue_mailbox(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<MailboxIssueReq>,
) -> ApiResult<axum::Json<MailboxIssueOut>> {
    ensure_mailbox_api_enabled(&state)?;

    let device_id = body.device_id.trim().to_string();
    if !is_valid_device_id(&device_id) {
        return Err(ApiError::bad_request("invalid device id"));
    }
    enforce_device_actor(&state, &headers, &state.pool, &device_id).await?;

    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &device_id).await? {
        return Err(ApiError::not_found("unknown device"));
    }

    let mailbox_token = issue_secret_token_hex(32);
    let token_hash = sha256_hex(&mailbox_token);
    let created_at = now_iso();

    let chat_mailboxes = state.table("chat_mailboxes");
    sqlx::query(&format!(
        "INSERT INTO {chat_mailboxes} (token_hash,owner_device_id,created_at,active) VALUES ($1,$2,$3,1) \
         ON CONFLICT(token_hash) DO NOTHING"
    ))
    .bind(&token_hash)
    .bind(&device_id)
    .bind(&created_at)
    .execute(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;

    Ok(axum::Json(MailboxIssueOut {
        mailbox_token,
        created_at,
    }))
}

pub async fn write_mailbox(
    State(state): State<AppState>,
    axum::Json(body): axum::Json<MailboxWriteReq>,
) -> ApiResult<axum::Json<MailboxWriteOut>> {
    ensure_mailbox_api_enabled(&state)?;

    let mailbox_token = normalize_mailbox_token(&body.mailbox_token)?;
    let token_hash = sha256_hex(&mailbox_token);
    let envelope_b64 = normalize_key_material(&body.envelope_b64, "envelope_b64", 16, 131072)?;
    let sender_hint = body
        .sender_hint
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string);
    if sender_hint.as_ref().is_some_and(|v| v.len() > 64) {
        return Err(ApiError::bad_request("invalid sender_hint"));
    }

    let chat_mailboxes = state.table("chat_mailboxes");
    let mailbox_row = sqlx::query(&format!(
        "SELECT token_hash FROM {chat_mailboxes} WHERE token_hash=$1 AND active=1 LIMIT 1"
    ))
    .bind(&token_hash)
    .fetch_optional(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;
    if mailbox_row.is_none() {
        return Err(ApiError::not_found("unknown mailbox"));
    }

    let created_at = now_iso();
    let expire_at = body.expire_after_seconds.map(|secs| {
        let ttl = secs.clamp(60, 7 * 24 * 3600);
        (Utc::now() + Duration::seconds(ttl)).to_rfc3339_opts(SecondsFormat::Secs, true)
    });
    let id = Uuid::new_v4().to_string();

    let chat_mailbox_messages = state.table("chat_mailbox_messages");
    sqlx::query(&format!(
        "INSERT INTO {chat_mailbox_messages} (id,token_hash,envelope_b64,sender_hint,created_at,expire_at,consumed_at) \
         VALUES ($1,$2,$3,$4,$5,$6,NULL)"
    ))
    .bind(&id)
    .bind(&token_hash)
    .bind(&envelope_b64)
    .bind(&sender_hint)
    .bind(&created_at)
    .bind(&expire_at)
    .execute(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;

    Ok(axum::Json(MailboxWriteOut {
        id,
        accepted: true,
        expire_at,
    }))
}

pub async fn poll_mailbox(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<MailboxPollReq>,
) -> ApiResult<axum::Json<Vec<MailboxMsgOut>>> {
    ensure_mailbox_api_enabled(&state)?;

    let device_id = body.device_id.trim().to_string();
    if !is_valid_device_id(&device_id) {
        return Err(ApiError::bad_request("invalid device id"));
    }
    enforce_device_actor(&state, &headers, &state.pool, &device_id).await?;
    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &device_id).await? {
        return Err(ApiError::not_found("unknown device"));
    }

    let mailbox_token = normalize_mailbox_token(&body.mailbox_token)?;
    let token_hash = sha256_hex(&mailbox_token);
    let chat_mailboxes = state.table("chat_mailboxes");
    let owner_row = sqlx::query(&format!(
        "SELECT 1 as one FROM {chat_mailboxes} WHERE token_hash=$1 AND owner_device_id=$2 AND active=1 LIMIT 1"
    ))
    .bind(&token_hash)
    .bind(&device_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;
    if owner_row.is_none() {
        return Err(ApiError::not_found("unknown mailbox"));
    }

    let limit = body.limit.unwrap_or(50).clamp(1, 200);
    let now = now_iso();
    let chat_mailbox_messages = state.table("chat_mailbox_messages");
    let rows = sqlx::query(&format!(
        "SELECT id,envelope_b64,sender_hint,created_at,expire_at FROM {chat_mailbox_messages} \
         WHERE token_hash=$1 \
           AND (consumed_at IS NULL OR TRIM(consumed_at)='') \
           AND (expire_at IS NULL OR TRIM(expire_at)='' OR expire_at >= $2) \
         ORDER BY created_at ASC LIMIT {limit}"
    ))
    .bind(&token_hash)
    .bind(&now)
    .fetch_all(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;

    let mut out = Vec::with_capacity(rows.len());
    let mut delivered = Vec::with_capacity(rows.len());
    for r in rows {
        let id: String = r.try_get("id").unwrap_or_default();
        if id.is_empty() {
            continue;
        }
        delivered.push(id.clone());
        out.push(MailboxMsgOut {
            id,
            envelope_b64: r.try_get("envelope_b64").unwrap_or_default(),
            sender_hint: r.try_get("sender_hint").ok(),
            created_at: r.try_get("created_at").unwrap_or_default(),
            expire_at: r.try_get("expire_at").ok(),
        });
    }
    if !delivered.is_empty() {
        let consumed_at = now_iso();
        for id in delivered {
            let _ = sqlx::query(&format!(
                "UPDATE {chat_mailbox_messages} SET consumed_at=$1 WHERE id=$2 AND (consumed_at IS NULL OR TRIM(consumed_at)='')"
            ))
            .bind(&consumed_at)
            .bind(&id)
            .execute(&state.pool)
            .await;
        }
    }

    Ok(axum::Json(out))
}

pub async fn rotate_mailbox(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<MailboxRotateReq>,
) -> ApiResult<axum::Json<MailboxRotateOut>> {
    ensure_mailbox_api_enabled(&state)?;

    let device_id = body.device_id.trim().to_string();
    if !is_valid_device_id(&device_id) {
        return Err(ApiError::bad_request("invalid device id"));
    }
    enforce_device_actor(&state, &headers, &state.pool, &device_id).await?;
    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &device_id).await? {
        return Err(ApiError::not_found("unknown device"));
    }

    let old_token = normalize_mailbox_token(&body.mailbox_token)?;
    let old_hash = sha256_hex(&old_token);

    let chat_mailboxes = state.table("chat_mailboxes");
    let owner_row = sqlx::query(&format!(
        "SELECT 1 as one FROM {chat_mailboxes} WHERE token_hash=$1 AND owner_device_id=$2 AND active=1 LIMIT 1"
    ))
    .bind(&old_hash)
    .bind(&device_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;
    if owner_row.is_none() {
        return Err(ApiError::not_found("unknown mailbox"));
    }

    let mailbox_token = issue_secret_token_hex(32);
    let new_hash = sha256_hex(&mailbox_token);
    let created_at = now_iso();

    let mut tx = state
        .pool
        .begin()
        .await
        .map_err(|_| ApiError::internal("database error"))?;

    let update = sqlx::query(&format!(
        "UPDATE {chat_mailboxes} SET active=0, rotated_at=$1 WHERE token_hash=$2 AND owner_device_id=$3 AND active=1"
    ))
    .bind(&created_at)
    .bind(&old_hash)
    .bind(&device_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| ApiError::internal("database error"))?;
    if update.rows_affected() == 0 {
        return Err(ApiError::conflict("mailbox rotate conflict"));
    }

    sqlx::query(&format!(
        "INSERT INTO {chat_mailboxes} (token_hash,owner_device_id,created_at,active) VALUES ($1,$2,$3,1)"
    ))
    .bind(&new_hash)
    .bind(&device_id)
    .bind(&created_at)
    .execute(&mut *tx)
    .await
    .map_err(|_| ApiError::internal("database error"))?;

    tx.commit()
        .await
        .map_err(|_| ApiError::internal("database error"))?;

    Ok(axum::Json(MailboxRotateOut {
        mailbox_token,
        created_at,
    }))
}

pub async fn set_block(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(device_id): Path<String>,
    axum::Json(body): axum::Json<ContactRuleReq>,
) -> ApiResult<axum::Json<serde_json::Value>> {
    let device_id = device_id.trim().to_string();
    if !is_valid_device_id(&device_id) {
        return Err(ApiError::not_found("not found"));
    }
    enforce_device_actor(&state, &headers, &state.pool, &device_id).await?;

    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &device_id).await? {
        return Err(ApiError::not_found("unknown device"));
    }
    let peer_id = body.peer_id.trim().to_string();
    if peer_id.is_empty() || !is_valid_device_id(&peer_id) {
        return Err(ApiError::bad_request("invalid peer_id"));
    }
    if peer_id == device_id {
        return Err(ApiError::bad_request("cannot block self"));
    }

    let blocked = body.blocked.unwrap_or(false);
    let hidden = body.hidden.unwrap_or(false);
    let now = now_iso();
    let contact_rules = state.table("contact_rules");
    sqlx::query(&format!(
        "INSERT INTO {contact_rules} (device_id,peer_id,blocked,hidden,created_at,updated_at) VALUES ($1,$2,$3,$4,$5,$6) \
         ON CONFLICT(device_id,peer_id) DO UPDATE SET blocked=excluded.blocked, hidden=excluded.hidden, updated_at=excluded.updated_at"
    ))
    .bind(&device_id)
    .bind(&peer_id)
    .bind(if blocked { 1_i64 } else { 0_i64 })
    .bind(if hidden { 1_i64 } else { 0_i64 })
    .bind(&now)
    .bind(&now)
    .execute(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;

    Ok(axum::Json(
        json!({"ok": true, "peer_id": peer_id, "blocked": blocked, "hidden": hidden}),
    ))
}

pub async fn set_prefs(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(device_id): Path<String>,
    axum::Json(body): axum::Json<ContactPrefsReq>,
) -> ApiResult<axum::Json<serde_json::Value>> {
    let device_id = device_id.trim().to_string();
    if !is_valid_device_id(&device_id) {
        return Err(ApiError::not_found("not found"));
    }
    enforce_device_actor(&state, &headers, &state.pool, &device_id).await?;

    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &device_id).await? {
        return Err(ApiError::not_found("unknown device"));
    }
    let peer_id = body.peer_id.trim().to_string();
    if peer_id.is_empty() || !is_valid_device_id(&peer_id) {
        return Err(ApiError::bad_request("invalid peer_id"));
    }
    if peer_id == device_id {
        return Err(ApiError::bad_request("cannot set prefs for self"));
    }

    let contact_rules = state.table("contact_rules");
    let row = sqlx::query(&format!(
        "SELECT blocked,hidden,muted,starred,pinned FROM {contact_rules} WHERE device_id=$1 AND peer_id=$2"
    ))
    .bind(&device_id)
    .bind(&peer_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;

    let mut blocked = 0_i64;
    let mut hidden = 0_i64;
    let mut muted = 0_i64;
    let mut starred = 0_i64;
    let mut pinned = 0_i64;
    if let Some(r) = row {
        blocked = r.try_get("blocked").unwrap_or(0);
        hidden = r.try_get("hidden").unwrap_or(0);
        muted = r.try_get("muted").unwrap_or(0);
        starred = r.try_get("starred").unwrap_or(0);
        pinned = r.try_get("pinned").unwrap_or(0);
    }
    if let Some(v) = body.muted {
        muted = if v { 1 } else { 0 };
    }
    if let Some(v) = body.starred {
        starred = if v { 1 } else { 0 };
    }
    if let Some(v) = body.pinned {
        pinned = if v { 1 } else { 0 };
    }

    let now = now_iso();
    sqlx::query(&format!(
        "INSERT INTO {contact_rules} (device_id,peer_id,blocked,hidden,muted,starred,pinned,created_at,updated_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) \
         ON CONFLICT(device_id,peer_id) DO UPDATE SET muted=excluded.muted, starred=excluded.starred, pinned=excluded.pinned, updated_at=excluded.updated_at"
    ))
    .bind(&device_id)
    .bind(&peer_id)
    .bind(blocked)
    .bind(hidden)
    .bind(muted)
    .bind(starred)
    .bind(pinned)
    .bind(&now)
    .bind(&now)
    .execute(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;

    Ok(axum::Json(
        json!({"ok": true, "peer_id": peer_id, "muted": muted == 1, "starred": starred == 1, "pinned": pinned == 1}),
    ))
}

pub async fn list_prefs(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(device_id): Path<String>,
) -> ApiResult<axum::Json<serde_json::Value>> {
    let device_id = device_id.trim().to_string();
    if !is_valid_device_id(&device_id) {
        return Err(ApiError::not_found("not found"));
    }
    enforce_device_actor(&state, &headers, &state.pool, &device_id).await?;

    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &device_id).await? {
        return Err(ApiError::not_found("unknown device"));
    }

    let contact_rules = state.table("contact_rules");
    let rows = sqlx::query(&format!(
        "SELECT peer_id,blocked,hidden,muted,starred,pinned FROM {contact_rules} WHERE device_id=$1"
    ))
    .bind(&device_id)
    .fetch_all(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;

    let mut prefs: Vec<serde_json::Value> = Vec::with_capacity(rows.len());
    for r in rows {
        prefs.push(json!({
            "peer_id": r.try_get::<String,_>("peer_id").unwrap_or_default(),
            "blocked": r.try_get::<i64,_>("blocked").unwrap_or(0) != 0,
            "hidden": r.try_get::<i64,_>("hidden").unwrap_or(0) != 0,
            "muted": r.try_get::<i64,_>("muted").unwrap_or(0) != 0,
            "starred": r.try_get::<i64,_>("starred").unwrap_or(0) != 0,
            "pinned": r.try_get::<i64,_>("pinned").unwrap_or(0) != 0,
        }));
    }
    Ok(axum::Json(json!({"prefs": prefs})))
}

pub async fn set_group_prefs(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(device_id): Path<String>,
    axum::Json(body): axum::Json<GroupPrefsReq>,
) -> ApiResult<axum::Json<serde_json::Value>> {
    let device_id = device_id.trim().to_string();
    if !is_valid_device_id(&device_id) {
        return Err(ApiError::not_found("not found"));
    }
    enforce_device_actor(&state, &headers, &state.pool, &device_id).await?;

    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &device_id).await? {
        return Err(ApiError::not_found("unknown device"));
    }

    let gid = body.group_id.trim().to_string();
    if gid.is_empty() || !is_valid_group_id(&gid) {
        return Err(ApiError::bad_request("invalid group id"));
    }
    let groups = state.table("groups");
    let group_row = sqlx::query(&format!("SELECT 1 as one FROM {groups} WHERE id=$1"))
        .bind(&gid)
        .fetch_optional(&state.pool)
        .await
        .map_err(|_| ApiError::internal("database error"))?;
    if group_row.is_none() {
        return Err(ApiError::not_found("unknown group"));
    }
    if !is_group_member(&state, &gid, &device_id).await {
        return Err(ApiError::forbidden("not a member"));
    }

    let group_prefs = state.table("group_prefs");
    let row = sqlx::query(&format!(
        "SELECT muted,pinned FROM {group_prefs} WHERE device_id=$1 AND group_id=$2"
    ))
    .bind(&device_id)
    .bind(&gid)
    .fetch_optional(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;

    let mut muted = row
        .as_ref()
        .and_then(|r| r.try_get::<i64, _>("muted").ok())
        .unwrap_or(0);
    let mut pinned = row
        .as_ref()
        .and_then(|r| r.try_get::<i64, _>("pinned").ok())
        .unwrap_or(0);
    if let Some(v) = body.muted {
        muted = if v { 1 } else { 0 };
    }
    if let Some(v) = body.pinned {
        pinned = if v { 1 } else { 0 };
    }

    let now = now_iso();
    sqlx::query(&format!(
        "INSERT INTO {group_prefs} (device_id,group_id,muted,pinned,created_at,updated_at) VALUES ($1,$2,$3,$4,$5,$6) \
         ON CONFLICT(device_id,group_id) DO UPDATE SET muted=excluded.muted, pinned=excluded.pinned, updated_at=excluded.updated_at"
    ))
    .bind(&device_id)
    .bind(&gid)
    .bind(muted)
    .bind(pinned)
    .bind(&now)
    .bind(&now)
    .execute(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;

    Ok(axum::Json(
        json!({"ok": true, "group_id": gid, "muted": muted == 1, "pinned": pinned == 1}),
    ))
}

pub async fn list_group_prefs(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(device_id): Path<String>,
) -> ApiResult<axum::Json<Vec<GroupPrefsOut>>> {
    let device_id = device_id.trim().to_string();
    if !is_valid_device_id(&device_id) {
        return Err(ApiError::not_found("not found"));
    }
    enforce_device_actor(&state, &headers, &state.pool, &device_id).await?;

    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &device_id).await? {
        return Err(ApiError::not_found("unknown device"));
    }

    let group_prefs = state.table("group_prefs");
    let rows = sqlx::query(&format!(
        "SELECT group_id,muted,pinned FROM {group_prefs} WHERE device_id=$1"
    ))
    .bind(&device_id)
    .fetch_all(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;
    let mut out: Vec<GroupPrefsOut> = Vec::with_capacity(rows.len());
    for r in rows {
        out.push(GroupPrefsOut {
            group_id: r.try_get("group_id").unwrap_or_default(),
            muted: r.try_get::<i64, _>("muted").unwrap_or(0) != 0,
            pinned: r.try_get::<i64, _>("pinned").unwrap_or(0) != 0,
        });
    }
    Ok(axum::Json(out))
}

pub async fn list_hidden(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(device_id): Path<String>,
) -> ApiResult<axum::Json<serde_json::Value>> {
    let device_id = device_id.trim().to_string();
    if !is_valid_device_id(&device_id) {
        return Err(ApiError::not_found("not found"));
    }
    enforce_device_actor(&state, &headers, &state.pool, &device_id).await?;

    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &device_id).await? {
        return Err(ApiError::not_found("unknown device"));
    }
    let contact_rules = state.table("contact_rules");
    let rows = sqlx::query(&format!(
        "SELECT peer_id FROM {contact_rules} WHERE device_id=$1 AND hidden=1"
    ))
    .bind(&device_id)
    .fetch_all(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;
    let mut hidden = Vec::with_capacity(rows.len());
    for r in rows {
        hidden.push(r.try_get::<String, _>("peer_id").unwrap_or_default());
    }
    Ok(axum::Json(json!({"hidden": hidden})))
}

pub async fn create_group(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<GroupCreateReq>,
) -> ApiResult<axum::Json<GroupOut>> {
    let owner_id = body.device_id.trim().to_string();
    if !is_valid_device_id(&owner_id) {
        return Err(ApiError::bad_request("invalid device id"));
    }
    enforce_device_actor(&state, &headers, &state.pool, &owner_id).await?;

    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &owner_id).await? {
        return Err(ApiError::not_found("unknown device"));
    }

    let mut gid = body
        .group_id
        .as_deref()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| format!("grp_{}", &Uuid::new_v4().simple().to_string()[..10]));
    gid = gid.trim().to_string();
    if gid.is_empty() || !is_valid_group_id(&gid) {
        return Err(ApiError::bad_request("invalid group id"));
    }

    let groups = state.table("groups");
    let exists = sqlx::query(&format!("SELECT 1 as one FROM {groups} WHERE id=$1"))
        .bind(&gid)
        .fetch_optional(&state.pool)
        .await
        .map_err(|_| ApiError::internal("database error"))?;
    if exists.is_some() {
        return Err(ApiError::conflict("group exists"));
    }

    let name = body.name.trim();
    if name.is_empty() || name.len() > 120 {
        return Err(ApiError::bad_request("invalid name"));
    }

    let created_at = now_iso();
    let group_members = state.table("group_members");

    let mut tx = state
        .pool
        .begin()
        .await
        .map_err(|_| ApiError::internal("database error"))?;

    sqlx::query(&format!(
        "INSERT INTO {groups} (id,name,creator_id,key_version,created_at) VALUES ($1,$2,$3,$4,$5)"
    ))
    .bind(&gid)
    .bind(name)
    .bind(&owner_id)
    .bind(0_i64)
    .bind(&created_at)
    .execute(&mut *tx)
    .await
    .map_err(|_| ApiError::internal("database error"))?;

    let mut members: Vec<String> = Vec::new();
    members.push(owner_id.clone());
    if let Some(extra) = body.member_ids.as_ref() {
        if extra.len() > 200 {
            return Err(ApiError::bad_request("invalid member_ids"));
        }
        for m in extra {
            members.push(m.trim().to_string());
        }
    }
    let mut seen: HashSet<String> = HashSet::new();
    for mid in members {
        let mid = mid.trim().to_string();
        if mid.is_empty() || seen.contains(&mid) || !is_valid_device_id(&mid) {
            continue;
        }
        seen.insert(mid.clone());
        if !device_exists(&state.pool, &devices, &mid).await? {
            continue;
        }
        let role = if mid == owner_id { "admin" } else { "member" };
        let _ = sqlx::query(&format!(
            "INSERT INTO {group_members} (group_id,device_id,role,joined_at) VALUES ($1,$2,$3,$4)"
        ))
        .bind(&gid)
        .bind(&mid)
        .bind(role)
        .bind(&created_at)
        .execute(&mut *tx)
        .await;
    }

    tx.commit()
        .await
        .map_err(|_| ApiError::internal("database error"))?;

    let count_row = sqlx::query(&format!(
        "SELECT COUNT(*) as c FROM {group_members} WHERE group_id=$1"
    ))
    .bind(&gid)
    .fetch_one(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;
    let member_count: i64 = count_row.try_get("c").unwrap_or(0);

    // Push notify group.
    let push_state = state.clone();
    let gid_clone = gid.clone();
    let push_owner_id = owner_id.clone();
    tokio::spawn(async move { notify_group(push_state, gid_clone, push_owner_id).await });

    Ok(axum::Json(GroupOut {
        group_id: gid,
        name: name.to_string(),
        creator_id: owner_id,
        created_at: Some(created_at),
        member_count,
        key_version: 0,
        avatar_b64: None,
        avatar_mime: None,
    }))
}

pub async fn list_groups(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(params): Query<ListGroupsParams>,
) -> ApiResult<axum::Json<Vec<GroupOut>>> {
    let did = params.device_id.trim().to_string();
    if !is_valid_device_id(&did) {
        return Err(ApiError::not_found("not found"));
    }
    enforce_device_actor(&state, &headers, &state.pool, &did).await?;
    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &did).await? {
        return Err(ApiError::not_found("unknown device"));
    }

    let group_members = state.table("group_members");
    let rows = sqlx::query(&format!(
        "SELECT group_id FROM {group_members} WHERE device_id=$1"
    ))
    .bind(&did)
    .fetch_all(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;
    let mut gids: Vec<String> = Vec::with_capacity(rows.len());
    for r in rows {
        gids.push(r.try_get::<String, _>("group_id").unwrap_or_default());
    }
    if gids.is_empty() {
        return Ok(axum::Json(vec![]));
    }

    // NOTE: SQLx Any doesn't provide array binding portably; do N small queries instead.
    let groups = state.table("groups");
    let mut out: Vec<GroupOut> = Vec::new();
    for gid in gids {
        let row = sqlx::query(&format!(
            "SELECT id,name,creator_id,created_at,key_version,avatar_b64,avatar_mime FROM {groups} WHERE id=$1"
        ))
        .bind(&gid)
        .fetch_optional(&state.pool)
        .await
        .ok()
        .flatten();
        let Some(r) = row else {
            continue;
        };
        let count_row = sqlx::query(&format!(
            "SELECT COUNT(*) as c FROM {group_members} WHERE group_id=$1"
        ))
        .bind(&gid)
        .fetch_one(&state.pool)
        .await
        .map_err(|_| ApiError::internal("database error"))?;
        let member_count: i64 = count_row.try_get("c").unwrap_or(0);
        out.push(GroupOut {
            group_id: r.try_get("id").unwrap_or_default(),
            name: r.try_get("name").unwrap_or_default(),
            creator_id: r.try_get("creator_id").unwrap_or_default(),
            created_at: r.try_get("created_at").ok(),
            member_count,
            key_version: r.try_get("key_version").unwrap_or(0),
            avatar_b64: r.try_get("avatar_b64").ok(),
            avatar_mime: r.try_get("avatar_mime").ok(),
        });
    }
    // Python orders by created_at desc; approximate by sorting on created_at string.
    out.sort_by(|a, b| b.created_at.cmp(&a.created_at));
    Ok(axum::Json(out))
}

pub async fn update_group(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(group_id): Path<String>,
    axum::Json(body): axum::Json<GroupUpdateReq>,
) -> ApiResult<axum::Json<GroupOut>> {
    let group_id = group_id.trim().to_string();
    if !is_valid_group_id(&group_id) {
        return Err(ApiError::not_found("not found"));
    }
    let actor = body.actor_id.trim().to_string();
    if !is_valid_device_id(&actor) {
        return Err(ApiError::bad_request("invalid device id"));
    }
    enforce_device_actor(&state, &headers, &state.pool, &actor).await?;
    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &actor).await? {
        return Err(ApiError::not_found("unknown device"));
    }
    let groups = state.table("groups");
    let row = sqlx::query(&format!(
        "SELECT id,name,creator_id,created_at,key_version,avatar_b64,avatar_mime FROM {groups} WHERE id=$1"
    ))
    .bind(&group_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?
    .ok_or_else(|| ApiError::not_found("unknown group"))?;

    if !is_group_admin(&state, &group_id, &actor).await {
        return Err(ApiError::forbidden("admin required"));
    }

    let mut name: String = row.try_get("name").unwrap_or_default();
    let mut avatar_b64: Option<String> = row.try_get("avatar_b64").ok();
    let mut avatar_mime: Option<String> = row.try_get("avatar_mime").ok();
    let creator_id: String = row.try_get("creator_id").unwrap_or_default();
    let created_at: Option<String> = row.try_get("created_at").ok();
    let key_version: i64 = row.try_get("key_version").unwrap_or(0);

    let mut changed = false;

    if let Some(new_name) = body.name.as_deref() {
        let new_name = new_name.trim();
        if !new_name.is_empty() && new_name.len() <= 120 && new_name != name {
            name = new_name.to_string();
            changed = true;
        }
    }

    if body.avatar_b64.is_some() {
        let new_b64 = body
            .avatar_b64
            .as_deref()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty());
        let new_mime = body
            .avatar_mime
            .as_deref()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty());
        if new_b64 != avatar_b64 || (new_b64.is_some() && new_mime != avatar_mime) {
            avatar_b64 = new_b64;
            avatar_mime = new_mime;
            changed = true;
        }
    }

    if changed {
        let mut tx = state
            .pool
            .begin()
            .await
            .map_err(|_| ApiError::internal("database error"))?;
        let _ = sqlx::query(&format!(
            "UPDATE {groups} SET name=$1, avatar_b64=$2, avatar_mime=$3 WHERE id=$4"
        ))
        .bind(&name)
        .bind(&avatar_b64)
        .bind(&avatar_mime)
        .bind(&group_id)
        .execute(&mut *tx)
        .await;
        tx.commit()
            .await
            .map_err(|_| ApiError::internal("database error"))?;
        // Best-effort push: wake clients so they refresh group state.
        let push_state = state.clone();
        let gid = group_id.clone();
        let actor_id = actor.clone();
        tokio::spawn(async move { notify_group(push_state, gid, actor_id).await });
    }

    let group_members = state.table("group_members");
    let count_row = sqlx::query(&format!(
        "SELECT COUNT(*) as c FROM {group_members} WHERE group_id=$1"
    ))
    .bind(&group_id)
    .fetch_one(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;
    let member_count: i64 = count_row.try_get("c").unwrap_or(0);

    Ok(axum::Json(GroupOut {
        group_id,
        name,
        creator_id,
        created_at,
        member_count,
        key_version,
        avatar_b64,
        avatar_mime,
    }))
}

pub async fn send_group_message(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(group_id): Path<String>,
    axum::Json(body): axum::Json<GroupSendReq>,
) -> ApiResult<axum::Json<GroupMsgOut>> {
    let group_id = group_id.trim().to_string();
    if !is_valid_group_id(&group_id) {
        return Err(ApiError::not_found("not found"));
    }
    let sender_id = body.sender_id.trim().to_string();
    if !is_valid_device_id(&sender_id) {
        return Err(ApiError::bad_request("invalid sender_id"));
    }
    let protocol_version = parse_protocol_version(body.protocol_version.as_deref())?;
    validate_protocol_write(
        state.chat_protocol_v2_enabled,
        state.chat_protocol_v1_write_enabled,
        state.chat_protocol_require_v2_for_groups,
        protocol_version,
        true,
    )?;
    enforce_device_actor(&state, &headers, &state.pool, &sender_id).await?;
    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &sender_id).await? {
        return Err(ApiError::not_found("unknown device"));
    }
    let groups = state.table("groups");
    let g_row = sqlx::query(&format!("SELECT 1 as one FROM {groups} WHERE id=$1"))
        .bind(&group_id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|_| ApiError::internal("database error"))?;
    if g_row.is_none() {
        return Err(ApiError::not_found("unknown group"));
    }
    if !is_group_member(&state, &group_id, &sender_id).await {
        return Err(ApiError::forbidden("not a member"));
    }
    enforce_no_protocol_downgrade_group(&state, &group_id, &sender_id, protocol_version).await?;

    let (nonce_b64, box_b64) = parse_required_group_ciphertext(&body)?;
    let nonce_val = Some(nonce_b64);
    let box_val = Some(box_b64);
    let kind = Some("sealed".to_string());
    let text_val = String::new();
    let att_b64: Option<String> = None;
    let att_mime: Option<String> = None;
    let voice_secs: Option<i64> = None;

    let expire_at = match body.expire_after_seconds {
        Some(secs) if secs > 0 => {
            if !(10..=7 * 24 * 3600).contains(&secs) {
                return Err(ApiError::bad_request("invalid expire_after_seconds"));
            }
            Some((Utc::now() + Duration::seconds(secs)).to_rfc3339_opts(SecondsFormat::Secs, true))
        }
        _ => None,
    };

    let mid = Uuid::new_v4().to_string();
    let created_at = now_iso();
    let group_messages = state.table("group_messages");
    sqlx::query(&format!(
        "INSERT INTO {group_messages} (id,group_id,sender_id,protocol_version,text,kind,nonce_b64,box_b64,attachment_b64,attachment_mime,voice_secs,created_at,expire_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)"
    ))
    .bind(&mid)
    .bind(&group_id)
    .bind(&sender_id)
    .bind(protocol_version.as_str())
    .bind(text_val.chars().take(4096).collect::<String>())
    .bind(&kind)
    .bind(&nonce_val)
    .bind(&box_val)
    .bind(&att_b64)
    .bind(&att_mime)
    .bind(voice_secs)
    .bind(&created_at)
    .bind(&expire_at)
    .execute(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;

    let push_state = state.clone();
    let gid = group_id.clone();
    let push_sender_id = sender_id.clone();
    tokio::spawn(async move { notify_group(push_state, gid, push_sender_id).await });

    Ok(axum::Json(GroupMsgOut {
        id: mid,
        group_id,
        sender_id,
        protocol_version: protocol_version.as_str().to_string(),
        text: text_val,
        kind,
        nonce_b64: nonce_val,
        box_b64: box_val,
        attachment_b64: att_b64,
        attachment_mime: att_mime,
        voice_secs,
        created_at: Some(created_at),
        expire_at,
    }))
}

fn parse_required_group_ciphertext(body: &GroupSendReq) -> Result<(String, String), ApiError> {
    let nonce_val = body
        .nonce_b64
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let box_val = body
        .box_b64
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());

    match (nonce_val, box_val) {
        (Some(nonce), Some(ciphertext)) => {
            let nonce = normalize_key_material(nonce, "nonce_b64", 16, 64)?;
            // Group message ciphertext can be larger (attachments inside sealed payload).
            // Still cap it to a sane bound to reduce DoS surface.
            let box_b64 = normalize_key_material(ciphertext, "box_b64", 16, 1_000_000)?;
            Ok((nonce, box_b64))
        }
        (None, Some(_)) => Err(ApiError::bad_request("missing nonce")),
        (Some(_), None) => Err(ApiError::bad_request("missing box")),
        (None, None) => Err(ApiError::bad_request("group message encryption required")),
    }
}

fn parse_required_direct_ciphertext(
    nonce_b64: &str,
    box_b64: &str,
) -> Result<(String, String), ApiError> {
    let nonce = nonce_b64.trim();
    let ciphertext = box_b64.trim();
    if nonce.is_empty() && ciphertext.is_empty() {
        return Err(ApiError::bad_request("message encryption required"));
    }
    if nonce.is_empty() {
        return Err(ApiError::bad_request("missing nonce"));
    }
    if ciphertext.is_empty() {
        return Err(ApiError::bad_request("missing box"));
    }
    let nonce = normalize_key_material(nonce, "nonce_b64", 16, 64)?;
    let box_b64 = normalize_key_material(ciphertext, "box_b64", 16, 8192)?;
    Ok((nonce, box_b64))
}

pub async fn group_inbox(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(group_id): Path<String>,
    Query(params): Query<GroupInboxParams>,
) -> ApiResult<axum::Json<Vec<GroupMsgOut>>> {
    let group_id = group_id.trim().to_string();
    if !is_valid_group_id(&group_id) {
        return Err(ApiError::not_found("not found"));
    }
    let did = params.device_id.trim().to_string();
    if !is_valid_device_id(&did) {
        return Err(ApiError::not_found("not found"));
    }
    enforce_device_actor(&state, &headers, &state.pool, &did).await?;
    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &did).await? {
        return Err(ApiError::not_found("unknown device"));
    }
    let groups = state.table("groups");
    let g_row = sqlx::query(&format!("SELECT 1 as one FROM {groups} WHERE id=$1"))
        .bind(&group_id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|_| ApiError::internal("database error"))?;
    if g_row.is_none() {
        return Err(ApiError::not_found("unknown group"));
    }
    if !is_group_member(&state, &group_id, &did).await {
        return Err(ApiError::forbidden("not a member"));
    }
    let device_v2_only = is_device_v2_only(&state, &did).await?;

    purge_expired(&state).await?;

    let limit = params.limit.unwrap_or(50).clamp(1, 200);
    let group_messages = state.table("group_messages");
    let mut sql = format!(
        "SELECT id,group_id,sender_id,protocol_version,text,kind,nonce_b64,box_b64,attachment_b64,attachment_mime,voice_secs,created_at,expire_at FROM {group_messages} WHERE group_id=$1 AND kind='sealed'"
    );
    if !state.chat_protocol_v1_read_enabled || device_v2_only {
        sql.push_str(&format!(
            " AND COALESCE(protocol_version,'{PROTOCOL_V1_LEGACY}') <> '{PROTOCOL_V1_LEGACY}'"
        ));
    }
    let mut binds: Vec<String> = Vec::new();
    if let Some(since) = params.since_iso.as_deref() {
        let since = canonical_iso(since)?;
        sql.push_str(" AND created_at >= $2");
        binds.push(since);
        sql.push_str(" AND (expire_at IS NULL OR expire_at >= $3)");
    } else {
        sql.push_str(" AND (expire_at IS NULL OR expire_at >= $2)");
    }
    sql.push_str(&format!(" ORDER BY created_at ASC LIMIT {limit}"));

    let now = now_iso();
    let mut q = sqlx::query(&sql).bind(&group_id);
    if binds.len() == 1 {
        q = q.bind(&binds[0]).bind(&now);
    } else {
        q = q.bind(&now);
    }

    let rows = q
        .fetch_all(&state.pool)
        .await
        .map_err(|_| ApiError::internal("database error"))?;

    let mut out: Vec<GroupMsgOut> = Vec::with_capacity(rows.len());
    for r in rows {
        let protocol_version = parse_row_protocol_version(
            r.try_get::<Option<String>, _>("protocol_version")
                .ok()
                .flatten()
                .as_deref(),
        );
        out.push(GroupMsgOut {
            id: r.try_get("id").unwrap_or_default(),
            group_id: r.try_get("group_id").unwrap_or_default(),
            sender_id: r.try_get("sender_id").unwrap_or_default(),
            protocol_version: protocol_version.as_str().to_string(),
            text: r.try_get("text").unwrap_or_default(),
            kind: r.try_get("kind").ok(),
            nonce_b64: r.try_get("nonce_b64").ok(),
            box_b64: r.try_get("box_b64").ok(),
            attachment_b64: r.try_get("attachment_b64").ok(),
            attachment_mime: r.try_get("attachment_mime").ok(),
            voice_secs: r.try_get("voice_secs").ok(),
            created_at: r.try_get("created_at").ok(),
            expire_at: r.try_get("expire_at").ok(),
        });
    }
    Ok(axum::Json(out))
}

pub async fn group_members(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(group_id): Path<String>,
    Query(params): Query<GroupMembersParams>,
) -> ApiResult<axum::Json<Vec<GroupMemberOut>>> {
    let group_id = group_id.trim().to_string();
    if !is_valid_group_id(&group_id) {
        return Err(ApiError::not_found("not found"));
    }
    let did = params.device_id.trim().to_string();
    if !is_valid_device_id(&did) {
        return Err(ApiError::not_found("not found"));
    }
    enforce_device_actor(&state, &headers, &state.pool, &did).await?;
    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &did).await? {
        return Err(ApiError::not_found("unknown device"));
    }
    let groups = state.table("groups");
    let g_row = sqlx::query(&format!("SELECT 1 as one FROM {groups} WHERE id=$1"))
        .bind(&group_id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|_| ApiError::internal("database error"))?;
    if g_row.is_none() {
        return Err(ApiError::not_found("unknown group"));
    }
    if !is_group_member(&state, &group_id, &did).await {
        return Err(ApiError::forbidden("not a member"));
    }

    let group_members = state.table("group_members");
    let rows = sqlx::query(&format!(
        "SELECT device_id,role,joined_at FROM {group_members} WHERE group_id=$1 ORDER BY joined_at ASC"
    ))
    .bind(&group_id)
    .fetch_all(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;
    let mut out: Vec<GroupMemberOut> = Vec::with_capacity(rows.len());
    for r in rows {
        out.push(GroupMemberOut {
            device_id: r.try_get("device_id").unwrap_or_default(),
            role: r.try_get("role").ok(),
            joined_at: r.try_get("joined_at").ok(),
        });
    }
    Ok(axum::Json(out))
}

pub async fn invite_members(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(group_id): Path<String>,
    axum::Json(body): axum::Json<GroupInviteReq>,
) -> ApiResult<axum::Json<GroupOut>> {
    let group_id = group_id.trim().to_string();
    if !is_valid_group_id(&group_id) {
        return Err(ApiError::not_found("not found"));
    }
    let inviter_id = body.inviter_id.trim().to_string();
    if !is_valid_device_id(&inviter_id) {
        return Err(ApiError::bad_request("invalid inviter_id"));
    }
    enforce_device_actor(&state, &headers, &state.pool, &inviter_id).await?;
    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &inviter_id).await? {
        return Err(ApiError::not_found("unknown device"));
    }

    let groups = state.table("groups");
    let g_row = sqlx::query(&format!(
        "SELECT id,name,creator_id,created_at,key_version,avatar_b64,avatar_mime FROM {groups} WHERE id=$1"
    ))
    .bind(&group_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?
    .ok_or_else(|| ApiError::not_found("unknown group"))?;

    if !is_group_admin(&state, &group_id, &inviter_id).await {
        return Err(ApiError::forbidden("admin required"));
    }

    let group_members = state.table("group_members");

    let mut tx = state
        .pool
        .begin()
        .await
        .map_err(|_| ApiError::internal("database error"))?;

    let mut added_ids: Vec<String> = Vec::new();
    if body.member_ids.len() > 200 {
        return Err(ApiError::bad_request("invalid member_ids"));
    }
    for mid in body.member_ids.iter() {
        let mid = mid.trim().to_string();
        if mid.is_empty() || mid == inviter_id || !is_valid_device_id(&mid) {
            continue;
        }
        if !device_exists(&state.pool, &devices, &mid).await? {
            continue;
        }
        if is_group_member(&state, &group_id, &mid).await {
            continue;
        }
        let _ = sqlx::query(&format!(
            "INSERT INTO {group_members} (group_id,device_id,role,joined_at) VALUES ($1,$2,$3,$4)"
        ))
        .bind(&group_id)
        .bind(&mid)
        .bind("member")
        .bind(now_iso())
        .execute(&mut *tx)
        .await;
        added_ids.push(mid);
    }

    tx.commit()
        .await
        .map_err(|_| ApiError::internal("database error"))?;

    if !added_ids.is_empty() {
        let push_state = state.clone();
        let gid = group_id.clone();
        let inviter = inviter_id.clone();
        tokio::spawn(async move { notify_group(push_state, gid, inviter).await });
    }

    let count_row = sqlx::query(&format!(
        "SELECT COUNT(*) as c FROM {group_members} WHERE group_id=$1"
    ))
    .bind(&group_id)
    .fetch_one(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;
    let member_count: i64 = count_row.try_get("c").unwrap_or(0);

    Ok(axum::Json(GroupOut {
        group_id: g_row.try_get("id").unwrap_or_default(),
        name: g_row.try_get("name").unwrap_or_default(),
        creator_id: g_row.try_get("creator_id").unwrap_or_default(),
        created_at: g_row.try_get("created_at").ok(),
        member_count,
        key_version: g_row.try_get("key_version").unwrap_or(0),
        avatar_b64: g_row.try_get("avatar_b64").ok(),
        avatar_mime: g_row.try_get("avatar_mime").ok(),
    }))
}

pub async fn leave_group(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(group_id): Path<String>,
    axum::Json(body): axum::Json<GroupLeaveReq>,
) -> ApiResult<axum::Json<serde_json::Value>> {
    let group_id = group_id.trim().to_string();
    if !is_valid_group_id(&group_id) {
        return Err(ApiError::not_found("not found"));
    }
    let did = body.device_id.trim().to_string();
    if !is_valid_device_id(&did) {
        return Err(ApiError::bad_request("invalid device id"));
    }
    enforce_device_actor(&state, &headers, &state.pool, &did).await?;
    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &did).await? {
        return Err(ApiError::not_found("unknown device"));
    }
    let groups = state.table("groups");
    let g_row = sqlx::query(&format!("SELECT creator_id FROM {groups} WHERE id=$1"))
        .bind(&group_id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|_| ApiError::internal("database error"))?
        .ok_or_else(|| ApiError::not_found("unknown group"))?;
    if !is_group_member(&state, &group_id, &did).await {
        return Err(ApiError::forbidden("not a member"));
    }

    let creator_id: String = g_row.try_get("creator_id").unwrap_or_default();
    let group_members = state.table("group_members");
    let group_messages = state.table("group_messages");
    let group_key_events = state.table("group_key_events");
    let group_prefs = state.table("group_prefs");

    let mut tx = state
        .pool
        .begin()
        .await
        .map_err(|_| ApiError::internal("database error"))?;

    let _ = sqlx::query(&format!(
        "DELETE FROM {group_members} WHERE group_id=$1 AND device_id=$2"
    ))
    .bind(&group_id)
    .bind(&did)
    .execute(&mut *tx)
    .await;

    let remaining_rows = sqlx::query(&format!(
        "SELECT device_id,role FROM {group_members} WHERE group_id=$1"
    ))
    .bind(&group_id)
    .fetch_all(&mut *tx)
    .await
    .unwrap_or_default();

    if remaining_rows.is_empty() {
        let _ = sqlx::query(&format!("DELETE FROM {group_messages} WHERE group_id=$1"))
            .bind(&group_id)
            .execute(&mut *tx)
            .await;
        let _ = sqlx::query(&format!("DELETE FROM {group_key_events} WHERE group_id=$1"))
            .bind(&group_id)
            .execute(&mut *tx)
            .await;
        let _ = sqlx::query(&format!("DELETE FROM {group_prefs} WHERE group_id=$1"))
            .bind(&group_id)
            .execute(&mut *tx)
            .await;
        let _ = sqlx::query(&format!("DELETE FROM {groups} WHERE id=$1"))
            .bind(&group_id)
            .execute(&mut *tx)
            .await;
        tx.commit()
            .await
            .map_err(|_| ApiError::internal("database error"))?;
        return Ok(axum::Json(json!({"ok": true, "deleted": true})));
    }

    // Ensure at least one admin remains.
    let mut admins: Vec<String> = Vec::new();
    let mut remaining: Vec<(String, String)> = Vec::new();
    for r in &remaining_rows {
        let rid: String = r.try_get("device_id").unwrap_or_default();
        let role: String = r.try_get("role").unwrap_or_default();
        if role.eq_ignore_ascii_case("admin") {
            admins.push(rid.clone());
        }
        remaining.push((rid, role));
    }
    if admins.is_empty() {
        let first = remaining[0].0.clone();
        let _ = sqlx::query(&format!(
            "UPDATE {group_members} SET role='admin' WHERE group_id=$1 AND device_id=$2"
        ))
        .bind(&group_id)
        .bind(&first)
        .execute(&mut *tx)
        .await;
        admins.push(first);
    }

    if creator_id == did {
        let new_creator = admins[0].clone();
        let _ = sqlx::query(&format!("UPDATE {groups} SET creator_id=$1 WHERE id=$2"))
            .bind(&new_creator)
            .bind(&group_id)
            .execute(&mut *tx)
            .await;
    }

    tx.commit()
        .await
        .map_err(|_| ApiError::internal("database error"))?;

    let push_state = state.clone();
    let gid = group_id.clone();
    tokio::spawn(async move { notify_group(push_state, gid, did.clone()).await });

    Ok(axum::Json(json!({"ok": true})))
}

pub async fn set_group_role(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(group_id): Path<String>,
    axum::Json(body): axum::Json<GroupRoleReq>,
) -> ApiResult<axum::Json<serde_json::Value>> {
    let group_id = group_id.trim().to_string();
    if !is_valid_group_id(&group_id) {
        return Err(ApiError::not_found("not found"));
    }
    let actor = body.actor_id.trim().to_string();
    let target = body.target_id.trim().to_string();
    if !is_valid_device_id(&actor) {
        return Err(ApiError::bad_request("invalid actor_id"));
    }
    if !is_valid_device_id(&target) {
        return Err(ApiError::bad_request("invalid target_id"));
    }
    enforce_device_actor(&state, &headers, &state.pool, &actor).await?;

    let role = body.role.trim().to_lowercase();
    if role != "admin" && role != "member" {
        return Err(ApiError::bad_request("invalid role"));
    }
    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &actor).await?
        || !device_exists(&state.pool, &devices, &target).await?
    {
        return Err(ApiError::not_found("unknown device"));
    }
    let groups = state.table("groups");
    let g_row = sqlx::query(&format!("SELECT 1 as one FROM {groups} WHERE id=$1"))
        .bind(&group_id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|_| ApiError::internal("database error"))?;
    if g_row.is_none() {
        return Err(ApiError::not_found("unknown group"));
    }
    if !is_group_admin(&state, &group_id, &actor).await {
        return Err(ApiError::forbidden("admin required"));
    }
    let group_members = state.table("group_members");
    let row = sqlx::query(&format!(
        "SELECT role FROM {group_members} WHERE group_id=$1 AND device_id=$2"
    ))
    .bind(&group_id)
    .bind(&target)
    .fetch_optional(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?
    .ok_or_else(|| ApiError::not_found("not a member"))?;
    drop(row);
    sqlx::query(&format!(
        "UPDATE {group_members} SET role=$1 WHERE group_id=$2 AND device_id=$3"
    ))
    .bind(&role)
    .bind(&group_id)
    .bind(&target)
    .execute(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;
    let push_state = state.clone();
    let gid = group_id.clone();
    let push_actor_id = actor.clone();
    tokio::spawn(async move { notify_group(push_state, gid, push_actor_id).await });

    Ok(axum::Json(
        json!({"ok": true, "device_id": target, "role": role}),
    ))
}

pub async fn rotate_group_key(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(group_id): Path<String>,
    axum::Json(body): axum::Json<GroupKeyRotateReq>,
) -> ApiResult<axum::Json<GroupKeyEventOut>> {
    let group_id = group_id.trim().to_string();
    if !is_valid_group_id(&group_id) {
        return Err(ApiError::not_found("not found"));
    }
    let actor = body.actor_id.trim().to_string();
    if !is_valid_device_id(&actor) {
        return Err(ApiError::bad_request("invalid device id"));
    }
    enforce_device_actor(&state, &headers, &state.pool, &actor).await?;
    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &actor).await? {
        return Err(ApiError::not_found("unknown device"));
    }
    let groups = state.table("groups");
    let row = sqlx::query(&format!("SELECT key_version FROM {groups} WHERE id=$1"))
        .bind(&group_id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|_| ApiError::internal("database error"))?
        .ok_or_else(|| ApiError::not_found("unknown group"))?;
    if !is_group_admin(&state, &group_id, &actor).await {
        return Err(ApiError::forbidden("admin required"));
    }
    let cur_ver: i64 = row.try_get("key_version").unwrap_or(0);
    let next_ver = cur_ver + 1;

    let now = now_iso();
    let key_fp = body
        .key_fp
        .as_deref()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());
    let group_key_events = state.table("group_key_events");

    let mut tx = state
        .pool
        .begin()
        .await
        .map_err(|_| ApiError::internal("database error"))?;

    let _ = sqlx::query(&format!("UPDATE {groups} SET key_version=$1 WHERE id=$2"))
        .bind(next_ver)
        .bind(&group_id)
        .execute(&mut *tx)
        .await;

    let _ = sqlx::query(&format!(
        "INSERT INTO {group_key_events} (group_id,version,actor_id,key_fp,created_at) VALUES ($1,$2,$3,$4,$5) \
         ON CONFLICT(group_id,version) DO NOTHING"
    ))
    .bind(&group_id)
    .bind(next_ver)
    .bind(&actor)
    .bind(&key_fp)
    .bind(&now)
    .execute(&mut *tx)
    .await;

    tx.commit()
        .await
        .map_err(|_| ApiError::internal("database error"))?;

    let push_state = state.clone();
    let gid = group_id.clone();
    let push_actor_id = actor.clone();
    tokio::spawn(async move { notify_group(push_state, gid, push_actor_id).await });

    Ok(axum::Json(GroupKeyEventOut {
        group_id,
        version: next_ver,
        actor_id: actor,
        key_fp,
        created_at: Some(now),
    }))
}

pub async fn list_key_events(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(group_id): Path<String>,
    Query(params): Query<KeyEventsParams>,
) -> ApiResult<axum::Json<Vec<GroupKeyEventOut>>> {
    let group_id = group_id.trim().to_string();
    if !is_valid_group_id(&group_id) {
        return Err(ApiError::not_found("not found"));
    }
    let did = params.device_id.trim().to_string();
    if !is_valid_device_id(&did) {
        return Err(ApiError::not_found("not found"));
    }
    enforce_device_actor(&state, &headers, &state.pool, &did).await?;
    let devices = state.table("devices");
    if !device_exists(&state.pool, &devices, &did).await? {
        return Err(ApiError::not_found("unknown device"));
    }
    let groups = state.table("groups");
    let g_row = sqlx::query(&format!("SELECT 1 as one FROM {groups} WHERE id=$1"))
        .bind(&group_id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|_| ApiError::internal("database error"))?;
    if g_row.is_none() {
        return Err(ApiError::not_found("unknown group"));
    }
    if !is_group_admin(&state, &group_id, &did).await {
        return Err(ApiError::forbidden("admin required"));
    }
    let limit = params.limit.unwrap_or(20).clamp(1, 200);
    let group_key_events = state.table("group_key_events");
    let rows = sqlx::query(&format!(
        "SELECT group_id,version,actor_id,key_fp,created_at FROM {group_key_events} WHERE group_id=$1 ORDER BY created_at DESC LIMIT {limit}"
    ))
    .bind(&group_id)
    .fetch_all(&state.pool)
    .await
    .map_err(|_| ApiError::internal("database error"))?;
    let mut out: Vec<GroupKeyEventOut> = Vec::with_capacity(rows.len());
    for r in rows {
        out.push(GroupKeyEventOut {
            group_id: r.try_get("group_id").unwrap_or_default(),
            version: r.try_get("version").unwrap_or(0),
            actor_id: r.try_get("actor_id").unwrap_or_default(),
            key_fp: r.try_get("key_fp").ok(),
            created_at: r.try_get("created_at").ok(),
        });
    }
    Ok(axum::Json(out))
}

fn require_sealed_sender_flag(sealed_sender: Option<bool>) -> ApiResult<bool> {
    let sealed_sender = sealed_sender.unwrap_or(false);
    if !sealed_sender {
        // Hardening: direct messages must use sealed-sender to avoid metadata downgrade.
        return Err(ApiError::bad_request("sealed_sender required"));
    }
    Ok(sealed_sender)
}

fn should_redact_sender(sealed_flag: i64, sealed_view: bool) -> bool {
    sealed_flag != 0 || sealed_view
}

#[cfg(test)]
mod tests {
    use super::{
        build_push_data, is_strict_v2_bundle_eligible, is_valid_device_id, normalize_key_material,
        normalize_mailbox_token, normalize_prekey_batch, parse_protocol_version,
        parse_required_direct_ciphertext, parse_required_group_ciphertext, register_keys,
        require_sealed_sender_flag, require_v2_only_key_registration, should_redact_sender,
        validate_protocol_write, verify_signed_prekey_signature, ChatProtocolVersion,
        PROTOCOL_V1_LEGACY, PROTOCOL_V2_LIBSIGNAL, PUSH_TYPE_CHAT_WAKEUP,
    };
    use crate::models::{GroupSendReq, OneTimePrekeyIn};
    use crate::state::AppState;
    use axum::body::{to_bytes, Body};
    use axum::http::{Request, StatusCode};
    use axum::routing::post;
    use axum::Router;
    use base64::engine::general_purpose::STANDARD;
    use base64::Engine;
    use ed25519_dalek::{Signer, SigningKey};
    use reqwest::Client;
    use sqlx::postgres::PgPoolOptions;
    use std::io::{self, Write};
    use std::sync::{Arc, Mutex};
    use tower::ServiceExt;
    use tracing_subscriber::fmt::writer::MakeWriter;

    fn group_req() -> GroupSendReq {
        GroupSendReq {
            sender_id: "DEV12345".to_string(),
            protocol_version: None,
            nonce_b64: None,
            box_b64: None,
            expire_after_seconds: None,
        }
    }

    #[derive(Clone, Default)]
    struct SharedLogBuffer(Arc<Mutex<Vec<u8>>>);

    impl SharedLogBuffer {
        fn as_string(&self) -> String {
            let guard = self.0.lock().expect("log buffer lock");
            String::from_utf8_lossy(&guard).to_string()
        }
    }

    struct SharedLogBufferWriter(Arc<Mutex<Vec<u8>>>);

    impl Write for SharedLogBufferWriter {
        fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
            let mut guard = self.0.lock().expect("log buffer writer lock");
            guard.extend_from_slice(buf);
            Ok(buf.len())
        }

        fn flush(&mut self) -> io::Result<()> {
            Ok(())
        }
    }

    impl<'a> MakeWriter<'a> for SharedLogBuffer {
        type Writer = SharedLogBufferWriter;

        fn make_writer(&'a self) -> Self::Writer {
            SharedLogBufferWriter(self.0.clone())
        }
    }

    #[tokio::test(flavor = "current_thread")]
    async fn keys_register_route_rejects_missing_v2_only_and_logs_security_event() {
        let logs = SharedLogBuffer::default();
        let subscriber = tracing_subscriber::fmt()
            .json()
            .with_ansi(false)
            .without_time()
            .with_target(false)
            .with_current_span(false)
            .with_writer(logs.clone())
            .finish();
        let _sub_guard = tracing::subscriber::set_default(subscriber);

        let pool = PgPoolOptions::new()
            .max_connections(1)
            .connect_lazy("postgresql://invalid:invalid@127.0.0.1:1/invalid")
            .expect("lazy test pool");
        let http = Client::builder().build().expect("http client");
        let state = AppState {
            pool,
            db_schema: None,
            env_name: "test".to_string(),
            enforce_device_auth: false,
            fcm_server_key: None,
            chat_protocol_v2_enabled: true,
            chat_protocol_v1_write_enabled: false,
            chat_protocol_v1_read_enabled: false,
            chat_protocol_require_v2_for_groups: true,
            chat_mailbox_api_enabled: false,
            chat_mailbox_inactive_retention_secs: 0,
            chat_mailbox_consumed_retention_secs: 0,
            http,
        };
        let app = Router::new()
            .route("/keys/register", post(register_keys))
            .with_state(state);

        let body = serde_json::json!({
            "device_id": "DEV12345",
            "identity_key_b64": "x",
            "identity_signing_pubkey_b64": "x",
            "signed_prekey_id": 1,
            "signed_prekey_b64": "x",
            "signed_prekey_sig_b64": "x",
            "signed_prekey_sig_alg": "ed25519"
        });
        let req = Request::builder()
            .method("POST")
            .uri("/keys/register")
            .header("content-type", "application/json")
            .body(Body::from(body.to_string()))
            .expect("request");

        let resp = app.oneshot(req).await.expect("response");
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
        let body = to_bytes(resp.into_body(), 1024 * 1024).await.expect("body");
        let out: serde_json::Value = serde_json::from_slice(&body).expect("json body");
        assert_eq!(
            out.get("detail").and_then(|v| v.as_str()),
            Some("v2_only=true required")
        );

        let log_text = logs.as_string();
        assert!(
            log_text.contains("\"security_event\":\"chat_key_register_policy\""),
            "missing security_event log: {log_text}"
        );
        assert!(
            log_text.contains("\"outcome\":\"blocked\""),
            "missing blocked outcome log: {log_text}"
        );
        assert!(
            log_text.contains("\"reason\":\"v2_only_required\""),
            "missing reason log: {log_text}"
        );
    }

    #[test]
    fn requires_group_ciphertext_envelope() {
        let req = group_req();
        let err =
            parse_required_group_ciphertext(&req).expect_err("must reject plaintext group msg");
        assert_eq!(err.status, StatusCode::BAD_REQUEST);
        assert_eq!(err.detail, "group message encryption required");
    }

    #[test]
    fn requires_nonce_when_box_present() {
        let mut req = group_req();
        req.box_b64 = Some("cipher".to_string());
        let err = parse_required_group_ciphertext(&req).expect_err("must require nonce");
        assert_eq!(err.status, StatusCode::BAD_REQUEST);
        assert_eq!(err.detail, "missing nonce");
    }

    #[test]
    fn requires_box_when_nonce_present() {
        let mut req = group_req();
        req.nonce_b64 = Some("nonce".to_string());
        let err = parse_required_group_ciphertext(&req).expect_err("must require box");
        assert_eq!(err.status, StatusCode::BAD_REQUEST);
        assert_eq!(err.detail, "missing box");
    }

    #[test]
    fn accepts_trimmed_nonce_and_box() {
        let mut req = group_req();
        req.nonce_b64 = Some("  AAAAAAAAAAAAAAAA  ".to_string());
        req.box_b64 = Some("  BBBBBBBBBBBBBBBB  ".to_string());
        let parsed = parse_required_group_ciphertext(&req).expect("must accept encrypted envelope");
        assert_eq!(parsed.0, "AAAAAAAAAAAAAAAA");
        assert_eq!(parsed.1, "BBBBBBBBBBBBBBBB");
    }

    #[test]
    fn requires_direct_ciphertext_envelope() {
        let err = parse_required_direct_ciphertext("", "")
            .expect_err("must reject plaintext direct message");
        assert_eq!(err.status, StatusCode::BAD_REQUEST);
        assert_eq!(err.detail, "message encryption required");
    }

    #[test]
    fn requires_nonce_when_direct_box_present() {
        let err = parse_required_direct_ciphertext("", "AAAAAAAAAAAAAAAA")
            .expect_err("must require nonce");
        assert_eq!(err.status, StatusCode::BAD_REQUEST);
        assert_eq!(err.detail, "missing nonce");
    }

    #[test]
    fn requires_box_when_direct_nonce_present() {
        let err =
            parse_required_direct_ciphertext("AAAAAAAAAAAAAAAA", "").expect_err("must require box");
        assert_eq!(err.status, StatusCode::BAD_REQUEST);
        assert_eq!(err.detail, "missing box");
    }

    #[test]
    fn accepts_trimmed_direct_nonce_and_box() {
        let parsed =
            parse_required_direct_ciphertext("  AAAAAAAAAAAAAAAA  ", "  BBBBBBBBBBBBBBBB  ")
                .expect("must accept encrypted envelope");
        assert_eq!(parsed.0, "AAAAAAAAAAAAAAAA");
        assert_eq!(parsed.1, "BBBBBBBBBBBBBBBB");
    }

    #[test]
    fn push_payload_is_wakeup_only() {
        let data = build_push_data();
        assert_eq!(data.len(), 2, "push data must remain minimal");
        assert_eq!(
            data.get("type").and_then(|v| v.as_str()),
            Some(PUSH_TYPE_CHAT_WAKEUP)
        );
        assert_eq!(data.get("wakeup").and_then(|v| v.as_bool()), Some(true));
    }

    #[test]
    fn protocol_parser_defaults_to_v1_legacy() {
        let parsed = parse_protocol_version(None).expect("missing protocol should default");
        assert_eq!(parsed, ChatProtocolVersion::V1Legacy);
        let parsed = parse_protocol_version(Some(PROTOCOL_V1_LEGACY)).expect("v1 should parse");
        assert_eq!(parsed, ChatProtocolVersion::V1Legacy);
    }

    #[test]
    fn protocol_parser_accepts_v2_and_rejects_invalid() {
        let parsed = parse_protocol_version(Some(PROTOCOL_V2_LIBSIGNAL)).expect("v2 should parse");
        assert_eq!(parsed, ChatProtocolVersion::V2Libsignal);

        let err = parse_protocol_version(Some("unknown_version")).expect_err("invalid version");
        assert_eq!(err.status, StatusCode::BAD_REQUEST);
        assert_eq!(err.detail, "invalid protocol_version");
    }

    #[test]
    fn protocol_write_validation_enforces_flags() {
        let err =
            validate_protocol_write(false, true, false, ChatProtocolVersion::V2Libsignal, false)
                .expect_err("v2 must be rejected when disabled");
        assert_eq!(err.detail, "protocol v2 disabled");

        let err = validate_protocol_write(true, false, false, ChatProtocolVersion::V1Legacy, false)
            .expect_err("v1 writes must be rejected when disabled");
        assert_eq!(err.detail, "protocol v1 writes disabled");

        let err = validate_protocol_write(true, true, true, ChatProtocolVersion::V1Legacy, true)
            .expect_err("group v1 must be rejected when v2 required");
        assert_eq!(
            err.detail,
            "group messages require protocol_version v2_libsignal"
        );
    }

    #[test]
    fn key_register_policy_requires_v2_enabled() {
        let err = require_v2_only_key_registration(false, Some(true))
            .expect_err("must reject when v2 is disabled");
        assert_eq!(err.status, StatusCode::BAD_REQUEST);
        assert_eq!(err.detail, "protocol v2 disabled");
    }

    #[test]
    fn key_register_policy_requires_explicit_v2_only_true() {
        let err = require_v2_only_key_registration(true, None)
            .expect_err("missing v2_only must be rejected");
        assert_eq!(err.status, StatusCode::BAD_REQUEST);
        assert_eq!(err.detail, "v2_only=true required");

        let err = require_v2_only_key_registration(true, Some(false))
            .expect_err("v2_only=false must be rejected");
        assert_eq!(err.status, StatusCode::BAD_REQUEST);
        assert_eq!(err.detail, "v2_only=true required");
    }

    #[test]
    fn key_register_policy_accepts_explicit_v2_only_true() {
        let v2_only =
            require_v2_only_key_registration(true, Some(true)).expect("v2_only=true should pass");
        assert!(v2_only);
    }

    #[test]
    fn strict_v2_bundle_policy_accepts_complete_bundle() {
        assert!(is_strict_v2_bundle_eligible(
            PROTOCOL_V2_LIBSIGNAL,
            true,
            true,
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            Some("BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="),
            7,
            "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=",
            "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD="
        ));
    }

    #[test]
    fn strict_v2_bundle_policy_rejects_legacy_or_missing_material() {
        assert!(!is_strict_v2_bundle_eligible(
            PROTOCOL_V1_LEGACY,
            false,
            false,
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            Some("BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="),
            7,
            "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=",
            "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD="
        ));
        assert!(!is_strict_v2_bundle_eligible(
            PROTOCOL_V2_LIBSIGNAL,
            true,
            true,
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            None,
            7,
            "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=",
            "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD="
        ));
        assert!(!is_strict_v2_bundle_eligible(
            PROTOCOL_V2_LIBSIGNAL,
            true,
            true,
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            Some("BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="),
            0,
            "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=",
            "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD="
        ));
    }

    #[test]
    fn key_material_normalizer_rejects_invalid_chars() {
        let err = normalize_key_material("%%%not-valid%%%", "identity_key_b64", 32, 8192)
            .expect_err("invalid chars must be rejected");
        assert_eq!(err.status, StatusCode::BAD_REQUEST);
        assert_eq!(err.detail, "invalid identity_key_b64");
    }

    #[test]
    fn signed_prekey_signature_verifier_accepts_valid_ed25519_signature() {
        let device_id = "DEV12345";
        let identity_key_b64 = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        let signed_prekey_id = 42_i64;
        let signed_prekey_b64 = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";
        let msg = format!(
            "shamell-key-register-v1\n{device_id}\n{identity_key_b64}\n{signed_prekey_id}\n{signed_prekey_b64}\n"
        );
        let sk = SigningKey::from_bytes(&[7_u8; 32]);
        let sig = sk.sign(msg.as_bytes());
        let pk_b64 = STANDARD.encode(sk.verifying_key().as_bytes());
        let sig_b64 = STANDARD.encode(sig.to_bytes());

        verify_signed_prekey_signature(
            device_id,
            identity_key_b64,
            signed_prekey_id,
            signed_prekey_b64,
            &pk_b64,
            &sig_b64,
        )
        .expect("valid signature");
    }

    #[test]
    fn signed_prekey_signature_verifier_rejects_tamper() {
        let device_id = "DEV12345";
        let identity_key_b64 = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        let signed_prekey_id = 42_i64;
        let signed_prekey_b64 = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";
        let msg = format!(
            "shamell-key-register-v1\n{device_id}\n{identity_key_b64}\n{signed_prekey_id}\n{signed_prekey_b64}\n"
        );
        let sk = SigningKey::from_bytes(&[9_u8; 32]);
        let sig = sk.sign(msg.as_bytes());
        let pk_b64 = STANDARD.encode(sk.verifying_key().as_bytes());
        let sig_b64 = STANDARD.encode(sig.to_bytes());

        let err = verify_signed_prekey_signature(
            device_id,
            identity_key_b64,
            signed_prekey_id + 1,
            signed_prekey_b64,
            &pk_b64,
            &sig_b64,
        )
        .expect_err("tampered payload must be rejected");
        assert_eq!(err.status, StatusCode::BAD_REQUEST);
        assert_eq!(err.detail, "invalid signed_prekey signature");
    }

    #[test]
    fn prekey_batch_rejects_duplicate_ids() {
        let prekeys = vec![
            OneTimePrekeyIn {
                key_id: 1,
                key_b64: "AAAAAABBBBBBCCCCCCDDDDDD====".to_string(),
            },
            OneTimePrekeyIn {
                key_id: 1,
                key_b64: "EEEEEEFFFFFFGGGGGGHHHHHH====".to_string(),
            },
        ];
        let err = normalize_prekey_batch(&prekeys).expect_err("duplicate IDs must be rejected");
        assert_eq!(err.status, StatusCode::BAD_REQUEST);
        assert_eq!(err.detail, "invalid prekeys");
    }

    #[test]
    fn prekey_batch_accepts_unique_entries() {
        let prekeys = vec![
            OneTimePrekeyIn {
                key_id: 101,
                key_b64: "AAAAAABBBBBBCCCCCCDDDDDD====".to_string(),
            },
            OneTimePrekeyIn {
                key_id: 202,
                key_b64: "EEEEEEFFFFFFGGGGGGHHHHHH====".to_string(),
            },
        ];
        let parsed = normalize_prekey_batch(&prekeys).expect("valid prekeys should pass");
        assert_eq!(parsed.len(), 2);
        assert_eq!(parsed[0].0, 101);
        assert_eq!(parsed[1].0, 202);
    }

    #[test]
    fn wakeup_push_payload_omits_sender_and_message_metadata() {
        let data = build_push_data();
        assert_eq!(
            data.get("type").and_then(|v| v.as_str()),
            Some("chat_wakeup")
        );
        assert_eq!(data.get("wakeup").and_then(|v| v.as_bool()), Some(true));
        assert!(!data.contains_key("device_id"));
        assert!(!data.contains_key("mid"));
        assert!(!data.contains_key("sender_id"));
        assert!(!data.contains_key("group_id"));
        assert!(!data.contains_key("group_name"));
    }

    #[test]
    fn mailbox_token_normalizer_accepts_hex_and_rejects_bad_chars() {
        let ok = normalize_mailbox_token(
            "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        )
        .expect("valid token");
        assert_eq!(ok.len(), 64);

        let err = normalize_mailbox_token("short token").expect_err("invalid token");
        assert_eq!(err.status, StatusCode::BAD_REQUEST);
        assert_eq!(err.detail, "invalid mailbox_token");
    }

    #[test]
    fn device_id_validation_rejects_reserved_words() {
        assert!(is_valid_device_id("DEV12345"));
        assert!(!is_valid_device_id("register"));
        assert!(!is_valid_device_id("REGISTER"));
    }

    #[test]
    fn direct_messages_require_sealed_sender() {
        let err = require_sealed_sender_flag(None).expect_err("must require sealed_sender");
        assert_eq!(err.status, StatusCode::BAD_REQUEST);
        assert_eq!(err.detail, "sealed_sender required");

        let err = require_sealed_sender_flag(Some(false)).expect_err("must require sealed_sender");
        assert_eq!(err.status, StatusCode::BAD_REQUEST);
        assert_eq!(err.detail, "sealed_sender required");

        let ok = require_sealed_sender_flag(Some(true)).expect("sealed_sender=true ok");
        assert!(ok);
    }

    #[test]
    fn sealed_view_redacts_sender_fields() {
        assert!(should_redact_sender(0, true));
        assert!(should_redact_sender(1, true));
        assert!(should_redact_sender(1, false));
        assert!(!should_redact_sender(0, false));
    }
}
