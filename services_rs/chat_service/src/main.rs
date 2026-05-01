use axum::extract::MatchedPath;
use axum::http::{header, header::HeaderName, Method, StatusCode};
use axum::routing::{get, post};
use axum::{Json, Router};
use serde_json::json;
use sha2::{Digest, Sha256};
use shamell_chat_service::{
    config::Config,
    db, handlers,
    push_token_crypto::{backfill_legacy_push_tokens, PushTokenProtector},
    state::AppState,
};
use shamell_common::host_guard::AllowedHostsLayer;
use shamell_common::internal_auth::InternalAuthLayer;
use shamell_common::internal_identity::InternalIdentityVerifier;
use shamell_common::request_id::RequestIdLayer;
use shamell_common::security_headers::SecurityHeadersLayer;
use std::net::SocketAddr;
use std::time::Duration;
use tokio::time::MissedTickBehavior;
use tower_http::cors::{AllowOrigin, Any, CorsLayer};
use tower_http::limit::RequestBodyLimitLayer;
use tower_http::trace::TraceLayer;
use tracing_subscriber::EnvFilter;

const RATE_LIMIT_CLEANUP_INTERVAL_SECS: u64 = 600;

fn hash_prefix(value: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(value.as_bytes());
    let digest = hasher.finalize();
    digest
        .iter()
        .take(6)
        .map(|b| format!("{b:02x}"))
        .collect::<String>()
}

