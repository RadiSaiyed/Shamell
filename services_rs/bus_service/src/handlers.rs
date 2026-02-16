use crate::error::{ApiError, ApiResult};
use crate::models::*;
use crate::state::AppState;
use axum::extract::{Path, Query, State};
use axum::http::HeaderMap;
use chrono::{DateTime, Datelike, Duration, NaiveDate, TimeZone, Timelike, Utc};
use hmac::{Hmac, Mac};
use sha2::Digest;
use sha2::Sha256;
use sqlx::postgres::PgRow;
use sqlx::{Row, Transaction};
use subtle::ConstantTimeEq;
use uuid::Uuid;

type HmacSha256 = Hmac<Sha256>;
const BUS_BOOKING_ACTION_CHARGE: &str = "charge";
const BUS_BOOKING_ACTION_REFUND: &str = "refund";

#[derive(Debug, serde::Deserialize)]
pub struct ListCitiesParams {
    pub q: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, serde::Deserialize)]
pub struct ListOperatorsParams {
    pub limit: Option<i64>,
}

#[derive(Debug, serde::Deserialize)]
pub struct ListRoutesParams {
    pub origin_city_id: Option<String>,
    pub dest_city_id: Option<String>,
}

#[derive(Debug, serde::Deserialize)]
pub struct SearchTripsParams {
    pub origin_city_id: String,
    pub dest_city_id: String,
    pub date: String, // YYYY-MM-DD
}

#[derive(Debug, serde::Deserialize)]
pub struct OperatorTripsParams {
    pub status: Option<String>,
    pub from_date: Option<String>,
    pub to_date: Option<String>,
    pub limit: Option<i64>,
    pub order: Option<String>,
}

#[derive(Debug, serde::Deserialize)]
pub struct QuoteParams {
    pub seats: Option<i32>,
}

#[derive(Debug, serde::Deserialize)]
pub struct BookingSearchParams {
    pub wallet_id: Option<String>,
    pub phone: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug)]
struct BookingRow {
    id: String,
    trip_id: String,
    seats: i32,
    status: String,
    created_at: Option<DateTime<Utc>>,
    wallet_id: Option<String>,
    customer_phone: Option<String>,
}

#[derive(Debug, serde::Deserialize)]
pub struct OperatorStatsParams {
    pub period: Option<String>,
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
        service: "Bus API",
        version: env!("CARGO_PKG_VERSION"),
    })
}

fn parse_iso8601(dt: &str) -> Result<DateTime<Utc>, ApiError> {
    let s = dt.trim();
    if s.is_empty() {
        return Err(ApiError::bad_request("invalid date format; use ISO8601"));
    }
    let s = s.replace('Z', "+00:00");
    let parsed = DateTime::parse_from_rfc3339(&s)
        .map_err(|_| ApiError::bad_request("invalid date format; use ISO8601"))?;
    Ok(parsed.with_timezone(&Utc))
}

fn parse_db_dt(raw: &str) -> Result<DateTime<Utc>, ApiError> {
    let s = raw.trim();
    if s.is_empty() {
        return Err(ApiError::internal("database error"));
    }
    let s = s.replace('Z', "+00:00");
    let parsed =
        DateTime::parse_from_rfc3339(&s).map_err(|_| ApiError::internal("database error"))?;
    Ok(parsed.with_timezone(&Utc))
}

fn row_dt(row: &PgRow, col: &str) -> Result<DateTime<Utc>, ApiError> {
    let raw: String = row
        .try_get(col)
        .map_err(|_| ApiError::internal("database error"))?;
    parse_db_dt(&raw)
}

fn row_dt_opt(row: &PgRow, col: &str) -> Option<DateTime<Utc>> {
    row.try_get::<Option<String>, _>(col)
        .ok()
        .flatten()
        .and_then(|s| parse_db_dt(&s).ok())
}

fn city_code_for_trip_id(name: &str) -> String {
    let cleaned: String = name
        .trim()
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .collect();
    if cleaned.is_empty() {
        return "CITY".to_string();
    }
    cleaned.chars().take(10).collect::<String>().to_uppercase()
}

async fn generate_trip_id(
    tx: &mut Transaction<'_, sqlx::Postgres>,
    state: &AppState,
    route_origin_name: &str,
    route_dest_name: &str,
    depart_at: DateTime<Utc>,
) -> Result<String, ApiError> {
    let o = city_code_for_trip_id(route_origin_name);
    let d = city_code_for_trip_id(route_dest_name);
    let dep = depart_at.with_timezone(&Utc);
    let base = format!(
        "{o}-{d}-{:04}{:02}{:02}-{:02}{:02}",
        dep.year(),
        dep.month(),
        dep.day(),
        dep.hour(),
        dep.minute()
    );
    let max_len = 36usize;
    let mut base_trimmed = base;
    if base_trimmed.len() > max_len - 3 {
        base_trimmed.truncate(max_len - 3);
    }

    let trips = state.table("trips");

    let mut trip_id = base_trimmed.clone();
    let mut n = 1u32;
    while n < 100 {
        let q = format!("SELECT 1 FROM {trips} WHERE id=$1 LIMIT 1");
        let exists = sqlx::query(&q)
            .bind(&trip_id)
            .fetch_optional(&mut **tx)
            .await
            .map_err(|e| {
                tracing::error!(error = %e, "db trip_id existence check failed");
                ApiError::internal("database error")
            })?
            .is_some();
        if !exists {
            return Ok(trip_id);
        }
        trip_id = format!("{base_trimmed}-{n}");
        if trip_id.len() > max_len {
            trip_id.truncate(max_len);
        }
        n += 1;
    }

    Ok(Uuid::new_v4().to_string())
}

fn ticket_sig(
    ticket_secret: &str,
    ticket_id: &str,
    booking_id: &str,
    trip_id: &str,
    seat: i32,
) -> String {
    let msg = format!("{ticket_id}:{booking_id}:{trip_id}:{seat}");
    let mut mac = HmacSha256::new_from_slice(ticket_secret.as_bytes()).expect("hmac key");
    mac.update(msg.as_bytes());
    let out = mac.finalize().into_bytes();
    hex::encode(out)
}

fn ticket_payload(
    ticket_secret: &str,
    ticket_id: &str,
    booking_id: &str,
    trip_id: &str,
    seat: i32,
) -> String {
    let sig = ticket_sig(ticket_secret, ticket_id, booking_id, trip_id, seat);
    format!("TICKET|id={ticket_id}|b={booking_id}|trip={trip_id}|seat={seat}|sig={sig}")
}

fn refund_pct_for_departure(now: DateTime<Utc>, depart_at: DateTime<Utc>) -> f64 {
    let delta = depart_at - now;
    if delta.num_seconds() < 0 {
        return 0.0;
    }
    let days = delta.num_seconds() as f64 / 86400.0;
    let hours = delta.num_seconds() as f64 / 3600.0;
    if days >= 30.0 {
        1.0
    } else if days >= 7.0 {
        0.7
    } else if hours >= 48.0 {
        0.4
    } else {
        0.2
    }
}

fn for_update_suffix(state: &AppState) -> &'static str {
    let _ = state;
    " FOR UPDATE"
}

fn normalize_limit(raw: Option<i64>, default: i64, min: i64, max: i64) -> i64 {
    let v = raw.unwrap_or(default);
    v.clamp(min, max)
}

pub async fn list_cities(
    State(state): State<AppState>,
    Query(params): Query<ListCitiesParams>,
) -> ApiResult<axum::Json<Vec<CityOut>>> {
    let q = params.q.unwrap_or_default().trim().to_string();
    let limit = normalize_limit(params.limit, 50, 1, 200);

    let cities = state.table("cities");
    let rows = if q.is_empty() {
        let sql = format!("SELECT id,name,country FROM {cities} ORDER BY name ASC LIMIT $1");
        sqlx::query(&sql)
            .bind(limit)
            .fetch_all(&state.pool)
            .await
    } else {
        let like = format!("%{}%", q.to_lowercase());
        let sql = format!(
            "SELECT id,name,country FROM {cities} WHERE LOWER(name) LIKE $1 ORDER BY name ASC LIMIT $2"
        );
        sqlx::query(&sql)
            .bind(like)
            .bind(limit)
            .fetch_all(&state.pool)
            .await
    }
    .map_err(|e| {
        tracing::error!(error = %e, "db list_cities failed");
        ApiError::internal("database error")
    })?;

    let mut out = Vec::with_capacity(rows.len());
    for r in rows {
        out.push(CityOut {
            id: r.try_get("id").unwrap_or_default(),
            name: r.try_get("name").unwrap_or_default(),
            country: r.try_get("country").unwrap_or(None),
        });
    }
    Ok(axum::Json(out))
}

pub async fn create_city(
    State(state): State<AppState>,
    axum::Json(body): axum::Json<CityIn>,
) -> ApiResult<axum::Json<CityOut>> {
    let name = body.name.trim().to_string();
    if name.is_empty() {
        return Err(ApiError::bad_request("name required"));
    }
    if name.len() > 120 {
        return Err(ApiError::bad_request("name too long"));
    }
    let country = body
        .country
        .map(|c| c.trim().to_string())
        .filter(|c| !c.is_empty());
    let id = Uuid::new_v4().to_string();

    let cities = state.table("cities");
    let sql = format!("INSERT INTO {cities} (id,name,country) VALUES ($1,$2,$3)");
    sqlx::query(&sql)
        .bind(&id)
        .bind(&name)
        .bind(&country)
        .execute(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "db create_city failed");
            ApiError::internal("database error")
        })?;

    Ok(axum::Json(CityOut { id, name, country }))
}

pub async fn list_operators(
    State(state): State<AppState>,
    Query(params): Query<ListOperatorsParams>,
) -> ApiResult<axum::Json<Vec<OperatorOut>>> {
    let limit = normalize_limit(params.limit, 50, 1, 200);
    let ops = state.table("bus_operators");
    let sql = format!("SELECT id,name,wallet_id,is_online FROM {ops} ORDER BY name ASC LIMIT $1");
    let rows = sqlx::query(&sql)
        .bind(limit)
        .fetch_all(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "db list_operators failed");
            ApiError::internal("database error")
        })?;
    let mut out = Vec::with_capacity(rows.len());
    for r in rows {
        let is_online: i64 = r.try_get("is_online").unwrap_or(0);
        out.push(OperatorOut {
            id: r.try_get("id").unwrap_or_default(),
            name: r.try_get("name").unwrap_or_default(),
            wallet_id: r.try_get("wallet_id").unwrap_or(None),
            is_online: is_online != 0,
        });
    }
    Ok(axum::Json(out))
}

pub async fn get_operator(
    Path(operator_id): Path<String>,
    State(state): State<AppState>,
) -> ApiResult<axum::Json<OperatorOut>> {
    let op = fetch_operator(&state, &state.table("bus_operators"), operator_id.trim())
        .await
        .ok_or_else(|| ApiError::not_found("operator not found"))?;
    Ok(axum::Json(op))
}

#[derive(Debug, serde::Serialize)]
pub struct OperatorOnlineOut {
    pub ok: bool,
    pub is_online: bool,
}

pub async fn operator_online(
    Path(operator_id): Path<String>,
    State(state): State<AppState>,
) -> ApiResult<axum::Json<OperatorOnlineOut>> {
    set_operator_online(&state, &operator_id, true).await
}

pub async fn operator_offline(
    Path(operator_id): Path<String>,
    State(state): State<AppState>,
) -> ApiResult<axum::Json<OperatorOnlineOut>> {
    set_operator_online(&state, &operator_id, false).await
}

async fn set_operator_online(
    state: &AppState,
    operator_id: &str,
    is_online: bool,
) -> ApiResult<axum::Json<OperatorOnlineOut>> {
    let ops = state.table("bus_operators");
    let sql = format!("UPDATE {ops} SET is_online=$1 WHERE id=$2");
    let res = sqlx::query(&sql)
        .bind(if is_online { 1i64 } else { 0i64 })
        .bind(operator_id)
        .execute(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!(error=%e, "db set_operator_online failed");
            ApiError::internal("database error")
        })?;
    if res.rows_affected() == 0 {
        return Err(ApiError::not_found("operator not found"));
    }
    Ok(axum::Json(OperatorOnlineOut {
        ok: true,
        is_online,
    }))
}

pub async fn create_operator(
    State(state): State<AppState>,
    axum::Json(body): axum::Json<OperatorIn>,
) -> ApiResult<axum::Json<OperatorOut>> {
    let name = body.name.trim().to_string();
    if name.is_empty() {
        return Err(ApiError::bad_request("name required"));
    }
    if name.len() > 120 {
        return Err(ApiError::bad_request("name too long"));
    }
    let wallet_id = body
        .wallet_id
        .map(|w| w.trim().to_string())
        .filter(|w| !w.is_empty());
    let id = Uuid::new_v4().to_string();

    let ops = state.table("bus_operators");
    let sql = format!("INSERT INTO {ops} (id,name,wallet_id,is_online) VALUES ($1,$2,$3,$4)");
    sqlx::query(&sql)
        .bind(&id)
        .bind(&name)
        .bind(&wallet_id)
        .bind(0i64)
        .execute(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!(error=%e, "db create_operator failed");
            ApiError::internal("database error")
        })?;

    Ok(axum::Json(OperatorOut {
        id,
        name,
        wallet_id,
        is_online: false,
    }))
}

