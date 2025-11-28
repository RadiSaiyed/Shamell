Secrets Rotation (Payments)

Scope
- Payments API secrets: `JWT_SECRET`, `INTERNAL_API_SECRET`, `ADMIN_TOKEN`.
- Vertical app secrets referencing Payments: `PAYMENTS_INTERNAL_SECRET`.
- Merchant API keys (per merchant).

Preparation
- Announce maintenance window if API tokens will be invalidated.
- Stage new secrets in your secret manager (e.g., 1Password, Vault, GitHub Actions secrets).

Steps
1) Rotate Payments JWT secret
   - Generate new strong secret.
   - Update environment (K8s Secret, Docker env, or `apps/payments/.env`).
   - Restart Payments API.
   - Note: existing JWTs become invalid; expect re-authentication.

2) Rotate INTERNAL_API_SECRET
   - Generate new secret; update Payments.
   - Update all vertical services to use the same value in their `PAYMENTS_INTERNAL_SECRET`.
   - Deploy vertical updates.
   - Optionally support overlap by accepting both old and new for a short period (feature flag not included in MVP; instead rotate during low traffic).

3) Rotate ADMIN_TOKEN
   - Update env and restart API.
   - Share securely with authorized admins only.

4) Merchant API keys
   - Create new key for the merchant.
   - Ask merchant to switch client to the new key.
   - Deactivate old key after cutover.

Verification
- Exercise internal API (HMAC signed) from a vertical with the new secret.
- Run health checks and quick payment flows.

Automation
- Local helper to update `.env` files: see `tools/secure_env_secrets.sh` and `tools/rotate_payments_secrets.sh`.

