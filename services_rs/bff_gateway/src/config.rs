use ipnet::IpNet;
use shamell_common::internal_identity::{parse_public_keys_csv, InternalRequestSigner};
use shamell_common::secret_policy;
use std::env;
use std::net::IpAddr;

#[derive(Clone, Debug)]
pub struct Config {
    pub env_name: String,

    pub host: String,
    pub port: u16,

    pub require_internal_secret: bool,
    pub internal_secret: Option<String>,
    pub security_alert_allowed_callers: Vec<String>,
    pub access_assignment_allowed_callers: Vec<String>,
    pub access_assignment_internal_identity_public_keys: Vec<(String, String)>,
    pub access_assignment_internal_identity_max_skew_secs: i64,
    pub access_assignment_require_internal_identity_v2: bool,
    pub access_assignment_allow_legacy_internal_secret_fallback: bool,
    pub security_alert_internal_identity_public_keys: Vec<(String, String)>,
    pub security_alert_internal_identity_max_skew_secs: i64,
    pub security_alert_require_internal_identity_v2: bool,
    pub security_alert_allow_legacy_internal_secret_fallback: bool,
    pub internal_service_id: String,
    pub enforce_route_authz: bool,
    pub role_header_secret: Option<String>,

    pub allowed_hosts: Vec<String>,
    pub allowed_origins: Vec<String>,
    pub trusted_proxy_cidrs: Vec<IpNet>,
    pub csrf_guard_enabled: bool,
    pub accept_legacy_session_cookie: bool,
    pub allow_legacy_contact_invite_chat_device_fallback: bool,
    pub auth_device_login_web_enabled: bool,
    pub workforce_oidc_issuer_url: Option<String>,
    pub workforce_oidc_client_id: Option<String>,
    pub workforce_oidc_audience: Option<String>,
    pub workforce_oidc_jwks_url: Option<String>,
    pub cloudflare_access_team_domain: Option<String>,
    pub cloudflare_access_audiences: Vec<String>,
    pub workforce_session_ttl_secs: i64,
    pub workforce_break_glass_session_ttl_secs: i64,
    pub workforce_step_up_enabled: bool,
    pub web_direct_access_allowed_origins: Vec<String>,
    pub web_direct_access_allowed_client_cidrs: Vec<IpNet>,
    pub web_direct_access_account_id: Option<String>,
    pub web_direct_access_phone: Option<String>,
    pub web_direct_access_device_id: Option<String>,
    pub web_direct_launch_signing_secret: Option<String>,
    pub web_direct_launch_allowed_redirect_origins: Vec<String>,
    pub web_direct_launch_max_ttl_secs: i64,

    pub payments_base_url: String,
    pub payments_internal_secret: Option<String>,
    pub fee_wallet_account_id: Option<String>,
    pub fee_wallet_phone: Option<String>,
    pub chat_base_url: String,
    pub chat_internal_secret: Option<String>,
    pub internal_identity_signing_seed_b64: Option<String>,

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

fn normalize_hex_token(raw: &str, len: usize) -> Option<String> {
    let trimmed = raw.trim();
    if trimmed.len() != len || !trimmed.chars().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    Some(trimmed.to_ascii_lowercase())
}

fn normalize_session_account_id(key: &str, raw: &str) -> Result<String, String> {
    normalize_hex_token(raw, 64).ok_or_else(|| format!("{key} must be a 64-char hex account id"))
}

fn normalize_optional_small_text(key: &str, raw: &str, max_len: usize) -> Result<String, String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Err(format!("{key} must not be empty"));
    }
    if trimmed.len() > max_len || trimmed.chars().any(|ch| ch.is_control()) {
        return Err(format!("{key} is invalid"));
    }
    Ok(trimmed.to_string())
}

fn normalize_upstream_base_url(
    key: &str,
    raw: &str,
    require_https: bool,
    enforce_internal_plaintext_hosts: bool,
) -> Result<String, String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Err(format!("{key} must be set"));
    }
    let mut url = reqwest::Url::parse(trimmed)
        .map_err(|_| format!("{key} must be a valid http(s) origin"))?;
    if !matches!(url.scheme(), "http" | "https") {
        return Err(format!("{key} must use http:// or https://"));
    }
    if require_https && url.scheme() != "https" {
        return Err(format!(
            "{key} must use https:// in prod/staging (or set BFF_ALLOW_INSECURE_UPSTREAM_HTTP=true for explicitly trusted internal-network plaintext)"
        ));
    }
    let host = url.host_str().unwrap_or("").trim();
    if host.is_empty() {
        return Err(format!("{key} must include a host"));
    }
    if enforce_internal_plaintext_hosts
        && url.scheme() == "http"
        && !is_internal_plaintext_upstream_host(host)
    {
        return Err(format!(
            "{key} must use an internal plaintext host when BFF_ALLOW_INSECURE_UPSTREAM_HTTP=true in prod/staging"
        ));
    }
    if !url.username().is_empty() || url.password().is_some() {
        return Err(format!("{key} must not include credentials"));
    }
    if url.query().is_some() || url.fragment().is_some() {
        return Err(format!("{key} must not include query or fragment"));
    }
    if !url.path().is_empty() && url.path() != "/" {
        return Err(format!("{key} must not include a non-root path"));
    }
    url.set_path("");
    url.set_query(None);
    url.set_fragment(None);
    let mut normalized = url.to_string();
    if normalized.ends_with('/') {
        normalized.pop();
    }
    Ok(normalized)
}

fn is_internal_plaintext_upstream_host(raw: &str) -> bool {
    let host = raw.trim().to_ascii_lowercase();
    if host.is_empty() {
        return false;
    }
    if host == "localhost" {
        return true;
    }
    if host.ends_with(".local") || host.ends_with(".internal") {
        return true;
    }
    if let Ok(ip) = host.parse::<IpAddr>() {
        return match ip {
            IpAddr::V4(ipv4) => ipv4.is_private() || ipv4.is_loopback() || ipv4.is_link_local(),
            IpAddr::V6(ipv6) => {
                ipv6.is_loopback() || ipv6.is_unicast_link_local() || ipv6.is_unique_local()
            }
        };
    }
    // Single-label service names (for example: `payments`, `chat`) are valid
    // for private service discovery in container networks and should stay
    // eligible for the explicit plaintext escape hatch.
    if !host.contains('.') {
        return host
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
            && !host.starts_with('-')
            && !host.ends_with('-');
    }
    false
}

fn normalize_allowed_origin(raw: &str) -> Result<String, String> {
    let trimmed = raw.trim();
    if trimmed == "*" {
        return Ok("*".to_string());
    }
    let url =
        reqwest::Url::parse(trimmed).map_err(|_| "must be a valid http(s) origin".to_string())?;
    let scheme = url.scheme().to_ascii_lowercase();
    if !matches!(scheme.as_str(), "http" | "https") {
        return Err("must use http:// or https://".to_string());
    }
    let host = url
        .host_str()
        .map(str::trim)
        .filter(|h| !h.is_empty())
        .ok_or_else(|| "must include a host".to_string())?
        .to_ascii_lowercase();
    if !url.username().is_empty() || url.password().is_some() {
        return Err("must not include credentials".to_string());
    }
    if url.query().is_some() || url.fragment().is_some() {
        return Err("must not include query or fragment".to_string());
    }
    if !url.path().is_empty() && url.path() != "/" {
        return Err("must not include a non-root path".to_string());
    }
    Ok(match url.port() {
        Some(port) => format!("{scheme}://{host}:{port}"),
        None => format!("{scheme}://{host}"),
    })
}

fn normalize_external_reference_url(
    key: &str,
    raw: &str,
    require_https: bool,
) -> Result<String, String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Err(format!("{key} must not be empty"));
    }
    let mut url =
        reqwest::Url::parse(trimmed).map_err(|_| format!("{key} must be a valid absolute URL"))?;
    if !matches!(url.scheme(), "http" | "https") {
        return Err(format!("{key} must use http:// or https://"));
    }
    if require_https && url.scheme() != "https" {
        return Err(format!("{key} must use https:// in prod/staging"));
    }
    if url.host_str().map(str::trim).unwrap_or("").is_empty() {
        return Err(format!("{key} must include a host"));
    }
    if !url.username().is_empty() || url.password().is_some() {
        return Err(format!("{key} must not include credentials"));
    }
    if url.query().is_some() || url.fragment().is_some() {
        return Err(format!("{key} must not include query or fragment"));
    }
    url.set_query(None);
    url.set_fragment(None);
    Ok(url.to_string())
}