fn http_request_span<B>(req: &axum::http::Request<B>) -> tracing::Span {
    if let Some(route) = req
        .extensions()
        .get::<MatchedPath>()
        .map(MatchedPath::as_str)
    {
        tracing::span!(
            tracing::Level::INFO,
            "http_request",
            method = %req.method(),
            route
        )
    } else {
        let path_hash = hash_prefix(req.uri().path());
        tracing::span!(
            tracing::Level::INFO,
            "http_request",
            method = %req.method(),
            path_hash
        )
    }
}

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
    let schema_result = if cfg.auto_apply_schema {
        match db::apply_versioned_schema_migrations(&pool, &cfg.db_schema).await {
            Ok(()) => db::ensure_schema(&pool, &cfg.db_schema).await,
            Err(e) => Err(e),
        }
    } else {
        db::assert_schema_ready(&pool, &cfg.db_schema).await
    };
    if let Err(e) = schema_result {
        tracing::error!(
            error = %e,
            auto_apply_schema = cfg.auto_apply_schema,
            "chat schema check failed"
        );
        std::process::exit(2);
    }

    let http = match reqwest::Client::builder()
        .timeout(Duration::from_secs(20))
        .connect_timeout(Duration::from_secs(5))
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
        chat_background_purge_enabled: cfg.purge_interval_seconds > 0,
        fcm_server_key: cfg.fcm_server_key.clone(),
        fcm_project_id: cfg.fcm_project_id.clone(),
        fcm_client_email: cfg.fcm_client_email.clone(),
        fcm_private_key_pem: cfg.fcm_private_key_pem.clone(),
        chat_protocol_v2_enabled: cfg.chat_protocol_v2_enabled,
        chat_protocol_v1_write_enabled: cfg.chat_protocol_v1_write_enabled,
        chat_protocol_v1_read_enabled: cfg.chat_protocol_v1_read_enabled,
        chat_protocol_require_v2_for_groups: cfg.chat_protocol_require_v2_for_groups,
        chat_mailbox_api_enabled: cfg.chat_mailbox_api_enabled,
        chat_mailbox_inactive_retention_secs: cfg.chat_mailbox_inactive_retention_secs,
        chat_mailbox_consumed_retention_secs: cfg.chat_mailbox_consumed_retention_secs,
        push_token_protector: PushTokenProtector::new(cfg.chat_push_token_encryption_key),
        http,
    };

    match backfill_legacy_push_tokens(&state).await {
        Ok(updated) => {
            if updated > 0 {
                tracing::info!(updated, "chat push-token ciphertext backfill completed");
            }
        }
        Err(error) => {
            tracing::error!(error = %error, "chat push-token ciphertext backfill failed");
            std::process::exit(2);
        }
    }

    if cfg.purge_interval_seconds > 0 {
        let st = state.clone();
        let secs = cfg.purge_interval_seconds as u64;
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_secs(secs));
            interval.set_missed_tick_behavior(MissedTickBehavior::Skip);
            loop {
                interval.tick().await;
                if let Err(err) = handlers::purge_expired(&st).await {
                    tracing::error!(error = ?err, "chat purge_expired background task failed");
                }
            }
        });
    }

    {
        let st = state.clone();
        tokio::spawn(async move {
            let mut interval =
                tokio::time::interval(Duration::from_secs(RATE_LIMIT_CLEANUP_INTERVAL_SECS));
            interval.set_missed_tick_behavior(MissedTickBehavior::Skip);
            loop {
                interval.tick().await;
                if let Err(err) = handlers::cleanup_chat_rate_limits(&st).await {
                    tracing::error!(error = ?err, "chat rate-limit cleanup background task failed");
                }
            }
        });
    }

    let internal_identity_verifier = if cfg.internal_identity_public_keys.is_empty() {
        None
    } else {
        match InternalIdentityVerifier::from_public_keys_base64(
            cfg.internal_identity_public_keys.clone(),
            cfg.internal_identity_max_skew_secs,
        ) {
            Ok(verifier) => Some(verifier),
            Err(e) => {
                tracing::error!(error = %e, "internal identity verifier init failed");
                std::process::exit(2);
            }
        }
    };

    let mut internal =
        InternalAuthLayer::new(cfg.require_internal_secret, cfg.internal_secret.clone())
            .with_allowed_callers(cfg.internal_allowed_callers.clone())
            .with_expected_audience("chat")
            .with_body_limit(cfg.max_body_bytes);
    if let Some(verifier) = internal_identity_verifier {
        internal = internal
            .with_identity_verifier(verifier)
            .with_require_identity_v2(cfg.require_internal_identity_v2)
            .with_legacy_secret_fallback(cfg.allow_legacy_internal_secret_fallback);
    }

    let authed = Router::new()
        .route("/devices/register", post(handlers::register))
        .route("/devices/:device_id", get(handlers::get_device))
        .route(
            "/devices/:device_id/guardrails/direct_peer",
            post(handlers::direct_peer_guard),
        )
        .route("/keys/bootstrap", post(handlers::bootstrap_keys))
        .route("/keys/register", post(handlers::register_keys))
        .route(
            "/keys/prekeys/status/:device_id",
            get(handlers::get_prekey_status),
        )
        .route("/keys/prekeys/upload", post(handlers::upload_prekeys))
        .route("/keys/bundle/:device_id", get(handlers::get_key_bundle))
        .route("/mailboxes/issue", post(handlers::issue_mailbox))
        .route("/mailboxes/write", post(handlers::write_mailbox))
        .route("/mailboxes/poll", post(handlers::poll_mailbox))
        .route("/mailboxes/rotate", post(handlers::rotate_mailbox))
        .route("/messages/send", post(handlers::send_message))
        .route("/messages/inbox", get(handlers::inbox))
        .route("/messages/inbox/window", post(handlers::inbox_window))
        .route("/messages/thread", get(handlers::thread_history))
        .route("/messages/stream", get(handlers::stream))
        .route("/events", get(handlers::list_conversation_events))
        .route("/events/stream", get(handlers::stream_conversation_events))
        .route("/messages/pins", get(handlers::list_message_pins))
        .route(
            "/messages/:mid/reactions",
            get(handlers::list_message_reactions).post(handlers::set_message_reaction),
        )
        .route("/messages/:mid/edit", post(handlers::edit_message))
        .route("/messages/:mid/delete", post(handlers::delete_message))
        .route("/messages/:mid/pin", post(handlers::set_message_pin))
        .route("/messages/:mid/report", post(handlers::report_message))
        .route("/messages/:mid/read", post(handlers::mark_read))
        .route(
            "/voice/transcripts",
            get(handlers::get_voice_transcript).post(handlers::save_voice_transcript),
        )
        .route(
            "/voice/transcript_jobs",
            get(handlers::list_voice_transcript_jobs).post(handlers::request_voice_transcript_job),
        )
        .route(
            "/voice/transcript_jobs/:job_id/complete",
            post(handlers::complete_voice_transcript_job),
        )
        .route(
            "/admin/moderation/reports",
            get(handlers::list_moderation_reports),
        )
        .route(
            "/admin/moderation/reports/:report_id/action",
            post(handlers::update_moderation_report),
        )
        .route(
            "/calls/logs",
            get(handlers::list_call_logs).post(handlers::save_call_log),
        )
        .route(
            "/devices/:device_id/push_token",
            post(handlers::register_push_token).delete(handlers::unregister_push_token),
        )
        .route("/push/notify", post(handlers::push_notify_internal))
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
        .route("/groups/inbox/batch", post(handlers::group_inbox_batch))
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
        // Avoid logging sensitive identifiers in raw fallback paths. Keep matched route
        // templates for observability and hash unmatched paths instead.
        .layer(TraceLayer::new_for_http().make_span_with(http_request_span))
        .layer(RequestIdLayer::new(HeaderName::from_static("x-request-id")));

    let addr: SocketAddr = format!("{}:{}", cfg.host, cfg.port)
        .parse()
        .unwrap_or_else(|_| SocketAddr::from(([0, 0, 0, 0], cfg.port)));
    tracing::info!(%addr, "starting shamell_chat_service");

    let listener = match tokio::net::TcpListener::bind(addr).await {
        Ok(listener) => listener,
        Err(e) => {
            tracing::error!(error = %e, %addr, "listener bind failed");
            std::process::exit(2);
        }
    };
    if let Err(e) = axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
    {
        tracing::error!(error = %e, "server exited with error");
        std::process::exit(2);
    }
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
        assert!(!has("x-internal-audience"));
        assert!(!has("x-internal-identity-ts"));
        assert!(!has("x-internal-identity-sig"));
        assert!(!has("x-internal-identity-sig-v2"));
        assert!(!has("x-internal-identity-nonce"));
        assert!(!has("x-legacy-internal-secret"));
        assert!(!has("x-forwarded-for"));
        assert!(!has("x-forwarded-host"));
        assert!(!has("x-real-ip"));
        assert!(!has("x-shamell-client-ip"));
        assert!(!has("x-shamell-client-ip-attested"));
        assert!(!has("cookie"));
    }
}