pub async fn create_route(
    State(state): State<AppState>,
    axum::Json(body): axum::Json<RouteIn>,
) -> ApiResult<axum::Json<RouteOut>> {
    let id = body.id.unwrap_or_default().trim().to_string();
    let id = if id.is_empty() {
        Uuid::new_v4().to_string()
    } else {
        id
    };
    let origin_city_id = body.origin_city_id.trim().to_string();
    let dest_city_id = body.dest_city_id.trim().to_string();
    let operator_id = body.operator_id.trim().to_string();
    if origin_city_id.is_empty() || dest_city_id.is_empty() || operator_id.is_empty() {
        return Err(ApiError::bad_request(
            "origin_city_id, dest_city_id and operator_id are required",
        ));
    }
    let bus_model = body
        .bus_model
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());
    let features = body
        .features
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());

    let routes = state.table("routes");
    let sql = format!(
        "INSERT INTO {routes} (id,origin_city_id,dest_city_id,operator_id,bus_model,features) VALUES ($1,$2,$3,$4,$5,$6)"
    );
    sqlx::query(&sql)
        .bind(&id)
        .bind(&origin_city_id)
        .bind(&dest_city_id)
        .bind(&operator_id)
        .bind(&bus_model)
        .bind(&features)
        .execute(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!(error=%e, "db create_route failed");
            ApiError::internal("database error")
        })?;

    Ok(axum::Json(RouteOut {
        id,
        origin_city_id,
        dest_city_id,
        operator_id,
        bus_model,
        features,
    }))
}

pub async fn list_routes(
    State(state): State<AppState>,
    Query(params): Query<ListRoutesParams>,
) -> ApiResult<axum::Json<Vec<RouteOut>>> {
    let routes = state.table("routes");
    let mut sql = format!(
        "SELECT id,origin_city_id,dest_city_id,operator_id,bus_model,features FROM {routes}"
    );
    let mut binds: Vec<String> = Vec::new();
    if let Some(o) = params
        .origin_city_id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        binds.push(o.to_string());
        sql.push_str(&format!(" WHERE origin_city_id=${}", binds.len()));
    }
    if let Some(d) = params
        .dest_city_id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        binds.push(d.to_string());
        if binds.len() == 1 {
            sql.push_str(&format!(" WHERE dest_city_id=${}", binds.len()));
        } else {
            sql.push_str(&format!(" AND dest_city_id=${}", binds.len()));
        }
    }

    let mut q = sqlx::query(&sql);
    for b in &binds {
        q = q.bind(b);
    }
    let rows = q.fetch_all(&state.pool).await.map_err(|e| {
        tracing::error!(error=%e, "db list_routes failed");
        ApiError::internal("database error")
    })?;
    let mut out = Vec::with_capacity(rows.len());
    for r in rows {
        out.push(RouteOut {
            id: r.try_get("id").unwrap_or_default(),
            origin_city_id: r.try_get("origin_city_id").unwrap_or_default(),
            dest_city_id: r.try_get("dest_city_id").unwrap_or_default(),
            operator_id: r.try_get("operator_id").unwrap_or_default(),
            bus_model: r.try_get("bus_model").unwrap_or(None),
            features: r.try_get("features").unwrap_or(None),
        });
    }
    Ok(axum::Json(out))
}

pub async fn route_detail(
    Path(route_id): Path<String>,
    State(state): State<AppState>,
) -> ApiResult<axum::Json<RouteOut>> {
    let routes = state.table("routes");
    let sql = format!(
        "SELECT id,origin_city_id,dest_city_id,operator_id,bus_model,features FROM {routes} WHERE id=$1"
    );
    let row = sqlx::query(&sql)
        .bind(route_id.trim())
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!(error=%e, "db route_detail failed");
            ApiError::internal("database error")
        })?
        .ok_or_else(|| ApiError::not_found("route not found"))?;

    Ok(axum::Json(RouteOut {
        id: row.try_get("id").unwrap_or_default(),
        origin_city_id: row.try_get("origin_city_id").unwrap_or_default(),
        dest_city_id: row.try_get("dest_city_id").unwrap_or_default(),
        operator_id: row.try_get("operator_id").unwrap_or_default(),
        bus_model: row.try_get("bus_model").unwrap_or(None),
        features: row.try_get("features").unwrap_or(None),
    }))
}

pub async fn create_trip(
    State(state): State<AppState>,
    axum::Json(body): axum::Json<TripIn>,
) -> ApiResult<axum::Json<TripOut>> {
    if body.price_cents <= 0 {
        return Err(ApiError::bad_request("price_cents must be > 0"));
    }
    let seats_total = body.seats_total;
    if seats_total < 1 {
        return Err(ApiError::bad_request("seats_total must be >= 1"));
    }
    let dep = parse_iso8601(&body.depart_at_iso)?;
    let arr = parse_iso8601(&body.arrive_at_iso)?;

    let routes = state.table("routes");
    let ops = state.table("bus_operators");
    let cities = state.table("cities");

    // Resolve route and operator (operator must be online).
    let route_row = sqlx::query(&format!(
        "SELECT id,origin_city_id,dest_city_id,operator_id,bus_model,features FROM {routes} WHERE id=$1"
    ))
    .bind(body.route_id.trim())
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(error=%e, "db route lookup failed");
        ApiError::internal("database error")
    })?
    .ok_or_else(|| ApiError::not_found("route not found"))?;
    let origin_city_id: String = route_row.try_get("origin_city_id").unwrap_or_default();
    let dest_city_id: String = route_row.try_get("dest_city_id").unwrap_or_default();
    let operator_id: String = route_row.try_get("operator_id").unwrap_or_default();

    let op_row = sqlx::query(&format!(
        "SELECT id,name,wallet_id,is_online FROM {ops} WHERE id=$1"
    ))
    .bind(&operator_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(error=%e, "db operator lookup failed");
        ApiError::internal("database error")
    })?
    .ok_or_else(|| ApiError::not_found("operator not found"))?;
    let is_online: i64 = op_row.try_get("is_online").unwrap_or(0);
    if is_online == 0 {
        return Err(ApiError::forbidden("operator offline"));
    }

    // City names used for human-friendly trip id; fall back if missing.
    let origin_name = sqlx::query(&format!("SELECT name FROM {cities} WHERE id=$1"))
        .bind(&origin_city_id)
        .fetch_optional(&state.pool)
        .await
        .ok()
        .and_then(|r| r.and_then(|row| row.try_get::<String, _>("name").ok()))
        .unwrap_or_else(|| "Origin".to_string());
    let dest_name = sqlx::query(&format!("SELECT name FROM {cities} WHERE id=$1"))
        .bind(&dest_city_id)
        .fetch_optional(&state.pool)
        .await
        .ok()
        .and_then(|r| r.and_then(|row| row.try_get::<String, _>("name").ok()))
        .unwrap_or_else(|| "Dest".to_string());

    let mut tx = state.pool.begin().await.map_err(|e| {
        tracing::error!(error=%e, "db begin tx failed");
        ApiError::internal("database error")
    })?;
    let trip_id = generate_trip_id(&mut tx, &state, &origin_name, &dest_name, dep).await?;

    let trips = state.table("trips");
    let sql = format!(
        "INSERT INTO {trips} (id,route_id,depart_at,arrive_at,price_cents,currency,seats_total,seats_available,status) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)"
    );
    sqlx::query(&sql)
        .bind(&trip_id)
        .bind(body.route_id.trim())
        .bind(dep.to_rfc3339())
        .bind(arr.to_rfc3339())
        .bind(body.price_cents)
        .bind(body.currency.trim())
        .bind(seats_total)
        .bind(seats_total)
        .bind("draft")
        .execute(&mut *tx)
        .await
        .map_err(|e| {
            tracing::error!(error=%e, "db create_trip failed");
            ApiError::internal("database error")
        })?;
    tx.commit().await.map_err(|e| {
        tracing::error!(error=%e, "db commit failed");
        ApiError::internal("database error")
    })?;

    Ok(axum::Json(TripOut {
        id: trip_id,
        route_id: body.route_id.trim().to_string(),
        depart_at: dep,
        arrive_at: arr,
        price_cents: body.price_cents,
        currency: body.currency.trim().to_string(),
        seats_total,
        seats_available: seats_total,
        status: "draft".to_string(),
    }))
}

pub async fn search_trips(
    State(state): State<AppState>,
    Query(params): Query<SearchTripsParams>,
) -> ApiResult<axum::Json<Vec<TripSearchOut>>> {
    let date = NaiveDate::parse_from_str(params.date.trim(), "%Y-%m-%d")
        .map_err(|_| ApiError::bad_request("invalid date (YYYY-MM-DD)"))?;
    let d0 = Utc
        .with_ymd_and_hms(date.year(), date.month(), date.day(), 0, 0, 0)
        .single()
        .ok_or_else(|| ApiError::bad_request("invalid date (YYYY-MM-DD)"))?;
    let d1 = d0 + Duration::days(1);

    let routes = state.table("routes");
    let trips = state.table("trips");
    let cities = state.table("cities");
    let ops = state.table("bus_operators");

    let route_rows = sqlx::query(&format!(
        "SELECT id,operator_id,features FROM {routes} WHERE origin_city_id=$1 AND dest_city_id=$2"
    ))
    .bind(params.origin_city_id.trim())
    .bind(params.dest_city_id.trim())
    .fetch_all(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(error=%e, "db search_trips routes failed");
        ApiError::internal("database error")
    })?;
    if route_rows.is_empty() {
        return Ok(axum::Json(vec![]));
    }

    let mut route_ids: Vec<String> = Vec::with_capacity(route_rows.len());
    let mut route_by_id: std::collections::HashMap<String, (String, Option<String>)> =
        std::collections::HashMap::new();
    let mut op_ids: Vec<String> = Vec::new();
    for r in route_rows {
        let rid: String = r.try_get("id").unwrap_or_default();
        let op_id: String = r.try_get("operator_id").unwrap_or_default();
        let features: Option<String> = r.try_get("features").unwrap_or(None);
        route_ids.push(rid.clone());
        route_by_id.insert(rid, (op_id.clone(), features));
        if !op_id.is_empty() {
            op_ids.push(op_id);
        }
    }

    let in_clause = make_in_clause(1, route_ids.len());
    let sql = format!(
        "SELECT id,route_id,depart_at,arrive_at,price_cents,currency,seats_total,seats_available,status FROM {trips} \
         WHERE route_id IN {in_clause} AND depart_at >= ${} AND depart_at < ${} AND status='published' \
         ORDER BY depart_at ASC",
        route_ids.len() + 1,
        route_ids.len() + 2
    );
    let mut q = sqlx::query(&sql);
    for rid in &route_ids {
        q = q.bind(rid);
    }
    q = q.bind(d0.to_rfc3339()).bind(d1.to_rfc3339());
    let trip_rows = q.fetch_all(&state.pool).await.map_err(|e| {
        tracing::error!(error=%e, "db search_trips trips failed");
        ApiError::internal("database error")
    })?;

    let origin = fetch_city(&state, &cities, params.origin_city_id.trim())
        .await
        .unwrap_or(CityOut {
            id: params.origin_city_id.trim().to_string(),
            name: "".to_string(),
            country: None,
        });
    let dest = fetch_city(&state, &cities, params.dest_city_id.trim())
        .await
        .unwrap_or(CityOut {
            id: params.dest_city_id.trim().to_string(),
            name: "".to_string(),
            country: None,
        });

    // Operators map
    let op_map = fetch_operators_map(&state, &ops, &op_ids).await?;

    let mut out: Vec<TripSearchOut> = Vec::with_capacity(trip_rows.len());
    for r in trip_rows {
        let trip = TripOut {
            id: r.try_get("id").unwrap_or_default(),
            route_id: r.try_get("route_id").unwrap_or_default(),
            depart_at: row_dt(&r, "depart_at")?,
            arrive_at: row_dt(&r, "arrive_at")?,
            price_cents: r.try_get("price_cents").unwrap_or(0),
            currency: r.try_get("currency").unwrap_or_else(|_| "SYP".to_string()),
            seats_total: r.try_get("seats_total").unwrap_or(40),
            seats_available: r.try_get("seats_available").unwrap_or(40),
            status: r.try_get("status").unwrap_or_else(|_| "draft".to_string()),
        };
        let (op_id, features) = route_by_id.get(&trip.route_id).cloned().unwrap_or_default();
        let operator = op_map.get(&op_id).cloned().unwrap_or(OperatorOut {
            id: op_id.clone(),
            name: "".to_string(),
            wallet_id: None,
            is_online: false,
        });
        out.push(TripSearchOut {
            trip,
            origin: origin.clone(),
            dest: dest.clone(),
            operator,
            features,
        });
    }
    Ok(axum::Json(out))
}

