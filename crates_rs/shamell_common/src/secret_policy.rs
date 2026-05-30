pub fn is_production_like(env_name: &str) -> bool {
    let env = env_name.trim().to_ascii_lowercase();
    matches!(env.as_str(), "prod" | "production" | "staging")
}

pub fn enforce_value_policy_for_env(
    env_name: &str,
    key: &str,
    value: Option<&str>,
    required_in_prod: bool,
) -> Result<(), String> {
    if !is_production_like(env_name) {
        return Ok(());
    }

    let Some(raw) = value else {
        if required_in_prod {
            return Err(format!("{key} must be set in prod/staging"));
        }
        return Ok(());
    };
    let secret = raw.trim();
    if secret.is_empty() {
        if required_in_prod {
            return Err(format!("{key} must be set in prod/staging"));
        }
        return Ok(());
    }

    if secret.len() < 16 {
        return Err(format!(
            "{key} must be at least 16 characters in prod/staging"
        ));
    }
    if looks_like_placeholder(secret) {
        return Err(format!(
            "{key} looks like a placeholder/default value; use a strong random secret"
        ));
    }
    Ok(())
}

fn looks_like_placeholder(secret: &str) -> bool {
    let s = secret.trim().to_ascii_lowercase();
    let banned_exact = [
        "change-me",
        "changeme",
        "replace-me",
        "secret",
        "password",
        "devsecret",
        "devkey",
        "default",
        "dummy",
        "example",
        "test",
        "qwerty",
        "letmein",
    ];
    if banned_exact.iter().any(|v| *v == s) {
        return true;
    }

    let banned_fragments = [
        "change-me",
        "change_me",
        "replace-me",
        "replace_me",
        "please-rotate",
        "set-me",
        "your-secret",
        "your_secret",
        "dev-secret",
        "dev_secret",
    ];
    banned_fragments.iter().any(|v| s.contains(v))
}

pub fn validate_secret_for_env(
    env_name: &str,
    key: &str,
    value: Option<&str>,
    required_in_prod: bool,
) -> Result<(), String> {
    enforce_value_policy_for_env(env_name, key, value, required_in_prod)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn non_prod_skips_validation() {
        let res = enforce_value_policy_for_env("dev", "INTERNAL_API_SECRET", Some("short"), true);
        assert!(res.is_ok());
    }

    #[test]
    fn prod_rejects_short_secret() {
        let res = enforce_value_policy_for_env("prod", "INTERNAL_API_SECRET", Some("short"), true);
        assert!(res.is_err());
    }

    #[test]
    fn prod_rejects_placeholder_like_secret() {
        let res = enforce_value_policy_for_env(
            "prod",
            "INTERNAL_API_SECRET",
            Some("change-me-super-secret-value"),
            true,
        );
        assert!(res.is_err());
    }

    #[test]
    fn prod_accepts_strong_secret() {
        let res = enforce_value_policy_for_env(
            "prod",
            "INTERNAL_API_SECRET",
            Some("p9s7Qk_4w-vN2xT8kP6m"),
            true,
        );
        assert!(res.is_ok());
    }
}
