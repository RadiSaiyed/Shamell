use axum::body::Body;
use axum::http::{header::HeaderName, Request, StatusCode};
use axum::routing::get;
use axum::Router;
use shamell_common::internal_auth::InternalAuthLayer;
use shamell_common::internal_identity::{
    InternalIdentityVerifier, InternalRequestSigner, INTERNAL_IDENTITY_AUDIENCE_HEADER,
    INTERNAL_IDENTITY_NONCE_HEADER, INTERNAL_IDENTITY_SIG_HEADER, INTERNAL_IDENTITY_SIG_V2_HEADER,
    INTERNAL_IDENTITY_TS_HEADER, INTERNAL_SERVICE_ID_HEADER,
};
use shamell_common::request_id::RequestIdLayer;
use tower::ServiceExt;

const TEST_AUDIENCE: &str = "chat";

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
                .header("x-internal-service-id", "payments")
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
async fn internal_identity_accepts_signed_request_without_secret() {
    let signer = InternalRequestSigner::from_seed_bytes("bff", [7u8; 32]).expect("signer");
    let verifier = InternalIdentityVerifier::from_public_keys_base64(
        vec![("bff".to_string(), signer.public_key_base64())],
        30,
    )
    .expect("verifier");
    let signed = signer
        .sign(
            &axum::http::Method::POST,
            TEST_AUDIENCE,
            "/x",
            br#"{"ok":true}"#,
        )
        .expect("signature");
    let app = Router::new()
        .route("/x", get(|| async { "ok" }).post(|| async { "ok" }))
        .layer(
            InternalAuthLayer::new(true, None)
                .with_expected_audience(TEST_AUDIENCE)
                .with_identity_verifier(verifier)
                .with_legacy_secret_fallback(false),
        );

    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/x")
                .header(INTERNAL_SERVICE_ID_HEADER, signed.service_id)
                .header(INTERNAL_IDENTITY_SIG_HEADER, signed.signature_b64)
                .header(INTERNAL_IDENTITY_AUDIENCE_HEADER, signed.audience)
                .header(INTERNAL_IDENTITY_TS_HEADER, signed.timestamp.to_string())
                .header(INTERNAL_IDENTITY_NONCE_HEADER, signed.nonce)
                .header(INTERNAL_IDENTITY_SIG_V2_HEADER, signed.signature_v2_b64)
                .body(Body::from(br#"{"ok":true}"#.as_slice().to_vec()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);
}

#[tokio::test]
async fn internal_identity_rejects_tampered_body() {
    let signer = InternalRequestSigner::from_seed_bytes("bff", [7u8; 32]).expect("signer");
    let verifier = InternalIdentityVerifier::from_public_keys_base64(
        vec![("bff".to_string(), signer.public_key_base64())],
        30,
    )
    .expect("verifier");
    let signed = signer
        .sign(
            &axum::http::Method::POST,
            TEST_AUDIENCE,
            "/x",
            br#"{"ok":true}"#,
        )
        .expect("signature");
    let app = Router::new()
        .route("/x", get(|| async { "ok" }).post(|| async { "ok" }))
        .layer(
            InternalAuthLayer::new(true, None)
                .with_expected_audience(TEST_AUDIENCE)
                .with_identity_verifier(verifier)
                .with_legacy_secret_fallback(false),
        );

    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/x")
                .header(INTERNAL_SERVICE_ID_HEADER, signed.service_id)
                .header(INTERNAL_IDENTITY_SIG_HEADER, signed.signature_b64)
                .header(INTERNAL_IDENTITY_AUDIENCE_HEADER, signed.audience)
                .header(INTERNAL_IDENTITY_TS_HEADER, signed.timestamp.to_string())
                .header(INTERNAL_IDENTITY_NONCE_HEADER, signed.nonce)
                .header(INTERNAL_IDENTITY_SIG_V2_HEADER, signed.signature_v2_b64)
                .body(Body::from(br#"{"ok":false}"#.as_slice().to_vec()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn internal_identity_can_fall_back_to_legacy_secret_when_enabled() {
    let signer = InternalRequestSigner::from_seed_bytes("bff", [7u8; 32]).expect("signer");
    let verifier = InternalIdentityVerifier::from_public_keys_base64(
        vec![("bff".to_string(), signer.public_key_base64())],
        30,
    )
    .expect("verifier");
    let app = Router::new().route("/x", get(|| async { "ok" })).layer(
        InternalAuthLayer::new(true, Some("secret".to_string()))
            .with_allowed_callers(vec!["bff".to_string()])
            .with_expected_audience(TEST_AUDIENCE)
            .with_identity_verifier(verifier)
            .with_legacy_secret_fallback(true),
    );

    let resp = app
        .oneshot(
            Request::builder()
                .uri("/x")
                .header("x-internal-secret", "secret")
                .header("x-internal-service-id", "bff")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);
}

#[tokio::test]
async fn internal_identity_rejects_replay_nonce() {
    let signer = InternalRequestSigner::from_seed_bytes("bff", [7u8; 32]).expect("signer");
    let verifier = InternalIdentityVerifier::from_public_keys_base64(
        vec![("bff".to_string(), signer.public_key_base64())],
        30,
    )
    .expect("verifier");
    let signed = signer
        .sign(
            &axum::http::Method::POST,
            TEST_AUDIENCE,
            "/x",
            br#"{"ok":true}"#,
        )
        .expect("signature");
    let app = Router::new()
        .route("/x", get(|| async { "ok" }).post(|| async { "ok" }))
        .layer(
            InternalAuthLayer::new(true, None)
                .with_expected_audience(TEST_AUDIENCE)
                .with_identity_verifier(verifier)
                .with_legacy_secret_fallback(false),
        );

    let request = || {
        Request::builder()
            .method("POST")
            .uri("/x")
            .header(INTERNAL_SERVICE_ID_HEADER, signed.service_id.clone())
            .header(INTERNAL_IDENTITY_SIG_HEADER, signed.signature_b64.clone())
            .header(INTERNAL_IDENTITY_AUDIENCE_HEADER, signed.audience.clone())
            .header(INTERNAL_IDENTITY_TS_HEADER, signed.timestamp.to_string())
            .header(INTERNAL_IDENTITY_NONCE_HEADER, signed.nonce.clone())
            .header(
                INTERNAL_IDENTITY_SIG_V2_HEADER,
                signed.signature_v2_b64.clone(),
            )
            .body(Body::from(br#"{"ok":true}"#.as_slice().to_vec()))
            .unwrap()
    };

    let first = app.clone().oneshot(request()).await.unwrap();
    assert_eq!(first.status(), StatusCode::OK);

    let second = app.oneshot(request()).await.unwrap();
    assert_eq!(second.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn internal_identity_rejects_wrong_audience() {
    let signer = InternalRequestSigner::from_seed_bytes("bff", [7u8; 32]).expect("signer");
    let verifier = InternalIdentityVerifier::from_public_keys_base64(
        vec![("bff".to_string(), signer.public_key_base64())],
        30,
    )
    .expect("verifier");
    let signed = signer
        .sign(
            &axum::http::Method::POST,
            "payments",
            "/x",
            br#"{"ok":true}"#,
        )
        .expect("signature");
    let app = Router::new()
        .route("/x", get(|| async { "ok" }).post(|| async { "ok" }))
        .layer(
            InternalAuthLayer::new(true, None)
                .with_expected_audience(TEST_AUDIENCE)
                .with_identity_verifier(verifier)
                .with_legacy_secret_fallback(false),
        );

    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/x")
                .header(INTERNAL_SERVICE_ID_HEADER, signed.service_id)
                .header(INTERNAL_IDENTITY_SIG_HEADER, signed.signature_b64)
                .header(INTERNAL_IDENTITY_AUDIENCE_HEADER, signed.audience)
                .header(INTERNAL_IDENTITY_TS_HEADER, signed.timestamp.to_string())
                .header(INTERNAL_IDENTITY_NONCE_HEADER, signed.nonce)
                .header(INTERNAL_IDENTITY_SIG_V2_HEADER, signed.signature_v2_b64)
                .body(Body::from(br#"{"ok":true}"#.as_slice().to_vec()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn internal_identity_accepts_legacy_v1_signature_for_rollout() {
    let signer = InternalRequestSigner::from_seed_bytes("bff", [7u8; 32]).expect("signer");
    let verifier = InternalIdentityVerifier::from_public_keys_base64(
        vec![("bff".to_string(), signer.public_key_base64())],
        30,
    )
    .expect("verifier");
    let signed = signer
        .sign(
            &axum::http::Method::POST,
            TEST_AUDIENCE,
            "/x",
            br#"{"ok":true}"#,
        )
        .expect("signature");
    let app = Router::new()
        .route("/x", get(|| async { "ok" }).post(|| async { "ok" }))
        .layer(
            InternalAuthLayer::new(true, None)
                .with_expected_audience(TEST_AUDIENCE)
                .with_identity_verifier(verifier)
                .with_legacy_secret_fallback(false),
        );

    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/x")
                .header(INTERNAL_SERVICE_ID_HEADER, signed.service_id)
                .header(INTERNAL_IDENTITY_TS_HEADER, signed.timestamp.to_string())
                .header(INTERNAL_IDENTITY_NONCE_HEADER, signed.nonce)
                .header(INTERNAL_IDENTITY_SIG_HEADER, signed.signature_b64)
                .body(Body::from(br#"{"ok":true}"#.as_slice().to_vec()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);
}

#[tokio::test]
async fn internal_identity_rejects_legacy_v1_signature_when_v2_required() {
    let signer = InternalRequestSigner::from_seed_bytes("bff", [7u8; 32]).expect("signer");
    let verifier = InternalIdentityVerifier::from_public_keys_base64(
        vec![("bff".to_string(), signer.public_key_base64())],
        30,
    )
    .expect("verifier");
    let signed = signer
        .sign(
            &axum::http::Method::POST,
            TEST_AUDIENCE,
            "/x",
            br#"{"ok":true}"#,
        )
        .expect("signature");
    let app = Router::new()
        .route("/x", get(|| async { "ok" }).post(|| async { "ok" }))
        .layer(
            InternalAuthLayer::new(true, None)
                .with_expected_audience(TEST_AUDIENCE)
                .with_identity_verifier(verifier)
                .with_require_identity_v2(true)
                .with_legacy_secret_fallback(false),
        );

    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/x")
                .header(INTERNAL_SERVICE_ID_HEADER, signed.service_id)
                .header(INTERNAL_IDENTITY_TS_HEADER, signed.timestamp.to_string())
                .header(INTERNAL_IDENTITY_NONCE_HEADER, signed.nonce)
                .header(INTERNAL_IDENTITY_SIG_HEADER, signed.signature_b64)
                .body(Body::from(br#"{"ok":true}"#.as_slice().to_vec()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
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
