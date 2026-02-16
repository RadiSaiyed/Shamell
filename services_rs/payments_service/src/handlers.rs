use crate::error::{ApiError, ApiResult};
use crate::models::*;
use crate::state::AppState;
use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, HeaderValue};
use chrono::{DateTime, Duration, Utc};
use sqlx::{Row, Transaction};
use std::collections::HashMap;
use subtle::ConstantTimeEq;
use uuid::Uuid;

const MAX_IDEMPOTENCY_KEY_LEN: usize = 128;
const BUS_BOOKING_SECRET_HEADER: &str = "x-bus-payments-internal-secret";
const ALLOWED_ROLES: &[&str] = &[
    "merchant",
    "qr_seller",
    "cashout_operator",
    "admin",
    "superadmin",
    "seller",
    "ops",
    "operator_bus",
];

fn parse_bus_booking_action(raw: Option<&str>) -> Result<&'static str, ApiError> {
    let action = raw
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or("charge")
        .to_ascii_lowercase();
    match action.as_str() {
        "charge" => Ok("charge"),
        "refund" => Ok("refund"),
        _ => Err(ApiError::bad_request("action must be charge or refund")),
    }
}

fn require_bus_booking_secret(state: &AppState, headers: &HeaderMap) -> ApiResult<()> {
    if state
        .bus_payments_internal_secret
        .as_deref()
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .is_none()
    {
        return Err(ApiError::forbidden("internal caller not allowed"));
    }
    let expected = state
        .bus_payments_internal_secret
        .as_deref()
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .unwrap_or_default();

    let provided = headers
        .get(BUS_BOOKING_SECRET_HEADER)
        .and_then(|v| v.to_str().ok())
        .map(str::trim)
        .unwrap_or("");
    if provided.is_empty() || provided.as_bytes().ct_eq(expected.as_bytes()).unwrap_u8() != 1 {
        return Err(ApiError::forbidden("internal caller not allowed"));
    }
    Ok(())
}

fn header_value(raw: &str, field: &str) -> Result<HeaderValue, ApiError> {
    HeaderValue::from_str(raw).map_err(|_| ApiError::bad_request(format!("invalid {field}")))
}

pub async fn health(State(state): State<AppState>) -> axum::Json<HealthOut> {
    axum::Json(HealthOut {
        status: "ok",
        env: state.env_name.clone(),
        service: "Payments API",
        version: env!("CARGO_PKG_VERSION"),
    })
}

pub async fn ensure_fee_wallet(state: &AppState) -> ApiResult<()> {
    let account_id = state
        .fee_wallet_account_id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let phone = state.fee_wallet_phone.trim();
    if account_id.is_none() && phone.is_empty() {
        return Ok(());
    }

    let mut tx = state.pool.begin().await.map_err(|e| {
        tracing::error!(error = %e, "db begin fee wallet tx failed");
        ApiError::internal("database error")
    })?;

    let _ = ensure_fee_wallet_tx(&mut tx, state).await?;

    tx.commit().await.map_err(|e| {
        tracing::error!(error = %e, "db commit fee wallet tx failed");
        ApiError::internal("database error")
    })?;

    Ok(())
}

fn valid_e164(phone: &str) -> bool {
    let p = phone.trim();
    if p.len() < 9 || p.len() > 16 || !p.starts_with('+') {
        return false;
    }
    let digits = &p[1..];
    if digits.starts_with('0') || !digits.chars().all(|c| c.is_ascii_digit()) {
        return false;
    }
    true
}

fn normalize_account_id(raw: &str) -> Result<String, ApiError> {
    let id = raw.trim().to_ascii_lowercase();
    if id.len() != 64 || !id.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(ApiError::bad_request("invalid account_id format"));
    }
    Ok(id)
}

fn normalize_alias(alias: &str) -> Result<String, ApiError> {
    let h = alias.trim().trim_start_matches('@').to_lowercase();
    let mut chars = h.chars();
    let Some(first) = chars.next() else {
        return Err(ApiError::bad_request("invalid alias"));
    };
    if !first.is_ascii_lowercase() {
        return Err(ApiError::bad_request("invalid alias"));
    }
    if h.len() < 2 || h.len() > 20 {
        return Err(ApiError::bad_request("invalid alias"));
    }
    if !h
        .chars()
        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_' || c == '.')
    {
        return Err(ApiError::bad_request("invalid alias"));
    }
    Ok(h)
}

fn now_iso() -> String {
    Utc::now().to_rfc3339()
}

fn for_update_suffix(state: &AppState) -> &'static str {
    let _ = state;
    " FOR UPDATE"
}

fn normalize_limit(raw: Option<i64>, default: i64, min: i64, max: i64) -> i64 {
    raw.unwrap_or(default).clamp(min, max)
}

fn idempotency_key(headers: &HeaderMap) -> Result<Option<String>, ApiError> {
    let Some(v) = headers.get("Idempotency-Key") else {
        return Ok(None);
    };
    let Ok(vs) = v.to_str() else {
        return Err(ApiError::bad_request("invalid Idempotency-Key"));
    };
    let k = vs.trim();
    if k.is_empty() {
        return Ok(None);
    }
    if k.len() > MAX_IDEMPOTENCY_KEY_LEN {
        return Err(ApiError::bad_request("Idempotency-Key too long"));
    }
    Ok(Some(k.to_string()))
}

fn parse_expires(raw: Option<String>) -> Option<DateTime<Utc>> {
    raw.as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .and_then(|s| DateTime::parse_from_rfc3339(s).ok())
        .map(|dt| dt.with_timezone(&Utc))
}

fn request_status_with_expiry(status: String, expires_at: Option<String>) -> String {
    if status == "pending" {
        if let Some(exp) = parse_expires(expires_at) {
            if exp < Utc::now() {
                return "expired".to_string();
            }
        }
    }
    status
}

async fn ensure_fee_wallet_tx(
    tx: &mut Transaction<'_, sqlx::Postgres>,
    state: &AppState,
) -> ApiResult<String> {
    let users = state.table("users");
    let wallets = state.table("wallets");

    let cfg_account_id = match state
        .fee_wallet_account_id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        Some(v) => Some(normalize_account_id(v)?),
        None => None,
    };
    let cfg_phone = state.fee_wallet_phone.trim();
    let cfg_phone = if cfg_phone.is_empty() {
        None
    } else {
        Some(cfg_phone)
    };
    if cfg_account_id.is_none() && cfg_phone.is_none() {
        return Err(ApiError::internal("fee wallet not configured"));
    }

    let user_row = if let Some(account_id) = cfg_account_id.as_deref() {
        sqlx::query(&format!(
            "SELECT id,account_id,phone FROM {users} WHERE account_id=$1"
        ))
        .bind(account_id)
        .fetch_optional(&mut **tx)
        .await
    } else {
        sqlx::query(&format!(
            "SELECT id,account_id,phone FROM {users} WHERE phone=$1"
        ))
        .bind(cfg_phone.unwrap_or(""))
        .fetch_optional(&mut **tx)
        .await
    }
    .map_err(|e| {
        tracing::error!(error = %e, "db fee wallet user lookup failed");
        ApiError::internal("database error")
    })?;

    let (user_id, account_id) = if let Some(row) = user_row {
        let id: String = row.try_get("id").unwrap_or_default();
        let mut account_id: Option<String> = row.try_get("account_id").unwrap_or(None);
        if account_id
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .is_none()
        {
            // Backfill missing account_id for legacy fee wallet records.
            let fresh = format!("{}{}", Uuid::new_v4().simple(), Uuid::new_v4().simple());
            let _ = sqlx::query(&format!(
                "UPDATE {users} SET account_id=$1 WHERE id=$2 AND (account_id IS NULL OR account_id='')"
            ))
            .bind(&fresh)
            .bind(&id)
            .execute(&mut **tx)
            .await;
            account_id = Some(fresh);
        }
        (id, account_id.unwrap_or_default())
    } else {
        let uid = Uuid::new_v4().to_string();
        let account_id = cfg_account_id
            .unwrap_or_else(|| format!("{}{}", Uuid::new_v4().simple(), Uuid::new_v4().simple()));
        sqlx::query(&format!(
            "INSERT INTO {users} (id,account_id,phone,kyc_level) VALUES ($1,$2,$3,$4)"
        ))
        .bind(&uid)
        .bind(&account_id)
        .bind(cfg_phone)
        .bind(2i64)
        .execute(&mut **tx)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "db fee wallet user create failed");
            ApiError::internal("database error")
        })?;
        (uid, account_id)
    };

    let wallet_row = sqlx::query(&format!("SELECT id FROM {wallets} WHERE user_id=$1"))
        .bind(&user_id)
        .fetch_optional(&mut **tx)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "db fee wallet lookup failed");
            ApiError::internal("database error")
        })?;

    if let Some(row) = wallet_row {
        return Ok(row.try_get("id").unwrap_or_default());
    }

    let wallet_id = Uuid::new_v4().to_string();
    sqlx::query(&format!(
        "INSERT INTO {wallets} (id,user_id,balance_cents,currency) VALUES ($1,$2,$3,$4)"
    ))
    .bind(&wallet_id)
    .bind(&user_id)
    .bind(0i64)
    .bind(&state.default_currency)
    .execute(&mut **tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db fee wallet create failed");
        ApiError::internal("database error")
    })?;

    let _ = account_id;
    Ok(wallet_id)
}

