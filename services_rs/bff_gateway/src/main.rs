mod auth;
mod authz;
mod config;
mod error;
mod handlers;
mod models;
mod state;

use axum::extract::MatchedPath;
use axum::extract::{Request, State};
use axum::http::{header, header::HeaderName, HeaderMap, Method, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::{delete, get, post};
use axum::{Json, Router};
use config::Config;
use serde_json::json;
use shamell_common::host_guard::AllowedHostsLayer;
use shamell_common::internal_auth::InternalAuthLayer;
use shamell_common::request_id::RequestIdLayer;
use shamell_common::security_headers::SecurityHeadersLayer;
use state::AppState;
use std::net::SocketAddr;
use std::time::Duration;
use tower_http::cors::{AllowOrigin, Any, CorsLayer};
use tower_http::limit::RequestBodyLimitLayer;
use tower_http::trace::TraceLayer;
use tracing_subscriber::EnvFilter;

const SESSION_COOKIE_NAME: &str = "__Host-sa_session";
const LEGACY_SESSION_COOKIE_NAME: &str = "sa_session";

#[tokio::main]
async fn main() {
    let cfg = match Config::from_env() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(2);
        }
    };

    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .json()
        .init();

    let http = match reqwest::Client::builder()
        .timeout(Duration::from_secs(cfg.upstream_timeout_secs))
        .user_agent(format!("shamell-bff-gateway/{}", env!("CARGO_PKG_VERSION")))
        .build()
    {
        Ok(c) => c,
        Err(e) => {
            tracing::error!(error = %e, "http client init failed");
            std::process::exit(2);
        }
    };

    let auth = match auth::AuthRuntime::from_env(&cfg.env_name).await {
        Ok(v) => v,
        Err(e) => {
            tracing::error!(error = %e, "auth runtime init failed");
            std::process::exit(2);
        }
    };
    auth::spawn_maintenance_task(auth.clone());

    let state = AppState {
        env_name: cfg.env_name.clone(),
        payments_base_url: cfg.payments_base_url.clone(),
        payments_internal_secret: cfg.payments_internal_secret.clone(),
        chat_base_url: cfg.chat_base_url.clone(),
        chat_internal_secret: cfg.chat_internal_secret.clone(),
        bus_base_url: cfg.bus_base_url.clone(),
        bus_internal_secret: cfg.bus_internal_secret.clone(),
        internal_service_id: cfg.internal_service_id.clone(),
        enforce_route_authz: cfg.enforce_route_authz,
        role_header_secret: cfg.role_header_secret.clone(),
        max_upstream_body_bytes: cfg.max_upstream_body_bytes,
        expose_upstream_errors: cfg.expose_upstream_errors,
        accept_legacy_session_cookie: cfg.accept_legacy_session_cookie,
        auth_device_login_web_enabled: cfg.auth_device_login_web_enabled,
        http,
        auth,
    };

    let internal_security_alerts =
        InternalAuthLayer::new(cfg.require_internal_secret, cfg.internal_secret.clone())
            .with_allowed_callers(cfg.security_alert_allowed_callers.clone());

    let internal_security = Router::new()
        .route(
            "/internal/security/alerts",
            post(handlers::security_alert_ingest),
        )
        .layer(internal_security_alerts);

    let payments_routes = Router::new()
        .route("/payments/users", post(handlers::payments_create_user))
        .route(
            "/payments/wallets/:wallet_id",
            get(handlers::payments_wallet),
        )
        .route("/payments/transfer", post(handlers::payments_transfer))
        .route(
            "/payments/wallets/:wallet_id/topup",
            post(handlers::payments_topup),
        )
        .route(
            "/payments/favorites",
            post(handlers::payments_favorites_create).get(handlers::payments_favorites_list),
        )
        .route(
            "/payments/favorites/:fid",
            delete(handlers::payments_favorites_delete),
        )
        .route(
            "/payments/requests",
            post(handlers::payments_requests_create).get(handlers::payments_requests_list),
        )
        .route(
            "/payments/requests/:rid/accept",
            post(handlers::payments_requests_accept),
        )
        .route(
            "/payments/requests/:rid/cancel",
            post(handlers::payments_requests_cancel),
        );

    let contacts_routes = Router::new()
        .route("/contacts/invites", post(handlers::contacts_invite_create))
        .route(
            "/contacts/invites/redeem",
            post(handlers::contacts_invite_redeem),
        );

    let chat_routes = Router::new()
        .route("/chat/devices/register", post(handlers::chat_register))
        .route("/chat/devices/:device_id", get(handlers::chat_get_device))
        .route(
            "/chat/devices/:device_id/push_token",
            post(handlers::chat_push_token),
        )
        .route("/chat/mailboxes/issue", post(handlers::chat_mailbox_issue))
        .route("/chat/mailboxes/write", post(handlers::chat_mailbox_write))
        .route("/chat/mailboxes/poll", post(handlers::chat_mailbox_poll))
        .route(
            "/chat/mailboxes/rotate",
            post(handlers::chat_mailbox_rotate),
        )
        .route("/chat/devices/:device_id/block", post(handlers::chat_block))
        .route(
            "/chat/devices/:device_id/prefs",
            post(handlers::chat_set_prefs).get(handlers::chat_list_prefs),
        )
        .route(
            "/chat/devices/:device_id/group_prefs",
            post(handlers::chat_set_group_prefs).get(handlers::chat_list_group_prefs),
        )
        .route(
            "/chat/devices/:device_id/hidden",
            get(handlers::chat_list_hidden),
        )
        .route("/chat/messages/send", post(handlers::chat_send))
        .route("/chat/messages/inbox", get(handlers::chat_inbox))
        .route("/chat/messages/stream", get(handlers::chat_stream))
        .route("/chat/messages/:mid/read", post(handlers::chat_mark_read))
        .route("/chat/groups/create", post(handlers::chat_group_create))
        .route("/chat/groups/list", get(handlers::chat_group_list))
        .route(
            "/chat/groups/:group_id/update",
            post(handlers::chat_group_update),
        )
        .route(
            "/chat/groups/:group_id/messages/send",
            post(handlers::chat_group_send),
        )
        .route(
            "/chat/groups/:group_id/messages/inbox",
            get(handlers::chat_group_inbox),
        )
        .route(
            "/chat/groups/:group_id/members",
            get(handlers::chat_group_members),
        )
        .route(
            "/chat/groups/:group_id/invite",
            post(handlers::chat_group_invite),
        )
        .route(
            "/chat/groups/:group_id/leave",
            post(handlers::chat_group_leave),
        )
        .route(
            "/chat/groups/:group_id/set_role",
            post(handlers::chat_group_set_role),
        )
        .route(
            "/chat/groups/:group_id/keys/rotate",
            post(handlers::chat_group_rotate_key),
        )
        .route(
            "/chat/groups/:group_id/keys/events",
            get(handlers::chat_group_key_events),
        );

    let bus_routes = Router::new()
        .route("/bus/health", get(handlers::bus_health))
        .route("/bus/cities", get(handlers::bus_cities))
        .route("/bus/cities_cached", get(handlers::bus_cities_cached))
        .route("/bus/routes", get(handlers::bus_routes))
        .route("/bus/operators", get(handlers::bus_list_operators))
        .route(
            "/bus/operators/:operator_id/stats",
            get(handlers::bus_operator_stats),
        )
        .route(
            "/bus/operators/:operator_id/trips",
            get(handlers::bus_operator_trips),
        )
        .route("/bus/trips/search", get(handlers::bus_trips_search))
        .route("/bus/trips/:trip_id", get(handlers::bus_trip_detail))
        .route("/bus/trips/:trip_id/book", post(handlers::bus_book_trip))
        .route("/bus/bookings/search", get(handlers::bus_booking_search))
        .route(
            "/bus/bookings/:booking_id",
            get(handlers::bus_booking_status),
        )
        .route(
            "/bus/bookings/:booking_id/tickets",
            get(handlers::bus_booking_tickets),
        );

    let operator_only = Router::new()
        .route("/bus/routes", post(handlers::bus_create_route))
        .route("/bus/operators", post(handlers::bus_create_operator))
        .route(
            "/bus/operators/:operator_id/online",
            post(handlers::bus_operator_online),
        )
        .route(
            "/bus/operators/:operator_id/offline",
            post(handlers::bus_operator_offline),
        )
        .route("/bus/trips", post(handlers::bus_create_trip))
        .route(
            "/bus/trips/:trip_id/publish",
            post(handlers::bus_publish_trip),
        )
        .route(
            "/bus/trips/:trip_id/unpublish",
            post(handlers::bus_unpublish_trip),
        )
        .route(
            "/bus/trips/:trip_id/cancel",
            post(handlers::bus_cancel_trip),
        )
        .route(
            "/bus/bookings/:booking_id/cancel",
            post(handlers::bus_booking_cancel),
        )
        .route("/bus/tickets/board", post(handlers::bus_ticket_board));

    let admin_only = Router::new()
        .route("/bus/cities", post(handlers::bus_create_city))
        .route("/bus/admin/summary", get(handlers::bus_admin_summary))
        .route(
            "/admin/roles",
            get(handlers::admin_roles_list)
                .post(handlers::admin_roles_add)
                .delete(handlers::admin_roles_remove),
        )
        .route("/admin/roles/check", get(handlers::admin_roles_check));

    let authed = Router::new()
        .merge(payments_routes.layer(cors_layer_for_headers(
            &cfg.allowed_origins,
            bff_payments_cors_allowed_headers(),
        )))
        .merge(contacts_routes.layer(cors_layer_for_headers(
            &cfg.allowed_origins,
            bff_contacts_cors_allowed_headers(),
        )))
        .merge(chat_routes.layer(cors_layer_for_headers(
            &cfg.allowed_origins,
            bff_chat_cors_allowed_headers(),
        )))
        .merge(bus_routes.layer(cors_layer_for_headers(
            &cfg.allowed_origins,
            bff_bus_cors_allowed_headers(),
        )))
        .merge(
            operator_only
                .layer(middleware::from_fn_with_state(
                    state.clone(),
                    authz::require_operator_bus,
                ))
                .layer(cors_layer_for_headers(
                    &cfg.allowed_origins,
                    bff_bus_cors_allowed_headers(),
                )),
        )
        .merge(
            admin_only
                .layer(middleware::from_fn_with_state(state.clone(), authz::require_admin))
                .layer(cors_layer_for_headers(
                    &cfg.allowed_origins,
                    bff_public_cors_allowed_headers(),
                )),
        );

    let public_auth = Router::new()
        .route("/", get(auth::root_redirect))
        .route("/login", get(auth::login_page))
        .route("/home", get(auth::home_page))
        .route("/app", get(auth::app_shell))
        .route(
            "/auth/account/create/challenge",
            post(auth::auth_account_create_challenge),
        )
        .route("/auth/account/create", post(auth::auth_account_create))
        .route("/auth/biometric/enroll", post(auth::auth_biometric_enroll))
        .route("/auth/biometric/login", post(auth::auth_biometric_login))
        .route("/auth/logout", post(auth::auth_logout))
        .route("/qr.svg", post(auth::qr_svg))
        .route(
            "/auth/device_login/start",
            post(auth::auth_device_login_start),
        )
        .route(
            "/auth/device_login/approve",
            post(auth::auth_device_login_approve),
        )
        .route(
            "/auth/device_login/redeem",
            post(auth::auth_device_login_redeem),
        )
        .route(
            "/auth/device_login/qr.svg",
            post(auth::auth_device_login_qr_svg),
        )
        .route("/auth/devices/register", post(auth::auth_devices_register))
        .route("/auth/devices", get(auth::auth_devices_list))
        .route(
            "/auth/devices/:device_id",
            delete(auth::auth_devices_delete),
        )
        .route("/me/roles", get(auth::me_roles))
        .route("/me/home_snapshot", get(auth::me_home_snapshot))
        .route("/me/mobility_history", get(auth::me_mobility_history));

    let public_auth = if cfg.auth_device_login_web_enabled {
        public_auth
            .route("/auth/device_login", get(auth::device_login_page))
            .route("/auth/device_login_demo", get(auth::device_login_demo))
    } else {
        public_auth
    };

    let public_auth = public_auth.layer(cors_layer_for_headers(
        &cfg.allowed_origins,
        bff_public_cors_allowed_headers(),
    ));
    let csrf_state = CsrfState {
        enabled: cfg.csrf_guard_enabled,
        allowed_origins: cfg.allowed_origins.clone(),
        accept_legacy_session_cookie: cfg.accept_legacy_session_cookie,
    };

    let app = Router::new()
        .route("/health", get(handlers::health))
        .merge(public_auth)
        .merge(internal_security)
        .merge(authed)
        // Ensure unknown routes return a proper 404, not an internal-auth error from a merged
        // router's layered fallback (defense-in-depth + avoids confusing clients).
        .fallback(|| async {
            (
                StatusCode::NOT_FOUND,
                Json(json!({ "detail": "not found" })),
            )
        })
        .with_state(state)
        .layer(middleware::from_fn_with_state(csrf_state, csrf_guard))
        .layer(RequestBodyLimitLayer::new(cfg.max_body_bytes))
        .layer(AllowedHostsLayer::new(cfg.allowed_hosts.clone()))
        .layer(SecurityHeadersLayer::from_env(&cfg.env_name))
        // Avoid logging sensitive query parameters (e.g., mailbox tokens). We log the matched
        // route template when available, otherwise just the path (no query string).
        .layer(
            TraceLayer::new_for_http().make_span_with(|req: &axum::http::Request<_>| {
                let path = req
                    .extensions()
                    .get::<MatchedPath>()
                    .map(MatchedPath::as_str)
                    .unwrap_or_else(|| req.uri().path());
                tracing::span!(
                    tracing::Level::INFO,
                    "http_request",
                    method = %req.method(),
                    path = %path
                )
            }),
        )
        .layer(RequestIdLayer::new(HeaderName::from_static("x-request-id")));

    let addr: SocketAddr = format!("{}:{}", cfg.host, cfg.port)
        .parse()
        .unwrap_or_else(|_| SocketAddr::from(([0, 0, 0, 0], cfg.port)));
    tracing::info!(%addr, "starting shamell_bff_gateway");

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .unwrap();
}