pub async fn operator_trips(
    Path(operator_id): Path<String>,
    State(state): State<AppState>,
    Query(params): Query<OperatorTripsParams>,
) -> ApiResult<axum::Json<Vec<TripSearchOut>>> {
    let order = params
        .order
        .unwrap_or_else(|| "desc".to_string())
        .trim()
        .to_lowercase();
    if !matches!(order.as_str(), "asc" | "desc") {
        return Err(ApiError::bad_request("invalid order (asc|desc)"));
    }
    let status = params
        .status
        .map(|s| s.trim().to_lowercase())
        .and_then(|s| {
            if s.is_empty() || s == "all" {
                None
            } else {
                Some(s)
            }
        });
    if let Some(s) = status.as_deref() {
        if !matches!(s, "draft" | "published" | "canceled") {
            return Err(ApiError::bad_request("invalid status"));
        }
    }
    let start = if let Some(fd) = params
        .from_date
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        let d = NaiveDate::parse_from_str(fd, "%Y-%m-%d")
            .map_err(|_| ApiError::bad_request("invalid from_date (YYYY-MM-DD)"))?;
        Some(
            Utc.with_ymd_and_hms(d.year(), d.month(), d.day(), 0, 0, 0)
                .single()
                .ok_or_else(|| ApiError::bad_request("invalid from_date (YYYY-MM-DD)"))?,
        )
    } else {
        None
    };
    let end = if let Some(td) = params
        .to_date
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        let d = NaiveDate::parse_from_str(td, "%Y-%m-%d")
            .map_err(|_| ApiError::bad_request("invalid to_date (YYYY-MM-DD)"))?;
        Some(
            Utc.with_ymd_and_hms(d.year(), d.month(), d.day(), 0, 0, 0)
                .single()
                .ok_or_else(|| ApiError::bad_request("invalid to_date (YYYY-MM-DD)"))?
                + Duration::days(1),
        )
    } else {
        None
    };

    let limit = normalize_limit(params.limit, 100, 1, 200);

    let routes = state.table("routes");
    let trips = state.table("trips");
    let cities = state.table("cities");
    let ops = state.table("bus_operators");

    let route_rows = sqlx::query(&format!(
        "SELECT id,origin_city_id,dest_city_id,features FROM {routes} WHERE operator_id=$1"
    ))
    .bind(operator_id.trim())
    .fetch_all(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(error=%e, "db operator_trips routes failed");
        ApiError::internal("database error")
    })?;
    if route_rows.is_empty() {
        return Ok(axum::Json(vec![]));
    }

    let mut route_ids: Vec<String> = Vec::with_capacity(route_rows.len());
    let mut route_by_id: std::collections::HashMap<String, (String, String, Option<String>)> =
        std::collections::HashMap::new();
    let mut city_ids: Vec<String> = Vec::new();
    for r in route_rows {
        let rid: String = r.try_get("id").unwrap_or_default();
        let o: String = r.try_get("origin_city_id").unwrap_or_default();
        let d: String = r.try_get("dest_city_id").unwrap_or_default();
        let features: Option<String> = r.try_get("features").unwrap_or(None);
        route_ids.push(rid.clone());
        route_by_id.insert(rid, (o.clone(), d.clone(), features));
        if !o.is_empty() {
            city_ids.push(o);
        }
        if !d.is_empty() {
            city_ids.push(d);
        }
    }

    let mut sql = format!(
        "SELECT id,route_id,depart_at,arrive_at,price_cents,currency,seats_total,seats_available,status FROM {trips} WHERE route_id IN {}",
        make_in_clause(1, route_ids.len())
    );
    let mut idx = route_ids.len() + 1;
    if start.is_some() {
        sql.push_str(&format!(" AND depart_at >= ${idx}"));
        idx += 1;
    }
    if end.is_some() {
        sql.push_str(&format!(" AND depart_at < ${idx}"));
        idx += 1;
    }
    if status.is_some() {
        sql.push_str(&format!(" AND status = ${idx}"));
        idx += 1;
    }
    sql.push_str(&format!(
        " ORDER BY depart_at {} LIMIT ${idx}",
        if order == "asc" { "ASC" } else { "DESC" }
    ));

    let mut q = sqlx::query(&sql);
    for rid in &route_ids {
        q = q.bind(rid);
    }
    if let Some(s) = start {
        q = q.bind(s.to_rfc3339());
    }
    if let Some(e) = end {
        q = q.bind(e.to_rfc3339());
    }
    if let Some(st) = status.as_deref() {
        q = q.bind(st);
    }
    q = q.bind(limit);

    let trip_rows = q.fetch_all(&state.pool).await.map_err(|e| {
        tracing::error!(error=%e, "db operator_trips trips failed");
        ApiError::internal("database error")
    })?;

    let op = fetch_operator(&state, &ops, operator_id.trim())
        .await
        .unwrap_or(OperatorOut {
            id: operator_id.trim().to_string(),
            name: "".to_string(),
            wallet_id: None,
            is_online: false,
        });
    let city_map = fetch_cities_map(&state, &cities, &city_ids).await?;

    let mut out: Vec<TripSearchOut> = Vec::with_capacity(trip_rows.len());
    for r in trip_rows {
        let trip = TripOut {
            id: r.try_get("id").unwrap_or_default(),
            route_id: r.try_get("route_id").unwrap_or_default(),
            depart_at: row_dt(&r, "depart_at")?,
            arrive_at: row_dt(&r, "arrive_at")?,
            price_cents: r.try_get("price_cents").unwrap_or(0),
            currency: r.try_get("currency").unwrap_or_else(|_| "SYP".to_string()),
            seats_total: r.try_get("seats_total").unwrap_or(40),
            seats_available: r.try_get("seats_available").unwrap_or(40),
            status: r.try_get("status").unwrap_or_else(|_| "draft".to_string()),
        };
        let (o_id, d_id, features) = route_by_id.get(&trip.route_id).cloned().unwrap_or_default();
        let origin = city_map.get(&o_id).cloned().unwrap_or(CityOut {
            id: o_id.clone(),
            name: "".to_string(),
            country: None,
        });
        let dest = city_map.get(&d_id).cloned().unwrap_or(CityOut {
            id: d_id.clone(),
            name: "".to_string(),
            country: None,
        });
        out.push(TripSearchOut {
            trip,
            origin,
            dest,
            operator: op.clone(),
            features,
        });
    }
    Ok(axum::Json(out))
}

pub async fn trip_detail(
    Path(trip_id): Path<String>,
    State(state): State<AppState>,
) -> ApiResult<axum::Json<TripOut>> {
    let trips = state.table("trips");
    let sql = format!("SELECT id,route_id,depart_at,arrive_at,price_cents,currency,seats_total,seats_available,status FROM {trips} WHERE id=$1");
    let row = sqlx::query(&sql)
        .bind(trip_id.trim())
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!(error=%e, "db trip_detail failed");
            ApiError::internal("database error")
        })?
        .ok_or_else(|| ApiError::not_found("trip not found"))?;
    Ok(axum::Json(TripOut {
        id: row.try_get("id").unwrap_or_default(),
        route_id: row.try_get("route_id").unwrap_or_default(),
        depart_at: row_dt(&row, "depart_at")?,
        arrive_at: row_dt(&row, "arrive_at")?,
        price_cents: row.try_get("price_cents").unwrap_or(0),
        currency: row
            .try_get("currency")
            .unwrap_or_else(|_| "SYP".to_string()),
        seats_total: row.try_get("seats_total").unwrap_or(40),
        seats_available: row.try_get("seats_available").unwrap_or(40),
        status: row
            .try_get("status")
            .unwrap_or_else(|_| "draft".to_string()),
    }))
}

pub async fn publish_trip(
    Path(trip_id): Path<String>,
    State(state): State<AppState>,
) -> ApiResult<axum::Json<TripOut>> {
    set_trip_status(&state, trip_id.trim(), "published").await
}

pub async fn unpublish_trip(
    Path(trip_id): Path<String>,
    State(state): State<AppState>,
) -> ApiResult<axum::Json<TripOut>> {
    set_trip_status(&state, trip_id.trim(), "draft").await
}

pub async fn cancel_trip(
    Path(trip_id): Path<String>,
    State(state): State<AppState>,
) -> ApiResult<axum::Json<TripOut>> {
    set_trip_status(&state, trip_id.trim(), "canceled").await
}

async fn set_trip_status(
    state: &AppState,
    trip_id: &str,
    status: &str,
) -> ApiResult<axum::Json<TripOut>> {
    let trips = state.table("trips");
    let routes = state.table("routes");
    let ops = state.table("bus_operators");

    let row = sqlx::query(&format!(
        "SELECT id,route_id,depart_at,arrive_at,price_cents,currency,seats_total,seats_available,status FROM {trips} WHERE id=$1"
    ))
    .bind(trip_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(error=%e, "db set_trip_status trip lookup failed");
        ApiError::internal("database error")
    })?
    .ok_or_else(|| ApiError::not_found("trip not found"))?;

    let current_status: String = row
        .try_get("status")
        .unwrap_or_else(|_| "draft".to_string());
    if current_status == "canceled" && status != "canceled" {
        return Err(ApiError::bad_request("trip canceled"));
    }

    if status == "published" {
        // Enforce operator online on publish (mirrors Python).
        let route_id: String = row.try_get("route_id").unwrap_or_default();
        let rt = sqlx::query(&format!("SELECT operator_id FROM {routes} WHERE id=$1"))
            .bind(&route_id)
            .fetch_optional(&state.pool)
            .await
            .map_err(|e| {
                tracing::error!(error=%e, "db set_trip_status route lookup failed");
                ApiError::internal("database error")
            })?
            .ok_or_else(|| ApiError::not_found("route not found"))?;
        let op_id: String = rt.try_get("operator_id").unwrap_or_default();
        let op = sqlx::query(&format!("SELECT is_online FROM {ops} WHERE id=$1"))
            .bind(&op_id)
            .fetch_optional(&state.pool)
            .await
            .map_err(|e| {
                tracing::error!(error=%e, "db set_trip_status operator lookup failed");
                ApiError::internal("database error")
            })?
            .ok_or_else(|| ApiError::not_found("operator not found"))?;
        let is_online: i64 = op.try_get("is_online").unwrap_or(0);
        if is_online == 0 {
            return Err(ApiError::forbidden("operator offline"));
        }
    }

    if current_status == status {
        return Ok(axum::Json(row_to_trip_out(row)?));
    }

    let upd = sqlx::query(&format!("UPDATE {trips} SET status=$1 WHERE id=$2"))
        .bind(status)
        .bind(trip_id)
        .execute(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!(error=%e, "db set_trip_status update failed");
            ApiError::internal("database error")
        })?;
    if upd.rows_affected() == 0 {
        return Err(ApiError::not_found("trip not found"));
    }

    let row2 = sqlx::query(&format!(
        "SELECT id,route_id,depart_at,arrive_at,price_cents,currency,seats_total,seats_available,status FROM {trips} WHERE id=$1"
    ))
    .bind(trip_id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(error=%e, "db set_trip_status refetch failed");
        ApiError::internal("database error")
    })?;
    Ok(axum::Json(row_to_trip_out(row2)?))
}

fn row_to_trip_out(row: PgRow) -> ApiResult<TripOut> {
    Ok(TripOut {
        id: row.try_get("id").unwrap_or_default(),
        route_id: row.try_get("route_id").unwrap_or_default(),
        depart_at: row_dt(&row, "depart_at")?,
        arrive_at: row_dt(&row, "arrive_at")?,
        price_cents: row.try_get("price_cents").unwrap_or(0),
        currency: row
            .try_get("currency")
            .unwrap_or_else(|_| "SYP".to_string()),
        seats_total: row.try_get("seats_total").unwrap_or(40),
        seats_available: row.try_get("seats_available").unwrap_or(40),
        status: row
            .try_get("status")
            .unwrap_or_else(|_| "draft".to_string()),
    })
}

pub async fn quote(
    Path(trip_id): Path<String>,
    State(state): State<AppState>,
    Query(params): Query<QuoteParams>,
) -> ApiResult<axum::Json<QuoteOut>> {
    let seats = params.seats.unwrap_or(1);
    if !(1..=10).contains(&seats) {
        return Err(ApiError::bad_request("invalid seats"));
    }
    let trips = state.table("trips");
    let row = sqlx::query(&format!(
        "SELECT price_cents,currency FROM {trips} WHERE id=$1"
    ))
    .bind(trip_id.trim())
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(error=%e, "db quote failed");
        ApiError::internal("database error")
    })?
    .ok_or_else(|| ApiError::not_found("trip not found"))?;
    let price: i64 = row.try_get("price_cents").unwrap_or(0);
    let currency: String = row
        .try_get("currency")
        .unwrap_or_else(|_| "SYP".to_string());
    Ok(axum::Json(QuoteOut {
        trip_id: trip_id.trim().to_string(),
        seats,
        total_cents: price * seats as i64,
        currency,
    }))
}

