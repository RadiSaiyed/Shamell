use axum::http::{HeaderMap, HeaderValue, Request};
use axum::response::Response;
use std::env;
use std::future::Future;
use std::pin::Pin;
use std::task::{Context, Poll};
use tower::{Layer, Service};

#[derive(Clone, Debug)]
pub struct SecurityHeadersLayer {
    enabled: bool,
    hsts_enabled: bool,
    csp_enabled: bool,
    csp_value: String,
}

impl SecurityHeadersLayer {
    pub fn new(enabled: bool, hsts_enabled: bool) -> Self {
        Self::with_csp(
            enabled,
            hsts_enabled,
            true,
            default_csp_header_value().to_string(),
        )
    }

    pub fn with_csp(
        enabled: bool,
        hsts_enabled: bool,
        csp_enabled: bool,
        csp_value: String,
    ) -> Self {
        let csp_value = csp_value.trim().to_string();
        Self {
            enabled,
            hsts_enabled,
            csp_enabled,
            csp_value: if csp_value.is_empty() {
                default_csp_header_value().to_string()
            } else {
                csp_value
            },
        }
    }

    pub fn from_env(env_name: &str) -> Self {
        let env_lower = env_name.trim().to_ascii_lowercase();
        let enabled = parse_bool_env("SECURITY_HEADERS_ENABLED", true);
        let hsts_default = matches!(env_lower.as_str(), "prod" | "production" | "staging");
        let hsts_enabled = parse_bool_env("HSTS_ENABLED", hsts_default);
        let csp_enabled = parse_bool_env("CSP_ENABLED", true);
        let csp_value = env::var("CSP_HEADER_VALUE")
            .unwrap_or_else(|_| default_csp_header_value().to_string())
            .trim()
            .to_string();
        Self::with_csp(enabled, hsts_enabled, csp_enabled, csp_value)
    }
}

impl<S> Layer<S> for SecurityHeadersLayer {
    type Service = SecurityHeadersService<S>;

    fn layer(&self, inner: S) -> Self::Service {
        SecurityHeadersService {
            inner,
            enabled: self.enabled,
            hsts_enabled: self.hsts_enabled,
            csp_enabled: self.csp_enabled,
            csp_value: self.csp_value.clone(),
        }
    }
}

#[derive(Clone)]
pub struct SecurityHeadersService<S> {
    inner: S,
    enabled: bool,
    hsts_enabled: bool,
    csp_enabled: bool,
    csp_value: String,
}

impl<S, B> Service<Request<B>> for SecurityHeadersService<S>
where
    S: Service<Request<B>, Response = Response> + Clone + Send + 'static,
    S::Future: Send + 'static,
    S::Error: Send + 'static,
    B: Send + 'static,
{
    type Response = Response;
    type Error = S::Error;
    type Future = Pin<Box<dyn Future<Output = Result<Response, S::Error>> + Send>>;

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, req: Request<B>) -> Self::Future {
        let enabled = self.enabled;
        let hsts_enabled = self.hsts_enabled;
        let csp_enabled = self.csp_enabled;
        let csp_value = self.csp_value.clone();
        let mut inner = self.inner.clone();
        Box::pin(async move {
            let mut resp = inner.call(req).await?;
            if enabled {
                add_security_headers(resp.headers_mut(), hsts_enabled, csp_enabled, &csp_value);
            }
            Ok(resp)
        })
    }
}

fn default_csp_header_value() -> &'static str {
    "default-src 'self'; base-uri 'none'; frame-ancestors 'none'; object-src 'none'; script-src 'self' https: 'unsafe-inline'; style-src 'self' https: 'unsafe-inline'; img-src 'self' https: data:; connect-src 'self' https: wss:; form-action 'self'"
}

fn parse_bool_env(key: &str, default: bool) -> bool {
    let raw = env::var(key).unwrap_or_default();
    let v = raw.trim().to_ascii_lowercase();
    if v.is_empty() {
        return default;
    }
    !matches!(v.as_str(), "0" | "false" | "no" | "off")
}

fn add_security_headers(
    headers: &mut HeaderMap,
    hsts_enabled: bool,
    csp_enabled: bool,
    csp_value: &str,
) {
    set_if_absent(headers, "x-content-type-options", "nosniff");
    set_if_absent(headers, "x-frame-options", "DENY");
    set_if_absent(headers, "referrer-policy", "no-referrer");
    set_if_absent(
        headers,
        "permissions-policy",
        "camera=(), microphone=(), geolocation=()",
    );
    if hsts_enabled {
        set_if_absent(
            headers,
            "strict-transport-security",
            "max-age=31536000; includeSubDomains",
        );
    }
    if csp_enabled {
        set_if_absent(headers, "content-security-policy", csp_value);
    }
}

