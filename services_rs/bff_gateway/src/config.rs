use shamell_common::secret_policy;
use std::env;

#[derive(Clone, Debug)]
pub struct Config {
    pub env_name: String,

    pub host: String,
    pub port: u16,

    pub require_internal_secret: bool,
    pub internal_secret: Option<String>,
    pub security_alert_allowed_callers: Vec<String>,
    pub internal_service_id: String,
    pub enforce_route_authz: bool,
    pub role_header_secret: Option<String>,

    pub allowed_hosts: Vec<String>,
    pub allowed_origins: Vec<String>,
    pub csrf_guard_enabled: bool,
    pub accept_legacy_session_cookie: bool,
    pub auth_device_login_web_enabled: bool,

    pub payments_base_url: String,
    pub payments_internal_secret: Option<String>,
    pub chat_base_url: String,
    pub chat_internal_secret: Option<String>,
    pub bus_base_url: String,
    pub bus_internal_secret: Option<String>,

    pub upstream_timeout_secs: u64,
    pub max_body_bytes: usize,
    pub max_upstream_body_bytes: usize,
    pub expose_upstream_errors: bool,
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

impl Config {
    pub fn from_env() -> Result<Self, String> {
        let env_name = env_or("ENV", "dev");
        let env_lower = env_name.trim().to_lowercase();
        let prod_like = matches!(env_lower.as_str(), "prod" | "production" | "staging");
        let deployment_profile = env_or("SHAMELL_DEPLOYMENT_PROFILE", "")
            .trim()
            .to_ascii_lowercase();
        if prod_like && deployment_profile == "root-dev" {
            return Err(
                "SHAMELL_DEPLOYMENT_PROFILE=root-dev is not allowed in prod/staging; use ops/pi deployment stack"
                    .to_string(),
            );
        }

        let host = env_or("APP_HOST", "0.0.0.0");
        let port: u16 = env_or("APP_PORT", "8080")
            .parse()
            .map_err(|_| "APP_PORT must be a valid u16".to_string())?;

        let require_internal_secret = {
            let raw = env_or("BFF_REQUIRE_INTERNAL_SECRET", "");
            match parse_bool_like(&raw) {
                Some(v) => v,
                None => prod_like,
            }
        };
        if prod_like && !require_internal_secret {
            return Err("BFF_REQUIRE_INTERNAL_SECRET must be true in prod/staging".to_string());
        }

        let internal_secret = env_opt("INTERNAL_API_SECRET");
        if require_internal_secret && internal_secret.as_deref().unwrap_or("").is_empty() {
            return Err(
                "INTERNAL_API_SECRET must be set when BFF_REQUIRE_INTERNAL_SECRET is enabled"
                    .to_string(),
            );
        }
        secret_policy::enforce_value_policy_for_env(
            &env_name,
            "INTERNAL_API_SECRET",
            internal_secret.as_deref(),
            false,
        )?;

        let mut security_alert_allowed_callers =
            parse_csv(&env_or("BFF_SECURITY_ALERT_ALLOWED_CALLERS", ""))
                .into_iter()
                .map(|v| v.trim().to_ascii_lowercase())
                .filter(|v| !v.is_empty())
                .collect::<Vec<_>>();
        if security_alert_allowed_callers.is_empty() && prod_like {
            security_alert_allowed_callers = vec!["security-reporter".to_string()];
        }
        if require_internal_secret && prod_like && security_alert_allowed_callers.is_empty() {
            return Err(
                "BFF_SECURITY_ALERT_ALLOWED_CALLERS must define at least one caller in prod/staging"
                    .to_string(),
            );
        }

        let internal_service_id = env_or("BFF_INTERNAL_SERVICE_ID", "bff")
            .trim()
            .to_ascii_lowercase();
        if internal_service_id.is_empty()
            || internal_service_id.len() > 64
            || !internal_service_id
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'))
        {
            return Err("BFF_INTERNAL_SERVICE_ID must be 1..64 [A-Za-z0-9-_.]".to_string());
        }

        let enforce_route_authz = {
            let raw = env_or("BFF_ENFORCE_ROUTE_AUTHZ", "");
            match parse_bool_like(&raw) {
                Some(v) => v,
                None => prod_like,
            }
        };
        if prod_like && !enforce_route_authz {
            return Err("BFF_ENFORCE_ROUTE_AUTHZ must be true in prod/staging".to_string());
        }
        let role_header_secret = env_opt("BFF_ROLE_HEADER_SECRET");
        if enforce_route_authz && role_header_secret.as_deref().unwrap_or("").is_empty() {
            return Err(
                "BFF_ROLE_HEADER_SECRET must be set when BFF_ENFORCE_ROUTE_AUTHZ is enabled"
                    .to_string(),
            );
        }
        secret_policy::enforce_value_policy_for_env(
            &env_name,
            "BFF_ROLE_HEADER_SECRET",
            role_header_secret.as_deref(),
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
        for extra in ["bff", "bff-gateway"] {
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

        let csrf_guard_enabled = {
            let raw = env_or("CSRF_GUARD_ENABLED", "");
            match parse_bool_like(&raw) {
                Some(v) => v,
                None => prod_like,
            }
        };
        if prod_like && !csrf_guard_enabled {
            return Err("CSRF_GUARD_ENABLED must be true in prod/staging".to_string());
        }
        let accept_legacy_session_cookie = {
            let raw = env_or("AUTH_ACCEPT_LEGACY_SESSION_COOKIE", "");
            match parse_bool_like(&raw) {
                Some(v) => v,
                None => matches!(env_lower.as_str(), "dev" | "test"),
            }
        };
        if prod_like && accept_legacy_session_cookie {
            return Err(
                "AUTH_ACCEPT_LEGACY_SESSION_COOKIE must be false in prod/staging".to_string(),
            );
        }
        if env::var_os("AUTH_ALLOW_HEADER_SESSION_AUTH").is_some() {
            return Err(
                "AUTH_ALLOW_HEADER_SESSION_AUTH has been removed; use cookie session auth only"
                    .to_string(),
            );
        }
        if env::var_os("AUTH_BLOCK_BROWSER_HEADER_SESSION").is_some() {
            return Err(
                "AUTH_BLOCK_BROWSER_HEADER_SESSION has been removed; use cookie session auth only"
                    .to_string(),
            );
        }
        let auth_device_login_web_enabled = {
            let raw = env_or("AUTH_DEVICE_LOGIN_WEB_ENABLED", "");
            parse_bool_like(&raw).unwrap_or(!prod_like)
        };

        let payments_base_url = env_or("PAYMENTS_BASE_URL", "http://payments:8082")
            .trim()
            .to_string();
        if payments_base_url.is_empty() {
            return Err("PAYMENTS_BASE_URL must be set".to_string());
        }
        let chat_base_url = env_or("CHAT_BASE_URL", "http://chat:8081")
            .trim()
            .to_string();
        if chat_base_url.is_empty() {
            return Err("CHAT_BASE_URL must be set".to_string());
        }
        let bus_base_url = env_or("BUS_BASE_URL", "http://bus:8083").trim().to_string();
        if bus_base_url.is_empty() {
            return Err("BUS_BASE_URL must be set".to_string());
        }

        let payments_internal_secret =
            env_opt("PAYMENTS_INTERNAL_SECRET").or_else(|| env_opt("INTERNAL_API_SECRET"));
        let chat_internal_secret = env_opt("CHAT_INTERNAL_SECRET").or_else(|| {
            if matches!(env_lower.as_str(), "dev" | "test") {
                env_opt("INTERNAL_API_SECRET")
            } else {
                None
            }
        });
        let bus_internal_secret = env_opt("BUS_INTERNAL_SECRET");
        if prod_like && payments_internal_secret.as_deref().unwrap_or("").is_empty() {
            return Err(
                "PAYMENTS_INTERNAL_SECRET must be set in prod/staging for BFF gateway".to_string(),
            );
        }
        if prod_like && chat_internal_secret.as_deref().unwrap_or("").is_empty() {
            return Err(
                "CHAT_INTERNAL_SECRET must be set in prod/staging for BFF gateway".to_string(),
            );
        }
        if prod_like && bus_internal_secret.as_deref().unwrap_or("").is_empty() {
            return Err(
                "BUS_INTERNAL_SECRET must be set in prod/staging for BFF gateway".to_string(),
            );
        }
        secret_policy::enforce_value_policy_for_env(
            &env_name,
            "PAYMENTS_INTERNAL_SECRET",
            payments_internal_secret.as_deref(),
            false,
        )?;
        secret_policy::enforce_value_policy_for_env(
            &env_name,
            "CHAT_INTERNAL_SECRET",
            chat_internal_secret.as_deref(),
            false,
        )?;
        secret_policy::enforce_value_policy_for_env(
            &env_name,
            "BUS_INTERNAL_SECRET",
            bus_internal_secret.as_deref(),
            false,
        )?;

        let upstream_timeout_secs: u64 = env_or("BFF_UPSTREAM_TIMEOUT_SECS", "15")
            .parse()
            .map_err(|_| "BFF_UPSTREAM_TIMEOUT_SECS must be an integer".to_string())?;
        let upstream_timeout_secs = upstream_timeout_secs.clamp(1, 60);

        let max_body_bytes: usize = env_or("BFF_MAX_BODY_BYTES", "1048576")
            .parse()
            .map_err(|_| "BFF_MAX_BODY_BYTES must be an integer".to_string())?;
        let max_body_bytes = max_body_bytes.clamp(16 * 1024, 10 * 1024 * 1024);

        let max_upstream_body_bytes: usize = env_or("BFF_MAX_UPSTREAM_BODY_BYTES", "1048576")
            .parse()
            .map_err(|_| "BFF_MAX_UPSTREAM_BODY_BYTES must be an integer".to_string())?;
        let max_upstream_body_bytes = max_upstream_body_bytes.clamp(16 * 1024, 20 * 1024 * 1024);

        let expose_upstream_errors = {
            let raw = env_or("BFF_EXPOSE_UPSTREAM_ERRORS", "");
            match parse_bool_like(&raw) {
                Some(v) => v,
                None => !matches!(env_lower.as_str(), "prod" | "production" | "staging"),
            }
        };

        Ok(Self {
            env_name,
            host,
            port,
            require_internal_secret,
            internal_secret,
            security_alert_allowed_callers,
            internal_service_id,
            enforce_route_authz,
            role_header_secret,
            allowed_hosts,
            allowed_origins,
            csrf_guard_enabled,
            accept_legacy_session_cookie,
            auth_device_login_web_enabled,
            payments_base_url,
            payments_internal_secret,
            chat_base_url,
            chat_internal_secret,
            bus_base_url,
            bus_internal_secret,
            upstream_timeout_secs,
            max_body_bytes,
            max_upstream_body_bytes,
            expose_upstream_errors,
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
            for required in [
                "ALLOWED_HOSTS",
                "ALLOWED_ORIGINS",
                "BFF_CSRF_ALLOWED_ORIGINS",
            ] {
                if !keys.contains(&required) {
                    keys.push(required);
                }
            }
            let mut saved = Vec::with_capacity(keys.len());
            for k in keys {
                saved.push((k.to_string(), env::var(k).ok()));
                env::remove_var(k);
            }
            // Keep baseline prod-safe defaults so tests fail only for the condition under test.
            env::set_var("ALLOWED_HOSTS", "online.shamell.online");
            env::set_var("ALLOWED_ORIGINS", "https://online.shamell.online");
            env::set_var("BFF_CSRF_ALLOWED_ORIGINS", "https://online.shamell.online");
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
    fn prod_requires_upstream_secrets() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "INTERNAL_API_SECRET",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "BFF_MAX_UPSTREAM_BODY_BYTES",
            "BFF_EXPOSE_UPSTREAM_ERRORS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::remove_var("INTERNAL_API_SECRET");
        env::remove_var("PAYMENTS_INTERNAL_SECRET");
        env::remove_var("CHAT_INTERNAL_SECRET");
        env::remove_var("BUS_INTERNAL_SECRET");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::remove_var("BFF_ENFORCE_ROUTE_AUTHZ");
        env::remove_var("BFF_ROLE_HEADER_SECRET");
        env::remove_var("BFF_MAX_UPSTREAM_BODY_BYTES");
        env::remove_var("BFF_EXPOSE_UPSTREAM_ERRORS");

        let res = Config::from_env();
        assert!(res.is_err());
    }

    #[test]
    fn internal_secret_only_required_when_enabled() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "INTERNAL_API_SECRET",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "BFF_MAX_UPSTREAM_BODY_BYTES",
            "BFF_EXPOSE_UPSTREAM_ERRORS",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");

        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "false");
        env::remove_var("BFF_ROLE_HEADER_SECRET");
        env::set_var("BFF_MAX_UPSTREAM_BODY_BYTES", "1048576");
        env::set_var("BFF_EXPOSE_UPSTREAM_ERRORS", "true");
        env::remove_var("INTERNAL_API_SECRET");
        assert!(Config::from_env().is_ok());

        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "true");
        env::remove_var("INTERNAL_API_SECRET");
        assert!(Config::from_env().is_err());
    }

    #[test]
    fn prod_defaults_to_internal_secret_required() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "INTERNAL_API_SECRET",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "BFF_MAX_UPSTREAM_BODY_BYTES",
            "BFF_EXPOSE_UPSTREAM_ERRORS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::remove_var("BFF_REQUIRE_INTERNAL_SECRET");
        env::remove_var("BFF_ENFORCE_ROUTE_AUTHZ");
        env::remove_var("BFF_ROLE_HEADER_SECRET");
        env::remove_var("BFF_MAX_UPSTREAM_BODY_BYTES");
        env::remove_var("BFF_EXPOSE_UPSTREAM_ERRORS");
        env::remove_var("INTERNAL_API_SECRET");

        assert!(Config::from_env().is_err());
    }