fn seat_numbers_hash(seats: &[i32]) -> String {
    let mut v: Vec<i32> = seats.to_vec();
    v.sort_unstable();
    let normalized = v
        .iter()
        .map(|sn| sn.to_string())
        .collect::<Vec<_>>()
        .join(",");
    let digest = sha2::Sha256::digest(normalized.as_bytes());
    hex::encode(digest)
}

async fn payments_transfer(
    state: &AppState,
    booking_id: &str,
    action: &str,
    from_wallet: &str,
    to_wallet: &str,
    amount_cents: i64,
) -> Result<serde_json::Value, ApiError> {
    let base = state
        .payments_base_url
        .as_deref()
        .ok_or_else(|| ApiError::internal("PAYMENTS_BASE_URL not configured"))?;
    let booking_id = booking_id.trim();
    if booking_id.is_empty() {
        return Err(ApiError::internal(
            "booking_id required for payments transfer",
        ));
    }
    let action = action.trim().to_ascii_lowercase();
    if action != BUS_BOOKING_ACTION_CHARGE && action != BUS_BOOKING_ACTION_REFUND {
        return Err(ApiError::internal(
            "invalid payments booking transfer action",
        ));
    }
    let url = format!(
        "{}/internal/bus/bookings/transfer",
        base.trim_end_matches('/')
    );

    let mut req = state
        .http
        .post(url)
        .json(&serde_json::json!({
            "booking_id": booking_id,
            "action": action,
            "from_wallet_id": from_wallet,
            "to_wallet_id": to_wallet,
            "amount_cents": amount_cents,
        }))
        .header("Content-Type", "application/json");

    if let Some(secret) = state.bus_payments_internal_secret.as_deref() {
        req = req.header("X-Bus-Payments-Internal-Secret", secret);
    }
    let caller = state.internal_service_id.trim();
    if !caller.is_empty() {
        req = req.header("X-Internal-Service-Id", caller);
    }

    let resp = req.send().await.map_err(|e| {
        tracing::error!(error=%e, "payments transfer http error");
        ApiError::upstream("payment failed")
    })?;
    let status = resp.status();
    let body = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        // Best-effort extraction of payments error details.
        let mut msg = body.clone();
        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&body) {
            if let Some(d) = v.get("detail").and_then(|x| x.as_str()) {
                msg = d.to_string();
            }
        }
        let low = msg.to_lowercase();
        if low.contains("insufficient") && (low.contains("fund") || low.contains("balance")) {
            return Err(ApiError::bad_request("insufficient funds"));
        }
        if low.contains("cannot transfer to same wallet") {
            return Err(ApiError::bad_request("cannot transfer to same wallet"));
        }
        return Err(ApiError::internal("payment failed"));
    }

    serde_json::from_str(&body).map_err(|e| {
        tracing::error!(error=%e, "payments transfer invalid json");
        ApiError::upstream("payment failed")
    })
}

async fn fail_booking_and_release(state: &AppState, booking_id: &str) -> Result<(), ApiError> {
    let bookings = state.table("bookings");
    let trips = state.table("trips");
    let tickets = state.table("tickets");

    let mut tx = state.pool.begin().await.map_err(|e| {
        tracing::error!(error=%e, "db begin tx failed");
        ApiError::internal("database error")
    })?;

    let b_sql = format!(
        "SELECT id,trip_id,seats FROM {bookings} WHERE id=$1{}",
        for_update_suffix(state)
    );
    let b = sqlx::query(&b_sql)
        .bind(booking_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|e| {
            tracing::error!(error=%e, "db fail_booking booking lookup failed");
            ApiError::internal("database error")
        })?;
    let Some(b) = b else {
        tx.rollback().await.ok();
        return Ok(());
    };
    let trip_id: String = b.try_get("trip_id").unwrap_or_default();
    let seats: i32 = b.try_get("seats").unwrap_or(0);

    let t_sql = format!(
        "SELECT seats_total,seats_available FROM {trips} WHERE id=$1{}",
        for_update_suffix(state)
    );
    if let Some(t) = sqlx::query(&t_sql)
        .bind(&trip_id)
        .fetch_optional(&mut *tx)
        .await
        .ok()
        .flatten()
    {
        let seats_total: i32 = t.try_get("seats_total").unwrap_or(0);
        let seats_avail: i32 = t.try_get("seats_available").unwrap_or(0);
        let new_avail = (seats_avail + seats).min(seats_total);
        let _ = sqlx::query(&format!(
            "UPDATE {trips} SET seats_available=$1 WHERE id=$2"
        ))
        .bind(new_avail)
        .bind(&trip_id)
        .execute(&mut *tx)
        .await;
    }

    let _ = sqlx::query(&format!(
        "UPDATE {tickets} SET status='canceled' WHERE booking_id=$1"
    ))
    .bind(booking_id)
    .execute(&mut *tx)
    .await;
    let _ = sqlx::query(&format!(
        "UPDATE {bookings} SET status='failed' WHERE id=$1"
    ))
    .bind(booking_id)
    .execute(&mut *tx)
    .await;

    tx.commit().await.ok();
    Ok(())
}

fn parse_ticket_payload(raw: &str) -> Result<(String, String, String, i32, String), ApiError> {
    let raw = raw.trim();
    if raw.is_empty() {
        return Err(ApiError::bad_request("invalid payload"));
    }
    let parts: Vec<&str> = raw.split('|').collect();
    if parts.is_empty() || parts[0] != "TICKET" {
        return Err(ApiError::bad_request("invalid payload"));
    }
    let mut id = String::new();
    let mut b = String::new();
    let mut trip = String::new();
    let mut seat = 0i32;
    let mut sig = String::new();
    for kv in parts.iter().skip(1) {
        let Some((k, v)) = kv.split_once('=') else {
            continue;
        };
        match k {
            "id" => id = v.to_string(),
            "b" => b = v.to_string(),
            "trip" => trip = v.to_string(),
            "seat" => seat = v.parse::<i32>().unwrap_or(0),
            "sig" => sig = v.to_string(),
            _ => {}
        }
    }
    if id.is_empty() || b.is_empty() || trip.is_empty() || sig.is_empty() {
        return Err(ApiError::bad_request("invalid payload"));
    }
    Ok((id, b, trip, seat, sig))
}

pub async fn ticket_board(
    State(state): State<AppState>,
    axum::Json(body): axum::Json<BoardReq>,
) -> ApiResult<axum::Json<serde_json::Value>> {
    let (tid, bid, trip_id, seat, sig) = parse_ticket_payload(&body.payload)?;

    let tickets = state.table("tickets");
    let bookings = state.table("bookings");

    let mut tx = state.pool.begin().await.map_err(|e| {
        tracing::error!(error=%e, "db begin tx failed");
        ApiError::internal("database error")
    })?;

    let sql = format!(
        "SELECT id,booking_id,trip_id,seat_no,status,boarded_at FROM {tickets} WHERE id=$1{}",
        for_update_suffix(&state)
    );
    let row = sqlx::query(&sql)
        .bind(&tid)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|e| {
            tracing::error!(error=%e, "db ticket_board ticket lookup failed");
            ApiError::internal("database error")
        })?
        .ok_or_else(|| ApiError::not_found("ticket not found"))?;

    let db_booking_id: String = row.try_get("booking_id").unwrap_or_default();
    let db_trip_id: String = row.try_get("trip_id").unwrap_or_default();
    if db_booking_id != bid || db_trip_id != trip_id {
        return Err(ApiError::not_found("ticket not found"));
    }
    let status: String = row
        .try_get("status")
        .unwrap_or_else(|_| "issued".to_string());
    if status == "canceled" {
        return Err(ApiError::bad_request("ticket canceled"));
    }

    let expect = ticket_sig(&state.ticket_secret, &tid, &bid, &trip_id, seat);
    if expect.as_bytes().ct_eq(sig.as_bytes()).unwrap_u8() != 1 {
        return Err(ApiError::unauthorized("invalid signature"));
    }

    // Booking confirmation enforcement (when payments are enabled outside dev/test).
    let booking_row = sqlx::query(&format!(
        "SELECT status FROM {bookings} WHERE id=$1{}",
        for_update_suffix(&state)
    ))
    .bind(&db_booking_id)
    .fetch_optional(&mut *tx)
    .await
    .ok()
    .flatten();
    if let Some(br) = booking_row {
        let b_status: String = br
            .try_get("status")
            .unwrap_or_else(|_| "pending".to_string());
        if b_status != "confirmed"
            && state.payments_enabled()
            && !matches!(state.env_lower.as_str(), "dev" | "test")
        {
            return Err(ApiError::bad_request("booking not confirmed"));
        }
    }

    if status == "boarded" {
        let boarded_at: Option<DateTime<Utc>> = row_dt_opt(&row, "boarded_at");
        tx.rollback().await.ok();
        return Ok(axum::Json(serde_json::json!({
            "ok": true,
            "status": "already_boarded",
            "boarded_at": boarded_at,
        })));
    }

    let now = Utc::now();
    let upd = sqlx::query(&format!(
        "UPDATE {tickets} SET status='boarded', boarded_at=$1 WHERE id=$2"
    ))
    .bind(now.to_rfc3339())
    .bind(&tid)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error=%e, "db ticket_board update failed");
        ApiError::internal("database error")
    })?;
    if upd.rows_affected() == 0 {
        return Err(ApiError::not_found("ticket not found"));
    }
    tx.commit().await.ok();
    Ok(axum::Json(serde_json::json!({
        "ok": true,
        "status": "boarded",
        "boarded_at": now,
    })))
}

pub async fn booking_status(
    Path(booking_id): Path<String>,
    State(state): State<AppState>,
) -> ApiResult<axum::Json<BookingOut>> {
    booking_out(&state, booking_id.trim(), true)
        .await
        .map(axum::Json)
}

pub async fn booking_tickets(
    Path(booking_id): Path<String>,
    State(state): State<AppState>,
) -> ApiResult<axum::Json<Vec<TicketOut>>> {
    let tickets = state.table("tickets");
    let rows = sqlx::query(&format!(
        "SELECT id,booking_id,trip_id,seat_no,status FROM {tickets} WHERE booking_id=$1 ORDER BY seat_no ASC"
    ))
    .bind(booking_id.trim())
    .fetch_all(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(error=%e, "db booking_tickets failed");
        ApiError::internal("database error")
    })?;

    let mut out = Vec::with_capacity(rows.len());
    for r in rows {
        let tid: String = r.try_get("id").unwrap_or_default();
        let bid: String = r.try_get("booking_id").unwrap_or_default();
        let trip_id: String = r.try_get("trip_id").unwrap_or_default();
        let seat_no: Option<i32> = r.try_get("seat_no").unwrap_or(None);
        let status: String = r.try_get("status").unwrap_or_else(|_| "issued".to_string());
        let payload = ticket_payload(
            &state.ticket_secret,
            &tid,
            &bid,
            &trip_id,
            seat_no.unwrap_or(0),
        );
        out.push(TicketOut {
            id: tid,
            booking_id: bid,
            trip_id,
            seat_no,
            status,
            payload,
        });
    }
    Ok(axum::Json(out))
}

