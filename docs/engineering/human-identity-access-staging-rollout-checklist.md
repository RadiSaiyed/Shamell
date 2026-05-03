# Human Identity & Access Staging Rollout Checklist

## Purpose
Use this checklist when enabling the new workforce IAM and access-assignment
path in staging before production rollout.

This checklist is written for operators, not only backend engineers.

## What Must Exist First
- Staging hostname for the BFF and dashboards is reachable.
- A staging ZITADEL tenant or equivalent workforce OIDC issuer exists.
- Cloudflare Access applications exist for the staging dashboard hostnames.
- Staging secrets are available for:
  - `BFF_INTERNAL_IDENTITY_SIGNING_SEED_B64`
  - `BFF_SECURITY_ALERT_INTERNAL_IDENTITY_PUBLIC_KEYS`
  - `BFF_ACCESS_ASSIGNMENT_INTERNAL_IDENTITY_PUBLIC_KEYS`
  - `ACCESS_ASSIGNMENT_ADMIN_SIGNING_SEED_B64`
  - `AUTH_ACCOUNT_CREATE_POW_SECRET`
  - Apple DeviceCheck staging keys
  - Google Play Integrity staging service-account JSON

## Required Staging Env Values
These values must be set in `ops/pi/.env` for staging:

- `ENV=staging`
- `WORKFORCE_OIDC_ISSUER_URL=https://iam-staging.shamell.online`
- `WORKFORCE_OIDC_CLIENT_ID=shamell-control-web-staging`
- `WORKFORCE_OIDC_AUDIENCE=shamell-workforce-staging`
- `WORKFORCE_OIDC_JWKS_URL=https://iam-staging.shamell.online/oauth/v2/keys`
- `CLOUDFLARE_ACCESS_TEAM_DOMAIN=shamell.cloudflareaccess.com`
- `CLOUDFLARE_ACCESS_AUDIENCES=control-staging,ops-staging,coach-operators-staging,crew-staging,cash-staging`
- `BFF_ACCESS_ASSIGNMENT_ALLOWED_CALLERS=control-automation,iam-sync`
- `BFF_ACCESS_ASSIGNMENT_REQUIRE_INTERNAL_IDENTITY_V2=true`
- `BFF_ACCESS_ASSIGNMENT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK=false`
- `ACCESS_ASSIGNMENT_ADMIN_SERVICE_ID=control-automation`
- `ACCESS_ASSIGNMENT_ADMIN_AUDIENCE=bff`
- `AUTH_ACCOUNT_CREATE_ENABLED=true`
- `AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED=true`
- `AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION=true`
- `AUTH_PAYMENT_MUTATION_HARDWARE_ATTESTATION_ENABLED=true`

## Rollout Steps
1. Populate `ops/pi/.env` from `ops/pi/env.staging.example`.
2. Run `bash scripts/check_deploy_env_invariants.sh`.
3. Run `./scripts/ops.sh pipg check`.
4. Run `./scripts/ops.sh pipg schema-migrate bff`.
5. Deploy the stack with `./scripts/ops.sh pipg deploy`.
6. Verify public boundaries with `./scripts/ops.sh pipg smoke-api`.
7. Verify IAM-specific strict/interim account-create behavior with `bash scripts/ci_account_create_profiles.sh`.
8. Verify internal signed access-assignment tooling with:
   `scripts/access_assignment_admin.sh keygen --service-id control-automation`
9. Confirm workforce routes are present:
   - `POST /auth/workforce/session/exchange`
   - `GET /me/access-context`
   - `GET /me/permissions`
   - `GET/POST/DELETE /admin/access/assignments`
10. Confirm Cloudflare Access is actually enforcing the dashboard hostnames and
    the BFF accepts the resulting workforce identity.

## Human Verification
- Owner account can reach all staging dashboards.
- Admin account can manage access assignments without legacy role headers.
- Coach operator account only sees its own operator scope.
- Boarding or crew account cannot access admin-only coach surfaces.
- Cash-agent account can access cash flows but not platform-wide admin tools.
- Unauthenticated dashboard requests are blocked.

## Do Not Proceed To Production Until
- Staging dashboards work without legacy `X-Auth-Roles` shortcuts.
- `GET /me/permissions` returns the expected normalized grants for real staging users.
- At least one access assignment create and revoke cycle succeeds through the
  signed internal path.
- `./scripts/ops.sh pipg smoke-api` and `bash scripts/ci_account_create_profiles.sh`
  are green on the intended staging host configuration.
