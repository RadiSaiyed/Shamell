# Shamell Pi Deployment Notes

Pi/Hetzner deploy uses a Rust microservices stack with Postgres:

- `docker-compose.postgres.yml` (Postgres + BFF + Chat + Payments + LiveKit)
- `docker-compose.yml` (alias copy of the same Postgres-backed stack)

## Environment
Use `ops/pi/.env` (do not commit secrets).

Security baseline templates:
- `env.prod.example`
- `env.staging.example`

Auth hardening baseline (set in env templates):
- Biometric/device-login rate limits (`AUTH_BIOMETRIC_LOGIN_*`, `AUTH_DEVICE_LOGIN_*`)
- token-scoped device-login limits (`AUTH_DEVICE_LOGIN_REDEEM_MAX_PER_TOKEN`, `AUTH_DEVICE_LOGIN_APPROVE_MAX_PER_TOKEN`)
- chat device abuse limits (`AUTH_CHAT_REGISTER_*`, `AUTH_CHAT_GET_DEVICE_*`)
- mailbox write abuse limits (`AUTH_CHAT_MAILBOX_WRITE_*`)
- chat protocol migration flags (`CHAT_PROTOCOL_V2_ENABLED`, `CHAT_PROTOCOL_V1_WRITE_ENABLED`, `CHAT_PROTOCOL_V1_READ_ENABLED`, `CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS`)
- mailbox transport API rollout flag (`CHAT_MAILBOX_API_ENABLED=true` in staging template, keep `false` in prod until rollout sign-off)
- mailbox transport metadata retention (`CHAT_MAILBOX_CONSUMED_RETENTION_SECS`, `CHAT_MAILBOX_INACTIVE_RETENTION_SECS`)
- fail-closed service schema bootstrap (`AUTH_AUTO_APPLY_SCHEMA=false`, `CHAT_AUTO_APPLY_SCHEMA=false`, `PAYMENTS_AUTO_APPLY_SCHEMA=false` in prod/staging; only turn on during controlled bootstrap/restore windows)
- fail-closed payments fee-wallet startup provisioning (`PAYMENTS_AUTO_PROVISION_FEE_WALLET=false` in prod/staging; only turn on during controlled first-time wallet bootstrap windows)
- Postgres-backed auth abuse state (`auth_biometric_tokens`, `auth_rate_limits`)
- session idle timeout (`AUTH_SESSION_IDLE_TTL_SECS`)
- CSRF guard for cookie sessions (`CSRF_GUARD_ENABLED`, `ALLOWED_ORIGINS`)
- legacy cookie fallback cutover switch (`AUTH_ACCEPT_LEGACY_SESSION_COOKIE`)
- service-side security headers + HSTS + CSP (`SECURITY_HEADERS_ENABLED`, `HSTS_ENABLED`, `CSP_ENABLED`)
- secret quality fail-fast in prod/staging (min length + no placeholder secrets)
- per-service internal auth baseline (`INTERNAL_API_SECRET` for edge -> BFF; keep `PAYMENTS_INTERNAL_SECRET` / `CHAT_INTERNAL_SECRET` empty unless a compatibility rollback is needed)
- signed, audience-bound BFF -> Chat/Payments service identity (`BFF_INTERNAL_IDENTITY_SIGNING_SEED_B64`, `CHAT_INTERNAL_IDENTITY_PUBLIC_KEYS`, `PAYMENTS_INTERNAL_IDENTITY_PUBLIC_KEYS`)
- signed security-alert ingress identity (`BFF_SECURITY_ALERT_INTERNAL_IDENTITY_PUBLIC_KEYS`, `BFF_SECURITY_ALERT_INTERNAL_IDENTITY_MAX_SKEW_SECS`, `BFF_SECURITY_ALERT_REQUIRE_INTERNAL_IDENTITY_V2=true`, `BFF_SECURITY_ALERT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK=false`)
- signed internal replay window + v2-only policy (`CHAT_INTERNAL_IDENTITY_MAX_SKEW_SECS`, `PAYMENTS_INTERNAL_IDENTITY_MAX_SKEW_SECS`, `CHAT_REQUIRE_INTERNAL_IDENTITY_V2=true`, `PAYMENTS_REQUIRE_INTERNAL_IDENTITY_V2=true`, `CHAT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK=false`, `PAYMENTS_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK=false`)
- internal caller allowlists (`BFF_SECURITY_ALERT_ALLOWED_CALLERS`, `CHAT_INTERNAL_ALLOWED_CALLERS`, `PAYMENTS_INTERNAL_ALLOWED_CALLERS`)
- legacy chat token bootstrap is removed and must stay disabled
- service caller IDs for internal hops (`BFF_INTERNAL_SERVICE_ID`)
- direct wallet topup disabled by default in staging/prod (`PAYMENTS_ALLOW_DIRECT_TOPUP=false`)
- periodic auth data cleanup (`AUTH_MAINTENANCE_INTERVAL_SECS`, `AUTH_*_CLEANUP_GRACE_SECS`)
- device metadata retention (`AUTH_DEVICE_SESSION_RETENTION_SECS`, recommended: `2592000` = 30 days)
- rate-limit state retention (`AUTH_RATE_LIMIT_RETENTION_SECS`)
- runtime alert endpoint (`SECURITY_ALERT_WEBHOOK_URL=http://127.0.0.1:8080/internal/security/alerts`)
- runtime alert signed identity (`SECURITY_ALERT_WEBHOOK_SIGNING_SEED_B64`, `SECURITY_ALERT_WEBHOOK_SERVICE_ID=security-reporter`)
- runtime alert legacy auth header override (`SECURITY_ALERT_WEBHOOK_INTERNAL_SECRET`, compatibility-only)
- runtime alert caller-id header (`SECURITY_ALERT_WEBHOOK_SERVICE_ID=security-reporter`)

