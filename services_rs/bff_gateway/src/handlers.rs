use crate::auth;
use crate::authz;
use crate::error::{ApiError, ApiResult};
use crate::models::{
    AdminRolesCheckQuery, AdminRolesListQuery, BusBookingSearchQuery, BusCitiesQuery,
    BusListOperatorsQuery, BusOperatorStatsQuery, BusOperatorTripsQuery, BusRoutesQuery,
    BusTripsSearchQuery, ChatGroupInboxQuery, ChatGroupKeyEventsQuery, ChatGroupListQuery,
    ChatGroupMembersQuery, ChatInboxQuery, ChatMailboxPollReq, ChatStreamQuery, FavoritesListQuery,
    HealthOut, RequestsListQuery,
};
use crate::state::AppState;
use axum::body::Body;
use axum::extract::{Path, Query, State};
use axum::http::{header::CONTENT_TYPE, HeaderMap, StatusCode};
use axum::response::Response;
use futures_util::StreamExt;
use reqwest::Method;
use serde::{Deserialize, Serialize};
use serde_json::Map;
use serde_json::{json, Value};

const H_USER_AGENT: &[&str] = &["User-Agent"];
const H_CHAT_AUTH: &[&str] = &["X-Chat-Device-Id", "X-Chat-Device-Token", "User-Agent"];
const H_BUS_WRITE: &[&str] = &["Idempotency-Key", "X-Device-ID", "User-Agent"];
const H_PAY_TRANSFER: &[&str] = &[
    "Idempotency-Key",
    "X-Device-ID",
    "User-Agent",
    "X-Merchant",
    "X-Ref",
];
const H_PAY_TOPUP: &[&str] = &["Idempotency-Key", "User-Agent"];

#[derive(Clone, Copy)]
enum Upstream {
    Payments,
    Chat,
    Bus,
}

#[derive(Debug, Clone)]
struct UserContext {
    account_id: String,
    wallet_id: String,
}

#[derive(Debug, Deserialize)]
pub struct SecurityAlertIngestIn {
    pub source: String,
    #[serde(default)]
    pub service: Option<String>,
    #[serde(default)]
    pub timestamp: Option<String>,
    #[serde(default)]
    pub window_secs: Option<u64>,
    #[serde(default)]
    pub alerts: Vec<String>,
    #[serde(default)]
    pub severity: Option<String>,
    #[serde(default)]
    pub note: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct SecurityAlertIngestOut {
    pub status: &'static str,
    pub accepted: usize,
}

async fn require_user_context(state: &AppState, headers: &HeaderMap) -> ApiResult<UserContext> {
    let principal = auth::require_session_principal(state, headers).await?;
    let wallet_id = ensure_wallet_for_account(
        state,
        headers,
        &principal.account_id,
        principal.phone.as_deref(),
    )
    .await?;
    Ok(UserContext {
        account_id: principal.account_id,
        wallet_id,
    })
}

async fn ensure_wallet_for_account(
    state: &AppState,
    headers: &HeaderMap,
    account_id: &str,
    phone: Option<&str>,
) -> ApiResult<String> {
    let mut payload = Map::new();
    payload.insert("account_id".to_string(), json!(account_id));
    if let Some(p) = phone.map(str::trim).filter(|s| !s.is_empty()) {
        payload.insert("phone".to_string(), json!(p));
    }
    let out = proxy_payments(
        state,
        Method::POST,
        "/users",
        Vec::new(),
        Some(Value::Object(payload)),
        headers,
        &[],
    )
    .await?;

    let wallet_id = out
        .0
        .get("wallet_id")
        .or_else(|| out.0.get("id"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(ToString::to_string)
        .ok_or_else(|| ApiError::internal("payments user response missing wallet_id"))?;

    Ok(wallet_id)
}

fn json_object(body: Value) -> ApiResult<Map<String, Value>> {
    match body {
        Value::Object(obj) => Ok(obj),
        _ => Err(ApiError::bad_request("object body required")),
    }
}

pub async fn health(State(state): State<AppState>) -> axum::Json<HealthOut> {
    axum::Json(HealthOut {
        status: "ok",
        env: state.env_name.clone(),
        service: "BFF Gateway",
        version: env!("CARGO_PKG_VERSION"),
    })
}

pub async fn security_alert_ingest(
    headers: HeaderMap,
    axum::Json(payload): axum::Json<SecurityAlertIngestIn>,
) -> ApiResult<(StatusCode, axum::Json<SecurityAlertIngestOut>)> {
    let source = payload.source.trim();
    if source.is_empty() || source.len() > 128 {
        return Err(ApiError::bad_request(
            "source must be present and <= 128 chars",
        ));
    }

    let service = payload
        .service
        .as_deref()
        .map(str::trim)
        .filter(|v| !v.is_empty());
    if service.is_some_and(|s| s.len() > 64) {
        return Err(ApiError::bad_request("service must be <= 64 chars"));
    }

    let severity = payload
        .severity
        .as_deref()
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .unwrap_or("warning")
        .to_ascii_lowercase();
    if !matches!(severity.as_str(), "info" | "warning" | "high" | "critical") {
        return Err(ApiError::bad_request(
            "severity must be one of: info, warning, high, critical",
        ));
    }

    let mut alerts = Vec::with_capacity(payload.alerts.len().min(64));
    if payload.alerts.is_empty() {
        return Err(ApiError::bad_request(
            "alerts must contain at least one item",
        ));
    }
    if payload.alerts.len() > 64 {
        return Err(ApiError::bad_request(
            "alerts must contain at most 64 items",
        ));
    }
    for item in payload.alerts {
        let item = item.trim();
        if item.is_empty() || item.len() > 256 {
            return Err(ApiError::bad_request(
                "each alert must be present and <= 256 chars",
            ));
        }
        alerts.push(item.to_string());
    }

    let note = payload
        .note
        .as_deref()
        .map(str::trim)
        .filter(|v| !v.is_empty());
    if note.is_some_and(|n| n.len() > 1024) {
        return Err(ApiError::bad_request("note must be <= 1024 chars"));
    }

    let timestamp = payload
        .timestamp
        .as_deref()
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .unwrap_or("-");
    let window_secs = payload.window_secs.unwrap_or(0);

    let request_id = header_value(&headers, "x-request-id").unwrap_or_else(|| "-".to_string());
    let client_ip = header_value(&headers, "x-shamell-client-ip")
        .or_else(|| {
            header_value(&headers, "x-forwarded-for")
                .and_then(|v| v.split(',').next().map(str::trim).map(str::to_string))
        })
        .unwrap_or_else(|| "-".to_string());

    match severity.as_str() {
        "critical" => tracing::error!(
            security_event = "runtime_security_alert_ingest",
            outcome = "accepted",
            source = source,
            service = service.unwrap_or("-"),
            severity = severity,
            timestamp = timestamp,
            window_secs = window_secs,
            alerts_count = alerts.len(),
            alerts = ?alerts,
            note = note.unwrap_or("-"),
            request_id = request_id,
            client_ip = client_ip,
            "runtime security alert received"
        ),
        "high" | "warning" => tracing::warn!(
            security_event = "runtime_security_alert_ingest",
            outcome = "accepted",
            source = source,
            service = service.unwrap_or("-"),
            severity = severity,
            timestamp = timestamp,
            window_secs = window_secs,
            alerts_count = alerts.len(),
            alerts = ?alerts,
            note = note.unwrap_or("-"),
            request_id = request_id,
            client_ip = client_ip,
            "runtime security alert received"
        ),
        _ => tracing::info!(
            security_event = "runtime_security_alert_ingest",
            outcome = "accepted",
            source = source,
            service = service.unwrap_or("-"),
            severity = severity,
            timestamp = timestamp,
            window_secs = window_secs,
            alerts_count = alerts.len(),
            alerts = ?alerts,
            note = note.unwrap_or("-"),
            request_id = request_id,
            client_ip = client_ip,
            "runtime security alert received"
        ),
    }

    Ok((
        StatusCode::ACCEPTED,
        axum::Json(SecurityAlertIngestOut {
            status: "accepted",
            accepted: alerts.len(),
        }),
    ))
}

pub async fn payments_create_user(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    let user = require_user_context(&state, &headers).await?;
    let mut obj = json_object(body)?;
    if let Some(raw_account_id) = obj
        .get("account_id")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        if raw_account_id != user.account_id {
            return Err(ApiError::new(
                StatusCode::FORBIDDEN,
                "account_id must match authenticated user",
            ));
        }
    }
    // Privacy best practice: never accept/forward a client-supplied phone identifier.
    obj.remove("phone");
    obj.insert("account_id".to_string(), json!(user.account_id));

    proxy_payments(
        &state,
        Method::POST,
        "/users",
        Vec::new(),
        Some(Value::Object(obj)),
        &headers,
        &[],
    )
    .await
}

pub async fn payments_wallet(
    Path(wallet_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<axum::Json<Value>> {
    let wallet_id = required_path(&wallet_id, "wallet_id")?;
    let user = require_user_context(&state, &headers).await?;
    if wallet_id != user.wallet_id {
        return Err(ApiError::new(
            StatusCode::FORBIDDEN,
            "wallet_id must match authenticated user",
        ));
    }

    proxy_payments(
        &state,
        Method::GET,
        &format!("/wallets/{wallet_id}"),
        Vec::new(),
        None,
        &headers,
        &[],
    )
    .await
}

pub async fn payments_transfer(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    let user = require_user_context(&state, &headers).await?;
    let mut obj = json_object(body)?;
    if let Some(raw_from) = obj
        .get("from_wallet_id")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        if raw_from != user.wallet_id {
            return Err(ApiError::new(
                StatusCode::FORBIDDEN,
                "from_wallet_id must match authenticated user",
            ));
        }
    }
    obj.insert("from_wallet_id".to_string(), json!(user.wallet_id));

    proxy_payments(
        &state,
        Method::POST,
        "/transfer",
        Vec::new(),
        Some(Value::Object(obj)),
        &headers,
        H_PAY_TRANSFER,
    )
    .await
}

pub async fn payments_topup(
    Path(wallet_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    let wallet_id = required_path(&wallet_id, "wallet_id")?;
    let user = require_user_context(&state, &headers).await?;
    if wallet_id != user.wallet_id {
        return Err(ApiError::new(
            StatusCode::FORBIDDEN,
            "wallet_id must match authenticated user",
        ));
    }

    proxy_payments(
        &state,
        Method::POST,
        &format!("/wallets/{wallet_id}/topup"),
        Vec::new(),
        Some(body),
        &headers,
        H_PAY_TOPUP,
    )
    .await
}

pub async fn payments_favorites_create(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    let user = require_user_context(&state, &headers).await?;
    let mut obj = json_object(body)?;
    if let Some(raw_owner) = obj
        .get("owner_wallet_id")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        if raw_owner != user.wallet_id {
            return Err(ApiError::new(
                StatusCode::FORBIDDEN,
                "owner_wallet_id must match authenticated user",
            ));
        }
    }
    obj.insert("owner_wallet_id".to_string(), json!(user.wallet_id));

    proxy_payments(
        &state,
        Method::POST,
        "/favorites",
        Vec::new(),
        Some(Value::Object(obj)),
        &headers,
        H_USER_AGENT,
    )
    .await
}

pub async fn payments_favorites_list(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<FavoritesListQuery>,
) -> ApiResult<axum::Json<Value>> {
    let user = require_user_context(&state, &headers).await?;
    if let Some(raw_owner) = q
        .owner_wallet_id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        if raw_owner != user.wallet_id {
            return Err(ApiError::new(
                StatusCode::FORBIDDEN,
                "owner_wallet_id must match authenticated user",
            ));
        }
    }

    proxy_payments(
        &state,
        Method::GET,
        "/favorites",
        vec![("owner_wallet_id".to_string(), user.wallet_id)],
        None,
        &headers,
        H_USER_AGENT,
    )
    .await
}

pub async fn payments_favorites_delete(
    Path(fid): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<axum::Json<Value>> {
    let fid = required_path(&fid, "favorite id")?;
    let user = require_user_context(&state, &headers).await?;
    ensure_favorite_owned(&state, &headers, &fid, &user.wallet_id).await?;

    proxy_payments(
        &state,
        Method::DELETE,
        &format!("/favorites/{fid}"),
        Vec::new(),
        None,
        &headers,
        H_USER_AGENT,
    )
    .await
}

pub async fn payments_requests_create(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    let user = require_user_context(&state, &headers).await?;
    let mut obj = json_object(body)?;
    if let Some(raw_from) = obj
        .get("from_wallet_id")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        if raw_from != user.wallet_id {
            return Err(ApiError::new(
                StatusCode::FORBIDDEN,
                "from_wallet_id must match authenticated user",
            ));
        }
    }
    obj.insert("from_wallet_id".to_string(), json!(user.wallet_id));

    proxy_payments(
        &state,
        Method::POST,
        "/requests",
        Vec::new(),
        Some(Value::Object(obj)),
        &headers,
        H_USER_AGENT,
    )
    .await
}

pub async fn payments_requests_list(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<RequestsListQuery>,
) -> ApiResult<axum::Json<Value>> {
    let user = require_user_context(&state, &headers).await?;
    if let Some(raw_wallet) = q
        .wallet_id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        if raw_wallet != user.wallet_id {
            return Err(ApiError::new(
                StatusCode::FORBIDDEN,
                "wallet_id must match authenticated user",
            ));
        }
    }

    let mut query = vec![("wallet_id".to_string(), user.wallet_id)];
    push_opt_query(&mut query, "kind", q.kind.as_deref());
    push_limit_query(&mut query, "limit", q.limit, 100, 1, 500);

    proxy_payments(
        &state,
        Method::GET,
        "/requests",
        query,
        None,
        &headers,
        H_USER_AGENT,
    )
    .await
}

pub async fn payments_requests_accept(
    Path(rid): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    let rid = required_path(&rid, "request id")?;
    let user = require_user_context(&state, &headers).await?;
    ensure_request_owned_by_kind(&state, &headers, &rid, &user.wallet_id, "incoming").await?;
    let mut obj = json_object(body)?;
    if let Some(raw_to) = obj
        .get("to_wallet_id")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        if raw_to != user.wallet_id {
            return Err(ApiError::new(
                StatusCode::FORBIDDEN,
                "to_wallet_id must match authenticated user",
            ));
        }
    }
    obj.insert("to_wallet_id".to_string(), json!(user.wallet_id));

