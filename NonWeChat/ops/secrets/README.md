This folder contains locally generated secrets for development or staging.

Important
- Do NOT commit real secrets to source control. The root `.gitignore` excludes `NonWeChat/ops/secrets/*.env`.
- Prefer using a secret manager (e.g., GitHub Actions secrets, 1Password, Vault) in production.
- Rotate secrets periodically and when team members change.
