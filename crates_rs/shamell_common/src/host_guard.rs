use axum::http::{Request, StatusCode};
use axum::response::{IntoResponse, Response};
use serde::Serialize;
use std::future::Future;
use std::pin::Pin;
use std::task::{Context, Poll};
use tower::{Layer, Service};

#[derive(Clone)]
pub struct AllowedHostsLayer {
    allowed: Vec<String>,
}

impl AllowedHostsLayer {
    pub fn new(mut allowed_hosts: Vec<String>) -> Self {
        // Normalize to lowercase and trim.
        allowed_hosts = allowed_hosts
            .into_iter()
            .map(|h| h.trim().to_lowercase())
            .filter(|h| !h.is_empty())
            .collect();
        Self {
            allowed: allowed_hosts,
        }
    }
}

impl<S> Layer<S> for AllowedHostsLayer {
    type Service = AllowedHostsService<S>;

    fn layer(&self, inner: S) -> Self::Service {
        AllowedHostsService {
            inner,
            allowed: self.allowed.clone(),
        }
    }
}

#[derive(Clone)]
pub struct AllowedHostsService<S> {
    inner: S,
    allowed: Vec<String>,
}

#[derive(Serialize)]
struct ErrorBody<'a> {
    detail: &'a str,
}

impl<S, B> Service<Request<B>> for AllowedHostsService<S>
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
        let allowed = self.allowed.clone();
        let mut inner = self.inner.clone();

        Box::pin(async move {
            if allowed.is_empty() {
                return inner.call(req).await;
            }

            let host = req
                .headers()
                .get("host")
                .and_then(|v| v.to_str().ok())
                .map(|s| s.trim())
                .unwrap_or("");

            let host = host.split(':').next().unwrap_or("").trim().to_lowercase();
            if host.is_empty() {
                let body = axum::Json(ErrorBody {
                    detail: "invalid host",
                });
                return Ok((StatusCode::BAD_REQUEST, body).into_response());
            }

            let ok = allowed.iter().any(|rule| match rule.as_str() {
                "*" => true,
                r if r.starts_with('.') => {
                    // Starlette-style: ".example.com" matches "a.example.com" and "example.com".
                    host == r[1..] || host.ends_with(rule)
                }
                r => host == r,
            });

            if !ok {
                let body = axum::Json(ErrorBody {
                    detail: "invalid host",
                });
                return Ok((StatusCode::BAD_REQUEST, body).into_response());
            }

            inner.call(req).await
        })
    }
}
