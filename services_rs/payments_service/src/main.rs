mod config;
mod db;
mod error;
mod handlers;
mod models;
mod state;

use axum::extract::MatchedPath;
use axum::extract::Request;
use axum::http::{header, header::HeaderName, Method, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::{delete, get, post};
use axum::Router;
use config::Config;
use shamell_common::host_guard::AllowedHostsLayer;
use shamell_common::internal_auth::InternalAuthLayer;
use shamell_common::request_id::RequestIdLayer;
use shamell_common::security_headers::SecurityHeadersLayer;
use state::AppState;
use std::net::SocketAddr;
use tower_http::cors::{AllowOrigin, Any, CorsLayer};
use tower_http::limit::RequestBodyLimitLayer;
use tower_http::trace::TraceLayer;
use tracing_subscriber::EnvFilter;

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

    let pool = match db::connect(&cfg.db_url).await {
        Ok(p) => p,
        Err(e) => {
            tracing::error!(error = %e, "db connect failed");
            std::process::exit(2);
        }
    };

    if let Err(e) = db::ensure_schema(&pool, &cfg.db_schema).await {
        tracing::error!(error = %e, "db ensure_schema failed");
        std::process::exit(2);
    }

    let state = AppState {
        pool,
        db_schema: cfg.db_schema.clone(),
        env_name: cfg.env_name.clone(),
        default_currency: cfg.default_currency.clone(),
        allow_direct_topup: cfg.allow_direct_topup,
        bus_payments_internal_secret: cfg.bus_payments_internal_secret.clone(),
        merchant_fee_bps: cfg.merchant_fee_bps,
        fee_wallet_account_id: cfg.fee_wallet_account_id.clone(),
        fee_wallet_phone: cfg.fee_wallet_phone.clone(),
    };

    if let Err(e) = handlers::ensure_fee_wallet(&state).await {
        tracing::error!(error = ?e, "failed to ensure fee wallet");
        std::process::exit(2);
    }

    let internal = InternalAuthLayer::new(cfg.require_internal_secret, cfg.internal_secret.clone())
        .with_allowed_callers(cfg.internal_allowed_callers.clone());

    let bus_only = Router::new()
        .route(
            "/internal/bus/bookings/transfer",
            post(handlers::transfer_bus_booking),
        )
        .layer(middleware::from_fn(require_bus_caller));

    let bff_only = Router::new()
        .route("/users", post(handlers::create_user))
        .route("/transfer", post(handlers::transfer))
        .route("/wallets/:wallet_id", get(handlers::get_wallet))
        .route("/wallets/:wallet_id/topup", post(handlers::topup))
        .route("/txns", get(handlers::list_txns))
        .route(
            "/favorites",
            post(handlers::create_favorite).get(handlers::list_favorites),
        )
        .route("/favorites/:fid", delete(handlers::delete_favorite))
        .route(
            "/requests",
            post(handlers::create_request).get(handlers::list_requests),
        )
        .route("/requests/:rid/accept", post(handlers::accept_request))
        .route("/requests/:rid/cancel", post(handlers::cancel_request))
        .route("/idempotency/:ikey", get(handlers::idempotency_status))
        .route(
            "/admin/roles",
            get(handlers::roles_list)
                .post(handlers::roles_add)
                .delete(handlers::roles_remove),
        )
        .route("/admin/roles/check", get(handlers::roles_check))
        .layer(middleware::from_fn(require_bff_caller));

    let bff_authed = Router::new().merge(bff_only).layer(internal);

    let cors = if cfg.allowed_origins.iter().any(|o| o == "*") {
        CorsLayer::new()
            .allow_origin(Any)
            .allow_methods([Method::GET, Method::POST, Method::DELETE, Method::OPTIONS])
            .allow_headers(payments_cors_allowed_headers())
            .allow_credentials(false)
    } else {
        let origins: Vec<axum::http::HeaderValue> = cfg
            .allowed_origins
            .iter()
            .filter_map(|o| o.parse().ok())
            .collect();
        CorsLayer::new()
            .allow_methods([Method::GET, Method::POST, Method::DELETE, Method::OPTIONS])
            .allow_headers(payments_cors_allowed_headers())
            .allow_credentials(false)
            .allow_origin(AllowOrigin::list(origins))
    };

    let app = Router::new()
        .route("/health", get(handlers::health))
        .merge(bus_only)
        .merge(bff_authed)
        // Ensure unknown routes return 404, not auth middleware fallback details.
        .fallback(|| async { StatusCode::NOT_FOUND })
        .with_state(state)
        .layer(cors)
        .layer(RequestBodyLimitLayer::new(cfg.max_body_bytes))
        .layer(AllowedHostsLayer::new(cfg.allowed_hosts.clone()))
        .layer(SecurityHeadersLayer::from_env(&cfg.env_name))
        // Avoid logging sensitive query parameters. We log the matched route template when
        // available, otherwise just the path (no query string).
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
    tracing::info!(%addr, "starting shamell_payments_service");

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

fn payments_cors_allowed_headers() -> Vec<HeaderName> {
    vec![
        header::ACCEPT,
        header::AUTHORIZATION,
        header::CONTENT_TYPE,
        HeaderName::from_static("x-request-id"),
        HeaderName::from_static("idempotency-key"),
        HeaderName::from_static("x-device-id"),
        HeaderName::from_static("x-merchant"),
        HeaderName::from_static("x-ref"),
    ]
}

#[derive(serde::Serialize)]
struct ErrorBody<'a> {
    detail: &'a str,
}