pub async fn create_user(
    State(state): State<AppState>,
    axum::Json(body): axum::Json<CreateUserReq>,
) -> ApiResult<axum::Json<UserResp>> {
    let account_id = normalize_account_id(&body.account_id)?;
    let phone = body
        .phone
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(ToString::to_string);
    if let Some(p) = phone.as_deref() {
        if !valid_e164(p) {
            return Err(ApiError::bad_request("invalid phone format"));
        }
    }

    let users = state.table("users");
    let wallets = state.table("wallets");
    let roles = state.table("roles");

    let mut tx = state.pool.begin().await.map_err(|e| {
        tracing::error!(error = %e, "db begin create_user failed");
        ApiError::internal("database error")
    })?;

    let u_row = sqlx::query(&format!(
        "SELECT id,account_id,phone FROM {users} WHERE account_id=$1"
    ))
    .bind(&account_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db create_user lookup failed");
        ApiError::internal("database error")
    })?;

    let u_row = if u_row.is_some() {
        u_row
    } else if let Some(p) = phone.as_deref() {
        sqlx::query(&format!(
            "SELECT id,account_id,phone FROM {users} WHERE phone=$1"
        ))
        .bind(p)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "db create_user lookup failed");
            ApiError::internal("database error")
        })?
    } else {
        None
    };

    let user_id = if let Some(r) = u_row {
        let id: String = r.try_get("id").unwrap_or_default();
        let existing_account_id: Option<String> = r.try_get("account_id").unwrap_or(None);
        let existing_account_id = existing_account_id
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(ToString::to_string);

        // If the user was found via phone, migrate the row to account_id.
        if existing_account_id.is_none() {
            let _ = sqlx::query(&format!(
                "UPDATE {users} SET account_id=$1 WHERE id=$2 AND (account_id IS NULL OR account_id='')"
            ))
            .bind(&account_id)
            .bind(&id)
            .execute(&mut *tx)
            .await;
        } else if existing_account_id.as_deref() != Some(account_id.as_str()) {
            return Err(ApiError::conflict("account_id does not match phone owner"));
        }

        // Best-effort: if a legacy account did not store phone, attach it once.
        if let Some(p) = phone.as_deref() {
            let existing_phone: Option<String> = r.try_get("phone").unwrap_or(None);
            if existing_phone
                .as_deref()
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .is_none()
            {
                let updated = sqlx::query(&format!(
                    "UPDATE {users} SET phone=$1 WHERE id=$2 AND phone IS NULL"
                ))
                .bind(p)
                .bind(&id)
                .execute(&mut *tx)
                .await
                .map_err(|e| {
                    tracing::error!(error = %e, "db create_user phone attach failed");
                    ApiError::internal("database error")
                })?
                .rows_affected();
                if updated == 0 {
                    // Someone else may have claimed the phone concurrently.
                    let owned = sqlx::query(&format!(
                        "SELECT 1 FROM {users} WHERE id=$1 AND phone=$2 LIMIT 1"
                    ))
                    .bind(&id)
                    .bind(p)
                    .fetch_optional(&mut *tx)
                    .await
                    .ok()
                    .flatten()
                    .is_some();
                    if !owned {
                        return Err(ApiError::conflict("phone already in use"));
                    }
                }
            }
        }

        // Best-effort migration: attach account_id to any legacy phone-keyed roles.
        if let Some(p) = phone.as_deref() {
            let _ = sqlx::query(&format!(
                "UPDATE {roles} SET account_id=$1 WHERE phone=$2 AND (account_id IS NULL OR account_id='')"
            ))
            .bind(&account_id)
            .bind(p)
            .execute(&mut *tx)
            .await;
        }
        id
    } else {
        let uid = Uuid::new_v4().to_string();
        sqlx::query(&format!(
            "INSERT INTO {users} (id,account_id,phone,kyc_level) VALUES ($1,$2,$3,$4)"
        ))
        .bind(&uid)
        .bind(&account_id)
        .bind(phone.as_deref())
        .bind(0i64)
        .execute(&mut *tx)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "db create_user insert failed");
            ApiError::internal("database error")
        })?;
        uid
    };

    let w_row = sqlx::query(&format!(
        "SELECT id,balance_cents,currency FROM {wallets} WHERE user_id=$1"
    ))
    .bind(&user_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db create_user wallet lookup failed");
        ApiError::internal("database error")
    })?;

    let (wallet_id, balance_cents, currency) = if let Some(r) = w_row {
        (
            r.try_get("id").unwrap_or_default(),
            r.try_get("balance_cents").unwrap_or(0i64),
            r.try_get("currency")
                .unwrap_or_else(|_| state.default_currency.clone()),
        )
    } else {
        let wid = Uuid::new_v4().to_string();
        sqlx::query(&format!(
            "INSERT INTO {wallets} (id,user_id,balance_cents,currency) VALUES ($1,$2,$3,$4)"
        ))
        .bind(&wid)
        .bind(&user_id)
        .bind(0i64)
        .bind(&state.default_currency)
        .execute(&mut *tx)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "db create_user wallet insert failed");
            ApiError::internal("database error")
        })?;
        (wid, 0, state.default_currency.clone())
    };

    tx.commit().await.map_err(|e| {
        tracing::error!(error = %e, "db create_user commit failed");
        ApiError::internal("database error")
    })?;

    Ok(axum::Json(UserResp {
        user_id,
        wallet_id,
        account_id: Some(account_id),
        phone,
        balance_cents,
        currency,
    }))
}

pub async fn get_wallet(
    Path(wallet_id): Path<String>,
    State(state): State<AppState>,
) -> ApiResult<axum::Json<WalletResp>> {
    let wallet_id = wallet_id.trim().to_string();
    if wallet_id.is_empty() {
        return Err(ApiError::bad_request("wallet_id required"));
    }

    let wallets = state.table("wallets");
    let row = sqlx::query(&format!(
        "SELECT id,balance_cents,currency FROM {wallets} WHERE id=$1"
    ))
    .bind(&wallet_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db get_wallet failed");
        ApiError::internal("database error")
    })?
    .ok_or_else(|| ApiError::not_found("Wallet not found"))?;

    Ok(axum::Json(WalletResp {
        wallet_id: row.try_get("id").unwrap_or_default(),
        balance_cents: row.try_get("balance_cents").unwrap_or(0),
        currency: row
            .try_get("currency")
            .unwrap_or_else(|_| state.default_currency.clone()),
    }))
}