async fn shutdown_signal() {
    let _ = tokio::signal::ctrl_c().await;
    tracing::info!("shutdown signal received");
}

fn bff_public_cors_allowed_headers() -> Vec<HeaderName> {
    vec![
        header::ACCEPT,
        header::CONTENT_TYPE,
        HeaderName::from_static("x-request-id"),
    ]
}

fn bff_chat_cors_allowed_headers() -> Vec<HeaderName> {
    let mut headers = bff_public_cors_allowed_headers();
    headers.extend([
        HeaderName::from_static("x-chat-device-id"),
        HeaderName::from_static("x-chat-device-token"),
    ]);
    headers
}

fn bff_contacts_cors_allowed_headers() -> Vec<HeaderName> {
    let mut headers = bff_public_cors_allowed_headers();
    headers.extend([HeaderName::from_static("x-chat-device-id")]);
    headers
}

fn bff_payments_cors_allowed_headers() -> Vec<HeaderName> {
    let mut headers = bff_public_cors_allowed_headers();
    headers.extend([
        HeaderName::from_static("x-device-id"),
        HeaderName::from_static("idempotency-key"),
        HeaderName::from_static("x-merchant"),
        HeaderName::from_static("x-ref"),
    ]);
    headers
}

fn bff_bus_cors_allowed_headers() -> Vec<HeaderName> {
    let mut headers = bff_public_cors_allowed_headers();
    headers.extend([
        HeaderName::from_static("x-device-id"),
        HeaderName::from_static("idempotency-key"),
    ]);
    headers
}

