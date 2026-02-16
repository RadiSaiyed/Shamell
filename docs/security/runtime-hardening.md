# Runtime Hardening (BFF / Microservices)

This doc lists the main security-related environment variables and recommended defaults.

## Secret Quality Policy

In `prod|staging`, services fail fast for weak secrets:
- minimum length: 16 characters
- placeholder/default-like values are rejected (e.g. `change-me`, `replace-me`, `...please-rotate...`)

Applied to internal auth and signing secrets such as:
- `INTERNAL_API_SECRET`
- `PAYMENTS_INTERNAL_SECRET`
- `BUS_PAYMENTS_INTERNAL_SECRET`
- `BUS_INTERNAL_SECRET`
- `BUS_TICKET_SECRET`
- `BFF_ROLE_HEADER_SECRET`

## Client IP Trust (Auth Rate Limits / Audits)

The BFF auth path uses an edge-attested header for client IP:
- `X-Shamell-Client-IP` (set by Nginx edge snippet)

Operational model:
- Public traffic never sets this header directly; Nginx overwrites it using `$remote_addr`.
- In `prod|staging`, auth rate limits fail closed when this header is missing.
- In `dev|test`, BFF can fall back to legacy proxy headers (`X-Forwarded-For`, `X-Real-IP`) for local convenience.

## Auth Abuse Guardrails (BFF)

Auth/session guardrails are backed by Postgres (`auth_biometric_tokens`, `auth_rate_limits`) so
limits remain consistent across multiple BFF instances.

Public account creation is protected by rate limits and an attestation layer:
- `POST /auth/account/create/challenge`: issues a short-lived signed challenge token (rate-limited).
  - may also include a PoW puzzle when enabled
  - includes a hardware-attestation nonce (Android Play Integrity) derived from the challenge token
- `POST /auth/account/create`: requires PoW and/or hardware attestation depending on policy (fails closed with `401`).

Environment variables:
- `AUTH_ACCOUNT_CREATE_WINDOW_SECS`
- `AUTH_ACCOUNT_CREATE_MAX_PER_IP`
- `AUTH_ACCOUNT_CREATE_MAX_PER_DEVICE`
- `AUTH_ACCOUNT_CREATE_ENABLED` (global gate for public brand-new account creation)
- `AUTH_ACCOUNT_CREATE_POW_ENABLED`
- `AUTH_ACCOUNT_CREATE_POW_TTL_SECS`
- `AUTH_ACCOUNT_CREATE_POW_DIFFICULTY_BITS`
- `AUTH_ACCOUNT_CREATE_POW_SECRET` (required in `prod|staging` when PoW is enabled)
- `AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED`
- `AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION`
- `AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID`
- `AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_KEY_ID`
- `AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64`
- `AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64`
- `AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES`
- `AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY`
- `AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED`
- `AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_LICENSED`
- `AUTH_ACCOUNT_CREATE_CHALLENGE_WINDOW_SECS`
- `AUTH_ACCOUNT_CREATE_CHALLENGE_MAX_PER_IP`
- `AUTH_ACCOUNT_CREATE_CHALLENGE_MAX_PER_DEVICE`
- `AUTH_BIOMETRIC_TOKEN_TTL_SECS`
- `AUTH_BIOMETRIC_LOGIN_WINDOW_SECS`
- `AUTH_BIOMETRIC_LOGIN_MAX_PER_IP`
- `AUTH_BIOMETRIC_LOGIN_MAX_PER_DEVICE`
- `AUTH_DEVICE_LOGIN_*` (device-login start/redeem/approve limits)
  - includes token-level limits: `AUTH_DEVICE_LOGIN_REDEEM_MAX_PER_TOKEN`, `AUTH_DEVICE_LOGIN_APPROVE_MAX_PER_TOKEN`
- `AUTH_CHAT_REGISTER_*` (limits for `/chat/devices/register`)
- `AUTH_CHAT_GET_DEVICE_*` (limits for `/chat/devices/{id}`)
- `AUTH_CHAT_SEND_*` (limits for `/chat/messages/send`)
- `AUTH_CHAT_SEND_REQUIRE_CONTACTS`: `true|false`
  - when `true`, direct sends require a server-side contact edge created via invite redemption
  - disallowed direct sends fail closed with `404` (reduces recipient enumeration)
- `AUTH_CHAT_GROUP_SEND_*` (limits for `/chat/groups/{id}/messages/send`)
- `AUTH_SESSION_IDLE_TTL_SECS` (session idle timeout window)
- `AUTH_MAINTENANCE_INTERVAL_SECS`
- `AUTH_*_CLEANUP_GRACE_SECS`
- `AUTH_DEVICE_SESSION_RETENTION_SECS`
- `AUTH_RATE_LIMIT_RETENTION_SECS`
  - recommended baseline: 30 days (`2592000`) for device metadata retention

Strict prod/staging profile:
- keep `AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED=true`
- keep `AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION=true` (no fallback)
- keep `AUTH_ACCOUNT_CREATE_ENABLED=true`
- provide complete Apple DeviceCheck and Google Play Integrity credentials (partial config fails closed)
- keep `AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY=true`
- keep `AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED=true`