pub async fn booking_search(
    State(state): State<AppState>,
    Query(params): Query<BookingSearchParams>,
) -> ApiResult<axum::Json<Vec<BookingSearchOut>>> {
    let wallet_id = params
        .wallet_id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let phone = params
        .phone
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    if wallet_id.is_none() && phone.is_none() {
        return Err(ApiError::bad_request("wallet_id or phone required"));
    }
    let limit = normalize_limit(params.limit, 20, 1, 100);

    let bookings = state.table("bookings");
    let mut sql = format!(
        "SELECT id,trip_id,seats,status,created_at,wallet_id,customer_phone FROM {bookings}"
    );
    let mut binds: Vec<String> = Vec::new();
    if let Some(w) = wallet_id {
        binds.push(w.to_string());
        sql.push_str(&format!(" WHERE wallet_id=${}", binds.len()));
    }
    if let Some(p) = phone {
        binds.push(p.to_string());
        if binds.len() == 1 {
            sql.push_str(&format!(" WHERE customer_phone=${}", binds.len()));
        } else {
            sql.push_str(&format!(" AND customer_phone=${}", binds.len()));
        }
    }
    sql.push_str(&format!(
        " ORDER BY created_at DESC LIMIT ${}",
        binds.len() + 1
    ));

    let mut q = sqlx::query(&sql);
    for b in &binds {
        q = q.bind(b);
    }
    q = q.bind(limit);
    let rows = q.fetch_all(&state.pool).await.map_err(|e| {
        tracing::error!(error=%e, "db booking_search failed");
        ApiError::internal("database error")
    })?;
    if rows.is_empty() {
        return Ok(axum::Json(vec![]));
    }

    let mut booking_rows: Vec<BookingRow> = Vec::with_capacity(rows.len());
    let mut trip_ids: Vec<String> = Vec::new();
    for r in rows {
        let id: String = r.try_get("id").unwrap_or_default();
        let trip_id: String = r.try_get("trip_id").unwrap_or_default();
        let seats: i32 = r.try_get("seats").unwrap_or(0);
        let status: String = r
            .try_get("status")
            .unwrap_or_else(|_| "pending".to_string());
        let created_at: Option<DateTime<Utc>> = row_dt_opt(&r, "created_at");
        let wallet_id: Option<String> = r.try_get("wallet_id").unwrap_or(None);
        let customer_phone: Option<String> = r.try_get("customer_phone").unwrap_or(None);
        booking_rows.push(BookingRow {
            id: id.clone(),
            trip_id: trip_id.clone(),
            seats,
            status,
            created_at,
            wallet_id,
            customer_phone,
        });
        if !trip_id.is_empty() {
            trip_ids.push(trip_id);
        }
    }

    let trip_map = fetch_trips_map(&state, &trip_ids).await?;
    let mut route_ids: Vec<String> = Vec::new();
    for t in trip_map.values() {
        if !t.route_id.is_empty() {
            route_ids.push(t.route_id.clone());
        }
    }
    let route_map = fetch_routes_map(&state, &route_ids).await?;
    let mut city_ids: Vec<String> = Vec::new();
    let mut op_ids: Vec<String> = Vec::new();
    for r in route_map.values() {
        if !r.origin_city_id.is_empty() {
            city_ids.push(r.origin_city_id.clone());
        }
        if !r.dest_city_id.is_empty() {
            city_ids.push(r.dest_city_id.clone());
        }
        if !r.operator_id.is_empty() {
            op_ids.push(r.operator_id.clone());
        }
    }
    let city_map = fetch_cities_map(&state, &state.table("cities"), &city_ids).await?;
    let op_map = fetch_operators_map(&state, &state.table("bus_operators"), &op_ids).await?;

    let mut out: Vec<BookingSearchOut> = Vec::with_capacity(booking_rows.len());
    for br in booking_rows {
        let Some(trip) = trip_map.get(&br.trip_id).cloned() else {
            continue;
        };
        let rt = route_map.get(&trip.route_id);
        let (origin, dest, operator) = if let Some(rt) = rt {
            let origin = city_map
                .get(&rt.origin_city_id)
                .cloned()
                .unwrap_or(CityOut {
                    id: rt.origin_city_id.clone(),
                    name: "".to_string(),
                    country: None,
                });
            let dest = city_map.get(&rt.dest_city_id).cloned().unwrap_or(CityOut {
                id: rt.dest_city_id.clone(),
                name: "".to_string(),
                country: None,
            });
            let operator = op_map.get(&rt.operator_id).cloned().unwrap_or(OperatorOut {
                id: rt.operator_id.clone(),
                name: "".to_string(),
                wallet_id: None,
                is_online: false,
            });
            (origin, dest, operator)
        } else {
            (
                CityOut {
                    id: "".to_string(),
                    name: "".to_string(),
                    country: None,
                },
                CityOut {
                    id: "".to_string(),
                    name: "".to_string(),
                    country: None,
                },
                OperatorOut {
                    id: "".to_string(),
                    name: "".to_string(),
                    wallet_id: None,
                    is_online: false,
                },
            )
        };
        out.push(BookingSearchOut {
            id: br.id,
            trip,
            origin,
            dest,
            operator,
            seats: br.seats,
            status: br.status,
            created_at: br.created_at,
            wallet_id: br.wallet_id,
            customer_phone: br.customer_phone,
        });
    }
    Ok(axum::Json(out))
}

pub async fn admin_summary(
    State(state): State<AppState>,
) -> ApiResult<axum::Json<AdminSummaryOut>> {
    let now = Utc::now();
    let start_today = Utc
        .with_ymd_and_hms(now.year(), now.month(), now.day(), 0, 0, 0)
        .single()
        .unwrap_or(now);
    let end_today = start_today + Duration::days(1);
    let start_today_s = start_today.to_rfc3339();
    let end_today_s = end_today.to_rfc3339();

    let ops = state.table("bus_operators");
    let routes = state.table("routes");
    let trips = state.table("trips");
    let bookings = state.table("bookings");

    let operators: i64 =
        scalar_i64(&state, &format!("SELECT COUNT(id) AS c FROM {ops}"), "c").await?;
    let routes_count: i64 =
        scalar_i64(&state, &format!("SELECT COUNT(id) AS c FROM {routes}"), "c").await?;
    let trips_total: i64 =
        scalar_i64(&state, &format!("SELECT COUNT(id) AS c FROM {trips}"), "c").await?;
    let trips_today: i64 = scalar_i64_binds(
        &state,
        &format!("SELECT COUNT(id) AS c FROM {trips} WHERE depart_at >= $1 AND depart_at < $2"),
        &[start_today_s.as_str(), end_today_s.as_str()],
        "c",
    )
    .await?;
    let bookings_total: i64 = scalar_i64(
        &state,
        &format!("SELECT COUNT(id) AS c FROM {bookings}"),
        "c",
    )
    .await?;
    let bookings_today: i64 = scalar_i64_binds(
        &state,
        &format!("SELECT COUNT(id) AS c FROM {bookings} WHERE created_at >= $1"),
        &[start_today_s.as_str()],
        "c",
    )
    .await?;

    let confirmed_today = sqlx::query(&format!(
        "SELECT id,trip_id,seats FROM {bookings} WHERE created_at >= $1 AND status='confirmed'"
    ))
    .bind(start_today_s)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(error=%e, "db admin_summary confirmed_today failed");
        ApiError::internal("database error")
    })?;
    let confirmed_today_count = confirmed_today.len() as i64;

    let mut trip_ids: Vec<String> = Vec::new();
    let mut confirmed: Vec<(String, String, i32)> = Vec::with_capacity(confirmed_today.len());
    for r in confirmed_today {
        let bid: String = r.try_get("id").unwrap_or_default();
        let tid: String = r.try_get("trip_id").unwrap_or_default();
        let seats: i32 = r.try_get("seats").unwrap_or(0);
        confirmed.push((bid, tid.clone(), seats));
        if !tid.is_empty() {
            trip_ids.push(tid);
        }
    }
    let trip_map = fetch_trips_map(&state, &trip_ids).await?;
    let mut revenue_cents_today: i64 = 0;
    for (_, tid, seats) in confirmed {
        if let Some(t) = trip_map.get(&tid) {
            revenue_cents_today += t.price_cents * seats as i64;
        }
    }

    Ok(axum::Json(AdminSummaryOut {
        operators,
        routes: routes_count,
        trips_total,
        trips_today,
        bookings_total,
        bookings_today,
        bookings_confirmed_today: confirmed_today_count,
        revenue_cents_today,
    }))
}

pub async fn operator_stats(
    Path(operator_id): Path<String>,
    State(state): State<AppState>,
    Query(params): Query<OperatorStatsParams>,
) -> ApiResult<axum::Json<OperatorStatsOut>> {
    let period = params.period.unwrap_or_else(|| "today".to_string());
    let now = Utc::now();
    let start = match period.as_str() {
        "today" => Utc
            .with_ymd_and_hms(now.year(), now.month(), now.day(), 0, 0, 0)
            .single()
            .unwrap_or(now),
        "7d" => now - Duration::days(7),
        "30d" => now - Duration::days(30),
        _ => return Err(ApiError::bad_request("invalid period")),
    };

    let routes = state.table("routes");
    let trips = state.table("trips");
    let bookings = state.table("bookings");
    let tickets = state.table("tickets");

    let route_rows = sqlx::query(&format!("SELECT id FROM {routes} WHERE operator_id=$1"))
        .bind(operator_id.trim())
        .fetch_all(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!(error=%e, "db operator_stats routes failed");
            ApiError::internal("database error")
        })?;
    if route_rows.is_empty() {
        return Ok(axum::Json(OperatorStatsOut {
            operator_id: operator_id.trim().to_string(),
            period,
            trips: 0,
            bookings: 0,
            confirmed_bookings: 0,
            seats_sold: 0,
            seats_total: 0,
            seats_boarded: 0,
            revenue_cents: 0,
        }));
    }
    let mut route_ids: Vec<String> = Vec::with_capacity(route_rows.len());
    for r in route_rows {
        let rid: String = r.try_get("id").unwrap_or_default();
        if !rid.is_empty() {
            route_ids.push(rid);
        }
    }

    let trips_sql = format!(
        "SELECT id,route_id,depart_at,arrive_at,price_cents,currency,seats_total,seats_available,status FROM {trips} WHERE route_id IN {} AND depart_at >= ${}",
        make_in_clause(1, route_ids.len()),
        route_ids.len() + 1
    );
    let mut q = sqlx::query(&trips_sql);
    for rid in &route_ids {
        q = q.bind(rid);
    }
    q = q.bind(start.to_rfc3339());
    let trip_rows = q.fetch_all(&state.pool).await.map_err(|e| {
        tracing::error!(error=%e, "db operator_stats trips failed");
        ApiError::internal("database error")
    })?;

    let mut trip_ids: Vec<String> = Vec::with_capacity(trip_rows.len());
    let mut trip_map: std::collections::HashMap<String, TripOut> = std::collections::HashMap::new();
    let mut seats_total: i32 = 0;
    for r in trip_rows {
        let trip = TripOut {
            id: r.try_get("id").unwrap_or_default(),
            route_id: r.try_get("route_id").unwrap_or_default(),
            depart_at: row_dt(&r, "depart_at")?,
            arrive_at: row_dt(&r, "arrive_at")?,
            price_cents: r.try_get("price_cents").unwrap_or(0),
            currency: r.try_get("currency").unwrap_or_else(|_| "SYP".to_string()),
            seats_total: r.try_get("seats_total").unwrap_or(40),
            seats_available: r.try_get("seats_available").unwrap_or(40),
            status: r.try_get("status").unwrap_or_else(|_| "draft".to_string()),
        };
        seats_total += trip.seats_total;
        trip_ids.push(trip.id.clone());
        trip_map.insert(trip.id.clone(), trip);
    }
    if trip_ids.is_empty() {
        return Ok(axum::Json(OperatorStatsOut {
            operator_id: operator_id.trim().to_string(),
            period,
            trips: 0,
            bookings: 0,
            confirmed_bookings: 0,
            seats_sold: 0,
            seats_total: 0,
            seats_boarded: 0,
            revenue_cents: 0,
        }));
    }

    let book_sql = format!(
        "SELECT id,trip_id,seats,status,created_at FROM {bookings} WHERE trip_id IN {} AND created_at >= ${}",
        make_in_clause(1, trip_ids.len()),
        trip_ids.len() + 1
    );
    let mut qb = sqlx::query(&book_sql);
    for tid in &trip_ids {
        qb = qb.bind(tid);
    }
    qb = qb.bind(start.to_rfc3339());
    let booking_rows = qb.fetch_all(&state.pool).await.map_err(|e| {
        tracing::error!(error=%e, "db operator_stats bookings failed");
        ApiError::internal("database error")
    })?;

    let mut confirmed_bookings = 0i32;
    let mut seats_sold = 0i32;
    let mut revenue_cents: i64 = 0;
    for b in booking_rows.iter() {
        let status: String = b
            .try_get("status")
            .unwrap_or_else(|_| "pending".to_string());
        if status == "confirmed" {
            confirmed_bookings += 1;
            let seats: i32 = b.try_get("seats").unwrap_or(0);
            seats_sold += seats;
            let tid: String = b.try_get("trip_id").unwrap_or_default();
            if let Some(t) = trip_map.get(&tid) {
                revenue_cents += t.price_cents * seats as i64;
            }
        }
    }

    let boarded_sql = format!(
        "SELECT COUNT(id) AS c FROM {tickets} WHERE trip_id IN {} AND status='boarded' AND boarded_at >= ${}",
        make_in_clause(1, trip_ids.len()),
        trip_ids.len() + 1
    );
    let mut qt = sqlx::query(&boarded_sql);
    for tid in &trip_ids {
        qt = qt.bind(tid);
    }
    qt = qt.bind(start.to_rfc3339());
    let seats_boarded: i64 = qt
        .fetch_one(&state.pool)
        .await
        .ok()
        .and_then(|r| r.try_get::<i64, _>("c").ok())
        .unwrap_or(0);

    Ok(axum::Json(OperatorStatsOut {
        operator_id: operator_id.trim().to_string(),
        period,
        trips: trip_ids.len() as i32,
        bookings: booking_rows.len() as i32,
        confirmed_bookings,
        seats_sold,
        seats_total,
        seats_boarded: seats_boarded as i32,
        revenue_cents,
    }))
}

