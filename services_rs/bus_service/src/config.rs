use regex::Regex;
use shamell_common::secret_policy;
use std::env;

#[derive(Clone, Debug)]
pub struct Config {
    pub env_name: String,
    pub env_lower: String,

    pub host: String,
    pub port: u16,
    pub max_body_bytes: usize,

    pub db_url: String,
    pub db_schema: Option<String>,

    pub ticket_secret: String,

    pub require_internal_secret: bool,
    pub internal_secret: Option<String>,
    pub internal_allowed_callers: Vec<String>,
    pub internal_service_id: String,

    pub allowed_hosts: Vec<String>,
    pub allowed_origins: Vec<String>,

    pub payments_base_url: Option<String>,
    pub bus_payments_internal_secret: Option<String>,
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
        _ => Err("BUS_DB_URL (or DB_URL) must be a postgres URL".to_string()),
    }
}

fn parse_required_bool_like(raw: &str) -> Option<bool> {
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

impl Config {
    pub fn from_env() -> Result<Self, String> {
        let env_name = env_or("ENV", "dev");
        let env_lower = env_name.trim().to_lowercase();

        let host = env_or("APP_HOST", "0.0.0.0");
        let port: u16 = env_or("APP_PORT", "8083")
            .parse()
            .map_err(|_| "APP_PORT must be a valid u16".to_string())?;

        let db_raw = env_opt("BUS_DB_URL")
            .or_else(|| env_opt("DB_URL"))
            .unwrap_or_else(|| "postgresql://shamell:shamell@db:5432/shamell_bus".to_string());
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

        let ticket_secret = env_or("BUS_TICKET_SECRET", "change-me-bus-ticket");
        secret_policy::enforce_value_policy_for_env(
            &env_name,
            "BUS_TICKET_SECRET",
            Some(ticket_secret.as_str()),
            !matches!(env_lower.as_str(), "dev" | "test"),
        )?;

        let require_internal_secret = {
            let raw = env_or("BUS_REQUIRE_INTERNAL_SECRET", "");
            match parse_required_bool_like(&raw) {
                Some(v) => v,
                None => prod_like,
            }
        };
        if prod_like && !require_internal_secret {
            return Err("BUS_REQUIRE_INTERNAL_SECRET must be true in prod/staging".to_string());
        }

        let internal_secret = env_opt("BUS_INTERNAL_SECRET");
        if require_internal_secret && internal_secret.as_deref().unwrap_or("").is_empty() {
            return Err(
                "BUS_INTERNAL_SECRET must be set when BUS_REQUIRE_INTERNAL_SECRET is enabled"
                    .to_string(),
            );
        }
        secret_policy::enforce_value_policy_for_env(
            &env_name,
            "BUS_INTERNAL_SECRET",
            internal_secret.as_deref(),
            false,
        )?;

        let mut internal_allowed_callers = parse_csv(&env_or("BUS_INTERNAL_ALLOWED_CALLERS", ""))
            .into_iter()
            .map(|v| v.trim().to_ascii_lowercase())
            .filter(|v| !v.is_empty())
            .collect::<Vec<_>>();
        if internal_allowed_callers.is_empty() && prod_like {
            internal_allowed_callers = vec!["bff".to_string()];
        }
        if require_internal_secret && prod_like && internal_allowed_callers.is_empty() {
            return Err(
                "BUS_INTERNAL_ALLOWED_CALLERS must define at least one caller in prod/staging"
                    .to_string(),
            );
        }

        let internal_service_id = env_or("BUS_INTERNAL_SERVICE_ID", "bus")
            .trim()
            .to_ascii_lowercase();
        if internal_service_id.is_empty()
            || internal_service_id.len() > 64
            || !internal_service_id
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'))
        {
            return Err("BUS_INTERNAL_SERVICE_ID must be 1..64 [A-Za-z0-9-_.]".to_string());
        }

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
        // Keep service-to-service calls working.
        for extra in ["bus"] {
            if !allowed_hosts.iter().any(|h| h == extra) {
                allowed_hosts.push(extra.to_string());
            }
        }
        if prod_like && allowed_hosts.iter().any(|h| h.trim() == "*") {
            return Err("ALLOWED_HOSTS must not contain '*' in prod/staging".to_string());
        }

        let mut allowed_origins = parse_csv(&env_or("ALLOWED_ORIGINS", ""));
        if allowed_origins.is_empty() {
            // Safe local default for development.
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
        let max_body_bytes: usize = env_or("BUS_MAX_BODY_BYTES", "1048576")
            .parse()
            .map_err(|_| "BUS_MAX_BODY_BYTES must be an integer".to_string())?;
        let max_body_bytes = max_body_bytes.clamp(16 * 1024, 10 * 1024 * 1024);

        let payments_base_url = env_opt("PAYMENTS_BASE_URL");
        let bus_payments_internal_secret = env_opt("BUS_PAYMENTS_INTERNAL_SECRET");
        if payments_base_url.is_some()
            && !matches!(env_lower.as_str(), "dev" | "test")
            && bus_payments_internal_secret.is_none()
        {
            return Err(
                "BUS_PAYMENTS_INTERNAL_SECRET must be set when PAYMENTS_BASE_URL is configured"
                    .to_string(),
            );
        }
        secret_policy::enforce_value_policy_for_env(
            &env_name,
            "BUS_PAYMENTS_INTERNAL_SECRET",
            bus_payments_internal_secret.as_deref(),
            false,
        )?;

        Ok(Self {
            env_name,
            env_lower,
            host,
            port,
            max_body_bytes,
            db_url,
            db_schema,
            ticket_secret,
            require_internal_secret,
            internal_secret,
            internal_allowed_callers,
            internal_service_id,
            allowed_hosts,
            allowed_origins,
            payments_base_url,
            bus_payments_internal_secret,
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
            for required in ["BUS_MAX_BODY_BYTES", "ALLOWED_HOSTS", "ALLOWED_ORIGINS"] {
                if !keys.contains(&required) {
                    keys.push(required);
                }
            }
            let mut saved = Vec::with_capacity(keys.len());
            for k in keys {
                let existing = env::var(k).ok();
                saved.push((k.to_string(), existing));
                env::remove_var(k);
            }
            env::set_var("ALLOWED_HOSTS", "online.shamell.online");
            env::set_var("ALLOWED_ORIGINS", "https://online.shamell.online");
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
            "BUS_DB_URL",
            "DB_URL",
            "BUS_TICKET_SECRET",
            "BUS_REQUIRE_INTERNAL_SECRET",
        ]);

        env::set_var("BUS_DB_URL", "sqlite:////tmp/bus.db");
        env::set_var("BUS_TICKET_SECRET", "ffffffffffffffffffffffffffffffff");
        // Avoid unrelated failures on internal secret.
        env::set_var("BUS_REQUIRE_INTERNAL_SECRET", "false");

        let res = Config::from_env();
        assert!(res.is_err());
    }

    #[test]
    fn prod_rejects_weak_ticket_secret() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&["ENV", "BUS_DB_URL", "DB_URL", "BUS_TICKET_SECRET"]);

        env::set_var("ENV", "prod");
        env::set_var("BUS_DB_URL", "postgresql://u:p@localhost:5432/bus");
        env::set_var("BUS_TICKET_SECRET", "change-me-bus-ticket");

        let res = Config::from_env();
        assert!(res.is_err());
    }

    #[test]
    fn prod_requires_bus_payments_secret_when_payments_enabled() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "BUS_DB_URL",
            "DB_URL",
            "BUS_TICKET_SECRET",
            "BUS_REQUIRE_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "PAYMENTS_BASE_URL",
            "BUS_PAYMENTS_INTERNAL_SECRET",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("BUS_DB_URL", "postgresql://u:p@localhost:5432/bus");
        env::set_var("BUS_TICKET_SECRET", "ffffffffffffffffffffffffffffffff");
        env::set_var("BUS_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::remove_var("BUS_PAYMENTS_INTERNAL_SECRET");

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
            "BUS_DB_URL",
            "DB_URL",
            "BUS_TICKET_SECRET",
            "BUS_REQUIRE_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "ALLOWED_HOSTS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("BUS_DB_URL", "postgresql://u:p@localhost:5432/bus");
        env::set_var("BUS_TICKET_SECRET", "ffffffffffffffffffffffffffffffff");
        env::set_var("BUS_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("ALLOWED_HOSTS", "*");

        let err = Config::from_env().expect_err("wildcard hosts must be rejected in prod");
        assert!(err.contains("ALLOWED_HOSTS"));
    }

    #[test]
    fn prod_rejects_non_https_allowed_origins() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "BUS_DB_URL",
            "DB_URL",
            "BUS_TICKET_SECRET",
            "BUS_REQUIRE_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "ALLOWED_ORIGINS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("BUS_DB_URL", "postgresql://u:p@localhost:5432/bus");
        env::set_var("BUS_TICKET_SECRET", "ffffffffffffffffffffffffffffffff");
        env::set_var("BUS_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("ALLOWED_ORIGINS", "http://online.shamell.online");

        let err = Config::from_env().expect_err("non-https origins must be rejected in prod");
        assert!(err.contains("ALLOWED_ORIGINS must use https:// origins"));
    }

    #[test]
    fn prod_rejects_internal_secret_toggle_off() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "BUS_DB_URL",
            "DB_URL",
            "BUS_TICKET_SECRET",
            "BUS_REQUIRE_INTERNAL_SECRET",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("BUS_DB_URL", "postgresql://u:p@localhost:5432/bus");
        env::set_var("BUS_TICKET_SECRET", "ffffffffffffffffffffffffffffffff");
        env::set_var("BUS_REQUIRE_INTERNAL_SECRET", "false");

        let err = Config::from_env().expect_err("must reject disabled internal secret in prod");
        assert!(err.contains("BUS_REQUIRE_INTERNAL_SECRET must be true in prod/staging"));
    }

    #[test]
    fn body_limit_is_clamped_to_safe_bounds() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "BUS_DB_URL",
            "DB_URL",
            "BUS_TICKET_SECRET",
            "BUS_REQUIRE_INTERNAL_SECRET",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("BUS_DB_URL", "postgresql://u:p@localhost:5432/bus");
        env::set_var("BUS_TICKET_SECRET", "ffffffffffffffffffffffffffffffff");
        env::set_var("BUS_REQUIRE_INTERNAL_SECRET", "false");

        env::set_var("BUS_MAX_BODY_BYTES", "1");
        let cfg = Config::from_env().expect("config");
        assert_eq!(cfg.max_body_bytes, 16 * 1024);

        env::set_var("BUS_MAX_BODY_BYTES", "999999999");
        let cfg = Config::from_env().expect("config");
        assert_eq!(cfg.max_body_bytes, 10 * 1024 * 1024);
    }
}
