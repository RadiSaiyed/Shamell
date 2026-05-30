use reqwest::Client;
use sqlx::PgPool;

#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
    pub db_schema: Option<String>,
    pub ticket_secret: String,
    pub env_name: String,
    pub env_lower: String,
    pub internal_service_id: String,
    pub payments_base_url: Option<String>,
    pub bus_payments_internal_secret: Option<String>,
    pub http: Client,
}

impl AppState {
    pub fn table(&self, name: &str) -> String {
        match &self.db_schema {
            Some(s) => format!("{s}.{name}"),
            None => name.to_string(),
        }
    }

    pub fn payments_enabled(&self) -> bool {
        self.payments_base_url.as_deref().unwrap_or("").trim() != ""
    }
}