pub async fn topup(
    Path(wallet_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<TopupReq>,
) -> ApiResult<axum::Json<WalletResp>> {
    let wallet_id = wallet_id.trim().to_string();
    if wallet_id.is_empty() {
        return Err(ApiError::bad_request("wallet_id required"));
    }
    if body.amount_cents <= 0 {
        return Err(ApiError::bad_request("amount_cents must be > 0"));
    }

    if !state.allow_direct_topup {
        return Err(ApiError::forbidden("Topup disabled"));
    }

    let ikey = idempotency_key(&headers)?;
    let idempotency = state.table("idempotency");

    if let Some(k) = ikey.as_deref() {
        let rec = sqlx::query(&format!("SELECT endpoint FROM {idempotency} WHERE ikey=$1"))
            .bind(k)
            .fetch_optional(&state.pool)
            .await
            .map_err(|e| {
                tracing::error!(error = %e, "db topup idempotency lookup failed");
                ApiError::internal("database error")
            })?;

        if let Some(r) = rec {
            let endpoint: String = r.try_get("endpoint").unwrap_or_default();
            if endpoint != "topup" {
                return Err(ApiError::conflict(
                    "Idempotency-Key reused for a different endpoint",
                ));
            }
            let wallets = state.table("wallets");
            let w = sqlx::query(&format!(
                "SELECT id,balance_cents,currency FROM {wallets} WHERE id=$1"
            ))
            .bind(&wallet_id)
            .fetch_optional(&state.pool)
            .await
            .map_err(|e| {
                tracing::error!(error = %e, "db topup wallet lookup failed");
                ApiError::internal("database error")
            })?
            .ok_or_else(|| ApiError::not_found("Wallet not found"))?;

            return Ok(axum::Json(WalletResp {
                wallet_id: w.try_get("id").unwrap_or_default(),
                balance_cents: w.try_get("balance_cents").unwrap_or(0),
                currency: w
                    .try_get("currency")
                    .unwrap_or_else(|_| state.default_currency.clone()),
            }));
        }
    }

    let wallets = state.table("wallets");
    let txns = state.table("txns");
    let ledger = state.table("ledger_entries");

    let mut tx = state.pool.begin().await.map_err(|e| {
        tracing::error!(error = %e, "db begin topup failed");
        ApiError::internal("database error")
    })?;

    let row = sqlx::query(&format!(
        "SELECT id,balance_cents,currency FROM {wallets} WHERE id=$1{}",
        for_update_suffix(&state)
    ))
    .bind(&wallet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db topup wallet lock failed");
        ApiError::internal("database error")
    })?
    .ok_or_else(|| ApiError::not_found("Wallet not found"))?;

    let old_balance: i64 = row.try_get("balance_cents").unwrap_or(0);
    let new_balance = old_balance
        .checked_add(body.amount_cents)
        .ok_or_else(|| ApiError::bad_request("balance overflow"))?;

    sqlx::query(&format!(
        "UPDATE {wallets} SET balance_cents=$1 WHERE id=$2"
    ))
    .bind(new_balance)
    .bind(&wallet_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db topup wallet update failed");
        ApiError::internal("database error")
    })?;

    let txn_id = Uuid::new_v4().to_string();
    let now = now_iso();
    sqlx::query(&format!(
        "INSERT INTO {txns} (id,from_wallet_id,to_wallet_id,amount_cents,kind,fee_cents,created_at) VALUES ($1,$2,$3,$4,$5,$6,$7)"
    ))
    .bind(&txn_id)
    .bind(Option::<String>::None)
    .bind(&wallet_id)
    .bind(body.amount_cents)
    .bind("topup")
    .bind(0i64)
    .bind(&now)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db topup txn insert failed");
        ApiError::internal("database error")
    })?;

    sqlx::query(&format!(
        "INSERT INTO {ledger} (id,wallet_id,amount_cents,txn_id,description,created_at) VALUES ($1,$2,$3,$4,$5,$6)"
    ))
    .bind(Uuid::new_v4().to_string())
    .bind(&wallet_id)
    .bind(body.amount_cents)
    .bind(&txn_id)
    .bind("topup")
    .bind(&now)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db topup ledger credit insert failed");
        ApiError::internal("database error")
    })?;

    sqlx::query(&format!(
        "INSERT INTO {ledger} (id,wallet_id,amount_cents,txn_id,description,created_at) VALUES ($1,$2,$3,$4,$5,$6)"
    ))
    .bind(Uuid::new_v4().to_string())
    .bind(Option::<String>::None)
    .bind(-body.amount_cents)
    .bind(&txn_id)
    .bind("topup_external")
    .bind(&now)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db topup ledger external insert failed");
        ApiError::internal("database error")
    })?;

    if let Some(k) = ikey {
        let _ = sqlx::query(&format!(
            "INSERT INTO {idempotency} (id,ikey,endpoint,txn_id,amount_cents,currency,wallet_id,balance_cents,created_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)"
        ))
        .bind(Uuid::new_v4().to_string())
        .bind(k)
        .bind("topup")
        .bind(&txn_id)
        .bind(body.amount_cents)
        .bind(state.default_currency.clone())
        .bind(&wallet_id)
        .bind(new_balance)
        .bind(&now)
        .execute(&mut *tx)
        .await;
    }

    tx.commit().await.map_err(|e| {
        tracing::error!(error = %e, "db topup commit failed");
        ApiError::internal("database error")
    })?;

    Ok(axum::Json(WalletResp {
        wallet_id,
        balance_cents: new_balance,
        currency: state.default_currency.clone(),
    }))
}

