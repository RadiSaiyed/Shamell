use crate::auth;
use crate::state::AppState;
use axum::body::Body;
use axum::extract::State;
use axum::http::{HeaderMap, Request, StatusCode};
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use serde::Serialize;
use std::collections::HashSet;
use subtle::ConstantTimeEq;

#[derive(Serialize)]
struct ErrorBody<'a> {
    detail: &'a str,
}

fn role_headers_trusted(state: &AppState, headers: &HeaderMap) -> bool {
    let configured_auth_token = state
        .role_header_secret
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());

    let Some(expected_auth_token) = configured_auth_token else {
        return false;
    };

    let provided = headers
        .get("x-role-auth")
        .and_then(|v| v.to_str().ok())
        .map(str::trim)
        .unwrap_or("");
    if provided.is_empty() {
        return false;
    }
    provided
        .as_bytes()
        .ct_eq(expected_auth_token.as_bytes())
        .unwrap_u8()
        == 1
}

fn parse_roles(state: &AppState, headers: &HeaderMap) -> HashSet<String> {
    let mut out = HashSet::new();
    if !role_headers_trusted(state, headers) {
        return out;
    }
    for h in ["x-auth-roles", "x-roles"] {
        let Some(v) = headers.get(h) else {
            continue;
        };
        let Ok(raw) = v.to_str() else {
            continue;
        };
        for role in raw.split(',') {
            let role = role.trim().to_ascii_lowercase();
            if !role.is_empty() {
                out.insert(role);
            }
        }
    }
    out
}

pub(crate) fn trusted_roles(state: &AppState, headers: &HeaderMap) -> HashSet<String> {
    parse_roles(state, headers)
}

fn forbidden(detail: &'static str) -> Response {
    let body = axum::Json(ErrorBody { detail });
    (StatusCode::FORBIDDEN, body).into_response()
}

fn unauthorized(detail: &'static str) -> Response {
    let body = axum::Json(ErrorBody { detail });
    (StatusCode::UNAUTHORIZED, body).into_response()
}

pub async fn require_admin(
    State(state): State<AppState>,
    req: Request<Body>,
    next: Next,
) -> Response {
    if !state.enforce_route_authz {
        return next.run(req).await;
    }
    if auth::require_session_account_id(&state, req.headers())
        .await
        .is_err()
    {
        return unauthorized("auth session required");
    }
    let roles = trusted_roles(&state, req.headers());
    if roles.contains("admin") || roles.contains("superadmin") {
        return next.run(req).await;
    }
    forbidden("admin role required")
}

