use axum::body::Body;
use axum::http::{header::HeaderName, Request, StatusCode};
use axum::routing::get;
use axum::Router;
use shamell_common::internal_auth::InternalAuthLayer;
use shamell_common::request_id::RequestIdLayer;
use tower::ServiceExt;

#[tokio::test]
async fn internal_auth_not_required_allows_request() {
    let app = Router::new()
        .route("/x", get(|| async { "ok" }))
        .layer(InternalAuthLayer::new(false, None));

    let resp = app
        .oneshot(Request::builder().uri("/x").body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);
}

#[tokio::test]
async fn internal_auth_required_without_secret_is_503() {
    let app = Router::new()
        .route("/x", get(|| async { "ok" }))
        .layer(InternalAuthLayer::new(true, None));

    let resp = app
        .oneshot(Request::builder().uri("/x").body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::SERVICE_UNAVAILABLE);
}

#[tokio::test]
async fn internal_auth_required_missing_or_wrong_header_is_401() {
    let app = Router::new()
        .route("/x", get(|| async { "ok" }))
        .layer(InternalAuthLayer::new(true, Some("secret".to_string())));

    // Missing header
    let resp = app
        .clone()
        .oneshot(Request::builder().uri("/x").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);

    // Wrong header
    let resp = app
        .oneshot(
            Request::builder()
                .uri("/x")
                .header("x-internal-secret", "nope")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn internal_auth_required_correct_header_is_200() {
    let app = Router::new()
        .route("/x", get(|| async { "ok" }))
        .layer(InternalAuthLayer::new(true, Some("secret".to_string())));

    let resp = app
        .oneshot(
            Request::builder()
                .uri("/x")
                .header("x-internal-secret", "secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);
}

#[tokio::test]
async fn internal_auth_allowed_callers_enforced() {
    let app = Router::new().route("/x", get(|| async { "ok" })).layer(
        InternalAuthLayer::new(true, Some("secret".to_string()))
            .with_allowed_callers(vec!["bff".to_string()]),
    );

    // Missing caller id
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/x")
                .header("x-internal-secret", "secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);

    // Wrong caller id
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/x")
                .header("x-internal-secret", "secret")
                .header("x-internal-service-id", "bus")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);

    // Allowed caller id (case-insensitive)
    let resp = app
        .oneshot(
            Request::builder()
                .uri("/x")
                .header("x-internal-secret", "secret")
                .header("x-internal-service-id", "BFF")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
}

#[tokio::test]
async fn request_id_sets_header_when_missing() {
    let app = Router::new()
        .route("/x", get(|| async { "ok" }))
        .layer(RequestIdLayer::new(HeaderName::from_static("x-request-id")));

    let resp = app
        .oneshot(Request::builder().uri("/x").body(Body::empty()).unwrap())
        .await
        .unwrap();

    let rid = resp
        .headers()
        .get("x-request-id")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");
    assert_eq!(rid.len(), 32);
    assert!(rid.chars().all(|c| c.is_ascii_hexdigit()));
}

#[tokio::test]
async fn request_id_preserves_existing_header() {
    let app = Router::new()
        .route("/x", get(|| async { "ok" }))
        .layer(RequestIdLayer::new(HeaderName::from_static("x-request-id")));

    let resp = app
        .oneshot(
            Request::builder()
                .uri("/x")
                .header("x-request-id", "abc")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    let rid = resp
        .headers()
        .get("x-request-id")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");
    assert_eq!(rid, "abc");
}