pub async fn transfer(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<TransferReq>,
) -> ApiResult<axum::Json<WalletResp>> {
    let from_wallet_id = body.from_wallet_id.trim().to_string();
    if from_wallet_id.is_empty() {
        return Err(ApiError::bad_request("from_wallet_id required"));
    }
    if body.amount_cents <= 0 {
        return Err(ApiError::bad_request("amount_cents must be > 0"));
    }

    let mut to_wallet_id = body
        .to_wallet_id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string());

    if to_wallet_id.is_none() {
        if let Some(alias) = body
            .to_alias
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
        {
            let handle = normalize_alias(alias)?;
            let aliases = state.table("aliases");
            let row = sqlx::query(&format!(
                "SELECT wallet_id FROM {aliases} WHERE handle=$1 AND status='active'"
            ))
            .bind(&handle)
            .fetch_optional(&state.pool)
            .await
            .map_err(|e| {
                tracing::error!(error = %e, "db transfer alias resolve failed");
                ApiError::internal("database error")
            })?
            .ok_or_else(|| ApiError::not_found("Alias not found"))?;
            to_wallet_id = Some(row.try_get("wallet_id").unwrap_or_default());
        }
    }

    let to_wallet_id =
        to_wallet_id.ok_or_else(|| ApiError::bad_request("Missing destination wallet or alias"))?;

    if from_wallet_id == to_wallet_id {
        return Err(ApiError::bad_request("Cannot transfer to same wallet"));
    }

    let ikey = idempotency_key(&headers)?;
    let idempotency = state.table("idempotency");

    if let Some(k) = ikey.as_deref() {
        let rec = sqlx::query(&format!(
            "SELECT endpoint,wallet_id,balance_cents,currency FROM {idempotency} WHERE ikey=$1"
        ))
        .bind(k)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "db transfer idempotency lookup failed");
            ApiError::internal("database error")
        })?;

        if let Some(r) = rec {
            let endpoint: String = r.try_get("endpoint").unwrap_or_default();
            if endpoint != "transfer" {
                return Err(ApiError::conflict(
                    "Idempotency-Key reused for a different endpoint",
                ));
            }

            let wallet_id: Option<String> = r.try_get("wallet_id").unwrap_or(None);
            let Some(wid) = wallet_id else {
                return Err(ApiError::internal("idempotency record missing wallet_id"));
            };

            let wallets = state.table("wallets");
            let row = sqlx::query(&format!(
                "SELECT id,balance_cents,currency FROM {wallets} WHERE id=$1"
            ))
            .bind(&wid)
            .fetch_optional(&state.pool)
            .await
            .map_err(|e| {
                tracing::error!(error = %e, "db transfer idempotent wallet lookup failed");
                ApiError::internal("database error")
            })?
            .ok_or_else(|| ApiError::not_found("Wallet not found"))?;

            return Ok(axum::Json(WalletResp {
                wallet_id: row.try_get("id").unwrap_or_default(),
                balance_cents: row
                    .try_get("balance_cents")
                    .or_else(|_| r.try_get("balance_cents"))
                    .unwrap_or(0),
                currency: row
                    .try_get("currency")
                    .or_else(|_| r.try_get("currency"))
                    .unwrap_or_else(|_| state.default_currency.clone()),
            }));
        }
    }

    let wallets = state.table("wallets");
    let txns = state.table("txns");
    let ledger = state.table("ledger_entries");

    let mut tx = state.pool.begin().await.map_err(|e| {
        tracing::error!(error = %e, "db begin transfer failed");
        ApiError::internal("database error")
    })?;

    let from_row = sqlx::query(&format!(
        "SELECT id,user_id,balance_cents,currency FROM {wallets} WHERE id=$1{}",
        for_update_suffix(&state)
    ))
    .bind(&from_wallet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db transfer from wallet lock failed");
        ApiError::internal("database error")
    })?
    .ok_or_else(|| ApiError::not_found("Wallet not found"))?;

    let to_row = sqlx::query(&format!(
        "SELECT id,user_id,balance_cents,currency FROM {wallets} WHERE id=$1{}",
        for_update_suffix(&state)
    ))
    .bind(&to_wallet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db transfer to wallet lock failed");
        ApiError::internal("database error")
    })?
    .ok_or_else(|| ApiError::not_found("Wallet not found"))?;

    let from_balance: i64 = from_row.try_get("balance_cents").unwrap_or(0);
    let to_balance: i64 = to_row.try_get("balance_cents").unwrap_or(0);
    let from_currency: String = from_row
        .try_get("currency")
        .unwrap_or_else(|_| state.default_currency.clone());
    let to_currency: String = to_row
        .try_get("currency")
        .unwrap_or_else(|_| state.default_currency.clone());

    if from_currency != to_currency {
        return Err(ApiError::bad_request("currency mismatch"));
    }

    if from_balance < body.amount_cents {
        return Err(ApiError::bad_request("Insufficient funds"));
    }

    let fee_cents = (body.amount_cents * state.merchant_fee_bps) / 10_000;
    let net_cents = body.amount_cents - fee_cents;
    if net_cents < 0 {
        return Err(ApiError::bad_request("Amount too small for fees"));
    }

    let new_from_balance = from_balance - body.amount_cents;
    let mut new_to_balance = to_balance + net_cents;

    sqlx::query(&format!(
        "UPDATE {wallets} SET balance_cents=$1 WHERE id=$2"
    ))
    .bind(new_from_balance)
    .bind(&from_wallet_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db transfer from update failed");
        ApiError::internal("database error")
    })?;

    sqlx::query(&format!(
        "UPDATE {wallets} SET balance_cents=$1 WHERE id=$2"
    ))
    .bind(new_to_balance)
    .bind(&to_wallet_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db transfer to update failed");
        ApiError::internal("database error")
    })?;

    let fee_wallet_id = if fee_cents > 0 {
        let fid = ensure_fee_wallet_tx(&mut tx, &state).await?;
        let fee_row = sqlx::query(&format!(
            "SELECT balance_cents FROM {wallets} WHERE id=$1{}",
            for_update_suffix(&state)
        ))
        .bind(&fid)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "db transfer fee wallet lock failed");
            ApiError::internal("database error")
        })?
        .ok_or_else(|| ApiError::internal("fee wallet missing"))?;

        let fee_old: i64 = fee_row.try_get("balance_cents").unwrap_or(0);
        let fee_new = fee_old + fee_cents;
        sqlx::query(&format!(
            "UPDATE {wallets} SET balance_cents=$1 WHERE id=$2"
        ))
        .bind(fee_new)
        .bind(&fid)
        .execute(&mut *tx)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "db transfer fee wallet update failed");
            ApiError::internal("database error")
        })?;

        if fid == to_wallet_id {
            new_to_balance = fee_new;
        }

        Some(fid)
    } else {
        None
    };

    let txn_id = Uuid::new_v4().to_string();
    let now = now_iso();

    sqlx::query(&format!(
        "INSERT INTO {txns} (id,from_wallet_id,to_wallet_id,amount_cents,kind,fee_cents,created_at) VALUES ($1,$2,$3,$4,$5,$6,$7)"
    ))
    .bind(&txn_id)
    .bind(&from_wallet_id)
    .bind(&to_wallet_id)
    .bind(body.amount_cents)
    .bind("transfer")
    .bind(fee_cents)
    .bind(&now)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db transfer txn insert failed");
        ApiError::internal("database error")
    })?;

    let merchant = headers
        .get("X-Merchant")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.trim())
        .filter(|s| !s.is_empty());
    let reference = headers
        .get("X-Ref")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.trim())
        .filter(|s| !s.is_empty());
    let mut meta_parts = Vec::new();
    if let Some(m) = merchant {
        meta_parts.push(format!("m={m}"));
    }
    if let Some(r) = reference {
        meta_parts.push(format!("ref={r}"));
    }
    let meta_suffix = if meta_parts.is_empty() {
        "".to_string()
    } else {
        format!(" {}", meta_parts.join(" "))
    };

    sqlx::query(&format!(
        "INSERT INTO {ledger} (id,wallet_id,amount_cents,txn_id,description,created_at) VALUES ($1,$2,$3,$4,$5,$6)"
    ))
    .bind(Uuid::new_v4().to_string())
    .bind(&from_wallet_id)
    .bind(-body.amount_cents)
    .bind(&txn_id)
    .bind(format!("transfer_debit{meta_suffix}"))
    .bind(&now)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db transfer ledger debit insert failed");
        ApiError::internal("database error")
    })?;

    sqlx::query(&format!(
        "INSERT INTO {ledger} (id,wallet_id,amount_cents,txn_id,description,created_at) VALUES ($1,$2,$3,$4,$5,$6)"
    ))
    .bind(Uuid::new_v4().to_string())
    .bind(&to_wallet_id)
    .bind(net_cents)
    .bind(&txn_id)
    .bind(format!("transfer_credit{meta_suffix}"))
    .bind(&now)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db transfer ledger credit insert failed");
        ApiError::internal("database error")
    })?;

    if let Some(fid) = fee_wallet_id {
        sqlx::query(&format!(
            "INSERT INTO {ledger} (id,wallet_id,amount_cents,txn_id,description,created_at) VALUES ($1,$2,$3,$4,$5,$6)"
        ))
        .bind(Uuid::new_v4().to_string())
        .bind(fid)
        .bind(fee_cents)
        .bind(&txn_id)
        .bind("fee_credit")
        .bind(&now)
        .execute(&mut *tx)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "db transfer ledger fee insert failed");
            ApiError::internal("database error")
        })?;
    }

    if let Some(k) = ikey {
        let _ = sqlx::query(&format!(
            "INSERT INTO {idempotency} (id,ikey,endpoint,txn_id,amount_cents,currency,wallet_id,balance_cents,created_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)"
        ))
        .bind(Uuid::new_v4().to_string())
        .bind(k)
        .bind("transfer")
        .bind(&txn_id)
        .bind(body.amount_cents)
        .bind(to_currency.clone())
        .bind(&to_wallet_id)
        .bind(new_to_balance)
        .bind(&now)
        .execute(&mut *tx)
        .await;
    }

    tx.commit().await.map_err(|e| {
        tracing::error!(error = %e, "db transfer commit failed");
        ApiError::internal("database error")
    })?;

    Ok(axum::Json(WalletResp {
        wallet_id: to_wallet_id,
        balance_cents: new_to_balance,
        currency: to_currency,
    }))
}

pub async fn transfer_bus_booking(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<BusBookingTransferReq>,
) -> ApiResult<axum::Json<WalletResp>> {
    require_bus_booking_secret(&state, &headers)?;

    let booking_id = body.booking_id.trim().to_string();
    if Uuid::parse_str(&booking_id).is_err() {
        return Err(ApiError::bad_request("invalid booking_id"));
    }

    let action = parse_bus_booking_action(body.action.as_deref())?;

    let from_wallet_id = body.from_wallet_id.trim().to_string();
    let to_wallet_id = body.to_wallet_id.trim().to_string();
    if from_wallet_id.is_empty() || to_wallet_id.is_empty() {
        return Err(ApiError::bad_request(
            "from_wallet_id and to_wallet_id required",
        ));
    }
    if body.amount_cents <= 0 {
        return Err(ApiError::bad_request("amount_cents must be > 0"));
    }

    let mut transfer_headers = HeaderMap::new();
    let idem = format!("bus-booking-{action}-{booking_id}");
    transfer_headers.insert("Idempotency-Key", header_value(&idem, "Idempotency-Key")?);
    transfer_headers.insert("X-Merchant", HeaderValue::from_static("bus"));
    let reference = format!("booking-{action}-{booking_id}");
    transfer_headers.insert("X-Ref", header_value(&reference, "X-Ref")?);

    transfer(
        State(state),
        transfer_headers,
        axum::Json(TransferReq {
            from_wallet_id,
            to_wallet_id: Some(to_wallet_id),
            to_alias: None,
            amount_cents: body.amount_cents,
        }),
    )
    .await
}