// Helpers: simple scalar queries
async fn scalar_i64(state: &AppState, sql: &str, col: &str) -> ApiResult<i64> {
    let row = sqlx::query(sql).fetch_one(&state.pool).await.map_err(|e| {
        tracing::error!(error=%e, "db scalar query failed");
        ApiError::internal("database error")
    })?;
    Ok(row.try_get::<i64, _>(col).unwrap_or(0))
}

async fn scalar_i64_binds(
    state: &AppState,
    sql: &str,
    binds: &[&str],
    col: &str,
) -> ApiResult<i64> {
    let mut q = sqlx::query(sql);
    for b in binds {
        q = q.bind(*b);
    }
    let row = q.fetch_one(&state.pool).await.map_err(|e| {
        tracing::error!(error=%e, "db scalar query failed");
        ApiError::internal("database error")
    })?;
    Ok(row.try_get::<i64, _>(col).unwrap_or(0))
}

fn make_in_clause(start_index: usize, n: usize) -> String {
    let mut parts: Vec<String> = Vec::with_capacity(n);
    for i in 0..n {
        parts.push(format!("${}", start_index + i));
    }
    format!("({})", parts.join(","))
}

async fn fetch_city(state: &AppState, cities_table: &str, city_id: &str) -> Option<CityOut> {
    let row = sqlx::query(&format!(
        "SELECT id,name,country FROM {cities_table} WHERE id=$1"
    ))
    .bind(city_id)
    .fetch_optional(&state.pool)
    .await
    .ok()
    .flatten()?;
    Some(CityOut {
        id: row.try_get("id").unwrap_or_default(),
        name: row.try_get("name").unwrap_or_default(),
        country: row.try_get("country").unwrap_or(None),
    })
}

async fn fetch_operator(state: &AppState, ops_table: &str, op_id: &str) -> Option<OperatorOut> {
    let row = sqlx::query(&format!(
        "SELECT id,name,wallet_id,is_online FROM {ops_table} WHERE id=$1"
    ))
    .bind(op_id)
    .fetch_optional(&state.pool)
    .await
    .ok()
    .flatten()?;
    let is_online: i64 = row.try_get("is_online").unwrap_or(0);
    Some(OperatorOut {
        id: row.try_get("id").unwrap_or_default(),
        name: row.try_get("name").unwrap_or_default(),
        wallet_id: row.try_get("wallet_id").unwrap_or(None),
        is_online: is_online != 0,
    })
}

async fn fetch_cities_map(
    state: &AppState,
    cities_table: &str,
    city_ids: &[String],
) -> ApiResult<std::collections::HashMap<String, CityOut>> {
    let ids: Vec<String> = city_ids
        .iter()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();
    if ids.is_empty() {
        return Ok(std::collections::HashMap::new());
    }
    let sql = format!(
        "SELECT id,name,country FROM {cities_table} WHERE id IN {}",
        make_in_clause(1, ids.len())
    );
    let mut q = sqlx::query(&sql);
    for id in &ids {
        q = q.bind(id);
    }
    let rows = q.fetch_all(&state.pool).await.map_err(|e| {
        tracing::error!(error=%e, "db fetch_cities_map failed");
        ApiError::internal("database error")
    })?;
    let mut out = std::collections::HashMap::new();
    for r in rows {
        let id: String = r.try_get("id").unwrap_or_default();
        out.insert(
            id.clone(),
            CityOut {
                id,
                name: r.try_get("name").unwrap_or_default(),
                country: r.try_get("country").unwrap_or(None),
            },
        );
    }
    Ok(out)
}

async fn fetch_operators_map(
    state: &AppState,
    ops_table: &str,
    op_ids: &[String],
) -> ApiResult<std::collections::HashMap<String, OperatorOut>> {
    let ids: Vec<String> = op_ids
        .iter()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();
    if ids.is_empty() {
        return Ok(std::collections::HashMap::new());
    }
    let sql = format!(
        "SELECT id,name,wallet_id,is_online FROM {ops_table} WHERE id IN {}",
        make_in_clause(1, ids.len())
    );
    let mut q = sqlx::query(&sql);
    for id in &ids {
        q = q.bind(id);
    }
    let rows = q.fetch_all(&state.pool).await.map_err(|e| {
        tracing::error!(error=%e, "db fetch_operators_map failed");
        ApiError::internal("database error")
    })?;
    let mut out = std::collections::HashMap::new();
    for r in rows {
        let id: String = r.try_get("id").unwrap_or_default();
        let is_online: i64 = r.try_get("is_online").unwrap_or(0);
        out.insert(
            id.clone(),
            OperatorOut {
                id,
                name: r.try_get("name").unwrap_or_default(),
                wallet_id: r.try_get("wallet_id").unwrap_or(None),
                is_online: is_online != 0,
            },
        );
    }
    Ok(out)
}

async fn fetch_trips_map(
    state: &AppState,
    trip_ids: &[String],
) -> ApiResult<std::collections::HashMap<String, TripOut>> {
    let trips = state.table("trips");
    let ids: Vec<String> = trip_ids
        .iter()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();
    if ids.is_empty() {
        return Ok(std::collections::HashMap::new());
    }
    let sql = format!(
        "SELECT id,route_id,depart_at,arrive_at,price_cents,currency,seats_total,seats_available,status FROM {trips} WHERE id IN {}",
        make_in_clause(1, ids.len())
    );
    let mut q = sqlx::query(&sql);
    for id in &ids {
        q = q.bind(id);
    }
    let rows = q.fetch_all(&state.pool).await.map_err(|e| {
        tracing::error!(error=%e, "db fetch_trips_map failed");
        ApiError::internal("database error")
    })?;
    let mut out = std::collections::HashMap::new();
    for r in rows {
        let id: String = r.try_get("id").unwrap_or_default();
        out.insert(
            id.clone(),
            TripOut {
                id,
                route_id: r.try_get("route_id").unwrap_or_default(),
                depart_at: row_dt(&r, "depart_at")?,
                arrive_at: row_dt(&r, "arrive_at")?,
                price_cents: r.try_get("price_cents").unwrap_or(0),
                currency: r.try_get("currency").unwrap_or_else(|_| "SYP".to_string()),
                seats_total: r.try_get("seats_total").unwrap_or(40),
                seats_available: r.try_get("seats_available").unwrap_or(40),
                status: r.try_get("status").unwrap_or_else(|_| "draft".to_string()),
            },
        );
    }
    Ok(out)
}

async fn fetch_routes_map(
    state: &AppState,
    route_ids: &[String],
) -> ApiResult<std::collections::HashMap<String, RouteOut>> {
    let routes = state.table("routes");
    let ids: Vec<String> = route_ids
        .iter()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();
    if ids.is_empty() {
        return Ok(std::collections::HashMap::new());
    }
    let sql = format!(
        "SELECT id,origin_city_id,dest_city_id,operator_id,bus_model,features FROM {routes} WHERE id IN {}",
        make_in_clause(1, ids.len())
    );
    let mut q = sqlx::query(&sql);
    for id in &ids {
        q = q.bind(id);
    }
    let rows = q.fetch_all(&state.pool).await.map_err(|e| {
        tracing::error!(error=%e, "db fetch_routes_map failed");
        ApiError::internal("database error")
    })?;
    let mut out = std::collections::HashMap::new();
    for r in rows {
        let id: String = r.try_get("id").unwrap_or_default();
        out.insert(
            id.clone(),
            RouteOut {
                id,
                origin_city_id: r.try_get("origin_city_id").unwrap_or_default(),
                dest_city_id: r.try_get("dest_city_id").unwrap_or_default(),
                operator_id: r.try_get("operator_id").unwrap_or_default(),
                bus_model: r.try_get("bus_model").unwrap_or(None),
                features: r.try_get("features").unwrap_or(None),
            },
        );
    }
    Ok(out)
}

async fn booking_out(
    state: &AppState,
    booking_id: &str,
    include_tickets: bool,
) -> ApiResult<BookingOut> {
    let bookings = state.table("bookings");
    let tickets_table = state.table("tickets");
    let b = sqlx::query(&format!(
        "SELECT id,trip_id,seats,status,payments_txn_id,created_at,wallet_id,customer_phone FROM {bookings} WHERE id=$1"
    ))
    .bind(booking_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(error=%e, "db booking_out booking lookup failed");
        ApiError::internal("database error")
    })?
    .ok_or_else(|| ApiError::not_found("not found"))?;

    let mut tickets: Option<Vec<TicketPayload>> = None;
    if include_tickets {
        let rows = sqlx::query(&format!(
            "SELECT id,booking_id,trip_id,seat_no,status FROM {tickets_table} WHERE booking_id=$1 ORDER BY seat_no ASC"
        ))
        .bind(booking_id)
        .fetch_all(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!(error=%e, "db booking_out tickets lookup failed");
            ApiError::internal("database error")
        })?;
        let mut v: Vec<TicketPayload> = Vec::with_capacity(rows.len());
        for r in rows {
            let tid: String = r.try_get("id").unwrap_or_default();
            let bid: String = r.try_get("booking_id").unwrap_or_default();
            let trip_id: String = r.try_get("trip_id").unwrap_or_default();
            let seat_no: Option<i32> = r.try_get("seat_no").unwrap_or(None);
            v.push(TicketPayload {
                id: tid.clone(),
                payload: ticket_payload(
                    &state.ticket_secret,
                    &tid,
                    &bid,
                    &trip_id,
                    seat_no.unwrap_or(0),
                ),
            });
        }
        tickets = Some(v);
    }

    Ok(BookingOut {
        id: b.try_get("id").unwrap_or_default(),
        trip_id: b.try_get("trip_id").unwrap_or_default(),
        seats: b.try_get("seats").unwrap_or(0),
        status: b
            .try_get("status")
            .unwrap_or_else(|_| "pending".to_string()),
        payments_txn_id: b.try_get("payments_txn_id").unwrap_or(None),
        created_at: row_dt_opt(&b, "created_at"),
        wallet_id: b.try_get("wallet_id").unwrap_or(None),
        customer_phone: b.try_get("customer_phone").unwrap_or(None),
        tickets,
    })
}

