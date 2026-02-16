use axum::http::{header::HeaderName, Request, StatusCode};
use axum::response::{IntoResponse, Response};
use serde::Serialize;
use std::future::Future;
use std::pin::Pin;
use std::task::{Context, Poll};
use subtle::ConstantTimeEq;
use tower::{Layer, Service};

#[derive(Clone)]
pub struct InternalAuthLayer {
    required: bool,
    secret: Option<String>,
    secret_header: HeaderName,
    caller_header: HeaderName,
    allowed_callers: Vec<String>,
}

impl InternalAuthLayer {
    pub fn new(required: bool, secret: Option<String>) -> Self {
        Self {
            required,
            secret,
            secret_header: HeaderName::from_static("x-internal-secret"),
            caller_header: HeaderName::from_static("x-internal-service-id"),
            allowed_callers: Vec::new(),
        }
    }

    pub fn with_allowed_callers(mut self, callers: Vec<String>) -> Self {
        let mut out: Vec<String> = Vec::new();
        for raw in callers {
            let caller = raw.trim().to_ascii_lowercase();
            if caller.is_empty() || out.iter().any(|c| c == &caller) {
                continue;
            }
            out.push(caller);
        }
        self.allowed_callers = out;
        self
    }
}

impl<S> Layer<S> for InternalAuthLayer {
    type Service = InternalAuthService<S>;

    fn layer(&self, inner: S) -> Self::Service {
        InternalAuthService {
            inner,
            required: self.required,
            secret: self.secret.clone(),
            secret_header: self.secret_header.clone(),
            caller_header: self.caller_header.clone(),
            allowed_callers: self.allowed_callers.clone(),
        }
    }
}

#[derive(Clone)]
pub struct InternalAuthService<S> {
    inner: S,
    required: bool,
    secret: Option<String>,
    secret_header: HeaderName,
    caller_header: HeaderName,
    allowed_callers: Vec<String>,
}

#[derive(Serialize)]
struct ErrorBody<'a> {
    detail: &'a str,
}

impl<S, B> Service<Request<B>> for InternalAuthService<S>
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
        let required = self.required;
        let secret = self.secret.clone();
        let secret_header = self.secret_header.clone();
        let caller_header = self.caller_header.clone();
        let allowed_callers = self.allowed_callers.clone();
        let mut inner = self.inner.clone();

        Box::pin(async move {
            if !required {
                return inner.call(req).await;
            }

            let Some(secret) = secret.filter(|s| !s.trim().is_empty()) else {
                let body = axum::Json(ErrorBody {
                    detail: "internal auth not configured",
                });
                return Ok((StatusCode::SERVICE_UNAVAILABLE, body).into_response());
            };

            let provided = req
                .headers()
                .get(&secret_header)
                .and_then(|v| v.to_str().ok())
                .map(|s| s.trim())
                .unwrap_or("");

            if provided.is_empty() || provided.as_bytes().ct_eq(secret.as_bytes()).unwrap_u8() != 1
            {
                let body = axum::Json(ErrorBody {
                    detail: "internal auth required",
                });
                return Ok((StatusCode::UNAUTHORIZED, body).into_response());
            }

            if !allowed_callers.is_empty() {
                let caller = req
                    .headers()
                    .get(&caller_header)
                    .and_then(|v| v.to_str().ok())
                    .map(str::trim)
                    .map(str::to_ascii_lowercase)
                    .unwrap_or_default();
                let caller_ok = !caller.is_empty() && allowed_callers.iter().any(|c| c == &caller);
                if !caller_ok {
                    let body = axum::Json(ErrorBody {
                        detail: "internal caller not allowed",
                    });
                    return Ok((StatusCode::UNAUTHORIZED, body).into_response());
                }
            }

            inner.call(req).await
        })
    }
}