fn cors_layer_for_headers(allowed_origins: &[String], allowed_headers: Vec<HeaderName>) -> CorsLayer {
    if allowed_origins.iter().any(|o| o == "*") {
        CorsLayer::new()
            .allow_origin(Any)
            .allow_methods([Method::GET, Method::POST, Method::DELETE, Method::OPTIONS])
            .allow_headers(allowed_headers)
            .allow_credentials(false)
    } else {
        let origins: Vec<axum::http::HeaderValue> = allowed_origins
            .iter()
            .filter_map(|o| o.parse().ok())
            .collect();
        CorsLayer::new()
            .allow_methods([Method::GET, Method::POST, Method::DELETE, Method::OPTIONS])
            .allow_headers(allowed_headers)
            .allow_credentials(false)
            .allow_origin(AllowOrigin::list(origins))
    }
}

#[derive(Clone)]
struct CsrfState {
    enabled: bool,
    allowed_origins: Vec<String>,
    accept_legacy_session_cookie: bool,
}

async fn csrf_guard(State(csrf): State<CsrfState>, req: Request, next: Next) -> Response {
    if let Some(reason) = csrf_block_reason(&csrf, req.method(), req.headers()) {
        tracing::warn!(reason, method = %req.method(), "blocked csrf candidate request");
        return (
            StatusCode::FORBIDDEN,
            Json(json!({ "detail": "forbidden" })),
        )
            .into_response();
    }
    next.run(req).await
}