### Account-Create Hardware Attestation (Strict)

For prod/staging, keep account creation strict (no fallback):

- `AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED=true`
- `AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION=true`
- `AUTH_ACCOUNT_CREATE_POW_ENABLED=true`
- `AUTH_ACCOUNT_CREATE_POW_SECRET` set to a strong secret

Required provider secrets in `ops/pi/.env`:

- `AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID`
- `AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_KEY_ID`
- `AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64` (base64 of `.p8` private key)
- `AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64` (base64 of service-account JSON)
- `AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES`
- `AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY=true`
- `AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED=true`

Convenience setup command:

```bash
scripts/configure_account_create_attestation.sh \
  --env-file ops/pi/.env \
  --apple-team-id <TEAM_ID> \
  --apple-key-id <KEY_ID> \
  --apple-p8-file <path/to/AuthKey_XXXX.p8> \
  --google-sa-json-file <path/to/play-integrity-sa.json>
```

### Account-Create Secure Interim Mode (Credentials Pending)

If Apple/Google attestation credentials are not available yet, keep account creation
fail-closed until provisioning is complete:

- `AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED=false`
- `AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION=false`
- `AUTH_ACCOUNT_CREATE_ENABLED=false`
- keep all attestation provider vars empty (`AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_*`,
  `AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64`,
  `AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES`)
- keep Play Integrity policy flags off:
  - `AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY=false`
  - `AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED=false`
  - `AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_LICENSED=false`

This keeps existing sessions/device-login working but blocks brand-new public account creation.

## Deployment

```bash
./scripts/ops.sh pipg check
./scripts/ops.sh pipg deploy
./scripts/ops.sh pipg report
./scripts/ops.sh pipg ride-report
./scripts/ops.sh pipg ride-repair-stale-presence --dry-run
./scripts/ops.sh pipg ride-release-gate
./scripts/ops.sh pipg smoke-api
./scripts/ops.sh pipg security-report
./scripts/ops.sh pipg security-drill --dry-run
```

Canonical edge maintenance:

```bash
./scripts/ops.sh pipg cloudflare-status
./scripts/ops.sh pipg cloudflare-refresh
./scripts/ops.sh pipg sync-nginx shamell
./scripts/ops.sh pipg sync-ufw shamell
./scripts/ops.sh pipg sync-edge shamell
./scripts/ops.sh pipg sync-ride-report-timer shamell --run-now
```

Access assignment admin path:

```bash
./scripts/ops.sh pipg access-assign keygen --service-id control-automation
./scripts/ops.sh pipg access-assign list --phone +963944444444
./scripts/ops.sh pipg access-assign add --phone +963944444444 --role-id platform.admin --platform
./scripts/ops.sh pipg access-assign remove --phone +963944444444 --role-id official.account_owner --official-account-id shamell_pay
```

Required env wiring for the signed internal admin path:

- `BFF_ACCESS_ASSIGNMENT_ALLOWED_CALLERS=control-automation,iam-sync`
- `BFF_ACCESS_ASSIGNMENT_INTERNAL_IDENTITY_PUBLIC_KEYS=control-automation=<pub>,iam-sync=<pub>`
- `BFF_ACCESS_ASSIGNMENT_INTERNAL_IDENTITY_MAX_SKEW_SECS=30`
- `BFF_ACCESS_ASSIGNMENT_REQUIRE_INTERNAL_IDENTITY_V2=true`
- `BFF_ACCESS_ASSIGNMENT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK=false`
- `ACCESS_ASSIGNMENT_ADMIN_SERVICE_ID=control-automation`
- `ACCESS_ASSIGNMENT_ADMIN_SIGNING_SEED_B64=<b64-ed25519-seed>`
- `ACCESS_ASSIGNMENT_ADMIN_AUDIENCE=bff`

Notes:
- `cloudflare-status` is the canonical local freshness check for the
  Cloudflare CIDR source of truth before any host sync.
- `check` and `deploy` now also fail closed if the local Cloudflare CIDR source
  of truth is stale.
- `report` now exits non-zero if health or Cloudflare freshness fails.
- `report` also runs `ride-report` on non-dev stacks and, by default, fails if
  ride-hailing findings are present.
- `ride-repair-stale-presence` is the explicit operator repair path for stale
  online driver presence rows; it sets those drivers offline and cancels any
  pending dispatch offers for them.
- `ride-release-gate` is the canonical ride close-out: it runs
  `schema-migrate bff`, `schema-migrate payments`, `health`, `smoke-api`, and
  `ride-report` with `RIDE_REPORT_FAIL_ON_FINDINGS=1`.
- GitHub Actions mirrors the same close-out with the `ride-gate` CI job and the
  scheduled `Ride Gate Nightly` workflow, both with artifact capture and a
  markdown run summary. The nightly workflow automatically opens or closes a
  single failure issue as the gate regresses or recovers.
- `sync-nginx` and `sync-edge` now run the same non-dev env preflight before
  any host mutation.
- `sync-edge` refreshes the local Cloudflare CIDR source of truth first, then
  syncs Nginx and UFW.
- `sync-ride-report-timer` installs a recurring `systemd` timer for ride ops
  audits using the same resolved deploy tree and env file as the host stack.
- `sync-nginx` forwards the currently selected ops env file (`ops/pi/.env` by
  default, or `ENV_FILE=...`) into `NGINX_SYNC_ENV_FILE`, so the host-local
  `X-Internal-Secret` snippet stays aligned with the same deployment env.
- Append `--allow-livekit` and/or `--direct-web` to `sync-edge` when the same
  UFW exceptions are intentionally needed on the target host.

`smoke-api` now verifies account-create rollout policy:
- strict mode (`AUTH_ACCOUNT_CREATE_ENABLED=true`): challenge endpoint should return `200` (or `429` under rate-limit)
- secure interim mode (`AUTH_ACCOUNT_CREATE_ENABLED=false`): challenge endpoint must return `503`
- emergency Pow-only mode (`AUTH_ACCOUNT_CREATE_ENABLED=true` + `AUTH_ACCOUNT_CREATE_EMERGENCY_POW_ONLY=true`):
  - requires `AUTH_ACCOUNT_CREATE_POW_ENABLED=true`
  - requires `AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED=false`
  - requires `AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION=false`
  - challenge endpoint should return `200` (or `429` under rate-limit)

When running smokes against a direct BFF instance, keep `BFF_TRUSTED_PROXY_CIDRS`
configured for the immediate loopback/proxy hop and optionally provide:
- `SMOKE_CLIENT_IP=<ip>` so the smoke sends `X-Forwarded-For: <ip>` and the BFF can derive that client IP through the trusted-proxy path

For Dockerized local dashboard proxies (`scripts/start_dashboard_dev_proxy.sh`,
`scripts/start_all_dashboard_proxies.sh`), loopback-only
`BFF_TRUSTED_PROXY_CIDRS=127.0.0.1/32,::1/128` is not enough. The BFF sees the
proxy container as a non-loopback peer, so add the Docker bridge/gateway CIDR
used by that proxy hop or explicitly opt out of client-IP simulation with
`DASHBOARD_PROXY_ALLOW_UNTRUSTED_CLIENT_IP=1`.

CI profile guard (strict + interim):

```bash
bash ./scripts/ci_account_create_profiles.sh
```

## Edge Internal-Auth (Internal Routes Only)

`X-Internal-Secret` is reserved for true internal-only endpoints (e.g.
`/internal/security/alerts`). The client-facing API routes must remain reachable
for authenticated clients (cookie session + app-auth), and should not rely on a
shared-secret header injected by Nginx.

If you do run internal-only routes behind Nginx, you can still inject the
header via the host-local snippet:

- `/etc/nginx/snippets/shamell_bff_internal_auth.local.conf`

Apply Nginx IaC (also renders the snippet from `ops/pi/.env` by default):

```bash
NGINX_SYNC_ENV_FILE=ops/pi/.env ./scripts/sync_hetzner_nginx.sh shamell
```

Aliases:
- `pi` -> `pipg`
- `prod` -> `pipg`

## Runtime Security Timer (Hetzner)

Install/update `systemd` timer on host:

```bash
./scripts/sync_hetzner_security_timer.sh shamell --run-now
```

Run webhook drill on host:

```bash
./scripts/sync_hetzner_security_timer.sh shamell --drill
```

## Ride Ops Timer (Hetzner)

Install/update `systemd` timer on host:

```bash
./scripts/ops.sh pipg sync-ride-report-timer shamell --run-now
```

## Mailbox API Staging Smoke

Use this checklist after staging deploy when `CHAT_MAILBOX_API_ENABLED=true`.

1. Health and config
   - `./scripts/ops.sh pipg check`
   - Confirm staging env contains `CHAT_MAILBOX_API_ENABLED=true`.
2. Endpoint reachability via BFF
   - Recommended: `./scripts/ops.sh pipg smoke-mailbox`
     - Note: this seeds a temporary auth session/device in `shamell_core` and cleans it up on exit.
     - It refuses to run when `ENV=prod` unless `SMOKE_ALLOW_PROD=1` is set.
   - `POST /chat/mailboxes/issue` with valid chat device auth headers returns `200` and `mailbox_token`.
   - `POST /chat/mailboxes/write` with that token and a valid envelope returns `200` and `accepted=true`.
   - Replaying the same `write` with the same token and envelope stays idempotent and must not create a duplicate mailbox row.
   - `POST /chat/mailboxes/poll` as mailbox owner returns the written message once.
   - A second `poll` returns empty list (message marked consumed).
   - `POST /chat/mailboxes/rotate` returns a new token; old token no longer accepts writes, and pending unread backlog remains pollable via the new token.
3. Fail-closed auth checks
   - `issue/poll/rotate` without valid device auth must return `401/403`.
   - `poll/rotate` from non-owner device must return not found/forbidden behavior (no existence leak).
4. Observability
   - Verify no mailbox token plaintext is logged in BFF/chat service logs.
   - Verify 5xx rate does not increase after enabling flag.
5. Rollback
   - Set `CHAT_MAILBOX_API_ENABLED=false`, redeploy.
   - Confirm mailbox endpoints return `404`.

Files:
- `ops/hetzner/systemd/shamell-security-events-report.service`
- `ops/hetzner/systemd/shamell-security-events-report.timer`
- `ops/hetzner/systemd/README.md`

## Backups
Postgres dump bundle:

```bash
./scripts/ops.sh pipg backup
```

Restore (destructive):

```bash
CONFIRM_RESTORE=1 ./scripts/ops.sh pipg restore <backup-file.tar.gz>
```

Optional full schema reset before restore:

```bash
CONFIRM_RESTORE=1 RESTORE_DROP_SCHEMA=1 ./scripts/ops.sh pipg restore <backup-file.tar.gz>
```

If Chat/Payments schema bootstrap is intentionally needed during a controlled restore or first-time bootstrap, prefer the dedicated migration binaries instead of toggling service startup mutation back on:

```bash
docker compose -f ops/pi/docker-compose.postgres.yml run --rm bff \
  shamell_bff_auth_schema_migrate

docker compose -f ops/pi/docker-compose.postgres.yml run --rm chat \
  shamell_chat_schema_migrate

docker compose -f ops/pi/docker-compose.postgres.yml run --rm payments \
  shamell_payments_schema_migrate
```

If payments fee-wallet provisioning is intentionally needed during a controlled first-time bootstrap, keep it as a separate maintenance action:

```bash
PAYMENTS_AUTO_PROVISION_FEE_WALLET=true \
  docker compose -f ops/pi/docker-compose.postgres.yml up -d payments
```

After the maintenance window completes, revert `PAYMENTS_AUTO_PROVISION_FEE_WALLET` to `false` and redeploy so subsequent boots stay fail-closed.

## LiveKit
- Keep `LIVEKIT_HTTP_PUBLISH_ADDR=127.0.0.1` and terminate TLS at Nginx.
- On the API host, keep `LIVEKIT_RTC_PUBLISH_ADDR=127.0.0.1` by default.
- For production RTC, run LiveKit on a dedicated host/IP (`ops/livekit` stack).
- Use strong non-dev `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` in staging/prod.