pub async fn list_txns(
    State(state): State<AppState>,
    Query(params): Query<TxnParams>,
) -> ApiResult<axum::Json<Vec<TxnItem>>> {
    let wallet_id = params.wallet_id.trim().to_string();
    if wallet_id.is_empty() {
        return Err(ApiError::bad_request("wallet_id required"));
    }
    let limit = normalize_limit(params.limit, 50, 1, 200);

    let txns = state.table("txns");
    let rows = sqlx::query(&format!(
        "SELECT id,from_wallet_id,to_wallet_id,amount_cents,fee_cents,kind,created_at FROM {txns} WHERE from_wallet_id=$1 OR to_wallet_id=$1 ORDER BY created_at DESC LIMIT $2"
    ))
    .bind(&wallet_id)
    .bind(limit)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db list_txns failed");
        ApiError::internal("database error")
    })?;

    let mut ids: Vec<String> = Vec::with_capacity(rows.len());
    for r in &rows {
        let id: String = r.try_get("id").unwrap_or_default();
        if !id.is_empty() {
            ids.push(id);
        }
    }

    let ledger = state.table("ledger_entries");
    let mut meta_map: HashMap<String, String> = HashMap::new();
    if !ids.is_empty() {
        let in_clause = make_in_clause(1, ids.len());
        let sql = format!("SELECT txn_id,description FROM {ledger} WHERE txn_id IN {in_clause}");
        let mut q = sqlx::query(&sql);
        for id in &ids {
            q = q.bind(id);
        }
        let meta_rows = q.fetch_all(&state.pool).await.map_err(|e| {
            tracing::error!(error = %e, "db list_txns meta lookup failed");
            ApiError::internal("database error")
        })?;
        for m in meta_rows {
            let tid: Option<String> = m.try_get("txn_id").unwrap_or(None);
            let desc: Option<String> = m.try_get("description").unwrap_or(None);
            if let (Some(tid), Some(desc)) = (tid, desc) {
                meta_map.entry(tid).or_insert(desc);
            }
        }
    }

    let mut out = Vec::with_capacity(rows.len());
    for r in rows {
        let id: String = r.try_get("id").unwrap_or_default();
        out.push(TxnItem {
            id: id.clone(),
            from_wallet_id: r.try_get("from_wallet_id").unwrap_or(None),
            to_wallet_id: r.try_get("to_wallet_id").unwrap_or_default(),
            amount_cents: r.try_get("amount_cents").unwrap_or(0),
            fee_cents: r.try_get("fee_cents").unwrap_or(0),
            kind: r.try_get("kind").unwrap_or_default(),
            created_at: r.try_get("created_at").unwrap_or(None),
            meta: meta_map.get(&id).cloned(),
        });
    }

    Ok(axum::Json(out))
}

pub async fn create_favorite(
    State(state): State<AppState>,
    axum::Json(body): axum::Json<FavoriteCreate>,
) -> ApiResult<axum::Json<FavoriteOut>> {
    let owner_wallet_id = body.owner_wallet_id.trim().to_string();
    let favorite_wallet_id = body.favorite_wallet_id.trim().to_string();
    if owner_wallet_id.is_empty() || favorite_wallet_id.is_empty() {
        return Err(ApiError::bad_request(
            "owner_wallet_id and favorite_wallet_id required",
        ));
    }
    if owner_wallet_id == favorite_wallet_id {
        return Err(ApiError::bad_request("Cannot favorite self"));
    }

    let favorites = state.table("favorites");
    let existing = sqlx::query(&format!(
        "SELECT id,owner_wallet_id,favorite_wallet_id,alias FROM {favorites} WHERE owner_wallet_id=$1 AND favorite_wallet_id=$2"
    ))
    .bind(&owner_wallet_id)
    .bind(&favorite_wallet_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db create_favorite lookup failed");
        ApiError::internal("database error")
    })?;

    if let Some(row) = existing {
        let id: String = row.try_get("id").unwrap_or_default();
        let alias = body
            .alias
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty());
        if let Some(alias) = alias {
            let _ = sqlx::query(&format!("UPDATE {favorites} SET alias=$1 WHERE id=$2"))
                .bind(alias)
                .bind(&id)
                .execute(&state.pool)
                .await;
        }
        return Ok(axum::Json(FavoriteOut {
            id,
            owner_wallet_id,
            favorite_wallet_id,
            alias: alias
                .map(|s| s.to_string())
                .or_else(|| row.try_get("alias").ok().flatten()),
        }));
    }

    let id = Uuid::new_v4().to_string();
    let now = now_iso();
    let alias = body
        .alias
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string());

    sqlx::query(&format!(
        "INSERT INTO {favorites} (id,owner_wallet_id,favorite_wallet_id,alias,created_at) VALUES ($1,$2,$3,$4,$5)"
    ))
    .bind(&id)
    .bind(&owner_wallet_id)
    .bind(&favorite_wallet_id)
    .bind(&alias)
    .bind(&now)
    .execute(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db create_favorite insert failed");
        ApiError::internal("database error")
    })?;

    Ok(axum::Json(FavoriteOut {
        id,
        owner_wallet_id,
        favorite_wallet_id,
        alias,
    }))
}

pub async fn list_favorites(
    State(state): State<AppState>,
    Query(params): Query<FavoritesParams>,
) -> ApiResult<axum::Json<Vec<FavoriteOut>>> {
    let owner_wallet_id = params.owner_wallet_id.trim().to_string();
    if owner_wallet_id.is_empty() {
        return Err(ApiError::bad_request("owner_wallet_id required"));
    }

    let favorites = state.table("favorites");
    let rows = sqlx::query(&format!(
        "SELECT id,owner_wallet_id,favorite_wallet_id,alias FROM {favorites} WHERE owner_wallet_id=$1 ORDER BY created_at DESC"
    ))
    .bind(&owner_wallet_id)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db list_favorites failed");
        ApiError::internal("database error")
    })?;

    let mut out = Vec::with_capacity(rows.len());
    for r in rows {
        out.push(FavoriteOut {
            id: r.try_get("id").unwrap_or_default(),
            owner_wallet_id: r.try_get("owner_wallet_id").unwrap_or_default(),
            favorite_wallet_id: r.try_get("favorite_wallet_id").unwrap_or_default(),
            alias: r.try_get("alias").unwrap_or(None),
        });
    }

    Ok(axum::Json(out))
}

pub async fn delete_favorite(
    Path(fid): Path<String>,
    State(state): State<AppState>,
) -> ApiResult<axum::Json<OkOut>> {
    let fid = fid.trim().to_string();
    if fid.is_empty() {
        return Err(ApiError::bad_request("favorite id required"));
    }

    let favorites = state.table("favorites");
    let res = sqlx::query(&format!("DELETE FROM {favorites} WHERE id=$1"))
        .bind(&fid)
        .execute(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "db delete_favorite failed");
            ApiError::internal("database error")
        })?;

    if res.rows_affected() == 0 {
        return Err(ApiError::not_found("not found"));
    }

    Ok(axum::Json(OkOut { ok: true }))
}

pub async fn create_request(
    State(state): State<AppState>,
    axum::Json(body): axum::Json<PaymentRequestCreate>,
) -> ApiResult<axum::Json<PaymentRequestOut>> {
    let from_wallet_id = body.from_wallet_id.trim().to_string();
    if from_wallet_id.is_empty() {
        return Err(ApiError::bad_request("from_wallet_id required"));
    }
    if body.amount_cents <= 0 {
        return Err(ApiError::bad_request("amount_cents must be > 0"));
    }

    let mut to_wallet_id = body
        .to_wallet_id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(ToString::to_string)
        .unwrap_or_default();
    if to_wallet_id.is_empty() {
        if let Some(alias_raw) = body
            .to_alias
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
        {
            let handle = normalize_alias(alias_raw)?;
            let aliases = state.table("aliases");
            let row = sqlx::query(&format!(
                "SELECT wallet_id FROM {aliases} WHERE handle=$1 AND status='active'"
            ))
            .bind(&handle)
            .fetch_optional(&state.pool)
            .await
            .map_err(|e| {
                tracing::error!(error = %e, "db create_request alias resolve failed");
                ApiError::internal("database error")
            })?;
            if let Some(row) = row {
                to_wallet_id = row.try_get::<String, _>("wallet_id").unwrap_or_default();
            }
            if to_wallet_id.trim().is_empty() {
                // Keep this intentionally generic to reduce alias/wallet enumeration.
                return Err(ApiError::not_found("Wallet not found"));
            }
        } else {
            return Err(ApiError::bad_request("to_wallet_id or to_alias required"));
        }
    }
    if from_wallet_id == to_wallet_id {
        return Err(ApiError::bad_request("cannot request payment from self"));
    }

    if let Some(expires_in) = body.expires_in_secs {
        if !(60..=7 * 24 * 3600).contains(&expires_in) {
            return Err(ApiError::bad_request("expires_in_secs out of range"));
        }
    }

    let wallets = state.table("wallets");
    let requests = state.table("payment_requests");

    let from_exists = sqlx::query(&format!("SELECT id,currency FROM {wallets} WHERE id=$1"))
        .bind(&from_wallet_id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "db create_request from lookup failed");
            ApiError::internal("database error")
        })?;
    let to_exists = sqlx::query(&format!("SELECT id FROM {wallets} WHERE id=$1"))
        .bind(&to_wallet_id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "db create_request to lookup failed");
            ApiError::internal("database error")
        })?;

    let Some(from_row) = from_exists else {
        return Err(ApiError::not_found("Wallet not found"));
    };
    if to_exists.is_none() {
        return Err(ApiError::not_found("Wallet not found"));
    }

    let currency: String = from_row
        .try_get("currency")
        .unwrap_or_else(|_| state.default_currency.clone());

    let id = Uuid::new_v4().to_string();
    let now = now_iso();
    #[allow(clippy::manual_map)]
    let expires_at = if let Some(secs) = body.expires_in_secs {
        Some((Utc::now() + Duration::seconds(secs)).to_rfc3339())
    } else {
        None
    };

    sqlx::query(&format!(
        "INSERT INTO {requests} (id,from_wallet_id,to_wallet_id,amount_cents,currency,message,status,created_at,expires_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)"
    ))
    .bind(&id)
    .bind(&from_wallet_id)
    .bind(&to_wallet_id)
    .bind(body.amount_cents)
    .bind(&currency)
    .bind(body.message.as_deref().map(str::trim).filter(|s| !s.is_empty()))
    .bind("pending")
    .bind(&now)
    .bind(&expires_at)
    .execute(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db create_request insert failed");
        ApiError::internal("database error")
    })?;

    Ok(axum::Json(PaymentRequestOut {
        id,
        from_wallet_id,
        to_wallet_id,
        amount_cents: body.amount_cents,
        currency,
        message: body.message.and_then(|m| {
            let m = m.trim().to_string();
            if m.is_empty() {
                None
            } else {
                Some(m)
            }
        }),
        status: "pending".to_string(),
    }))
}

