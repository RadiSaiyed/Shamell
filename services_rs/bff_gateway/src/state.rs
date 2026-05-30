use reqwest::Client;

use crate::auth::AuthRuntime;

#[derive(Clone)]
pub struct AppState {
    pub env_name: String,
    pub payments_base_url: String,
    pub payments_internal_secret: Option<String>,
    pub chat_base_url: String,
    pub chat_internal_secret: Option<String>,
    pub bus_base_url: String,
    pub bus_internal_secret: Option<String>,
    pub internal_service_id: String,
    pub enforce_route_authz: bool,
    pub role_header_secret: Option<String>,
    pub max_upstream_body_bytes: usize,
    pub expose_upstream_errors: bool,
    pub accept_legacy_session_cookie: bool,
    pub auth_device_login_web_enabled: bool,
    pub http: Client,
    pub auth: Option<AuthRuntime>,
}

impl AppState {
    pub fn payments_url(&self, path: &str) -> String {
        format!("{}{}", self.payments_base_url.trim_end_matches('/'), path)
    }

    pub fn chat_url(&self, path: &str) -> String {
        format!("{}{}", self.chat_base_url.trim_end_matches('/'), path)
    }

    pub fn bus_url(&self, path: &str) -> String {
        format!("{}{}", self.bus_base_url.trim_end_matches('/'), path)
    }
}