pub async fn book_trip(
    Path(trip_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::Json(body): axum::Json<BookReq>,
) -> ApiResult<axum::Json<BookingOut>> {
    let trip_id = trip_id.trim().to_string();
    if trip_id.is_empty() {
        return Err(ApiError::bad_request("trip_id required"));
    }

    let env_test = state.env_lower == "test";
    let require_payment = state.payments_enabled() && !env_test;

    let wallet_id = body
        .wallet_id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string());
    if require_payment && wallet_id.is_none() {
        return Err(ApiError::bad_request("wallet_id required for booking"));
    }

    let trips = state.table("trips");
    let trip_row = sqlx::query(&format!(
        "SELECT id,route_id,depart_at,arrive_at,price_cents,currency,seats_total,seats_available,status FROM {trips} WHERE id=$1"
    ))
    .bind(&trip_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(error=%e, "db book_trip trip lookup failed");
        ApiError::internal("database error")
    })?
    .ok_or_else(|| ApiError::not_found("trip not found"))?;

    let trip_status: String = trip_row
        .try_get("status")
        .unwrap_or_else(|_| "draft".to_string());
    if trip_status != "published" && !env_test {
        return Err(ApiError::bad_request("trip not published"));
    }

    let seats_total: i32 = trip_row.try_get("seats_total").unwrap_or(40);
    let price_cents: i64 = trip_row.try_get("price_cents").unwrap_or(0);
    let route_id: String = trip_row.try_get("route_id").unwrap_or_default();

    // Seat selection validation
    let mut seat_numbers: Vec<i32> = Vec::new();
    if let Some(arr) = body.seat_numbers {
        if arr.is_empty() {
            return Err(ApiError::bad_request("seat_numbers cannot be empty"));
        }
        let mut seen = std::collections::HashSet::new();
        for sn in arr {
            if sn < 1 || sn > seats_total {
                return Err(ApiError::bad_request("seat_numbers out of range"));
            }
            if !seen.insert(sn) {
                return Err(ApiError::bad_request("seat_numbers must be unique"));
            }
            seat_numbers.push(sn);
        }
    }

    let seats_requested = if !seat_numbers.is_empty() {
        seat_numbers.len() as i32
    } else {
        body.seats
    };
    if !(1..=10).contains(&seats_requested) {
        return Err(ApiError::bad_request("invalid seats"));
    }

    let seat_numbers_hash_val = if !seat_numbers.is_empty() {
        Some(seat_numbers_hash(&seat_numbers))
    } else {
        None
    };

    let idempotency_key = headers
        .get("Idempotency-Key")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());

    if let Some(k) = idempotency_key.as_deref() {
        if k.len() > 120 {
            return Err(ApiError::bad_request("Idempotency-Key too long"));
        }
    }

    let idempotency = state.table("idempotency");
    let bookings = state.table("bookings");

    // Idempotency handling (match semantics from the Python service).
    let mut existing_booking_id: Option<String> = None;
    if let Some(ikey) = idempotency_key.as_deref() {
        let row = sqlx::query(&format!(
            "SELECT trip_id,wallet_id,seats,seat_numbers_hash,booking_id FROM {idempotency} WHERE key=$1"
        ))
        .bind(ikey)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!(error=%e, "db idempotency lookup failed");
            ApiError::internal("database error")
        })?;

        if let Some(idem) = row {
            let idem_trip: Option<String> = idem.try_get("trip_id").unwrap_or(None);
            let idem_wallet: Option<String> = idem.try_get("wallet_id").unwrap_or(None);
            let idem_seats: Option<i32> = idem.try_get("seats").unwrap_or(None);
            let idem_hash: Option<String> = idem.try_get("seat_numbers_hash").unwrap_or(None);
            let idem_booking: Option<String> = idem.try_get("booking_id").unwrap_or(None);

            if idem_trip.as_deref().unwrap_or("") != trip_id
                || idem_wallet.as_deref().unwrap_or("") != wallet_id.as_deref().unwrap_or("")
                || idem_seats.unwrap_or(0) != seats_requested
                || idem_hash.as_deref().unwrap_or("")
                    != seat_numbers_hash_val.as_deref().unwrap_or("")
            {
                return Err(ApiError::conflict(
                    "Idempotency-Key reused with different parameters",
                ));
            }

            if let Some(bid) = idem_booking {
                if let Some(b) = sqlx::query(&format!("SELECT status FROM {bookings} WHERE id=$1"))
                    .bind(&bid)
                    .fetch_optional(&state.pool)
                    .await
                    .ok()
                    .flatten()
                {
                    let st: String = b
                        .try_get("status")
                        .unwrap_or_else(|_| "pending".to_string());
                    if require_payment && st == "pending" {
                        existing_booking_id = Some(bid);
                    } else {
                        // Return existing booking as-is.
                        let out = booking_out(&state, &bid, true).await?;
                        return Ok(axum::Json(out));
                    }
                }
            }
        } else {
            let now = Utc::now();
            let sql = format!(
                "INSERT INTO {idempotency} (key,trip_id,wallet_id,seats,seat_numbers_hash,created_at) VALUES ($1,$2,$3,$4,$5,$6)"
            );
            // Best-effort insert. If it races, the unique constraint will trip and the next request will re-read.
            let _ = sqlx::query(&sql)
                .bind(ikey)
                .bind(&trip_id)
                .bind(&wallet_id)
                .bind(seats_requested)
                .bind(&seat_numbers_hash_val)
                .bind(now.to_rfc3339())
                .execute(&state.pool)
                .await;
        }
    }

    // Reserve seats + create booking if we didn't already create one for this idempotency key.
    let booking_id = if let Some(bid) = existing_booking_id.clone() {
        bid
    } else {
        let ticket_status = if require_payment { "pending" } else { "issued" };

        let tickets = state.table("tickets");
        let mut tx = state.pool.begin().await.map_err(|e| {
            tracing::error!(error=%e, "db begin tx failed");
            ApiError::internal("database error")
        })?;

        // Lock trip and check availability.
        let trip_lock_sql = format!(
            "SELECT seats_total,seats_available FROM {trips} WHERE id=$1{}",
            for_update_suffix(&state)
        );
        let locked = sqlx::query(&trip_lock_sql)
            .bind(&trip_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|e| {
                tracing::error!(error=%e, "db trip lock failed");
                ApiError::internal("database error")
            })?
            .ok_or_else(|| ApiError::not_found("trip not found"))?;
        let seats_avail: i32 = locked.try_get("seats_available").unwrap_or(0);
        let seats_total_locked: i32 = locked.try_get("seats_total").unwrap_or(seats_total);
        if seats_avail < seats_requested {
            return Err(ApiError::bad_request("not enough seats"));
        }

        // Taken seats
        let taken_sql = format!(
            "SELECT seat_no FROM {tickets} WHERE trip_id=$1 AND seat_no IS NOT NULL AND status != 'canceled'{}",
            for_update_suffix(&state)
        );
        let taken_rows = sqlx::query(&taken_sql)
            .bind(&trip_id)
            .fetch_all(&mut *tx)
            .await
            .map_err(|e| {
                tracing::error!(error=%e, "db taken seats query failed");
                ApiError::internal("database error")
            })?;
        let mut taken: std::collections::HashSet<i32> = std::collections::HashSet::new();
        for r in taken_rows {
            if let Ok(Some(sn)) = r.try_get::<Option<i32>, _>("seat_no") {
                taken.insert(sn);
            }
        }

        let assigned: Vec<i32> = if !seat_numbers.is_empty() {
            for sn in &seat_numbers {
                if taken.contains(sn) {
                    return Err(ApiError::bad_request(
                        "one or more selected seats already booked",
                    ));
                }
            }
            seat_numbers.clone()
        } else {
            let mut v: Vec<i32> = Vec::with_capacity(seats_requested as usize);
            for sn in 1..=seats_total_locked {
                if taken.contains(&sn) {
                    continue;
                }
                v.push(sn);
                if v.len() == seats_requested as usize {
                    break;
                }
            }
            if v.len() != seats_requested as usize {
                return Err(ApiError::bad_request("not enough seats"));
            }
            v
        };

        // Update availability.
        let new_avail = seats_avail - seats_requested;
        sqlx::query(&format!(
            "UPDATE {trips} SET seats_available=$1 WHERE id=$2"
        ))
        .bind(new_avail)
        .bind(&trip_id)
        .execute(&mut *tx)
        .await
        .map_err(|e| {
            tracing::error!(error=%e, "db trip update failed");
            ApiError::internal("database error")
        })?;

        let bid = Uuid::new_v4().to_string();
        let now = Utc::now();
        sqlx::query(&format!(
            "INSERT INTO {bookings} (id,trip_id,price_cents,customer_phone,wallet_id,seats,status,created_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)"
        ))
        .bind(&bid)
        .bind(&trip_id)
        .bind(price_cents)
        .bind(body.customer_phone.as_deref().map(str::trim).filter(|s| !s.is_empty()))
        .bind(&wallet_id)
        .bind(seats_requested)
        .bind("pending")
        .bind(now.to_rfc3339())
        .execute(&mut *tx)
        .await
        .map_err(|e| {
            tracing::error!(error=%e, "db booking insert failed");
            ApiError::internal("database error")
        })?;

        for sn in &assigned {
            let tid = Uuid::new_v4().to_string();
            sqlx::query(&format!(
                "INSERT INTO {tickets} (id,booking_id,trip_id,seat_no,status,issued_at) VALUES ($1,$2,$3,$4,$5,$6)"
            ))
            .bind(&tid)
            .bind(&bid)
            .bind(&trip_id)
            .bind(*sn)
            .bind(ticket_status)
            .bind(now.to_rfc3339())
            .execute(&mut *tx)
            .await
            .map_err(|e| {
                tracing::error!(error=%e, "db ticket insert failed");
                ApiError::internal("database error")
            })?;
        }

        if let Some(ikey) = idempotency_key.as_deref() {
            let _ = sqlx::query(&format!(
                "UPDATE {idempotency} SET booking_id=$1 WHERE key=$2"
            ))
            .bind(&bid)
            .bind(ikey)
            .execute(&mut *tx)
            .await;
        }

        tx.commit().await.map_err(|e| {
            tracing::error!(error=%e, "db commit failed");
            ApiError::internal("database error")
        })?;

        // Offline/no-payments mode: booking remains pending but tickets are issued.
        if !require_payment {
            let out = booking_out(&state, &bid, true).await?;
            return Ok(axum::Json(out));
        }

        bid
    };

    // Payment + confirmation step.
    let routes = state.table("routes");
    let ops = state.table("bus_operators");
    let rt = sqlx::query(&format!("SELECT operator_id FROM {routes} WHERE id=$1"))
        .bind(&route_id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!(error=%e, "db book_trip route lookup failed");
            ApiError::internal("database error")
        })?
        .ok_or_else(|| ApiError::not_found("route not found"))?;
    let op_id: String = rt.try_get("operator_id").unwrap_or_default();
    let op = sqlx::query(&format!("SELECT wallet_id FROM {ops} WHERE id=$1"))
        .bind(&op_id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!(error=%e, "db book_trip operator lookup failed");
            ApiError::internal("database error")
        })?
        .ok_or_else(|| ApiError::not_found("operator not found"))?;
    let op_wallet: Option<String> = op.try_get("wallet_id").unwrap_or(None);
    let Some(op_wallet) = op_wallet.filter(|s| !s.trim().is_empty()) else {
        // Payment is enabled, but operator isn't configured. Roll back booking.
        fail_booking_and_release(&state, &booking_id).await.ok();
        return Err(ApiError::internal("operator wallet not configured"));
    };

    // Load booking seats for amount (idempotency replays may get existing booking).
    let b_row = sqlx::query(&format!(
        "SELECT seats,wallet_id,status FROM {bookings} WHERE id=$1"
    ))
    .bind(&booking_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(error=%e, "db book_trip booking lookup failed");
        ApiError::internal("database error")
    })?
    .ok_or_else(|| ApiError::internal("booking confirmation failed"))?;
    let b_seats: i32 = b_row.try_get("seats").unwrap_or(seats_requested);
    let b_wallet: Option<String> = b_row.try_get("wallet_id").unwrap_or(None);
    let amount = price_cents * b_seats as i64;

    // If the rider wallet is the operator wallet, no transfer is necessary.
    let mut payment_resp: Option<serde_json::Value> = None;
    if let Some(from_wallet) = b_wallet.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
        if from_wallet != op_wallet {
            match payments_transfer(
                &state,
                &booking_id,
                BUS_BOOKING_ACTION_CHARGE,
                from_wallet,
                &op_wallet,
                amount,
            )
            .await
            {
                Ok(v) => payment_resp = Some(v),
                Err(e) => {
                    fail_booking_and_release(&state, &booking_id).await.ok();
                    return Err(e);
                }
            }
        }
    }

    // Confirm booking + issue tickets.
    let tickets = state.table("tickets");
    let mut tx = state.pool.begin().await.map_err(|e| {
        tracing::error!(error=%e, "db begin tx failed");
        ApiError::internal("database error")
    })?;
    let lock_booking_sql = format!(
        "SELECT status FROM {bookings} WHERE id=$1{}",
        for_update_suffix(&state)
    );
    let br = sqlx::query(&lock_booking_sql)
        .bind(&booking_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|e| {
            tracing::error!(error=%e, "db confirm booking lookup failed");
            ApiError::internal("database error")
        })?
        .ok_or_else(|| ApiError::internal("booking confirmation failed"))?;
    let st: String = br
        .try_get("status")
        .unwrap_or_else(|_| "pending".to_string());
    if st != "confirmed" {
        let txn_id = payment_resp
            .as_ref()
            .and_then(|v| v.get("id").or_else(|| v.get("txn_id")))
            .and_then(|x| x.as_str())
            .map(|s| s.to_string());
        let upd = sqlx::query(&format!(
            "UPDATE {bookings} SET status='confirmed', payments_txn_id=$1 WHERE id=$2"
        ))
        .bind(&txn_id)
        .bind(&booking_id)
        .execute(&mut *tx)
        .await
        .map_err(|e| {
            tracing::error!(error=%e, "db confirm booking update failed");
            ApiError::internal("database error")
        })?;
        if upd.rows_affected() == 0 {
            return Err(ApiError::internal("booking confirmation failed"));
        }
        let now = Utc::now();
        let _ = sqlx::query(&format!("UPDATE {tickets} SET status='issued', issued_at=COALESCE(issued_at,$1) WHERE booking_id=$2"))
            .bind(now.to_rfc3339())
            .bind(&booking_id)
            .execute(&mut *tx)
            .await;
    }
    tx.commit().await.ok();

    let out = booking_out(&state, &booking_id, true).await?;
    Ok(axum::Json(out))
}