    #[test]
    fn prod_rejects_internal_secret_toggle_off() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");

        let err = Config::from_env().expect_err("must reject disabled internal secret in prod");
        assert!(err.contains("BFF_REQUIRE_INTERNAL_SECRET must be true in prod/staging"));
    }

    #[test]
    fn device_login_web_defaults_disabled_in_prod() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "INTERNAL_API_SECRET",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "AUTH_DEVICE_LOGIN_WEB_ENABLED",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var("INTERNAL_API_SECRET", "dddddddddddddddddddddddddddddddd");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "true");
        env::set_var("BFF_ROLE_HEADER_SECRET", "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
        env::remove_var("AUTH_DEVICE_LOGIN_WEB_ENABLED");

        let cfg = Config::from_env().expect("config");
        assert!(!cfg.auth_device_login_web_enabled);
    }

    #[test]
    fn device_login_web_defaults_enabled_in_dev() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "AUTH_DEVICE_LOGIN_WEB_ENABLED",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "false");
        env::remove_var("AUTH_DEVICE_LOGIN_WEB_ENABLED");

        let cfg = Config::from_env().expect("config");
        assert!(cfg.auth_device_login_web_enabled);
    }

    #[test]
    fn body_limit_is_clamped_to_safe_bounds() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "BFF_MAX_BODY_BYTES",
            "BFF_MAX_UPSTREAM_BODY_BYTES",
            "BFF_EXPOSE_UPSTREAM_ERRORS",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "false");
        env::remove_var("BFF_ROLE_HEADER_SECRET");
        env::set_var("BFF_MAX_UPSTREAM_BODY_BYTES", "1048576");
        env::set_var("BFF_EXPOSE_UPSTREAM_ERRORS", "true");

        env::set_var("BFF_MAX_BODY_BYTES", "1");
        let cfg = Config::from_env().expect("config");
        assert_eq!(cfg.max_body_bytes, 16 * 1024);

        env::set_var("BFF_MAX_BODY_BYTES", "999999999");
        let cfg = Config::from_env().expect("config");
        assert_eq!(cfg.max_body_bytes, 10 * 1024 * 1024);
    }

    #[test]
    fn upstream_limit_is_clamped_to_safe_bounds() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "BFF_MAX_UPSTREAM_BODY_BYTES",
            "BFF_EXPOSE_UPSTREAM_ERRORS",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "false");
        env::remove_var("BFF_ROLE_HEADER_SECRET");
        env::set_var("BFF_EXPOSE_UPSTREAM_ERRORS", "true");

        env::set_var("BFF_MAX_UPSTREAM_BODY_BYTES", "1");
        let cfg = Config::from_env().expect("config");
        assert_eq!(cfg.max_upstream_body_bytes, 16 * 1024);

        env::set_var("BFF_MAX_UPSTREAM_BODY_BYTES", "999999999");
        let cfg = Config::from_env().expect("config");
        assert_eq!(cfg.max_upstream_body_bytes, 20 * 1024 * 1024);
    }

    #[test]
    fn prod_defaults_to_route_authz_enabled() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "BFF_MAX_UPSTREAM_BODY_BYTES",
            "BFF_EXPOSE_UPSTREAM_ERRORS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("INTERNAL_API_SECRET", "dddddddddddddddddddddddddddddddd");
        env::remove_var("BFF_REQUIRE_INTERNAL_SECRET");
        env::remove_var("BFF_ENFORCE_ROUTE_AUTHZ");
        env::set_var("BFF_ROLE_HEADER_SECRET", "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
        env::remove_var("BFF_MAX_UPSTREAM_BODY_BYTES");
        env::remove_var("BFF_EXPOSE_UPSTREAM_ERRORS");

        let cfg = Config::from_env().expect("config");
        assert!(cfg.enforce_route_authz);
    }

    #[test]
    fn prod_rejects_route_authz_toggle_off() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("INTERNAL_API_SECRET", "dddddddddddddddddddddddddddddddd");
        env::remove_var("BFF_REQUIRE_INTERNAL_SECRET");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "false");
        env::set_var("BFF_ROLE_HEADER_SECRET", "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");

        let err = Config::from_env().expect_err("route authz must not be disabled in prod");
        assert!(err.contains("BFF_ENFORCE_ROUTE_AUTHZ must be true in prod/staging"));
    }

    #[test]
    fn prod_defaults_to_hidden_upstream_errors() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "BFF_MAX_UPSTREAM_BODY_BYTES",
            "BFF_EXPOSE_UPSTREAM_ERRORS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("INTERNAL_API_SECRET", "dddddddddddddddddddddddddddddddd");
        env::remove_var("BFF_REQUIRE_INTERNAL_SECRET");
        env::remove_var("BFF_ENFORCE_ROUTE_AUTHZ");
        env::set_var("BFF_ROLE_HEADER_SECRET", "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
        env::remove_var("BFF_MAX_UPSTREAM_BODY_BYTES");
        env::remove_var("BFF_EXPOSE_UPSTREAM_ERRORS");

        let cfg = Config::from_env().expect("config");
        assert!(!cfg.expose_upstream_errors);
    }

    #[test]
    fn prod_route_authz_requires_role_header_secret() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "BFF_MAX_UPSTREAM_BODY_BYTES",
            "BFF_EXPOSE_UPSTREAM_ERRORS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("INTERNAL_API_SECRET", "dddddddddddddddddddddddddddddddd");
        env::remove_var("BFF_REQUIRE_INTERNAL_SECRET");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "true");
        env::remove_var("BFF_ROLE_HEADER_SECRET");
        env::set_var("BFF_MAX_UPSTREAM_BODY_BYTES", "1048576");
        env::set_var("BFF_EXPOSE_UPSTREAM_ERRORS", "false");

        assert!(Config::from_env().is_err());
    }

    #[test]
    fn dev_route_authz_requires_role_header_secret() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "true");
        env::remove_var("BFF_ROLE_HEADER_SECRET");

        let err = Config::from_env().expect_err("route authz must require role secret in dev");
        assert!(err.contains(
            "BFF_ROLE_HEADER_SECRET must be set when BFF_ENFORCE_ROUTE_AUTHZ is enabled"
        ));
    }

    #[test]
    fn csrf_guard_defaults_enabled_in_prod() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "CSRF_GUARD_ENABLED",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("INTERNAL_API_SECRET", "dddddddddddddddddddddddddddddddd");
        env::remove_var("BFF_REQUIRE_INTERNAL_SECRET");
        env::remove_var("BFF_ENFORCE_ROUTE_AUTHZ");
        env::set_var("BFF_ROLE_HEADER_SECRET", "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
        env::remove_var("CSRF_GUARD_ENABLED");

        let cfg = Config::from_env().expect("config");
        assert!(cfg.csrf_guard_enabled);
    }

    #[test]
    fn csrf_guard_defaults_disabled_in_dev() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "CSRF_GUARD_ENABLED",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "false");
        env::remove_var("CSRF_GUARD_ENABLED");

        let cfg = Config::from_env().expect("config");
        assert!(!cfg.csrf_guard_enabled);
    }

    #[test]
    fn prod_rejects_csrf_guard_toggle_off() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "CSRF_GUARD_ENABLED",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("INTERNAL_API_SECRET", "dddddddddddddddddddddddddddddddd");
        env::remove_var("BFF_REQUIRE_INTERNAL_SECRET");
        env::remove_var("BFF_ENFORCE_ROUTE_AUTHZ");
        env::set_var("BFF_ROLE_HEADER_SECRET", "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
        env::set_var("CSRF_GUARD_ENABLED", "false");

        let err = Config::from_env().expect_err("csrf guard must not be disabled in prod");
        assert!(err.contains("CSRF_GUARD_ENABLED must be true in prod/staging"));
    }

    #[test]
    fn prod_csrf_guard_rejects_wildcard_origin() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "CSRF_GUARD_ENABLED",
            "ALLOWED_ORIGINS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("INTERNAL_API_SECRET", "dddddddddddddddddddddddddddddddd");
        env::remove_var("BFF_REQUIRE_INTERNAL_SECRET");
        env::remove_var("BFF_ENFORCE_ROUTE_AUTHZ");
        env::set_var("BFF_ROLE_HEADER_SECRET", "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
        env::set_var("CSRF_GUARD_ENABLED", "true");
        env::set_var("ALLOWED_ORIGINS", "*");

        let err = Config::from_env().expect_err("wildcard origins must be rejected in prod");
        assert!(err.contains("ALLOWED_ORIGINS"));
    }

    #[test]
    fn prod_rejects_non_https_allowed_origins() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "CSRF_GUARD_ENABLED",
            "ALLOWED_ORIGINS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("INTERNAL_API_SECRET", "dddddddddddddddddddddddddddddddd");
        env::remove_var("BFF_REQUIRE_INTERNAL_SECRET");
        env::remove_var("BFF_ENFORCE_ROUTE_AUTHZ");
        env::set_var("BFF_ROLE_HEADER_SECRET", "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
        env::set_var("CSRF_GUARD_ENABLED", "true");
        env::set_var("ALLOWED_ORIGINS", "http://online.shamell.online");

        let err = Config::from_env().expect_err("non-https origins must be rejected in prod");
        assert!(err.contains("ALLOWED_ORIGINS must use https:// origins"));
    }

    #[test]
    fn legacy_cookie_fallback_defaults_off_in_prod() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "AUTH_ACCEPT_LEGACY_SESSION_COOKIE",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("INTERNAL_API_SECRET", "dddddddddddddddddddddddddddddddd");
        env::remove_var("BFF_REQUIRE_INTERNAL_SECRET");
        env::remove_var("BFF_ENFORCE_ROUTE_AUTHZ");
        env::set_var("BFF_ROLE_HEADER_SECRET", "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
        env::remove_var("AUTH_ACCEPT_LEGACY_SESSION_COOKIE");

        let cfg = Config::from_env().expect("config");
        assert!(!cfg.accept_legacy_session_cookie);
    }

    #[test]
    fn prod_rejects_legacy_cookie_fallback_toggle_on() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "AUTH_ACCEPT_LEGACY_SESSION_COOKIE",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("INTERNAL_API_SECRET", "dddddddddddddddddddddddddddddddd");
        env::remove_var("BFF_REQUIRE_INTERNAL_SECRET");
        env::remove_var("BFF_ENFORCE_ROUTE_AUTHZ");
        env::set_var("BFF_ROLE_HEADER_SECRET", "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
        env::set_var("AUTH_ACCEPT_LEGACY_SESSION_COOKIE", "true");

        let err = Config::from_env()
            .expect_err("legacy cookie fallback must not be enabled in prod/staging");
        assert!(err.contains("AUTH_ACCEPT_LEGACY_SESSION_COOKIE must be false in prod/staging"));
    }

    #[test]
    fn legacy_cookie_fallback_defaults_on_in_dev() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "AUTH_ACCEPT_LEGACY_SESSION_COOKIE",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "false");
        env::remove_var("AUTH_ACCEPT_LEGACY_SESSION_COOKIE");

        let cfg = Config::from_env().expect("config");
        assert!(cfg.accept_legacy_session_cookie);
    }

    #[test]
    fn rejects_removed_header_session_auth_env_toggle() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "AUTH_ALLOW_HEADER_SESSION_AUTH",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "true");
        env::set_var("BFF_ROLE_HEADER_SECRET", "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
        env::set_var("AUTH_ALLOW_HEADER_SESSION_AUTH", "false");

        let err = Config::from_env().expect_err("removed env toggle must fail");
        assert!(err.contains("AUTH_ALLOW_HEADER_SESSION_AUTH has been removed"));
    }

    #[test]
    fn rejects_removed_browser_header_session_env_toggle() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "AUTH_BLOCK_BROWSER_HEADER_SESSION",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "true");
        env::set_var("BFF_ROLE_HEADER_SECRET", "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
        env::set_var("AUTH_BLOCK_BROWSER_HEADER_SESSION", "true");

        let err = Config::from_env().expect_err("removed env toggle must fail");
        assert!(err.contains("AUTH_BLOCK_BROWSER_HEADER_SESSION has been removed"));
    }

    #[test]
    fn prod_rejects_placeholder_internal_secret() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "INTERNAL_API_SECRET",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "change-me");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "true");
        env::set_var("BFF_ROLE_HEADER_SECRET", "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");

        assert!(Config::from_env().is_err());
    }

    #[test]
    fn prod_rejects_wildcard_allowed_hosts() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "INTERNAL_API_SECRET",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "ALLOWED_HOSTS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var("INTERNAL_API_SECRET", "dddddddddddddddddddddddddddddddd");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "true");
        env::set_var("BFF_ROLE_HEADER_SECRET", "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
        env::set_var("ALLOWED_HOSTS", "*");

        let err = Config::from_env().expect_err("wildcard hosts must be rejected in prod");
        assert!(err.contains("ALLOWED_HOSTS"));
    }

    #[test]
    fn prod_rejects_root_dev_deployment_profile() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BUS_BASE_URL",
            "INTERNAL_API_SECRET",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BUS_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "SHAMELL_DEPLOYMENT_PROFILE",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BUS_BASE_URL", "http://bus:8083");
        env::set_var("INTERNAL_API_SECRET", "dddddddddddddddddddddddddddddddd");
        env::set_var(
            "PAYMENTS_INTERNAL_SECRET",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        );
        env::set_var("CHAT_INTERNAL_SECRET", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        env::set_var("BUS_INTERNAL_SECRET", "cccccccccccccccccccccccccccccccc");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "true");
        env::set_var("BFF_ROLE_HEADER_SECRET", "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
        env::set_var("SHAMELL_DEPLOYMENT_PROFILE", "root-dev");

        let err =
            Config::from_env().expect_err("root-dev profile must never be allowed in prod/staging");
        assert!(err.contains("SHAMELL_DEPLOYMENT_PROFILE=root-dev"));
    }
}
