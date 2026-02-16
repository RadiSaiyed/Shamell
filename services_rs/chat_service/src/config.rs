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

    pub enforce_device_auth: bool,

    pub allowed_hosts: Vec<String>,
    pub allowed_origins: Vec<String>,

    pub purge_interval_seconds: i64,
    pub fcm_server_key: Option<String>,
    pub chat_protocol_v2_enabled: bool,
    pub chat_protocol_v1_write_enabled: bool,
    pub chat_protocol_v1_read_enabled: bool,
    pub chat_protocol_require_v2_for_groups: bool,
    pub chat_mailbox_api_enabled: bool,
    pub chat_mailbox_inactive_retention_secs: i64,
    pub chat_mailbox_consumed_retention_secs: i64,
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
        _ => Err("CHAT_DB_URL (or DB_URL) must be a postgres URL".to_string()),
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
        let port: u16 = env_or("APP_PORT", "8081")
            .parse()
            .map_err(|_| "APP_PORT must be a valid u16".to_string())?;

        let db_raw = env_opt("CHAT_DB_URL")
            .or_else(|| env_opt("DB_URL"))
            .unwrap_or_else(|| "postgresql://shamell:shamell@db:5432/shamell_chat".to_string());
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
            let raw = env_or("CHAT_REQUIRE_INTERNAL_SECRET", "");
            match parse_required_bool_like(&raw) {
                Some(v) => v,
                None => prod_like,
            }
        };
        if prod_like && !require_internal_secret {
            return Err("CHAT_REQUIRE_INTERNAL_SECRET must be true in prod/staging".to_string());
        }
        let internal_secret =
            env_opt("INTERNAL_API_SECRET").or_else(|| env_opt("CHAT_INTERNAL_SECRET"));
        if require_internal_secret && internal_secret.as_deref().unwrap_or("").is_empty() {
            return Err(
                "INTERNAL_API_SECRET must be set when CHAT_REQUIRE_INTERNAL_SECRET is enabled"
                    .to_string(),
            );
        }
        secret_policy::validate_secret_for_env(
            &env_name,
            "INTERNAL_API_SECRET",
            internal_secret.as_deref(),
            false,
        )?;

        let mut internal_allowed_callers = parse_csv(&env_or("CHAT_INTERNAL_ALLOWED_CALLERS", ""))
            .into_iter()
            .map(|v| v.trim().to_ascii_lowercase())
            .filter(|v| !v.is_empty())
            .collect::<Vec<_>>();
        if internal_allowed_callers.is_empty() && prod_like {
            internal_allowed_callers = vec!["bff".to_string()];
        }
        if require_internal_secret && prod_like && internal_allowed_callers.is_empty() {
            return Err(
                "CHAT_INTERNAL_ALLOWED_CALLERS must define at least one caller in prod/staging"
                    .to_string(),
            );
        }

        let enforce_device_auth = {
            let raw = env_or("CHAT_ENFORCE_DEVICE_AUTH", "");
            match parse_required_bool_like(&raw) {
                Some(v) => v,
                None => prod_like,
            }
        };
        if prod_like && !enforce_device_auth {
            return Err("CHAT_ENFORCE_DEVICE_AUTH must be true in prod/staging".to_string());
        }
        let legacy_auth_bootstrap_enabled =
            parse_required_bool_like(&env_or("CHAT_ALLOW_LEGACY_AUTH_BOOTSTRAP", ""))
                .unwrap_or(false);
        if legacy_auth_bootstrap_enabled {
            return Err(
                "CHAT_ALLOW_LEGACY_AUTH_BOOTSTRAP is no longer supported and must remain disabled"
                    .to_string(),
            );
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
        for extra in ["chat"] {
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

        let max_body_bytes: usize = env_or("CHAT_MAX_BODY_BYTES", "2097152")
            .parse()
            .map_err(|_| "CHAT_MAX_BODY_BYTES must be an integer".to_string())?;
        let max_body_bytes = max_body_bytes.clamp(16 * 1024, 10 * 1024 * 1024);

        let purge_interval_seconds: i64 = env_or("CHAT_PURGE_INTERVAL_SECONDS", "600")
            .parse()
            .map_err(|_| "CHAT_PURGE_INTERVAL_SECONDS must be an integer".to_string())?;

        let fcm_server_key = env_opt("FCM_SERVER_KEY");

        let chat_protocol_v2_enabled =
            parse_required_bool_like(&env_or("CHAT_PROTOCOL_V2_ENABLED", "true")).unwrap_or(true);
        let chat_protocol_v1_write_enabled =
            parse_required_bool_like(&env_or("CHAT_PROTOCOL_V1_WRITE_ENABLED", "false"))
                .unwrap_or(false);
        let chat_protocol_v1_read_enabled =
            parse_required_bool_like(&env_or("CHAT_PROTOCOL_V1_READ_ENABLED", "false"))
                .unwrap_or(false);
        let chat_protocol_require_v2_for_groups =
            parse_required_bool_like(&env_or("CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS", "true"))
                .unwrap_or(true);
        let chat_mailbox_api_enabled =
            parse_required_bool_like(&env_or("CHAT_MAILBOX_API_ENABLED", "false")).unwrap_or(false);
        let chat_mailbox_inactive_retention_secs: i64 =
            env_or("CHAT_MAILBOX_INACTIVE_RETENTION_SECS", "86400")
                .parse::<i64>()
                .map_err(|_| "CHAT_MAILBOX_INACTIVE_RETENTION_SECS must be an integer".to_string())?
                .clamp(0, 31_536_000);
        let chat_mailbox_consumed_retention_secs: i64 =
            env_or("CHAT_MAILBOX_CONSUMED_RETENTION_SECS", "3600")
                .parse::<i64>()
                .map_err(|_| "CHAT_MAILBOX_CONSUMED_RETENTION_SECS must be an integer".to_string())?
                .clamp(0, 31_536_000);

        if !chat_protocol_v2_enabled && chat_protocol_require_v2_for_groups {
            return Err(
                "CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS=true requires CHAT_PROTOCOL_V2_ENABLED=true"
                    .to_string(),
            );
        }
        if prod_like && !chat_protocol_require_v2_for_groups {
            return Err(
                "CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS must be true in prod/staging (no group chat protocol downgrade)"
                    .to_string(),
            );
        }
        if prod_like && (chat_protocol_v1_write_enabled || chat_protocol_v1_read_enabled) {
            return Err(
                "legacy chat protocol v1 must remain disabled in prod/staging; set CHAT_PROTOCOL_V1_WRITE_ENABLED=false and CHAT_PROTOCOL_V1_READ_ENABLED=false"
                    .to_string(),
            );
        }
        if !chat_protocol_v2_enabled && !chat_protocol_v1_write_enabled {
            return Err(
                "at least one of CHAT_PROTOCOL_V2_ENABLED or CHAT_PROTOCOL_V1_WRITE_ENABLED must be enabled"
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
            enforce_device_auth,
            allowed_hosts,
            allowed_origins,
            purge_interval_seconds,
            fcm_server_key,
            chat_protocol_v2_enabled,
            chat_protocol_v1_write_enabled,
            chat_protocol_v1_read_enabled,
            chat_protocol_require_v2_for_groups,
            chat_mailbox_api_enabled,
            chat_mailbox_inactive_retention_secs,
            chat_mailbox_consumed_retention_secs,
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
            if !keys.contains(&"CHAT_ENFORCE_DEVICE_AUTH") {
                keys.push("CHAT_ENFORCE_DEVICE_AUTH");
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
            "CHAT_DB_URL",
            "DB_URL",
            "DB_SCHEMA",
            "CHAT_MAX_BODY_BYTES",
            "CHAT_REQUIRE_INTERNAL_SECRET",
            "CHAT_PROTOCOL_V2_ENABLED",
            "CHAT_PROTOCOL_V1_WRITE_ENABLED",
            "CHAT_PROTOCOL_V1_READ_ENABLED",
            "CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS",
            "CHAT_MAILBOX_API_ENABLED",
            "CHAT_MAILBOX_INACTIVE_RETENTION_SECS",
            "CHAT_MAILBOX_CONSUMED_RETENTION_SECS",
        ]);

        env::set_var("CHAT_DB_URL", "sqlite:////tmp/chat.db");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "false");

        let res = Config::from_env();
        assert!(res.is_err());
    }

    #[test]
    fn prod_rejects_weak_internal_secret() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "CHAT_DB_URL",
            "DB_URL",
            "DB_SCHEMA",
            "CHAT_MAX_BODY_BYTES",
            "CHAT_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "CHAT_INTERNAL_SECRET",
            "CHAT_PROTOCOL_V2_ENABLED",
            "CHAT_PROTOCOL_V1_WRITE_ENABLED",
            "CHAT_PROTOCOL_V1_READ_ENABLED",
            "CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS",
            "CHAT_MAILBOX_API_ENABLED",
            "CHAT_MAILBOX_INACTIVE_RETENTION_SECS",
            "CHAT_MAILBOX_CONSUMED_RETENTION_SECS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "change-me-secret");
        env::remove_var("CHAT_INTERNAL_SECRET");

        let res = Config::from_env();
        assert!(res.is_err());
    }

    #[test]
    fn rejects_legacy_auth_bootstrap_when_enabled() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "CHAT_DB_URL",
            "DB_URL",
            "DB_SCHEMA",
            "CHAT_MAX_BODY_BYTES",
            "CHAT_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "CHAT_ALLOW_LEGACY_AUTH_BOOTSTRAP",
            "CHAT_PROTOCOL_V2_ENABLED",
            "CHAT_PROTOCOL_V1_WRITE_ENABLED",
            "CHAT_PROTOCOL_V1_READ_ENABLED",
            "CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS",
            "CHAT_MAILBOX_API_ENABLED",
            "CHAT_MAILBOX_INACTIVE_RETENTION_SECS",
            "CHAT_MAILBOX_CONSUMED_RETENTION_SECS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "chat-secret-0123456789");
        env::set_var("CHAT_ALLOW_LEGACY_AUTH_BOOTSTRAP", "true");

        let err = Config::from_env().expect_err("legacy bootstrap should be rejected");
        assert!(err.contains("CHAT_ALLOW_LEGACY_AUTH_BOOTSTRAP"));
    }

    #[test]
    fn prod_rejects_wildcard_allowed_hosts() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "CHAT_DB_URL",
            "DB_URL",
            "DB_SCHEMA",
            "CHAT_MAX_BODY_BYTES",
            "CHAT_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "ALLOWED_HOSTS",
            "CHAT_PROTOCOL_V2_ENABLED",
            "CHAT_PROTOCOL_V1_WRITE_ENABLED",
            "CHAT_PROTOCOL_V1_READ_ENABLED",
            "CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS",
            "CHAT_MAILBOX_API_ENABLED",
            "CHAT_MAILBOX_INACTIVE_RETENTION_SECS",
            "CHAT_MAILBOX_CONSUMED_RETENTION_SECS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "chat-secret-0123456789");
        env::set_var("ALLOWED_HOSTS", "*");

        let err = Config::from_env().expect_err("wildcard hosts must be rejected in prod");
        assert!(err.contains("ALLOWED_HOSTS"));
    }

    #[test]
    fn prod_rejects_non_https_allowed_origins() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "CHAT_DB_URL",
            "DB_URL",
            "DB_SCHEMA",
            "CHAT_MAX_BODY_BYTES",
            "CHAT_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "ALLOWED_ORIGINS",
            "CHAT_PROTOCOL_V2_ENABLED",
            "CHAT_PROTOCOL_V1_WRITE_ENABLED",
            "CHAT_PROTOCOL_V1_READ_ENABLED",
            "CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS",
            "CHAT_MAILBOX_API_ENABLED",
            "CHAT_MAILBOX_INACTIVE_RETENTION_SECS",
            "CHAT_MAILBOX_CONSUMED_RETENTION_SECS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "chat-secret-0123456789");
        env::set_var("ALLOWED_ORIGINS", "http://online.shamell.online");

        let err = Config::from_env().expect_err("non-https origins must be rejected in prod");
        assert!(err.contains("ALLOWED_ORIGINS must use https:// origins"));
    }

    #[test]
    fn prod_rejects_v1_protocol_flags_when_enabled() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "CHAT_DB_URL",
            "CHAT_MAX_BODY_BYTES",
            "CHAT_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "CHAT_PROTOCOL_V2_ENABLED",
            "CHAT_PROTOCOL_V1_WRITE_ENABLED",
            "CHAT_PROTOCOL_V1_READ_ENABLED",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "chat-secret-0123456789");
        env::set_var("CHAT_PROTOCOL_V2_ENABLED", "true");
        env::set_var("CHAT_PROTOCOL_V1_WRITE_ENABLED", "true");
        env::set_var("CHAT_PROTOCOL_V1_READ_ENABLED", "true");

        let err = Config::from_env().expect_err("v1 flags must be rejected in prod");
        assert!(err.contains("legacy chat protocol v1"));
    }

    #[test]
    fn prod_rejects_device_auth_toggle_off() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "CHAT_DB_URL",
            "CHAT_MAX_BODY_BYTES",
            "CHAT_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "CHAT_ENFORCE_DEVICE_AUTH",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "chat-secret-0123456789");
        env::set_var("CHAT_ENFORCE_DEVICE_AUTH", "false");

        let err = Config::from_env().expect_err("must reject disabled device auth in prod");
        assert!(err.contains("CHAT_ENFORCE_DEVICE_AUTH must be true in prod/staging"));
    }

    #[test]
    fn prod_rejects_internal_secret_toggle_off() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "CHAT_DB_URL",
            "CHAT_MAX_BODY_BYTES",
            "CHAT_REQUIRE_INTERNAL_SECRET",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "false");

        let err = Config::from_env().expect_err("must reject disabled internal secret in prod");
        assert!(err.contains("CHAT_REQUIRE_INTERNAL_SECRET must be true in prod/staging"));
    }

    #[test]
    fn rejects_require_v2_groups_when_v2_disabled() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "CHAT_DB_URL",
            "CHAT_MAX_BODY_BYTES",
            "CHAT_REQUIRE_INTERNAL_SECRET",
            "CHAT_PROTOCOL_V2_ENABLED",
            "CHAT_PROTOCOL_V1_WRITE_ENABLED",
            "CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS",
            "CHAT_MAILBOX_API_ENABLED",
            "CHAT_MAILBOX_INACTIVE_RETENTION_SECS",
            "CHAT_MAILBOX_CONSUMED_RETENTION_SECS",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("CHAT_PROTOCOL_V2_ENABLED", "false");
        env::set_var("CHAT_PROTOCOL_V1_WRITE_ENABLED", "true");
        env::set_var("CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS", "true");

        let err = Config::from_env().expect_err("must reject invalid protocol policy");
        assert!(err.contains("CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS"));
    }

    #[test]
    fn rejects_when_all_protocol_writes_are_disabled() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "CHAT_DB_URL",
            "CHAT_MAX_BODY_BYTES",
            "CHAT_REQUIRE_INTERNAL_SECRET",
            "CHAT_PROTOCOL_V2_ENABLED",
            "CHAT_PROTOCOL_V1_WRITE_ENABLED",
            "CHAT_MAILBOX_API_ENABLED",
            "CHAT_MAILBOX_INACTIVE_RETENTION_SECS",
            "CHAT_MAILBOX_CONSUMED_RETENTION_SECS",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("CHAT_PROTOCOL_V2_ENABLED", "false");
        env::set_var("CHAT_PROTOCOL_V1_WRITE_ENABLED", "false");

        let err = Config::from_env().expect_err("must reject config that disables all writes");
        assert!(err.contains("CHAT_PROTOCOL_V2_ENABLED"));
    }

    #[test]
    fn mailbox_api_defaults_to_disabled() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "CHAT_DB_URL",
            "CHAT_MAX_BODY_BYTES",
            "CHAT_REQUIRE_INTERNAL_SECRET",
            "CHAT_MAILBOX_API_ENABLED",
            "CHAT_MAILBOX_INACTIVE_RETENTION_SECS",
            "CHAT_MAILBOX_CONSUMED_RETENTION_SECS",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "false");
        env::remove_var("CHAT_MAILBOX_API_ENABLED");

        let cfg = Config::from_env().expect("config should parse");
        assert!(!cfg.chat_mailbox_api_enabled);
    }

    #[test]
    fn mailbox_api_can_be_enabled_explicitly() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "CHAT_DB_URL",
            "CHAT_MAX_BODY_BYTES",
            "CHAT_REQUIRE_INTERNAL_SECRET",
            "CHAT_MAILBOX_API_ENABLED",
            "CHAT_MAILBOX_INACTIVE_RETENTION_SECS",
            "CHAT_MAILBOX_CONSUMED_RETENTION_SECS",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("CHAT_MAILBOX_API_ENABLED", "true");

        let cfg = Config::from_env().expect("config should parse");
        assert!(cfg.chat_mailbox_api_enabled);
    }

    #[test]
    fn body_limit_is_clamped_to_safe_bounds() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "CHAT_DB_URL",
            "CHAT_MAX_BODY_BYTES",
            "CHAT_REQUIRE_INTERNAL_SECRET",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "false");

        env::set_var("CHAT_MAX_BODY_BYTES", "1");
        let cfg = Config::from_env().expect("config should parse");
        assert_eq!(cfg.max_body_bytes, 16 * 1024);

        env::set_var("CHAT_MAX_BODY_BYTES", "999999999");
        let cfg = Config::from_env().expect("config should parse");
        assert_eq!(cfg.max_body_bytes, 10 * 1024 * 1024);
    }
}
