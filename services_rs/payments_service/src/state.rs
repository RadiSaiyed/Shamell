use sqlx::PgPool;

#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
    pub db_schema: Option<String>,
    pub env_name: String,
    pub default_currency: String,
    pub allow_direct_topup: bool,
    pub allow_emergency_direct_topup: bool,
    pub require_idempotency_key: bool,
    pub merchant_fee_bps: i64,
    pub fee_wallet_account_id: Option<String>,
    pub fee_wallet_phone: String,
    pub admin_credit_max_amount_cents: i64,
    pub admin_credit_operator_daily_limit_cents: i64,
    pub admin_credit_approval_threshold_cents: i64,
}

impl AppState {
    pub fn table(&self, name: &str) -> String {
        match &self.db_schema {
            Some(s) => format!("{s}.{name}"),
            None => name.to_string(),
        }
    }
}