fn csrf_block_reason(
    csrf: &CsrfState,
    method: &Method,
    headers: &HeaderMap,
) -> Option<&'static str> {
    if !csrf.enabled {
        return None;
    }
    if !matches!(
        *method,
        Method::POST | Method::PUT | Method::PATCH | Method::DELETE
    ) {
        return None;
    }
    if !has_cookie_session(headers, csrf.accept_legacy_session_cookie) {
        return None;
    }

    if let Some(origin_raw) = header_text(headers, header::ORIGIN) {
        let Some(origin) = normalize_origin(origin_raw) else {
            return Some("invalid_origin");
        };
        if origin_is_allowed(&origin, csrf) || origin_matches_host(&origin, headers) {
            return None;
        }
        return Some("origin_not_allowed");
    }

    if let Some(referer_raw) = header_text(headers, header::REFERER) {
        let Some(origin) = normalize_origin(referer_raw) else {
            return Some("invalid_referer");
        };
        if origin_is_allowed(&origin, csrf) || origin_matches_host(&origin, headers) {
            return None;
        }
        return Some("referer_not_allowed");
    }

    if header_text(headers, HeaderName::from_static("sec-fetch-site"))
        .is_some_and(|v| v.eq_ignore_ascii_case("cross-site"))
    {
        return Some("cross_site_fetch");
    }
    None
}

fn header_text(headers: &HeaderMap, name: impl Into<HeaderName>) -> Option<&str> {
    headers
        .get(name.into())?
        .to_str()
        .ok()
        .map(str::trim)
        .filter(|v| !v.is_empty())
}