fn set_if_absent(headers: &mut HeaderMap, name: &'static str, value: &str) {
    if headers.contains_key(name) {
        return;
    }
    if let Ok(v) = HeaderValue::from_str(value) {
        headers.insert(name, v);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use axum::response::IntoResponse;
    use axum::routing::get;
    use axum::Router;
    use std::sync::{Mutex, OnceLock};
    use tower::ServiceExt;

    static ENV_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

    struct EnvGuard {
        saved: Vec<(String, Option<String>)>,
    }

    impl EnvGuard {
        fn new(keys: &[&str]) -> Self {
            let mut saved = Vec::with_capacity(keys.len());
            for k in keys {
                saved.push(((*k).to_string(), env::var(k).ok()));
            }
            Self { saved }
        }
    }

    impl Drop for EnvGuard {
        fn drop(&mut self) {
            for (k, v) in self.saved.drain(..) {
                match v {
                    Some(val) => env::set_var(k, val),
                    None => env::remove_var(k),
                }
            }
        }
    }

    async fn ok() -> &'static str {
        "ok"
    }

    async fn existing_headers() -> axum::response::Response {
        let mut resp = "ok".into_response();
        resp.headers_mut()
            .insert("x-frame-options", HeaderValue::from_static("SAMEORIGIN"));
        resp
    }

    #[tokio::test]
    async fn adds_headers_when_enabled() {
        let app = Router::new()
            .route("/", get(ok))
            .layer(SecurityHeadersLayer::new(true, true));
        let resp = app
            .oneshot(Request::builder().uri("/").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        assert_eq!(
            resp.headers()
                .get("x-content-type-options")
                .and_then(|v| v.to_str().ok()),
            Some("nosniff")
        );
        assert_eq!(
            resp.headers()
                .get("strict-transport-security")
                .and_then(|v| v.to_str().ok()),
            Some("max-age=31536000; includeSubDomains")
        );
        assert!(resp.headers().get("content-security-policy").is_some());
    }

    #[tokio::test]
    async fn does_not_override_existing_headers() {
        let app = Router::new()
            .route("/", get(existing_headers))
            .layer(SecurityHeadersLayer::new(true, true));
        let resp = app
            .oneshot(Request::builder().uri("/").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(
            resp.headers()
                .get("x-frame-options")
                .and_then(|v| v.to_str().ok()),
            Some("SAMEORIGIN")
        );
    }

    #[tokio::test]
    async fn disabled_layer_adds_nothing() {
        let app = Router::new()
            .route("/", get(ok))
            .layer(SecurityHeadersLayer::new(false, true));
        let resp = app
            .oneshot(Request::builder().uri("/").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert!(resp.headers().get("x-content-type-options").is_none());
        assert!(resp.headers().get("strict-transport-security").is_none());
        assert!(resp.headers().get("content-security-policy").is_none());
    }

    #[tokio::test]
    async fn from_env_prod_defaults_enable_hsts() {
        let layer = {
            let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
            let _env = EnvGuard::new(&[
                "SECURITY_HEADERS_ENABLED",
                "HSTS_ENABLED",
                "CSP_ENABLED",
                "CSP_HEADER_VALUE",
            ]);
            env::remove_var("SECURITY_HEADERS_ENABLED");
            env::remove_var("HSTS_ENABLED");
            env::remove_var("CSP_ENABLED");
            env::remove_var("CSP_HEADER_VALUE");
            SecurityHeadersLayer::from_env("prod")
        };

        let app = Router::new().route("/", get(ok)).layer(layer);
        let resp = app
            .oneshot(Request::builder().uri("/").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert!(resp.headers().get("strict-transport-security").is_some());
        assert!(resp.headers().get("content-security-policy").is_some());
    }

    #[tokio::test]
    async fn from_env_dev_defaults_disable_hsts() {
        let layer = {
            let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
            let _env = EnvGuard::new(&[
                "SECURITY_HEADERS_ENABLED",
                "HSTS_ENABLED",
                "CSP_ENABLED",
                "CSP_HEADER_VALUE",
            ]);
            env::remove_var("SECURITY_HEADERS_ENABLED");
            env::remove_var("HSTS_ENABLED");
            env::remove_var("CSP_ENABLED");
            env::remove_var("CSP_HEADER_VALUE");
            SecurityHeadersLayer::from_env("dev")
        };

        let app = Router::new().route("/", get(ok)).layer(layer);
        let resp = app
            .oneshot(Request::builder().uri("/").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert!(resp.headers().get("strict-transport-security").is_none());
        assert!(resp.headers().get("x-content-type-options").is_some());
        assert!(resp.headers().get("content-security-policy").is_some());
    }

    #[tokio::test]
    async fn from_env_allows_disabling_csp() {
        let layer = {
            let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
            let _env = EnvGuard::new(&[
                "SECURITY_HEADERS_ENABLED",
                "HSTS_ENABLED",
                "CSP_ENABLED",
                "CSP_HEADER_VALUE",
            ]);
            env::set_var("SECURITY_HEADERS_ENABLED", "true");
            env::set_var("HSTS_ENABLED", "true");
            env::set_var("CSP_ENABLED", "false");
            env::remove_var("CSP_HEADER_VALUE");
            SecurityHeadersLayer::from_env("prod")
        };

        let app = Router::new().route("/", get(ok)).layer(layer);
        let resp = app
            .oneshot(Request::builder().uri("/").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert!(resp.headers().get("strict-transport-security").is_some());
        assert!(resp.headers().get("content-security-policy").is_none());
    }

    #[tokio::test]
    async fn from_env_uses_custom_csp_value() {
        let layer = {
            let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
            let _env = EnvGuard::new(&[
                "SECURITY_HEADERS_ENABLED",
                "HSTS_ENABLED",
                "CSP_ENABLED",
                "CSP_HEADER_VALUE",
            ]);
            env::set_var("SECURITY_HEADERS_ENABLED", "true");
            env::set_var("HSTS_ENABLED", "false");
            env::set_var("CSP_ENABLED", "true");
            env::set_var(
                "CSP_HEADER_VALUE",
                "default-src 'none'; frame-ancestors 'none'",
            );
            SecurityHeadersLayer::from_env("dev")
        };

        let app = Router::new().route("/", get(ok)).layer(layer);
        let resp = app
            .oneshot(Request::builder().uri("/").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(
            resp.headers()
                .get("content-security-policy")
                .and_then(|v| v.to_str().ok()),
            Some("default-src 'none'; frame-ancestors 'none'")
        );
    }
}