pub async fn list_requests(
    State(state): State<AppState>,
    Query(params): Query<RequestsParams>,
) -> ApiResult<axum::Json<Vec<PaymentRequestOut>>> {
    let wallet_id = params.wallet_id.trim().to_string();
    if wallet_id.is_empty() {
        return Err(ApiError::bad_request("wallet_id required"));
    }
    let kind = params
        .kind
        .as_deref()
        .map(str::trim)
        .unwrap_or("")
        .to_lowercase();
    let limit = normalize_limit(params.limit, 100, 1, 500);

    let requests = state.table("payment_requests");
    let (sql, bind_kind) = match kind.as_str() {
        "incoming" => (
            format!(
                "SELECT id,from_wallet_id,to_wallet_id,amount_cents,currency,message,status,expires_at FROM {requests} WHERE to_wallet_id=$1 ORDER BY created_at DESC LIMIT $2"
            ),
            "incoming",
        ),
        "outgoing" => (
            format!(
                "SELECT id,from_wallet_id,to_wallet_id,amount_cents,currency,message,status,expires_at FROM {requests} WHERE from_wallet_id=$1 ORDER BY created_at DESC LIMIT $2"
            ),
            "outgoing",
        ),
        _ => (
            format!(
                "SELECT id,from_wallet_id,to_wallet_id,amount_cents,currency,message,status,expires_at FROM {requests} WHERE to_wallet_id=$1 OR from_wallet_id=$1 ORDER BY created_at DESC LIMIT $2"
            ),
            "all",
        ),
    };

    let rows = sqlx::query(&sql)
        .bind(&wallet_id)
        .bind(limit)
        .fetch_all(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, kind = bind_kind, "db list_requests failed");
            ApiError::internal("database error")
        })?;

    let mut out = Vec::with_capacity(rows.len());
    for r in rows {
        let id: String = r.try_get("id").unwrap_or_default();
        let status_raw: String = r
            .try_get("status")
            .unwrap_or_else(|_| "pending".to_string());
        let expires_at: Option<String> = r.try_get("expires_at").unwrap_or(None);
        let status = request_status_with_expiry(status_raw.clone(), expires_at.clone());

        if status == "expired" && status_raw == "pending" {
            let _ = sqlx::query(&format!(
                "UPDATE {requests} SET status='expired' WHERE id=$1"
            ))
            .bind(&id)
            .execute(&state.pool)
            .await;
        }

        out.push(PaymentRequestOut {
            id,
            from_wallet_id: r.try_get("from_wallet_id").unwrap_or_default(),
            to_wallet_id: r.try_get("to_wallet_id").unwrap_or_default(),
            amount_cents: r.try_get("amount_cents").unwrap_or(0),
            currency: r
                .try_get("currency")
                .unwrap_or_else(|_| state.default_currency.clone()),
            message: r.try_get("message").unwrap_or(None),
            status,
        });
    }

    Ok(axum::Json(out))
}

pub async fn cancel_request(
    Path(rid): Path<String>,
    State(state): State<AppState>,
) -> ApiResult<axum::Json<OkOut>> {
    let rid = rid.trim().to_string();
    if rid.is_empty() {
        return Err(ApiError::bad_request("request id required"));
    }

    let requests = state.table("payment_requests");
    let row = sqlx::query(&format!(
        "SELECT id,status,expires_at FROM {requests} WHERE id=$1"
    ))
    .bind(&rid)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db cancel_request lookup failed");
        ApiError::internal("database error")
    })?
    .ok_or_else(|| ApiError::not_found("not found"))?;

    let status_raw: String = row
        .try_get("status")
        .unwrap_or_else(|_| "pending".to_string());
    let expires_at: Option<String> = row.try_get("expires_at").unwrap_or(None);
    let status = request_status_with_expiry(status_raw.clone(), expires_at);
    if status == "expired" {
        let _ = sqlx::query(&format!(
            "UPDATE {requests} SET status='expired' WHERE id=$1"
        ))
        .bind(&rid)
        .execute(&state.pool)
        .await;
        return Err(ApiError::bad_request("expired"));
    }
    if status_raw != "pending" {
        return Err(ApiError::bad_request("not pending"));
    }

    sqlx::query(&format!(
        "UPDATE {requests} SET status='canceled' WHERE id=$1"
    ))
    .bind(&rid)
    .execute(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db cancel_request update failed");
        ApiError::internal("database error")
    })?;

    Ok(axum::Json(OkOut { ok: true }))
}

