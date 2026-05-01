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

            if !host_matches_any(&host, &allowed) {
                let body = axum::Json(ErrorBody {
                    detail: "invalid host",
                });
                return Ok((StatusCode::BAD_REQUEST, body).into_response());
            }

            inner.call(req).await
        })
    }
}

/// Pure host matcher used by `AllowedHostsService`. Exposed at crate scope
/// so it can be unit-tested without spinning up a tower service.
///
/// Rules supported:
/// - `"*"` matches anything.
/// - A rule starting with `.` (Starlette-style, e.g. `.example.com`) matches
///   the bare apex (`example.com`) and any subdomain (`a.example.com`,
///   `a.b.example.com`).
/// - Anything else is an exact match against the lowercased host.
///
/// Caller is expected to have already lowercased and port-stripped `host`.
pub fn host_matches_any(host: &str, rules: &[String]) -> bool {
    rules.iter().any(|rule| match rule.as_str() {
        "*" => true,
        r if r.starts_with('.') => host == &r[1..] || host.ends_with(rule),
        r => host == r,
    })
}

#[cfg(test)]
mod tests {
    use super::host_matches_any;

    fn rules(items: &[&str]) -> Vec<String> {
        items.iter().map(|s| (*s).to_string()).collect()
    }

    #[test]
    fn exact_match_only_accepts_exact_host() {
        let rs = rules(&["api.shamell.online"]);
        assert!(host_matches_any("api.shamell.online", &rs));
        assert!(!host_matches_any("evil.api.shamell.online", &rs));
        assert!(!host_matches_any("api.shamell.onlin", &rs));
        assert!(!host_matches_any("", &rs));
    }

    #[test]
    fn wildcard_rule_accepts_apex_and_any_subdomain() {
        let rs = rules(&[".shamell.online"]);
        assert!(host_matches_any("shamell.online", &rs));
        assert!(host_matches_any("api.shamell.online", &rs));
        assert!(host_matches_any("a.b.shamell.online", &rs));
    }

    #[test]
    fn wildcard_rule_does_not_match_lookalike_apex() {
        let rs = rules(&[".shamell.online"]);
        // Critical: ".shamell.online" must NOT match "evilshamell.online".
        assert!(!host_matches_any("evilshamell.online", &rs));
        // ...nor a domain that merely shares the suffix without the dot.
        assert!(!host_matches_any("notshamell.online", &rs));
        // ...nor an unrelated TLD that happens to contain the substring.
        assert!(!host_matches_any("shamell.online.attacker.com", &rs));
    }

    #[test]
    fn star_rule_matches_anything() {
        let rs = rules(&["*"]);
        assert!(host_matches_any("anything.example", &rs));
        assert!(host_matches_any("", &rs)); // pure function; emptiness is filtered earlier
    }

    #[test]
    fn empty_rules_never_match() {
        let rs: Vec<String> = vec![];
        assert!(!host_matches_any("anything.example", &rs));
    }

    #[test]
    fn multiple_rules_use_first_hit() {
        let rs = rules(&["api.shamell.online", ".dev.shamell.online"]);
        assert!(host_matches_any("api.shamell.online", &rs));
        assert!(host_matches_any("foo.dev.shamell.online", &rs));
        assert!(host_matches_any("dev.shamell.online", &rs));
        assert!(!host_matches_any("bar.shamell.online", &rs));
    }
}