Secure interim mode (when attestation credentials are not yet available):
- set `AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED=false`
- set `AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION=false`
- set `AUTH_ACCOUNT_CREATE_ENABLED=false`
- keep attestation provider variables empty:
  - `AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_*`
  - `AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64`
  - `AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES`
- keep Play Integrity policy flags disabled in this mode:
  - `AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY=false`
  - `AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED=false`
  - `AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_LICENSED=false`
- outcome: brand-new account creation endpoints are disabled server-side (fail-closed) until credentials are provisioned

Audit logging:
- Device-login flow emits structured security events (`issued`, `approved`, `redeemed`, `blocked`) with
  pseudonymous identifiers (`phone_hash`, `token_hash`) to support abuse triage without leaking raw PII/tokens.

## Push SSRF Guardrails (UnifiedPush)

UnifiedPush endpoints are user-controlled callback URLs and must be treated as untrusted.

Environment variables:
- `PUSH_ALLOWED_HOSTS`: optional comma-separated hostname allowlist
- `PUSH_ALLOW_HTTP`: `true|false` (default: `false`)
- `PUSH_ALLOW_PRIVATE_IPS`: `true|false` (default: `false`)
- `PUSH_VALIDATE_DNS`: `true|false` (default: `true`)
- `PUSH_MAX_ENDPOINT_LEN`: max callback URL length (default: `2048`)

## Maps / Geocoding / Routing Abuse Guardrails

These endpoints can proxy paid APIs (e.g. TomTom/ORS) and should be rate-limited.

Environment variables (examples):
- `MAPS_RATE_WINDOW_SECS` (default: `60`)
- `MAPS_MAX_QUERY_LEN` (default: `256`)
- `MAPS_MAX_BATCH_QUERIES` (default: `50`)
- `MAPS_CACHE_MAX_ITEMS` (default: `2000`)
- `MAPS_CACHE_TTL_SECS` (default: `600`)

Per-IP limits (authenticated vs anonymous):
- `MAPS_GEOCODE_MAX_PER_IP_AUTH`, `MAPS_GEOCODE_MAX_PER_IP_ANON`
- `MAPS_GEOCODE_BATCH_MAX_PER_IP_AUTH`, `MAPS_GEOCODE_BATCH_MAX_PER_IP_ANON`
- `MAPS_ROUTE_MAX_PER_IP_AUTH`, `MAPS_ROUTE_MAX_PER_IP_ANON`
- `MAPS_POI_MAX_PER_IP_AUTH`, `MAPS_POI_MAX_PER_IP_ANON`
- `MAPS_REVERSE_MAX_PER_IP_AUTH`, `MAPS_REVERSE_MAX_PER_IP_ANON`

Note: `/osm/geocode_batch` requires authentication by design (it can amplify abuse).

## Fleet Helper Input Caps

The fleet helper endpoints are CPU-bound; cap input sizes.

Environment variables:
- `FLEET_MAX_STOPS` (default: `200`)
- `FLEET_MAX_DEPOTS` (default: `50`)

## Security Headers

Environment variables:
- `SECURITY_HEADERS_ENABLED`: `true|false` (default: `true`)
- `HSTS_ENABLED`: `true|false` (default: `true` in `prod|staging`, else `false`)
- `CSP_ENABLED`: `true|false` (default: `true`)
- `CSP_HEADER_VALUE`: optional override for the CSP header value

When enabled, all Rust services add (if absent):
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `Referrer-Policy: no-referrer`
- `Permissions-Policy: camera=(), microphone=(), geolocation=()`
- `Strict-Transport-Security: max-age=31536000; includeSubDomains` (when `HSTS_ENABLED=true`)
- `Content-Security-Policy: ...` (when `CSP_ENABLED=true`)

## CSRF Guard (Cookie Sessions)

The BFF supports cookie-based browser sessions (`__Host-sa_session`).
Legacy `sa_session` cookie fallback is controlled via env for staged cutover. For defense-in-depth,
cookie-authenticated non-idempotent requests are blocked unless they come from an
allowed origin (or the request is clearly same-host).

Behavior:
- only enforced for unsafe methods (`POST|PUT|PATCH|DELETE`)
- only enforced when session cookie auth is used (`__Host-sa_session` or legacy `sa_session`)
- fallback block on `Sec-Fetch-Site: cross-site` when no `Origin/Referer` is available

Environment variables:
- `CSRF_GUARD_ENABLED`: `true|false` (default: `true` in `prod|staging`, else `false`)
- `AUTH_ACCEPT_LEGACY_SESSION_COOKIE`: `true|false` (default: `false` in `prod|staging`, `true` in `dev|test`)
- `ALLOWED_ORIGINS`: comma-separated origin allowlist (scheme + host + optional port)
  - must include your web app origin(s) if you rely on cookie sessions (e.g. `https://online.shamell.online,https://shamell.online`)
  - `*` disables the allowlist check (not recommended)

