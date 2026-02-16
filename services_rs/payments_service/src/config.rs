use regex::Regex;
use shamell_common::secret_policy;
use std::env;

#[derive(Clone, Debug)]
pub struct Config {
    pub env_name: String,

    pub host: String,
    pub port: u16,
    pub max_body_bytes: usize,

    pub db_url: String,
    pub db_schema: Option<String>,

    pub require_internal_secret: bool,
    pub internal_secret: Option<String>,
    pub internal_allowed_callers: Vec<String>,
    pub bus_payments_internal_secret: Option<String>,

    pub allowed_hosts: Vec<String>,
    pub allowed_origins: Vec<String>,

    pub default_currency: String,
    pub allow_direct_topup: bool,
    pub merchant_fee_bps: i64,
    pub fee_wallet_account_id: Option<String>,
    pub fee_wallet_phone: String,
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

fn parse_bool_like(raw: &str) -> Option<bool> {
    let v = raw.trim().to_lowercase();
    if v.is_empty() {
        return None;
    }
    if matches!(v.as_str(), "0" | "false" | "no" | "off") {
        Some(false)
    } else {
        Some(true)
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

impl Config {
    pub fn from_env() -> Result<Self, String> {
        let env_name = env_or("ENV", "dev");
        let env_lower = env_name.trim().to_lowercase();

        let host = env_or("APP_HOST", "0.0.0.0");
        let port: u16 = env_or("APP_PORT", "8082")
            .parse()
            .map_err(|_| "APP_PORT must be a valid u16".to_string())?;

        let db_raw = env_opt("PAYMENTS_DB_URL")
            .or_else(|| env_opt("DB_URL"))
            .unwrap_or_else(|| "postgresql://shamell:shamell@db:5432/shamell_payments".to_string());
        let db_url = normalize_db_url(&db_raw);
        validate_postgres_url(&db_url)?;

        let db_schema = env_opt("DB_SCHEMA");
        if let Some(s) = &db_schema {
            let re = Regex::new(r"^[A-Za-z_][A-Za-z0-9_]*$").map_err(|e| e.to_string())?;
            if !re.is_match(s) {
                return Err("DB_SCHEMA must match ^[A-Za-z_][A-Za-z0-9_]*$".to_string());
            }
        }

        let prod_like = matches!(env_lower.as_str(), "prod" | "production" | "staging");

        let require_internal_secret = {
            let raw = env_or("PAYMENTS_REQUIRE_INTERNAL_SECRET", "");
            match parse_bool_like(&raw) {
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
        if require_internal_secret && internal_secret.as_deref().unwrap_or("").is_empty() {
            return Err(
                "INTERNAL_API_SECRET must be set when PAYMENTS_REQUIRE_INTERNAL_SECRET is enabled"
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

        let bus_payments_internal_secret = env_opt("BUS_PAYMENTS_INTERNAL_SECRET");
        if prod_like
            && bus_payments_internal_secret
                .as_deref()
                .unwrap_or("")
                .trim()
                .is_empty()
        {
            return Err("BUS_PAYMENTS_INTERNAL_SECRET must be set in prod/staging".to_string());
        }
        secret_policy::validate_secret_for_env(
            &env_name,
            "BUS_PAYMENTS_INTERNAL_SECRET",
            bus_payments_internal_secret.as_deref(),
            false,
        )?;

        let mut allowed_hosts = parse_csv(&env_or("ALLOWED_HOSTS", ""));
        if allowed_hosts.is_empty() {
            // Fail closed on missing host allowlist:
            // - dev/test keep loopback defaults for local ergonomics
            // - prod/staging requires explicit external hosts from ALLOWED_HOSTS
            if matches!(env_lower.as_str(), "dev" | "test") {
                allowed_hosts = vec!["localhost".to_string(), "127.0.0.1".to_string()];
            }
        }
        if matches!(env_lower.as_str(), "dev" | "test") {
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
        if prod_like && allowed_hosts.iter().any(|h| h.trim() == "*") {
            return Err("ALLOWED_HOSTS must not contain '*' in prod/staging".to_string());
        }

        let mut allowed_origins = parse_csv(&env_or("ALLOWED_ORIGINS", ""));
        if allowed_origins.is_empty() {
            allowed_origins = vec![
                "http://localhost:5173".to_string(),
                "http://127.0.0.1:5173".to_string(),
            ];
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
            default_currency.truncate(3);
        }

        let allow_direct_topup = {
            let raw = env_or("PAYMENTS_ALLOW_DIRECT_TOPUP", "");
            match parse_bool_like(&raw) {
                Some(v) => v,
                None => matches!(env_lower.as_str(), "dev" | "test"),
            }
        };
        let merchant_fee_bps: i64 = env_or("MERCHANT_FEE_BPS", "150")
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

        Ok(Self {
            env_name,
            host,
            port,
            max_body_bytes,
            db_url,
            db_schema,
            require_internal_secret,
            internal_secret,
            internal_allowed_callers,
            bus_payments_internal_secret,
            allowed_hosts,
            allowed_origins,
            default_currency,
            allow_direct_topup,
            merchant_fee_bps,
            fee_wallet_account_id,
            fee_wallet_phone,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
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
            let mut saved = Vec::with_capacity(keys.len());
            for k in keys {
                let existing = env::var(k).ok();
                saved.push((k.to_string(), existing));
                env::remove_var(k);
            }
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
    fn prod_rejects_weak_internal_secret() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "PAYMENTS_INTERNAL_SECRET",
            "BUS_PAYMENTS_INTERNAL_SECRET",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "prod");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "change-me-secret");
        env::remove_var("PAYMENTS_INTERNAL_SECRET");
        env::set_var(
            "BUS_PAYMENTS_INTERNAL_SECRET",
            "bus-pay-bind-secret-0123456789",
        );
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );

        let res = Config::from_env();
        assert!(res.is_err());
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
            "BUS_PAYMENTS_INTERNAL_SECRET",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "prod");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "payments-secret-0123456789");
        env::remove_var("PAYMENTS_ALLOW_DIRECT_TOPUP");
        env::set_var(
            "BUS_PAYMENTS_INTERNAL_SECRET",
            "bus-pay-bind-secret-0123456789",
        );
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );

        let cfg = Config::from_env().expect("config");
        assert!(!cfg.allow_direct_topup);
    }

    #[test]
    fn prod_requires_bus_binding_secret_when_bus_caller_enabled() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_DB_URL",
            "DB_URL",
            "PAYMENTS_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "PAYMENTS_INTERNAL_ALLOWED_CALLERS",
            "BUS_PAYMENTS_INTERNAL_SECRET",
            "FEE_WALLET_ACCOUNT_ID",
        ]);

        env::set_var("ENV", "prod");
        env::set_var(
            "PAYMENTS_DB_URL",
            "postgresql://u:p@localhost:5432/payments",
        );
        env::set_var("PAYMENTS_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "payments-secret-0123456789");
        env::set_var("PAYMENTS_INTERNAL_ALLOWED_CALLERS", "bff,bus");
        env::remove_var("BUS_PAYMENTS_INTERNAL_SECRET");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );

        let res = Config::from_env();
        assert!(res.is_err());
        let msg = res.err().unwrap_or_default();
        assert!(msg.contains("BUS_PAYMENTS_INTERNAL_SECRET"));
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
            "BUS_PAYMENTS_INTERNAL_SECRET",
            "ALLOWED_HOSTS",
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
            "BUS_PAYMENTS_INTERNAL_SECRET",
            "bus-pay-bind-secret-0123456789",
        );
        env::set_var("ALLOWED_HOSTS", "*");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );

        let err = Config::from_env().expect_err("wildcard hosts must be rejected in prod");
        assert!(err.contains("ALLOWED_HOSTS"));
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
            "BUS_PAYMENTS_INTERNAL_SECRET",
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
            "BUS_PAYMENTS_INTERNAL_SECRET",
            "bus-pay-bind-secret-0123456789",
        );
        env::set_var("ALLOWED_ORIGINS", "http://online.shamell.online");
        env::set_var(
            "FEE_WALLET_ACCOUNT_ID",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );

        let err = Config::from_env().expect_err("non-https origins must be rejected in prod");
        assert!(err.contains("ALLOWED_ORIGINS must use https:// origins"));
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
}
