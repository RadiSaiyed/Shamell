use axum::http::Uri;
use base64::engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD};
use base64::Engine;
use regex::Regex;
use shamell_common::internal_identity::parse_public_keys_csv;
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
    pub auto_apply_schema: bool,

    pub require_internal_secret: bool,
    pub internal_secret: Option<String>,
    pub internal_allowed_callers: Vec<String>,
    pub internal_identity_public_keys: Vec<(String, String)>,
    pub internal_identity_max_skew_secs: i64,
    pub require_internal_identity_v2: bool,
    pub allow_legacy_internal_secret_fallback: bool,

    pub enforce_device_auth: bool,

    pub allowed_hosts: Vec<String>,
    pub allowed_origins: Vec<String>,

    pub purge_interval_seconds: i64,
    pub fcm_server_key: Option<String>,
    pub fcm_project_id: Option<String>,
    pub fcm_client_email: Option<String>,
    pub fcm_private_key_pem: Option<String>,
    pub chat_push_token_encryption_key: Option<[u8; 32]>,
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

fn parse_required_bool_like(key: &str, raw: &str) -> Result<Option<bool>, String> {
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

fn parse_base64_key_32(raw: &str, key: &str) -> Result<[u8; 32], String> {
    let decoded = URL_SAFE_NO_PAD
        .decode(raw.as_bytes())
        .or_else(|_| STANDARD.decode(raw.as_bytes()))
        .map_err(|_| format!("{key} must be base64/base64url for exactly 32 bytes"))?;
    if decoded.len() != 32 {
        return Err(format!("{key} must decode to exactly 32 bytes"));
    }
    let mut key_bytes = [0u8; 32];
    key_bytes.copy_from_slice(&decoded);
    Ok(key_bytes)
}

fn normalize_multiline_secret(raw: &str) -> String {
    raw.replace("\\n", "\n").trim().to_string()
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
        let port: u16 = env_or("APP_PORT", "8081")
            .parse()
            .map_err(|_| "APP_PORT must be a valid u16".to_string())?;

        let db_raw = match env_opt("CHAT_DB_URL").or_else(|| env_opt("DB_URL")) {
            Some(v) => v,
            None if prod_like => {
                return Err("CHAT_DB_URL (or DB_URL) must be set in prod/staging".to_string());
            }
            None => "postgresql://shamell:shamell@db:5432/shamell_chat".to_string(),
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
            let raw = env_or("CHAT_AUTO_APPLY_SCHEMA", "");
            match parse_required_bool_like("CHAT_AUTO_APPLY_SCHEMA", &raw)? {
                Some(v) => v,
                None => !prod_like,
            }
        };

        let require_internal_secret = {
            let raw = env_or("CHAT_REQUIRE_INTERNAL_SECRET", "");
            match parse_required_bool_like("CHAT_REQUIRE_INTERNAL_SECRET", &raw)? {
                Some(v) => v,
                None => prod_like,
            }
        };
        if prod_like && !require_internal_secret {
            return Err("CHAT_REQUIRE_INTERNAL_SECRET must be true in prod/staging".to_string());
        }
        let internal_secret =
            env_opt("INTERNAL_API_SECRET").or_else(|| env_opt("CHAT_INTERNAL_SECRET"));
        let internal_identity_public_keys =
            parse_public_keys_csv(&env_or("CHAT_INTERNAL_IDENTITY_PUBLIC_KEYS", ""))
                .map_err(|e| format!("CHAT_INTERNAL_IDENTITY_PUBLIC_KEYS {e}"))?;
        let internal_identity_max_skew_secs: i64 =
            env_or("CHAT_INTERNAL_IDENTITY_MAX_SKEW_SECS", "30")
                .parse()
                .map_err(|_| {
                    "CHAT_INTERNAL_IDENTITY_MAX_SKEW_SECS must be an integer".to_string()
                })?;
        let internal_identity_max_skew_secs = internal_identity_max_skew_secs.clamp(1, 300);
        let require_internal_identity_v2 = {
            let raw = env_or("CHAT_REQUIRE_INTERNAL_IDENTITY_V2", "");
            match parse_required_bool_like("CHAT_REQUIRE_INTERNAL_IDENTITY_V2", &raw)? {
                Some(v) => v,
                None => prod_like,
            }
        };
        let allow_legacy_internal_secret_fallback = {
            let raw = env_or("CHAT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK", "");
            match parse_required_bool_like("CHAT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK", &raw)? {
                Some(v) => v,
                None => !prod_like,
            }
        };
        if prod_like && internal_identity_public_keys.is_empty() {
            return Err(
                "CHAT_INTERNAL_IDENTITY_PUBLIC_KEYS must be set in prod/staging".to_string(),
            );
        }
        if prod_like && !require_internal_identity_v2 {
            return Err(
                "CHAT_REQUIRE_INTERNAL_IDENTITY_V2 must be true in prod/staging".to_string(),
            );
        }
        if prod_like && allow_legacy_internal_secret_fallback {
            return Err(
                "CHAT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK must be false in prod/staging"
                    .to_string(),
            );
        }
        if require_internal_secret
            && internal_secret.as_deref().unwrap_or("").is_empty()
            && (internal_identity_public_keys.is_empty() || allow_legacy_internal_secret_fallback)
        {
            return Err(
                "INTERNAL_API_SECRET must be set when CHAT_REQUIRE_INTERNAL_SECRET is enabled unless strong service identity is configured without legacy fallback"
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
            match parse_required_bool_like("CHAT_ENFORCE_DEVICE_AUTH", &raw)? {
                Some(v) => v,
                None => prod_like,
            }
        };
        if prod_like && !enforce_device_auth {
            return Err("CHAT_ENFORCE_DEVICE_AUTH must be true in prod/staging".to_string());
        }
        let legacy_auth_bootstrap_enabled = parse_required_bool_like(
            "CHAT_ALLOW_LEGACY_AUTH_BOOTSTRAP",
            &env_or("CHAT_ALLOW_LEGACY_AUTH_BOOTSTRAP", ""),
        )?
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
        for extra in ["chat"] {
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

        let max_body_bytes: usize = env_or("CHAT_MAX_BODY_BYTES", "2097152")
            .parse()
            .map_err(|_| "CHAT_MAX_BODY_BYTES must be an integer".to_string())?;
        let max_body_bytes = max_body_bytes.clamp(16 * 1024, 10 * 1024 * 1024);

        let purge_interval_seconds: i64 = env_or("CHAT_PURGE_INTERVAL_SECONDS", "600")
            .parse()
            .map_err(|_| "CHAT_PURGE_INTERVAL_SECONDS must be an integer".to_string())?;

        let fcm_server_key = env_opt("FCM_SERVER_KEY");
        secret_policy::validate_secret_for_env(
            &env_name,
            "FCM_SERVER_KEY",
            fcm_server_key.as_deref(),
            false,
        )?;
        let fcm_project_id = env_opt("FCM_PROJECT_ID");
        let fcm_client_email = env_opt("FCM_CLIENT_EMAIL");
        let fcm_private_key_pem =
            env_opt("FCM_PRIVATE_KEY").map(|raw| normalize_multiline_secret(&raw));
        secret_policy::validate_secret_for_env(
            &env_name,
            "FCM_PRIVATE_KEY",
            fcm_private_key_pem.as_deref(),
            false,
        )?;
        let fcm_v1_parts = [
            fcm_project_id.as_ref().map(|_| "FCM_PROJECT_ID"),
            fcm_client_email.as_ref().map(|_| "FCM_CLIENT_EMAIL"),
            fcm_private_key_pem.as_ref().map(|_| "FCM_PRIVATE_KEY"),
        ];
        let fcm_v1_present = fcm_v1_parts.iter().filter(|v| v.is_some()).count();
        if fcm_v1_present > 0 && fcm_v1_present < 3 {
            return Err(
                "FCM_PROJECT_ID, FCM_CLIENT_EMAIL, and FCM_PRIVATE_KEY must be set together for FCM HTTP v1"
                    .to_string(),
            );
        }
        let chat_push_token_encryption_key_b64 = env_opt("CHAT_PUSH_TOKEN_ENCRYPTION_KEY_B64");
        secret_policy::validate_secret_for_env(
            &env_name,
            "CHAT_PUSH_TOKEN_ENCRYPTION_KEY_B64",
            chat_push_token_encryption_key_b64.as_deref(),
            prod_like,
        )?;
        let chat_push_token_encryption_key = chat_push_token_encryption_key_b64
            .as_deref()
            .map(|raw| parse_base64_key_32(raw, "CHAT_PUSH_TOKEN_ENCRYPTION_KEY_B64"))
            .transpose()?;

        let chat_protocol_v2_enabled = parse_required_bool_like(
            "CHAT_PROTOCOL_V2_ENABLED",
            &env_or("CHAT_PROTOCOL_V2_ENABLED", "true"),
        )?
        .unwrap_or(true);
        let chat_protocol_v1_write_enabled = parse_required_bool_like(
            "CHAT_PROTOCOL_V1_WRITE_ENABLED",
            &env_or("CHAT_PROTOCOL_V1_WRITE_ENABLED", "false"),
        )?
        .unwrap_or(false);
        let chat_protocol_v1_read_enabled = parse_required_bool_like(
            "CHAT_PROTOCOL_V1_READ_ENABLED",
            &env_or("CHAT_PROTOCOL_V1_READ_ENABLED", "false"),
        )?
        .unwrap_or(false);
        let chat_protocol_require_v2_for_groups = parse_required_bool_like(
            "CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS",
            &env_or("CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS", "true"),
        )?
        .unwrap_or(true);
        let chat_mailbox_api_enabled = parse_required_bool_like(
            "CHAT_MAILBOX_API_ENABLED",
            &env_or("CHAT_MAILBOX_API_ENABLED", "false"),
        )?
        .unwrap_or(false);
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
            auto_apply_schema,
            require_internal_secret,
            internal_secret,
            internal_allowed_callers,
            internal_identity_public_keys,
            internal_identity_max_skew_secs,
            require_internal_identity_v2,
            allow_legacy_internal_secret_fallback,
            enforce_device_auth,
            allowed_hosts,
            allowed_origins,
            purge_interval_seconds,
            fcm_server_key,
            fcm_project_id,
            fcm_client_email,
            fcm_private_key_pem,
            chat_push_token_encryption_key,
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
    use shamell_common::internal_identity::InternalRequestSigner;
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
            if !keys.contains(&"ALLOWED_ORIGINS") {
                keys.push("ALLOWED_ORIGINS");
            }
            for extra in [
                "CHAT_INTERNAL_IDENTITY_PUBLIC_KEYS",
                "CHAT_INTERNAL_IDENTITY_MAX_SKEW_SECS",
                "CHAT_REQUIRE_INTERNAL_IDENTITY_V2",
                "CHAT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK",
                "CHAT_PUSH_TOKEN_ENCRYPTION_KEY_B64",
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
            "CHAT_INTERNAL_IDENTITY_PUBLIC_KEYS",
            format!("bff={}", signer.public_key_base64()),
        );
        env::set_var("CHAT_INTERNAL_IDENTITY_MAX_SKEW_SECS", "30");
        env::set_var("CHAT_REQUIRE_INTERNAL_IDENTITY_V2", "true");
        env::set_var("CHAT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK", "false");
        env::set_var(
            "CHAT_PUSH_TOKEN_ENCRYPTION_KEY_B64",
            "CQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQk",
        );
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
        let _env = EnvGuard::new(&["CHAT_MAILBOX_API_ENABLED"]);

        env::set_var("CHAT_MAILBOX_API_ENABLED", "on-ish");
        let err = Config::from_env().expect_err("invalid boolean env values must fail closed");
        assert!(err.contains("CHAT_MAILBOX_API_ENABLED must be one of"));
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
    fn prod_requires_explicit_database_url() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&["ENV", "CHAT_DB_URL", "DB_URL"]);

        env::set_var("ENV", "prod");
        env::remove_var("CHAT_DB_URL");
        env::remove_var("DB_URL");

        let err = Config::from_env().expect_err("prod must fail closed without explicit DB url");
        assert!(err.contains("CHAT_DB_URL (or DB_URL) must be set in prod/staging"));
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
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "change-me-secret");
        env::remove_var("CHAT_INTERNAL_SECRET");

        let res = Config::from_env();
        assert!(res.is_err());
    }

    #[test]
    fn prod_allows_missing_internal_secret_when_identity_replaces_it() {
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
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "true");
        env::remove_var("INTERNAL_API_SECRET");
        env::remove_var("CHAT_INTERNAL_SECRET");

        let cfg = Config::from_env().expect("identity config should replace shared secret");
        assert!(cfg.internal_secret.is_none());
        assert!(!cfg.internal_identity_public_keys.is_empty());
    }

    #[test]
    fn prod_rejects_missing_push_token_encryption_key() {
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
            "CHAT_PUSH_TOKEN_ENCRYPTION_KEY_B64",
            "CHAT_PROTOCOL_V2_ENABLED",
            "CHAT_PROTOCOL_V1_WRITE_ENABLED",
            "CHAT_PROTOCOL_V1_READ_ENABLED",
            "CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS",
            "CHAT_MAILBOX_API_ENABLED",
            "CHAT_MAILBOX_INACTIVE_RETENTION_SECS",
            "CHAT_MAILBOX_CONSUMED_RETENTION_SECS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "true");
        env::remove_var("INTERNAL_API_SECRET");
        env::remove_var("CHAT_INTERNAL_SECRET");
        env::remove_var("CHAT_PUSH_TOKEN_ENCRYPTION_KEY_B64");

        let res = Config::from_env();
        assert!(res.is_err());
        assert!(res
            .expect_err("missing push token encryption key should fail")
            .contains("CHAT_PUSH_TOKEN_ENCRYPTION_KEY_B64 must be set in prod/staging"));
    }

    #[test]
    fn prod_rejects_placeholder_fcm_server_key() {
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
            "FCM_SERVER_KEY",
            "CHAT_PROTOCOL_V2_ENABLED",
            "CHAT_PROTOCOL_V1_WRITE_ENABLED",
            "CHAT_PROTOCOL_V1_READ_ENABLED",
            "CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS",
            "CHAT_MAILBOX_API_ENABLED",
            "CHAT_MAILBOX_INACTIVE_RETENTION_SECS",
            "CHAT_MAILBOX_CONSUMED_RETENTION_SECS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "true");
        env::remove_var("INTERNAL_API_SECRET");
        env::remove_var("CHAT_INTERNAL_SECRET");
        env::set_var("FCM_SERVER_KEY", "change-me-fcm-server-key");

        let res = Config::from_env();
        assert!(res.is_err());
        assert!(res
            .expect_err("placeholder fcm key should fail")
            .contains("FCM_SERVER_KEY looks like a placeholder/default value"));
    }

    #[test]
    fn fcm_v1_requires_complete_service_account_triplet() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "CHAT_DB_URL",
            "CHAT_REQUIRE_INTERNAL_SECRET",
            "FCM_PROJECT_ID",
            "FCM_CLIENT_EMAIL",
            "FCM_PRIVATE_KEY",
        ]);

        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("FCM_PROJECT_ID", "shamell-b42f9");
        env::set_var(
            "FCM_CLIENT_EMAIL",
            "firebase@shamell-b42f9.iam.gserviceaccount.com",
        );
        env::remove_var("FCM_PRIVATE_KEY");

        let err = Config::from_env().expect_err("partial FCM v1 config must fail closed");
        assert!(err.contains(
            "FCM_PROJECT_ID, FCM_CLIENT_EMAIL, and FCM_PRIVATE_KEY must be set together"
        ));
    }

    #[test]
    fn fcm_v1_private_key_normalizes_escaped_newlines() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "CHAT_DB_URL",
            "CHAT_REQUIRE_INTERNAL_SECRET",
            "FCM_PROJECT_ID",
            "FCM_CLIENT_EMAIL",
            "FCM_PRIVATE_KEY",
        ]);

        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("FCM_PROJECT_ID", "shamell-b42f9");
        env::set_var(
            "FCM_CLIENT_EMAIL",
            "firebase@shamell-b42f9.iam.gserviceaccount.com",
        );
        env::set_var(
            "FCM_PRIVATE_KEY",
            "-----BEGIN PRIVATE KEY-----\\nabc123\\n-----END PRIVATE KEY-----\\n",
        );

        let cfg = Config::from_env().expect("complete FCM v1 config should parse");
        assert_eq!(
            cfg.fcm_private_key_pem.as_deref(),
            Some("-----BEGIN PRIVATE KEY-----\nabc123\n-----END PRIVATE KEY-----")
        );
    }

    #[test]
    fn prod_rejects_legacy_secret_fallback_with_identity() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "CHAT_DB_URL",
            "DB_URL",
            "DB_SCHEMA",
            "CHAT_MAX_BODY_BYTES",
            "CHAT_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "CHAT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK",
            "CHAT_PROTOCOL_V2_ENABLED",
            "CHAT_PROTOCOL_V1_WRITE_ENABLED",
            "CHAT_PROTOCOL_V1_READ_ENABLED",
            "CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS",
            "CHAT_MAILBOX_API_ENABLED",
            "CHAT_MAILBOX_INACTIVE_RETENTION_SECS",
            "CHAT_MAILBOX_CONSUMED_RETENTION_SECS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "chat-secret-0123456789");
        env::set_var("CHAT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK", "true");

        let err = Config::from_env().expect_err("legacy fallback must be rejected in prod");
        assert!(err.contains("CHAT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK"));
    }

    #[test]
    fn prod_rejects_internal_identity_v2_toggle_off() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "CHAT_DB_URL",
            "DB_URL",
            "DB_SCHEMA",
            "CHAT_MAX_BODY_BYTES",
            "CHAT_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "CHAT_REQUIRE_INTERNAL_IDENTITY_V2",
            "CHAT_PROTOCOL_V2_ENABLED",
            "CHAT_PROTOCOL_V1_WRITE_ENABLED",
            "CHAT_PROTOCOL_V1_READ_ENABLED",
            "CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS",
            "CHAT_MAILBOX_API_ENABLED",
            "CHAT_MAILBOX_INACTIVE_RETENTION_SECS",
            "CHAT_MAILBOX_CONSUMED_RETENTION_SECS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "chat-secret-0123456789");
        env::set_var("CHAT_REQUIRE_INTERNAL_IDENTITY_V2", "false");

        let err = Config::from_env().expect_err("v2-only internal identity must be enforced");
        assert!(err.contains("CHAT_REQUIRE_INTERNAL_IDENTITY_V2"));
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
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
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
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "chat-secret-0123456789");
        env::set_var("ALLOWED_HOSTS", "*");

        let err = Config::from_env().expect_err("wildcard hosts must be rejected in prod");
        assert!(err.contains("ALLOWED_HOSTS"));
    }

    #[test]
    fn rejects_allowed_hosts_with_scheme_or_path() {
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

        env::set_var("ENV", "dev");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("INTERNAL_API_SECRET", "chat-secret-0123456789");
        env::set_var("ALLOWED_HOSTS", "https://chat.shamell.test/api");

        let err = Config::from_env().expect_err("url-form host must be rejected");
        assert!(err.contains("ALLOWED_HOSTS contains invalid host"));
        assert!(err.contains("plain host"));
    }

    #[test]
    fn rejects_allowed_hosts_with_wildcard_subdomain_pattern() {
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

        env::set_var("ENV", "dev");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("INTERNAL_API_SECRET", "chat-secret-0123456789");
        env::set_var("ALLOWED_HOSTS", ".shamell.test");

        let err = Config::from_env().expect_err("wildcard subdomain host must be rejected");
        assert!(err.contains("ALLOWED_HOSTS contains invalid host"));
        assert!(err.contains("wildcard subdomain"));
    }

    #[test]
    fn prod_requires_explicit_allowed_origins() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "CHAT_DB_URL",
            "CHAT_MAX_BODY_BYTES",
            "CHAT_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "ALLOWED_ORIGINS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "chat-secret-0123456789");
        env::remove_var("ALLOWED_ORIGINS");

        let err = Config::from_env().expect_err("missing ALLOWED_ORIGINS must be rejected in prod");
        assert!(err.contains("ALLOWED_ORIGINS must be set in prod/staging"));
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
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "chat-secret-0123456789");
        env::set_var("ALLOWED_ORIGINS", "http://online.shamell.online");

        let err = Config::from_env().expect_err("non-https origins must be rejected in prod");
        assert!(err.contains("ALLOWED_ORIGINS must use https:// origins"));
    }

    #[test]
    fn rejects_allowed_origins_with_credentials() {
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

        env::set_var("ENV", "dev");
        env::set_var("ALLOWED_ORIGINS", "https://user:pass@online.shamell.test");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("INTERNAL_API_SECRET", "chat-secret-0123456789");

        let err = Config::from_env().expect_err("credentialed origins must be rejected");
        assert!(err.contains("ALLOWED_ORIGINS contains invalid origin"));
        assert!(err.contains("must not include credentials"));
    }

    #[test]
    fn rejects_allowed_origins_with_non_root_path() {
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

        env::set_var("ENV", "dev");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test/app");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("INTERNAL_API_SECRET", "chat-secret-0123456789");

        let err = Config::from_env().expect_err("path-bearing origins must be rejected");
        assert!(err.contains("ALLOWED_ORIGINS contains invalid origin"));
        assert!(err.contains("must not include a non-root path"));
    }

    #[test]
    fn canonicalizes_allowed_origins_to_origin_form() {
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

        env::set_var("ENV", "dev");
        env::set_var(
            "ALLOWED_ORIGINS",
            "HTTPS://online.shamell.test/,http://localhost:5173/",
        );
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("INTERNAL_API_SECRET", "chat-secret-0123456789");

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
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
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
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
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
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
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

    #[test]
    fn prod_defaults_schema_bootstrap_to_disabled() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "CHAT_DB_URL",
            "CHAT_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "CHAT_AUTO_APPLY_SCHEMA",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "chat-secret-0123456789");
        env::remove_var("CHAT_AUTO_APPLY_SCHEMA");

        let cfg = Config::from_env().expect("config should parse");
        assert!(!cfg.auto_apply_schema);
    }

    #[test]
    fn dev_defaults_schema_bootstrap_to_enabled() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "CHAT_DB_URL",
            "CHAT_REQUIRE_INTERNAL_SECRET",
            "CHAT_AUTO_APPLY_SCHEMA",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "false");
        env::remove_var("CHAT_AUTO_APPLY_SCHEMA");

        let cfg = Config::from_env().expect("config should parse");
        assert!(cfg.auto_apply_schema);
    }

    #[test]
    fn prod_can_opt_in_schema_bootstrap_explicitly() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "CHAT_DB_URL",
            "CHAT_REQUIRE_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "CHAT_AUTO_APPLY_SCHEMA",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("CHAT_DB_URL", "postgresql://u:p@localhost:5432/chat");
        env::set_var("CHAT_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "chat-secret-0123456789");
        env::set_var("CHAT_AUTO_APPLY_SCHEMA", "true");

        let cfg = Config::from_env().expect("config should parse");
        assert!(cfg.auto_apply_schema);
    }
}
