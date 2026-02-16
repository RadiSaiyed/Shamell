mod config;
mod db;
mod error;
mod handlers;
mod models;
mod state;

use axum::extract::MatchedPath;
use axum::http::{header, header::HeaderName, Method, StatusCode};
use axum::routing::{get, post};
use axum::Router;
use config::Config;
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

    let http = match reqwest::Client::builder()
        .timeout(Duration::from_secs(20))
        .build()
    {
        Ok(c) => c,
        Err(e) => {
            tracing::error!(error = %e, "http client init failed");
            std::process::exit(2);
        }
    };

    let state = AppState {
        pool,
        db_schema: cfg.db_schema.clone(),
        ticket_secret: cfg.ticket_secret.clone(),
        env_name: cfg.env_name.clone(),
        env_lower: cfg.env_lower.clone(),
        internal_service_id: cfg.internal_service_id.clone(),
        payments_base_url: cfg.payments_base_url.clone(),
        bus_payments_internal_secret: cfg.bus_payments_internal_secret.clone(),
        http,
    };

    let internal = InternalAuthLayer::new(cfg.require_internal_secret, cfg.internal_secret.clone())
        .with_allowed_callers(cfg.internal_allowed_callers.clone());

    let authed = Router::new()
        .route(
            "/cities",
            get(handlers::list_cities).post(handlers::create_city),
        )
        .route(
            "/operators",
            get(handlers::list_operators).post(handlers::create_operator),
        )
        .route("/operators/:operator_id", get(handlers::get_operator))
        .route(
            "/operators/:operator_id/online",
            post(handlers::operator_online),
        )
        .route(
            "/operators/:operator_id/offline",
            post(handlers::operator_offline),
        )
        .route(
            "/operators/:operator_id/trips",
            get(handlers::operator_trips),
        )
        .route(
            "/operators/:operator_id/stats",
            get(handlers::operator_stats),
        )
        .route(
            "/routes",
            get(handlers::list_routes).post(handlers::create_route),
        )
        .route("/routes/:route_id", get(handlers::route_detail))
        .route("/trips", post(handlers::create_trip))
        .route("/trips/search", get(handlers::search_trips))
        .route("/trips/:trip_id", get(handlers::trip_detail))
        .route("/trips/:trip_id/publish", post(handlers::publish_trip))
        .route("/trips/:trip_id/unpublish", post(handlers::unpublish_trip))
        .route("/trips/:trip_id/cancel", post(handlers::cancel_trip))
        .route("/trips/:trip_id/quote", post(handlers::quote))
        .route("/trips/:trip_id/book", post(handlers::book_trip))
        .route("/bookings/:booking_id", get(handlers::booking_status))
        .route(
            "/bookings/:booking_id/cancel",
            post(handlers::cancel_booking),
        )
        .route("/bookings/search", get(handlers::booking_search))
        .route(
            "/bookings/:booking_id/tickets",
            get(handlers::booking_tickets),
        )
        .route("/tickets/board", post(handlers::ticket_board))
        .route("/admin/summary", get(handlers::admin_summary))
        .layer(internal);

    let cors = if cfg.allowed_origins.iter().any(|o| o == "*") {
        CorsLayer::new()
            .allow_origin(Any)
            .allow_methods([Method::GET, Method::POST, Method::DELETE, Method::OPTIONS])
            .allow_headers(bus_cors_allowed_headers())
            .allow_credentials(false)
    } else {
        let origins: Vec<axum::http::HeaderValue> = cfg
            .allowed_origins
            .iter()
            .filter_map(|o| o.parse().ok())
            .collect();
        CorsLayer::new()
            .allow_methods([Method::GET, Method::POST, Method::DELETE, Method::OPTIONS])
            .allow_headers(bus_cors_allowed_headers())
            // This is an internal service (no cookies/session credentials expected).
            .allow_credentials(false)
            .allow_origin(AllowOrigin::list(origins))
    };

    let app = Router::new()
        .route("/health", get(handlers::health))
        .merge(authed)
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
    tracing::info!(%addr, "starting shamell_bus_service");

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

fn bus_cors_allowed_headers() -> Vec<HeaderName> {
    vec![
        header::ACCEPT,
        header::AUTHORIZATION,
        header::CONTENT_TYPE,
        HeaderName::from_static("x-request-id"),
        HeaderName::from_static("idempotency-key"),
        HeaderName::from_static("x-device-id"),
    ]
}

#[cfg(test)]
mod router_fallback_tests {
    use super::*;
    use axum::body::Body;
    use axum::http::Request;
    use tower::ServiceExt;

    async fn ok_handler() -> &'static str {
        "ok"
    }

    #[tokio::test]
    async fn unknown_routes_return_404_not_internal_auth_required() {
        let internal = InternalAuthLayer::new(true, Some("test-secret".to_string()));
        let authed = Router::new().route("/foo", get(ok_handler)).layer(internal);

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
    fn bus_cors_whitelist_excludes_internal_and_proxy_headers() {
        let headers = bus_cors_allowed_headers();
        let has = |name: &str| {
            headers
                .iter()
                .any(|h| h.as_str().eq_ignore_ascii_case(name))
        };

        assert!(has("content-type"));
        assert!(has("x-request-id"));
        assert!(has("idempotency-key"));
        assert!(has("x-device-id"));

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
