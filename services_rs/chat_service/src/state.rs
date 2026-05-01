use crate::push_token_crypto::PushTokenProtector;
use reqwest::Client;
use sqlx::PgPool;

#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
    pub db_schema: Option<String>,
    pub env_name: String,
    pub enforce_device_auth: bool,
    pub chat_background_purge_enabled: bool,
    pub fcm_server_key: Option<String>,
    pub fcm_project_id: Option<String>,
    pub fcm_client_email: Option<String>,
    pub fcm_private_key_pem: Option<String>,
    pub chat_protocol_v2_enabled: bool,
    pub chat_protocol_v1_write_enabled: bool,
    pub chat_protocol_v1_read_enabled: bool,
    pub chat_protocol_require_v2_for_groups: bool,
    pub chat_mailbox_api_enabled: bool,
    pub chat_mailbox_inactive_retention_secs: i64,
    pub chat_mailbox_consumed_retention_secs: i64,
    pub push_token_protector: PushTokenProtector,
    pub http: Client,
}

impl AppState {
    pub fn table(&self, name: &str) -> String {
        match &self.db_schema {
            Some(s) => format!("{s}.{name}"),
            None => name.to_string(),
        }
    }
}