fn has_cookie_session(headers: &HeaderMap, accept_legacy_session_cookie: bool) -> bool {
    let Some(raw) = header_text(headers, header::COOKIE) else {
        return false;
    };
    raw.split(';').map(str::trim).any(|part| {
        part.strip_prefix(SESSION_COOKIE_NAME)
            .or_else(|| {
                if accept_legacy_session_cookie {
                    part.strip_prefix(LEGACY_SESSION_COOKIE_NAME)
                } else {
                    None
                }
            })
            .and_then(|tail| tail.strip_prefix('='))
            .map(str::trim)
            .is_some_and(|value| !value.is_empty())
    })
}

#[cfg(test)]
mod router_fallback_tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use axum::routing::get;
    use tower::ServiceExt;

    #[tokio::test]
    async fn unknown_routes_return_404_not_internal_auth_required() {
        let internal = InternalAuthLayer::new(true, Some("test-secret".to_string()));
        let authed = Router::new()
            .route("/foo", get(|| async { "ok" }))
            .layer(internal);

        // Without a top-level fallback, the merged `authed` router's layered fallback can
        // leak `internal auth required` to clients for unknown routes. Assert our fix.
        let app = Router::new()
            .route("/health", get(|| async { "ok" }))
            .merge(authed)
            .fallback(|| async {
                (
                    StatusCode::NOT_FOUND,
                    Json(json!({ "detail": "not found" })),
                )
            });

        let resp = app
            .oneshot(
                Request::builder()
                    .uri("/does_not_exist")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
    }
}

fn normalize_origin(raw: &str) -> Option<String> {
    let s = raw.trim();
    if s.is_empty() || s.eq_ignore_ascii_case("null") {
        return None;
    }
    let url = reqwest::Url::parse(s).ok()?;
    let scheme = url.scheme().to_ascii_lowercase();
    if !matches!(scheme.as_str(), "http" | "https") {
        return None;
    }
    let host = url.host_str()?.trim().to_ascii_lowercase();
    if host.is_empty() {
        return None;
    }
    let port = url.port();
    Some(match port {
        Some(p) => format!("{scheme}://{host}:{p}"),
        None => format!("{scheme}://{host}"),
    })
}

fn origin_is_allowed(origin: &str, csrf: &CsrfState) -> bool {
    for allowed in &csrf.allowed_origins {
        let allowed = allowed.trim();
        if allowed == "*" {
            return true;
        }
        if normalize_origin(allowed).as_deref() == Some(origin) {
            return true;
        }
    }
    false
}