pub async fn cancel_booking(
    Path(booking_id): Path<String>,
    State(state): State<AppState>,
) -> ApiResult<axum::Json<BookingCancelOut>> {
    let booking_id = booking_id.trim().to_string();
    if booking_id.is_empty() {
        return Err(ApiError::bad_request("booking_id required"));
    }

    let bookings = state.table("bookings");
    let trips = state.table("trips");
    let tickets = state.table("tickets");
    let routes = state.table("routes");
    let ops = state.table("bus_operators");

    let mut tx = state.pool.begin().await.map_err(|e| {
        tracing::error!(error=%e, "db begin tx failed");
        ApiError::internal("database error")
    })?;

    let b_sql = format!(
        "SELECT id,trip_id,price_cents,seats,status,wallet_id,customer_phone,created_at,payments_txn_id FROM {bookings} WHERE id=$1{}",
        for_update_suffix(&state)
    );
    let b = sqlx::query(&b_sql)
        .bind(&booking_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|e| {
            tracing::error!(error=%e, "db cancel_booking booking lookup failed");
            ApiError::internal("database error")
        })?
        .ok_or_else(|| ApiError::not_found("not found"))?;
    let b_status: String = b
        .try_get("status")
        .unwrap_or_else(|_| "pending".to_string());
    if b_status == "canceled" {
        return Err(ApiError::bad_request("booking already canceled"));
    }
    let trip_id: String = b.try_get("trip_id").unwrap_or_default();
    let b_seats: i32 = b.try_get("seats").unwrap_or(0);
    let b_wallet: Option<String> = b.try_get("wallet_id").unwrap_or(None);
    let b_customer_phone: Option<String> = b.try_get("customer_phone").unwrap_or(None);
    let b_created_at: Option<DateTime<Utc>> = row_dt_opt(&b, "created_at");
    let b_payments_txn_id: Option<String> = b.try_get("payments_txn_id").unwrap_or(None);
    let b_price: Option<i64> = b.try_get("price_cents").unwrap_or(None);

    let t_sql = format!(
        "SELECT id,route_id,depart_at,price_cents,currency,seats_total,seats_available FROM {trips} WHERE id=$1{}",
        for_update_suffix(&state)
    );
    let t = sqlx::query(&t_sql)
        .bind(&trip_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|e| {
            tracing::error!(error=%e, "db cancel_booking trip lookup failed");
            ApiError::internal("database error")
        })?
        .ok_or_else(|| ApiError::not_found("trip not found"))?;
    let depart_at: DateTime<Utc> = row_dt(&t, "depart_at")?;
    let now = Utc::now();
    let pct = refund_pct_for_departure(now, depart_at);
    if pct <= 0.0 {
        return Err(ApiError::bad_request("departure passed; cannot cancel"));
    }

    // Prevent cancel if any ticket already boarded.
    let boarded = sqlx::query(&format!(
        "SELECT 1 FROM {tickets} WHERE booking_id=$1 AND status='boarded' LIMIT 1"
    ))
    .bind(&booking_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error=%e, "db cancel_booking boarded check failed");
        ApiError::internal("database error")
    })?
    .is_some();
    if boarded {
        return Err(ApiError::bad_request("one or more tickets already boarded"));
    }

    let trip_price: i64 = t.try_get("price_cents").unwrap_or(0);
    let amount = b_price.unwrap_or(trip_price) * (b_seats as i64);
    let refund_cents: i64 = ((amount as f64) * pct).round() as i64;
    let currency: String = t.try_get("currency").unwrap_or_else(|_| "SYP".to_string());

    // Release seats.
    let seats_total: i32 = t.try_get("seats_total").unwrap_or(0);
    let seats_avail: i32 = t.try_get("seats_available").unwrap_or(0);
    let new_avail = (seats_avail + b_seats).min(seats_total);
    sqlx::query(&format!(
        "UPDATE {trips} SET seats_available=$1 WHERE id=$2"
    ))
    .bind(new_avail)
    .bind(&trip_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error=%e, "db cancel_booking trip update failed");
        ApiError::internal("database error")
    })?;

    // Cancel tickets (except boarded, which we already prevented).
    let _ = sqlx::query(&format!(
        "UPDATE {tickets} SET status='canceled' WHERE booking_id=$1 AND status != 'boarded'"
    ))
    .bind(&booking_id)
    .execute(&mut *tx)
    .await;

    // Apply refund only when payments are configured and both wallets are known.
    if state.payments_enabled() && refund_cents > 0 {
        if let Some(wid) = b_wallet.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
            let route_id: String = t.try_get("route_id").unwrap_or_default();
            let rt = sqlx::query(&format!("SELECT operator_id FROM {routes} WHERE id=$1"))
                .bind(&route_id)
                .fetch_optional(&mut *tx)
                .await
                .map_err(|e| {
                    tracing::error!(error=%e, "db cancel_booking route lookup failed");
                    ApiError::internal("database error")
                })?
                .ok_or_else(|| ApiError::not_found("route not found"))?;
            let op_id: String = rt.try_get("operator_id").unwrap_or_default();
            let op = sqlx::query(&format!("SELECT wallet_id FROM {ops} WHERE id=$1"))
                .bind(&op_id)
                .fetch_optional(&mut *tx)
                .await
                .map_err(|e| {
                    tracing::error!(error=%e, "db cancel_booking operator lookup failed");
                    ApiError::internal("database error")
                })?
                .ok_or_else(|| ApiError::not_found("operator not found"))?;
            let op_wallet: Option<String> = op.try_get("wallet_id").unwrap_or(None);
            let Some(op_wallet) = op_wallet.filter(|s| !s.trim().is_empty()) else {
                return Err(ApiError::internal(
                    "operator wallet not configured for refund",
                ));
            };
            // Note: this keeps the DB transaction open while calling an upstream service,
            // which can hold row locks longer than ideal. We keep it for parity with the
            // Python implementation and to avoid committing partial state if the refund fails.
            let _resp = payments_transfer(
                &state,
                &booking_id,
                BUS_BOOKING_ACTION_REFUND,
                &op_wallet,
                wid,
                refund_cents,
            )
            .await
            .map_err(|e| ApiError::upstream(format!("refund failed: {}", e.detail)))?;
        }
    }

    // Mark booking canceled (no payments mode or no wallet).
    let _ = sqlx::query(&format!(
        "UPDATE {bookings} SET status='canceled' WHERE id=$1"
    ))
    .bind(&booking_id)
    .execute(&mut *tx)
    .await;
    tx.commit().await.ok();

    let booking = BookingOut {
        id: booking_id.clone(),
        trip_id,
        seats: b_seats,
        status: "canceled".to_string(),
        payments_txn_id: b_payments_txn_id,
        created_at: b_created_at,
        wallet_id: b_wallet,
        customer_phone: b_customer_phone,
        tickets: None,
    };
    Ok(axum::Json(BookingCancelOut {
        booking,
        refund_cents,
        refund_currency: currency,
        refund_pct: (pct * 100.0).round() as i32,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use reqwest::Client;
    use sqlx::postgres::PgPoolOptions;
    use std::collections::HashMap;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpListener;
    use tokio::sync::oneshot;

    #[derive(Debug)]
    struct CapturedRequest {
        method: String,
        path: String,
        headers: HashMap<String, String>,
        body: String,
    }

    fn find_subsequence(haystack: &[u8], needle: &[u8]) -> Option<usize> {
        haystack.windows(needle.len()).position(|w| w == needle)
    }

    async fn spawn_mock_payment_server(
        status_line: &str,
        response_body: &str,
    ) -> (String, oneshot::Receiver<CapturedRequest>) {
        let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind");
        let addr = listener.local_addr().expect("local addr");
        let (tx, rx) = oneshot::channel();
        let status_line = status_line.to_string();
        let response_body = response_body.to_string();

        tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.expect("accept");
            let mut buf: Vec<u8> = Vec::new();
            let mut tmp = [0u8; 2048];
            let header_end = loop {
                let n = stream.read(&mut tmp).await.expect("read");
                if n == 0 {
                    break None;
                }
                buf.extend_from_slice(&tmp[..n]);
                if let Some(i) = find_subsequence(&buf, b"\r\n\r\n") {
                    break Some(i);
                }
            };

            let Some(header_end) = header_end else {
                return;
            };

            let header_text = String::from_utf8_lossy(&buf[..header_end]).to_string();
            let mut lines = header_text.split("\r\n");
            let request_line = lines.next().unwrap_or_default();
            let mut req_parts = request_line.split_whitespace();
            let method = req_parts.next().unwrap_or_default().to_string();
            let path = req_parts.next().unwrap_or_default().to_string();

            let mut headers: HashMap<String, String> = HashMap::new();
            for line in lines {
                if let Some((k, v)) = line.split_once(':') {
                    headers.insert(k.trim().to_ascii_lowercase(), v.trim().to_string());
                }
            }

            let content_len = headers
                .get("content-length")
                .and_then(|v| v.parse::<usize>().ok())
                .unwrap_or(0);

            let mut body = buf[(header_end + 4)..].to_vec();
            while body.len() < content_len {
                let n = stream.read(&mut tmp).await.expect("read body");
                if n == 0 {
                    break;
                }
                body.extend_from_slice(&tmp[..n]);
            }
            body.truncate(content_len);

            let _ = tx.send(CapturedRequest {
                method,
                path,
                headers,
                body: String::from_utf8_lossy(&body).to_string(),
            });

            let response = format!(
                "HTTP/1.1 {status_line}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                response_body.len(),
                response_body
            );
            let _ = stream.write_all(response.as_bytes()).await;
            let _ = stream.flush().await;
        });

        (format!("http://{}", addr), rx)
    }

    fn test_state(base_url: &str, bus_secret: Option<&str>) -> AppState {
        let pool = PgPoolOptions::new()
            .connect_lazy("postgresql://shamell:shamell@localhost:5432/shamell_bus")
            .expect("lazy pool");
        let http = Client::builder().build().expect("http client");
        AppState {
            pool,
            db_schema: None,
            ticket_secret: "ticket-secret-test".to_string(),
            env_name: "test".to_string(),
            env_lower: "test".to_string(),
            internal_service_id: "bus".to_string(),
            payments_base_url: Some(base_url.to_string()),
            bus_payments_internal_secret: bus_secret.map(ToString::to_string),
            http,
        }
    }

    #[tokio::test]
    async fn payments_transfer_charge_hits_booking_bound_endpoint() {
        let (base_url, rx) =
            spawn_mock_payment_server("200 OK", "{\"txn_id\":\"tx-charge-1\"}").await;
        let state = test_state(&base_url, Some("bus-binding-secret"));
        let booking_id = "550e8400-e29b-41d4-a716-446655440000";

        let out = payments_transfer(
            &state,
            booking_id,
            BUS_BOOKING_ACTION_CHARGE,
            "wallet-from",
            "wallet-to",
            12_500,
        )
        .await
        .expect("payments transfer");
        assert_eq!(
            out.get("txn_id").and_then(|v| v.as_str()),
            Some("tx-charge-1")
        );

        let captured = rx.await.expect("captured request");
        assert_eq!(captured.method, "POST");
        assert_eq!(captured.path, "/internal/bus/bookings/transfer");
        assert_eq!(
            captured
                .headers
                .get("x-bus-payments-internal-secret")
                .map(String::as_str),
            Some("bus-binding-secret")
        );
        assert_eq!(
            captured
                .headers
                .get("x-internal-service-id")
                .map(String::as_str),
            Some("bus")
        );

        let body: serde_json::Value = serde_json::from_str(&captured.body).expect("json body");
        assert_eq!(
            body.get("booking_id").and_then(|v| v.as_str()),
            Some(booking_id)
        );
        assert_eq!(body.get("action").and_then(|v| v.as_str()), Some("charge"));
        assert_eq!(
            body.get("from_wallet_id").and_then(|v| v.as_str()),
            Some("wallet-from")
        );
        assert_eq!(
            body.get("to_wallet_id").and_then(|v| v.as_str()),
            Some("wallet-to")
        );
        assert_eq!(
            body.get("amount_cents").and_then(|v| v.as_i64()),
            Some(12_500)
        );
    }

    #[tokio::test]
    async fn payments_transfer_refund_hits_booking_bound_endpoint() {
        let (base_url, rx) =
            spawn_mock_payment_server("200 OK", "{\"txn_id\":\"tx-refund-1\"}").await;
        let state = test_state(&base_url, Some("bus-binding-secret"));
        let booking_id = "00000000-0000-0000-0000-000000000001";

        let out = payments_transfer(
            &state,
            booking_id,
            BUS_BOOKING_ACTION_REFUND,
            "operator-wallet",
            "rider-wallet",
            8_400,
        )
        .await
        .expect("payments transfer");
        assert_eq!(
            out.get("txn_id").and_then(|v| v.as_str()),
            Some("tx-refund-1")
        );

        let captured = rx.await.expect("captured request");
        assert_eq!(captured.method, "POST");
        assert_eq!(captured.path, "/internal/bus/bookings/transfer");

        let body: serde_json::Value = serde_json::from_str(&captured.body).expect("json body");
        assert_eq!(
            body.get("booking_id").and_then(|v| v.as_str()),
            Some(booking_id)
        );
        assert_eq!(body.get("action").and_then(|v| v.as_str()), Some("refund"));
        assert_eq!(
            body.get("from_wallet_id").and_then(|v| v.as_str()),
            Some("operator-wallet")
        );
        assert_eq!(
            body.get("to_wallet_id").and_then(|v| v.as_str()),
            Some("rider-wallet")
        );
        assert_eq!(
            body.get("amount_cents").and_then(|v| v.as_i64()),
            Some(8_400)
        );
    }
}