async fn require_bff_caller(req: Request, next: Next) -> Response {
    let caller = req
        .headers()
        .get("x-internal-service-id")
        .and_then(|v| v.to_str().ok())
        .map(str::trim)
        .map(str::to_ascii_lowercase)
        .unwrap_or_default();
    if caller != "bff" {
        return (
            StatusCode::UNAUTHORIZED,
            axum::Json(ErrorBody {
                detail: "internal caller not allowed",
            }),
        )
            .into_response();
    }
    next.run(req).await
}

async fn require_bus_caller(req: Request, next: Next) -> Response {
    let caller = req
        .headers()
        .get("x-internal-service-id")
        .and_then(|v| v.to_str().ok())
        .map(str::trim)
        .map(str::to_ascii_lowercase)
        .unwrap_or_default();
    if caller != "bus" {
        return (
            StatusCode::UNAUTHORIZED,
            axum::Json(ErrorBody {
                detail: "internal caller not allowed",
            }),
        )
            .into_response();
    }
    next.run(req).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{HeaderValue, Request, StatusCode};
    use axum::routing::get;
    use tower::ServiceExt;

    async fn ok_handler() -> &'static str {
        "ok"
    }

    #[tokio::test]
    async fn bff_caller_guard_blocks_non_bff() {
        let app = Router::new()
            .route("/x", get(ok_handler))
            .layer(middleware::from_fn(require_bff_caller));

        let resp = app
            .clone()
            .oneshot(Request::builder().uri("/x").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);

        let mut wrong = Request::builder().uri("/x").body(Body::empty()).unwrap();
        wrong.headers_mut().insert(
            "x-internal-service-id",
            HeaderValue::from_static("security-reporter"),
        );
        let resp = app.clone().oneshot(wrong).await.unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);

        let mut ok = Request::builder().uri("/x").body(Body::empty()).unwrap();
        ok.headers_mut()
            .insert("x-internal-service-id", HeaderValue::from_static("bff"));
        let resp = app.oneshot(ok).await.unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn bus_caller_guard_blocks_non_bus() {
        let app = Router::new()
            .route("/x", get(ok_handler))
            .layer(middleware::from_fn(require_bus_caller));

        let resp = app
            .clone()
            .oneshot(Request::builder().uri("/x").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);

        let mut wrong = Request::builder().uri("/x").body(Body::empty()).unwrap();
        wrong
            .headers_mut()
            .insert("x-internal-service-id", HeaderValue::from_static("bff"));
        let resp = app.clone().oneshot(wrong).await.unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);

        let mut ok = Request::builder().uri("/x").body(Body::empty()).unwrap();
        ok.headers_mut()
            .insert("x-internal-service-id", HeaderValue::from_static("bus"));
        let resp = app.oneshot(ok).await.unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn unknown_routes_return_404_not_internal_auth_required() {
        let internal = InternalAuthLayer::new(true, Some("test-secret".to_string()));
        let authed = Router::new()
            .route("/foo", get(ok_handler))
            .layer(internal);

        let app = Router::new()
            .route("/health", get(ok_handler))
            .merge(authed)
            .fallback(|| async { StatusCode::NOT_FOUND });

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

    #[test]
    fn payments_cors_whitelist_excludes_internal_and_proxy_headers() {
        let headers = payments_cors_allowed_headers();
        let has = |name: &str| {
            headers
                .iter()
                .any(|h| h.as_str().eq_ignore_ascii_case(name))
        };

        assert!(has("content-type"));
        assert!(has("x-request-id"));
        assert!(has("idempotency-key"));
        assert!(has("x-merchant"));
        assert!(has("x-ref"));

        assert!(!has("x-internal-secret"));
        assert!(!has("x-internal-service-id"));
        assert!(!has("x-bus-payments-internal-secret"));
        assert!(!has("x-forwarded-for"));
        assert!(!has("x-forwarded-host"));
        assert!(!has("x-real-ip"));
        assert!(!has("x-shamell-client-ip"));
        assert!(!has("cookie"));
    }
}
