mod config;
mod db;
mod error;
mod handlers;
mod models;
mod state;

use axum::extract::MatchedPath;
use axum::http::{header, header::HeaderName, Method, StatusCode};
use axum::routing::{get, post};
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
        env_name: cfg.env_name.clone(),
        enforce_device_auth: cfg.enforce_device_auth,
        fcm_server_key: cfg.fcm_server_key.clone(),
        chat_protocol_v2_enabled: cfg.chat_protocol_v2_enabled,
        chat_protocol_v1_write_enabled: cfg.chat_protocol_v1_write_enabled,
        chat_protocol_v1_read_enabled: cfg.chat_protocol_v1_read_enabled,
        chat_protocol_require_v2_for_groups: cfg.chat_protocol_require_v2_for_groups,
        chat_mailbox_api_enabled: cfg.chat_mailbox_api_enabled,
        chat_mailbox_inactive_retention_secs: cfg.chat_mailbox_inactive_retention_secs,
        chat_mailbox_consumed_retention_secs: cfg.chat_mailbox_consumed_retention_secs,
        http,
    };

    if cfg.purge_interval_seconds > 0 {
        let st = state.clone();
        let secs = cfg.purge_interval_seconds as u64;
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_secs(secs));
            loop {
                interval.tick().await;
                let _ = handlers::purge_expired(&st).await;
            }
        });
    }

    let internal = InternalAuthLayer::new(cfg.require_internal_secret, cfg.internal_secret.clone())
        .with_allowed_callers(cfg.internal_allowed_callers.clone());

    let authed = Router::new()
        .route("/devices/register", post(handlers::register))
        .route("/devices/:device_id", get(handlers::get_device))
        .route("/keys/register", post(handlers::register_keys))
        .route("/keys/prekeys/upload", post(handlers::upload_prekeys))
        .route("/keys/bundle/:device_id", get(handlers::get_key_bundle))
        .route("/mailboxes/issue", post(handlers::issue_mailbox))
        .route("/mailboxes/write", post(handlers::write_mailbox))
        .route("/mailboxes/poll", post(handlers::poll_mailbox))
        .route("/mailboxes/rotate", post(handlers::rotate_mailbox))
        .route("/messages/send", post(handlers::send_message))
        .route("/messages/inbox", get(handlers::inbox))
        .route("/messages/stream", get(handlers::stream))
        .route("/messages/:mid/read", post(handlers::mark_read))
        .route(
            "/devices/:device_id/push_token",
            post(handlers::register_push_token),
        )
        .route("/devices/:device_id/block", post(handlers::set_block))
        .route(
            "/devices/:device_id/prefs",
            post(handlers::set_prefs).get(handlers::list_prefs),
        )
        .route(
            "/devices/:device_id/group_prefs",
            post(handlers::set_group_prefs).get(handlers::list_group_prefs),
        )
        .route("/devices/:device_id/hidden", get(handlers::list_hidden))
        .route("/groups/create", post(handlers::create_group))
        .route("/groups/list", get(handlers::list_groups))
        .route("/groups/:group_id/update", post(handlers::update_group))
        .route(
            "/groups/:group_id/messages/send",
            post(handlers::send_group_message),
        )
        .route(
            "/groups/:group_id/messages/inbox",
            get(handlers::group_inbox),
        )
        .route("/groups/:group_id/members", get(handlers::group_members))
        .route("/groups/:group_id/invite", post(handlers::invite_members))
        .route("/groups/:group_id/leave", post(handlers::leave_group))
        .route("/groups/:group_id/set_role", post(handlers::set_group_role))
        .route(
            "/groups/:group_id/keys/rotate",
            post(handlers::rotate_group_key),
        )
        .route(
            "/groups/:group_id/keys/events",
            get(handlers::list_key_events),
        )
        .layer(internal);

    let cors = if cfg.allowed_origins.iter().any(|o| o == "*") {
        CorsLayer::new()
            .allow_origin(Any)
            .allow_methods([Method::GET, Method::POST, Method::DELETE, Method::OPTIONS])
            .allow_headers(chat_cors_allowed_headers())
            .allow_credentials(false)
    } else {
        let origins: Vec<axum::http::HeaderValue> = cfg
            .allowed_origins
            .iter()
            .filter_map(|o| o.parse().ok())
            .collect();
        CorsLayer::new()
            .allow_methods([Method::GET, Method::POST, Method::DELETE, Method::OPTIONS])
            .allow_headers(chat_cors_allowed_headers())
            .allow_credentials(false)
            .allow_origin(AllowOrigin::list(origins))
    };

    let app = Router::new()
        .route("/health", get(handlers::health))
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
        .layer(RequestBodyLimitLayer::new(cfg.max_body_bytes))
        .layer(cors)
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
    tracing::info!(%addr, "starting shamell_chat_service");

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

fn chat_cors_allowed_headers() -> Vec<HeaderName> {
    vec![
        header::ACCEPT,
        header::AUTHORIZATION,
        header::CONTENT_TYPE,
        HeaderName::from_static("x-request-id"),
        HeaderName::from_static("x-chat-device-id"),
        HeaderName::from_static("x-chat-device-token"),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chat_cors_whitelist_excludes_internal_and_proxy_headers() {
        let headers = chat_cors_allowed_headers();
        let has = |name: &str| {
            headers
                .iter()
                .any(|h| h.as_str().eq_ignore_ascii_case(name))
        };

        assert!(has("content-type"));
        assert!(has("x-chat-device-id"));
        assert!(has("x-chat-device-token"));
        assert!(has("x-request-id"));

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