fn origin_matches_host(origin: &str, headers: &HeaderMap) -> bool {
    let origin_host = reqwest::Url::parse(origin)
        .ok()
        .and_then(|u| u.host_str().map(str::to_ascii_lowercase))
        .unwrap_or_default();
    if origin_host.is_empty() {
        return false;
    }
    let host_raw = header_text(headers, HeaderName::from_static("x-forwarded-host"))
        .or_else(|| header_text(headers, header::HOST))
        .unwrap_or("");
    let host = host_raw
        .split(',')
        .next()
        .unwrap_or("")
        .trim()
        .split(':')
        .next()
        .unwrap_or("")
        .trim()
        .to_ascii_lowercase();
    !host.is_empty() && host == origin_host
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{header, Method, Request, StatusCode};
    use axum::routing::post;
    use tower::ServiceExt;

    fn state(
        enabled: bool,
        allowed_origins: &[&str],
        accept_legacy_session_cookie: bool,
    ) -> CsrfState {
        CsrfState {
            enabled,
            allowed_origins: allowed_origins.iter().map(|v| (*v).to_string()).collect(),
            accept_legacy_session_cookie,
        }
    }

    fn headers(raw: &[(&str, &str)]) -> HeaderMap {
        let mut h = HeaderMap::new();
        for (k, v) in raw {
            h.insert(
                HeaderName::from_bytes(k.as_bytes()).expect("header name"),
                axum::http::HeaderValue::from_str(v).expect("header value"),
            );
        }
        h
    }

    fn assert_no_sensitive_headers(headers: &[HeaderName]) {
        let has = |name: &str| {
            headers
                .iter()
                .any(|h| h.as_str().eq_ignore_ascii_case(name))
        };
        assert!(!has("authorization"));
        assert!(!has("x-internal-secret"));
        assert!(!has("x-internal-service-id"));
        assert!(!has("x-role-auth"));
        assert!(!has("x-auth-roles"));
        assert!(!has("x-roles"));
        assert!(!has("x-forwarded-for"));
        assert!(!has("x-forwarded-host"));
        assert!(!has("x-real-ip"));
        assert!(!has("x-shamell-client-ip"));
        assert!(!has("cookie"));
    }

    fn allow_headers(resp: &axum::response::Response) -> Vec<String> {
        resp.headers()
            .get(header::ACCESS_CONTROL_ALLOW_HEADERS)
            .and_then(|v| v.to_str().ok())
            .unwrap_or("")
            .split(',')
            .map(str::trim)
            .filter(|v| !v.is_empty())
            .map(str::to_ascii_lowercase)
            .collect()
    }

    fn has_allow_header(resp: &axum::response::Response, name: &str) -> bool {
        allow_headers(resp)
            .iter()
            .any(|h| h.eq_ignore_ascii_case(name))
    }

    fn cors_zone_test_app() -> Router {
        let allowed_origins = vec!["https://online.shamell.online".to_string()];

        let public_auth = Router::new()
            .route("/auth/biometric/login", post(|| async { StatusCode::OK }))
            .layer(cors_layer_for_headers(
                &allowed_origins,
                bff_public_cors_allowed_headers(),
            ));
        let contacts = Router::new()
            .route("/contacts/invites/redeem", post(|| async { StatusCode::OK }))
            .layer(cors_layer_for_headers(
                &allowed_origins,
                bff_contacts_cors_allowed_headers(),
            ));
        let chat = Router::new()
            .route("/chat/messages/send", post(|| async { StatusCode::OK }))
            .layer(cors_layer_for_headers(
                &allowed_origins,
                bff_chat_cors_allowed_headers(),
            ));
        let payments = Router::new()
            .route("/payments/transfer", post(|| async { StatusCode::OK }))
            .layer(cors_layer_for_headers(
                &allowed_origins,
                bff_payments_cors_allowed_headers(),
            ));
        let bus = Router::new()
            .route("/bus/trips/:trip_id/book", post(|| async { StatusCode::OK }))
            .layer(cors_layer_for_headers(
                &allowed_origins,
                bff_bus_cors_allowed_headers(),
            ));
        let internal = Router::new().route("/internal/security/alerts", post(|| async { "ok" }));

        Router::new()
            .merge(public_auth)
            .merge(contacts)
            .merge(chat)
            .merge(payments)
            .merge(bus)
            .merge(internal)
    }

    async fn preflight(path: &str, requested_method: Method, requested_headers: &str) -> axum::response::Response {
        cors_zone_test_app()
            .oneshot(
                Request::builder()
                    .method(Method::OPTIONS)
                    .uri(path)
                    .header(header::ORIGIN, "https://online.shamell.online")
                    .header(
                        header::ACCESS_CONTROL_REQUEST_METHOD,
                        requested_method.as_str(),
                    )
                    .header(header::ACCESS_CONTROL_REQUEST_HEADERS, requested_headers)
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap()
    }

    #[test]
    fn csrf_guard_blocks_cross_site_cookie_write() {
        let st = state(true, &["https://online.shamell.online"], false);
        let h = headers(&[
            (
                "cookie",
                "__Host-sa_session=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            ),
            ("origin", "https://evil.example"),
            ("host", "api.shamell.online"),
        ]);
        let reason = csrf_block_reason(&st, &Method::POST, &h);
        assert_eq!(reason, Some("origin_not_allowed"));
    }

    #[test]
    fn csrf_guard_allows_allowed_origin_cookie_write() {
        let st = state(true, &["https://online.shamell.online"], false);
        let h = headers(&[
            (
                "cookie",
                "__Host-sa_session=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            ),
            ("origin", "https://online.shamell.online"),
        ]);
        assert_eq!(csrf_block_reason(&st, &Method::POST, &h), None);
    }

    #[test]
    fn csrf_guard_rejects_cross_site_even_when_sa_cookie_header_is_present() {
        let st = state(true, &["https://online.shamell.online"], false);
        let h = headers(&[
            (
                "cookie",
                "__Host-sa_session=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            ),
            ("sa_cookie", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
            ("origin", "https://evil.example"),
        ]);
        assert_eq!(
            csrf_block_reason(&st, &Method::POST, &h),
            Some("origin_not_allowed")
        );
    }

    #[test]
    fn csrf_guard_allows_same_host_origin() {
        let st = state(true, &["https://online.shamell.online"], false);
        let h = headers(&[
            (
                "cookie",
                "__Host-sa_session=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            ),
            ("origin", "https://api.shamell.online"),
            ("host", "api.shamell.online"),
        ]);
        assert_eq!(csrf_block_reason(&st, &Method::POST, &h), None);
    }

    #[test]
    fn csrf_guard_blocks_cross_site_fetch_without_origin() {
        let st = state(true, &["https://online.shamell.online"], false);
        let h = headers(&[
            (
                "cookie",
                "__Host-sa_session=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            ),
            ("sec-fetch-site", "cross-site"),
        ]);
        assert_eq!(
            csrf_block_reason(&st, &Method::POST, &h),
            Some("cross_site_fetch")
        );
    }

    #[test]
    fn csrf_guard_skips_safe_methods() {
        let st = state(true, &["https://online.shamell.online"], false);
        let h = headers(&[
            (
                "cookie",
                "__Host-sa_session=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            ),
            ("origin", "https://evil.example"),
        ]);
        assert_eq!(csrf_block_reason(&st, &Method::GET, &h), None);
    }

    #[test]
    fn csrf_guard_detects_legacy_cookie_name_during_migration() {
        let st = state(true, &["https://online.shamell.online"], true);
        let h = headers(&[
            ("cookie", "sa_session=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
            ("origin", "https://evil.example"),
            ("host", "api.shamell.online"),
        ]);
        assert_eq!(
            csrf_block_reason(&st, &Method::POST, &h),
            Some("origin_not_allowed")
        );
    }

    #[test]
    fn csrf_guard_ignores_legacy_cookie_when_cutover_enabled() {
        let st = state(true, &["https://online.shamell.online"], false);
        let h = headers(&[
            ("cookie", "sa_session=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
            ("origin", "https://evil.example"),
            ("host", "api.shamell.online"),
        ]);
        assert_eq!(csrf_block_reason(&st, &Method::POST, &h), None);
    }

    #[test]
    fn csrf_guard_does_not_skip_on_invalid_sa_cookie_header() {
        let st = state(true, &["https://online.shamell.online"], false);
        let h = headers(&[
            (
                "cookie",
                "__Host-sa_session=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            ),
            ("sa_cookie", "not-a-token"),
            ("origin", "https://evil.example"),
            ("host", "api.shamell.online"),
        ]);
        assert_eq!(
            csrf_block_reason(&st, &Method::POST, &h),
            Some("origin_not_allowed")
        );
    }

    #[test]
    fn csrf_guard_ignores_sa_cookie_header_for_non_browser_flow() {
        let st = state(true, &["https://online.shamell.online"], false);
        let h = headers(&[
            (
                "cookie",
                "__Host-sa_session=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            ),
            ("sa_cookie", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
        ]);
        assert_eq!(csrf_block_reason(&st, &Method::POST, &h), None);
    }

    #[test]
    fn csrf_guard_without_session_cookie_is_not_blocked() {
        let st = state(true, &["https://online.shamell.online"], false);
        let h = headers(&[
            ("sa_cookie", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
            ("origin", "https://evil.example"),
            ("host", "api.shamell.online"),
        ]);
        assert_eq!(csrf_block_reason(&st, &Method::POST, &h), None);
    }

    #[test]
    fn bff_public_cors_whitelist_is_minimal_and_excludes_sensitive_headers() {
        let headers = bff_public_cors_allowed_headers();
        let has = |name: &str| {
            headers
                .iter()
                .any(|h| h.as_str().eq_ignore_ascii_case(name))
        };

        assert!(has("content-type"));
        assert!(has("x-request-id"));

        assert!(!has("authorization"));
        assert!(!has("x-chat-device-id"));
        assert!(!has("x-chat-device-token"));
        assert!(!has("x-device-id"));
        assert!(!has("idempotency-key"));
        assert!(!has("x-merchant"));
        assert!(!has("x-ref"));
        assert_no_sensitive_headers(&headers);
    }

    #[test]
    fn bff_chat_cors_whitelist_includes_only_chat_headers_and_excludes_sensitive_headers() {
        let headers = bff_chat_cors_allowed_headers();
        let has = |name: &str| {
            headers
                .iter()
                .any(|h| h.as_str().eq_ignore_ascii_case(name))
        };

        assert!(has("content-type"));
        assert!(has("x-chat-device-id"));
        assert!(has("x-chat-device-token"));
        assert!(has("x-request-id"));
        assert!(!has("idempotency-key"));
        assert!(!has("x-device-id"));
        assert!(!has("x-merchant"));
        assert!(!has("x-ref"));
        assert_no_sensitive_headers(&headers);
    }

    #[test]
    fn bff_contacts_cors_whitelist_includes_contact_headers_and_excludes_sensitive_headers() {
        let headers = bff_contacts_cors_allowed_headers();
        let has = |name: &str| {
            headers
                .iter()
                .any(|h| h.as_str().eq_ignore_ascii_case(name))
        };

        assert!(has("content-type"));
        assert!(has("x-chat-device-id"));
        assert!(has("x-request-id"));
        assert!(!has("x-chat-device-token"));
        assert!(!has("idempotency-key"));
        assert!(!has("x-device-id"));
        assert!(!has("x-merchant"));
        assert!(!has("x-ref"));
        assert_no_sensitive_headers(&headers);
    }

    #[test]
    fn bff_payments_cors_whitelist_includes_payment_headers_and_excludes_sensitive_headers() {
        let headers = bff_payments_cors_allowed_headers();
        let has = |name: &str| {
            headers
                .iter()
                .any(|h| h.as_str().eq_ignore_ascii_case(name))
        };

        assert!(has("content-type"));
        assert!(has("idempotency-key"));
        assert!(has("x-device-id"));
        assert!(has("x-merchant"));
        assert!(has("x-ref"));
        assert!(has("x-request-id"));
        assert!(!has("x-chat-device-id"));
        assert!(!has("x-chat-device-token"));
        assert_no_sensitive_headers(&headers);
    }

    #[test]
    fn bff_bus_cors_whitelist_includes_bus_headers_and_excludes_sensitive_headers() {
        let headers = bff_bus_cors_allowed_headers();
        let has = |name: &str| {
            headers
                .iter()
                .any(|h| h.as_str().eq_ignore_ascii_case(name))
        };

        assert!(has("content-type"));
        assert!(has("idempotency-key"));
        assert!(has("x-device-id"));
        assert!(has("x-request-id"));
        assert!(!has("x-chat-device-id"));
        assert!(!has("x-chat-device-token"));
        assert!(!has("x-merchant"));
        assert!(!has("x-ref"));
        assert_no_sensitive_headers(&headers);
    }

    #[tokio::test]
    async fn cors_preflight_public_allows_only_public_headers() {
        let resp = preflight(
            "/auth/biometric/login",
            Method::POST,
            "content-type,x-request-id",
        )
        .await;
        assert!(resp.status().is_success());
        assert!(has_allow_header(&resp, "content-type"));
        assert!(has_allow_header(&resp, "x-request-id"));
        assert!(!has_allow_header(&resp, "x-chat-device-id"));
        assert!(!has_allow_header(&resp, "idempotency-key"));
    }

    #[tokio::test]
    async fn cors_preflight_chat_zone_scopes_to_chat_headers() {
        let resp = preflight(
            "/chat/messages/send",
            Method::POST,
            "content-type,x-chat-device-id,x-chat-device-token",
        )
        .await;
        assert!(resp.status().is_success());
        assert!(has_allow_header(&resp, "x-chat-device-id"));
        assert!(has_allow_header(&resp, "x-chat-device-token"));
        assert!(!has_allow_header(&resp, "x-merchant"));
        assert!(!has_allow_header(&resp, "idempotency-key"));
    }

    #[tokio::test]
    async fn cors_preflight_contacts_zone_scopes_to_contact_headers() {
        let resp = preflight(
            "/contacts/invites/redeem",
            Method::POST,
            "content-type,x-chat-device-id",
        )
        .await;
        assert!(resp.status().is_success());
        assert!(has_allow_header(&resp, "x-chat-device-id"));
        assert!(!has_allow_header(&resp, "x-chat-device-token"));
        assert!(!has_allow_header(&resp, "x-merchant"));
        assert!(!has_allow_header(&resp, "idempotency-key"));
    }

    #[tokio::test]
    async fn cors_preflight_payments_zone_scopes_to_payments_headers() {
        let resp = preflight(
            "/payments/transfer",
            Method::POST,
            "content-type,idempotency-key,x-device-id,x-merchant,x-ref",
        )
        .await;
        assert!(resp.status().is_success());
        assert!(has_allow_header(&resp, "idempotency-key"));
        assert!(has_allow_header(&resp, "x-device-id"));
        assert!(has_allow_header(&resp, "x-merchant"));
        assert!(has_allow_header(&resp, "x-ref"));
        assert!(!has_allow_header(&resp, "x-chat-device-id"));
    }

    #[tokio::test]
    async fn cors_preflight_bus_zone_scopes_to_bus_headers() {
        let resp = preflight(
            "/bus/trips/t-123/book",
            Method::POST,
            "content-type,idempotency-key,x-device-id",
        )
        .await;
        assert!(resp.status().is_success());
        assert!(has_allow_header(&resp, "idempotency-key"));
        assert!(has_allow_header(&resp, "x-device-id"));
        assert!(!has_allow_header(&resp, "x-merchant"));
        assert!(!has_allow_header(&resp, "x-chat-device-id"));
    }

    #[tokio::test]
    async fn cors_preflight_internal_route_has_no_cors_headers() {
        let resp = preflight(
            "/internal/security/alerts",
            Method::POST,
            "content-type,x-request-id",
        )
        .await;
        assert!(resp.status().is_client_error());
        assert!(resp
            .headers()
            .get(header::ACCESS_CONTROL_ALLOW_ORIGIN)
            .is_none());
    }
}