    proxy_payments(
        &state,
        Method::POST,
        &format!("/requests/{rid}/accept"),
        Vec::new(),
        Some(Value::Object(obj)),
        &headers,
        H_PAY_TOPUP,
    )
    .await
}

pub async fn payments_requests_cancel(
    Path(rid): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<axum::Json<Value>> {
    let rid = required_path(&rid, "request id")?;
    let user = require_user_context(&state, &headers).await?;
    ensure_request_owned_by_kind(&state, &headers, &rid, &user.wallet_id, "outgoing").await?;

    proxy_payments(
        &state,
        Method::POST,
        &format!("/requests/{rid}/cancel"),
        Vec::new(),
        None,
        &headers,
        H_USER_AGENT,
    )
    .await
}

pub async fn chat_register(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    let principal = if state.auth.is_some() {
        Some(auth::require_session_principal(&state, &headers).await?)
    } else {
        None
    };
    let register_device_id = extract_chat_device_id_from_body(&body)
        .ok_or_else(|| ApiError::bad_request("device_id required"))?;
    auth::enforce_chat_register_rate_limit(&state, &headers, Some(&register_device_id)).await?;
    let client_device_id = body
        .as_object()
        .and_then(|o| o.get("client_device_id"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(ToString::to_string);
    let out = proxy_chat(
        &state,
        Method::POST,
        "/devices/register",
        Vec::new(),
        Some(body),
        &headers,
        H_CHAT_AUTH,
    )
    .await?;
    if let Some(principal) = principal.as_ref() {
        auth::bind_chat_device_to_principal(
            &state,
            principal,
            &register_device_id,
            client_device_id.as_deref(),
        )
        .await?;
    }
    Ok(out)
}

#[derive(Debug, Deserialize)]
pub struct ContactInviteCreateIn {
    pub max_uses: Option<i64>,
}

pub async fn contacts_invite_create(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<ContactInviteCreateIn>,
) -> ApiResult<axum::Json<Value>> {
    if state.auth.is_none() {
        return Err(ApiError::new(
            StatusCode::SERVICE_UNAVAILABLE,
            "auth not configured",
        ));
    }
    let principal = auth::require_session_principal(&state, &headers).await?;
    let requested_max_uses = body.max_uses.unwrap_or(1);
    let (token, expires_at, max_uses) =
        auth::create_contact_invite(&state, &headers, &principal, requested_max_uses).await?;
    Ok(axum::Json(json!({
        "token": token,
        "expires_at": expires_at,
        "max_uses": max_uses,
    })))
}

#[derive(Debug, Deserialize)]
pub struct ContactInviteRedeemIn {
    pub token: Option<String>,
}

pub async fn contacts_invite_redeem(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<ContactInviteRedeemIn>,
) -> ApiResult<axum::Json<Value>> {
    if state.auth.is_none() {
        return Err(ApiError::new(
            StatusCode::SERVICE_UNAVAILABLE,
            "auth not configured",
        ));
    }
    let principal = auth::require_session_principal(&state, &headers).await?;
    let token = body.token.unwrap_or_default();
    let device_id = auth::redeem_contact_invite(&state, &headers, &principal, &token).await?;
    Ok(axum::Json(json!({
        "device_id": device_id,
    })))
}

pub async fn chat_get_device(
    Path(device_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<axum::Json<Value>> {
    let device_id = required_path(&device_id, "device_id")?;
    auth::enforce_chat_get_device_rate_limit(&state, &headers, &device_id).await?;
    proxy_chat(
        &state,
        Method::GET,
        &format!("/devices/{device_id}"),
        Vec::new(),
        None,
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_push_token(
    Path(device_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    let device_id = required_path(&device_id, "device_id")?;
    proxy_chat(
        &state,
        Method::POST,
        &format!("/devices/{device_id}/push_token"),
        Vec::new(),
        Some(body),
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_mailbox_issue(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    proxy_chat(
        &state,
        Method::POST,
        "/mailboxes/issue",
        Vec::new(),
        Some(body),
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_mailbox_write(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    let sender_device_id = header_value(&headers, "x-chat-device-id");
    let mailbox_token = body
        .as_object()
        .and_then(|o| o.get("mailbox_token"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty());
    auth::enforce_chat_mailbox_write_rate_limit(
        &state,
        &headers,
        sender_device_id.as_deref(),
        mailbox_token,
    )
    .await?;
    proxy_chat(
        &state,
        Method::POST,
        "/mailboxes/write",
        Vec::new(),
        Some(body),
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_mailbox_poll(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<ChatMailboxPollReq>,
) -> ApiResult<axum::Json<Value>> {
    proxy_chat(
        &state,
        Method::POST,
        "/mailboxes/poll",
        Vec::new(),
        Some(serde_json::to_value(body).unwrap_or_else(|_| json!({}))),
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_mailbox_rotate(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    proxy_chat(
        &state,
        Method::POST,
        "/mailboxes/rotate",
        Vec::new(),
        Some(body),
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_block(
    Path(device_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    let device_id = required_path(&device_id, "device_id")?;
    proxy_chat(
        &state,
        Method::POST,
        &format!("/devices/{device_id}/block"),
        Vec::new(),
        Some(body),
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_set_prefs(
    Path(device_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    let device_id = required_path(&device_id, "device_id")?;
    proxy_chat(
        &state,
        Method::POST,
        &format!("/devices/{device_id}/prefs"),
        Vec::new(),
        Some(body),
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_list_prefs(
    Path(device_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<axum::Json<Value>> {
    let device_id = required_path(&device_id, "device_id")?;
    proxy_chat(
        &state,
        Method::GET,
        &format!("/devices/{device_id}/prefs"),
        Vec::new(),
        None,
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_set_group_prefs(
    Path(device_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    let device_id = required_path(&device_id, "device_id")?;
    proxy_chat(
        &state,
        Method::POST,
        &format!("/devices/{device_id}/group_prefs"),
        Vec::new(),
        Some(body),
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_list_group_prefs(
    Path(device_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<axum::Json<Value>> {
    let device_id = required_path(&device_id, "device_id")?;
    proxy_chat(
        &state,
        Method::GET,
        &format!("/devices/{device_id}/group_prefs"),
        Vec::new(),
        None,
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_list_hidden(
    Path(device_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<axum::Json<Value>> {
    let device_id = required_path(&device_id, "device_id")?;
    proxy_chat(
        &state,
        Method::GET,
        &format!("/devices/{device_id}/hidden"),
        Vec::new(),
        None,
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_send(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    proxy_chat(
        &state,
        Method::POST,
        "/messages/send",
        Vec::new(),
        Some(body),
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_inbox(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<ChatInboxQuery>,
) -> ApiResult<axum::Json<Value>> {
    let device_id = required_query(q.device_id.as_deref(), "device_id required", "device_id")?;
    let mut query = vec![("device_id".to_string(), device_id)];
    push_opt_query(&mut query, "since_iso", q.since_iso.as_deref());
    push_limit_query(&mut query, "limit", q.limit, 50, 1, 200);

    proxy_chat(
        &state,
        Method::GET,
        "/messages/inbox",
        query,
        None,
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_stream(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<ChatStreamQuery>,
) -> ApiResult<Response> {
    let device_id = required_query(q.device_id.as_deref(), "device_id required", "device_id")?;
    let mut query = vec![("device_id".to_string(), device_id)];
    push_opt_query(&mut query, "since_iso", q.since_iso.as_deref());
    push_limit_query(&mut query, "limit", q.limit, 50, 1, 200);
    // Best practice: never allow clients to downgrade sealed-sender views.
    query.push(("sealed_view".to_string(), "true".to_string()));

    proxy_chat_stream(&state, "/messages/stream", query, &headers, H_CHAT_AUTH).await
}

pub async fn chat_mark_read(
    Path(mid): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    let mid = required_path(&mid, "message id")?;
    proxy_chat(
        &state,
        Method::POST,
        &format!("/messages/{mid}/read"),
        Vec::new(),
        Some(body),
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_group_create(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    proxy_chat(
        &state,
        Method::POST,
        "/groups/create",
        Vec::new(),
        Some(body),
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_group_list(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<ChatGroupListQuery>,
) -> ApiResult<axum::Json<Value>> {
    let device_id = required_query(q.device_id.as_deref(), "device_id required", "device_id")?;
    proxy_chat(
        &state,
        Method::GET,
        "/groups/list",
        vec![("device_id".to_string(), device_id)],
        None,
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_group_update(
    Path(group_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    let group_id = required_path(&group_id, "group_id")?;
    proxy_chat(
        &state,
        Method::POST,
        &format!("/groups/{group_id}/update"),
        Vec::new(),
        Some(body),
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_group_send(
    Path(group_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    let group_id = required_path(&group_id, "group_id")?;
    proxy_chat(
        &state,
        Method::POST,
        &format!("/groups/{group_id}/messages/send"),
        Vec::new(),
        Some(body),
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_group_inbox(
    Path(group_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<ChatGroupInboxQuery>,
) -> ApiResult<axum::Json<Value>> {
    let group_id = required_path(&group_id, "group_id")?;
    let device_id = required_query(q.device_id.as_deref(), "device_id required", "device_id")?;
    let mut query = vec![("device_id".to_string(), device_id)];
    push_opt_query(&mut query, "since_iso", q.since_iso.as_deref());
    push_limit_query(&mut query, "limit", q.limit, 50, 1, 200);

    proxy_chat(
        &state,
        Method::GET,
        &format!("/groups/{group_id}/messages/inbox"),
        query,
        None,
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_group_members(
    Path(group_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<ChatGroupMembersQuery>,
) -> ApiResult<axum::Json<Value>> {
    let group_id = required_path(&group_id, "group_id")?;
    let device_id = required_query(q.device_id.as_deref(), "device_id required", "device_id")?;

    proxy_chat(
        &state,
        Method::GET,
        &format!("/groups/{group_id}/members"),
        vec![("device_id".to_string(), device_id)],
        None,
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_group_invite(
    Path(group_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    let group_id = required_path(&group_id, "group_id")?;
    proxy_chat(
        &state,
        Method::POST,
        &format!("/groups/{group_id}/invite"),
        Vec::new(),
        Some(body),
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_group_leave(
    Path(group_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    let group_id = required_path(&group_id, "group_id")?;
    proxy_chat(
        &state,
        Method::POST,
        &format!("/groups/{group_id}/leave"),
        Vec::new(),
        Some(body),
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_group_set_role(
    Path(group_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    let group_id = required_path(&group_id, "group_id")?;
    proxy_chat(
        &state,
        Method::POST,
        &format!("/groups/{group_id}/set_role"),
        Vec::new(),
        Some(body),
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_group_rotate_key(
    Path(group_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    let group_id = required_path(&group_id, "group_id")?;
    proxy_chat(
        &state,
        Method::POST,
        &format!("/groups/{group_id}/keys/rotate"),
        Vec::new(),
        Some(body),
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn chat_group_key_events(
    Path(group_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<ChatGroupKeyEventsQuery>,
) -> ApiResult<axum::Json<Value>> {
    let group_id = required_path(&group_id, "group_id")?;
    let device_id = required_query(q.device_id.as_deref(), "device_id required", "device_id")?;

    let mut query = vec![("device_id".to_string(), device_id)];
    push_limit_query(&mut query, "limit", q.limit, 20, 1, 200);

    proxy_chat(
        &state,
        Method::GET,
        &format!("/groups/{group_id}/keys/events"),
        query,
        None,
        &headers,
        H_CHAT_AUTH,
    )
    .await
}

pub async fn bus_health(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<axum::Json<Value>> {
    proxy_bus(
        &state,
        Method::GET,
        "/health",
        Vec::new(),
        None,
        &headers,
        H_USER_AGENT,
    )
    .await
}

pub async fn bus_cities(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<BusCitiesQuery>,
) -> ApiResult<axum::Json<Value>> {
    let mut query = Vec::new();
    push_opt_query(&mut query, "q", q.q.as_deref());
    push_limit_query(&mut query, "limit", q.limit, 50, 1, 200);

    proxy_bus(
        &state,
        Method::GET,
        "/cities",
        query,
        None,
        &headers,
        H_USER_AGENT,
    )
    .await
}

pub async fn bus_cities_cached(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<BusCitiesQuery>,
) -> ApiResult<axum::Json<Value>> {
    let mut query = Vec::new();
    push_limit_query(&mut query, "limit", q.limit, 50, 1, 200);

    proxy_bus(
        &state,
        Method::GET,
        "/cities",
        query,
        None,
        &headers,
        H_USER_AGENT,
    )
    .await
}

pub async fn bus_routes(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<BusRoutesQuery>,
) -> ApiResult<axum::Json<Value>> {
    let mut query = Vec::new();
    push_opt_query(&mut query, "origin_city_id", q.origin_city_id.as_deref());
    push_opt_query(&mut query, "dest_city_id", q.dest_city_id.as_deref());

    proxy_bus(
        &state,
        Method::GET,
        "/routes",
        query,
        None,
        &headers,
        H_USER_AGENT,
    )
    .await
}

pub async fn bus_trips_search(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<BusTripsSearchQuery>,
) -> ApiResult<axum::Json<Value>> {
    let origin_city_id = required_query(
        q.origin_city_id.as_deref(),
        "origin_city_id required",
        "origin_city_id",
    )?;
    let dest_city_id = required_query(
        q.dest_city_id.as_deref(),
        "dest_city_id required",
        "dest_city_id",
    )?;
    let date = required_query(q.date.as_deref(), "date required", "date")?;

    let mut out = proxy_bus(
        &state,
        Method::GET,
        "/trips/search",
        vec![
            ("origin_city_id".to_string(), origin_city_id),
            ("dest_city_id".to_string(), dest_city_id),
            ("date".to_string(), date),
        ],
        None,
        &headers,
        H_USER_AGENT,
    )
    .await?
    .0;
    redact_operator_wallets_in_trip_search(&mut out);
    Ok(axum::Json(out))
}

pub async fn bus_trip_detail(
    Path(trip_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<axum::Json<Value>> {
    let trip_id = required_path(&trip_id, "trip_id")?;

    proxy_bus(
        &state,
        Method::GET,
        &format!("/trips/{trip_id}"),
        Vec::new(),
        None,
        &headers,
        H_USER_AGENT,
    )
    .await
}

pub async fn bus_create_city(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    proxy_bus(
        &state,
        Method::POST,
        "/cities",
        Vec::new(),
        Some(body),
        &headers,
        H_BUS_WRITE,
    )
    .await
}

pub async fn bus_list_operators(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<BusListOperatorsQuery>,
) -> ApiResult<axum::Json<Value>> {
    let mut query = Vec::new();
    push_limit_query(&mut query, "limit", q.limit, 50, 1, 200);

    let mut out = proxy_bus(
        &state,
        Method::GET,
        "/operators",
        query,
        None,
        &headers,
        H_USER_AGENT,
    )
    .await?
    .0;
    redact_operator_wallets_in_operator_list(&mut out);
    Ok(axum::Json(out))
}

pub async fn bus_create_operator(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    let roles = authz::trusted_roles(&state, &headers);
    let is_admin = roles.contains("admin") || roles.contains("superadmin");
    let mut obj = json_object(body)?;
    if !is_admin {
        let user = require_user_context(&state, &headers).await?;
        if let Some(raw_wallet) = obj
            .get("wallet_id")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|s| !s.is_empty())
        {
            if raw_wallet != user.wallet_id {
                return Err(ApiError::new(
                    StatusCode::FORBIDDEN,
                    "wallet_id must match authenticated user",
                ));
            }
        }
        obj.insert("wallet_id".to_string(), json!(user.wallet_id));
    }

    proxy_bus(
        &state,
        Method::POST,
        "/operators",
        Vec::new(),
        Some(Value::Object(obj)),
        &headers,
        H_BUS_WRITE,
    )
    .await
}

pub async fn bus_operator_online(
    Path(operator_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<axum::Json<Value>> {
    let operator_id = required_path(&operator_id, "operator_id")?;
    ensure_operator_owned_or_admin(&state, &headers, &operator_id).await?;
    proxy_bus(
        &state,
        Method::POST,
        &format!("/operators/{operator_id}/online"),
        Vec::new(),
        None,
        &headers,
        H_BUS_WRITE,
    )
    .await
}

pub async fn bus_operator_offline(
    Path(operator_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<axum::Json<Value>> {
    let operator_id = required_path(&operator_id, "operator_id")?;
    ensure_operator_owned_or_admin(&state, &headers, &operator_id).await?;
    proxy_bus(
        &state,
        Method::POST,
        &format!("/operators/{operator_id}/offline"),
        Vec::new(),
        None,
        &headers,
        H_BUS_WRITE,
    )
    .await
}

pub async fn bus_operator_stats(
    Path(operator_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<BusOperatorStatsQuery>,
) -> ApiResult<axum::Json<Value>> {
    let operator_id = required_path(&operator_id, "operator_id")?;
    ensure_operator_owned_or_admin(&state, &headers, &operator_id).await?;
    let mut query = Vec::new();
    push_opt_query(&mut query, "period", q.period.as_deref());

    proxy_bus(
        &state,
        Method::GET,
        &format!("/operators/{operator_id}/stats"),
        query,
        None,
        &headers,
        H_USER_AGENT,
    )
    .await
}

pub async fn bus_operator_trips(
    Path(operator_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<BusOperatorTripsQuery>,
) -> ApiResult<axum::Json<Value>> {
    let operator_id = required_path(&operator_id, "operator_id")?;
    ensure_operator_owned_or_admin(&state, &headers, &operator_id).await?;
    let mut query = Vec::new();
    push_opt_query(&mut query, "status", q.status.as_deref());
    push_opt_query(&mut query, "from_date", q.from_date.as_deref());
    push_opt_query(&mut query, "to_date", q.to_date.as_deref());
    push_limit_query(&mut query, "limit", q.limit, 100, 1, 200);
    push_opt_query(&mut query, "order", q.order.as_deref());

    proxy_bus(
        &state,
        Method::GET,
        &format!("/operators/{operator_id}/trips"),
        query,
        None,
        &headers,
        H_USER_AGENT,
    )
    .await
}

pub async fn bus_create_route(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    let operator_id = body
        .get("operator_id")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| ApiError::bad_request("operator_id required"))?;
    ensure_operator_owned_or_admin(&state, &headers, operator_id).await?;

    proxy_bus(
        &state,
        Method::POST,
        "/routes",
        Vec::new(),
        Some(body),
        &headers,
        H_BUS_WRITE,
    )
    .await
}

pub async fn bus_create_trip(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    let route_id = body
        .get("route_id")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| ApiError::bad_request("route_id required"))?;
    ensure_route_owned_or_admin(&state, &headers, route_id).await?;

    proxy_bus(
        &state,
        Method::POST,
        "/trips",
        Vec::new(),
        Some(body),
        &headers,
        H_BUS_WRITE,
    )
    .await
}

pub async fn bus_publish_trip(
    Path(trip_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<axum::Json<Value>> {
    let trip_id = required_path(&trip_id, "trip_id")?;
    ensure_trip_owned_or_admin(&state, &headers, &trip_id).await?;
    proxy_bus(
        &state,
        Method::POST,
        &format!("/trips/{trip_id}/publish"),
        Vec::new(),
        None,
        &headers,
        H_BUS_WRITE,
    )
    .await
}

pub async fn bus_unpublish_trip(
    Path(trip_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<axum::Json<Value>> {
    let trip_id = required_path(&trip_id, "trip_id")?;
    ensure_trip_owned_or_admin(&state, &headers, &trip_id).await?;
    proxy_bus(
        &state,
        Method::POST,
        &format!("/trips/{trip_id}/unpublish"),
        Vec::new(),
        None,
        &headers,
        H_BUS_WRITE,
    )
    .await
}

pub async fn bus_cancel_trip(
    Path(trip_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<axum::Json<Value>> {
    let trip_id = required_path(&trip_id, "trip_id")?;
    ensure_trip_owned_or_admin(&state, &headers, &trip_id).await?;
    proxy_bus(
        &state,
        Method::POST,
        &format!("/trips/{trip_id}/cancel"),
        Vec::new(),
        None,
        &headers,
        H_BUS_WRITE,
    )
    .await
}

pub async fn bus_book_trip(
    Path(trip_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    let trip_id = required_path(&trip_id, "trip_id")?;
    let user = require_user_context(&state, &headers).await?;
    let mut obj = json_object(body)?;
    if let Some(raw_wallet) = obj
        .get("wallet_id")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        if raw_wallet != user.wallet_id {
            return Err(ApiError::new(
                StatusCode::FORBIDDEN,
                "wallet_id must match authenticated user",
            ));
        }
    }
    // Privacy hardening: treat phone as optional metadata, never as an identity anchor.
    // Do not accept/forward client-supplied phone identifiers in this flow.
    obj.remove("customer_phone");
    obj.insert("wallet_id".to_string(), json!(user.wallet_id));

    proxy_bus(
        &state,
        Method::POST,
        &format!("/trips/{trip_id}/book"),
        Vec::new(),
        Some(Value::Object(obj)),
        &headers,
        H_BUS_WRITE,
    )
    .await
}

pub async fn bus_booking_search(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<BusBookingSearchQuery>,
) -> ApiResult<axum::Json<Value>> {
    let user = require_user_context(&state, &headers).await?;
    if let Some(raw_wallet) = q
        .wallet_id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        if raw_wallet != user.wallet_id {
            return Err(ApiError::new(
                StatusCode::FORBIDDEN,
                "wallet_id must match authenticated user",
            ));
        }
    }
    let mut query = vec![("wallet_id".to_string(), user.wallet_id.clone())];
    push_limit_query(&mut query, "limit", q.limit, 20, 1, 100);

    proxy_bus(
        &state,
        Method::GET,
        "/bookings/search",
        query,
        None,
        &headers,
        H_USER_AGENT,
    )
    .await
}

pub async fn bus_booking_status(
    Path(booking_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<axum::Json<Value>> {
    let booking_id = required_path(&booking_id, "booking_id")?;
    let user = require_user_context(&state, &headers).await?;
    let booking = fetch_owned_booking(&state, &headers, &booking_id, &user).await?;
    Ok(axum::Json(booking))
}

pub async fn bus_booking_tickets(
    Path(booking_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<axum::Json<Value>> {
    let booking_id = required_path(&booking_id, "booking_id")?;
    let user = require_user_context(&state, &headers).await?;
    let _ = fetch_owned_booking(&state, &headers, &booking_id, &user).await?;
    proxy_bus(
        &state,
        Method::GET,
        &format!("/bookings/{booking_id}/tickets"),
        Vec::new(),
        None,
        &headers,
        H_USER_AGENT,
    )
    .await
}

pub async fn bus_booking_cancel(
    Path(booking_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<axum::Json<Value>> {
    let booking_id = required_path(&booking_id, "booking_id")?;
    ensure_booking_owned_by_operator_or_admin(&state, &headers, &booking_id).await?;
    proxy_bus(
        &state,
        Method::POST,
        &format!("/bookings/{booking_id}/cancel"),
        Vec::new(),
        None,
        &headers,
        H_BUS_WRITE,
    )
    .await
}

pub async fn bus_ticket_board(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    let trip_id = body
        .get("payload")
        .and_then(Value::as_str)
        .and_then(ticket_payload_trip_id)
        .ok_or_else(|| ApiError::bad_request("ticket payload missing trip id"))?;
    ensure_trip_owned_or_admin(&state, &headers, &trip_id).await?;

    proxy_bus(
        &state,
        Method::POST,
        "/tickets/board",
        Vec::new(),
        Some(body),
        &headers,
        H_BUS_WRITE,
    )
    .await
}

pub async fn bus_admin_summary(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<axum::Json<Value>> {
    proxy_bus(
        &state,
        Method::GET,
        "/admin/summary",
        Vec::new(),
        None,
        &headers,
        H_USER_AGENT,
    )
    .await
}

pub async fn admin_roles_list(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<AdminRolesListQuery>,
) -> ApiResult<axum::Json<Value>> {
    let mut query = Vec::new();
    push_opt_query(&mut query, "account_id", q.account_id.as_deref());
    push_opt_query(&mut query, "phone", q.phone.as_deref());
    push_opt_query(&mut query, "role", q.role.as_deref());
    push_limit_query(&mut query, "limit", q.limit, 100, 1, 1000);

    proxy_payments(
        &state,
        Method::GET,
        "/admin/roles",
        query,
        None,
        &headers,
        H_USER_AGENT,
    )
    .await
}

pub async fn admin_roles_add(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    proxy_payments(
        &state,
        Method::POST,
        "/admin/roles",
        Vec::new(),
        Some(body),
        &headers,
        H_USER_AGENT,
    )
    .await
}

pub async fn admin_roles_remove(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<Value>,
) -> ApiResult<axum::Json<Value>> {
    proxy_payments(
        &state,
        Method::DELETE,
        "/admin/roles",
        Vec::new(),
        Some(body),
        &headers,
        H_USER_AGENT,
    )
    .await
}

pub async fn admin_roles_check(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<AdminRolesCheckQuery>,
) -> ApiResult<axum::Json<Value>> {
    let role = required_query(q.role.as_deref(), "role required", "role")?;
    let account_id = q
        .account_id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(ToString::to_string);
    let phone = q
        .phone
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(ToString::to_string);
    if account_id.is_none() && phone.is_none() {
        return Err(ApiError::bad_request("account_id or phone required"));
    }
    let mut query = Vec::new();
    if let Some(a) = account_id {
        query.push(("account_id".to_string(), a));
    }
    if let Some(p) = phone {
        query.push(("phone".to_string(), p));
    }
    query.push(("role".to_string(), role));

    proxy_payments(
        &state,
        Method::GET,
        "/admin/roles/check",
        query,
        None,
        &headers,
        H_USER_AGENT,
    )
    .await
}

async fn proxy_payments(
    state: &AppState,
    method: Method,
    path: &str,
    query: Vec<(String, String)>,
    body: Option<Value>,
    headers: &HeaderMap,
    forward_headers: &[&str],
) -> ApiResult<axum::Json<Value>> {
    let spec = ProxySpec {
        method,
        path,
        query,
        body,
        headers,
        forward_headers,
    };
    proxy_upstream(state, Upstream::Payments, spec).await
}

async fn proxy_chat(
    state: &AppState,
    method: Method,
    path: &str,
    query: Vec<(String, String)>,
    body: Option<Value>,
    headers: &HeaderMap,
    forward_headers: &[&str],
) -> ApiResult<axum::Json<Value>> {
    require_chat_guardrails_if_configured(state, headers, path, &query, body.as_ref()).await?;
    let spec = ProxySpec {
        method,
        path,
        query,
        body,
        headers,
        forward_headers,
    };
    proxy_upstream(state, Upstream::Chat, spec).await
}

async fn proxy_chat_stream(
    state: &AppState,
    path: &str,
    query: Vec<(String, String)>,
    headers: &HeaderMap,
    forward_headers: &[&str],
) -> ApiResult<Response> {
    require_chat_guardrails_if_configured(state, headers, path, &query, None).await?;
    let mut req = state.http.request(Method::GET, state.chat_url(path));
    if let Some(secret) = state.chat_internal_secret.as_deref() {
        let secret = secret.trim();
        if !secret.is_empty() {
            req = req.header("X-Internal-Secret", secret);
        }
    }
    let caller = state.internal_service_id.trim();
    if !caller.is_empty() {
        req = req.header("X-Internal-Service-Id", caller);
    }
    if !query.is_empty() {
        req = req.query(&query);
    }
    for h in forward_headers
        .iter()
        .copied()
        .chain(std::iter::once("X-Request-ID"))
    {
        if let Some(v) = headers.get(h) {
            if let Ok(vs) = v.to_str() {
                let vv = vs.trim();
                if !vv.is_empty() {
                    req = req.header(h, vv);
                }
            }
        }
    }

    let resp = req.send().await.map_err(|e| {
        tracing::error!(error = %e, path, upstream = "chat", "upstream call failed");
        ApiError::internal("chat upstream unavailable")
    })?;

    let status = StatusCode::from_u16(resp.status().as_u16()).unwrap_or(StatusCode::BAD_GATEWAY);
    if !status.is_success() {
        let text = resp.text().await.unwrap_or_default();
        let detail = sanitize_upstream_detail(state, status, "chat", text);
        return Err(ApiError::upstream(status, detail));
    }

    let content_type = resp.headers().get(CONTENT_TYPE).cloned();
    let stream = resp.bytes_stream();
    let mut out = Response::new(Body::from_stream(stream));
    *out.status_mut() = status;
    if let Some(ct) = content_type {
        out.headers_mut().insert(CONTENT_TYPE, ct);
    } else {
        out.headers_mut().insert(
            CONTENT_TYPE,
            axum::http::HeaderValue::from_static("text/event-stream"),
        );
    }
    out.headers_mut().insert(
        axum::http::header::CACHE_CONTROL,
        axum::http::HeaderValue::from_static("no-cache"),
    );
    Ok(out)
}

async fn proxy_bus(
    state: &AppState,
    method: Method,
    path: &str,
    query: Vec<(String, String)>,
    body: Option<Value>,
    headers: &HeaderMap,
    forward_headers: &[&str],
) -> ApiResult<axum::Json<Value>> {
    let spec = ProxySpec {
        method,
        path,
        query,
        body,
        headers,
        forward_headers,
    };
    proxy_upstream(state, Upstream::Bus, spec).await
}

struct ProxySpec<'a> {
    method: Method,
    path: &'a str,
    query: Vec<(String, String)>,
    body: Option<Value>,
    headers: &'a HeaderMap,
    forward_headers: &'a [&'a str],
}

async fn proxy_upstream(
    state: &AppState,
    upstream: Upstream,
    spec: ProxySpec<'_>,
) -> ApiResult<axum::Json<Value>> {
    let ProxySpec {
        method,
        path,
        query,
        body,
        headers,
        forward_headers,
    } = spec;

    let (url, upstream_name, secret) = match upstream {
        Upstream::Payments => (
            state.payments_url(path),
            "payments",
            state.payments_internal_secret.as_deref(),
        ),
        Upstream::Chat => (
            state.chat_url(path),
            "chat",
            state.chat_internal_secret.as_deref(),
        ),
        Upstream::Bus => (
            state.bus_url(path),
            "bus",
            state.bus_internal_secret.as_deref(),
        ),
    };

    let mut req = state.http.request(method, url);

    if let Some(secret) = secret.map(str::trim).filter(|s| !s.is_empty()) {
        req = req.header("X-Internal-Secret", secret);
    }
    let caller = state.internal_service_id.trim();
    if !caller.is_empty() {
        req = req.header("X-Internal-Service-Id", caller);
    }

    if !query.is_empty() {
        req = req.query(&query);
    }

    for h in forward_headers
        .iter()
        .copied()
        .chain(std::iter::once("X-Request-ID"))
    {
        if let Some(v) = headers.get(h) {
            if let Ok(vs) = v.to_str() {
                let vv = vs.trim();
                if !vv.is_empty() {
                    req = req.header(h, vv);
                }
            }
        }
    }

    if let Some(b) = body {
        req = req.json(&b);
    }

    let resp = req.send().await.map_err(|e| {
        tracing::error!(error = %e, path, upstream = upstream_name, "upstream call failed");
        ApiError::internal(format!("{upstream_name} upstream unavailable"))
    })?;

    let status = StatusCode::from_u16(resp.status().as_u16()).unwrap_or(StatusCode::BAD_GATEWAY);
    let is_json = resp
        .headers()
        .get(CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .map(|ct| ct.to_ascii_lowercase().starts_with("application/json"))
        .unwrap_or(false);
    let bytes =
        read_response_body_limited(resp, state.max_upstream_body_bytes, upstream_name, path)
            .await?;

    if is_json {
        let parsed: Value = serde_json::from_slice(&bytes).unwrap_or_else(
            |_| json!({"detail": format!("{upstream_name} upstream returned invalid json")}),
        );
        if status.is_success() {
            return Ok(axum::Json(parsed));
        }
        let detail = extract_detail(&parsed).unwrap_or_else(|| parsed.to_string());
        let detail = sanitize_upstream_detail(state, status, upstream_name, detail);
        return Err(ApiError::upstream(status, detail));
    }

    let text = String::from_utf8_lossy(&bytes).to_string();
    if status.is_success() {
        return Ok(axum::Json(json!({"raw": text})));
    }

    let detail = sanitize_upstream_detail(state, status, upstream_name, text);
    Err(ApiError::upstream(status, detail))
}

async fn read_response_body_limited(
    resp: reqwest::Response,
    max_bytes: usize,
    upstream_name: &str,
    path: &str,
) -> ApiResult<Vec<u8>> {
    if let Some(cl) = resp.content_length() {
        if cl as usize > max_bytes {
            tracing::warn!(
                upstream = upstream_name,
                path,
                content_length = cl,
                max_bytes,
                "upstream response exceeds configured limit"
            );
            return Err(ApiError::upstream(
                StatusCode::BAD_GATEWAY,
                format!("{upstream_name} upstream response too large"),
            ));
        }
    }

    let mut out: Vec<u8> = Vec::new();
    let mut total = 0usize;
    let mut stream = resp.bytes_stream();
    while let Some(next) = stream.next().await {
        let chunk = next.map_err(|e| {
            tracing::error!(
                error = %e,
                path,
                upstream = upstream_name,
                "upstream body read failed"
            );
            ApiError::internal(format!("{upstream_name} upstream body read failed"))
        })?;
        total += chunk.len();
        if total > max_bytes {
            tracing::warn!(
                upstream = upstream_name,
                path,
                total_bytes = total,
                max_bytes,
                "upstream response exceeded configured limit while streaming"
            );
            return Err(ApiError::upstream(
                StatusCode::BAD_GATEWAY,
                format!("{upstream_name} upstream response too large"),
            ));
        }
        out.extend_from_slice(&chunk);
    }
    Ok(out)
}

fn sanitize_upstream_detail(
    state: &AppState,
    status: StatusCode,
    upstream_name: &str,
    detail: String,
) -> String {
    if !state.expose_upstream_errors && (status.is_client_error() || status.is_server_error()) {
        return format!("{upstream_name} upstream error");
    }
    detail
}

async fn ensure_favorite_owned(
    state: &AppState,
    headers: &HeaderMap,
    fid: &str,
    owner_wallet_id: &str,
) -> ApiResult<()> {
    let out = proxy_payments(
        state,
        Method::GET,
        "/favorites",
        vec![("owner_wallet_id".to_string(), owner_wallet_id.to_string())],
        None,
        headers,
        H_USER_AGENT,
    )
    .await?;
    let found = out.0.as_array().is_some_and(|items| {
        items.iter().any(|it| {
            it.get("id")
                .and_then(Value::as_str)
                .map(str::trim)
                .is_some_and(|id| id == fid)
        })
    });
    if !found {
        return Err(ApiError::new(StatusCode::NOT_FOUND, "not found"));
    }
    Ok(())
}

async fn ensure_request_owned_by_kind(
    state: &AppState,
    headers: &HeaderMap,
    rid: &str,
    wallet_id: &str,
    kind: &str,
) -> ApiResult<()> {
    let out = proxy_payments(
        state,
        Method::GET,
        "/requests",
        vec![
            ("wallet_id".to_string(), wallet_id.to_string()),
            ("kind".to_string(), kind.to_string()),
            ("limit".to_string(), "500".to_string()),
        ],
        None,
        headers,
        H_USER_AGENT,
    )
    .await?;
    let found = out.0.as_array().is_some_and(|items| {
        items.iter().any(|it| {
            it.get("id")
                .and_then(Value::as_str)
                .map(str::trim)
                .is_some_and(|id| id == rid)
        })
    });
    if !found {
        return Err(ApiError::new(StatusCode::NOT_FOUND, "not found"));
    }
    Ok(())
}

async fn fetch_owned_booking(
    state: &AppState,
    headers: &HeaderMap,
    booking_id: &str,
    user: &UserContext,
) -> ApiResult<Value> {
    let booking = proxy_bus(
        state,
        Method::GET,
        &format!("/bookings/{booking_id}"),
        Vec::new(),
        None,
        headers,
        H_USER_AGENT,
    )
    .await?
    .0;

    let owner_wallet = booking
        .get("wallet_id")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let wallet_match = owner_wallet.is_some_and(|w| w == user.wallet_id.as_str());
    if !wallet_match {
        return Err(ApiError::new(StatusCode::NOT_FOUND, "not found"));
    }
    Ok(booking)
}

async fn ensure_operator_owned_or_admin(
    state: &AppState,
    headers: &HeaderMap,
    operator_id: &str,
) -> ApiResult<()> {
    let roles = authz::trusted_roles(state, headers);
    if roles.contains("admin") || roles.contains("superadmin") {
        return Ok(());
    }

    let user = require_user_context(state, headers).await?;
    let operator = proxy_bus(
        state,
        Method::GET,
        &format!("/operators/{operator_id}"),
        Vec::new(),
        None,
        headers,
        H_USER_AGENT,
    )
    .await?
    .0;

    let owner_wallet = operator
        .get("wallet_id")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| ApiError::new(StatusCode::FORBIDDEN, "operator has no owner wallet"))?;

    if owner_wallet != user.wallet_id.as_str() {
        return Err(ApiError::new(
            StatusCode::FORBIDDEN,
            "operator_id must belong to authenticated user",
        ));
    }
    Ok(())
}

async fn ensure_route_owned_or_admin(
    state: &AppState,
    headers: &HeaderMap,
    route_id: &str,
) -> ApiResult<()> {
    let route = proxy_bus(
        state,
        Method::GET,
        &format!("/routes/{route_id}"),
        Vec::new(),
        None,
        headers,
        H_USER_AGENT,
    )
    .await?
    .0;
    let operator_id = route
        .get("operator_id")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| ApiError::internal("bus route response missing operator_id"))?;
    ensure_operator_owned_or_admin(state, headers, operator_id).await
}

async fn ensure_trip_owned_or_admin(
    state: &AppState,
    headers: &HeaderMap,
    trip_id: &str,
) -> ApiResult<()> {
    let trip = proxy_bus(
        state,
        Method::GET,
        &format!("/trips/{trip_id}"),
        Vec::new(),
        None,
        headers,
        H_USER_AGENT,
    )
    .await?
    .0;
    let route_id = trip
        .get("route_id")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| ApiError::internal("bus trip response missing route_id"))?;
    ensure_route_owned_or_admin(state, headers, route_id).await
}

async fn ensure_booking_owned_by_operator_or_admin(
    state: &AppState,
    headers: &HeaderMap,
    booking_id: &str,
) -> ApiResult<()> {
    let booking = proxy_bus(
        state,
        Method::GET,
        &format!("/bookings/{booking_id}"),
        Vec::new(),
        None,
        headers,
        H_USER_AGENT,
    )
    .await?
    .0;
    let trip_id = booking
        .get("trip_id")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| ApiError::internal("bus booking response missing trip_id"))?;
    ensure_trip_owned_or_admin(state, headers, trip_id).await
}

fn ticket_payload_trip_id(raw: &str) -> Option<String> {
    let payload = raw.trim();
    if !payload.starts_with("TICKET|") {
        return None;
    }
    for kv in payload.split('|').skip(1) {
        let (k, v) = kv.split_once('=')?;
        if k == "trip" {
            let out = v.trim();
            if !out.is_empty() {
                return Some(out.to_string());
            }
        }
    }
    None
}

async fn require_chat_guardrails_if_configured(
    state: &AppState,
    headers: &HeaderMap,
    path: &str,
    query: &[(String, String)],
    body: Option<&Value>,
) -> ApiResult<()> {
    let norm_path = path.trim_end_matches('/');
    if norm_path == "/messages/send" {
        // Best practice: direct messages must use sealed-sender; never allow a client-driven
        // metadata downgrade, even in dev builds.
        let sealed_sender = body
            .and_then(|v| v.as_object())
            .and_then(|o| o.get("sealed_sender"))
            .and_then(Value::as_bool)
            .unwrap_or(false);
        if !sealed_sender {
            return Err(ApiError::bad_request("sealed_sender required"));
        }
    }
    if state.auth.is_some() {
        let principal = auth::require_session_principal(state, headers).await?;
        // Allow device registration before ownership can be established.
        // Subsequent chat calls are bound to the authenticated user via auth_chat_devices.
        if norm_path == "/devices/register" {
            return Ok(());
        }
        let device_id = extract_chat_device_id(headers, path, query, body)
            .ok_or_else(|| ApiError::bad_request("chat device_id required"))?;
        let _ = auth::require_chat_device_owned_by_principal(state, &principal, &device_id).await?;

        // Rate limits: apply only after AuthN/AuthZ has succeeded to avoid allowing
        // unauthenticated callers to burn rate-limit buckets.
        let sender_device_id = Some(device_id.as_str());
        if norm_path == "/messages/send" {
            auth::enforce_chat_send_rate_limit(state, headers, sender_device_id).await?;
            if auth::chat_send_requires_contacts(state) {
                let recipient_id = body
                    .and_then(|v| v.as_object())
                    .and_then(|o| o.get("recipient_id"))
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .ok_or_else(|| ApiError::bad_request("recipient_id required"))?;
                auth::require_chat_contact_allowed_for_direct_send(state, &principal, recipient_id)
                    .await?;
            }
        } else if norm_path.starts_with("/groups/") && norm_path.ends_with("/messages/send") {
            auth::enforce_chat_group_send_rate_limit(state, headers, sender_device_id).await?;
        }
    }
    Ok(())
}

fn extract_chat_device_id(
    headers: &HeaderMap,
    path: &str,
    query: &[(String, String)],
    body: Option<&Value>,
) -> Option<String> {
    header_value(headers, "x-chat-device-id")
        .or_else(|| {
            query
                .iter()
                .find(|(k, v)| k == "device_id" && !v.trim().is_empty())
                .map(|(_, v)| v.trim().to_string())
        })
        .or_else(|| extract_chat_device_id_from_path(path))
        .or_else(|| body.and_then(extract_chat_device_id_from_body))
}

fn extract_chat_device_id_from_path(path: &str) -> Option<String> {
    let rest = path.strip_prefix("/devices/")?;
    let device_id = rest.split('/').next().unwrap_or("").trim();
    // "/devices/register" is an action route, not a device resource path.
    if device_id.is_empty() || device_id.eq_ignore_ascii_case("register") {
        None
    } else {
        Some(device_id.to_string())
    }
}

fn extract_chat_device_id_from_body(body: &Value) -> Option<String> {
    let obj = body.as_object()?;
    for key in [
        "device_id",
        "from_device_id",
        "sender_device_id",
        "actor_device_id",
    ] {
        if let Some(v) = obj
            .get(key)
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|s| !s.is_empty())
        {
            return Some(v.to_string());
        }
    }
    None
}

fn required_path(raw: &str, field: &str) -> ApiResult<String> {
    let v = raw.trim().to_string();
    if v.is_empty() {
        return Err(ApiError::bad_request(format!("{field} required")));
    }
    if v.len() > 200 {
        return Err(ApiError::bad_request(format!("{field} too long")));
    }
    // Keep upstream path construction safe: never allow reserved path/query
    // delimiters in path parameters.
    if v.contains(['/', '\\', '?', '#', '%']) {
        return Err(ApiError::bad_request(format!("{field} invalid")));
    }
    Ok(v)
}

fn required_query(raw: Option<&str>, detail: &str, _field: &str) -> ApiResult<String> {
    let v = raw
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| ApiError::bad_request(detail))?;
    Ok(v.to_string())
}

fn header_value(headers: &HeaderMap, name: &str) -> Option<String> {
    headers
        .get(name)
        .and_then(|v| v.to_str().ok())
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(ToString::to_string)
}

fn push_opt_query(query: &mut Vec<(String, String)>, key: &str, raw: Option<&str>) {
    if let Some(v) = raw.map(str::trim).filter(|s| !s.is_empty()) {
        query.push((key.to_string(), v.to_string()));
    }
}

fn push_limit_query(
    query: &mut Vec<(String, String)>,
    key: &str,
    raw: Option<i64>,
    default: i64,
    min: i64,
    max: i64,
) {
    let v = raw.unwrap_or(default).clamp(min, max);
    query.push((key.to_string(), v.to_string()));
}

fn extract_detail(v: &Value) -> Option<String> {
    v.get("detail")
        .and_then(|d| d.as_str())
        .map(ToString::to_string)
}

fn redact_operator_wallets_in_operator_list(v: &mut Value) {
    let Some(items) = v.as_array_mut() else {
        return;
    };
    for item in items {
        if let Some(obj) = item.as_object_mut() {
            obj.remove("wallet_id");
        }
    }
}

fn redact_operator_wallets_in_trip_search(v: &mut Value) {
    let Some(items) = v.as_array_mut() else {
        return;
    };
    for item in items {
        let Some(obj) = item.as_object_mut() else {
            continue;
        };
        let Some(operator) = obj.get_mut("operator") else {
            continue;
        };
        if let Some(op_obj) = operator.as_object_mut() {
            op_obj.remove("wallet_id");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::extract::State as AxumState;
    use axum::http::Uri;
    use axum::response::IntoResponse;
    use axum::routing::get;
    use axum::Json;
    use axum::Router;
    use std::sync::{Arc, Mutex};

    #[derive(Clone, Default)]
    struct CaptureState {
        query: Arc<Mutex<Option<String>>>,
    }

    async fn capture_json(
        AxumState(state): AxumState<CaptureState>,
        uri: Uri,
    ) -> axum::Json<Value> {
        let mut lock = state.query.lock().expect("capture lock");
        *lock = uri.query().map(ToString::to_string);
        axum::Json(json!({"ok": true}))
    }

    async fn capture_sse(AxumState(state): AxumState<CaptureState>, uri: Uri) -> impl IntoResponse {
        let mut lock = state.query.lock().expect("capture lock");
        *lock = uri.query().map(ToString::to_string);
        (
            [(CONTENT_TYPE.as_str(), "text/event-stream")],
            "data: {\"ok\":true}\n\n",
        )
    }

    async fn spawn_test_server(app: Router) -> (String, tokio::task::JoinHandle<()>) {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind");
        let addr = listener.local_addr().expect("local addr");
        let handle = tokio::spawn(async move {
            axum::serve(listener, app).await.expect("serve");
        });
        (format!("http://{addr}"), handle)
    }

    fn mk_state_full(
        payments_base: String,
        bus_base: String,
        chat_base: String,
        max_upstream_body_bytes: usize,
        expose_upstream_errors: bool,
    ) -> AppState {
        AppState {
            env_name: "test".to_string(),
            payments_base_url: payments_base,
            payments_internal_secret: None,
            chat_base_url: chat_base,
            chat_internal_secret: Some("chat-secret".to_string()),
            bus_base_url: bus_base,
            bus_internal_secret: None,
            internal_service_id: "bff".to_string(),
            enforce_route_authz: false,
            role_header_secret: None,
            max_upstream_body_bytes,
            expose_upstream_errors,
            accept_legacy_session_cookie: false,
            auth_device_login_web_enabled: false,
            http: reqwest::Client::builder().build().expect("client"),
            auth: None,
        }
    }

    fn mk_state(
        bus_base: String,
        chat_base: String,
        max_upstream_body_bytes: usize,
        expose_upstream_errors: bool,
    ) -> AppState {
        mk_state_full(
            "http://127.0.0.1".to_string(),
            bus_base,
            chat_base,
            max_upstream_body_bytes,
            expose_upstream_errors,
        )
    }

    #[tokio::test]
    async fn bus_list_operators_forwards_only_limit_query() {
        let capture = CaptureState::default();
        let app = Router::new()
            .route("/operators", get(capture_json))
            .with_state(capture.clone());
        let (base, handle) = spawn_test_server(app).await;

        let state = mk_state(base, "http://127.0.0.1".to_string(), 1024 * 1024, true);
        let _ = bus_list_operators(
            AxumState(state),
            HeaderMap::new(),
            Query(BusListOperatorsQuery { limit: Some(9999) }),
        )
        .await
        .expect("bus list operators");

        let q = capture.query.lock().expect("capture lock").clone();
        handle.abort();

        assert_eq!(q.as_deref(), Some("limit=200"));
    }

    #[tokio::test]
    async fn chat_stream_proxies_sse_and_query() {
        let capture = CaptureState::default();
        let app = Router::new()
            .route("/messages/stream", get(capture_sse))
            .with_state(capture.clone());
        let (chat_base, handle) = spawn_test_server(app).await;

        let state = mk_state("http://127.0.0.1".to_string(), chat_base, 1024 * 1024, true);
        let resp = chat_stream(
            AxumState(state),
            HeaderMap::new(),
            Query(ChatStreamQuery {
                device_id: Some("dev_1".to_string()),
                since_iso: None,
                limit: Some(3),
            }),
        )
        .await
        .expect("chat stream");

        let status = resp.status();
        let ct = resp
            .headers()
            .get(CONTENT_TYPE)
            .and_then(|v| v.to_str().ok())
            .unwrap_or("")
            .to_string();
        let body = axum::body::to_bytes(resp.into_body(), 1024 * 1024)
            .await
            .expect("body");
        let body_s = String::from_utf8_lossy(&body).to_string();
        let q = capture.query.lock().expect("capture lock").clone();
        handle.abort();

        assert_eq!(status, StatusCode::OK);
        assert!(ct.starts_with("text/event-stream"));
        assert!(body_s.contains("data:"));
        let q = q.unwrap_or_default();
        assert!(q.contains("device_id=dev_1"));
        assert!(q.contains("limit=3"));
        assert!(q.contains("sealed_view=true"));
    }

    #[tokio::test]
    async fn chat_send_requires_sealed_sender() {
        let state = mk_state(
            "http://127.0.0.1".to_string(),
            "http://127.0.0.1".to_string(),
            1024 * 1024,
            true,
        );
        let err = chat_send(
            AxumState(state),
            HeaderMap::new(),
            axum::Json(json!({"sender_id":"dev_1","recipient_id":"dev_2"})),
        )
        .await
        .expect_err("must reject missing sealed_sender");

        assert_eq!(err.status, StatusCode::BAD_REQUEST);
        assert_eq!(err.detail, "sealed_sender required");
    }

    async fn large_json() -> impl IntoResponse {
        let payload = format!("{{\"blob\":\"{}\"}}", "x".repeat(5000));
        ([(CONTENT_TYPE.as_str(), "application/json")], payload)
    }

    #[tokio::test]
    async fn upstream_response_limit_is_enforced() {
        let app = Router::new().route("/cities", get(large_json));
        let (bus_base, handle) = spawn_test_server(app).await;

        let state = mk_state(bus_base, "http://127.0.0.1".to_string(), 256, true);
        let err = bus_cities(
            AxumState(state),
            HeaderMap::new(),
            Query(BusCitiesQuery {
                q: None,
                limit: None,
            }),
        )
        .await
        .expect_err("expected upstream body size error");

        handle.abort();
        assert_eq!(err.status, StatusCode::BAD_GATEWAY);
        assert!(err.detail.contains("upstream response too large"));
    }

    async fn error_500_json() -> impl IntoResponse {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            [(CONTENT_TYPE.as_str(), "application/json")],
            "{\"detail\":\"db stack trace\"}",
        )
    }

    async fn error_401_json() -> impl IntoResponse {
        (
            StatusCode::UNAUTHORIZED,
            [(CONTENT_TYPE.as_str(), "application/json")],
            "{\"detail\":\"internal auth required\"}",
        )
    }

    #[tokio::test]
    async fn upstream_5xx_detail_is_redacted_when_disabled() {
        let app = Router::new().route("/cities", get(error_500_json));
        let (bus_base, handle) = spawn_test_server(app).await;

        let state = mk_state(bus_base, "http://127.0.0.1".to_string(), 1024 * 1024, false);
        let err = bus_cities(
            AxumState(state),
            HeaderMap::new(),
            Query(BusCitiesQuery {
                q: None,
                limit: None,
            }),
        )
        .await
        .expect_err("expected upstream 500");

        handle.abort();
        assert_eq!(err.status, StatusCode::INTERNAL_SERVER_ERROR);
        assert_eq!(err.detail, "bus upstream error");
    }

    #[tokio::test]
    async fn upstream_4xx_detail_is_redacted_when_disabled() {
        let app = Router::new().route("/cities", get(error_401_json));
        let (bus_base, handle) = spawn_test_server(app).await;

        let state = mk_state(bus_base, "http://127.0.0.1".to_string(), 1024 * 1024, false);
        let err = bus_cities(
            AxumState(state),
            HeaderMap::new(),
            Query(BusCitiesQuery {
                q: None,
                limit: None,
            }),
        )
        .await
        .expect_err("expected upstream 401");

        handle.abort();
        assert_eq!(err.status, StatusCode::UNAUTHORIZED);
        assert_eq!(err.detail, "bus upstream error");
    }

    async fn requests_list() -> axum::Json<Value> {
        axum::Json(json!([
            {
                "id": "req-visible"
            }
        ]))
    }

    #[tokio::test]
    async fn ensure_request_owned_by_kind_returns_not_found_when_missing() {
        let app = Router::new().route("/requests", get(requests_list));
        let (payments_base, handle) = spawn_test_server(app).await;
        let state = mk_state_full(
            payments_base,
            "http://127.0.0.1".to_string(),
            "http://127.0.0.1".to_string(),
            1024 * 1024,
            true,
        );

        let err = ensure_request_owned_by_kind(
            &state,
            &HeaderMap::new(),
            "req-missing",
            "wallet-1",
            "incoming",
        )
        .await
        .expect_err("expected ownership check to fail");
        handle.abort();

        assert_eq!(err.status, StatusCode::NOT_FOUND);
    }

    async fn booking_other_owner() -> axum::Json<Value> {
        axum::Json(json!({
            "id": "b1",
            "wallet_id": "wallet-other",
            "customer_phone": "+963955555555"
        }))
    }

    #[tokio::test]
    async fn fetch_owned_booking_rejects_foreign_owner() {
        let app = Router::new().route("/bookings/:booking_id", get(booking_other_owner));
        let (bus_base, handle) = spawn_test_server(app).await;
        let state = mk_state(bus_base, "http://127.0.0.1".to_string(), 1024 * 1024, true);

        let user = UserContext {
            account_id: "acct-1".to_string(),
            wallet_id: "wallet-self".to_string(),
        };
        let err = fetch_owned_booking(&state, &HeaderMap::new(), "b1", &user)
            .await
            .expect_err("expected foreign booking to be blocked");
        handle.abort();

        assert_eq!(err.status, StatusCode::NOT_FOUND);
    }

    #[test]
    fn redact_operator_wallets_in_operator_list_removes_wallet_id() {
        let mut out = json!([
            {
                "id": "op-1",
                "name": "Operator One",
                "wallet_id": "wallet-secret"
            }
        ]);
        redact_operator_wallets_in_operator_list(&mut out);

        let arr = out.as_array().expect("array");
        let first = arr.first().and_then(Value::as_object).expect("object");
        assert!(!first.contains_key("wallet_id"));
    }

    #[test]
    fn redact_operator_wallets_in_trip_search_removes_nested_wallet_id() {
        let mut out = json!([
            {
                "trip": { "id": "t1" },
                "operator": {
                    "id": "op-1",
                    "wallet_id": "wallet-secret"
                }
            }
        ]);
        redact_operator_wallets_in_trip_search(&mut out);

        let arr = out.as_array().expect("array");
        let first = arr.first().and_then(Value::as_object).expect("object");
        let operator = first
            .get("operator")
            .and_then(Value::as_object)
            .expect("operator object");
        assert!(!operator.contains_key("wallet_id"));
    }

    #[test]
    fn required_path_rejects_reserved_delimiters() {
        let err =
            required_path("abc/def", "trip_id").expect_err("expected reserved char rejection");
        assert_eq!(err.status, StatusCode::BAD_REQUEST);
    }

    #[test]
    fn extract_chat_device_id_prefers_header() {
        let mut headers = HeaderMap::new();
        headers.insert(
            "x-chat-device-id",
            "dev-header".parse().expect("header value"),
        );
        let query = vec![("device_id".to_string(), "dev-query".to_string())];
        let body = json!({"device_id":"dev-body"});
        let out = extract_chat_device_id(&headers, "/devices/dev-path/prefs", &query, Some(&body));
        assert_eq!(out.as_deref(), Some("dev-header"));
    }

    #[test]
    fn extract_chat_device_id_falls_back_to_path() {
        let headers = HeaderMap::new();
        let out = extract_chat_device_id(&headers, "/devices/dev-path/prefs", &[], None);
        assert_eq!(out.as_deref(), Some("dev-path"));
    }

    #[test]
    fn extract_chat_device_id_reads_body_keys() {
        let headers = HeaderMap::new();
        let body = json!({"actor_device_id":"dev-actor"});
        let out = extract_chat_device_id(&headers, "/groups/create", &[], Some(&body));
        assert_eq!(out.as_deref(), Some("dev-actor"));
    }

    #[test]
    fn extract_chat_device_id_ignores_register_action_path() {
        let headers = HeaderMap::new();
        let body = json!({"device_id":"dev-body"});
        let out = extract_chat_device_id(&headers, "/devices/register", &[], Some(&body));
        assert_eq!(out.as_deref(), Some("dev-body"));
    }

    #[test]
    fn ticket_payload_trip_id_extracts_trip_value() {
        let trip_id = ticket_payload_trip_id("TICKET|id=t1|b=b1|trip=TRIP-A12|seat=1|sig=abcdef")
            .expect("trip id expected");
        assert_eq!(trip_id, "TRIP-A12");
    }

    #[test]
    fn ticket_payload_trip_id_rejects_invalid_payload() {
        assert!(ticket_payload_trip_id("INVALID").is_none());
        assert!(ticket_payload_trip_id("TICKET|id=t1|b=b1|seat=1|sig=abcdef").is_none());
    }

    #[tokio::test]
    async fn security_alert_ingest_accepts_valid_payload() {
        let resp = security_alert_ingest(
            HeaderMap::new(),
            Json(SecurityAlertIngestIn {
                source: "shamell-security-events-report".to_string(),
                service: Some("bff".to_string()),
                timestamp: Some("2026-02-11T22:00:00Z".to_string()),
                window_secs: Some(300),
                alerts: vec!["auth_rate_limit_exceeded.blocked:40/30".to_string()],
                severity: Some("warning".to_string()),
                note: Some("Synthetic test".to_string()),
            }),
        )
        .await
        .expect("security alert ingest response");

        assert_eq!(resp.0, StatusCode::ACCEPTED);
        assert_eq!(resp.1.accepted, 1);
    }

    #[tokio::test]
    async fn security_alert_ingest_rejects_invalid_severity() {
        let err = security_alert_ingest(
            HeaderMap::new(),
            Json(SecurityAlertIngestIn {
                source: "shamell-security-events-report".to_string(),
                service: Some("bff".to_string()),
                timestamp: None,
                window_secs: None,
                alerts: vec!["auth_rate_limit_exceeded.blocked:40/30".to_string()],
                severity: Some("urgent".to_string()),
                note: None,
            }),
        )
        .await
        .expect_err("invalid severity must fail");

        assert_eq!(err.status, StatusCode::BAD_REQUEST);
        assert!(err.detail.contains("severity must be one of"));
    }

    #[tokio::test]
    async fn security_alert_ingest_rejects_empty_alerts() {
        let err = security_alert_ingest(
            HeaderMap::new(),
            Json(SecurityAlertIngestIn {
                source: "shamell-security-events-report".to_string(),
                service: Some("bff".to_string()),
                timestamp: None,
                window_secs: None,
                alerts: vec![],
                severity: Some("warning".to_string()),
                note: None,
            }),
        )
        .await
        .expect_err("empty alerts must fail");

        assert_eq!(err.status, StatusCode::BAD_REQUEST);
        assert!(err.detail.contains("alerts must contain at least one"));
    }
}