fn normalize_team_domain(key: &str, raw: &str) -> Result<String, String> {
    let trimmed = raw.trim().to_ascii_lowercase();
    if trimmed.is_empty() {
        return Err(format!("{key} must not be empty"));
    }
    if trimmed.contains("://")
        || trimmed.contains('/')
        || trimmed.contains('?')
        || trimmed.contains('#')
        || trimmed.contains('@')
        || trimmed.contains(':')
    {
        return Err(format!("{key} must be a plain hostname"));
    }
    if !trimmed
        .chars()
        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || matches!(c, '.' | '-'))
    {
        return Err(format!("{key} must contain only lowercase host characters"));
    }
    Ok(trimmed)
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

fn normalize_trusted_proxy_cidr(raw: &str) -> Result<IpNet, String> {
    raw.trim()
        .parse::<IpNet>()
        .map_err(|_| "must be a valid IPv4/IPv6 CIDR".to_string())
}

fn trusted_proxy_cidr_is_universal(cidr: &IpNet) -> bool {
    match cidr {
        IpNet::V4(v4) => v4.prefix_len() == 0,
        IpNet::V6(v6) => v6.prefix_len() == 0,
    }
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
            match parse_bool_like("BFF_REQUIRE_INTERNAL_SECRET", &raw)? {
                Some(v) => v,
                None => prod_like,
            }
        };
        if prod_like && !require_internal_secret {
            return Err("BFF_REQUIRE_INTERNAL_SECRET must be true in prod/staging".to_string());
        }

        let internal_secret = env_opt("INTERNAL_API_SECRET");
        secret_policy::validate_secret_for_env(
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
        let security_alert_internal_identity_public_keys = parse_public_keys_csv(&env_or(
            "BFF_SECURITY_ALERT_INTERNAL_IDENTITY_PUBLIC_KEYS",
            "",
        ))
        .map_err(|e| format!("BFF_SECURITY_ALERT_INTERNAL_IDENTITY_PUBLIC_KEYS {e}"))?;
        let security_alert_internal_identity_max_skew_secs: i64 =
            env_or("BFF_SECURITY_ALERT_INTERNAL_IDENTITY_MAX_SKEW_SECS", "30")
                .parse()
                .map_err(|_| {
                    "BFF_SECURITY_ALERT_INTERNAL_IDENTITY_MAX_SKEW_SECS must be an integer"
                        .to_string()
                })?;
        let security_alert_internal_identity_max_skew_secs =
            security_alert_internal_identity_max_skew_secs.clamp(1, 300);
        let security_alert_require_internal_identity_v2 = {
            let raw = env_or("BFF_SECURITY_ALERT_REQUIRE_INTERNAL_IDENTITY_V2", "");
            match parse_bool_like("BFF_SECURITY_ALERT_REQUIRE_INTERNAL_IDENTITY_V2", &raw)? {
                Some(v) => v,
                None => prod_like,
            }
        };
        let security_alert_allow_legacy_internal_secret_fallback = {
            let raw = env_or(
                "BFF_SECURITY_ALERT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK",
                "",
            );
            match parse_bool_like(
                "BFF_SECURITY_ALERT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK",
                &raw,
            )? {
                Some(v) => v,
                None => !prod_like,
            }
        };
        if prod_like && security_alert_internal_identity_public_keys.is_empty() {
            return Err(
                "BFF_SECURITY_ALERT_INTERNAL_IDENTITY_PUBLIC_KEYS must be set in prod/staging"
                    .to_string(),
            );
        }
        if prod_like && !security_alert_require_internal_identity_v2 {
            return Err(
                "BFF_SECURITY_ALERT_REQUIRE_INTERNAL_IDENTITY_V2 must be true in prod/staging"
                    .to_string(),
            );
        }
        if prod_like && security_alert_allow_legacy_internal_secret_fallback {
            return Err(
                "BFF_SECURITY_ALERT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK must be false in prod/staging"
                    .to_string(),
            );
        }
        if require_internal_secret
            && internal_secret.as_deref().unwrap_or("").is_empty()
            && (security_alert_internal_identity_public_keys.is_empty()
                || security_alert_allow_legacy_internal_secret_fallback)
        {
            return Err(
                "INTERNAL_API_SECRET must be set when BFF_REQUIRE_INTERNAL_SECRET is enabled unless security alert identity is configured without legacy fallback"
                    .to_string(),
            );
        }
        let access_assignment_allowed_callers =
            parse_csv(&env_or("BFF_ACCESS_ASSIGNMENT_ALLOWED_CALLERS", ""))
                .into_iter()
                .map(|v| v.trim().to_ascii_lowercase())
                .filter(|v| !v.is_empty())
                .collect::<Vec<_>>();
        let access_assignment_internal_identity_public_keys = parse_public_keys_csv(&env_or(
            "BFF_ACCESS_ASSIGNMENT_INTERNAL_IDENTITY_PUBLIC_KEYS",
            "",
        ))
        .map_err(|e| format!("BFF_ACCESS_ASSIGNMENT_INTERNAL_IDENTITY_PUBLIC_KEYS {e}"))?;
        let access_assignment_internal_identity_max_skew_secs: i64 = env_or(
            "BFF_ACCESS_ASSIGNMENT_INTERNAL_IDENTITY_MAX_SKEW_SECS",
            "30",
        )
        .parse()
        .map_err(|_| {
            "BFF_ACCESS_ASSIGNMENT_INTERNAL_IDENTITY_MAX_SKEW_SECS must be an integer".to_string()
        })?;
        let access_assignment_internal_identity_max_skew_secs =
            access_assignment_internal_identity_max_skew_secs.clamp(1, 300);
        let access_assignment_require_internal_identity_v2 = {
            let raw = env_or("BFF_ACCESS_ASSIGNMENT_REQUIRE_INTERNAL_IDENTITY_V2", "");
            match parse_bool_like("BFF_ACCESS_ASSIGNMENT_REQUIRE_INTERNAL_IDENTITY_V2", &raw)? {
                Some(v) => v,
                None => prod_like,
            }
        };
        let access_assignment_allow_legacy_internal_secret_fallback = {
            let raw = env_or(
                "BFF_ACCESS_ASSIGNMENT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK",
                "",
            );
            match parse_bool_like(
                "BFF_ACCESS_ASSIGNMENT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK",
                &raw,
            )? {
                Some(v) => v,
                None => !prod_like,
            }
        };
        if prod_like
            && !access_assignment_allowed_callers.is_empty()
            && access_assignment_internal_identity_public_keys.is_empty()
        {
            return Err(
                "BFF_ACCESS_ASSIGNMENT_INTERNAL_IDENTITY_PUBLIC_KEYS must be set when BFF_ACCESS_ASSIGNMENT_ALLOWED_CALLERS is enabled in prod/staging"
                    .to_string(),
            );
        }
        if prod_like
            && !access_assignment_allowed_callers.is_empty()
            && !access_assignment_require_internal_identity_v2
        {
            return Err(
                "BFF_ACCESS_ASSIGNMENT_REQUIRE_INTERNAL_IDENTITY_V2 must be true when BFF_ACCESS_ASSIGNMENT_ALLOWED_CALLERS is enabled in prod/staging"
                    .to_string(),
            );
        }
        if prod_like
            && !access_assignment_allowed_callers.is_empty()
            && access_assignment_allow_legacy_internal_secret_fallback
        {
            return Err(
                "BFF_ACCESS_ASSIGNMENT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK must be false when BFF_ACCESS_ASSIGNMENT_ALLOWED_CALLERS is enabled in prod/staging"
                    .to_string(),
            );
        }
        if require_internal_secret
            && !access_assignment_allowed_callers.is_empty()
            && internal_secret.as_deref().unwrap_or("").is_empty()
            && (access_assignment_internal_identity_public_keys.is_empty()
                || access_assignment_allow_legacy_internal_secret_fallback)
        {
            return Err(
                "INTERNAL_API_SECRET must be set when BFF_ACCESS_ASSIGNMENT_ALLOWED_CALLERS is enabled unless access assignment identity is configured without legacy fallback"
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
            match parse_bool_like("BFF_ENFORCE_ROUTE_AUTHZ", &raw)? {
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
        secret_policy::validate_secret_for_env(
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
        for extra in ["bff", "bff-gateway"] {
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
        let trusted_proxy_cidrs = parse_csv(&env_or("BFF_TRUSTED_PROXY_CIDRS", ""))
            .into_iter()
            .map(|cidr| {
                normalize_trusted_proxy_cidr(&cidr).map_err(|reason| {
                    format!("BFF_TRUSTED_PROXY_CIDRS contains invalid CIDR: {reason}")
                })
            })
            .collect::<Result<Vec<_>, _>>()?;
        if prod_like
            && trusted_proxy_cidrs
                .iter()
                .any(trusted_proxy_cidr_is_universal)
        {
            return Err(
                "BFF_TRUSTED_PROXY_CIDRS must not contain 0.0.0.0/0 or ::/0 in prod/staging"
                    .to_string(),
            );
        }
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

        let csrf_guard_enabled = {
            let raw = env_or("CSRF_GUARD_ENABLED", "");
            match parse_bool_like("CSRF_GUARD_ENABLED", &raw)? {
                Some(v) => v,
                None => prod_like,
            }
        };
        if csrf_guard_enabled && allowed_origins.iter().any(|o| o.trim() == "*") {
            return Err(
                "ALLOWED_ORIGINS must not contain '*' when CSRF_GUARD_ENABLED=true".to_string(),
            );
        }
        if prod_like && !csrf_guard_enabled {
            return Err("CSRF_GUARD_ENABLED must be true in prod/staging".to_string());
        }
        let accept_legacy_session_cookie = {
            let raw = env_or("AUTH_ACCEPT_LEGACY_SESSION_COOKIE", "");
            match parse_bool_like("AUTH_ACCEPT_LEGACY_SESSION_COOKIE", &raw)? {
                Some(v) => v,
                None => dev_or_test,
            }
        };
        if prod_like && accept_legacy_session_cookie {
            return Err(
                "AUTH_ACCEPT_LEGACY_SESSION_COOKIE must be false in prod/staging".to_string(),
            );
        }
        let allow_legacy_contact_invite_chat_device_fallback = {
            let raw = env_or("AUTH_ALLOW_LEGACY_CONTACT_INVITE_CHAT_DEVICE_FALLBACK", "");
            match parse_bool_like(
                "AUTH_ALLOW_LEGACY_CONTACT_INVITE_CHAT_DEVICE_FALLBACK",
                &raw,
            )? {
                Some(v) => v,
                None => dev_or_test,
            }
        };
        if prod_like && allow_legacy_contact_invite_chat_device_fallback {
            return Err(
                "AUTH_ALLOW_LEGACY_CONTACT_INVITE_CHAT_DEVICE_FALLBACK must be false in prod/staging".to_string(),
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
            parse_bool_like("AUTH_DEVICE_LOGIN_WEB_ENABLED", &raw)?.unwrap_or(!prod_like)
        };
        let workforce_oidc_issuer_url = env_opt("WORKFORCE_OIDC_ISSUER_URL")
            .map(|value| {
                normalize_external_reference_url("WORKFORCE_OIDC_ISSUER_URL", &value, prod_like)
            })
            .transpose()?;
        let workforce_oidc_client_id = env_opt("WORKFORCE_OIDC_CLIENT_ID");
        let workforce_oidc_audience = env_opt("WORKFORCE_OIDC_AUDIENCE");
        let workforce_oidc_jwks_url = env_opt("WORKFORCE_OIDC_JWKS_URL")
            .map(|value| {
                normalize_external_reference_url("WORKFORCE_OIDC_JWKS_URL", &value, prod_like)
            })
            .transpose()?;
        let cloudflare_access_team_domain = env_opt("CLOUDFLARE_ACCESS_TEAM_DOMAIN")
            .map(|value| normalize_team_domain("CLOUDFLARE_ACCESS_TEAM_DOMAIN", &value))
            .transpose()?;
        let cloudflare_access_audiences = parse_csv(&env_or("CLOUDFLARE_ACCESS_AUDIENCES", ""))
            .into_iter()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
            .collect::<Vec<_>>();
        let workforce_session_ttl_secs: i64 = env_or("WORKFORCE_SESSION_TTL_SECS", "28800")
            .parse()
            .map_err(|_| "WORKFORCE_SESSION_TTL_SECS must be an integer".to_string())?;
        let workforce_session_ttl_secs = workforce_session_ttl_secs.clamp(300, 86_400);
        let workforce_break_glass_session_ttl_secs: i64 =
            env_or("WORKFORCE_BREAK_GLASS_SESSION_TTL_SECS", "900")
                .parse()
                .map_err(|_| {
                    "WORKFORCE_BREAK_GLASS_SESSION_TTL_SECS must be an integer".to_string()
                })?;
        let workforce_break_glass_session_ttl_secs =
            workforce_break_glass_session_ttl_secs.clamp(60, 86_400);
        let workforce_step_up_enabled = {
            let raw = env_or("WORKFORCE_STEP_UP_ENABLED", "");
            match parse_bool_like("WORKFORCE_STEP_UP_ENABLED", &raw)? {
                Some(value) => value,
                None => prod_like,
            }
        };
        let web_direct_access_allowed_origins =
            parse_csv(&env_or("AUTH_WEB_DIRECT_ACCESS_ALLOWED_ORIGINS", ""))
                .into_iter()
                .map(|origin| {
                    normalize_allowed_origin(&origin).map_err(|reason| {
                format!("AUTH_WEB_DIRECT_ACCESS_ALLOWED_ORIGINS contains invalid origin: {reason}")
            })
                })
                .collect::<Result<Vec<_>, _>>()?;
        let web_direct_access_allowed_client_cidrs =
            parse_csv(&env_or("AUTH_WEB_DIRECT_ACCESS_ALLOWED_CLIENT_CIDRS", ""))
                .into_iter()
                .map(|cidr| {
                    normalize_trusted_proxy_cidr(&cidr).map_err(|reason| {
                        format!(
                    "AUTH_WEB_DIRECT_ACCESS_ALLOWED_CLIENT_CIDRS contains invalid CIDR: {reason}"
                )
                    })
                })
                .collect::<Result<Vec<_>, _>>()?;
        if prod_like
            && web_direct_access_allowed_client_cidrs
                .iter()
                .any(trusted_proxy_cidr_is_universal)
        {
            return Err(
                "AUTH_WEB_DIRECT_ACCESS_ALLOWED_CLIENT_CIDRS must not contain 0.0.0.0/0 or ::/0 in prod/staging"
                    .to_string(),
            );
        }
        let web_direct_access_account_id = env_opt("AUTH_WEB_DIRECT_ACCESS_ACCOUNT_ID")
            .map(|value| normalize_session_account_id("AUTH_WEB_DIRECT_ACCESS_ACCOUNT_ID", &value))
            .transpose()?;
        let web_direct_access_phone = env_opt("AUTH_WEB_DIRECT_ACCESS_PHONE")
            .map(|value| normalize_optional_small_text("AUTH_WEB_DIRECT_ACCESS_PHONE", &value, 32))
            .transpose()?;
        let web_direct_access_device_id = env_opt("AUTH_WEB_DIRECT_ACCESS_DEVICE_ID")
            .map(|value| {
                normalize_optional_small_text("AUTH_WEB_DIRECT_ACCESS_DEVICE_ID", &value, 128)
            })
            .transpose()?;
        let web_direct_access_enabled = !web_direct_access_allowed_origins.is_empty()
            || !web_direct_access_allowed_client_cidrs.is_empty()
            || web_direct_access_account_id.is_some()
            || web_direct_access_phone.is_some()
            || web_direct_access_device_id.is_some();
        if web_direct_access_enabled {
            if web_direct_access_allowed_origins.is_empty() {
                return Err(
                    "AUTH_WEB_DIRECT_ACCESS_ALLOWED_ORIGINS must be set when direct web access is enabled"
                        .to_string(),
                );
            }
            if web_direct_access_allowed_client_cidrs.is_empty() {
                return Err(
                    "AUTH_WEB_DIRECT_ACCESS_ALLOWED_CLIENT_CIDRS must be set when direct web access is enabled"
                        .to_string(),
                );
            }
            if web_direct_access_account_id.is_none() && web_direct_access_phone.is_none() {
                return Err(
                    "AUTH_WEB_DIRECT_ACCESS_ACCOUNT_ID or AUTH_WEB_DIRECT_ACCESS_PHONE must be set when direct web access is enabled"
                        .to_string(),
                );
            }
        }
        let web_direct_launch_signing_secret = env_opt("AUTH_WEB_DIRECT_LAUNCH_SIGNING_SECRET")
            .map(|value| {
                normalize_optional_small_text("AUTH_WEB_DIRECT_LAUNCH_SIGNING_SECRET", &value, 256)
            })
            .transpose()?;
        let web_direct_launch_allowed_redirect_origins =
            parse_csv(&env_or("AUTH_WEB_DIRECT_LAUNCH_ALLOWED_REDIRECT_ORIGINS", ""))
                .into_iter()
                .map(|origin| {
                    normalize_allowed_origin(&origin).map_err(|reason| {
                        format!(
                            "AUTH_WEB_DIRECT_LAUNCH_ALLOWED_REDIRECT_ORIGINS contains invalid origin: {reason}"
                        )
                    })
                })
                .collect::<Result<Vec<_>, _>>()?;
        let web_direct_launch_allowed_redirect_origins =
            if web_direct_launch_allowed_redirect_origins.is_empty() {
                web_direct_access_allowed_origins.clone()
            } else {
                web_direct_launch_allowed_redirect_origins
            };
        let web_direct_launch_max_ttl_secs: i64 =
            env_or("AUTH_WEB_DIRECT_LAUNCH_MAX_TTL_SECS", "604800")
                .parse()
                .map_err(|_| {
                    "AUTH_WEB_DIRECT_LAUNCH_MAX_TTL_SECS must be an integer".to_string()
                })?;
        let web_direct_launch_max_ttl_secs = web_direct_launch_max_ttl_secs.clamp(300, 2_592_000);
        let web_direct_launch_enabled = web_direct_launch_signing_secret.is_some()
            || !web_direct_launch_allowed_redirect_origins.is_empty();
        if web_direct_launch_enabled {
            if web_direct_launch_signing_secret.is_none() {
                return Err(
                    "AUTH_WEB_DIRECT_LAUNCH_SIGNING_SECRET must be set when direct web launch is enabled"
                        .to_string(),
                );
            }
            if web_direct_launch_allowed_redirect_origins.is_empty() {
                return Err(
                    "AUTH_WEB_DIRECT_LAUNCH_ALLOWED_REDIRECT_ORIGINS must be set when direct web launch is enabled"
                        .to_string(),
                );
            }
        }

        let allow_insecure_upstream_http = {
            let raw = env_or("BFF_ALLOW_INSECURE_UPSTREAM_HTTP", "");
            parse_bool_like("BFF_ALLOW_INSECURE_UPSTREAM_HTTP", &raw)?.unwrap_or(false)
        };
        let upstream_require_https = prod_like && !allow_insecure_upstream_http;

        let payments_base_url = normalize_upstream_base_url(
            "PAYMENTS_BASE_URL",
            &env_or("PAYMENTS_BASE_URL", "http://payments:8082"),
            upstream_require_https,
            prod_like && allow_insecure_upstream_http,
        )?;
        let chat_base_url = normalize_upstream_base_url(
            "CHAT_BASE_URL",
            &env_or("CHAT_BASE_URL", "http://chat:8081"),
            upstream_require_https,
            prod_like && allow_insecure_upstream_http,
        )?;

        let payments_internal_secret =
            env_opt("PAYMENTS_INTERNAL_SECRET").or_else(|| env_opt("INTERNAL_API_SECRET"));
        let fee_wallet_account_id = env_opt("FEE_WALLET_ACCOUNT_ID");
        let fee_wallet_phone = env_opt("FEE_WALLET_PHONE");
        let chat_internal_secret = env_opt("CHAT_INTERNAL_SECRET").or_else(|| {
            if matches!(env_lower.as_str(), "dev" | "test") {
                env_opt("INTERNAL_API_SECRET")
            } else {
                None
            }
        });
        let internal_identity_signing_seed_b64 = env_opt("BFF_INTERNAL_IDENTITY_SIGNING_SEED_B64");
        if let Some(seed_b64) = internal_identity_signing_seed_b64.as_deref() {
            InternalRequestSigner::from_seed_base64(&internal_service_id, seed_b64)
                .map_err(|e| format!("BFF_INTERNAL_IDENTITY_SIGNING_SEED_B64 invalid: {e}"))?;
        }
        if prod_like && internal_identity_signing_seed_b64.is_none() {
            return Err(
                "BFF_INTERNAL_IDENTITY_SIGNING_SEED_B64 must be set in prod/staging".to_string(),
            );
        }
        if prod_like
            && internal_identity_signing_seed_b64.is_none()
            && payments_internal_secret.as_deref().unwrap_or("").is_empty()
        {
            return Err(
                "PAYMENTS_INTERNAL_SECRET must be set in prod/staging for BFF gateway".to_string(),
            );
        }
        if prod_like
            && internal_identity_signing_seed_b64.is_none()
            && chat_internal_secret.as_deref().unwrap_or("").is_empty()
        {
            return Err(
                "CHAT_INTERNAL_SECRET must be set in prod/staging for BFF gateway".to_string(),
            );
        }
        secret_policy::validate_secret_for_env(
            &env_name,
            "PAYMENTS_INTERNAL_SECRET",
            payments_internal_secret.as_deref(),
            false,
        )?;
        secret_policy::validate_secret_for_env(
            &env_name,
            "CHAT_INTERNAL_SECRET",
            chat_internal_secret.as_deref(),
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
            match parse_bool_like("BFF_EXPOSE_UPSTREAM_ERRORS", &raw)? {
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
            access_assignment_allowed_callers,
            access_assignment_internal_identity_public_keys,
            access_assignment_internal_identity_max_skew_secs,
            access_assignment_require_internal_identity_v2,
            access_assignment_allow_legacy_internal_secret_fallback,
            security_alert_internal_identity_public_keys,
            security_alert_internal_identity_max_skew_secs,
            security_alert_require_internal_identity_v2,
            security_alert_allow_legacy_internal_secret_fallback,
            internal_service_id,
            enforce_route_authz,
            role_header_secret,
            allowed_hosts,
            allowed_origins,
            trusted_proxy_cidrs,
            csrf_guard_enabled,
            accept_legacy_session_cookie,
            allow_legacy_contact_invite_chat_device_fallback,
            auth_device_login_web_enabled,
            workforce_oidc_issuer_url,
            workforce_oidc_client_id,
            workforce_oidc_audience,
            workforce_oidc_jwks_url,
            cloudflare_access_team_domain,
            cloudflare_access_audiences,
            workforce_session_ttl_secs,
            workforce_break_glass_session_ttl_secs,
            workforce_step_up_enabled,
            web_direct_access_allowed_origins,
            web_direct_access_allowed_client_cidrs,
            web_direct_access_account_id,
            web_direct_access_phone,
            web_direct_access_device_id,
            web_direct_launch_signing_secret,
            web_direct_launch_allowed_redirect_origins,
            web_direct_launch_max_ttl_secs,
            payments_base_url,
            payments_internal_secret,
            fee_wallet_account_id,
            fee_wallet_phone,
            chat_base_url,
            chat_internal_secret,
            internal_identity_signing_seed_b64,
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
    use shamell_common::internal_identity::InternalRequestSigner;
    use std::sync::{Mutex, OnceLock};

    static ENV_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

    struct EnvGuard {
        saved: Vec<(String, Option<String>)>,
    }

    impl EnvGuard {
        fn new(keys: &[&str]) -> Self {
            let mut keys = keys.to_vec();
            if !keys.contains(&"ALLOWED_ORIGINS") {
                keys.push("ALLOWED_ORIGINS");
            }
            if !keys.contains(&"BFF_ALLOW_INSECURE_UPSTREAM_HTTP") {
                keys.push("BFF_ALLOW_INSECURE_UPSTREAM_HTTP");
            }
            if !keys.contains(&"BFF_TRUSTED_PROXY_CIDRS") {
                keys.push("BFF_TRUSTED_PROXY_CIDRS");
            }
            if !keys.contains(&"BFF_INTERNAL_IDENTITY_SIGNING_SEED_B64") {
                keys.push("BFF_INTERNAL_IDENTITY_SIGNING_SEED_B64");
            }
            if !keys.contains(&"BFF_SECURITY_ALERT_INTERNAL_IDENTITY_PUBLIC_KEYS") {
                keys.push("BFF_SECURITY_ALERT_INTERNAL_IDENTITY_PUBLIC_KEYS");
            }
            if !keys.contains(&"BFF_SECURITY_ALERT_REQUIRE_INTERNAL_IDENTITY_V2") {
                keys.push("BFF_SECURITY_ALERT_REQUIRE_INTERNAL_IDENTITY_V2");
            }
            if !keys.contains(&"WORKFORCE_OIDC_ISSUER_URL") {
                keys.push("WORKFORCE_OIDC_ISSUER_URL");
            }
            if !keys.contains(&"WORKFORCE_OIDC_CLIENT_ID") {
                keys.push("WORKFORCE_OIDC_CLIENT_ID");
            }
            if !keys.contains(&"WORKFORCE_OIDC_AUDIENCE") {
                keys.push("WORKFORCE_OIDC_AUDIENCE");
            }
            if !keys.contains(&"WORKFORCE_OIDC_JWKS_URL") {
                keys.push("WORKFORCE_OIDC_JWKS_URL");
            }
            if !keys.contains(&"CLOUDFLARE_ACCESS_TEAM_DOMAIN") {
                keys.push("CLOUDFLARE_ACCESS_TEAM_DOMAIN");
            }
            if !keys.contains(&"CLOUDFLARE_ACCESS_AUDIENCES") {
                keys.push("CLOUDFLARE_ACCESS_AUDIENCES");
            }
            if !keys.contains(&"WORKFORCE_SESSION_TTL_SECS") {
                keys.push("WORKFORCE_SESSION_TTL_SECS");
            }
            if !keys.contains(&"WORKFORCE_BREAK_GLASS_SESSION_TTL_SECS") {
                keys.push("WORKFORCE_BREAK_GLASS_SESSION_TTL_SECS");
            }
            if !keys.contains(&"WORKFORCE_STEP_UP_ENABLED") {
                keys.push("WORKFORCE_STEP_UP_ENABLED");
            }
            let mut saved = Vec::with_capacity(keys.len());
            for k in keys {
                saved.push((k.to_string(), env::var(k).ok()));
            }
            install_default_internal_identity_env();
            install_default_security_alert_identity_env();
            install_default_upstream_security_test_env();
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
            "BFF_INTERNAL_IDENTITY_SIGNING_SEED_B64",
            signer.seed_base64(),
        );
    }

    fn install_default_security_alert_identity_env() {
        let signer =
            InternalRequestSigner::from_seed_bytes("security-reporter", [9u8; 32]).expect("signer");
        env::set_var(
            "BFF_SECURITY_ALERT_INTERNAL_IDENTITY_PUBLIC_KEYS",
            format!("security-reporter={}", signer.public_key_base64()),
        );
        env::set_var("BFF_SECURITY_ALERT_REQUIRE_INTERNAL_IDENTITY_V2", "true");
    }

    fn install_default_upstream_security_test_env() {
        // Most config tests focus on a specific guardrail. Keep upstream-http
        // override enabled by default in tests so those assertions stay scoped.
        env::set_var("BFF_ALLOW_INSECURE_UPSTREAM_HTTP", "true");
    }

    #[test]
    fn prod_requires_upstream_secrets() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "INTERNAL_API_SECRET",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "BFF_MAX_UPSTREAM_BODY_BYTES",
            "BFF_EXPOSE_UPSTREAM_ERRORS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::remove_var("INTERNAL_API_SECRET");
        env::remove_var("PAYMENTS_INTERNAL_SECRET");
        env::remove_var("CHAT_INTERNAL_SECRET");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::remove_var("BFF_ENFORCE_ROUTE_AUTHZ");
        env::remove_var("BFF_ROLE_HEADER_SECRET");
        env::remove_var("BFF_MAX_UPSTREAM_BODY_BYTES");
        env::remove_var("BFF_EXPOSE_UPSTREAM_ERRORS");

        let res = Config::from_env();
        assert!(res.is_err());
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
        let _env = EnvGuard::new(&["BFF_ALLOW_INSECURE_UPSTREAM_HTTP"]);

        env::set_var("BFF_ALLOW_INSECURE_UPSTREAM_HTTP", "maybe");
        let err = Config::from_env().expect_err("invalid boolean env values must fail closed");
        assert!(err.contains("BFF_ALLOW_INSECURE_UPSTREAM_HTTP must be one of"));
    }

    #[test]
    fn prod_requires_internal_identity_signing_seed() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "ALLOWED_ORIGINS",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "BFF_INTERNAL_IDENTITY_SIGNING_SEED_B64",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "true");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");
        env::remove_var("BFF_INTERNAL_IDENTITY_SIGNING_SEED_B64");

        let err = Config::from_env().expect_err("missing signing seed must fail in prod");
        assert!(err.contains("BFF_INTERNAL_IDENTITY_SIGNING_SEED_B64"));
    }

    #[test]
    fn prod_requires_security_alert_identity_public_keys() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "ALLOWED_ORIGINS",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "BFF_SECURITY_ALERT_INTERNAL_IDENTITY_PUBLIC_KEYS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "true");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");
        env::remove_var("BFF_SECURITY_ALERT_INTERNAL_IDENTITY_PUBLIC_KEYS");

        let err = Config::from_env().expect_err("missing security alert identity keys must fail");
        assert!(err.contains("BFF_SECURITY_ALERT_INTERNAL_IDENTITY_PUBLIC_KEYS"));
    }

    #[test]
    fn prod_rejects_security_alert_legacy_secret_fallback_with_identity() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "ALLOWED_ORIGINS",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "BFF_SECURITY_ALERT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "true");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");
        env::set_var(
            "BFF_SECURITY_ALERT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK",
            "true",
        );

        let err = Config::from_env().expect_err("legacy fallback must be disabled in prod");
        assert!(err.contains("BFF_SECURITY_ALERT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK"));
    }

    #[test]
    fn prod_rejects_security_alert_identity_v2_toggle_off() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "ALLOWED_ORIGINS",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "BFF_SECURITY_ALERT_REQUIRE_INTERNAL_IDENTITY_V2",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "true");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");
        env::set_var("BFF_SECURITY_ALERT_REQUIRE_INTERNAL_IDENTITY_V2", "false");

        let err = Config::from_env().expect_err("v2-only alert identity must be enforced");
        assert!(err.contains("BFF_SECURITY_ALERT_REQUIRE_INTERNAL_IDENTITY_V2"));
    }

    #[test]
    fn prod_allows_missing_internal_secret_when_security_alert_identity_replaces_it() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "ALLOWED_ORIGINS",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::remove_var("INTERNAL_API_SECRET");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "true");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");

        let cfg =
            Config::from_env().expect("security alert identity should replace internal secret");
        assert!(cfg.internal_secret.is_none());
    }

    #[test]
    fn prod_allows_missing_upstream_secrets_when_identity_signing_enabled() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "ALLOWED_ORIGINS",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "INTERNAL_API_SECRET",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::remove_var("PAYMENTS_INTERNAL_SECRET");
        env::remove_var("CHAT_INTERNAL_SECRET");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "true");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");

        let cfg = Config::from_env().expect("signing identity should replace upstream secrets");
        assert!(cfg.internal_identity_signing_seed_b64.is_some());
    }

    #[test]
    fn internal_secret_only_required_when_enabled() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "INTERNAL_API_SECRET",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "BFF_MAX_UPSTREAM_BODY_BYTES",
            "BFF_EXPOSE_UPSTREAM_ERRORS",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");

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
    fn rejects_upstream_base_urls_with_credentials() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://user:pass@payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");

        let err = Config::from_env().expect_err("credentials must be rejected");
        assert!(err.contains("PAYMENTS_BASE_URL must not include credentials"));
    }

    #[test]
    fn rejects_upstream_base_urls_with_non_root_path() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082/api");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");

        let err = Config::from_env().expect_err("non-root path must be rejected");
        assert!(err.contains("PAYMENTS_BASE_URL must not include a non-root path"));
    }

    #[test]
    fn canonicalizes_upstream_base_urls_to_origin_form() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "HTTP://payments:8082/");
        env::set_var("CHAT_BASE_URL", "http://chat:8081/");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");

        let cfg = Config::from_env().expect("config");
        assert_eq!(cfg.payments_base_url, "http://payments:8082");
        assert_eq!(cfg.chat_base_url, "http://chat:8081");
    }

    #[test]
    fn prod_rejects_http_upstream_base_urls_by_default() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "ALLOWED_ORIGINS",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BFF_ALLOW_INSECURE_UPSTREAM_HTTP",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "https://chat:8081");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "true");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");
        env::remove_var("BFF_ALLOW_INSECURE_UPSTREAM_HTTP");

        let err = Config::from_env().expect_err("prod must fail closed on plaintext upstream");
        assert!(err.contains("PAYMENTS_BASE_URL must use https:// in prod/staging"));
    }

    #[test]
    fn prod_allows_http_upstream_with_explicit_escape_hatch() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "ALLOWED_ORIGINS",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BFF_ALLOW_INSECURE_UPSTREAM_HTTP",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BFF_ALLOW_INSECURE_UPSTREAM_HTTP", "true");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "true");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");

        let cfg =
            Config::from_env().expect("explicit escape hatch should allow plaintext upstream");
        assert_eq!(cfg.payments_base_url, "http://payments:8082");
        assert_eq!(cfg.chat_base_url, "http://chat:8081");
    }

    #[test]
    fn prod_rejects_public_http_upstream_even_with_escape_hatch() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "ALLOWED_ORIGINS",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "BFF_ALLOW_INSECURE_UPSTREAM_HTTP",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://api.example.com:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("BFF_ALLOW_INSECURE_UPSTREAM_HTTP", "true");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "true");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");

        let err = Config::from_env()
            .expect_err("prod plaintext escape hatch must reject public HTTP upstream hosts");
        assert!(err.contains(
            "PAYMENTS_BASE_URL must use an internal plaintext host when BFF_ALLOW_INSECURE_UPSTREAM_HTTP=true in prod/staging"
        ));
    }

    #[test]
    fn internal_plaintext_upstream_host_classifier_is_conservative() {
        for host in [
            "localhost",
            "127.0.0.1",
            "::1",
            "10.0.0.8",
            "192.168.1.20",
            "chat",
            "payments",
            "svc.internal",
            "devbox.local",
        ] {
            assert!(
                is_internal_plaintext_upstream_host(host),
                "expected internal plaintext host: {host}"
            );
        }
        for host in [
            "api.example.com",
            "8.8.8.8",
            "1.1.1.1",
            "public.shamell.online",
        ] {
            assert!(
                !is_internal_plaintext_upstream_host(host),
                "expected public host to be rejected: {host}"
            );
        }
    }

    #[test]
    fn prod_defaults_to_internal_secret_required() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "INTERNAL_API_SECRET",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "BFF_MAX_UPSTREAM_BODY_BYTES",
            "BFF_EXPOSE_UPSTREAM_ERRORS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
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
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
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
            "INTERNAL_API_SECRET",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "AUTH_DEVICE_LOGIN_WEB_ENABLED",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "true");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");
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
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "AUTH_DEVICE_LOGIN_WEB_ENABLED",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
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
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
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
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
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
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "BFF_MAX_UPSTREAM_BODY_BYTES",
            "BFF_EXPOSE_UPSTREAM_ERRORS",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
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
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "BFF_MAX_UPSTREAM_BODY_BYTES",
            "BFF_EXPOSE_UPSTREAM_ERRORS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::remove_var("BFF_REQUIRE_INTERNAL_SECRET");
        env::remove_var("BFF_ENFORCE_ROUTE_AUTHZ");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");
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
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::remove_var("BFF_REQUIRE_INTERNAL_SECRET");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "false");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");

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
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "BFF_MAX_UPSTREAM_BODY_BYTES",
            "BFF_EXPOSE_UPSTREAM_ERRORS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::remove_var("BFF_REQUIRE_INTERNAL_SECRET");
        env::remove_var("BFF_ENFORCE_ROUTE_AUTHZ");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");
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
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "BFF_MAX_UPSTREAM_BODY_BYTES",
            "BFF_EXPOSE_UPSTREAM_ERRORS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
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
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
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
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "CSRF_GUARD_ENABLED",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::remove_var("BFF_REQUIRE_INTERNAL_SECRET");
        env::remove_var("BFF_ENFORCE_ROUTE_AUTHZ");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");
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
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "CSRF_GUARD_ENABLED",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
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
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "CSRF_GUARD_ENABLED",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::remove_var("BFF_REQUIRE_INTERNAL_SECRET");
        env::remove_var("BFF_ENFORCE_ROUTE_AUTHZ");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");
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
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "CSRF_GUARD_ENABLED",
            "ALLOWED_ORIGINS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::remove_var("BFF_REQUIRE_INTERNAL_SECRET");
        env::remove_var("BFF_ENFORCE_ROUTE_AUTHZ");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");
        env::set_var("CSRF_GUARD_ENABLED", "true");
        env::set_var("ALLOWED_ORIGINS", "*");

        let err = Config::from_env().expect_err("wildcard origins must be rejected in prod");
        assert!(err.contains("ALLOWED_ORIGINS"));
    }

    #[test]
    fn csrf_guard_rejects_wildcard_origin_in_non_prod_too() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "CSRF_GUARD_ENABLED",
            "ALLOWED_ORIGINS",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("ALLOWED_ORIGINS", "*");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "false");
        env::set_var("CSRF_GUARD_ENABLED", "true");

        let err = Config::from_env()
            .expect_err("wildcard origins must be rejected whenever CSRF guard is enabled");
        assert!(err.contains("ALLOWED_ORIGINS must not contain '*' when CSRF_GUARD_ENABLED=true"));
    }

    #[test]
    fn prod_requires_explicit_allowed_origins() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
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
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::remove_var("BFF_REQUIRE_INTERNAL_SECRET");
        env::remove_var("BFF_ENFORCE_ROUTE_AUTHZ");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");
        env::set_var("CSRF_GUARD_ENABLED", "true");
        env::remove_var("ALLOWED_ORIGINS");

        let err = Config::from_env().expect_err("missing ALLOWED_ORIGINS must be rejected in prod");
        assert!(err.contains("ALLOWED_ORIGINS must be set in prod/staging"));
    }

    #[test]
    fn prod_rejects_non_https_allowed_origins() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "CSRF_GUARD_ENABLED",
            "ALLOWED_ORIGINS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::remove_var("BFF_REQUIRE_INTERNAL_SECRET");
        env::remove_var("BFF_ENFORCE_ROUTE_AUTHZ");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");
        env::set_var("CSRF_GUARD_ENABLED", "true");
        env::set_var("ALLOWED_ORIGINS", "http://online.shamell.online");

        let err = Config::from_env().expect_err("non-https origins must be rejected in prod");
        assert!(err.contains("ALLOWED_ORIGINS must use https:// origins"));
    }

    #[test]
    fn rejects_allowed_origins_with_credentials() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "CSRF_GUARD_ENABLED",
            "ALLOWED_ORIGINS",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("ALLOWED_ORIGINS", "https://user:pass@online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "false");
        env::remove_var("BFF_ROLE_HEADER_SECRET");
        env::set_var("CSRF_GUARD_ENABLED", "true");

        let err = Config::from_env().expect_err("credentialed origins must be rejected");
        assert!(err.contains("ALLOWED_ORIGINS contains invalid origin"));
        assert!(err.contains("must not include credentials"));
    }

    #[test]
    fn rejects_allowed_origins_with_non_root_path() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "CSRF_GUARD_ENABLED",
            "ALLOWED_ORIGINS",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test/app");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "false");
        env::remove_var("BFF_ROLE_HEADER_SECRET");
        env::set_var("CSRF_GUARD_ENABLED", "true");

        let err = Config::from_env().expect_err("path-bearing origins must be rejected");
        assert!(err.contains("ALLOWED_ORIGINS contains invalid origin"));
        assert!(err.contains("must not include a non-root path"));
    }

    #[test]
    fn canonicalizes_allowed_origins_to_origin_form() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "CSRF_GUARD_ENABLED",
            "ALLOWED_ORIGINS",
        ]);

        env::set_var("ENV", "dev");
        env::set_var(
            "ALLOWED_ORIGINS",
            "HTTPS://online.shamell.test/,http://localhost:5173/",
        );
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "false");
        env::remove_var("BFF_ROLE_HEADER_SECRET");
        env::set_var("CSRF_GUARD_ENABLED", "true");

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
    fn legacy_cookie_fallback_defaults_off_in_prod() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "AUTH_ACCEPT_LEGACY_SESSION_COOKIE",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::remove_var("BFF_REQUIRE_INTERNAL_SECRET");
        env::remove_var("BFF_ENFORCE_ROUTE_AUTHZ");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");
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
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "AUTH_ACCEPT_LEGACY_SESSION_COOKIE",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::remove_var("BFF_REQUIRE_INTERNAL_SECRET");
        env::remove_var("BFF_ENFORCE_ROUTE_AUTHZ");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");
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
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "AUTH_ACCEPT_LEGACY_SESSION_COOKIE",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "false");
        env::remove_var("AUTH_ACCEPT_LEGACY_SESSION_COOKIE");

        let cfg = Config::from_env().expect("config");
        assert!(cfg.accept_legacy_session_cookie);
    }

    #[test]
    fn legacy_contact_invite_chat_device_fallback_defaults_off_in_prod() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "AUTH_ALLOW_LEGACY_CONTACT_INVITE_CHAT_DEVICE_FALLBACK",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::remove_var("BFF_REQUIRE_INTERNAL_SECRET");
        env::remove_var("BFF_ENFORCE_ROUTE_AUTHZ");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");
        env::remove_var("AUTH_ALLOW_LEGACY_CONTACT_INVITE_CHAT_DEVICE_FALLBACK");

        let cfg = Config::from_env().expect("config");
        assert!(!cfg.allow_legacy_contact_invite_chat_device_fallback);
    }

    #[test]
    fn prod_rejects_legacy_contact_invite_chat_device_fallback_toggle_on() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "AUTH_ALLOW_LEGACY_CONTACT_INVITE_CHAT_DEVICE_FALLBACK",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::remove_var("BFF_REQUIRE_INTERNAL_SECRET");
        env::remove_var("BFF_ENFORCE_ROUTE_AUTHZ");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");
        env::set_var(
            "AUTH_ALLOW_LEGACY_CONTACT_INVITE_CHAT_DEVICE_FALLBACK",
            "true",
        );

        let err = Config::from_env().expect_err(
            "legacy contact-invite chat-device fallback must not be enabled in prod/staging",
        );
        assert!(err.contains(
            "AUTH_ALLOW_LEGACY_CONTACT_INVITE_CHAT_DEVICE_FALLBACK must be false in prod/staging"
        ));
    }

    #[test]
    fn legacy_contact_invite_chat_device_fallback_defaults_on_in_dev() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "AUTH_ALLOW_LEGACY_CONTACT_INVITE_CHAT_DEVICE_FALLBACK",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("ALLOWED_ORIGINS", "http://localhost:5173");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::remove_var("BFF_REQUIRE_INTERNAL_SECRET");
        env::remove_var("BFF_ENFORCE_ROUTE_AUTHZ");
        env::remove_var("AUTH_ALLOW_LEGACY_CONTACT_INVITE_CHAT_DEVICE_FALLBACK");

        let cfg = Config::from_env().expect("config");
        assert!(cfg.allow_legacy_contact_invite_chat_device_fallback);
    }

    #[test]
    fn rejects_removed_header_session_auth_env_toggle() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "AUTH_ALLOW_HEADER_SESSION_AUTH",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "true");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");
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
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "AUTH_BLOCK_BROWSER_HEADER_SESSION",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "true");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");
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
            "INTERNAL_API_SECRET",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("INTERNAL_API_SECRET", "change-me-super-secret-value");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "true");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");

        assert!(Config::from_env().is_err());
    }

    #[test]
    fn prod_rejects_wildcard_allowed_hosts() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "INTERNAL_API_SECRET",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "ALLOWED_HOSTS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "true");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");
        env::set_var("ALLOWED_HOSTS", "*");

        let err = Config::from_env().expect_err("wildcard hosts must be rejected in prod");
        assert!(err.contains("ALLOWED_HOSTS"));
    }

    #[test]
    fn rejects_allowed_hosts_with_scheme_or_path() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "CSRF_GUARD_ENABLED",
            "ALLOWED_HOSTS",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "false");
        env::remove_var("BFF_ROLE_HEADER_SECRET");
        env::set_var("CSRF_GUARD_ENABLED", "true");
        env::set_var("ALLOWED_HOSTS", "https://api.shamell.test/admin");

        let err = Config::from_env().expect_err("url-form host must be rejected");
        assert!(err.contains("ALLOWED_HOSTS contains invalid host"));
        assert!(err.contains("plain host"));
    }

    #[test]
    fn rejects_allowed_hosts_with_wildcard_subdomain_pattern() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "CSRF_GUARD_ENABLED",
            "ALLOWED_HOSTS",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "false");
        env::remove_var("BFF_ROLE_HEADER_SECRET");
        env::set_var("CSRF_GUARD_ENABLED", "true");
        env::set_var("ALLOWED_HOSTS", ".shamell.test");

        let err = Config::from_env().expect_err("wildcard subdomain host must be rejected");
        assert!(err.contains("ALLOWED_HOSTS contains invalid host"));
        assert!(err.contains("wildcard subdomain"));
    }

    #[test]
    fn prod_rejects_root_dev_deployment_profile() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "INTERNAL_API_SECRET",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "SHAMELL_DEPLOYMENT_PROFILE",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "true");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");
        env::set_var("SHAMELL_DEPLOYMENT_PROFILE", "root-dev");

        let err =
            Config::from_env().expect_err("root-dev profile must never be allowed in prod/staging");
        assert!(err.contains("SHAMELL_DEPLOYMENT_PROFILE=root-dev"));
    }

    #[test]
    fn parses_trusted_proxy_cidrs() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "BFF_TRUSTED_PROXY_CIDRS",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "false");
        env::remove_var("BFF_ROLE_HEADER_SECRET");
        env::set_var("BFF_TRUSTED_PROXY_CIDRS", "10.0.0.0/8,192.168.0.0/16");

        let cfg = Config::from_env().expect("config");
        assert_eq!(cfg.trusted_proxy_cidrs.len(), 2);
        assert_eq!(cfg.trusted_proxy_cidrs[0].to_string(), "10.0.0.0/8");
        assert_eq!(cfg.trusted_proxy_cidrs[1].to_string(), "192.168.0.0/16");
    }

    #[test]
    fn rejects_invalid_trusted_proxy_cidrs() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "BFF_TRUSTED_PROXY_CIDRS",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "false");
        env::remove_var("BFF_ROLE_HEADER_SECRET");
        env::set_var("BFF_TRUSTED_PROXY_CIDRS", "not-a-cidr");

        let err = Config::from_env().expect_err("invalid CIDR must fail");
        assert!(err.contains("BFF_TRUSTED_PROXY_CIDRS contains invalid CIDR"));
    }

    #[test]
    fn prod_rejects_universal_trusted_proxy_cidrs() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "ALLOWED_ORIGINS",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "INTERNAL_API_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "BFF_ROLE_HEADER_SECRET",
            "BFF_TRUSTED_PROXY_CIDRS",
        ]);

        env::set_var("ENV", "prod");
        env::set_var("ALLOWED_ORIGINS", "https://online.shamell.test");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("INTERNAL_API_SECRET", "bff-secret-0123456789");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "true");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "true");
        env::set_var("BFF_ROLE_HEADER_SECRET", "edge-secret-0123456789");
        env::set_var("BFF_TRUSTED_PROXY_CIDRS", "0.0.0.0/0,::/0");

        let err = Config::from_env().expect_err("prod must reject universal proxy trust");
        assert!(err.contains("BFF_TRUSTED_PROXY_CIDRS must not contain 0.0.0.0/0 or ::/0"));
    }

    #[test]
    fn parses_workforce_iam_config_when_provided() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let iam_sync_signer =
            InternalRequestSigner::from_seed_bytes("iam-sync", [3u8; 32]).expect("signer");
        let control_automation_signer =
            InternalRequestSigner::from_seed_bytes("control-automation", [4u8; 32])
                .expect("signer");
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "WORKFORCE_OIDC_ISSUER_URL",
            "WORKFORCE_OIDC_CLIENT_ID",
            "WORKFORCE_OIDC_AUDIENCE",
            "WORKFORCE_OIDC_JWKS_URL",
            "CLOUDFLARE_ACCESS_TEAM_DOMAIN",
            "CLOUDFLARE_ACCESS_AUDIENCES",
            "WORKFORCE_SESSION_TTL_SECS",
            "WORKFORCE_BREAK_GLASS_SESSION_TTL_SECS",
            "WORKFORCE_STEP_UP_ENABLED",
            "BFF_ACCESS_ASSIGNMENT_ALLOWED_CALLERS",
            "BFF_ACCESS_ASSIGNMENT_INTERNAL_IDENTITY_PUBLIC_KEYS",
            "BFF_ACCESS_ASSIGNMENT_INTERNAL_IDENTITY_MAX_SKEW_SECS",
            "BFF_ACCESS_ASSIGNMENT_REQUIRE_INTERNAL_IDENTITY_V2",
            "BFF_ACCESS_ASSIGNMENT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "false");
        env::set_var("WORKFORCE_OIDC_ISSUER_URL", "https://iam.shamell.online");
        env::set_var("WORKFORCE_OIDC_CLIENT_ID", "shamell-control-web");
        env::set_var("WORKFORCE_OIDC_AUDIENCE", "shamell-workforce");
        env::set_var(
            "WORKFORCE_OIDC_JWKS_URL",
            "https://iam.shamell.online/oauth/v2/keys",
        );
        env::set_var(
            "CLOUDFLARE_ACCESS_TEAM_DOMAIN",
            "shamell.cloudflareaccess.com",
        );
        env::set_var(
            "CLOUDFLARE_ACCESS_AUDIENCES",
            "control-prod,coach-operators-prod",
        );
        env::set_var("WORKFORCE_SESSION_TTL_SECS", "14400");
        env::set_var("WORKFORCE_BREAK_GLASS_SESSION_TTL_SECS", "600");
        env::set_var("WORKFORCE_STEP_UP_ENABLED", "true");
        env::set_var(
            "BFF_ACCESS_ASSIGNMENT_ALLOWED_CALLERS",
            "iam-sync, control-automation",
        );
        env::set_var(
            "BFF_ACCESS_ASSIGNMENT_INTERNAL_IDENTITY_PUBLIC_KEYS",
            format!(
                "iam-sync={},control-automation={}",
                iam_sync_signer.public_key_base64(),
                control_automation_signer.public_key_base64()
            ),
        );
        env::set_var(
            "BFF_ACCESS_ASSIGNMENT_INTERNAL_IDENTITY_MAX_SKEW_SECS",
            "45",
        );
        env::set_var("BFF_ACCESS_ASSIGNMENT_REQUIRE_INTERNAL_IDENTITY_V2", "true");
        env::set_var(
            "BFF_ACCESS_ASSIGNMENT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK",
            "false",
        );

        let cfg = Config::from_env().expect("config");
        assert_eq!(
            cfg.workforce_oidc_issuer_url.as_deref(),
            Some("https://iam.shamell.online/")
        );
        assert_eq!(
            cfg.workforce_oidc_jwks_url.as_deref(),
            Some("https://iam.shamell.online/oauth/v2/keys")
        );
        assert_eq!(
            cfg.cloudflare_access_team_domain.as_deref(),
            Some("shamell.cloudflareaccess.com")
        );
        assert_eq!(
            cfg.cloudflare_access_audiences,
            vec![
                "control-prod".to_string(),
                "coach-operators-prod".to_string()
            ]
        );
        assert_eq!(cfg.workforce_session_ttl_secs, 14_400);
        assert_eq!(cfg.workforce_break_glass_session_ttl_secs, 600);
        assert!(cfg.workforce_step_up_enabled);
        assert_eq!(
            cfg.access_assignment_allowed_callers,
            vec!["iam-sync".to_string(), "control-automation".to_string()]
        );
        assert_eq!(
            cfg.access_assignment_internal_identity_public_keys,
            vec![
                ("iam-sync".to_string(), iam_sync_signer.public_key_base64(),),
                (
                    "control-automation".to_string(),
                    control_automation_signer.public_key_base64(),
                )
            ]
        );
        assert_eq!(cfg.access_assignment_internal_identity_max_skew_secs, 45);
        assert!(cfg.access_assignment_require_internal_identity_v2);
        assert!(!cfg.access_assignment_allow_legacy_internal_secret_fallback);
    }

    #[test]
    fn parses_direct_web_launch_config_when_provided() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "AUTH_WEB_DIRECT_LAUNCH_SIGNING_SECRET",
            "AUTH_WEB_DIRECT_LAUNCH_ALLOWED_REDIRECT_ORIGINS",
            "AUTH_WEB_DIRECT_LAUNCH_MAX_TTL_SECS",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "false");
        env::set_var(
            "AUTH_WEB_DIRECT_LAUNCH_SIGNING_SECRET",
            "launch-secret-0123456789",
        );
        env::set_var(
            "AUTH_WEB_DIRECT_LAUNCH_ALLOWED_REDIRECT_ORIGINS",
            "https://online.shamell.online,https://shamell.online",
        );
        env::set_var("AUTH_WEB_DIRECT_LAUNCH_MAX_TTL_SECS", "7200");

        let cfg = Config::from_env().expect("config");
        assert_eq!(
            cfg.web_direct_launch_signing_secret.as_deref(),
            Some("launch-secret-0123456789")
        );
        assert_eq!(
            cfg.web_direct_launch_allowed_redirect_origins,
            vec![
                "https://online.shamell.online".to_string(),
                "https://shamell.online".to_string()
            ]
        );
        assert_eq!(cfg.web_direct_launch_max_ttl_secs, 7200);
    }

    #[test]
    fn rejects_invalid_cloudflare_team_domain() {
        let _g = ENV_LOCK.get_or_init(|| Mutex::new(())).lock().unwrap();
        let _env = EnvGuard::new(&[
            "ENV",
            "PAYMENTS_BASE_URL",
            "CHAT_BASE_URL",
            "PAYMENTS_INTERNAL_SECRET",
            "CHAT_INTERNAL_SECRET",
            "BFF_REQUIRE_INTERNAL_SECRET",
            "BFF_ENFORCE_ROUTE_AUTHZ",
            "CLOUDFLARE_ACCESS_TEAM_DOMAIN",
        ]);

        env::set_var("ENV", "dev");
        env::set_var("PAYMENTS_BASE_URL", "http://payments:8082");
        env::set_var("CHAT_BASE_URL", "http://chat:8081");
        env::set_var("PAYMENTS_INTERNAL_SECRET", "pay-secret-0123456789");
        env::set_var("CHAT_INTERNAL_SECRET", "chat-secret-0123456789");
        env::set_var("BFF_REQUIRE_INTERNAL_SECRET", "false");
        env::set_var("BFF_ENFORCE_ROUTE_AUTHZ", "false");
        env::set_var(
            "CLOUDFLARE_ACCESS_TEAM_DOMAIN",
            "https://shamell.cloudflareaccess.com",
        );

        let err = Config::from_env().expect_err("team domain must be a plain hostname");
        assert!(err.contains("CLOUDFLARE_ACCESS_TEAM_DOMAIN"));
    }
}