pub async fn accept_request(
    Path(rid): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<AcceptRequestReq>,
) -> ApiResult<axum::Json<WalletResp>> {
    let rid = rid.trim().to_string();
    if rid.is_empty() {
        return Err(ApiError::bad_request("request id required"));
    }
    let to_wallet_id = body.to_wallet_id.trim().to_string();
    if to_wallet_id.is_empty() {
        return Err(ApiError::bad_request("to_wallet_id required"));
    }

    let ikey = idempotency_key(&headers)?;
    let idempotency = state.table("idempotency");

    if let Some(k) = ikey.as_deref() {
        let rec = sqlx::query(&format!(
            "SELECT endpoint,wallet_id,balance_cents,currency FROM {idempotency} WHERE ikey=$1"
        ))
        .bind(k)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "db accept_request idempotency lookup failed");
            ApiError::internal("database error")
        })?;

        if let Some(r) = rec {
            let endpoint: String = r.try_get("endpoint").unwrap_or_default();
            if endpoint != "request_accept" {
                return Err(ApiError::conflict(
                    "Idempotency-Key reused for a different endpoint",
                ));
            }
            let wid: Option<String> = r.try_get("wallet_id").unwrap_or(None);
            let wid = wid.ok_or_else(|| ApiError::internal("idempotency wallet missing"))?;
            let wallets = state.table("wallets");
            let row = sqlx::query(&format!(
                "SELECT id,balance_cents,currency FROM {wallets} WHERE id=$1"
            ))
            .bind(&wid)
            .fetch_optional(&state.pool)
            .await
            .map_err(|e| {
                tracing::error!(error = %e, "db accept_request idempotent wallet lookup failed");
                ApiError::internal("database error")
            })?
            .ok_or_else(|| ApiError::not_found("Wallet not found"))?;

            return Ok(axum::Json(WalletResp {
                wallet_id: row.try_get("id").unwrap_or_default(),
                balance_cents: row
                    .try_get("balance_cents")
                    .or_else(|_| r.try_get("balance_cents"))
                    .unwrap_or(0),
                currency: row
                    .try_get("currency")
                    .or_else(|_| r.try_get("currency"))
                    .unwrap_or_else(|_| state.default_currency.clone()),
            }));
        }
    }

    let requests = state.table("payment_requests");
    let wallets = state.table("wallets");
    let txns = state.table("txns");
    let ledger = state.table("ledger_entries");

    let mut tx = state.pool.begin().await.map_err(|e| {
        tracing::error!(error = %e, "db begin accept_request failed");
        ApiError::internal("database error")
    })?;

    let req_row = sqlx::query(&format!(
        "SELECT id,from_wallet_id,to_wallet_id,amount_cents,currency,status,expires_at FROM {requests} WHERE id=$1{}",
        for_update_suffix(&state)
    ))
    .bind(&rid)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db accept_request request lock failed");
        ApiError::internal("database error")
    })?
    .ok_or_else(|| ApiError::not_found("not found"))?;

    let status_raw: String = req_row
        .try_get("status")
        .unwrap_or_else(|_| "pending".to_string());
    let expires_at: Option<String> = req_row.try_get("expires_at").unwrap_or(None);
    let status = request_status_with_expiry(status_raw.clone(), expires_at);
    if status == "expired" {
        let _ = sqlx::query(&format!(
            "UPDATE {requests} SET status='expired' WHERE id=$1"
        ))
        .bind(&rid)
        .execute(&mut *tx)
        .await;
        return Err(ApiError::bad_request("expired"));
    }
    if status_raw != "pending" {
        return Err(ApiError::bad_request("not pending"));
    }

    let req_to_wallet_id: String = req_row.try_get("to_wallet_id").unwrap_or_default();
    if to_wallet_id != req_to_wallet_id {
        return Err(ApiError::bad_request("wallet mismatch for request"));
    }

    let req_from_wallet_id: String = req_row.try_get("from_wallet_id").unwrap_or_default();
    let amount_cents: i64 = req_row.try_get("amount_cents").unwrap_or(0);

    let payer = sqlx::query(&format!(
        "SELECT id,balance_cents,currency FROM {wallets} WHERE id=$1{}",
        for_update_suffix(&state)
    ))
    .bind(&req_to_wallet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db accept_request payer lock failed");
        ApiError::internal("database error")
    })?
    .ok_or_else(|| ApiError::not_found("wallet missing"))?;

    let payee = sqlx::query(&format!(
        "SELECT id,balance_cents FROM {wallets} WHERE id=$1{}",
        for_update_suffix(&state)
    ))
    .bind(&req_from_wallet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db accept_request payee lock failed");
        ApiError::internal("database error")
    })?
    .ok_or_else(|| ApiError::not_found("wallet missing"))?;

    let payer_balance: i64 = payer.try_get("balance_cents").unwrap_or(0);
    let payee_balance: i64 = payee.try_get("balance_cents").unwrap_or(0);
    if payer_balance < amount_cents {
        return Err(ApiError::bad_request("insufficient funds"));
    }

    let payer_new = payer_balance - amount_cents;
    let payee_new = payee_balance + amount_cents;

    sqlx::query(&format!(
        "UPDATE {wallets} SET balance_cents=$1 WHERE id=$2"
    ))
    .bind(payer_new)
    .bind(&req_to_wallet_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db accept_request payer update failed");
        ApiError::internal("database error")
    })?;

    sqlx::query(&format!(
        "UPDATE {wallets} SET balance_cents=$1 WHERE id=$2"
    ))
    .bind(payee_new)
    .bind(&req_from_wallet_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db accept_request payee update failed");
        ApiError::internal("database error")
    })?;

    let txn_id = Uuid::new_v4().to_string();
    let now = now_iso();

    sqlx::query(&format!(
        "INSERT INTO {txns} (id,from_wallet_id,to_wallet_id,amount_cents,kind,fee_cents,created_at) VALUES ($1,$2,$3,$4,$5,$6,$7)"
    ))
    .bind(&txn_id)
    .bind(&req_to_wallet_id)
    .bind(&req_from_wallet_id)
    .bind(amount_cents)
    .bind("transfer")
    .bind(0i64)
    .bind(&now)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db accept_request txn insert failed");
        ApiError::internal("database error")
    })?;

    sqlx::query(&format!(
        "INSERT INTO {ledger} (id,wallet_id,amount_cents,txn_id,description,created_at) VALUES ($1,$2,$3,$4,$5,$6)"
    ))
    .bind(Uuid::new_v4().to_string())
    .bind(&req_to_wallet_id)
    .bind(-amount_cents)
    .bind(&txn_id)
    .bind(format!("transfer_debit;request:{rid}"))
    .bind(&now)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db accept_request ledger debit insert failed");
        ApiError::internal("database error")
    })?;

    sqlx::query(&format!(
        "INSERT INTO {ledger} (id,wallet_id,amount_cents,txn_id,description,created_at) VALUES ($1,$2,$3,$4,$5,$6)"
    ))
    .bind(Uuid::new_v4().to_string())
    .bind(&req_from_wallet_id)
    .bind(amount_cents)
    .bind(&txn_id)
    .bind(format!("transfer_credit;request:{rid}"))
    .bind(&now)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db accept_request ledger credit insert failed");
        ApiError::internal("database error")
    })?;

    sqlx::query(&format!(
        "UPDATE {requests} SET status='accepted' WHERE id=$1"
    ))
    .bind(&rid)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db accept_request status update failed");
        ApiError::internal("database error")
    })?;

    if let Some(k) = ikey {
        let payer_currency: String = payer
            .try_get("currency")
            .unwrap_or_else(|_| state.default_currency.clone());
        let _ = sqlx::query(&format!(
            "INSERT INTO {idempotency} (id,ikey,endpoint,txn_id,amount_cents,currency,wallet_id,balance_cents,created_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)"
        ))
        .bind(Uuid::new_v4().to_string())
        .bind(k)
        .bind("request_accept")
        .bind(&txn_id)
        .bind(amount_cents)
        .bind(payer_currency)
        .bind(&req_to_wallet_id)
        .bind(payer_new)
        .bind(&now)
        .execute(&mut *tx)
        .await;
    }

    tx.commit().await.map_err(|e| {
        tracing::error!(error = %e, "db accept_request commit failed");
        ApiError::internal("database error")
    })?;

    Ok(axum::Json(WalletResp {
        wallet_id: req_to_wallet_id,
        balance_cents: payer_new,
        currency: payer
            .try_get("currency")
            .unwrap_or_else(|_| state.default_currency.clone()),
    }))
}

pub async fn idempotency_status(
    Path(ikey): Path<String>,
    State(state): State<AppState>,
) -> ApiResult<axum::Json<IdempotencyExistsOut>> {
    let ikey = ikey.trim().to_string();
    if ikey.is_empty() {
        return Err(ApiError::bad_request("idempotency key required"));
    }

    let idempotency = state.table("idempotency");
    let rec = sqlx::query(&format!(
        "SELECT txn_id,endpoint,created_at FROM {idempotency} WHERE ikey=$1"
    ))
    .bind(&ikey)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "db idempotency_status failed");
        ApiError::internal("database error")
    })?;

    if let Some(r) = rec {
        return Ok(axum::Json(IdempotencyExistsOut {
            exists: true,
            txn_id: r.try_get("txn_id").unwrap_or(None),
            endpoint: r.try_get("endpoint").unwrap_or(None),
            created_at: r.try_get("created_at").unwrap_or(None),
        }));
    }

    Ok(axum::Json(IdempotencyExistsOut {
        exists: false,
        txn_id: None,
        endpoint: None,
        created_at: None,
    }))
}

pub async fn roles_list(
    State(state): State<AppState>,
    Query(params): Query<RolesParams>,
) -> ApiResult<axum::Json<Vec<RoleItem>>> {
    let roles = state.table("roles");
    let account_id = params
        .account_id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(normalize_account_id)
        .transpose()?;
    let phone = params
        .phone
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string());
    if let Some(p) = phone.as_deref() {
        if !valid_e164(p) {
            return Err(ApiError::bad_request("invalid phone format"));
        }
    }
    let role = params
        .role
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|s| s.to_lowercase());
    let limit = normalize_limit(params.limit, 200, 1, 1000);

    let rows = match (account_id.as_deref(), phone.as_deref(), role.as_deref()) {
        (Some(a), _, Some(r)) => {
            sqlx::query(&format!(
                "SELECT id,account_id,phone,role,created_at FROM {roles} WHERE account_id=$1 AND role=$2 ORDER BY created_at DESC LIMIT $3"
            ))
            .bind(a)
            .bind(r)
            .bind(limit)
            .fetch_all(&state.pool)
            .await
        }
        (Some(a), _, None) => {
            sqlx::query(&format!(
                "SELECT id,account_id,phone,role,created_at FROM {roles} WHERE account_id=$1 ORDER BY created_at DESC LIMIT $2"
            ))
            .bind(a)
            .bind(limit)
            .fetch_all(&state.pool)
            .await
        }
        (None, Some(p), Some(r)) => {
            sqlx::query(&format!(
                "SELECT id,account_id,phone,role,created_at FROM {roles} WHERE phone=$1 AND role=$2 ORDER BY created_at DESC LIMIT $3"
            ))
            .bind(p)
            .bind(r)
            .bind(limit)
            .fetch_all(&state.pool)
            .await
        }
        (None, Some(p), None) => {
            sqlx::query(&format!(
                "SELECT id,account_id,phone,role,created_at FROM {roles} WHERE phone=$1 ORDER BY created_at DESC LIMIT $2"
            ))
            .bind(p)
            .bind(limit)
            .fetch_all(&state.pool)
            .await
        }
        (None, None, Some(r)) => {
            sqlx::query(&format!(
                "SELECT id,account_id,phone,role,created_at FROM {roles} WHERE role=$1 ORDER BY created_at DESC LIMIT $2"
            ))
            .bind(r)
            .bind(limit)
            .fetch_all(&state.pool)
            .await
        }
        (None, None, None) => {
            sqlx::query(&format!(
                "SELECT id,account_id,phone,role,created_at FROM {roles} ORDER BY created_at DESC LIMIT $1"
            ))
            .bind(limit)
            .fetch_all(&state.pool)
            .await
        }
    }
    .map_err(|e| {
        tracing::error!(error = %e, "db roles_list failed");
        ApiError::internal("database error")
    })?;

    let mut out = Vec::with_capacity(rows.len());
    for r in rows {
        out.push(RoleItem {
            id: r.try_get("id").unwrap_or_default(),
            account_id: r.try_get("account_id").unwrap_or(None),
            phone: r.try_get("phone").unwrap_or(None),
            role: r.try_get("role").unwrap_or_default(),
            created_at: r.try_get("created_at").unwrap_or(None),
        });
    }

    Ok(axum::Json(out))
}