pub async fn require_operator_bus(
    State(state): State<AppState>,
    req: Request<Body>,
    next: Next,
) -> Response {
    if !state.enforce_route_authz {
        return next.run(req).await;
    }
    if auth::require_session_account_id(&state, req.headers())
        .await
        .is_err()
    {
        return unauthorized("auth session required");
    }
    let roles = trusted_roles(&state, req.headers());
    if roles.contains("operator_bus") || roles.contains("admin") || roles.contains("superadmin") {
        return next.run(req).await;
    }
    forbidden("operator_bus role required")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::state::AppState;
    use axum::http::{HeaderValue, Request, StatusCode};
    use axum::middleware::from_fn_with_state;
    use axum::routing::get;
    use axum::Router;
    use reqwest::Client;
    use tower::ServiceExt;

    fn state(
        enforce_route_authz: bool,
        env_name: &str,
        role_header_secret: Option<&str>,
    ) -> AppState {
        AppState {
            env_name: env_name.to_string(),
            payments_base_url: "http://127.0.0.1".to_string(),
            payments_internal_secret: None,
            chat_base_url: "http://127.0.0.1".to_string(),
            chat_internal_secret: None,
            bus_base_url: "http://127.0.0.1".to_string(),
            bus_internal_secret: None,
            internal_service_id: "bff".to_string(),
            enforce_route_authz,
            role_header_secret: role_header_secret.map(ToString::to_string),
            max_upstream_body_bytes: 1024 * 1024,
            expose_upstream_errors: true,
            accept_legacy_session_cookie: false,
            auth_device_login_web_enabled: false,
            http: Client::new(),
            auth: None,
        }
    }

    async fn ok_handler() -> &'static str {
        "ok"
    }

    #[tokio::test]
    async fn admin_guard_allows_when_disabled() {
        let st = state(false, "test", None);
        let app = Router::new()
            .route("/x", get(ok_handler))
            .layer(from_fn_with_state(st.clone(), require_admin))
            .with_state(st);

        let resp = app
            .oneshot(Request::builder().uri("/x").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn admin_guard_blocks_without_role() {
        let st = state(true, "test", None);
        let app = Router::new()
            .route("/x", get(ok_handler))
            .layer(from_fn_with_state(st.clone(), require_admin))
            .with_state(st);

        let resp = app
            .oneshot(Request::builder().uri("/x").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn admin_guard_requires_auth_session_even_with_admin_role() {
        let st = state(true, "test", None);
        let app = Router::new()
            .route("/x", get(ok_handler))
            .layer(from_fn_with_state(st.clone(), require_admin))
            .with_state(st);

        let mut req = Request::builder().uri("/x").body(Body::empty()).unwrap();
        req.headers_mut()
            .insert("x-auth-roles", HeaderValue::from_static("seller,Admin,ops"));

        let resp = app.oneshot(req).await.unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn operator_guard_requires_auth_session_even_with_operator_role() {
        let st = state(true, "test", None);
        let app = Router::new()
            .route("/x", get(ok_handler))
            .layer(from_fn_with_state(st.clone(), require_operator_bus))
            .with_state(st);

        let mut req = Request::builder().uri("/x").body(Body::empty()).unwrap();
        req.headers_mut()
            .insert("x-auth-roles", HeaderValue::from_static("operator_bus"));

        let resp = app.oneshot(req).await.unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn role_secret_is_still_required_when_session_missing() {
        let st = state(true, "test", Some("edge-secret"));
        let app = Router::new()
            .route("/x", get(ok_handler))
            .layer(from_fn_with_state(st.clone(), require_admin))
            .with_state(st);

        let mut no_secret = Request::builder().uri("/x").body(Body::empty()).unwrap();
        no_secret
            .headers_mut()
            .insert("x-auth-roles", HeaderValue::from_static("admin"));
        let resp = app.clone().oneshot(no_secret).await.unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);

        let mut bad_secret = Request::builder().uri("/x").body(Body::empty()).unwrap();
        bad_secret
            .headers_mut()
            .insert("x-auth-roles", HeaderValue::from_static("admin"));
        bad_secret
            .headers_mut()
            .insert("x-role-auth", HeaderValue::from_static("wrong"));
        let resp = app.clone().oneshot(bad_secret).await.unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);

        let mut good = Request::builder().uri("/x").body(Body::empty()).unwrap();
        good.headers_mut()
            .insert("x-auth-roles", HeaderValue::from_static("admin"));
        good.headers_mut()
            .insert("x-role-auth", HeaderValue::from_static("edge-secret"));
        let resp = app.oneshot(good).await.unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
    }

    #[test]
    fn parse_roles_requires_role_secret_when_configured() {
        let st = state(true, "test", Some("edge-secret"));
        let mut headers = HeaderMap::new();
        headers.insert(
            "x-auth-roles",
            HeaderValue::from_static("admin,operator_bus"),
        );
        let empty = parse_roles(&st, &headers);
        assert!(empty.is_empty());

        headers.insert("x-role-auth", HeaderValue::from_static("wrong"));
        let wrong = parse_roles(&st, &headers);
        assert!(wrong.is_empty());

        headers.insert("x-role-auth", HeaderValue::from_static("edge-secret"));
        let ok = parse_roles(&st, &headers);
        assert!(ok.contains("admin"));
        assert!(ok.contains("operator_bus"));
    }

    #[test]
    fn parse_roles_never_trusts_without_configured_secret() {
        let st = state(true, "dev", None);
        let mut headers = HeaderMap::new();
        headers.insert("x-auth-roles", HeaderValue::from_static("admin"));
        headers.insert("x-role-auth", HeaderValue::from_static("any-value"));

        let parsed = parse_roles(&st, &headers);
        assert!(parsed.is_empty());
    }
}
