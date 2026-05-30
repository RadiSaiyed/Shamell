use sqlx::PgPool;

#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
    pub db_schema: Option<String>,
    pub env_name: String,
    pub default_currency: String,
    pub allow_direct_topup: bool,
    pub bus_payments_internal_secret: Option<String>,
    pub merchant_fee_bps: i64,
    pub fee_wallet_account_id: Option<String>,
    pub fee_wallet_phone: String,
}

impl AppState {
    pub fn table(&self, name: &str) -> String {
        match &self.db_schema {
            Some(s) => format!("{s}.{name}"),
            None => name.to_string(),
        }
    }
}
