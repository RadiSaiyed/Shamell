use axum::http::Uri;
use regex::Regex;
use shamell_common::internal_identity::parse_public_keys_csv;
use shamell_common::secret_policy;
use std::env;

const SUPPORTED_WALLET_CURRENCIES: &[&str] = &["SYP", "USD", "EUR", "SAR", "AED", "QAR", "KWD"];

#[derive(Clone, Debug)]
pub struct Config {
    pub env_name: String,

    pub host: String,
    pub port: u16,
    pub max_body_bytes: usize,

    pub db_url: String,
    pub db_schema: Option<String>,
    pub auto_apply_schema: bool,
    pub auto_provision_fee_wallet: bool,

    pub require_internal_secret: bool,
    pub internal_secret: Option<String>,
    pub internal_allowed_callers: Vec<String>,
    pub internal_identity_public_keys: Vec<(String, String)>,
    pub internal_identity_max_skew_secs: i64,
    pub require_internal_identity_v2: bool,
    pub allow_legacy_internal_secret_fallback: bool,

    pub allowed_hosts: Vec<String>,
    pub allowed_origins: Vec<String>,

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

fn env_or(key: &str, default: &str) -> String {
    env::var(key).unwrap_or_else(|_| default.to_string())
}

fn env_opt(key: &str) -> Option<String> {
    match env::var(key) {
        Ok(v) => {
            let v = v.trim().to_string();
            if v.is_empty() {
                None
            } else {
                Some(v)
            }
        }
        Err(_) => None,
    }
}

fn parse_csv(raw: &str) -> Vec<String> {
    raw.split(',')
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
        .collect()
}

fn parse_i64_env(key: &str, default: &str) -> Result<i64, String> {
    env_or(key, default)
        .parse::<i64>()
        .map_err(|_| format!("{key} must be an integer"))
}

fn parse_bool_like(key: &str, raw: &str) -> Result<Option<bool>, String> {
    let v = raw.trim().to_ascii_lowercase();
    if v.is_empty() {
        return Ok(None);
    }
    match v.as_str() {
        "1" | "true" | "yes" | "on" => Ok(Some(true)),
        "0" | "false" | "no" | "off" => Ok(Some(false)),
        _ => Err(format!(
            "{key} must be one of: 1, true, yes, on, 0, false, no, off"
        )),
    }
}

fn normalize_db_url(raw: &str) -> String {
    // Accept SQLAlchemy-style URLs like "postgresql+psycopg://..." by dropping
    // the "+driver" portion.
    if let Some(colon) = raw.find(':') {
        let (scheme, rest) = raw.split_at(colon);
        if let Some(plus) = scheme.find('+') {
            return format!("{}{}", &scheme[..plus], rest);
        }
    }
    raw.to_string()
}

fn validate_postgres_url(url: &str) -> Result<(), String> {
    let scheme = url
        .split_once(':')
        .map(|(s, _)| s.trim().to_lowercase())
        .unwrap_or_default();
    match scheme.as_str() {
        "postgres" | "postgresql" => Ok(()),
        _ => Err("PAYMENTS_DB_URL (or DB_URL) must be a postgres URL".to_string()),
    }
}

fn truncate_utf8_safely(s: &mut String, max: usize) {
    if s.len() <= max {
        return;
    }
    let mut boundary = max;
    while boundary > 0 && !s.is_char_boundary(boundary) {
        boundary -= 1;
    }
    s.truncate(boundary);
}

fn is_supported_wallet_currency(currency: &str) -> bool {
    let currency = currency.trim().to_ascii_uppercase();
    SUPPORTED_WALLET_CURRENCIES.contains(&currency.as_str())
}

fn normalize_allowed_origin(raw: &str) -> Result<String, String> {
    let trimmed = raw.trim();
    if trimmed == "*" {
        return Ok("*".to_string());
    }
    if trimmed.contains('#') {
        return Err("must not include query or fragment".to_string());
    }
    let uri: Uri = trimmed
        .parse()
        .map_err(|_| "must be a valid http(s) origin".to_string())?;
    let scheme = uri.scheme_str().unwrap_or_default().to_ascii_lowercase();
    if !matches!(scheme.as_str(), "http" | "https") {
        return Err("must use http:// or https://".to_string());
    }
    let authority = uri
        .authority()
        .map(|v| v.as_str().trim())
        .filter(|v| !v.is_empty())
        .ok_or_else(|| "must include a host".to_string())?;
    if authority.contains('@') {
        return Err("must not include credentials".to_string());
    }
    if uri.path_and_query().is_some_and(|pq| pq.query().is_some()) {
        return Err("must not include query or fragment".to_string());
    }
    let path = uri.path().trim();
    if !path.is_empty() && path != "/" {
        return Err("must not include a non-root path".to_string());
    }
    Ok(format!("{scheme}://{}", authority.to_ascii_lowercase()))
}

fn normalize_allowed_host(raw: &str) -> Result<String, String> {
    let trimmed = raw.trim().to_ascii_lowercase();
    if trimmed.is_empty() {
        return Err("must not be empty".to_string());
    }
    if trimmed == "*" {
        return Ok(trimmed);
    }
    if trimmed.starts_with('.') {
        return Err("must not use wildcard subdomain patterns".to_string());
    }
    if trimmed.contains("://")
        || trimmed.contains('@')
        || trimmed.contains('/')
        || trimmed.contains('?')
        || trimmed.contains('#')
        || trimmed.contains(':')
    {
        return Err("must be a plain host without scheme, port, or path".to_string());
    }
    if !trimmed
        .chars()
        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || matches!(c, '.' | '-'))
    {
        return Err("must contain only lowercase host characters".to_string());
    }
    Ok(trimmed)
}