pub async fn roles_add(
    State(state): State<AppState>,
    axum::Json(body): axum::Json<RoleUpsert>,
) -> ApiResult<axum::Json<OkOut>> {
    let mut account_id = body
        .account_id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(normalize_account_id)
        .transpose()?;
    let mut phone = body
        .phone
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string());
    if let Some(p) = phone.as_deref() {
        if !valid_e164(p) {
            return Err(ApiError::bad_request("invalid phone format"));
        }
    }
    let role = body.role.trim().to_lowercase();
    if !ALLOWED_ROLES.iter().any(|x| *x == role) {
        return Err(ApiError::bad_request("invalid role"));
    }
    if account_id.is_none() && phone.is_none() {
        return Err(ApiError::bad_request("account_id or phone required"));
    }

    // If only a phone is provided, attempt to resolve it to an account_id (best effort).
    if account_id.is_none() {
        if let Some(p) = phone.as_deref() {
            let users = state.table("users");
            if let Some(row) = sqlx::query(&format!(
                "SELECT account_id FROM {users} WHERE phone=$1 LIMIT 1"
            ))
            .bind(p)
            .fetch_optional(&state.pool)
            .await
            .ok()
            .flatten()
            {
                let acct: Option<String> = row.try_get("account_id").unwrap_or(None);
                let acct = acct
                    .as_deref()
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .map(ToString::to_string);
                if acct.is_some() {
                    account_id = acct;
                    // Avoid persisting phone in roles when we have a stable account id.
                    phone = None;
                }
            }
        }
    }

    let roles = state.table("roles");
    let exists = if let Some(a) = account_id.as_deref() {
        sqlx::query(&format!(
            "SELECT id FROM {roles} WHERE account_id=$1 AND role=$2"
        ))
        .bind(a)
        .bind(&role)
        .fetch_optional(&state.pool)
        .await
    } else {
        sqlx::query(&format!(
            "SELECT id FROM {roles} WHERE phone=$1 AND role=$2"
        ))
        .bind(phone.as_deref().unwrap_or(""))
        .bind(&role)
        .fetch_optional(&state.pool)
        .await
    }
    .map_err(|e| {
        tracing::error!(error = %e, "db roles_add lookup failed");
        ApiError::internal("database error")
    })?;

    if exists.is_none() {
        let now = now_iso();
        sqlx::query(&format!(
            "INSERT INTO {roles} (id,account_id,phone,role,created_at) VALUES ($1,$2,$3,$4,$5)"
        ))
        .bind(Uuid::new_v4().to_string())
        .bind(account_id.as_deref())
        .bind(phone.as_deref())
        .bind(&role)
        .bind(&now)
        .execute(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "db roles_add insert failed");
            ApiError::internal("database error")
        })?;
    }

    Ok(axum::Json(OkOut { ok: true }))
}

pub async fn roles_remove(
    State(state): State<AppState>,
    axum::Json(body): axum::Json<RoleUpsert>,
) -> ApiResult<axum::Json<OkOut>> {
    let account_id = body
        .account_id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(normalize_account_id)
        .transpose()?;
    let phone = body
        .phone
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string());
    if let Some(p) = phone.as_deref() {
        if !valid_e164(p) {
            return Err(ApiError::bad_request("invalid phone format"));
        }
    }
    let role = body.role.trim().to_lowercase();
    if role.is_empty() {
        return Err(ApiError::bad_request("role required"));
    }
    if account_id.is_none() && phone.is_none() {
        return Err(ApiError::bad_request("account_id or phone required"));
    }

    let roles = state.table("roles");
    let _ = if let Some(a) = account_id.as_deref() {
        sqlx::query(&format!(
            "DELETE FROM {roles} WHERE account_id=$1 AND role=$2"
        ))
        .bind(a)
        .bind(&role)
        .execute(&state.pool)
        .await
    } else {
        sqlx::query(&format!("DELETE FROM {roles} WHERE phone=$1 AND role=$2"))
            .bind(phone.as_deref().unwrap_or(""))
            .bind(&role)
            .execute(&state.pool)
            .await
    }
    .map_err(|e| {
        tracing::error!(error = %e, "db roles_remove failed");
        ApiError::internal("database error")
    })?;

    Ok(axum::Json(OkOut { ok: true }))
}

pub async fn roles_check(
    State(state): State<AppState>,
    Query(params): Query<RoleCheckParams>,
) -> ApiResult<axum::Json<RoleCheckOut>> {
    let account_id = params
        .account_id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(normalize_account_id)
        .transpose()?;
    let phone = params
        .phone
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string());
    let role = params.role.trim().to_lowercase();
    if let Some(p) = phone.as_deref() {
        if !valid_e164(p) {
            return Err(ApiError::bad_request("invalid phone format"));
        }
    }
    if role.is_empty() {
        return Err(ApiError::bad_request("role required"));
    }
    if account_id.is_none() && phone.is_none() {
        return Err(ApiError::bad_request("account_id or phone required"));
    }

    let roles = state.table("roles");
    let exists = if let Some(a) = account_id.as_deref() {
        sqlx::query(&format!(
            "SELECT 1 FROM {roles} WHERE account_id=$1 AND role=$2 LIMIT 1"
        ))
        .bind(a)
        .bind(&role)
        .fetch_optional(&state.pool)
        .await
    } else {
        sqlx::query(&format!(
            "SELECT 1 FROM {roles} WHERE phone=$1 AND role=$2 LIMIT 1"
        ))
        .bind(phone.as_deref().unwrap_or(""))
        .bind(&role)
        .fetch_optional(&state.pool)
        .await
    }
    .map_err(|e| {
        tracing::error!(error = %e, "db roles_check failed");
        ApiError::internal("database error")
    })?
    .is_some();

    Ok(axum::Json(RoleCheckOut { ok: exists }))
}

fn make_in_clause(start_index: usize, count: usize) -> String {
    let mut parts = Vec::with_capacity(count);
    for i in 0..count {
        parts.push(format!("${}", start_index + i));
    }
    format!("({})", parts.join(","))
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::StatusCode;

    #[test]
    fn alias_normalization_works() {
        assert_eq!(normalize_alias("@alice").unwrap(), "alice");
        assert!(normalize_alias("not valid!").is_err());
    }

    #[test]
    fn e164_validation_works() {
        assert!(valid_e164("+491700000001"));
        assert!(!valid_e164("491700000001"));
        assert!(!valid_e164("+0123"));
    }

    #[test]
    fn bus_booking_action_validation_works() {
        assert_eq!(parse_bus_booking_action(None).unwrap(), "charge");
        assert_eq!(parse_bus_booking_action(Some("refund")).unwrap(), "refund");
        assert!(parse_bus_booking_action(Some("replay")).is_err());
    }

    #[tokio::test]
    async fn bus_booking_secret_is_fail_closed_when_missing() {
        let state = AppState {
            pool: sqlx::PgPool::connect_lazy("postgresql://postgres:postgres@localhost/postgres")
                .expect("lazy pool"),
            db_schema: Some("public".to_string()),
            env_name: "test".to_string(),
            default_currency: "SYP".to_string(),
            allow_direct_topup: false,
            bus_payments_internal_secret: None,
            merchant_fee_bps: 150,
            fee_wallet_account_id: None,
            fee_wallet_phone: "+963999999999".to_string(),
        };
        let headers = HeaderMap::new();
        let err =
            require_bus_booking_secret(&state, &headers).expect_err("expected fail-closed guard");
        assert_eq!(err.status, StatusCode::FORBIDDEN);
    }
}
