use axum::extract::connect_info::ConnectInfo;
use axum::extract::MatchedPath;
use axum::extract::{Request, State};
use axum::http::{header, header::HeaderName, HeaderMap, HeaderValue, Method, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::{delete, get, patch, post};
use axum::{Json, Router};
use ipnet::IpNet;
use serde_json::json;
use sha2::{Digest, Sha256};
use shamell_bff_gateway::{
    auth, authz, coach_catalog, coach_gtfs,
    config::Config,
    handlers,
    state::{
        AppState, DirectWebAccessConfig, DirectWebLaunchConfig, WorkforceAccessConfig,
        DEFAULT_GEO_LOOKUP_BASE_URL,
    },
};
use shamell_common::host_guard::AllowedHostsLayer;
use shamell_common::internal_auth::InternalAuthLayer;
use shamell_common::internal_identity::{InternalIdentityVerifier, InternalRequestSigner};
use shamell_common::request_id::RequestIdLayer;
use shamell_common::security_headers::SecurityHeadersLayer;
use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::RwLock;
use tower_http::cors::{AllowOrigin, Any, CorsLayer};
use tower_http::limit::RequestBodyLimitLayer;
use tower_http::trace::TraceLayer;
use tracing_subscriber::EnvFilter;

const SESSION_COOKIE_NAME: &str = "__Host-sa_session";
const LEGACY_SESSION_COOKIE_NAME: &str = "sa_session";
const TRUSTED_CLIENT_IP_HEADER: &str = "x-shamell-client-ip";
const TRUSTED_CLIENT_IP_ATTESTED_HEADER: &str = "x-shamell-client-ip-attested";

#[derive(Clone)]
struct TrustedProxyState {
    trusted_proxy_cidrs: Vec<IpNet>,
}

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

    let http = match reqwest::Client::builder()
        .timeout(Duration::from_secs(cfg.upstream_timeout_secs))
        .connect_timeout(Duration::from_secs(5))
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
    auth::seed_official_catalog_best_effort(auth.as_ref(), "startup").await;
    let coach_gtfs_feed_dir = if let Some(auth_runtime) = auth.as_ref() {
        let repo = coach_catalog::CoachCatalogRepository::new(auth_runtime.pool().clone());
        match repo.find_import_config("static_catalog", "gtfs").await {
            Ok(Some(config)) => Some(config.feed_locator),
            Ok(None) => coach_gtfs::configured_gtfs_feed_dir(),
            Err(error) => {
                tracing::warn!(
                    error = %error,
                    "coach catalog import config lookup failed during startup; falling back to environment"
                );
                coach_gtfs::configured_gtfs_feed_dir()
            }
        }
    } else {
        coach_gtfs::configured_gtfs_feed_dir()
    };
    coach_gtfs::import_gtfs_catalog_best_effort(
        auth.as_ref(),
        coach_gtfs_feed_dir.as_deref(),
        "startup",
    )
    .await;
    coach_catalog::seed_coach_catalog_best_effort(auth.as_ref(), "startup").await;
    // The maintenance loop's JoinHandle is intentionally held by the
    // process until shutdown -- there is no per-request lifecycle and
    // we never restart it without restarting the process. Drop guard
    // is named to make that lifetime explicit and to silence the
    // #[must_use] on spawn_maintenance_task.
    let _auth_maintenance_task: Option<tokio::task::JoinHandle<()>> =
        auth::spawn_maintenance_task(auth.clone());

    let internal_request_signer = match cfg.internal_identity_signing_seed_b64.as_deref() {
        Some(seed_b64) => {
            match InternalRequestSigner::from_seed_base64(&cfg.internal_service_id, seed_b64) {
                Ok(signer) => Some(signer),
                Err(e) => {
                    tracing::error!(error = %e, "internal identity signer init failed");
                    std::process::exit(2);
                }
            }
        }
        None => None,
    };
    let security_alert_identity_verifier =
        if cfg.security_alert_internal_identity_public_keys.is_empty() {
            None
        } else {
            match InternalIdentityVerifier::from_public_keys_base64(
                cfg.security_alert_internal_identity_public_keys.clone(),
                cfg.security_alert_internal_identity_max_skew_secs,
            ) {
                Ok(verifier) => Some(verifier),
                Err(e) => {
                    tracing::error!(error = %e, "security alert identity verifier init failed");
                    std::process::exit(2);
                }
            }
        };
    let access_assignment_identity_verifier = if cfg
        .access_assignment_internal_identity_public_keys
        .is_empty()
    {
        None
    } else {
        match InternalIdentityVerifier::from_public_keys_base64(
            cfg.access_assignment_internal_identity_public_keys.clone(),
            cfg.access_assignment_internal_identity_max_skew_secs,
        ) {
            Ok(verifier) => Some(verifier),
            Err(e) => {
                tracing::error!(
                    error = %e,
                    "access assignment identity verifier init failed"
                );
                std::process::exit(2);
            }
        }
    };

    let state = AppState {
        env_name: cfg.env_name.clone(),
        allowed_origins: cfg.allowed_origins.clone(),
        payments_base_url: cfg.payments_base_url.clone(),
        payments_internal_secret: cfg.payments_internal_secret.clone(),
        fee_wallet_account_id: cfg.fee_wallet_account_id.clone(),
        fee_wallet_phone: cfg.fee_wallet_phone.clone(),
        chat_base_url: cfg.chat_base_url.clone(),
        chat_internal_secret: cfg.chat_internal_secret.clone(),
        internal_service_id: cfg.internal_service_id.clone(),
        internal_request_signer,
        enforce_route_authz: cfg.enforce_route_authz,
        role_header_secret: cfg.role_header_secret.clone(),
        upstream_timeout_secs: cfg.upstream_timeout_secs,
        max_upstream_body_bytes: cfg.max_upstream_body_bytes,
        expose_upstream_errors: cfg.expose_upstream_errors,
        accept_legacy_session_cookie: cfg.accept_legacy_session_cookie,
        allow_legacy_contact_invite_chat_device_fallback: cfg
            .allow_legacy_contact_invite_chat_device_fallback,
        auth_device_login_web_enabled: cfg.auth_device_login_web_enabled,
        workforce_access: Some(WorkforceAccessConfig {
            oidc_issuer_url: cfg.workforce_oidc_issuer_url.clone(),
            oidc_client_id: cfg.workforce_oidc_client_id.clone(),
            oidc_audience: cfg.workforce_oidc_audience.clone(),
            oidc_jwks_url: cfg.workforce_oidc_jwks_url.clone(),
            cloudflare_access_team_domain: cfg.cloudflare_access_team_domain.clone(),
            cloudflare_access_audiences: cfg.cloudflare_access_audiences.clone(),
            session_ttl_secs: cfg.workforce_session_ttl_secs,
            break_glass_session_ttl_secs: cfg.workforce_break_glass_session_ttl_secs,
        }),
        direct_web_access: if cfg.web_direct_access_allowed_origins.is_empty()
            && cfg.web_direct_access_allowed_client_cidrs.is_empty()
        {
            None
        } else {
            Some(DirectWebAccessConfig {
                allowed_origins: cfg.web_direct_access_allowed_origins.clone(),
                allowed_client_cidrs: cfg.web_direct_access_allowed_client_cidrs.clone(),
                account_id: cfg.web_direct_access_account_id.clone(),
                phone: cfg.web_direct_access_phone.clone(),
                device_id: cfg.web_direct_access_device_id.clone(),
            })
        },
        direct_web_launch: cfg
            .web_direct_launch_signing_secret
            .as_ref()
            .map(|signing_secret| DirectWebLaunchConfig {
                signing_secret: signing_secret.clone(),
                allowed_redirect_origins: cfg.web_direct_launch_allowed_redirect_origins.clone(),
                max_ttl_secs: cfg.web_direct_launch_max_ttl_secs,
            }),
        geo_lookup_base_url: DEFAULT_GEO_LOOKUP_BASE_URL.to_string(),
        http,
        auth,
        wallet_resolution_cache: Arc::new(RwLock::new(HashMap::new())),
        geo_lookup_cache: Arc::new(RwLock::new(HashMap::new())),
        account_roles_cache: Arc::new(RwLock::new(HashMap::new())),
    };

    let mut internal_security_alerts =
        InternalAuthLayer::new(cfg.require_internal_secret, cfg.internal_secret.clone())
            .with_allowed_callers(cfg.security_alert_allowed_callers.clone())
            .with_expected_audience("bff");
    if let Some(verifier) = security_alert_identity_verifier.clone() {
        internal_security_alerts = internal_security_alerts
            .with_identity_verifier(verifier)
            .with_require_identity_v2(cfg.security_alert_require_internal_identity_v2)
            .with_legacy_secret_fallback(cfg.security_alert_allow_legacy_internal_secret_fallback);
    }

    let internal_security = Router::new()
        .route(
            "/internal/security/alerts",
            post(handlers::security_alert_ingest),
        )
        .layer(internal_security_alerts);

    let internal_access_assignments = if cfg.access_assignment_allowed_callers.is_empty() {
        Router::new()
    } else {
        let mut internal_access_auth =
            InternalAuthLayer::new(cfg.require_internal_secret, cfg.internal_secret.clone())
                .with_allowed_callers(cfg.access_assignment_allowed_callers.clone())
                .with_expected_audience("bff");
        if let Some(verifier) = access_assignment_identity_verifier {
            internal_access_auth = internal_access_auth
                .with_identity_verifier(verifier)
                .with_require_identity_v2(cfg.access_assignment_require_internal_identity_v2)
                .with_legacy_secret_fallback(
                    cfg.access_assignment_allow_legacy_internal_secret_fallback,
                );
        }
        Router::new()
            .route(
                "/internal/admin/access/assignments",
                get(auth::internal_admin_access_assignments_list)
                    .post(auth::internal_admin_access_assignments_add)
                    .delete(auth::internal_admin_access_assignments_remove),
            )
            .layer(internal_access_auth)
    };

    let payments_routes = Router::new()
        .route("/payments/users", post(handlers::payments_create_user))
        .route(
            "/payments/wallets/:wallet_id",
            get(handlers::payments_wallet),
        )
        .route(
            "/payments/wallets/:wallet_id/buckets",
            get(handlers::payments_wallet_buckets),
        )
        .route(
            "/payments/wallets/:wallet_id/driver-ledger",
            get(handlers::payments_wallet_driver_ledger),
        )
        .route(
            "/payments/wallets/:wallet_id/snapshot",
            get(handlers::payments_wallet_snapshot),
        )
        .route(
            "/payments/wallets/:wallet_id/statement",
            get(handlers::payments_wallet_statement),
        )
        .route(
            "/payments/wallets/:wallet_id/limits",
            get(handlers::payments_wallet_limits),
        )
        .route(
            "/payments/wallets/:wallet_id/holds",
            get(handlers::payments_wallet_holds_list).post(handlers::payments_wallet_holds_create),
        )
        .route(
            "/payments/holds/:hold_id/resolve",
            post(handlers::payments_wallet_holds_resolve),
        )
        .route("/payments/transfer", post(handlers::payments_transfer))
        .route(
            "/payments/wallets/:wallet_id/topup",
            post(handlers::payments_topup),
        )
        .route(
            "/payments/admin/credits",
            get(handlers::payments_admin_credits_list).post(handlers::payments_admin_credit),
        )
        .route(
            "/payments/admin/credits/metrics",
            get(handlers::payments_admin_credit_metrics),
        )
        .route(
            "/payments/admin/risk/metrics",
            get(handlers::payments_admin_risk_metrics),
        )
        .route(
            "/payments/admin/wallet-controls",
            post(handlers::payments_admin_wallet_control),
        )
        .route("/payments/admin/kyc", post(handlers::payments_admin_kyc))
        .route(
            "/payments/admin/credits/reconciliation",
            get(handlers::payments_admin_credit_reconciliation),
        )
        .route(
            "/payments/admin/credits/:request_id/approve",
            post(handlers::payments_admin_credit_approve),
        )
        .route("/wallets/:wallet_id", get(handlers::payments_wallet))
        .route(
            "/wallets/:wallet_id/buckets",
            get(handlers::payments_wallet_buckets),
        )
        .route(
            "/wallets/:wallet_id/driver-ledger",
            get(handlers::payments_wallet_driver_ledger),
        )
        .route(
            "/wallets/:wallet_id/snapshot",
            get(handlers::payments_wallet_snapshot),
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
        )
        .route(
            "/payments/exchange/quotes",
            get(handlers::payments_exchange_quotes_list)
                .post(handlers::payments_exchange_quotes_create),
        )
        .route(
            "/payments/exchange/quotes/:quote_id/execute",
            post(handlers::payments_exchange_quotes_execute),
        )
        .route(
            "/payments/payment-links",
            get(handlers::payments_payment_links_list)
                .post(handlers::payments_payment_links_create),
        )
        .route(
            "/payments/payment-links/:link_id",
            get(handlers::payments_payment_link_get),
        )
        .route(
            "/payments/payment-links/:link_id/pay",
            post(handlers::payments_payment_link_pay),
        )
        .route(
            "/payments/refunds",
            get(handlers::payments_refunds_list).post(handlers::payments_refunds_create),
        )
        .route(
            "/payments/refunds/:refund_id/resolve",
            post(handlers::payments_refunds_resolve),
        )
        .route(
            "/payments/recurring",
            get(handlers::payments_recurring_list).post(handlers::payments_recurring_create),
        )
        .route(
            "/payments/recurring/:recurring_id/cancel",
            post(handlers::payments_recurring_cancel),
        )
        .route(
            "/payments/merchant/profile",
            get(handlers::payments_merchant_profile_get)
                .post(handlers::payments_merchant_profile_upsert),
        )
        .route(
            "/payments/mini/payment-intents",
            post(handlers::payments_mini_payment_intents_create),
        )
        .route(
            "/payments/mini/payment-intents/:intent_id",
            get(handlers::payments_mini_payment_intents_get),
        )
        .route(
            "/payments/mini/payment-intents/:intent_id/confirm",
            post(handlers::payments_mini_payment_intents_confirm),
        )
        .route(
            "/payments/merchant/webhooks",
            get(handlers::payments_merchant_webhooks_list)
                .post(handlers::payments_merchant_webhooks_create),
        )
        .route(
            "/payments/merchant/settlements",
            get(handlers::payments_merchant_settlements_list)
                .post(handlers::payments_merchant_settlements_create),
        )
        .route(
            "/payments/admin/settlements/:settlement_id/resolve",
            post(handlers::payments_admin_settlement_resolve),
        )
        .route(
            "/payments/disputes",
            get(handlers::payments_disputes_list).post(handlers::payments_disputes_create),
        )
        .route(
            "/payments/aliases",
            get(handlers::payments_aliases_list).post(handlers::payments_aliases_upsert),
        )
        .route(
            "/payments/kyc/documents",
            get(handlers::payments_kyc_documents_list)
                .post(handlers::payments_kyc_documents_create),
        )
        .route("/payments/fx/rates", get(handlers::payments_fx_rates_list))
        .route(
            "/payments/offline-payments",
            get(handlers::payments_offline_list).post(handlers::payments_offline_submit),
        )
        .route("/payments/events", get(handlers::payments_events_list))
        .route(
            "/payments/admin/fx/rates",
            post(handlers::payments_admin_fx_rate_upsert),
        )
        .route(
            "/payments/admin/reconciliation",
            get(handlers::payments_admin_reconciliation),
        )
        .route(
            "/payments/admin/risk/rules",
            get(handlers::payments_admin_risk_rules_list)
                .post(handlers::payments_admin_risk_rules_create),
        )
        .route(
            "/payments/admin/risk/evaluate",
            post(handlers::payments_admin_risk_evaluate),
        )
        .route(
            "/payments/admin/audit/timeline",
            get(handlers::payments_admin_audit_timeline),
        )
        .route(
            "/payments/admin/recurring/run",
            post(handlers::payments_admin_recurring_run),
        )
        .route(
            "/me/rides/trips",
            get(handlers::rides_trips_list).post(handlers::rides_trip_create),
        )
        .route("/me/rides/trips/active", get(handlers::rides_trip_active))
        .route(
            "/me/rides/trips/active/stream",
            get(handlers::rides_trip_active_stream),
        )
        .route("/me/rides/trips/:ride_id", get(handlers::rides_trip_get))
        .route(
            "/me/rides/trips/:ride_id/enter_matching",
            post(handlers::rides_trip_enter_matching),
        )
        .route(
            "/me/rides/trips/:ride_id/live",
            get(handlers::rides_trip_live_get),
        )
        .route(
            "/me/rides/support_tickets",
            get(handlers::rides_support_tickets_list).post(handlers::rides_support_ticket_create),
        )
        .route(
            "/me/rides/trips/:ride_id/tracking",
            get(handlers::rides_trip_tracking_get),
        )
        .route(
            "/me/rides/trips/:ride_id/commands",
            post(handlers::rides_trip_command),
        )
        .route("/me/rides/driver/queue", get(handlers::rides_driver_queue))
        .route(
            "/me/rides/driver/stream",
            get(handlers::rides_driver_stream),
        )
        .route(
            "/me/rides/driver/dispatch_offers",
            get(handlers::rides_driver_queue),
        )
        .route(
            "/me/rides/driver/dispatch_offers/:offer_id/accept",
            post(handlers::rides_driver_dispatch_offer_accept),
        )
        .route(
            "/me/rides/driver/dispatch_offers/:offer_id/reject",
            post(handlers::rides_driver_dispatch_offer_reject),
        )
        .route(
            "/me/rides/driver/presence",
            get(handlers::rides_driver_presence_get).post(handlers::rides_driver_presence_upsert),
        )
        .route(
            "/me/rides/driver/trips/active",
            get(handlers::rides_driver_trip_active),
        )
        .route(
            "/me/rides/driver/finance_dashboard",
            get(handlers::rides_driver_finance_dashboard),
        )
        .route(
            "/me/rides/driver/shift_summary",
            get(handlers::rides_driver_shift_summary),
        )
        .route(
            "/me/rides/driver/documents",
            get(handlers::rides_driver_documents).post(handlers::rides_driver_document_upsert),
        )
        .route(
            "/me/rides/driver/payout_requests",
            post(handlers::rides_driver_payout_request_create),
        )
        .route(
            "/me/rides/operator/live_board",
            get(handlers::rides_operator_live_board),
        )
        .route(
            "/me/rides/operator/stream",
            get(handlers::rides_operator_stream),
        )
        .route(
            "/me/rides/operator/driver_roster",
            get(handlers::rides_operator_driver_roster),
        )
        .route(
            "/me/rides/operator/fleet/live",
            get(handlers::rides_operator_fleet_live),
        )
        .route(
            "/me/rides/operator/pricing_policy",
            get(handlers::rides_operator_pricing_policy)
                .post(handlers::rides_operator_pricing_policy_upsert),
        )
        .route(
            "/me/rides/operator/case_queue",
            get(handlers::rides_operator_case_queue),
        )
        .route(
            "/me/rides/operator/support_queue",
            get(handlers::rides_operator_support_queue),
        )
        .route(
            "/me/rides/operator/document_queue",
            get(handlers::rides_operator_document_queue),
        )
        .route(
            "/me/rides/operator/finance_queue",
            get(handlers::rides_operator_finance_queue),
        )
        .route(
            "/me/rides/operator/trips/:ride_id/commands",
            post(handlers::rides_operator_trip_command),
        )
        .route(
            "/me/rides/operator/documents/:document_id/review",
            post(handlers::rides_operator_document_review),
        )
        .route(
            "/me/rides/operator/support_tickets/:ticket_id/resolve",
            post(handlers::rides_operator_support_ticket_resolve),
        )
        .route(
            "/me/rides/operator/payout_requests/:rid/approve",
            post(handlers::rides_operator_payout_request_approve),
        )
        .route(
            "/me/rides/pricing_preview",
            get(handlers::rides_pricing_preview),
        )
        .route(
            "/me/rides/driver/trips/:ride_id/accept",
            post(handlers::rides_driver_trip_accept),
        )
        .route(
            "/me/rides/driver/trips/:ride_id/status",
            post(handlers::rides_driver_trip_status),
        )
        .route(
            "/me/rides/driver/trips/:ride_id/location_ping",
            post(handlers::rides_driver_location_ping),
        )
        .route(
            "/me/rides/driver/trips/:ride_id/commands",
            post(handlers::rides_driver_trip_command),
        );

    let contacts_routes = contacts_routes();

    let chat_routes = Router::new()
        .route("/chat/devices/register", post(handlers::chat_register))
        .route("/chat/devices/:device_id", get(handlers::chat_get_device))
        .route("/chat/keys/bootstrap", post(handlers::chat_keys_bootstrap))
        .route("/chat/keys/register", post(handlers::chat_keys_register))
        .route(
            "/chat/keys/prekeys/status/:device_id",
            get(handlers::chat_get_prekey_status),
        )
        .route(
            "/chat/keys/prekeys/upload",
            post(handlers::chat_prekeys_upload),
        )
        .route(
            "/chat/keys/bundle/:device_id",
            get(handlers::chat_get_key_bundle),
        )
        .route(
            "/chat/devices/:device_id/push_token",
            post(handlers::chat_push_token).delete(handlers::chat_delete_push_token),
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
        .route("/chat/messages/thread", get(handlers::chat_thread))
        .route("/chat/messages/stream", get(handlers::chat_stream))
        .route("/chat/events", get(handlers::chat_events))
        .route("/chat/events/stream", get(handlers::chat_events_stream))
        .route("/chat/messages/pins", get(handlers::chat_list_message_pins))
        .route(
            "/chat/messages/:mid/reactions",
            get(handlers::chat_list_message_reactions).post(handlers::chat_set_message_reaction),
        )
        .route(
            "/chat/messages/:mid/edit",
            post(handlers::chat_edit_message),
        )
        .route(
            "/chat/messages/:mid/delete",
            post(handlers::chat_delete_message),
        )
        .route(
            "/chat/messages/:mid/pin",
            post(handlers::chat_set_message_pin),
        )
        .route(
            "/chat/messages/:mid/report",
            post(handlers::chat_report_message),
        )
        .route("/chat/messages/:mid/read", post(handlers::chat_mark_read))
        .route(
            "/chat/voice/transcripts",
            get(handlers::chat_get_voice_transcript).post(handlers::chat_save_voice_transcript),
        )
        .route(
            "/chat/voice/transcript_jobs",
            get(handlers::chat_list_voice_transcript_jobs)
                .post(handlers::chat_request_voice_transcript_job),
        )
        .route(
            "/chat/voice/transcript_jobs/:job_id/complete",
            post(handlers::chat_complete_voice_transcript_job),
        )
        .route(
            "/chat/calls/logs",
            get(handlers::chat_list_call_logs).post(handlers::chat_save_call_log),
        )
        .route("/ws/chat/inbox", get(handlers::ws_chat_inbox))
        .route("/ws/chat/groups", get(handlers::ws_chat_groups))
        .route("/ws/chat/typing", get(handlers::ws_chat_typing))
        .route("/ws/call/signaling", get(handlers::ws_call_signaling))
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

    let admin_only = Router::new()
        .route(
            "/admin/roles",
            get(handlers::admin_roles_list)
                .post(handlers::admin_roles_add)
                .delete(handlers::admin_roles_remove),
        )
        .route("/admin/roles/check", get(handlers::admin_roles_check))
        .route(
            "/admin/chat/moderation/reports",
            get(handlers::chat_admin_moderation_reports),
        )
        .route(
            "/admin/chat/moderation/reports/:report_id/action",
            post(handlers::chat_admin_moderation_action),
        );

    let session_routes = Router::new()
        .route("/auth/devices/register", post(auth::auth_devices_register))
        .route("/auth/devices", get(auth::auth_devices_list))
        .route(
            "/auth/devices/:device_id",
            delete(auth::auth_devices_delete),
        )
        .route(
            "/admin/access/assignments",
            get(auth::admin_access_assignments_list)
                .post(auth::admin_access_assignments_add)
                .delete(auth::admin_access_assignments_remove),
        )
        .route("/official_accounts", get(auth::official_accounts_list))
        .route(
            "/official_accounts/notifications",
            get(auth::official_accounts_notifications),
        )
        .route(
            "/official_accounts/:account_id/auto_replies",
            get(auth::official_account_auto_replies),
        )
        .route(
            "/official_accounts/:account_id/follow",
            post(auth::official_accounts_follow),
        )
        .route(
            "/official_accounts/:account_id/unfollow",
            post(auth::official_accounts_unfollow),
        )
        .route(
            "/official_accounts/:account_id/notification_mode",
            post(auth::official_accounts_set_notification_mode),
        )
        .route(
            "/admin/official_accounts/:account_id/auto_replies",
            get(auth::admin_official_account_auto_replies_list)
                .post(auth::admin_official_account_auto_replies_create),
        )
        .route(
            "/admin/official_accounts/:account_id/moments_stats",
            get(auth::official_account_moments_stats),
        )
        .route(
            "/admin/official_accounts/:account_id",
            patch(auth::admin_official_account_patch),
        )
        .route(
            "/admin/official_accounts/:account_id/owners",
            get(auth::admin_official_account_owners_list)
                .post(auth::admin_official_account_owners_add)
                .delete(auth::admin_official_account_owners_remove),
        )
        .route(
            "/admin/official_auto_replies/:rule_id",
            patch(auth::admin_official_auto_reply_patch),
        )
        .route(
            "/admin/official_feeds",
            get(auth::admin_official_feeds_list).post(auth::admin_official_feeds_create),
        )
        .route(
            "/admin/official_accounts/:account_id/service_inbox",
            get(auth::admin_official_service_inbox_list),
        )
        .route(
            "/admin/official_accounts/:account_id/service_inbox/:session_id/mark_read",
            post(auth::admin_official_service_inbox_mark_read),
        )
        .route(
            "/admin/official_accounts/:account_id/service_inbox/:session_id/close",
            post(auth::admin_official_service_inbox_close),
        )
        .route(
            "/admin/official_accounts/:account_id/service_inbox/:session_id/template_messages",
            post(auth::admin_official_service_inbox_send_template_message),
        )
        .route("/me/roles", get(auth::me_roles))
        .route("/me/access-context", get(auth::me_access_context))
        .route("/me/permissions", get(auth::me_permissions))
        .route("/me/home_snapshot", get(auth::me_home_snapshot))
        .route("/me/activity", post(auth::me_activity_record))
        .route(
            "/me/platform/features/events",
            post(auth::me_platform_feature_event_record),
        )
        .route("/admin/user-activity", get(auth::admin_user_activity))
        .route(
            "/admin/platform/features/summary",
            get(auth::admin_platform_feature_summary),
        )
        .route("/me/geo/reverse", get(handlers::moments_geo_reverse))
        .route("/me/geo/search", get(handlers::moments_geo_search))
        .route("/me/coach/bootstrap", get(handlers::coach_bootstrap))
        .route("/me/coach/search", get(handlers::coach_search))
        .route("/me/coach/offers/:offer_id", get(handlers::coach_offer_get))
        .route("/me/coach/holds", post(handlers::coach_hold_create))
        .route("/me/coach/holds/:hold_id", get(handlers::coach_hold_get))
        .route(
            "/me/coach/journeys/:journey_id/live",
            get(handlers::coach_journey_live_get),
        )
        .route(
            "/me/coach/bookings",
            get(handlers::coach_booking_list).post(handlers::coach_booking_create),
        )
        .route(
            "/me/coach/bookings/:booking_id",
            get(handlers::coach_booking_get),
        )
        .route(
            "/me/coach/bookings/:booking_id/refund_eligibility",
            get(handlers::coach_refund_eligibility_get),
        )
        .route(
            "/me/coach/bookings/:booking_id/change_options",
            get(handlers::coach_change_options_get),
        )
        .route(
            "/me/coach/bookings/:booking_id/tickets",
            post(handlers::coach_ticket_issue),
        )
        .route(
            "/me/coach/bookings/:booking_id/refunds",
            post(handlers::coach_refund_request),
        )
        .route(
            "/me/coach/bookings/:booking_id/rebook_requests",
            post(handlers::coach_rebook_request),
        )
        .route(
            "/me/coach/bookings/:booking_id/reissue",
            post(handlers::coach_self_service_reissue),
        )
        .route(
            "/me/coach/bookings/:booking_id/reissue/resolve_payment_failure",
            post(handlers::coach_resolve_reissue_payment_failure),
        )
        .route(
            "/me/coach/tickets/:ticket_id",
            get(handlers::coach_ticket_get),
        )
        .route(
            "/me/coach/admin/overview",
            get(handlers::coach_admin_overview),
        )
        .route(
            "/me/coach/admin/risk/dashboard",
            get(handlers::coach_admin_risk_dashboard),
        )
        .route(
            "/me/coach/admin/risk/:risk_id/action",
            post(handlers::coach_admin_risk_action),
        )
        .route(
            "/me/coach/admin/partners/onboarding",
            get(handlers::coach_admin_partner_onboarding),
        )
        .route(
            "/me/coach/admin/partners/:operator_id/onboarding_action",
            post(handlers::coach_admin_partner_onboarding_action),
        )
        .route(
            "/me/coach/admin/disruptions",
            get(handlers::coach_admin_disruptions),
        )
        .route(
            "/me/coach/admin/disruptions/:trip_id/action",
            post(handlers::coach_admin_disruption_action),
        )
        .route(
            "/me/coach/admin/finance/journal",
            get(handlers::coach_admin_finance_journal),
        )
        .route(
            "/me/coach/admin/finance/shamell_pay_reconciliation",
            get(handlers::coach_admin_shamell_pay_reconciliation),
        )
        .route(
            "/me/coach/admin/finance/shamell_pay_reconciliation/:payout_run_id/release_operator_rail",
            post(handlers::coach_admin_shamell_pay_release_operator_rail),
        )
        .route(
            "/me/coach/admin/finance/shamell_pay_reconciliation/:payout_run_id/confirm_operator_rail",
            post(handlers::coach_admin_shamell_pay_confirm_operator_rail),
        )
        .route(
            "/me/coach/admin/finance/shamell_pay_reconciliation/:payout_run_id/fail_operator_rail",
            post(handlers::coach_admin_shamell_pay_fail_operator_rail),
        )
        .route(
            "/me/coach/admin/finance/shamell_pay_reports",
            post(handlers::coach_admin_shamell_pay_report_import_create),
        )
        .route(
            "/me/coach/admin/support/cases",
            get(handlers::coach_admin_support_cases),
        )
        .route(
            "/me/coach/admin/support/cases/:case_id",
            get(handlers::coach_admin_support_case_get),
        )
        .route(
            "/me/coach/admin/support/cases/:case_id/resolve_payment_failure",
            post(handlers::coach_admin_support_case_resolve_payment_failure),
        )
        .route(
            "/me/coach/operator/refund_queue",
            get(handlers::coach_operator_refund_queue),
        )
        .route(
            "/me/coach/operator/change_queue",
            get(handlers::coach_operator_change_queue),
        )
        .route(
            "/me/coach/operator/reconciliation",
            get(handlers::coach_operator_reconciliation),
        )
        .route(
            "/me/coach/operator/settlement_statements",
            get(handlers::coach_operator_settlement_statements),
        )
        .route(
            "/me/coach/operator/payout_runs",
            get(handlers::coach_operator_payout_runs)
                .post(handlers::coach_operator_payout_run_create),
        )
        .route(
            "/me/coach/operator/payout_reconciliation",
            get(handlers::coach_operator_payout_reconciliation),
        )
        .route(
            "/me/coach/operator/payout_imports",
            get(handlers::coach_operator_payout_imports),
        )
        .route(
            "/me/coach/operator/catalog_import_runs",
            get(handlers::coach_operator_catalog_import_runs)
                .post(handlers::coach_operator_catalog_import_run_trigger),
        )
        .route(
            "/me/coach/operator/catalog_import_run_saved_views",
            get(handlers::coach_operator_catalog_import_run_saved_views)
                .post(handlers::coach_operator_catalog_import_run_saved_view_upsert),
        )
        .route(
            "/me/coach/operator/catalog_import_run_saved_views/:view_id/delete",
            post(handlers::coach_operator_catalog_import_run_saved_view_delete),
        )
        .route(
            "/me/coach/operator/catalog_import_run_saved_views/:view_id/favorite",
            post(handlers::coach_operator_catalog_import_run_saved_view_favorite_toggle),
        )
        .route(
            "/me/coach/operator/catalog_import_run_saved_views/:view_id/use",
            post(handlers::coach_operator_catalog_import_run_saved_view_use),
        )
        .route(
            "/me/coach/operator/catalog_import_run_issue_saved_views",
            get(handlers::coach_operator_catalog_import_run_issue_saved_views)
                .post(handlers::coach_operator_catalog_import_run_issue_saved_view_upsert),
        )
        .route(
            "/me/coach/operator/catalog_import_run_issue_saved_views/:view_id/delete",
            post(handlers::coach_operator_catalog_import_run_issue_saved_view_delete),
        )
        .route(
            "/me/coach/operator/catalog_import_run_issue_saved_views/:view_id/favorite",
            post(handlers::coach_operator_catalog_import_run_issue_saved_view_favorite_toggle),
        )
        .route(
            "/me/coach/operator/catalog_import_run_issue_saved_views/:view_id/use",
            post(handlers::coach_operator_catalog_import_run_issue_saved_view_use),
        )
        .route(
            "/me/coach/operator/catalog_import_runs/:import_run_id",
            get(handlers::coach_operator_catalog_import_run_get),
        )
        .route(
            "/me/coach/operator/catalog_import_runs/:import_run_id/replays",
            get(handlers::coach_operator_catalog_import_run_replays),
        )
        .route(
            "/me/coach/operator/catalog_source_artifacts",
            get(handlers::coach_operator_catalog_source_artifacts),
        )
        .route(
            "/me/coach/operator/catalog_source_artifacts/:artifact_id",
            get(handlers::coach_operator_catalog_source_artifact_get),
        )
        .route(
            "/me/coach/operator/catalog_import_sources",
            get(handlers::coach_operator_catalog_import_sources),
        )
        .route(
            "/me/coach/operator/catalog_import_sources/upload",
            post(handlers::coach_operator_catalog_import_source_upload),
        )
        .route(
            "/me/coach/operator/catalog_import_config",
            get(handlers::coach_operator_catalog_import_config)
                .post(handlers::coach_operator_catalog_import_config_update),
        )
        .route(
            "/me/coach/operator/feed_health",
            get(handlers::coach_operator_feed_health),
        )
        .route(
            "/me/coach/operator/payout_import_profiles",
            get(handlers::coach_operator_payout_import_profiles),
        )
        .route(
            "/me/coach/operator/payout_import_previews",
            get(handlers::coach_operator_payout_import_previews),
        )
        .route(
            "/me/coach/operator/payout_import_preview_saved_views",
            get(handlers::coach_operator_payout_import_preview_saved_views)
                .post(handlers::coach_operator_payout_import_preview_saved_view_upsert),
        )
        .route(
            "/me/coach/operator/payout_import_preview_saved_views/:view_id/delete",
            post(handlers::coach_operator_payout_import_preview_saved_view_delete),
        )
        .route(
            "/me/coach/operator/payout_import_preview_saved_views/:view_id/favorite",
            post(handlers::coach_operator_payout_import_preview_saved_view_favorite_toggle),
        )
        .route(
            "/me/coach/operator/payout_import_preview_saved_views/:view_id/use",
            post(handlers::coach_operator_payout_import_preview_saved_view_use),
        )
        .route(
            "/me/coach/operator/payout_import_previews/:preview_token/invalidate",
            post(handlers::coach_operator_payout_import_preview_invalidate),
        )
        .route(
            "/me/coach/operator/payout_import_batches",
            get(handlers::coach_operator_payout_import_batches)
                .post(handlers::coach_operator_payout_import_batch_create),
        )
        .route(
            "/me/coach/operator/payout_import_batch_saved_views",
            get(handlers::coach_operator_payout_import_batch_saved_views)
                .post(handlers::coach_operator_payout_import_batch_saved_view_upsert),
        )
        .route(
            "/me/coach/operator/payout_import_batch_saved_views/:view_id/delete",
            post(handlers::coach_operator_payout_import_batch_saved_view_delete),
        )
        .route(
            "/me/coach/operator/payout_import_batch_saved_views/:view_id/favorite",
            post(handlers::coach_operator_payout_import_batch_saved_view_favorite_toggle),
        )
        .route(
            "/me/coach/operator/payout_import_batch_saved_views/:view_id/use",
            post(handlers::coach_operator_payout_import_batch_saved_view_use),
        )
        .route(
            "/me/coach/operator/payout_import_batches/upload",
            post(handlers::coach_operator_payout_import_batch_upload),
        )
        .route(
            "/downloads/coach/payout_import_reports/:artifact_name",
            get(handlers::coach_operator_payout_import_report_download),
        )
        .route(
            "/me/coach/operator/payout_runs/:payout_run_id/mark_paid",
            post(handlers::coach_operator_payout_run_mark_paid),
        )
        .route(
            "/me/coach/operator/payout_runs/:payout_run_id/imports",
            post(handlers::coach_operator_payout_run_import_create),
        )
        .route(
            "/me/coach/operator/payout_runs/:payout_run_id/exports",
            post(handlers::coach_operator_payout_run_export_create),
        )
        .route(
            "/downloads/coach/settlement_exports/:artifact_name",
            get(handlers::coach_operator_settlement_export_download),
        )
        .route(
            "/me/coach/operator/refund_requests/:refund_request_id/review",
            post(handlers::coach_operator_refund_request_review),
        )
        .route(
            "/me/coach/operator/change_requests/:change_request_id/review",
            post(handlers::coach_operator_change_request_review),
        )
        .route(
            "/me/coach/crew/departures",
            get(handlers::coach_crew_departures),
        )
        .route(
            "/me/coach/crew/trips/:trip_id/manifest",
            get(handlers::coach_crew_manifest_get),
        )
        .route(
            "/me/coach/crew/trips/:trip_id/boardings",
            post(handlers::coach_crew_boarding_record),
        )
        .route("/me/rides/search", get(handlers::rides_search))
        .route("/me/rides/bootstrap", get(handlers::rides_bootstrap))
        .route(
            "/me/rides/map_tiles/:z/:x/:y",
            get(handlers::rides_map_tile),
        )
        .route("/me/rides/route", get(handlers::rides_route))
        .route("/me/rides/traffic", get(handlers::rides_traffic))
        .route(
            "/me/official_template_messages",
            get(auth::me_official_template_messages),
        )
        .route(
            "/me/official_template_messages/:mid/read",
            post(auth::me_official_template_messages_mark_read),
        );

    let authed = Router::new()
        .merge(session_routes.layer(cors_layer_for_headers(
            &cfg.allowed_origins,
            bff_session_cors_allowed_headers(),
        )))
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
        .merge(
            admin_only
                .layer(middleware::from_fn_with_state(
                    state.clone(),
                    authz::require_admin,
                ))
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
            post(auth::auth_password_only_required),
        )
        .route(
            "/auth/payment_attestation/challenge",
            post(auth::auth_payment_attestation_challenge),
        )
        .route(
            "/auth/biometric/enroll/challenge",
            post(auth::auth_password_only_required),
        )
        .route(
            "/auth/biometric/login/challenge",
            post(auth::auth_password_only_required),
        )
        .route(
            "/auth/workforce/session/exchange",
            post(auth::auth_workforce_session_exchange),
        )
        .route("/auth/direct-web/launch", get(auth::auth_direct_web_launch))
        .route("/auth/signup", post(auth::auth_username_password_signup))
        .route("/auth/login", post(auth::auth_username_password_login))
        .route(
            "/auth/account/create",
            post(auth::auth_password_only_required),
        )
        .route(
            "/auth/biometric/enroll",
            post(auth::auth_password_only_required),
        )
        .route(
            "/auth/biometric/login",
            post(auth::auth_password_only_required),
        )
        .route("/auth/logout", post(auth::auth_logout))
        .route("/qr.svg", post(auth::qr_svg))
        .route(
            "/auth/device_login/start",
            post(auth::auth_password_only_required),
        )
        .route(
            "/auth/device_login/approve",
            post(auth::auth_password_only_required),
        )
        .route(
            "/auth/device_login/redeem",
            post(auth::auth_password_only_required),
        )
        .route(
            "/auth/device_login/qr.svg",
            post(auth::auth_password_only_required),
        )
        .route(
            "/auth/control_bootstrap",
            get(auth::auth_control_web_bootstrap),
        );

    let public_auth = if cfg.auth_device_login_web_enabled {
        public_auth
            .route("/auth/device_login", get(auth::auth_password_only_required))
            .route(
                "/auth/device_login_demo",
                get(auth::auth_password_only_required),
            )
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
    let trusted_proxy_state = TrustedProxyState {
        trusted_proxy_cidrs: cfg.trusted_proxy_cidrs.clone(),
    };

    let app = Router::new()
        .route("/health", get(handlers::health))
        .merge(public_auth)
        .merge(internal_security)
        .merge(internal_access_assignments)
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
        // Avoid logging sensitive identifiers in raw fallback paths. Keep matched route
        // templates for observability and hash unmatched paths instead.
        .layer(TraceLayer::new_for_http().make_span_with(http_request_span))
        .layer(RequestIdLayer::new(HeaderName::from_static("x-request-id")))
        .layer(middleware::from_fn_with_state(
            trusted_proxy_state,
            trusted_client_ip_middleware,
        ));

    let addr: SocketAddr = format!("{}:{}", cfg.host, cfg.port)
        .parse()
        .unwrap_or_else(|_| SocketAddr::from(([0, 0, 0, 0], cfg.port)));
    tracing::info!(%addr, "starting shamell_bff_gateway");

    let listener = match tokio::net::TcpListener::bind(addr).await {
        Ok(listener) => listener,
        Err(e) => {
            tracing::error!(error = %e, %addr, "listener bind failed");
            std::process::exit(2);
        }
    };
    if let Err(e) = axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
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

fn bff_public_cors_allowed_headers() -> Vec<HeaderName> {
    vec![
        header::ACCEPT,
        header::CONTENT_TYPE,
        HeaderName::from_static("x-request-id"),
    ]
}

fn bff_session_cors_allowed_headers() -> Vec<HeaderName> {
    let mut headers = bff_public_cors_allowed_headers();
    headers.extend([
        HeaderName::from_static("idempotency-key"),
        HeaderName::from_static("x-shamell-app-surface"),
    ]);
    headers
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
        HeaderName::from_static("x-shamell-payment-attestation-challenge"),
        HeaderName::from_static("x-shamell-payment-play-integrity"),
        HeaderName::from_static("x-shamell-payment-apple-devicecheck"),
    ]);
    headers
}

fn cors_layer_for_headers(
    allowed_origins: &[String],
    allowed_headers: Vec<HeaderName>,
) -> CorsLayer {
    if allowed_origins.iter().any(|o| o == "*") {
        CorsLayer::new()
            .allow_origin(Any)
            .allow_methods([
                Method::GET,
                Method::POST,
                Method::PATCH,
                Method::DELETE,
                Method::OPTIONS,
            ])
            .allow_headers(allowed_headers)
            .allow_credentials(false)
    } else {
        let origins: Vec<axum::http::HeaderValue> = allowed_origins
            .iter()
            .filter_map(|o| o.parse().ok())
            .collect();
        CorsLayer::new()
            .allow_methods([
                Method::GET,
                Method::POST,
                Method::PATCH,
                Method::DELETE,
                Method::OPTIONS,
            ])
            .allow_headers(allowed_headers)
            .allow_credentials(true)
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

async fn trusted_client_ip_middleware(
    State(proxy): State<TrustedProxyState>,
    mut req: Request,
    next: Next,
) -> Response {
    let peer_ip = req
        .extensions()
        .get::<ConnectInfo<SocketAddr>>()
        .map(|info| info.0.ip());
    let forwarded_for =
        header_text(req.headers(), HeaderName::from_static("x-forwarded-for")).map(str::to_string);

    strip_spoofable_client_ip_headers(req.headers_mut());

    if let Some(peer_ip) = peer_ip {
        let client_ip = derive_client_ip(
            peer_ip,
            forwarded_for.as_deref(),
            &proxy.trusted_proxy_cidrs,
        );
        if let Ok(value) = HeaderValue::from_str(&client_ip.to_string()) {
            req.headers_mut()
                .insert(HeaderName::from_static(TRUSTED_CLIENT_IP_HEADER), value);
            req.headers_mut().insert(
                HeaderName::from_static(TRUSTED_CLIENT_IP_ATTESTED_HEADER),
                HeaderValue::from_static("1"),
            );
        }
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

fn strip_spoofable_client_ip_headers(headers: &mut HeaderMap) {
    for name in [
        "forwarded",
        "x-forwarded-for",
        "x-forwarded-host",
        "x-real-ip",
        TRUSTED_CLIENT_IP_HEADER,
        TRUSTED_CLIENT_IP_ATTESTED_HEADER,
    ] {
        headers.remove(HeaderName::from_static(name));
    }
}

fn derive_client_ip(
    peer_ip: IpAddr,
    forwarded_for: Option<&str>,
    trusted_proxy_cidrs: &[IpNet],
) -> IpAddr {
    if !ip_in_trusted_proxy_cidrs(peer_ip, trusted_proxy_cidrs) {
        return peer_ip;
    }

    let mut hops = parse_forwarded_for_chain(forwarded_for);
    hops.push(peer_ip);

    for ip in hops.iter().rev().copied() {
        if !ip_in_trusted_proxy_cidrs(ip, trusted_proxy_cidrs) {
            return ip;
        }
    }

    peer_ip
}

fn parse_forwarded_for_chain(raw: Option<&str>) -> Vec<IpAddr> {
    raw.unwrap_or("")
        .split(',')
        .filter_map(parse_forwarded_ip_token)
        .collect()
}

fn parse_forwarded_ip_token(raw: &str) -> Option<IpAddr> {
    let token = raw.trim();
    if token.is_empty() {
        return None;
    }
    let token = token
        .strip_prefix("for=")
        .or_else(|| token.strip_prefix("For="))
        .unwrap_or(token)
        .trim()
        .trim_matches('"');

    if let Ok(ip) = token.parse::<IpAddr>() {
        return Some(ip);
    }
    if let Ok(sock) = token.parse::<SocketAddr>() {
        return Some(sock.ip());
    }
    if let Some(host) = token
        .strip_prefix('[')
        .and_then(|rest| rest.split_once(']').map(|(host, _)| host))
    {
        if let Ok(ip) = host.parse::<IpAddr>() {
            return Some(ip);
        }
    }
    None
}

fn ip_in_trusted_proxy_cidrs(ip: IpAddr, trusted_proxy_cidrs: &[IpNet]) -> bool {
    trusted_proxy_cidrs.iter().any(|cidr| cidr.contains(&ip))
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

fn contacts_routes() -> Router<AppState> {
    Router::new()
        .route(
            "/contacts/resolve_by_shamell_id",
            post(handlers::contacts_resolve_by_shamell_id),
        )
        .route("/contacts/invites", post(handlers::contacts_invite_create))
        .route(
            "/contacts/invites/redeem",
            post(handlers::contacts_invite_redeem),
        )
}

#[cfg(test)]
mod router_fallback_tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{header, Method, Request, StatusCode};
    use axum::routing::get;
    use tower::ServiceExt;

    fn test_state() -> AppState {
        AppState {
            env_name: "test".to_string(),
            allowed_origins: vec!["https://online.shamell.online".to_string()],
            payments_base_url: "http://127.0.0.1:1".to_string(),
            payments_internal_secret: None,
            fee_wallet_account_id: None,
            fee_wallet_phone: None,
            chat_base_url: "http://127.0.0.1:1".to_string(),
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
            http: reqwest::Client::builder().build().expect("http client"),
            auth: None,
            wallet_resolution_cache: Arc::new(RwLock::new(HashMap::new())),
            geo_lookup_cache: Arc::new(RwLock::new(HashMap::new())),
            account_roles_cache: Arc::new(RwLock::new(HashMap::new())),
        }
    }

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

    #[tokio::test]
    async fn explicit_origin_cors_reflects_origin_with_credentials() {
        let app = Router::new()
            .route("/me/permissions", get(|| async { "ok" }))
            .layer(cors_layer_for_headers(
                &["https://online.shamell.online".to_string()],
                bff_public_cors_allowed_headers(),
            ))
            .with_state(test_state());

        let resp = app
            .oneshot(
                Request::builder()
                    .method(Method::OPTIONS)
                    .uri("/me/permissions")
                    .header(header::ORIGIN, "https://online.shamell.online")
                    .header(header::ACCESS_CONTROL_REQUEST_METHOD, "GET")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(resp.status(), StatusCode::OK);
        assert_eq!(
            resp.headers()
                .get(header::ACCESS_CONTROL_ALLOW_ORIGIN)
                .and_then(|value| value.to_str().ok()),
            Some("https://online.shamell.online")
        );
        assert_eq!(
            resp.headers()
                .get(header::ACCESS_CONTROL_ALLOW_CREDENTIALS)
                .and_then(|value| value.to_str().ok()),
            Some("true")
        );
    }

    #[tokio::test]
    async fn legacy_contacts_resolve_route_is_not_exposed() {
        let app = Router::new()
            .merge(contacts_routes())
            .with_state(test_state());

        let resp = app
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/contacts/resolve")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn contacts_resolve_by_shamell_id_route_is_exposed() {
        let app = Router::new()
            .merge(contacts_routes())
            .with_state(test_state());

        let resp = app
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/contacts/resolve_by_shamell_id")
                    .header("content-type", "application/json")
                    .body(Body::from("{\"shamell_id\":\"SA123456\"}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_ne!(resp.status(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn legacy_official_feed_route_is_not_exposed() {
        let app = Router::new()
            .route("/official_accounts", get(auth::official_accounts_list))
            .route(
                "/official_accounts/notifications",
                get(auth::official_accounts_notifications),
            )
            .route(
                "/official_accounts/:account_id/auto_replies",
                get(auth::official_account_auto_replies),
            )
            .route(
                "/official_accounts/:account_id/moments_stats",
                get(auth::official_account_moments_stats),
            )
            .with_state(test_state());

        let resp = app
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/official_accounts/shamell_pay/feed")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn legacy_official_moments_stats_route_is_not_exposed() {
        let app = Router::new()
            .route("/official_accounts", get(auth::official_accounts_list))
            .route(
                "/official_accounts/notifications",
                get(auth::official_accounts_notifications),
            )
            .route(
                "/official_accounts/:account_id/auto_replies",
                get(auth::official_account_auto_replies),
            )
            .with_state(test_state());

        let resp = app
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/official_accounts/shamell_pay/moments_stats")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn legacy_me_official_moments_stats_route_is_not_exposed() {
        let app = Router::new()
            .route("/me/roles", get(auth::me_roles))
            .route("/me/access-context", get(auth::me_access_context))
            .route("/me/permissions", get(auth::me_permissions))
            .route("/me/home_snapshot", get(auth::me_home_snapshot))
            .route(
                "/me/official_template_messages",
                get(auth::me_official_template_messages),
            )
            .with_state(test_state());

        let resp = app
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/official_moments_stats")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn me_access_snapshot_routes_are_exposed() {
        let app = Router::new()
            .route("/me/access-context", get(auth::me_access_context))
            .route("/me/permissions", get(auth::me_permissions))
            .with_state(test_state());

        let access_context_resp = app
            .clone()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/access-context")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(
            access_context_resp.status(),
            StatusCode::SERVICE_UNAVAILABLE
        );

        let permissions_resp = app
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/permissions")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(permissions_resp.status(), StatusCode::SERVICE_UNAVAILABLE);
    }

    #[tokio::test]
    async fn workforce_exchange_and_access_assignment_routes_are_exposed() {
        let signer = InternalRequestSigner::from_seed_bytes("iam-sync", [7u8; 32]).expect("signer");
        let verifier = InternalIdentityVerifier::from_public_keys_base64(
            vec![("iam-sync".to_string(), signer.public_key_base64())],
            30,
        )
        .expect("verifier");
        let internal_app = Router::new()
            .route(
                "/internal/admin/access/assignments",
                get(auth::internal_admin_access_assignments_list)
                    .post(auth::internal_admin_access_assignments_add)
                    .delete(auth::internal_admin_access_assignments_remove),
            )
            .layer(
                InternalAuthLayer::new(true, None)
                    .with_allowed_callers(vec!["iam-sync".to_string()])
                    .with_expected_audience("bff")
                    .with_identity_verifier(verifier)
                    .with_legacy_secret_fallback(false),
            );
        let app = Router::new()
            .route(
                "/auth/workforce/session/exchange",
                post(auth::auth_workforce_session_exchange),
            )
            .route(
                "/admin/access/assignments",
                get(auth::admin_access_assignments_list)
                    .post(auth::admin_access_assignments_add)
                    .delete(auth::admin_access_assignments_remove),
            )
            .merge(internal_app)
            .with_state(test_state());

        let exchange_resp = app
            .clone()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/auth/workforce/session/exchange")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(r#"{"jwt_assertion":"token"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(exchange_resp.status(), StatusCode::SERVICE_UNAVAILABLE);

        let direct_launch_resp = app
            .clone()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/auth/direct-web/launch?token=test")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(direct_launch_resp.status(), StatusCode::UNAUTHORIZED);

        let assignments_resp = app
            .clone()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/admin/access/assignments")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(assignments_resp.status(), StatusCode::UNAUTHORIZED);

        let internal_unauthorized_resp = app
            .clone()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/internal/admin/access/assignments?phone=%2B963944444444")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(
            internal_unauthorized_resp.status(),
            StatusCode::UNAUTHORIZED
        );

        let signed = signer
            .sign(
                &Method::GET,
                "bff",
                "/internal/admin/access/assignments?phone=%2B963944444444",
                b"",
            )
            .expect("signature");
        let internal_authorized_resp = app
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/internal/admin/access/assignments?phone=%2B963944444444")
                    .header(
                        shamell_common::internal_identity::INTERNAL_SERVICE_ID_HEADER,
                        signed.service_id,
                    )
                    .header(
                        shamell_common::internal_identity::INTERNAL_IDENTITY_SIG_HEADER,
                        signed.signature_b64,
                    )
                    .header(
                        shamell_common::internal_identity::INTERNAL_IDENTITY_AUDIENCE_HEADER,
                        signed.audience,
                    )
                    .header(
                        shamell_common::internal_identity::INTERNAL_IDENTITY_TS_HEADER,
                        signed.timestamp.to_string(),
                    )
                    .header(
                        shamell_common::internal_identity::INTERNAL_IDENTITY_NONCE_HEADER,
                        signed.nonce,
                    )
                    .header(
                        shamell_common::internal_identity::INTERNAL_IDENTITY_SIG_V2_HEADER,
                        signed.signature_v2_b64,
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(
            internal_authorized_resp.status(),
            StatusCode::SERVICE_UNAVAILABLE
        );
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
    if scheme == "http" && !matches!(host.as_str(), "localhost" | "127.0.0.1" | "::1") {
        // Fail closed: browser origins for cookie-authenticated flows must be
        // HTTPS except explicit local-dev loopback hosts.
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
            // Fail closed for cookie-authenticated CSRF checks:
            // wildcard CORS is never sufficient proof of same-site intent.
            continue;
        }
        if normalize_origin(allowed).as_deref() == Some(origin) {
            return true;
        }
    }
    false
}

fn parse_host_authority(raw: &str) -> Option<(String, Option<u16>)> {
    let authority = raw.split(',').next()?.trim();
    if authority.is_empty() {
        return None;
    }
    if let Some(host) = authority.strip_prefix('[') {
        let end = host.find(']')?;
        let host_name = host[..end].trim().to_ascii_lowercase();
        if host_name.is_empty() {
            return None;
        }
        let remainder = host[end + 1..].trim();
        let port = if remainder.is_empty() {
            None
        } else {
            remainder
                .strip_prefix(':')
                .and_then(|value| value.parse::<u16>().ok())
        };
        return Some((host_name, port));
    }

    if let Some((host, port_raw)) = authority.rsplit_once(':') {
        if !host.contains(':') {
            let host = host.trim().to_ascii_lowercase();
            if host.is_empty() {
                return None;
            }
            return Some((host, port_raw.trim().parse::<u16>().ok()));
        }
    }

    let host = authority.trim().to_ascii_lowercase();
    if host.is_empty() {
        None
    } else {
        Some((host, None))
    }
}

fn origin_uses_default_port(origin: &reqwest::Url) -> bool {
    match origin.scheme() {
        "http" => origin.port().unwrap_or(80) == 80,
        "https" => origin.port().unwrap_or(443) == 443,
        _ => false,
    }
}

fn origin_matches_host(origin: &str, headers: &HeaderMap) -> bool {
    let origin = match reqwest::Url::parse(origin) {
        Ok(origin) => origin,
        Err(_) => return false,
    };
    let origin_host = origin
        .host_str()
        .map(str::trim)
        .filter(|host| !host.is_empty())
        .map(str::to_ascii_lowercase)
        .unwrap_or_default();
    if origin_host.is_empty() {
        return false;
    }
    let host_raw = header_text(headers, header::HOST).unwrap_or("");
    let Some((host, host_port)) = parse_host_authority(host_raw) else {
        return false;
    };
    if host != origin_host {
        return false;
    }
    match host_port {
        Some(port) => origin.port_or_known_default() == Some(port),
        None => origin_uses_default_port(&origin),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::{to_bytes, Body};
    use axum::http::{header, Method, Request, StatusCode};
    use axum::routing::{get, patch, post};
    use axum::Json;
    use serde_json::{json, Value};
    use shamell_common::internal_identity::{
        InternalIdentityVerifier, InternalRequestSigner, INTERNAL_IDENTITY_AUDIENCE_HEADER,
        INTERNAL_IDENTITY_NONCE_HEADER, INTERNAL_IDENTITY_SIG_HEADER,
        INTERNAL_IDENTITY_SIG_V2_HEADER, INTERNAL_IDENTITY_TS_HEADER, INTERNAL_SERVICE_ID_HEADER,
    };
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
        assert!(!has("x-internal-audience"));
        assert!(!has("x-internal-identity-ts"));
        assert!(!has("x-internal-identity-sig"));
        assert!(!has("x-internal-identity-sig-v2"));
        assert!(!has("x-internal-identity-nonce"));
        assert!(!has("x-role-auth"));
        assert!(!has("x-auth-roles"));
        assert!(!has("x-roles"));
        assert!(!has("x-forwarded-for"));
        assert!(!has("x-forwarded-host"));
        assert!(!has("x-real-ip"));
        assert!(!has("x-shamell-client-ip"));
        assert!(!has("x-shamell-client-ip-attested"));
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
        let session = Router::new()
            .route("/me/home_snapshot", get(|| async { StatusCode::OK }))
            .route(
                "/admin/official_auto_replies/:rule_id",
                patch(|| async { StatusCode::OK }),
            )
            .route(
                "/official_accounts/:account_id/follow",
                post(|| async { StatusCode::OK }),
            )
            .layer(cors_layer_for_headers(
                &allowed_origins,
                bff_session_cors_allowed_headers(),
            ));
        let contacts = Router::new()
            .route(
                "/contacts/invites/redeem",
                post(|| async { StatusCode::OK }),
            )
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
            .route("/me/rides/trips", post(|| async { StatusCode::OK }))
            .layer(cors_layer_for_headers(
                &allowed_origins,
                bff_payments_cors_allowed_headers(),
            ));
        let internal = Router::new().route("/internal/security/alerts", post(|| async { "ok" }));

        Router::new()
            .merge(public_auth)
            .merge(session)
            .merge(contacts)
            .merge(chat)
            .merge(payments)
            .merge(internal)
    }

    fn password_only_auth_routes_test_app(auth_device_login_web_enabled: bool) -> Router {
        let public_auth = Router::new()
            .route(
                "/auth/account/create/challenge",
                post(auth::auth_password_only_required),
            )
            .route(
                "/auth/biometric/enroll/challenge",
                post(auth::auth_password_only_required),
            )
            .route(
                "/auth/biometric/login/challenge",
                post(auth::auth_password_only_required),
            )
            .route("/auth/signup", post(|| async { StatusCode::OK }))
            .route("/auth/login", post(|| async { StatusCode::OK }))
            .route(
                "/auth/account/create",
                post(auth::auth_password_only_required),
            )
            .route(
                "/auth/biometric/enroll",
                post(auth::auth_password_only_required),
            )
            .route(
                "/auth/biometric/login",
                post(auth::auth_password_only_required),
            )
            .route(
                "/auth/device_login/start",
                post(auth::auth_password_only_required),
            )
            .route(
                "/auth/device_login/approve",
                post(auth::auth_password_only_required),
            )
            .route(
                "/auth/device_login/redeem",
                post(auth::auth_password_only_required),
            )
            .route(
                "/auth/device_login/qr.svg",
                post(auth::auth_password_only_required),
            );
        if auth_device_login_web_enabled {
            public_auth
                .route("/auth/device_login", get(auth::auth_password_only_required))
                .route(
                    "/auth/device_login_demo",
                    get(auth::auth_password_only_required),
                )
        } else {
            public_auth
        }
    }

    async fn preflight(
        path: &str,
        requested_method: Method,
        requested_headers: &str,
    ) -> axum::response::Response {
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

    fn owners_route_test_state_no_auth() -> AppState {
        AppState {
            env_name: "test".to_string(),
            allowed_origins: vec!["https://online.shamell.online".to_string()],
            payments_base_url: "http://payments:8082".to_string(),
            payments_internal_secret: None,
            fee_wallet_account_id: None,
            fee_wallet_phone: None,
            chat_base_url: "http://chat:8081".to_string(),
            chat_internal_secret: None,
            internal_service_id: "bff".to_string(),
            internal_request_signer: None,
            enforce_route_authz: true,
            role_header_secret: None,
            upstream_timeout_secs: 12,
            max_upstream_body_bytes: 1_048_576,
            expose_upstream_errors: false,
            accept_legacy_session_cookie: false,
            allow_legacy_contact_invite_chat_device_fallback: false,
            auth_device_login_web_enabled: true,
            workforce_access: None,
            direct_web_access: None,
            direct_web_launch: None,
            geo_lookup_base_url: DEFAULT_GEO_LOOKUP_BASE_URL.to_string(),
            http: reqwest::Client::new(),
            auth: None,
            wallet_resolution_cache: Arc::new(RwLock::new(HashMap::new())),
            geo_lookup_cache: Arc::new(RwLock::new(HashMap::new())),
            account_roles_cache: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    fn owners_route_test_app_no_auth() -> Router {
        Router::new()
            .route(
                "/admin/official_accounts/:account_id/owners",
                get(auth::admin_official_account_owners_list)
                    .post(auth::admin_official_account_owners_add)
                    .delete(auth::admin_official_account_owners_remove),
            )
            .with_state(owners_route_test_state_no_auth())
    }

    async fn spawn_payments_roles_stub(
        status: StatusCode,
        body: Value,
    ) -> (String, tokio::task::JoinHandle<()>) {
        let app = Router::new().route(
            "/admin/roles",
            get(move || {
                let body = body.clone();
                async move { (status, Json(body)) }
            }),
        );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind");
        let addr = listener.local_addr().expect("addr");
        let server = tokio::spawn(async move {
            let _ = axum::serve(listener, app).await;
        });
        (format!("http://{addr}"), server)
    }

    fn official_admin_test_app_no_auth() -> Router {
        Router::new()
            .route(
                "/admin/official_accounts/:account_id/owners",
                get(auth::admin_official_account_owners_list)
                    .post(auth::admin_official_account_owners_add)
                    .delete(auth::admin_official_account_owners_remove),
            )
            .route(
                "/admin/official_accounts/:account_id/auto_replies",
                get(auth::admin_official_account_auto_replies_list)
                    .post(auth::admin_official_account_auto_replies_create),
            )
            .route(
                "/admin/official_accounts/:account_id/moments_stats",
                get(auth::official_account_moments_stats),
            )
            .route(
                "/admin/official_accounts/:account_id",
                patch(auth::admin_official_account_patch),
            )
            .route(
                "/admin/official_feeds",
                post(auth::admin_official_feeds_create),
            )
            .route(
                "/admin/official_auto_replies/:rule_id",
                patch(auth::admin_official_auto_reply_patch),
            )
            .route(
                "/admin/official_accounts/:account_id/service_inbox",
                get(auth::admin_official_service_inbox_list),
            )
            .route(
                "/admin/official_accounts/:account_id/service_inbox/:session_id/mark_read",
                post(auth::admin_official_service_inbox_mark_read),
            )
            .route(
                "/admin/official_accounts/:account_id/service_inbox/:session_id/close",
                post(auth::admin_official_service_inbox_close),
            )
            .route(
                "/admin/official_accounts/:account_id/service_inbox/:session_id/template_messages",
                post(auth::admin_official_service_inbox_send_template_message),
            )
            .with_state(owners_route_test_state_no_auth())
    }

    fn session_surface_test_app_no_auth() -> Router {
        Router::new()
            .route("/auth/devices", get(auth::auth_devices_list))
            .route("/official_accounts", get(auth::official_accounts_list))
            .route("/me/home_snapshot", get(auth::me_home_snapshot))
            .route("/me/geo/search", get(handlers::moments_geo_search))
            .route("/me/coach/bootstrap", get(handlers::coach_bootstrap))
            .route("/me/coach/search", get(handlers::coach_search))
            .route("/me/coach/offers/:offer_id", get(handlers::coach_offer_get))
            .route("/me/coach/holds", post(handlers::coach_hold_create))
            .route("/me/coach/holds/:hold_id", get(handlers::coach_hold_get))
            .route(
                "/me/coach/journeys/:journey_id/live",
                get(handlers::coach_journey_live_get),
            )
            .route(
                "/me/coach/bookings",
                get(handlers::coach_booking_list).post(handlers::coach_booking_create),
            )
            .route(
                "/me/coach/bookings/:booking_id",
                get(handlers::coach_booking_get),
            )
            .route(
                "/me/coach/bookings/:booking_id/refund_eligibility",
                get(handlers::coach_refund_eligibility_get),
            )
            .route(
                "/me/coach/bookings/:booking_id/change_options",
                get(handlers::coach_change_options_get),
            )
            .route(
                "/me/coach/bookings/:booking_id/tickets",
                post(handlers::coach_ticket_issue),
            )
            .route(
                "/me/coach/bookings/:booking_id/refunds",
                post(handlers::coach_refund_request),
            )
            .route(
                "/me/coach/bookings/:booking_id/rebook_requests",
                post(handlers::coach_rebook_request),
            )
            .route(
                "/me/coach/bookings/:booking_id/reissue",
                post(handlers::coach_self_service_reissue),
            )
            .route(
                "/me/coach/bookings/:booking_id/reissue/resolve_payment_failure",
                post(handlers::coach_resolve_reissue_payment_failure),
            )
            .route(
                "/me/coach/tickets/:ticket_id",
                get(handlers::coach_ticket_get),
            )
            .route(
                "/me/coach/admin/overview",
                get(handlers::coach_admin_overview),
            )
            .route(
                "/me/coach/admin/risk/dashboard",
                get(handlers::coach_admin_risk_dashboard),
            )
            .route(
                "/me/coach/admin/risk/:risk_id/action",
                post(handlers::coach_admin_risk_action),
            )
            .route(
                "/me/coach/admin/partners/onboarding",
                get(handlers::coach_admin_partner_onboarding),
            )
            .route(
                "/me/coach/admin/partners/:operator_id/onboarding_action",
                post(handlers::coach_admin_partner_onboarding_action),
            )
            .route(
                "/me/coach/admin/disruptions",
                get(handlers::coach_admin_disruptions),
            )
            .route(
                "/me/coach/admin/disruptions/:trip_id/action",
                post(handlers::coach_admin_disruption_action),
            )
            .route(
                "/me/coach/admin/finance/journal",
                get(handlers::coach_admin_finance_journal),
            )
            .route(
                "/me/coach/admin/finance/shamell_pay_reconciliation",
                get(handlers::coach_admin_shamell_pay_reconciliation),
            )
            .route(
                "/me/coach/admin/finance/shamell_pay_reconciliation/:payout_run_id/release_operator_rail",
                post(handlers::coach_admin_shamell_pay_release_operator_rail),
            )
            .route(
                "/me/coach/admin/finance/shamell_pay_reconciliation/:payout_run_id/confirm_operator_rail",
                post(handlers::coach_admin_shamell_pay_confirm_operator_rail),
            )
            .route(
                "/me/coach/admin/finance/shamell_pay_reconciliation/:payout_run_id/fail_operator_rail",
                post(handlers::coach_admin_shamell_pay_fail_operator_rail),
            )
            .route(
                "/me/coach/admin/finance/shamell_pay_reports",
                post(handlers::coach_admin_shamell_pay_report_import_create),
            )
            .route(
                "/me/coach/admin/support/cases",
                get(handlers::coach_admin_support_cases),
            )
            .route(
                "/me/coach/admin/support/cases/:case_id",
                get(handlers::coach_admin_support_case_get),
            )
            .route(
                "/me/coach/admin/support/cases/:case_id/resolve_payment_failure",
                post(handlers::coach_admin_support_case_resolve_payment_failure),
            )
            .route(
                "/me/coach/operator/refund_queue",
                get(handlers::coach_operator_refund_queue),
            )
            .route(
                "/me/coach/operator/change_queue",
                get(handlers::coach_operator_change_queue),
            )
            .route(
                "/me/coach/operator/reconciliation",
                get(handlers::coach_operator_reconciliation),
            )
            .route(
                "/me/coach/operator/settlement_statements",
                get(handlers::coach_operator_settlement_statements),
            )
            .route(
                "/me/coach/operator/payout_runs",
                get(handlers::coach_operator_payout_runs)
                    .post(handlers::coach_operator_payout_run_create),
            )
            .route(
                "/me/coach/operator/payout_reconciliation",
                get(handlers::coach_operator_payout_reconciliation),
            )
            .route(
                "/me/coach/operator/payout_imports",
                get(handlers::coach_operator_payout_imports),
            )
            .route(
                "/me/coach/operator/catalog_import_runs",
                get(handlers::coach_operator_catalog_import_runs)
                    .post(handlers::coach_operator_catalog_import_run_trigger),
            )
            .route(
                "/me/coach/operator/catalog_import_run_saved_views",
                get(handlers::coach_operator_catalog_import_run_saved_views)
                    .post(handlers::coach_operator_catalog_import_run_saved_view_upsert),
            )
            .route(
                "/me/coach/operator/catalog_import_run_saved_views/:view_id/delete",
                post(handlers::coach_operator_catalog_import_run_saved_view_delete),
            )
            .route(
                "/me/coach/operator/catalog_import_run_saved_views/:view_id/favorite",
                post(handlers::coach_operator_catalog_import_run_saved_view_favorite_toggle),
            )
            .route(
                "/me/coach/operator/catalog_import_run_saved_views/:view_id/use",
                post(handlers::coach_operator_catalog_import_run_saved_view_use),
            )
            .route(
                "/me/coach/operator/catalog_import_run_issue_saved_views",
                get(handlers::coach_operator_catalog_import_run_issue_saved_views)
                    .post(handlers::coach_operator_catalog_import_run_issue_saved_view_upsert),
            )
            .route(
                "/me/coach/operator/catalog_import_run_issue_saved_views/:view_id/delete",
                post(handlers::coach_operator_catalog_import_run_issue_saved_view_delete),
            )
            .route(
                "/me/coach/operator/catalog_import_run_issue_saved_views/:view_id/favorite",
                post(handlers::coach_operator_catalog_import_run_issue_saved_view_favorite_toggle),
            )
            .route(
                "/me/coach/operator/catalog_import_run_issue_saved_views/:view_id/use",
                post(handlers::coach_operator_catalog_import_run_issue_saved_view_use),
            )
            .route(
                "/me/coach/operator/catalog_import_runs/:import_run_id",
                get(handlers::coach_operator_catalog_import_run_get),
            )
            .route(
                "/me/coach/operator/catalog_import_runs/:import_run_id/replays",
                get(handlers::coach_operator_catalog_import_run_replays),
            )
            .route(
                "/me/coach/operator/catalog_source_artifacts",
                get(handlers::coach_operator_catalog_source_artifacts),
            )
            .route(
                "/me/coach/operator/catalog_source_artifacts/:artifact_id",
                get(handlers::coach_operator_catalog_source_artifact_get),
            )
            .route(
                "/me/coach/operator/catalog_import_sources",
                get(handlers::coach_operator_catalog_import_sources),
            )
            .route(
                "/me/coach/operator/catalog_import_sources/upload",
                post(handlers::coach_operator_catalog_import_source_upload),
            )
            .route(
                "/me/coach/operator/catalog_import_config",
                get(handlers::coach_operator_catalog_import_config)
                    .post(handlers::coach_operator_catalog_import_config_update),
            )
            .route(
                "/me/coach/operator/feed_health",
                get(handlers::coach_operator_feed_health),
            )
            .route(
                "/me/coach/operator/payout_import_profiles",
                get(handlers::coach_operator_payout_import_profiles),
            )
            .route(
                "/me/coach/operator/payout_import_previews",
                get(handlers::coach_operator_payout_import_previews),
            )
            .route(
                "/me/coach/operator/payout_import_preview_saved_views",
                get(handlers::coach_operator_payout_import_preview_saved_views)
                    .post(handlers::coach_operator_payout_import_preview_saved_view_upsert),
            )
            .route(
                "/me/coach/operator/payout_import_preview_saved_views/:view_id/delete",
                post(handlers::coach_operator_payout_import_preview_saved_view_delete),
            )
            .route(
                "/me/coach/operator/payout_import_preview_saved_views/:view_id/favorite",
                post(handlers::coach_operator_payout_import_preview_saved_view_favorite_toggle),
            )
            .route(
                "/me/coach/operator/payout_import_preview_saved_views/:view_id/use",
                post(handlers::coach_operator_payout_import_preview_saved_view_use),
            )
            .route(
                "/me/coach/operator/payout_import_previews/:preview_token/invalidate",
                post(handlers::coach_operator_payout_import_preview_invalidate),
            )
            .route(
                "/me/coach/operator/payout_import_batches",
                get(handlers::coach_operator_payout_import_batches)
                    .post(handlers::coach_operator_payout_import_batch_create),
            )
            .route(
                "/me/coach/operator/payout_import_batch_saved_views",
                get(handlers::coach_operator_payout_import_batch_saved_views)
                    .post(handlers::coach_operator_payout_import_batch_saved_view_upsert),
            )
            .route(
                "/me/coach/operator/payout_import_batch_saved_views/:view_id/delete",
                post(handlers::coach_operator_payout_import_batch_saved_view_delete),
            )
            .route(
                "/me/coach/operator/payout_import_batch_saved_views/:view_id/favorite",
                post(handlers::coach_operator_payout_import_batch_saved_view_favorite_toggle),
            )
            .route(
                "/me/coach/operator/payout_import_batch_saved_views/:view_id/use",
                post(handlers::coach_operator_payout_import_batch_saved_view_use),
            )
            .route(
                "/me/coach/operator/payout_import_batches/upload",
                post(handlers::coach_operator_payout_import_batch_upload),
            )
            .route(
                "/downloads/coach/payout_import_reports/:artifact_name",
                get(handlers::coach_operator_payout_import_report_download),
            )
            .route(
                "/me/coach/operator/payout_runs/:payout_run_id/mark_paid",
                post(handlers::coach_operator_payout_run_mark_paid),
            )
            .route(
                "/me/coach/operator/payout_runs/:payout_run_id/imports",
                post(handlers::coach_operator_payout_run_import_create),
            )
            .route(
                "/me/coach/operator/payout_runs/:payout_run_id/exports",
                post(handlers::coach_operator_payout_run_export_create),
            )
            .route(
                "/downloads/coach/settlement_exports/:artifact_name",
                get(handlers::coach_operator_settlement_export_download),
            )
            .route(
                "/me/coach/operator/refund_requests/:refund_request_id/review",
                post(handlers::coach_operator_refund_request_review),
            )
            .route(
                "/me/coach/operator/change_requests/:change_request_id/review",
                post(handlers::coach_operator_change_request_review),
            )
            .route(
                "/me/coach/crew/departures",
                get(handlers::coach_crew_departures),
            )
            .route(
                "/me/coach/crew/trips/:trip_id/manifest",
                get(handlers::coach_crew_manifest_get),
            )
            .route(
                "/me/coach/crew/trips/:trip_id/boardings",
                post(handlers::coach_crew_boarding_record),
            )
            .route("/me/rides/bootstrap", get(handlers::rides_bootstrap))
            .route(
                "/me/rides/support_tickets",
                get(handlers::rides_support_tickets_list)
                    .post(handlers::rides_support_ticket_create),
            )
            .route(
                "/me/rides/trips/:ride_id/tracking",
                get(handlers::rides_trip_tracking_get),
            )
            .route(
                "/me/rides/trips/:ride_id/enter_matching",
                post(handlers::rides_trip_enter_matching),
            )
            .route(
                "/me/rides/trips/:ride_id/live",
                get(handlers::rides_trip_live_get),
            )
            .route(
                "/me/rides/trips/active/stream",
                get(handlers::rides_trip_active_stream),
            )
            .route(
                "/me/rides/pricing_preview",
                get(handlers::rides_pricing_preview),
            )
            .route("/me/rides/driver/queue", get(handlers::rides_driver_queue))
            .route(
                "/me/rides/driver/stream",
                get(handlers::rides_driver_stream),
            )
            .route(
                "/me/rides/driver/dispatch_offers",
                get(handlers::rides_driver_queue),
            )
            .route(
                "/me/rides/driver/dispatch_offers/:offer_id/accept",
                post(handlers::rides_driver_dispatch_offer_accept),
            )
            .route(
                "/me/rides/driver/dispatch_offers/:offer_id/reject",
                post(handlers::rides_driver_dispatch_offer_reject),
            )
            .route(
                "/me/rides/driver/presence",
                get(handlers::rides_driver_presence_get)
                    .post(handlers::rides_driver_presence_upsert),
            )
            .route(
                "/me/rides/driver/finance_dashboard",
                get(handlers::rides_driver_finance_dashboard),
            )
            .route(
                "/me/rides/driver/shift_summary",
                get(handlers::rides_driver_shift_summary),
            )
            .route(
                "/me/rides/driver/documents",
                get(handlers::rides_driver_documents).post(handlers::rides_driver_document_upsert),
            )
            .route(
                "/me/rides/driver/payout_requests",
                post(handlers::rides_driver_payout_request_create),
            )
            .route(
                "/me/rides/operator/fleet/live",
                get(handlers::rides_operator_fleet_live),
            )
            .route(
                "/me/rides/driver/trips/:ride_id/status",
                post(handlers::rides_driver_trip_status),
            )
            .route(
                "/me/rides/driver/trips/:ride_id/location_ping",
                post(handlers::rides_driver_location_ping),
            )
            .route(
                "/me/rides/operator/live_board",
                get(handlers::rides_operator_live_board),
            )
            .route(
                "/me/rides/operator/stream",
                get(handlers::rides_operator_stream),
            )
            .route(
                "/me/rides/operator/driver_roster",
                get(handlers::rides_operator_driver_roster),
            )
            .route(
                "/me/rides/operator/pricing_policy",
                get(handlers::rides_operator_pricing_policy)
                    .post(handlers::rides_operator_pricing_policy_upsert),
            )
            .route(
                "/me/rides/operator/case_queue",
                get(handlers::rides_operator_case_queue),
            )
            .route(
                "/me/rides/operator/support_queue",
                get(handlers::rides_operator_support_queue),
            )
            .route(
                "/me/rides/operator/document_queue",
                get(handlers::rides_operator_document_queue),
            )
            .route(
                "/me/rides/operator/finance_queue",
                get(handlers::rides_operator_finance_queue),
            )
            .route(
                "/me/rides/operator/trips/:ride_id/commands",
                post(handlers::rides_operator_trip_command),
            )
            .route(
                "/me/rides/operator/documents/:document_id/review",
                post(handlers::rides_operator_document_review),
            )
            .route(
                "/me/rides/operator/support_tickets/:ticket_id/resolve",
                post(handlers::rides_operator_support_ticket_resolve),
            )
            .route(
                "/me/rides/operator/payout_requests/:rid/approve",
                post(handlers::rides_operator_payout_request_approve),
            )
            .route(
                "/me/rides/map_tiles/:z/:x/:y",
                get(handlers::rides_map_tile),
            )
            .with_state(owners_route_test_state_no_auth())
    }

    async fn response_detail(resp: axum::response::Response) -> Option<String> {
        let body = to_bytes(resp.into_body(), 1024 * 1024).await.ok()?;
        let v: Value = serde_json::from_slice(&body).ok()?;
        v.get("detail").and_then(|x| x.as_str()).map(str::to_string)
    }

    #[test]
    fn parse_forwarded_ip_token_supports_ip_and_socket_forms() {
        assert_eq!(
            parse_forwarded_ip_token("198.51.100.20"),
            Some("198.51.100.20".parse().unwrap())
        );
        assert_eq!(
            parse_forwarded_ip_token("198.51.100.20:443"),
            Some("198.51.100.20".parse().unwrap())
        );
        assert_eq!(
            parse_forwarded_ip_token("for=\"[2001:db8::2]:443\""),
            Some("2001:db8::2".parse().unwrap())
        );
    }

    #[test]
    fn derive_client_ip_ignores_forwarded_chain_without_trusted_proxy() {
        let client_ip = derive_client_ip(
            "203.0.113.9".parse().unwrap(),
            Some("198.51.100.20, 198.51.100.21"),
            &[],
        );
        assert_eq!(client_ip, "203.0.113.9".parse::<IpAddr>().unwrap());
    }

    #[test]
    fn derive_client_ip_uses_rightmost_untrusted_hop_behind_trusted_proxy() {
        let trusted = vec!["10.0.0.0/8".parse().unwrap()];
        let client_ip = derive_client_ip(
            "10.0.0.5".parse().unwrap(),
            Some("198.51.100.20, 10.0.0.9"),
            &trusted,
        );
        assert_eq!(client_ip, "198.51.100.20".parse::<IpAddr>().unwrap());
    }

    #[tokio::test]
    async fn trusted_client_ip_middleware_derives_forwarded_ip_for_trusted_loopback_peer() {
        let app = Router::new()
            .route(
                "/",
                get(|headers: HeaderMap| async move {
                    Json(json!({
                        "client_ip": headers
                            .get(TRUSTED_CLIENT_IP_HEADER)
                            .and_then(|value| value.to_str().ok()),
                        "client_ip_attested": headers
                            .get(TRUSTED_CLIENT_IP_ATTESTED_HEADER)
                            .and_then(|value| value.to_str().ok()),
                    }))
                }),
            )
            .layer(middleware::from_fn_with_state(
                TrustedProxyState {
                    trusted_proxy_cidrs: vec!["127.0.0.1/32".parse().unwrap()],
                },
                trusted_client_ip_middleware,
            ));

        let mut req = Request::builder().uri("/").body(Body::empty()).unwrap();
        req.headers_mut()
            .insert("x-forwarded-for", "203.0.113.10".parse().unwrap());
        req.extensions_mut()
            .insert(ConnectInfo(SocketAddr::from(([127, 0, 0, 1], 43210))));

        let resp = app.oneshot(req).await.unwrap();
        assert_eq!(resp.status(), StatusCode::OK);

        let body = to_bytes(resp.into_body(), 1024 * 1024).await.unwrap();
        let payload: Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(
            payload.get("client_ip").and_then(Value::as_str),
            Some("203.0.113.10")
        );
        assert_eq!(
            payload.get("client_ip_attested").and_then(Value::as_str),
            Some("1")
        );
    }

    #[tokio::test]
    async fn trusted_client_ip_middleware_ignores_forwarded_headers_for_untrusted_peer() {
        let app = Router::new()
            .route(
                "/",
                get(|headers: HeaderMap| async move {
                    Json(json!({
                        "client_ip": headers
                            .get(TRUSTED_CLIENT_IP_HEADER)
                            .and_then(|value| value.to_str().ok()),
                        "client_ip_attested": headers
                            .get(TRUSTED_CLIENT_IP_ATTESTED_HEADER)
                            .and_then(|value| value.to_str().ok()),
                    }))
                }),
            )
            .layer(middleware::from_fn_with_state(
                TrustedProxyState {
                    trusted_proxy_cidrs: vec!["127.0.0.1/32".parse().unwrap()],
                },
                trusted_client_ip_middleware,
            ));

        let mut req = Request::builder().uri("/").body(Body::empty()).unwrap();
        req.headers_mut()
            .insert("x-forwarded-for", "203.0.113.10".parse().unwrap());
        req.headers_mut()
            .insert(TRUSTED_CLIENT_IP_HEADER, "198.51.100.99".parse().unwrap());
        req.headers_mut()
            .insert("x-real-ip", "198.51.100.98".parse().unwrap());
        req.extensions_mut()
            .insert(ConnectInfo(SocketAddr::from(([198, 51, 100, 20], 43210))));

        let resp = app.oneshot(req).await.unwrap();
        assert_eq!(resp.status(), StatusCode::OK);

        let body = to_bytes(resp.into_body(), 1024 * 1024).await.unwrap();
        let payload: Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(
            payload.get("client_ip").and_then(Value::as_str),
            Some("198.51.100.20")
        );
        assert_eq!(
            payload.get("client_ip_attested").and_then(Value::as_str),
            Some("1")
        );
    }

    #[test]
    fn strip_spoofable_client_ip_headers_removes_all_forwarding_metadata() {
        let mut headers = HeaderMap::new();
        headers.insert("forwarded", "for=198.51.100.20".parse().unwrap());
        headers.insert("x-forwarded-for", "198.51.100.20".parse().unwrap());
        headers.insert("x-forwarded-host", "evil.example".parse().unwrap());
        headers.insert("x-real-ip", "198.51.100.20".parse().unwrap());
        headers.insert(TRUSTED_CLIENT_IP_HEADER, "198.51.100.20".parse().unwrap());
        headers.insert(TRUSTED_CLIENT_IP_ATTESTED_HEADER, "1".parse().unwrap());

        strip_spoofable_client_ip_headers(&mut headers);

        assert!(headers.is_empty());
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
    fn csrf_guard_does_not_trust_wildcard_allowed_origins_for_cookie_writes() {
        let st = state(true, &["*"], false);
        let h = headers(&[
            (
                "cookie",
                "__Host-sa_session=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            ),
            ("origin", "https://evil.example"),
            ("host", "api.shamell.online"),
        ]);
        assert_eq!(
            csrf_block_reason(&st, &Method::POST, &h),
            Some("origin_not_allowed")
        );
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
    fn csrf_guard_rejects_same_host_http_origin() {
        let st = state(true, &["https://online.shamell.online"], false);
        let h = headers(&[
            (
                "cookie",
                "__Host-sa_session=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            ),
            ("origin", "http://api.shamell.online"),
            ("host", "api.shamell.online"),
        ]);
        assert_eq!(
            csrf_block_reason(&st, &Method::POST, &h),
            Some("invalid_origin")
        );
    }

    #[test]
    fn csrf_guard_rejects_same_host_different_port_origin() {
        let st = state(true, &["https://online.shamell.online"], false);
        let h = headers(&[
            (
                "cookie",
                "__Host-sa_session=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            ),
            ("origin", "https://api.shamell.online:8443"),
            ("host", "api.shamell.online"),
        ]);
        assert_eq!(
            csrf_block_reason(&st, &Method::POST, &h),
            Some("origin_not_allowed")
        );
    }

    #[test]
    fn csrf_guard_does_not_trust_x_forwarded_host_for_same_host_bypass() {
        let st = state(true, &["https://online.shamell.online"], false);
        let h = headers(&[
            (
                "cookie",
                "__Host-sa_session=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            ),
            ("origin", "https://evil.example"),
            ("host", "api.shamell.online"),
            ("x-forwarded-host", "evil.example"),
        ]);
        assert_eq!(
            csrf_block_reason(&st, &Method::POST, &h),
            Some("origin_not_allowed")
        );
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
    fn bff_session_cors_whitelist_allows_idempotency_for_session_mutations_only() {
        let headers = bff_session_cors_allowed_headers();
        let has = |name: &str| {
            headers
                .iter()
                .any(|h| h.as_str().eq_ignore_ascii_case(name))
        };

        assert!(has("content-type"));
        assert!(has("idempotency-key"));
        assert!(has("x-request-id"));
        assert!(has("x-shamell-app-surface"));
        assert!(!has("x-chat-device-id"));
        assert!(!has("x-chat-device-token"));
        assert!(!has("x-device-id"));
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
        assert!(has("x-shamell-payment-attestation-challenge"));
        assert!(has("x-shamell-payment-play-integrity"));
        assert!(has("x-shamell-payment-apple-devicecheck"));
        assert!(has("x-request-id"));
        assert!(!has("x-chat-device-id"));
        assert!(!has("x-chat-device-token"));
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
    async fn public_auth_routes_block_legacy_auth_flows_in_password_only_mode() {
        let app = password_only_auth_routes_test_app(true);
        let legacy_routes = [
            (Method::POST, "/auth/account/create/challenge"),
            (Method::POST, "/auth/biometric/enroll/challenge"),
            (Method::POST, "/auth/biometric/login/challenge"),
            (Method::POST, "/auth/account/create"),
            (Method::POST, "/auth/biometric/enroll"),
            (Method::POST, "/auth/biometric/login"),
            (Method::POST, "/auth/device_login/start"),
            (Method::POST, "/auth/device_login/approve"),
            (Method::POST, "/auth/device_login/redeem"),
            (Method::POST, "/auth/device_login/qr.svg"),
            (Method::GET, "/auth/device_login"),
            (Method::GET, "/auth/device_login_demo"),
        ];

        for (method, path) in legacy_routes {
            let resp = app
                .clone()
                .oneshot(
                    Request::builder()
                        .method(method.clone())
                        .uri(path)
                        .body(Body::empty())
                        .unwrap(),
                )
                .await
                .unwrap();
            assert_eq!(resp.status(), StatusCode::GONE, "{method} {path}");
            assert_eq!(
                response_detail(resp).await.as_deref(),
                Some("only username/password sign-up and sign-in are supported"),
                "{method} {path}"
            );
        }
    }

    #[tokio::test]
    async fn public_auth_routes_keep_device_login_pages_unrouted_when_web_disabled() {
        let app = password_only_auth_routes_test_app(false);

        let resp = app
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/auth/device_login")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn cors_preflight_session_allows_patch_routes() {
        let resp = preflight(
            "/admin/official_auto_replies/rule-1",
            Method::PATCH,
            "content-type,idempotency-key,x-request-id",
        )
        .await;
        assert!(resp.status().is_success());
        assert!(has_allow_header(&resp, "content-type"));
        assert!(has_allow_header(&resp, "idempotency-key"));
        assert!(has_allow_header(&resp, "x-request-id"));
    }

    #[tokio::test]
    async fn cors_preflight_session_home_snapshot_allows_app_surface_header() {
        let resp = preflight("/me/home_snapshot", Method::GET, "x-shamell-app-surface").await;
        assert!(resp.status().is_success());
        assert!(has_allow_header(&resp, "x-shamell-app-surface"));
        assert!(!has_allow_header(&resp, "x-shamell-client-ip"));
        assert!(!has_allow_header(&resp, "cookie"));
    }

    #[tokio::test]
    async fn cors_preflight_session_official_follow_allows_idempotency_key() {
        let resp = preflight(
            "/official_accounts/oa_123/follow",
            Method::POST,
            "content-type,idempotency-key,x-request-id",
        )
        .await;
        assert!(resp.status().is_success());
        assert!(has_allow_header(&resp, "content-type"));
        assert!(has_allow_header(&resp, "idempotency-key"));
        assert!(has_allow_header(&resp, "x-request-id"));
        assert!(!has_allow_header(&resp, "x-chat-device-id"));
        assert!(!has_allow_header(&resp, "x-device-id"));
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
            "content-type,idempotency-key,x-device-id,x-merchant,x-ref,x-shamell-payment-attestation-challenge,x-shamell-payment-play-integrity",
        )
        .await;
        assert!(resp.status().is_success());
        assert!(has_allow_header(&resp, "idempotency-key"));
        assert!(has_allow_header(&resp, "x-device-id"));
        assert!(has_allow_header(&resp, "x-merchant"));
        assert!(has_allow_header(&resp, "x-ref"));
        assert!(has_allow_header(
            &resp,
            "x-shamell-payment-attestation-challenge",
        ));
        assert!(has_allow_header(&resp, "x-shamell-payment-play-integrity"));
        assert!(!has_allow_header(&resp, "x-chat-device-id"));
    }

    #[tokio::test]
    async fn cors_preflight_rides_trip_mutation_allows_idempotency_key() {
        let resp = preflight(
            "/me/rides/trips",
            Method::POST,
            "content-type,idempotency-key,x-device-id",
        )
        .await;
        assert!(resp.status().is_success());
        assert!(has_allow_header(&resp, "idempotency-key"));
        assert!(has_allow_header(&resp, "x-device-id"));
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

    #[tokio::test]
    async fn security_alerts_route_accepts_signed_internal_identity() {
        let signer =
            InternalRequestSigner::from_seed_bytes("security-reporter", [9u8; 32]).expect("signer");
        let verifier = InternalIdentityVerifier::from_public_keys_base64(
            vec![("security-reporter".to_string(), signer.public_key_base64())],
            30,
        )
        .expect("verifier");
        let signed = signer
            .sign(
                &Method::POST,
                "bff",
                "/internal/security/alerts",
                br#"{"alerts":["demo.alert:1/1"],"severity":"info"}"#,
            )
            .expect("signature");
        let app = Router::new()
            .route(
                "/internal/security/alerts",
                post(|| async { StatusCode::OK }),
            )
            .layer(
                InternalAuthLayer::new(true, None)
                    .with_allowed_callers(vec!["security-reporter".to_string()])
                    .with_expected_audience("bff")
                    .with_identity_verifier(verifier)
                    .with_legacy_secret_fallback(false),
            );

        let resp = app
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/internal/security/alerts")
                    .header(INTERNAL_SERVICE_ID_HEADER, signed.service_id)
                    .header(INTERNAL_IDENTITY_SIG_HEADER, signed.signature_b64)
                    .header(INTERNAL_IDENTITY_AUDIENCE_HEADER, signed.audience)
                    .header(INTERNAL_IDENTITY_TS_HEADER, signed.timestamp.to_string())
                    .header(INTERNAL_IDENTITY_NONCE_HEADER, signed.nonce)
                    .header(INTERNAL_IDENTITY_SIG_V2_HEADER, signed.signature_v2_b64)
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(
                        br#"{"alerts":["demo.alert:1/1"],"severity":"info"}"#
                            .as_slice()
                            .to_vec(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(resp.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn owners_route_rejects_invalid_account_id_with_400() {
        let resp = owners_route_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/admin/official_accounts/bad%2Fid/owners")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official account id invalid")
        );
    }

    #[tokio::test]
    async fn owners_route_requires_auth_runtime_for_list() {
        let resp = owners_route_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/admin/official_accounts/shamell_pay/owners")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::SERVICE_UNAVAILABLE);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("auth not configured")
        );
    }

    #[tokio::test]
    async fn owners_route_requires_auth_runtime_for_add() {
        let resp = owners_route_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/admin/official_accounts/shamell_pay/owners")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from("{}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::SERVICE_UNAVAILABLE);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("auth not configured")
        );
    }

    #[tokio::test]
    async fn me_home_snapshot_requires_auth_runtime() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/home_snapshot")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::SERVICE_UNAVAILABLE);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("auth not configured")
        );
    }

    #[tokio::test]
    async fn auth_devices_list_requires_auth_runtime() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/auth/devices")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::SERVICE_UNAVAILABLE);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("auth not configured")
        );
    }

    #[tokio::test]
    async fn official_accounts_list_requires_auth_runtime() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/official_accounts")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::SERVICE_UNAVAILABLE);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("auth not configured")
        );
    }

    #[tokio::test]
    async fn moments_geo_search_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/geo/search?q=Damascus")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_bootstrap_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/bootstrap")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_search_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/search?from=Damascus&to=Aleppo&departure_date=2026-04-08")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_hold_create_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/coach/holds")
                    .header("content-type", "application/json")
                    .header("idempotency-key", "coach-hold-test-1")
                    .body(Body::from(
                        r#"{"offer_id":"offer_demo_express_direct","passengers":1}"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_booking_list_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/bookings")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_journey_live_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/journeys/journey_demo_express_direct/live")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_refund_eligibility_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/bookings/booking_demo_express_direct/refund_eligibility")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_change_options_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/bookings/booking_demo_express_direct/change_options")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_ticket_issue_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/coach/bookings/booking_demo/tickets")
                    .header("content-type", "application/json")
                    .header("idempotency-key", "coach-ticket-test-1")
                    .body(Body::from(
                        r#"{"offer_id":"offer_demo_express_direct","passenger_ids":["pax_1"]}"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_refund_request_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/coach/bookings/booking_demo_express_direct/refunds")
                    .header("content-type", "application/json")
                    .header("idempotency-key", "coach-refund-test-1")
                    .body(Body::from(
                        r#"{"refund_kind":"refund_credit","reason":"customer changed plans"}"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_rebook_request_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/coach/bookings/booking_demo_express_direct/rebook_requests")
                    .header("content-type", "application/json")
                    .header("idempotency-key", "coach-rebook-test-1")
                    .body(Body::from(
                        r#"{"target_offer_id":"offer_demo_express_midday","reason":"move to midday departure"}"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_self_service_reissue_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/coach/bookings/booking_demo_express_direct/reissue")
                    .header("content-type", "application/json")
                    .header("idempotency-key", "coach-reissue-test-1")
                    .body(Body::from(
                        r#"{"target_offer_id":"offer_demo_express_evening","reason":"switch to evening departure"}"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_resolve_reissue_payment_failure_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri(
                        "/me/coach/bookings/booking_demo_express_direct/reissue/resolve_payment_failure",
                    )
                    .header("content-type", "application/json")
                    .header("idempotency-key", "coach-reissue-recovery-test-1")
                    .body(Body::from(r#"{"payment_method":"card"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_admin_overview_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/admin/overview")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_admin_finance_journal_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/admin/finance/journal")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_admin_shamell_pay_reconciliation_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/admin/finance/shamell_pay_reconciliation")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_admin_shamell_pay_report_import_create_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/coach/admin/finance/shamell_pay_reports")
                    .header("content-type", "application/json")
                    .body(Body::from(
                        r#"{"report_name":"shamell_pay_2026w15.csv","report_format":"csv","report_body":"merchant_reference,psp_status,psp_reference,settlement_reference,booked_at,description\npayoutrun_demo_1,booked,shpay_ref_1,shpay_batch_2026w15,2026-04-14T10:06:00Z,booked via Shamell Pay","dry_run":true}"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_admin_shamell_pay_release_operator_rail_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri(
                        "/me/coach/admin/finance/shamell_pay_reconciliation/payoutrun_demo_1/release_operator_rail",
                    )
                    .header("content-type", "application/json")
                    .header(
                        "idempotency-key",
                        "coach-admin-shamell-pay-release-operator-rail-1",
                    )
                    .body(Body::from(r#"{"note":"release operator rail"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_admin_shamell_pay_confirm_operator_rail_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri(
                        "/me/coach/admin/finance/shamell_pay_reconciliation/payoutrun_demo_1/confirm_operator_rail",
                    )
                    .header("content-type", "application/json")
                    .header(
                        "idempotency-key",
                        "coach-admin-shamell-pay-confirm-operator-rail-1",
                    )
                    .body(Body::from(r#"{"note":"confirm operator rail"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_admin_shamell_pay_fail_operator_rail_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri(
                        "/me/coach/admin/finance/shamell_pay_reconciliation/payoutrun_demo_1/fail_operator_rail",
                    )
                    .header("content-type", "application/json")
                    .header(
                        "idempotency-key",
                        "coach-admin-shamell-pay-fail-operator-rail-1",
                    )
                    .body(Body::from(r#"{"note":"fail operator rail"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_admin_risk_dashboard_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/admin/risk/dashboard")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_admin_risk_action_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/coach/admin/risk/risk_demo_finance/action")
                    .header("content-type", "application/json")
                    .header("idempotency-key", "coach-admin-risk-action-1")
                    .body(Body::from(r#"{"action":"acknowledge"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_admin_disruptions_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/admin/disruptions")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_admin_disruption_action_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/coach/admin/disruptions/trip_demo_express_direct/action")
                    .header("content-type", "application/json")
                    .header("idempotency-key", "coach-admin-disruption-action-1")
                    .body(Body::from(
                        r#"{"action":"mark_delayed","delay_minutes":45}"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_admin_support_cases_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/admin/support/cases")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_admin_support_case_detail_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/admin/support/cases/booking_demo_express_direct")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_admin_support_case_recovery_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri(
                        "/me/coach/admin/support/cases/booking_demo_express_direct/resolve_payment_failure",
                    )
                    .header("content-type", "application/json")
                    .header("idempotency-key", "coach-admin-support-recovery-1")
                    .body(Body::from(r#"{"payment_method":"card"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_refund_queue_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/operator/refund_queue")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_change_queue_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/operator/change_queue")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_reconciliation_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/operator/reconciliation")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_settlement_statements_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/operator/settlement_statements")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_payout_runs_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/operator/payout_runs")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_payout_reconciliation_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/operator/payout_reconciliation")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_payout_imports_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/operator/payout_imports")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_catalog_import_runs_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/operator/catalog_import_runs")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_catalog_import_run_saved_views_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/operator/catalog_import_run_saved_views")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_catalog_import_run_saved_view_delete_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri(
                        "/me/coach/operator/catalog_import_run_saved_views/catalogimportrunsavedview_demo/delete",
                    )
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from("{}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_catalog_import_run_saved_view_favorite_requires_authenticated_session()
    {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri(
                        "/me/coach/operator/catalog_import_run_saved_views/catalogimportrunsavedview_demo/favorite",
                    )
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from("{\"favorite\":true}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_catalog_import_run_saved_view_use_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri(
                        "/me/coach/operator/catalog_import_run_saved_views/catalogimportrunsavedview_demo/use",
                    )
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from("{\"used_at\":\"2026-04-13T10:00:00Z\"}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_catalog_import_run_issue_saved_views_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/operator/catalog_import_run_issue_saved_views")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_catalog_import_run_issue_saved_view_delete_requires_authenticated_session(
    ) {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri(
                        "/me/coach/operator/catalog_import_run_issue_saved_views/catalogimportrunissuesavedview_demo/delete",
                    )
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from("{}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_catalog_import_run_issue_saved_view_favorite_requires_authenticated_session(
    ) {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri(
                        "/me/coach/operator/catalog_import_run_issue_saved_views/catalogimportrunissuesavedview_demo/favorite",
                    )
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from("{\"favorite\":true}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_catalog_import_run_issue_saved_view_use_requires_authenticated_session()
    {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri(
                        "/me/coach/operator/catalog_import_run_issue_saved_views/catalogimportrunissuesavedview_demo/use",
                    )
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from("{\"used_at\":\"2026-04-13T10:00:00Z\"}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_catalog_source_artifacts_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/operator/catalog_source_artifacts")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_catalog_source_artifact_detail_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri(
                        "/me/coach/operator/catalog_source_artifacts/catalogsourceartifact_demo_failed",
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_catalog_import_run_trigger_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/coach/operator/catalog_import_runs")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from("{}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_catalog_import_run_detail_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/operator/catalog_import_runs/catalogimportrun_demo_failed")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_catalog_import_run_lineage_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/operator/catalog_import_runs/catalogimportrun_demo_failed/replays")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_catalog_import_config_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/operator/catalog_import_config")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_catalog_import_sources_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/operator/catalog_import_sources")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_catalog_import_source_upload_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/coach/operator/catalog_import_sources/upload")
                    .header(
                        "content-type",
                        "multipart/form-data; boundary=coach-catalog-upload-test",
                    )
                    .header(
                        "idempotency-key",
                        "coach-ops-catalog-import-source-upload-test-1",
                    )
                    .body(Body::from(
                        "--coach-catalog-upload-test\r\nContent-Disposition: form-data; name=\"source_kind\"\r\n\r\ngtfs\r\n--coach-catalog-upload-test--\r\n",
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_catalog_import_config_update_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/coach/operator/catalog_import_config")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from("{\"feed_locator\":\"/srv/feeds/operator_a\"}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_feed_health_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/operator/feed_health")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_payout_import_profiles_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/operator/payout_import_profiles")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_payout_import_previews_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/operator/payout_import_previews")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_payout_import_preview_saved_views_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/operator/payout_import_preview_saved_views")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_payout_import_preview_saved_view_delete_requires_authenticated_session()
    {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri(
                        "/me/coach/operator/payout_import_preview_saved_views/previewview_demo/delete",
                    )
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from("{}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_payout_import_preview_saved_view_favorite_requires_authenticated_session(
    ) {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri(
                        "/me/coach/operator/payout_import_preview_saved_views/previewview_demo/favorite",
                    )
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from("{\"favorite\":true}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_payout_import_preview_saved_view_use_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri(
                        "/me/coach/operator/payout_import_preview_saved_views/previewview_demo/use",
                    )
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from("{\"used_at\":\"2026-04-13T10:00:00Z\"}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_payout_import_preview_invalidate_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri(
                        "/me/coach/operator/payout_import_previews/previewtoken_demo_active/invalidate",
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_payout_import_batches_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/operator/payout_import_batches")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_payout_import_batch_saved_views_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/operator/payout_import_batch_saved_views")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_payout_import_batch_saved_view_delete_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri(
                        "/me/coach/operator/payout_import_batch_saved_views/payoutimportbatchview_demo/delete",
                    )
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from("{}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_payout_import_batch_saved_view_favorite_requires_authenticated_session()
    {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri(
                        "/me/coach/operator/payout_import_batch_saved_views/payoutimportbatchview_demo/favorite",
                    )
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from("{\"favorite\":true}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_payout_import_batch_saved_view_use_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri(
                        "/me/coach/operator/payout_import_batch_saved_views/payoutimportbatchview_demo/use",
                    )
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from("{\"used_at\":\"2026-04-13T10:00:00Z\"}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_payout_run_create_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/coach/operator/payout_runs")
                    .header("content-type", "application/json")
                    .header("idempotency-key", "coach-ops-payout-run-create-test-1")
                    .body(Body::from(
                        r#"{"statement_ids":["settlement_op_demo_express_2026w15"]}"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_payout_import_batch_create_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/coach/operator/payout_import_batches")
                    .header("content-type", "application/json")
                    .header("idempotency-key", "coach-ops-payout-import-batch-test-1")
                    .body(Body::from(
                        r#"{"import_source":"bank_report","report_name":"bank_report_2026w15.csv","report_format":"csv","report_body":"payout_run_id,external_status\npayoutrun_demo_1,executed"}"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_payout_import_batch_upload_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/coach/operator/payout_import_batches/upload")
                    .header(
                        "content-type",
                        "multipart/form-data; boundary=coach-upload-test",
                    )
                    .header("idempotency-key", "coach-ops-payout-import-upload-test-1")
                    .body(Body::from(
                        "--coach-upload-test\r\nContent-Disposition: form-data; name=\"import_source\"\r\n\r\nbank_report\r\n--coach-upload-test--\r\n",
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_payout_run_import_create_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/coach/operator/payout_runs/payoutrun_demo_1/imports")
                    .header("content-type", "application/json")
                    .header("idempotency-key", "coach-ops-payout-import-test-1")
                    .body(Body::from(
                        r#"{"import_source":"bank_report","external_status":"executed","payment_reference":"payout_batch_2026w15"}"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_payout_run_mark_paid_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/coach/operator/payout_runs/payoutrun_demo_1/mark_paid")
                    .header("content-type", "application/json")
                    .header("idempotency-key", "coach-ops-payout-run-paid-test-1")
                    .body(Body::from(
                        r#"{"payment_reference":"payout_batch_2026w15"}"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_payout_run_export_create_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/coach/operator/payout_runs/payoutrun_demo_1/exports")
                    .header("content-type", "application/json")
                    .header("idempotency-key", "coach-ops-payout-run-export-test-1")
                    .body(Body::from(r#"{"export_format":"csv"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_settlement_export_download_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri(
                        "/downloads/coach/settlement_exports/export_payoutrun_demo_express_csv.csv",
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_payout_import_report_download_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri(
                        "/downloads/coach/payout_import_reports/payoutreport_demo_batch_report.csv",
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_refund_review_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/coach/operator/refund_requests/refundreq_demo_1/review")
                    .header("content-type", "application/json")
                    .header("idempotency-key", "coach-ops-refund-review-test-1")
                    .body(Body::from(r#"{"decision":"approve"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_operator_change_review_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/coach/operator/change_requests/changereq_demo_1/review")
                    .header("content-type", "application/json")
                    .header("idempotency-key", "coach-ops-change-review-test-1")
                    .body(Body::from(r#"{"decision":"reject"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_crew_departures_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/crew/departures")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_crew_manifest_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/coach/crew/trips/trip_demo_express_direct/manifest")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn coach_crew_boarding_record_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/coach/crew/trips/trip_demo_express_direct/boardings")
                    .header("content-type", "application/json")
                    .header("idempotency-key", "coach-crew-boarding-test-1")
                    .body(Body::from(
                        r#"{"ticket_id":"ticket_booking_demo_express_direct_1","scan_status":"scanned","device_id":"crew_device_demo"}"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_bootstrap_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/rides/bootstrap")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_map_tile_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/rides/map_tiles/0/0/0")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_trip_live_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/rides/trips/RIDE123/live")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_trip_enter_matching_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/rides/trips/RIDE123/enter_matching")
                    .header("content-type", "application/json")
                    .body(Body::from("{}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_trip_active_stream_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/rides/trips/active/stream")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_driver_queue_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/rides/driver/queue")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_driver_dispatch_offers_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/rides/driver/dispatch_offers")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_driver_stream_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/rides/driver/stream")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_driver_dispatch_offer_accept_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/rides/driver/dispatch_offers/OFFER123/accept")
                    .header("content-type", "application/json")
                    .body(Body::from("{}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_driver_dispatch_offer_reject_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/rides/driver/dispatch_offers/OFFER123/reject")
                    .header("content-type", "application/json")
                    .body(Body::from("{}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_operator_fleet_live_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/rides/operator/fleet/live")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_driver_trip_status_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/rides/driver/trips/RIDE123/status")
                    .header("content-type", "application/json")
                    .body(Body::from(r#"{"status":"head_to_pickup"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_operator_stream_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/rides/operator/stream")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_driver_presence_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/rides/driver/presence")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_driver_presence_upsert_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/rides/driver/presence")
                    .header("content-type", "application/json")
                    .body(Body::from(r#"{"online":true}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_trip_tracking_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/rides/trips/ride_123/tracking")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_support_tickets_list_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/rides/support_tickets")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_support_ticket_create_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/rides/support_tickets")
                    .header("content-type", "application/json")
                    .body(Body::from(
                        r#"{"category":"payment_issue","body":"Need help with a fare charge."}"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_driver_finance_dashboard_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/rides/driver/finance_dashboard")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_driver_location_ping_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/rides/driver/trips/ride_123/location_ping")
                    .header("content-type", "application/json")
                    .body(Body::from(r#"{"lat":33.5138,"lon":36.2765}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_driver_shift_summary_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/rides/driver/shift_summary")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_driver_documents_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/rides/driver/documents")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_driver_document_upsert_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/rides/driver/documents")
                    .header("content-type", "application/json")
                    .body(Body::from(
                        r#"{"document_type":"insurance","document_number":"INS-1"}"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_driver_payout_request_create_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/rides/driver/payout_requests")
                    .header("content-type", "application/json")
                    .body(Body::from("{}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_operator_live_board_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/rides/operator/live_board")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_operator_driver_roster_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/rides/operator/driver_roster")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_operator_pricing_policy_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/rides/operator/pricing_policy")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_operator_pricing_policy_upsert_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/rides/operator/pricing_policy")
                    .header("content-type", "application/json")
                    .body(Body::from(
                        r#"{"ride_class":"economy","base_fare_minor_units":700,"per_km_minor_units":130,"per_minute_minor_units":35,"traffic_delay_per_minute_minor_units":18,"booking_fee_minor_units":150,"minimum_fare_minor_units":1100,"driver_share_bps":8200}"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_operator_finance_queue_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/rides/operator/finance_queue")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_operator_trip_command_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/rides/operator/trips/ride_123/commands")
                    .header("content-type", "application/json")
                    .body(Body::from(
                        r#"{"command":"cancel_trip","reason":"Operator cancelled"}"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_operator_case_queue_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/rides/operator/case_queue")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_operator_support_queue_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/rides/operator/support_queue")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_operator_document_queue_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/rides/operator/document_queue")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_operator_support_ticket_resolve_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/rides/operator/support_tickets/rst_123/resolve")
                    .header("content-type", "application/json")
                    .body(Body::from(r#"{"note":"Customer contacted and refunded."}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_operator_document_review_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/rides/operator/documents/doc_123/review")
                    .header("content-type", "application/json")
                    .body(Body::from(r#"{"decision":"approve"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_operator_payout_request_approve_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/me/rides/operator/payout_requests/req_123/approve")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn rides_pricing_preview_requires_authenticated_session() {
        let resp = session_surface_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/me/rides/pricing_preview?ride_class=economy&distance_m=1200&eta_s=240")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response_detail(resp).await.as_deref(), Some("unauthorized"));
    }

    #[tokio::test]
    async fn owners_route_rejects_unsupported_method() {
        let resp = owners_route_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::PATCH)
                    .uri("/admin/official_accounts/shamell_pay/owners")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::METHOD_NOT_ALLOWED);
    }

    #[tokio::test]
    async fn owners_route_forbidden_when_scope_missing() {
        let resp = owners_route_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/admin/official_accounts/shamell_pay/owners")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_updates")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::FORBIDDEN);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official owner scope required")
        );
    }

    #[tokio::test]
    async fn owners_route_returns_not_found_when_official_missing() {
        let resp = owners_route_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/admin/official_accounts/shamell_pay/owners")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_pay")
                    .header("x-test-official-exists", "0")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official account not found")
        );
    }

    #[tokio::test]
    async fn owners_route_filters_upstream_roles_and_minimizes_response() {
        let (base_url, server) = spawn_payments_roles_stub(
            StatusCode::OK,
            json!([
                {
                    "id": "role-1",
                    "account_id": "acct_1",
                    "phone": "+963111111111",
                    "role": "official_owner:shamell_pay",
                    "created_at": "2026-03-15T00:00:00Z",
                    "unexpected": "secret"
                },
                {
                    "id": "role-2",
                    "account_id": "acct_2",
                    "phone": "+963222222222",
                    "role": "official_owner:shamell_updates",
                    "created_at": "2026-03-15T00:00:00Z"
                },
                {
                    "id": "role-3",
                    "account_id": "",
                    "phone": "",
                    "role": "official_owner:shamell_pay",
                    "created_at": "2026-03-15T00:00:00Z"
                }
            ]),
        )
        .await;
        let mut state = owners_route_test_state_no_auth();
        state.payments_base_url = base_url;
        let app = Router::new()
            .route(
                "/admin/official_accounts/:account_id/owners",
                get(auth::admin_official_account_owners_list),
            )
            .with_state(state);

        let resp = app
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/admin/official_accounts/shamell_pay/owners")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_pay")
                    .header("x-test-official-exists", "1")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        server.abort();

        assert_eq!(resp.status(), StatusCode::OK);
        let body = to_bytes(resp.into_body(), 1024 * 1024).await.unwrap();
        let decoded: Value = serde_json::from_slice(&body).unwrap();
        let owners = decoded["owners"].as_array().expect("owners array");
        assert_eq!(owners.len(), 1);
        assert_eq!(owners[0]["account_id"], "acct_1");
        assert_eq!(owners[0]["phone"], "+963111111111");
        assert_eq!(owners[0]["created_at"], "2026-03-15T00:00:00Z");
        assert!(owners[0].get("id").is_none());
        assert!(owners[0].get("role").is_none());
        assert!(owners[0].get("unexpected").is_none());
    }

    #[tokio::test]
    async fn owners_route_add_forbidden_when_scope_missing() {
        let resp = owners_route_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/admin/official_accounts/shamell_pay/owners")
                    .header(header::CONTENT_TYPE, "application/json")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_updates")
                    .body(Body::from("{}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::FORBIDDEN);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official owner scope required")
        );
    }

    #[tokio::test]
    async fn owners_route_remove_forbidden_when_scope_missing() {
        let resp = owners_route_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::DELETE)
                    .uri("/admin/official_accounts/shamell_pay/owners")
                    .header(header::CONTENT_TYPE, "application/json")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_updates")
                    .body(Body::from("{}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::FORBIDDEN);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official owner scope required")
        );
    }

    #[tokio::test]
    async fn owners_route_add_returns_not_found_when_official_missing() {
        let resp = owners_route_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/admin/official_accounts/shamell_pay/owners")
                    .header(header::CONTENT_TYPE, "application/json")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_pay")
                    .header("x-test-official-exists", "0")
                    .body(Body::from("{}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official account not found")
        );
    }

    #[tokio::test]
    async fn owners_route_remove_returns_not_found_when_official_missing() {
        let resp = owners_route_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::DELETE)
                    .uri("/admin/official_accounts/shamell_pay/owners")
                    .header(header::CONTENT_TYPE, "application/json")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_pay")
                    .header("x-test-official-exists", "0")
                    .body(Body::from("{}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official account not found")
        );
    }

    #[tokio::test]
    async fn auto_replies_list_forbidden_when_scope_missing() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/admin/official_accounts/shamell_pay/auto_replies")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_updates")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::FORBIDDEN);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official owner scope required")
        );
    }

    #[tokio::test]
    async fn auto_replies_list_returns_not_found_when_official_missing() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/admin/official_accounts/shamell_pay/auto_replies")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_pay")
                    .header("x-test-official-exists", "0")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official account not found")
        );
    }

    #[tokio::test]
    async fn official_moments_stats_forbidden_when_scope_missing() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/admin/official_accounts/shamell_pay/moments_stats")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_updates")
                    .header("x-test-official-exists", "1")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::FORBIDDEN);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official owner scope required")
        );
    }

    #[tokio::test]
    async fn official_moments_stats_returns_not_found_when_official_missing() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/admin/official_accounts/shamell_pay/moments_stats")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_pay")
                    .header("x-test-official-exists", "0")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official account not found")
        );
    }

    #[tokio::test]
    async fn official_account_patch_forbidden_when_scope_missing() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::PATCH)
                    .uri("/admin/official_accounts/shamell_pay")
                    .header(header::CONTENT_TYPE, "application/json")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_updates")
                    .body(Body::from(r#"{}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::FORBIDDEN);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official owner scope required")
        );
    }

    #[tokio::test]
    async fn official_account_patch_returns_not_found_when_official_missing() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::PATCH)
                    .uri("/admin/official_accounts/shamell_pay")
                    .header(header::CONTENT_TYPE, "application/json")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_pay")
                    .header("x-test-official-exists", "0")
                    .body(Body::from(r#"{}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official account not found")
        );
    }

    #[tokio::test]
    async fn official_account_patch_rejects_invalid_website_url_before_auth_runtime() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::PATCH)
                    .uri("/admin/official_accounts/shamell_pay")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(r#"{"website_url":"javascript:alert(1)"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("invalid website_url")
        );
    }

    #[tokio::test]
    async fn official_account_patch_rejects_invalid_qr_payload_before_auth_runtime() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::PATCH)
                    .uri("/admin/official_accounts/shamell_pay")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(r#"{"qr_payload":"bad\u0000payload"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("invalid qr_payload")
        );
    }

    #[tokio::test]
    async fn official_feeds_create_rejects_invalid_thumb_url_before_auth_runtime() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/admin/official_feeds")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(
                        r#"{"account_id":"shamell_pay","id":"promo_1","snippet":"hello","thumb_url":"data:image/png;base64,AAAA"}"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("invalid thumb_url")
        );
    }

    #[tokio::test]
    async fn auto_replies_create_forbidden_when_scope_missing() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/admin/official_accounts/shamell_pay/auto_replies")
                    .header(header::CONTENT_TYPE, "application/json")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_updates")
                    .body(Body::from(r#"{"kind":"welcome","text":"hi"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::FORBIDDEN);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official owner scope required")
        );
    }

    #[tokio::test]
    async fn auto_replies_create_returns_not_found_when_official_missing() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/admin/official_accounts/shamell_pay/auto_replies")
                    .header(header::CONTENT_TYPE, "application/json")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_pay")
                    .header("x-test-official-exists", "0")
                    .body(Body::from(r#"{"kind":"welcome","text":"hi"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official account not found")
        );
    }

    #[tokio::test]
    async fn service_inbox_list_forbidden_when_scope_missing() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/admin/official_accounts/shamell_pay/service_inbox")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_updates")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::FORBIDDEN);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official owner scope required")
        );
    }

    #[tokio::test]
    async fn service_inbox_list_returns_not_found_when_official_missing() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/admin/official_accounts/shamell_pay/service_inbox")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_pay")
                    .header("x-test-official-exists", "0")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official account not found")
        );
    }

    #[tokio::test]
    async fn service_inbox_mark_read_forbidden_when_scope_missing() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/admin/official_accounts/shamell_pay/service_inbox/1/mark_read")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_updates")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::FORBIDDEN);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official owner scope required")
        );
    }

    #[tokio::test]
    async fn service_inbox_mark_read_returns_not_found_when_official_missing() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/admin/official_accounts/shamell_pay/service_inbox/1/mark_read")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_pay")
                    .header("x-test-official-exists", "0")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official account not found")
        );
    }

    #[tokio::test]
    async fn service_inbox_close_forbidden_when_scope_missing() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/admin/official_accounts/shamell_pay/service_inbox/1/close")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_updates")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::FORBIDDEN);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official owner scope required")
        );
    }

    #[tokio::test]
    async fn service_inbox_close_returns_not_found_when_official_missing() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/admin/official_accounts/shamell_pay/service_inbox/1/close")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_pay")
                    .header("x-test-official-exists", "0")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official account not found")
        );
    }

    #[tokio::test]
    async fn service_inbox_template_message_forbidden_when_scope_missing() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/admin/official_accounts/shamell_pay/service_inbox/1/template_messages")
                    .header(header::CONTENT_TYPE, "application/json")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_updates")
                    .body(Body::from(r#"{"title":"Hello","body":"Template body"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::FORBIDDEN);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official owner scope required")
        );
    }

    #[tokio::test]
    async fn service_inbox_template_message_returns_not_found_when_official_missing() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/admin/official_accounts/shamell_pay/service_inbox/1/template_messages")
                    .header(header::CONTENT_TYPE, "application/json")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_pay")
                    .header("x-test-official-exists", "0")
                    .body(Body::from(r#"{"title":"Hello","body":"Template body"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official account not found")
        );
    }

    #[tokio::test]
    async fn auto_reply_patch_rejects_invalid_rule_id_with_400() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::PATCH)
                    .uri("/admin/official_auto_replies/not-a-number")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(r#"{"text":"patched"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("rule id invalid")
        );
    }

    #[tokio::test]
    async fn auto_reply_patch_forbidden_when_scope_missing() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::PATCH)
                    .uri("/admin/official_auto_replies/9")
                    .header(header::CONTENT_TYPE, "application/json")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_updates")
                    .header("x-test-auto-reply-exists", "1")
                    .header("x-test-auto-reply-account-id", "shamell_pay")
                    .body(Body::from(r#"{"text":"patched"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::FORBIDDEN);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official owner scope required")
        );
    }

    #[tokio::test]
    async fn auto_reply_patch_returns_not_found_when_rule_missing() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::PATCH)
                    .uri("/admin/official_auto_replies/9")
                    .header(header::CONTENT_TYPE, "application/json")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_pay")
                    .header("x-test-auto-reply-exists", "0")
                    .body(Body::from(r#"{"text":"patched"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("auto reply not found")
        );
    }

    #[tokio::test]
    async fn auto_replies_list_rejects_invalid_account_id_with_400() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/admin/official_accounts/bad%2Fid/auto_replies")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official account id invalid")
        );
    }

    #[tokio::test]
    async fn auto_replies_create_rejects_invalid_account_id_with_400() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/admin/official_accounts/bad%2Fid/auto_replies")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(r#"{"kind":"welcome","text":"hi"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official account id invalid")
        );
    }

    #[tokio::test]
    async fn service_inbox_list_rejects_invalid_account_id_with_400() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::GET)
                    .uri("/admin/official_accounts/bad%2Fid/service_inbox")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("official account id invalid")
        );
    }

    #[tokio::test]
    async fn service_inbox_mark_read_rejects_invalid_session_id_with_400() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/admin/official_accounts/shamell_pay/service_inbox/nope/mark_read")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("session id invalid")
        );
    }

    #[tokio::test]
    async fn service_inbox_close_rejects_invalid_session_id_with_400() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/admin/official_accounts/shamell_pay/service_inbox/nope/close")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("session id invalid")
        );
    }

    #[tokio::test]
    async fn service_inbox_template_message_rejects_invalid_session_id_with_400() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri(
                        "/admin/official_accounts/shamell_pay/service_inbox/nope/template_messages",
                    )
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(r#"{"title":"Hello","body":"Template body"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("session id invalid")
        );
    }

    #[tokio::test]
    async fn service_inbox_template_message_requires_title() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/admin/official_accounts/shamell_pay/service_inbox/1/template_messages")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(r#"{"body":"Template body"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("title required")
        );
    }

    #[tokio::test]
    async fn service_inbox_template_message_requires_body() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/admin/official_accounts/shamell_pay/service_inbox/1/template_messages")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(r#"{"title":"Hello"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("body required")
        );
    }

    #[tokio::test]
    async fn service_inbox_template_message_rejects_title_too_long() {
        let long_title = "x".repeat(181);
        let payload = format!(r#"{{"title":"{long_title}","body":"Template body"}}"#);
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/admin/official_accounts/shamell_pay/service_inbox/1/template_messages")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(payload))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("title too long")
        );
    }

    #[tokio::test]
    async fn service_inbox_template_message_rejects_body_too_long() {
        let long_body = "x".repeat(4001);
        let payload = format!(r#"{{"title":"Hello","body":"{long_body}"}}"#);
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/admin/official_accounts/shamell_pay/service_inbox/1/template_messages")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(payload))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("body too long")
        );
    }

    #[tokio::test]
    async fn owners_route_add_requires_account_or_phone() {
        let resp = owners_route_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/admin/official_accounts/shamell_pay/owners")
                    .header(header::CONTENT_TYPE, "application/json")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_pay")
                    .header("x-test-official-exists", "1")
                    .body(Body::from("{}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("account_id or phone required")
        );
    }

    #[tokio::test]
    async fn owners_route_remove_requires_account_or_phone() {
        let resp = owners_route_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::DELETE)
                    .uri("/admin/official_accounts/shamell_pay/owners")
                    .header(header::CONTENT_TYPE, "application/json")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_pay")
                    .header("x-test-official-exists", "1")
                    .body(Body::from("{}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("account_id or phone required")
        );
    }

    #[tokio::test]
    async fn auto_reply_patch_requires_keyword_for_keyword_kind() {
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::PATCH)
                    .uri("/admin/official_auto_replies/9")
                    .header(header::CONTENT_TYPE, "application/json")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_pay")
                    .header("x-test-auto-reply-exists", "1")
                    .header("x-test-auto-reply-account-id", "shamell_pay")
                    .body(Body::from(r#"{"kind":"keyword","text":"patched"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("keyword required for keyword rule")
        );
    }

    #[tokio::test]
    async fn auto_reply_patch_rejects_text_too_long() {
        let long_text = "x".repeat(4001);
        let payload = format!(r#"{{"text":"{long_text}"}}"#);
        let resp = official_admin_test_app_no_auth()
            .oneshot(
                Request::builder()
                    .method(Method::PATCH)
                    .uri("/admin/official_auto_replies/9")
                    .header(header::CONTENT_TYPE, "application/json")
                    .header("x-test-account-id", "acct_test_1")
                    .header("x-test-roles", "official_owner:shamell_pay")
                    .header("x-test-auto-reply-exists", "1")
                    .header("x-test-auto-reply-account-id", "shamell_pay")
                    .body(Body::from(payload))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
        assert_eq!(
            response_detail(resp).await.as_deref(),
            Some("text too long")
        );
    }
}