Recommended cutover:
1. Keep `AUTH_ACCEPT_LEGACY_SESSION_COOKIE=true` in staging for one short migration window.
2. Verify no active clients rely on legacy cookie-only auth.
3. Set `AUTH_ACCEPT_LEGACY_SESSION_COOKIE=false` in staging, then production.

## Host Header Allowlist (Trusted Hosts)

The BFF (and internal services) enable Starlette's `TrustedHostMiddleware` when `ALLOWED_HOSTS` is set.
This mitigates Host header attacks and prevents misrouting, but it will also hard-fail
requests with unknown Host headers (HTTP 400).

Environment variables:
- `ALLOWED_HOSTS`: comma-separated host allowlist (no wildcards)
  - production must include your public domains (at least `api.shamell.online` and `online.shamell.online`)
  - include `localhost,127.0.0.1` for local health checks

## In-Memory Store Bounds (Rate Limits / Guardrails)

The BFF uses best-effort in-memory stores for rate limiting and velocity guardrails.
To prevent memory DoS via key-spam (many unique IPs/devices/wallet IDs), these stores
are bounded.

Environment variables:
- `RATE_STORE_MAX_KEYS`: max keys per store (default: `20000`)
  - set to `0` to clear stores (disables rate limiting; not recommended)

## Route Allowlist (Attack-Surface Reduction)

The BFF contains legacy/optional endpoints for experiments and past modules.
In production/staging, it is best practice to **fail-closed** and only expose
the routes your clients actually use.

Environment variables:
- `BFF_ROUTE_ALLOWLIST_ENABLED`: `true|false`
  - default: `true` in `prod|staging`, else `false`
- `BFF_ROUTE_ALLOWLIST_EXACT`: comma-separated exact paths to allow (optional)
  - when unset, the BFF uses a safe default (e.g. `/health`, `/`, `/docs` when enabled)
- `BFF_ROUTE_ALLOWLIST_PREFIXES`: comma-separated path prefixes to allow (optional)
  - when unset, the BFF uses a conservative Shamell-like default (auth, me, chat, payments, bus, admin, etc.)

Notes:
- Disallowed paths return `404` to reduce endpoint enumeration.
- Keep this enabled in `prod|staging` and tighten the list as you delete modules.

## Privileged Route AuthZ

Privileged BFF routes (operator/admin) are protected by two checks:
- authenticated session (`__Host-sa_session` cookie; optional legacy `sa_session` fallback via `AUTH_ACCEPT_LEGACY_SESSION_COOKIE`)
- trusted role headers (`X-Auth-Roles`/`X-Roles`) plus `X-Role-Auth` attestation

Both checks must pass when route authz is enabled.

## Chat Protocol Policy (V2-Only, No Fallback)

The chat service supports a staged protocol migration using explicit message metadata.

Environment variables:
- `CHAT_PROTOCOL_V2_ENABLED`: `true|false` (default: `true`)
- `CHAT_PROTOCOL_V1_WRITE_ENABLED`: `true|false` (default: `false`)
- `CHAT_PROTOCOL_V1_READ_ENABLED`: `true|false` (default: `false`)
- `CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS`: `true|false` (default: `true`)

Safety constraints:
- `CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS=true` requires `CHAT_PROTOCOL_V2_ENABLED=true`.
- At least one write path must stay enabled (`v2` or `v1 write`), otherwise service startup fails.

Recommended policy (strict by default):
1. Keep `CHAT_PROTOCOL_V2_ENABLED=true`.
2. Keep `CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS=true`.
3. Keep legacy disabled: `CHAT_PROTOCOL_V1_WRITE_ENABLED=false` and `CHAT_PROTOCOL_V1_READ_ENABLED=false`.

## Request Body Caps (DoS Hardening)

To reduce memory/CPU DoS risk, enforce strict request body size caps at multiple layers.

Environment variables:
- `BFF_MAX_BODY_BYTES`: cap request bodies accepted by the BFF (default: 1 MiB, clamped to 16 KiB..10 MiB)
- `BFF_MAX_UPSTREAM_BODY_BYTES`: cap upstream responses the BFF will read (default: 1 MiB, clamped to 16 KiB..20 MiB)
- `CHAT_MAX_BODY_BYTES`: cap request bodies accepted by the chat service (default: 2 MiB, clamped to 16 KiB..10 MiB)

## Chat Push Metadata Minimization

To reduce provider-visible communication metadata, chat push should be wake-only.

Behavior:
- Chat push payload is fixed to wake-only (`type=chat_wakeup`) with no `sender_id`,
  `group_id`, `group_name`, `device_id`, or message ID.

Safety constraints:
- Keep push content minimal and let the app poll inbox after wake-up.

## Mailbox API Rollout

The chat service can expose mailbox-style store-and-forward endpoints behind a feature gate.

Environment variable:
- `CHAT_MAILBOX_API_ENABLED`: `true|false` (default: `false`)

Notes:
- Keep disabled until clients are ready for mailbox token flows.
- When disabled, mailbox endpoints return `404`.
