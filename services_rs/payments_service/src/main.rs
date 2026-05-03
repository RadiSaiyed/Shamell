use axum::extract::MatchedPath;
use axum::extract::Request;
use axum::http::{header, header::HeaderName, Method, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::Router;
use sha2::{Digest, Sha256};
use shamell_common::host_guard::AllowedHostsLayer;
use shamell_common::internal_auth::InternalAuthLayer;
use shamell_common::internal_identity::InternalIdentityVerifier;
use shamell_common::request_id::RequestIdLayer;
use shamell_common::security_headers::SecurityHeadersLayer;
use shamell_payments_service::{config::Config, db, handlers, state::AppState};
use std::{net::SocketAddr, time::Duration};
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
    if cfg.allow_emergency_direct_topup {
        tracing::warn!(
            security_event = "payments_emergency_direct_topup",
            outcome = "enabled",
            env = %cfg.env_name,
            "payments emergency direct topup is enabled"
        );
    }

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
            "payments schema check failed"
        );
        std::process::exit(2);
    }

    let state = AppState {
        pool,
        db_schema: cfg.db_schema.clone(),
        env_name: cfg.env_name.clone(),
        default_currency: cfg.default_currency.clone(),
        allow_direct_topup: cfg.allow_direct_topup,
        allow_emergency_direct_topup: cfg.allow_emergency_direct_topup,
        require_idempotency_key: cfg.require_idempotency_key,
        merchant_fee_bps: cfg.merchant_fee_bps,
        fee_wallet_account_id: cfg.fee_wallet_account_id.clone(),
        fee_wallet_phone: cfg.fee_wallet_phone.clone(),
        admin_credit_max_amount_cents: cfg.admin_credit_max_amount_cents,
        admin_credit_operator_daily_limit_cents: cfg.admin_credit_operator_daily_limit_cents,
        admin_credit_approval_threshold_cents: cfg.admin_credit_approval_threshold_cents,
    };

    let fee_wallet_result = if cfg.auto_provision_fee_wallet {
        handlers::ensure_fee_wallet(&state).await
    } else {
        handlers::assert_fee_wallet_ready(&state).await
    };
    if let Err(e) = fee_wallet_result {
        tracing::error!(
            error = ?e,
            auto_provision_fee_wallet = cfg.auto_provision_fee_wallet,
            "failed fee wallet startup check"
        );
        std::process::exit(2);
    }

    {
        let st = state.clone();
        tokio::spawn(async move {
            let mut interval =
                tokio::time::interval(Duration::from_secs(RATE_LIMIT_CLEANUP_INTERVAL_SECS));
            interval.set_missed_tick_behavior(MissedTickBehavior::Skip);
            loop {
                interval.tick().await;
                if let Err(err) = handlers::cleanup_admin_rate_limits(&st).await {
                    tracing::error!(
                        error = ?err,
                        "payments rate-limit cleanup background task failed"
                    );
                }
                if let Err(err) = handlers::cleanup_idempotency_keys(&st).await {
                    tracing::error!(
                        error = ?err,
                        "payments idempotency cleanup background task failed"
                    );
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
            .with_expected_audience("payments")
            .with_body_limit(cfg.max_body_bytes);
    if let Some(verifier) = internal_identity_verifier {
        internal = internal
            .with_identity_verifier(verifier)
            .with_require_identity_v2(cfg.require_internal_identity_v2)
            .with_legacy_secret_fallback(cfg.allow_legacy_internal_secret_fallback);
    }

    let bff_only = Router::new()
        .route(
            "/users",
            get(handlers::get_user).post(handlers::create_user),
        )
        .route("/transfer", post(handlers::transfer))
        .route("/wallets/:wallet_id", get(handlers::get_wallet))
        .route(
            "/wallets/:wallet_id/buckets",
            get(handlers::get_wallet_buckets),
        )
        .route(
            "/wallets/:wallet_id/driver-ledger",
            get(handlers::get_driver_wallet_ledger),
        )
        .route(
            "/driver-ride-fee-holds",
            get(handlers::list_driver_ride_fee_holds),
        )
        .route(
            "/wallets/:wallet_id/driver-ride-fee",
            post(handlers::mutate_driver_ride_fee_hold),
        )
        .route(
            "/wallets/:wallet_id/snapshot",
            get(handlers::wallet_snapshot),
        )
        .route(
            "/wallets/:wallet_id/statement",
            get(handlers::wallet_snapshot),
        )
        .route("/wallets/:wallet_id/limits", get(handlers::wallet_limits))
        .route(
            "/wallets/:wallet_id/holds",
            get(handlers::list_wallet_holds).post(handlers::create_wallet_hold),
        )
        .route(
            "/holds/:hold_id/resolve",
            post(handlers::resolve_wallet_hold),
        )
        .route("/wallets/:wallet_id/topup", post(handlers::topup))
        .route(
            "/exchange/quotes",
            get(handlers::list_exchange_quotes).post(handlers::create_exchange_quote),
        )
        .route(
            "/exchange/quotes/:quote_id/execute",
            post(handlers::execute_exchange_quote),
        )
        .route(
            "/payment-links",
            get(handlers::list_payment_links).post(handlers::create_payment_link),
        )
        .route("/payment-links/:link_id", get(handlers::get_payment_link))
        .route(
            "/payment-links/:link_id/pay",
            post(handlers::pay_payment_link),
        )
        .route(
            "/refunds",
            get(handlers::list_refunds).post(handlers::create_refund),
        )
        .route(
            "/refunds/:refund_id/resolve",
            post(handlers::resolve_refund),
        )
        .route(
            "/recurring",
            get(handlers::list_recurring_payments).post(handlers::create_recurring_payment),
        )
        .route(
            "/recurring/:recurring_id/cancel",
            post(handlers::cancel_recurring_payment),
        )
        .route(
            "/merchant/profiles",
            post(handlers::upsert_merchant_profile),
        )
        .route(
            "/merchant/profiles/:wallet_id",
            get(handlers::get_merchant_profile),
        )
        .route(
            "/mini/payment-intents",
            post(handlers::create_mini_payment_intent),
        )
        .route(
            "/mini/payment-intents/:intent_id",
            get(handlers::get_mini_payment_intent),
        )
        .route(
            "/mini/payment-intents/:intent_id/confirm",
            post(handlers::confirm_mini_payment_intent),
        )
        .route(
            "/merchant/webhooks",
            get(handlers::list_merchant_webhooks).post(handlers::create_merchant_webhook),
        )
        .route(
            "/merchant/settlements",
            get(handlers::list_merchant_settlements).post(handlers::create_merchant_settlement),
        )
        .route(
            "/merchant/settlements/:settlement_id/resolve",
            post(handlers::resolve_merchant_settlement),
        )
        .route(
            "/disputes",
            get(handlers::list_payment_disputes).post(handlers::create_payment_dispute),
        )
        .route(
            "/aliases",
            get(handlers::list_wallet_aliases).post(handlers::upsert_wallet_alias),
        )
        .route(
            "/kyc/documents",
            get(handlers::list_kyc_documents).post(handlers::create_kyc_document),
        )
        .route(
            "/fx/rates",
            get(handlers::list_fx_rates).post(handlers::upsert_fx_rate),
        )
        .route(
            "/offline-payments",
            get(handlers::list_offline_payments).post(handlers::submit_offline_payment),
        )
        .route("/events", get(handlers::list_payment_events))
        .route("/admin/risk/metrics", get(handlers::risk_metrics))
        .route(
            "/admin/risk/rules",
            get(handlers::list_risk_rules).post(handlers::create_risk_rule),
        )
        .route("/admin/risk/evaluate", post(handlers::evaluate_risk_rules))
        .route(
            "/admin/reconciliation",
            get(handlers::ledger_reconciliation),
        )
        .route("/admin/audit/timeline", get(handlers::audit_timeline))
        .route("/admin/recurring/run", post(handlers::run_recurring_due))
        .route(
            "/admin/wallet-controls",
            post(handlers::upsert_wallet_control),
        )
        .route("/admin/kyc", post(handlers::update_kyc))
        .route(
            "/admin/credits",
            get(handlers::list_admin_credits).post(handlers::admin_credit),
        )
        .route(
            "/admin/credits/metrics",
            get(handlers::admin_credit_metrics),
        )
        .route(
            "/admin/credits/reconciliation",
            get(handlers::admin_credit_reconciliation),
        )
        .route(
            "/admin/credits/:request_id/approve",
            post(handlers::admin_credit_approve),
        )
        .route(
            "/favorites",
            post(handlers::create_favorite).get(handlers::list_favorites),
        )
        .route(
            "/favorites/:fid",
            get(handlers::get_favorite).delete(handlers::delete_favorite),
        )
        .route(
            "/requests",
            post(handlers::create_request).get(handlers::list_requests),
        )
        .route("/requests/:rid", get(handlers::get_request))
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
        .merge(bff_authed)
        // Ensure unknown routes return 404, not auth middleware fallback details.
        .fallback(|| async { StatusCode::NOT_FOUND })
        .with_state(state)
        .layer(cors)
        .layer(RequestBodyLimitLayer::new(cfg.max_body_bytes))
        .layer(AllowedHostsLayer::new(cfg.allowed_hosts.clone()))
        .layer(SecurityHeadersLayer::from_env(&cfg.env_name))
        // Avoid logging sensitive identifiers in raw fallback paths. Keep matched route
        // templates for observability and hash unmatched paths instead.
        .layer(TraceLayer::new_for_http().make_span_with(http_request_span))
        .layer(RequestIdLayer::new(HeaderName::from_static("x-request-id")));

    let addr: SocketAddr = format!("{}:{}", cfg.host, cfg.port)
        .parse()
        .unwrap_or_else(|_| SocketAddr::from(([0, 0, 0, 0], cfg.port)));
    tracing::info!(%addr, "starting shamell_payments_service");

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