impl Config {
    pub fn from_env() -> Result<Self, String> {
        let env_name = env_or("ENV", "dev");
        let env_lower = env_name.trim().to_lowercase();
        let prod_like = match env_lower.as_str() {
            "prod" | "production" | "staging" => true,
            "dev" | "development" | "test" => false,
            _ => {
                return Err(
                    "ENV must be one of: dev, development, test, staging, prod, production"
                        .to_string(),
                )
            }
        };
        let dev_or_test = matches!(env_lower.as_str(), "dev" | "development" | "test");

        let host = env_or("APP_HOST", "0.0.0.0");
        let port: u16 = env_or("APP_PORT", "8082")
            .parse()
            .map_err(|_| "APP_PORT must be a valid u16".to_string())?;

        let db_raw = match env_opt("PAYMENTS_DB_URL").or_else(|| env_opt("DB_URL")) {
            Some(v) => v,
            None if prod_like => {
                return Err("PAYMENTS_DB_URL (or DB_URL) must be set in prod/staging".to_string());
            }
            None => "postgresql://shamell:shamell@db:5432/shamell_payments".to_string(),
        };
        let db_url = normalize_db_url(&db_raw);
        validate_postgres_url(&db_url)?;

        let db_schema = env_opt("DB_SCHEMA");
        if let Some(s) = &db_schema {
            let re = Regex::new(r"^[A-Za-z_][A-Za-z0-9_]*$").map_err(|e| e.to_string())?;
            if !re.is_match(s) {
                return Err("DB_SCHEMA must match ^[A-Za-z_][A-Za-z0-9_]*$".to_string());
            }
        }

        let auto_apply_schema = {
            let raw = env_or("PAYMENTS_AUTO_APPLY_SCHEMA", "");
            match parse_bool_like("PAYMENTS_AUTO_APPLY_SCHEMA", &raw)? {
                Some(v) => v,
                None => !prod_like,
            }
        };
        let auto_provision_fee_wallet = {
            let raw = env_or("PAYMENTS_AUTO_PROVISION_FEE_WALLET", "");
            match parse_bool_like("PAYMENTS_AUTO_PROVISION_FEE_WALLET", &raw)? {
                Some(v) => v,
                None => !prod_like,
            }
        };

        let require_internal_secret = {
            let raw = env_or("PAYMENTS_REQUIRE_INTERNAL_SECRET", "");
            match parse_bool_like("PAYMENTS_REQUIRE_INTERNAL_SECRET", &raw)? {
                Some(v) => v,
                None => prod_like,
            }
        };
        if prod_like && !require_internal_secret {
            return Err(
                "PAYMENTS_REQUIRE_INTERNAL_SECRET must be true in prod/staging".to_string(),
            );
        }

        let internal_secret =
            env_opt("INTERNAL_API_SECRET").or_else(|| env_opt("PAYMENTS_INTERNAL_SECRET"));
        let internal_identity_public_keys =
            parse_public_keys_csv(&env_or("PAYMENTS_INTERNAL_IDENTITY_PUBLIC_KEYS", ""))
                .map_err(|e| format!("PAYMENTS_INTERNAL_IDENTITY_PUBLIC_KEYS {e}"))?;
        let internal_identity_max_skew_secs: i64 =
            env_or("PAYMENTS_INTERNAL_IDENTITY_MAX_SKEW_SECS", "30")
                .parse()
                .map_err(|_| {
                    "PAYMENTS_INTERNAL_IDENTITY_MAX_SKEW_SECS must be an integer".to_string()
                })?;
        let internal_identity_max_skew_secs = internal_identity_max_skew_secs.clamp(1, 300);
        let require_internal_identity_v2 = {
            let raw = env_or("PAYMENTS_REQUIRE_INTERNAL_IDENTITY_V2", "");
            match parse_bool_like("PAYMENTS_REQUIRE_INTERNAL_IDENTITY_V2", &raw)? {
                Some(v) => v,
                None => prod_like,
            }
        };
        let allow_legacy_internal_secret_fallback = {
            let raw = env_or("PAYMENTS_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK", "");
            match parse_bool_like("PAYMENTS_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK", &raw)? {
                Some(v) => v,
                None => !prod_like,
            }
        };
        if prod_like && internal_identity_public_keys.is_empty() {
            return Err(
                "PAYMENTS_INTERNAL_IDENTITY_PUBLIC_KEYS must be set in prod/staging".to_string(),
            );
        }
        if prod_like && !require_internal_identity_v2 {
            return Err(
                "PAYMENTS_REQUIRE_INTERNAL_IDENTITY_V2 must be true in prod/staging".to_string(),
            );
        }
        if prod_like && allow_legacy_internal_secret_fallback {
            return Err(
                "PAYMENTS_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK must be false in prod/staging"
                    .to_string(),
            );
        }
        if require_internal_secret
            && internal_secret.as_deref().unwrap_or("").is_empty()
            && (internal_identity_public_keys.is_empty() || allow_legacy_internal_secret_fallback)
        {
            return Err(
                "INTERNAL_API_SECRET must be set when PAYMENTS_REQUIRE_INTERNAL_SECRET is enabled unless strong service identity is configured without legacy fallback"
                    .to_string(),
            );
        }
        secret_policy::validate_secret_for_env(
            &env_name,
            "INTERNAL_API_SECRET",
            internal_secret.as_deref(),
            false,
        )?;

        let mut internal_allowed_callers =
            parse_csv(&env_or("PAYMENTS_INTERNAL_ALLOWED_CALLERS", ""))
                .into_iter()
                .map(|v| v.trim().to_ascii_lowercase())
                .filter(|v| !v.is_empty())
                .collect::<Vec<_>>();
        if internal_allowed_callers.is_empty() && prod_like {
            internal_allowed_callers = vec!["bff".to_string()];
        }
        if require_internal_secret && prod_like && internal_allowed_callers.is_empty() {
            return Err(
                "PAYMENTS_INTERNAL_ALLOWED_CALLERS must define at least one caller in prod/staging"
                    .to_string(),
            );
        }

        let mut allowed_hosts = parse_csv(&env_or("ALLOWED_HOSTS", ""));
        if allowed_hosts.is_empty() {
            // Fail closed on missing host allowlist:
            // - dev/test keep loopback defaults for local ergonomics
            // - prod/staging requires explicit external hosts from ALLOWED_HOSTS
            if dev_or_test {
                allowed_hosts = vec!["localhost".to_string(), "127.0.0.1".to_string()];
            }
        }
        if dev_or_test {
            for extra in ["localhost", "127.0.0.1"] {
                if !allowed_hosts.iter().any(|h| h == extra) {
                    allowed_hosts.push(extra.to_string());
                }
            }
        }
        for extra in ["payments"] {
            if !allowed_hosts.iter().any(|h| h == extra) {
                allowed_hosts.push(extra.to_string());
            }
        }
        allowed_hosts = allowed_hosts
            .into_iter()
            .map(|host| {
                normalize_allowed_host(&host)
                    .map_err(|reason| format!("ALLOWED_HOSTS contains invalid host: {reason}"))
            })
            .collect::<Result<Vec<_>, _>>()?;
        if prod_like && allowed_hosts.iter().any(|h| h.trim() == "*") {
            return Err("ALLOWED_HOSTS must not contain '*' in prod/staging".to_string());
        }

        let mut allowed_origins = parse_csv(&env_or("ALLOWED_ORIGINS", ""));
        if allowed_origins.is_empty() && dev_or_test {
            allowed_origins = vec![
                "http://localhost:5173".to_string(),
                "http://127.0.0.1:5173".to_string(),
            ];
        }
        allowed_origins = allowed_origins
            .into_iter()
            .map(|origin| {
                normalize_allowed_origin(&origin)
                    .map_err(|reason| format!("ALLOWED_ORIGINS contains invalid origin: {reason}"))
            })
            .collect::<Result<Vec<_>, _>>()?;
        if prod_like && allowed_origins.is_empty() {
            return Err("ALLOWED_ORIGINS must be set in prod/staging".to_string());
        }
        if prod_like && allowed_origins.iter().any(|o| o.trim() == "*") {
            return Err("ALLOWED_ORIGINS must not contain '*' in prod/staging".to_string());
        }
        if prod_like
            && allowed_origins
                .iter()
                .any(|o| !o.trim().starts_with("https://"))
        {
            return Err("ALLOWED_ORIGINS must use https:// origins in prod/staging".to_string());
        }
        let max_body_bytes: usize = env_or("PAYMENTS_MAX_BODY_BYTES", "1048576")
            .parse()
            .map_err(|_| "PAYMENTS_MAX_BODY_BYTES must be an integer".to_string())?;
        let max_body_bytes = max_body_bytes.clamp(16 * 1024, 10 * 1024 * 1024);

        let mut default_currency = env_or("DEFAULT_CURRENCY", "SYP").trim().to_uppercase();
        if default_currency.is_empty() {
            default_currency = "SYP".to_string();
        }
        if default_currency.len() > 3 {
            truncate_utf8_safely(&mut default_currency, 3);
        }
        if !is_supported_wallet_currency(&default_currency) {
            return Err(format!(
                "DEFAULT_CURRENCY must be one of: {}",
                SUPPORTED_WALLET_CURRENCIES.join(", ")
            ));
        }

        let allow_direct_topup = {
            let raw = env_or("PAYMENTS_ALLOW_DIRECT_TOPUP", "");
            match parse_bool_like("PAYMENTS_ALLOW_DIRECT_TOPUP", &raw)? {
                Some(v) => v,
                None => {
                    // Backward-compatible fallback for older deploys that still
                    // use DEV_ENABLE_TOPUP.
                    let legacy_raw = env_or("DEV_ENABLE_TOPUP", "");
                    match parse_bool_like("DEV_ENABLE_TOPUP", &legacy_raw)? {
                        Some(v) => v,
                        None => dev_or_test,
                    }
                }
            }
        };
        if prod_like && allow_direct_topup {
            return Err("PAYMENTS_ALLOW_DIRECT_TOPUP must be false in prod/staging".to_string());
        }
        let allow_emergency_direct_topup = {
            let raw = env_or("PAYMENTS_EMERGENCY_DIRECT_TOPUP_ENABLED", "");
            parse_bool_like("PAYMENTS_EMERGENCY_DIRECT_TOPUP_ENABLED", &raw)?.unwrap_or_default()
        };
        if allow_direct_topup && allow_emergency_direct_topup {
            return Err(
                "PAYMENTS_ALLOW_DIRECT_TOPUP and PAYMENTS_EMERGENCY_DIRECT_TOPUP_ENABLED are mutually exclusive"
                    .to_string(),
            );
        }
        let require_idempotency_key = {
            let raw = env_or("PAYMENTS_REQUIRE_IDEMPOTENCY_KEY", "");
            match parse_bool_like("PAYMENTS_REQUIRE_IDEMPOTENCY_KEY", &raw)? {
                Some(v) => v,
                None => prod_like,
            }
        };
        if prod_like && !require_idempotency_key {
            return Err(
                "PAYMENTS_REQUIRE_IDEMPOTENCY_KEY must be true in prod/staging".to_string(),
            );
        }
        let default_merchant_fee_bps = if dev_or_test { "0" } else { "150" };
        let merchant_fee_bps: i64 = env_or("MERCHANT_FEE_BPS", default_merchant_fee_bps)
            .parse()
            .map_err(|_| "MERCHANT_FEE_BPS must be an integer".to_string())?;
        let merchant_fee_bps = merchant_fee_bps.clamp(0, 10_000);

        let fee_wallet_account_id = env_opt("FEE_WALLET_ACCOUNT_ID");
        let fee_wallet_phone = env_opt("FEE_WALLET_PHONE").unwrap_or_default();
        if prod_like
            && merchant_fee_bps > 0
            && fee_wallet_account_id
                .as_deref()
                .unwrap_or("")
                .trim()
                .is_empty()
            && fee_wallet_phone.trim().is_empty()
        {
            return Err(
                "FEE_WALLET_ACCOUNT_ID (recommended) or FEE_WALLET_PHONE must be set in prod/staging when MERCHANT_FEE_BPS > 0"
                    .to_string(),
            );
        }

        let admin_credit_max_amount_cents =
            parse_i64_env("PAYMENTS_ADMIN_CREDIT_MAX_AMOUNT_CENTS", "10000000000")?;
        if admin_credit_max_amount_cents <= 0 {
            return Err("PAYMENTS_ADMIN_CREDIT_MAX_AMOUNT_CENTS must be > 0".to_string());
        }
        let admin_credit_operator_daily_limit_cents = parse_i64_env(
            "PAYMENTS_ADMIN_CREDIT_OPERATOR_DAILY_LIMIT_CENTS",
            "10000000000",
        )?;
        if admin_credit_operator_daily_limit_cents < 0 {
            return Err(
                "PAYMENTS_ADMIN_CREDIT_OPERATOR_DAILY_LIMIT_CENTS must be >= 0".to_string(),
            );
        }
        if admin_credit_operator_daily_limit_cents > 0
            && admin_credit_operator_daily_limit_cents < admin_credit_max_amount_cents
        {
            return Err(
                "PAYMENTS_ADMIN_CREDIT_OPERATOR_DAILY_LIMIT_CENTS must be >= PAYMENTS_ADMIN_CREDIT_MAX_AMOUNT_CENTS or 0 to disable"
                    .to_string(),
            );
        }
        let mut admin_credit_approval_threshold_cents =
            parse_i64_env("PAYMENTS_ADMIN_CREDIT_APPROVAL_THRESHOLD_CENTS", "0")?;
        if admin_credit_approval_threshold_cents < 0 {
            return Err("PAYMENTS_ADMIN_CREDIT_APPROVAL_THRESHOLD_CENTS must be >= 0".to_string());
        }
        if admin_credit_approval_threshold_cents > admin_credit_max_amount_cents {
            admin_credit_approval_threshold_cents = admin_credit_max_amount_cents;
        }

        Ok(Self {
            env_name,
            host,
            port,
            max_body_bytes,
            db_url,
            db_schema,
            auto_apply_schema,
            auto_provision_fee_wallet,
            require_internal_secret,
            internal_secret,
            internal_allowed_callers,
            internal_identity_public_keys,
            internal_identity_max_skew_secs,
            require_internal_identity_v2,
            allow_legacy_internal_secret_fallback,
            allowed_hosts,
            allowed_origins,
            default_currency,
            allow_direct_topup,
            allow_emergency_direct_topup,
            require_idempotency_key,
            merchant_fee_bps,
            fee_wallet_account_id,
            fee_wallet_phone,
            admin_credit_max_amount_cents,
            admin_credit_operator_daily_limit_cents,
            admin_credit_approval_threshold_cents,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use shamell_common::internal_identity::InternalRequestSigner;
    use std::sync::{Mutex, OnceLock};

    static ENV_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

    struct EnvGuard {
        saved: Vec<(String, Option<String>)>,
    }

    impl EnvGuard {
        fn new(keys: &[&str]) -> Self {
            let mut keys = keys.to_vec();
            if !keys.contains(&"PAYMENTS_MAX_BODY_BYTES") {
                keys.push("PAYMENTS_MAX_BODY_BYTES");
            }
            if !keys.contains(&"ALLOWED_ORIGINS") {
                keys.push("ALLOWED_ORIGINS");
            }
            for extra in [
                "PAYMENTS_INTERNAL_IDENTITY_PUBLIC_KEYS",
                "PAYMENTS_INTERNAL_IDENTITY_MAX_SKEW_SECS",
                "PAYMENTS_REQUIRE_INTERNAL_IDENTITY_V2",
                "PAYMENTS_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK",
                "PAYMENTS_REQUIRE_IDEMPOTENCY_KEY",
                "PAYMENTS_EMERGENCY_DIRECT_TOPUP_ENABLED",
                "PAYMENTS_ADMIN_CREDIT_MAX_AMOUNT_CENTS",
                "PAYMENTS_ADMIN_CREDIT_OPERATOR_DAILY_LIMIT_CENTS",
                "PAYMENTS_ADMIN_CREDIT_APPROVAL_THRESHOLD_CENTS",
            ] {
                if !keys.contains(&extra) {
                    keys.push(extra);
                }
            }
            let mut saved = Vec::with_capacity(keys.len());
            for k in keys {
                let existing = env::var(k).ok();
                saved.push((k.to_string(), existing));
                env::remove_var(k);
            }
            install_default_internal_identity_env();
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

    fn install_default_internal_identity_env() {
        let signer = InternalRequestSigner::from_seed_bytes("bff", [7u8; 32]).expect("signer");
        env::set_var(
            "PAYMENTS_INTERNAL_IDENTITY_PUBLIC_KEYS",
            format!("bff={}", signer.public_key_base64()),
        );
        env::set_var("PAYMENTS_INTERNAL_IDENTITY_MAX_SKEW_SECS", "30");
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_IDENTITY_V2", "true");
        env::set_var("PAYMENTS_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK", "false");
    }

    #[test]
    fn rejects_unknown_environment_profile() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&["ENV"]);

        env::set_var("ENV", "qa");
        let err = Config::from_env().expect_err("unknown env profiles must fail closed");
        assert!(
            err.contains("ENV must be one of: dev, development, test, staging, prod, production")
        );
    }

    #[test]
    fn rejects_invalid_boolean_environment_values() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&["PAYMENTS_REQUIRE_IDEMPOTENCY_KEY"]);

        env::set_var("PAYMENTS_REQUIRE_IDEMPOTENCY_KEY", "enabled-ish");
        let err = Config::from_env().expect_err("invalid boolean env values must fail closed");
        assert!(err.contains("PAYMENTS_REQUIRE_IDEMPOTENCY_KEY must be one of"));
    }

    #[test]
    fn rejects_non_postgres_url() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
        ]);

        env::set_var("PAYMENTS_DB_URL", "sqlite:////tmp/payments.db");
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "false");

        let res = Config::from_env();
        assert!(res.is_err());
    }

    #[test]
    fn prod_requires_explicit_database_url() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&["ENV", "PAYMENTS_DB_URL", "DB_URL"]);

        env::set_var("ENV", "prod");
        env::remove_var("PAYMENTS_DB_URL");
        env::remove_var("DB_URL");

        let err = Config::from_env().expect_err("prod must fail closed without explicit DB url");
        assert!(err.contains("PAYMENTS_DB_URL (or DB_URL) must be set in prod/staging"));
    }

    #[test]
    fn prod_rejects_weak_internal_secret() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "PAYMENTS_INTERNAL_SECRET",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "change-me-secret");
        env::remove_var("PAYMENTS_INTERNAL_SECRET");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );

        let res = Config::from_env();
        assert!(res.is_err());
    }

    #[test]
    fn prod_allows_missing_internal_secret_when_identity_replaces_it() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "PAYMENTS_INTERNAL_SECRET",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "true");
        env::remove_var("INTERNAL_API_SECRET");
        env::remove_var("PAYMENTS_INTERNAL_SECRET");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );

        let cfg = Config::from_env().expect("identity config should replace shared secret");
        assert!(cfg.internal_secret.is_none());
        assert!(!cfg.internal_identity_public_keys.is_empty());
    }

    #[test]
    fn prod_rejects_legacy_secret_fallback_with_identity() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "PAYMENTS_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "payments-secret-0123456789");
        env::set_var("PAYMENTS_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK", "true");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );

        let err = Config::from_env().expect_err("legacy fallback must be rejected in prod");
        assert!(err.contains("PAYMENTS_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK"));
    }

    #[test]
    fn prod_rejects_internal_identity_v2_toggle_off() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "PAYMENTS_REQUIRE_INTERNAL_IDENTITY_V2",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "payments-secret-0123456789");
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_IDENTITY_V2", "false");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );

        let err = Config::from_env().expect_err("v2-only internal identity must be enforced");
        assert!(err.contains("PAYMENTS_REQUIRE_INTERNAL_IDENTITY_V2"));
    }

    #[test]
    fn prod_defaults_direct_topup_to_disabled() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "PAYMENTS_ALLOW_DIRECT_TOPUP",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "payments-secret-0123456789");
        env::remove_var("PAYMENTS_ALLOW_DIRECT_TOPUP");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );

        let cfg = Config::from_env().expect("config");
        assert!(!cfg.allow_direct_topup);
    }

    #[test]
    fn prod_rejects_enabling_direct_topup() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "PAYMENTS_ALLOW_DIRECT_TOPUP",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "payments-secret-0123456789");
        env::set_var("PAYMENTS_ALLOW_DIRECT_TOPUP", "true");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );

        let err = Config::from_env().expect_err("direct topup must be rejected in prod/staging");
        assert!(err.contains("PAYMENTS_ALLOW_DIRECT_TOPUP"));
    }

    #[test]
    fn prod_allows_emergency_direct_topup_toggle() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "PAYMENTS_ALLOW_DIRECT_TOPUP",
            "PAYMENTS_EMERGENCY_DIRECT_TOPUP_ENABLED",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "payments-secret-0123456789");
        env::set_var("PAYMENTS_ALLOW_DIRECT_TOPUP", "false");
        env::set_var("PAYMENTS_EMERGENCY_DIRECT_TOPUP_ENABLED", "true");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );

        let cfg = Config::from_env().expect("config");
        assert!(!cfg.allow_direct_topup);
        assert!(cfg.allow_emergency_direct_topup);
    }

    #[test]
    fn topup_toggles_are_mutually_exclusive() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "PAYMENTS_ALLOW_DIRECT_TOPUP",
            "PAYMENTS_EMERGENCY_DIRECT_TOPUP_ENABLED",
        ]);

        env::set_var("ENV", "dev");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("PAYMENTS_ALLOW_DIRECT_TOPUP", "true");
        env::set_var("PAYMENTS_EMERGENCY_DIRECT_TOPUP_ENABLED", "true");

        let err = Config::from_env().expect_err("topup toggles must not be enabled together");
        assert!(err.contains("mutually exclusive"));
    }

    #[test]
    fn prod_defaults_to_require_idempotency_key() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "PAYMENTS_REQUIRE_IDEMPOTENCY_KEY",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "payments-secret-0123456789");
        env::remove_var("PAYMENTS_REQUIRE_IDEMPOTENCY_KEY");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );

        let cfg = Config::from_env().expect("config");
        assert!(cfg.require_idempotency_key);
    }

    #[test]
    fn dev_defaults_to_optional_idempotency_key() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "PAYMENTS_REQUIRE_IDEMPOTENCY_KEY",
        ]);

        env::set_var("ENV", "dev");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "false");
        env::remove_var("PAYMENTS_REQUIRE_IDEMPOTENCY_KEY");

        let cfg = Config::from_env().expect("config");
        assert!(!cfg.require_idempotency_key);
    }

    #[test]
    fn prod_rejects_disabling_required_idempotency_key() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "PAYMENTS_REQUIRE_IDEMPOTENCY_KEY",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "payments-secret-0123456789");
        env::set_var("PAYMENTS_REQUIRE_IDEMPOTENCY_KEY", "false");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );

        let err = Config::from_env().expect_err("idempotency enforcement must be required");
        assert!(err.contains("PAYMENTS_REQUIRE_IDEMPOTENCY_KEY"));
    }

    #[test]
    fn default_currency_truncates_multibyte_input_without_panicking() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "DEFAULT_CURRENCY",
        ]);

        env::set_var("ENV", "dev");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("DEFAULT_CURRENCY", "€€");

        let cfg = Config::from_env().expect("config");
        assert_eq!(cfg.default_currency, "€");
        assert!(cfg.default_currency.len() <= 3);
    }

    #[test]
    fn dev_legacy_topup_toggle_is_still_supported() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "PAYMENTS_ALLOW_DIRECT_TOPUP",
            "DEV_ENABLE_TOPUP",
        ]);

        env::set_var("ENV", "dev");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("INTERNAL_API_SECRET", "payments-secret-0123456789");
        env::remove_var("PAYMENTS_ALLOW_DIRECT_TOPUP");
        env::set_var("DEV_ENABLE_TOPUP", "false");

        let cfg = Config::from_env().expect("config");
        assert!(!cfg.allow_direct_topup);
    }

    #[test]
    fn prod_rejects_wildcard_allowed_hosts() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "ALLOWED_HOSTS",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "payments-secret-0123456789");
        env::set_var("ALLOWED_HOSTS", "*");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );

        let err = Config::from_env().expect_err("wildcard hosts must be rejected in prod");
        assert!(err.contains("ALLOWED_HOSTS"));
    }

    #[test]
    fn rejects_allowed_hosts_with_scheme_or_path() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "ALLOWED_HOSTS",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "dev");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("INTERNAL_API_SECRET", "payments-secret-0123456789");
        env::set_var("ALLOWED_HOSTS", "https://payments.shamell.test/api");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );

        let err = Config::from_env().expect_err("url-form host must be rejected");
        assert!(err.contains("ALLOWED_HOSTS contains invalid host"));
        assert!(err.contains("plain host"));
    }

    #[test]
    fn rejects_allowed_hosts_with_wildcard_subdomain_pattern() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "ALLOWED_HOSTS",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "dev");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("INTERNAL_API_SECRET", "payments-secret-0123456789");
        env::set_var("ALLOWED_HOSTS", ".shamell.test");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );

        let err = Config::from_env().expect_err("wildcard subdomain host must be rejected");
        assert!(err.contains("ALLOWED_HOSTS contains invalid host"));
        assert!(err.contains("wildcard subdomain"));
    }

    #[test]
    fn prod_requires_explicit_allowed_origins() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "ALLOWED_ORIGINS",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "prod");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "payments-secret-0123456789");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::remove_var("ALLOWED_ORIGINS");

        let err = Config::from_env().expect_err("missing ALLOWED_ORIGINS must be rejected in prod");
        assert!(err.contains("ALLOWED_ORIGINS must be set in prod/staging"));
    }

    #[test]
    fn prod_rejects_non_https_allowed_origins() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "ALLOWED_ORIGINS",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "payments-secret-0123456789");
        env::set_var("ALLOWED_ORIGINS", "http://online.shamell.online");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );

        let err = Config::from_env().expect_err("non-https origins must be rejected in prod");
        assert!(err.contains("ALLOWED_ORIGINS must use https:// origins"));
    }

    #[test]
    fn rejects_allowed_origins_with_credentials() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "ALLOWED_ORIGINS",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("ALLOWED_ORIGINS", "https://user:pass@online.shamell.test");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("INTERNAL_API_SECRET", "payments-secret-0123456789");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );

        let err = Config::from_env().expect_err("credentialed origins must be rejected");
        assert!(err.contains("ALLOWED_ORIGINS contains invalid origin"));
        assert!(err.contains("must not include credentials"));
    }

    #[test]
    fn rejects_allowed_origins_with_non_root_path() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "ALLOWED_ORIGINS",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test/app");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("INTERNAL_API_SECRET", "payments-secret-0123456789");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );

        let err = Config::from_env().expect_err("path-bearing origins must be rejected");
        assert!(err.contains("ALLOWED_ORIGINS contains invalid origin"));
        assert!(err.contains("must not include a non-root path"));
    }

    #[test]
    fn canonicalizes_allowed_origins_to_origin_form() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "ALLOWED_ORIGINS",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "dev");
        env::set_var(
            "ALLOWED_ORIGINS",
            "HTTPS://online.shamell.test/,http://localhost:5173/",
        );
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("INTERNAL_API_SECRET", "payments-secret-0123456789");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );

        let cfg = Config::from_env().expect("config");
        assert_eq!(
            cfg.allowed_origins,
            vec![
                "https://online.shamell.test".to_string(),
                "http://localhost:5173".to_string()
            ]
        );
    }

    #[test]
    fn prod_rejects_internal_secret_toggle_off() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "false");

        let err = Config::from_env().expect_err("must reject disabled internal secret in prod");
        assert!(err.contains("PAYMENTS_REQUIRE_INTERNAL_SECRET must be true in prod/staging"));
    }

    #[test]
    fn body_limit_is_clamped_to_safe_bounds() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
        ]);

        env::set_var("ENV", "dev");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "false");

        env::set_var("PAYMENTS_MAX_BODY_BYTES", "1");
        let cfg = Config::from_env().expect("config");
        assert_eq!(cfg.max_body_bytes, 16 * 1024);

        env::set_var("PAYMENTS_MAX_BODY_BYTES", "999999999");
        let cfg = Config::from_env().expect("config");
        assert_eq!(cfg.max_body_bytes, 10 * 1024 * 1024);
    }

    #[test]
    fn dev_defaults_merchant_fee_bps_to_zero() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "MERCHANT_FEE_BPS",
        ]);

        env::set_var("ENV", "dev");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "false");
        env::remove_var("MERCHANT_FEE_BPS");

        let cfg = Config::from_env().expect("config");
        assert_eq!(cfg.merchant_fee_bps, 0);
    }

    #[test]
    fn prod_defaults_merchant_fee_bps_to_150() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "MERCHANT_FEE_BPS",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "payments-secret-0123456789");
        env::remove_var("MERCHANT_FEE_BPS");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );

        let cfg = Config::from_env().expect("config");
        assert_eq!(cfg.merchant_fee_bps, 150);
    }

    #[test]
    fn prod_defaults_schema_bootstrap_to_disabled() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "PAYMENTS_AUTO_APPLY_SCHEMA",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "payments-secret-0123456789");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::remove_var("PAYMENTS_AUTO_APPLY_SCHEMA");

        let cfg = Config::from_env().expect("config");
        assert!(!cfg.auto_apply_schema);
    }

    #[test]
    fn prod_defaults_fee_wallet_provisioning_to_disabled() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "PAYMENTS_AUTO_PROVISION_FEE_WALLET",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "payments-secret-0123456789");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::remove_var("PAYMENTS_AUTO_PROVISION_FEE_WALLET");

        let cfg = Config::from_env().expect("config");
        assert!(!cfg.auto_provision_fee_wallet);
    }

    #[test]
    fn dev_defaults_schema_bootstrap_to_enabled() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "PAYMENTS_AUTO_APPLY_SCHEMA",
        ]);

        env::set_var("ENV", "dev");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "false");
        env::remove_var("PAYMENTS_AUTO_APPLY_SCHEMA");

        let cfg = Config::from_env().expect("config");
        assert!(cfg.auto_apply_schema);
    }

    #[test]
    fn dev_defaults_fee_wallet_provisioning_to_enabled() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "PAYMENTS_AUTO_PROVISION_FEE_WALLET",
        ]);

        env::set_var("ENV", "dev");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "false");
        env::remove_var("PAYMENTS_AUTO_PROVISION_FEE_WALLET");

        let cfg = Config::from_env().expect("config");
        assert!(cfg.auto_provision_fee_wallet);
    }

    #[test]
    fn prod_can_opt_in_schema_bootstrap_explicitly() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "PAYMENTS_AUTO_APPLY_SCHEMA",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "payments-secret-0123456789");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("PAYMENTS_AUTO_APPLY_SCHEMA", "true");

        let cfg = Config::from_env().expect("config");
        assert!(cfg.auto_apply_schema);
    }

    #[test]
    fn prod_can_opt_in_fee_wallet_provisioning_explicitly() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "PAYMENTS_AUTO_PROVISION_FEE_WALLET",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "payments-secret-0123456789");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("PAYMENTS_AUTO_PROVISION_FEE_WALLET", "true");

        let cfg = Config::from_env().expect("config");
        assert!(cfg.auto_provision_fee_wallet);
    }
}
