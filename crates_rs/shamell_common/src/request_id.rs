use axum::http::{header::HeaderName, HeaderValue, Request};
use axum::response::Response;
use std::future::Future;
use std::pin::Pin;
use std::task::{Context, Poll};
use tower::{Layer, Service};
use uuid::Uuid;

#[derive(Clone, Debug)]
pub struct RequestId(pub String);

#[derive(Clone)]
pub struct RequestIdLayer {
    header: HeaderName,
}

impl RequestIdLayer {
    pub fn new(header_name: HeaderName) -> Self {
        Self {
            header: header_name,
        }
    }
}

impl<S> Layer<S> for RequestIdLayer {
    type Service = RequestIdService<S>;

    fn layer(&self, inner: S) -> Self::Service {
        RequestIdService {
            inner,
            header: self.header.clone(),
        }
    }
}

#[derive(Clone)]
pub struct RequestIdService<S> {
    inner: S,
    header: HeaderName,
}

impl<S, B> Service<Request<B>> for RequestIdService<S>
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

    fn call(&mut self, mut req: Request<B>) -> Self::Future {
        let header = self.header.clone();

        let rid = req
            .headers()
            .get(&header)
            .and_then(|v| v.to_str().ok())
            .map(|s| s.trim())
            .filter(|s| !s.is_empty())
            .map(|s| s.to_string())
            .unwrap_or_else(|| Uuid::new_v4().simple().to_string());

        req.extensions_mut().insert(RequestId(rid.clone()));

        let mut inner = self.inner.clone();
        Box::pin(async move {
            let mut resp = inner.call(req).await?;
            if !resp.headers().contains_key(&header) {
                if let Ok(v) = HeaderValue::from_str(&rid) {
                    resp.headers_mut().insert(header, v);
                }
            }
            Ok(resp)
        })
    }
}
