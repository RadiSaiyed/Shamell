# Shamell Monolith – Security & Operations Hardening

This document summarises the key security and operational mechanisms of the
Shamell monolith. It complements the architecture overview in
`docs/shamell_monolith_overview.md` with concrete hardening aspects.

## 1. OTP / Login Flows

### 1.1 One‑time codes

- OTP codes are kept per phone number in the BFF in `_LOGIN_CODES`.
- `_check_code(phone, code)` ensures:
  - the code matches the stored value, and
  - the code has not expired (`LOGIN_CODE_TTL_SECS`).
- On successful verification the code is deleted:
  - `_LOGIN_CODES[phone]` is removed → the code is truly one‑time.

Endpoints:

- `POST /auth/request_code` – request a new OTP code.
- `POST /auth/verify` – verify the code and create a `sa_session` cookie.

### 1.2 Returning OTP codes (`AUTH_EXPOSE_CODES`)

Control via environment variable:

- `AUTH_EXPOSE_CODES=true` (default, recommended for dev/test):
  - the response from `/auth/request_code` includes an additional `code`
    field for convenience.
- `AUTH_EXPOSE_CODES=false` (recommended for production):
  - the response only contains `{"ok": true, "phone": ..., "ttl": ...}`.
  - the OTP code is only delivered via out‑of‑band channels (e.g. SMS / push).

## 2. Rate Limiting for Auth

Both auth endpoints are protected by a simple in‑process rate limiter:

- Configuration (env):
  - `AUTH_RATE_WINDOW_SECS` – window in seconds (default: `60`).
  - `AUTH_MAX_PER_PHONE` – max requests per phone number and window (default: `5`).
  - `AUTH_MAX_PER_IP` – max requests per IP and window (default: `40`).
- Covered endpoints:
  - `POST /auth/request_code`
  - `POST /auth/verify`
- Behaviour:
  - if the per‑phone limit is exceeded → HTTP `429` with
    `detail="rate limited: too many codes for this phone"`.
  - if the per‑IP limit is exceeded → HTTP `429` with
    `detail="rate limited: too many requests from this ip"`.
  - the client IP is taken best‑effort from `X-Forwarded-For` or
    `request.client.host`.

## 3. HTTP Security Headers

A global middleware adds a set of sensible default security headers:

- Env toggle:
  - `SECURITY_HEADERS_ENABLED=true|false` (default: `true`).
- Headers (when enabled):
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY` (clickjacking protection)
  - `Referrer-Policy: strict-origin-when-cross-origin`
  - `Content-Security-Policy` (CSP):

    ```text
    default-src 'self';
    img-src 'self' data:;
    script-src 'self' 'unsafe-inline';
    style-src 'self' 'unsafe-inline';
    connect-src 'self' https:;
    frame-ancestors 'none'
    ```

The CSP is intentionally moderate to still support the simple HTML admin UIs
with inline scripts/styles, while restricting external origins.

## 4. Maintenance Mode

The BFF offers a global maintenance mode to gracefully take the system
offline:

- Env flag:
  - `MAINTENANCE_MODE=true|false` (default: `false`).
- Behaviour when `MAINTENANCE_MODE=true`:
  - All requests whose path does **not** start with `/admin` or `/health`
    are answered with HTTP `503`:
    - Payload: `{"status":"maintenance","detail":"service temporarily unavailable"}`.
    - Header: `Retry-After: 60`.
  - Admin routes (`/admin/*`) and health endpoints (`/health*`) remain reachable:
    - admins can still perform deployments/changes,
    - monitoring keeps visibility into the monolith.

## 5. Admin Info & Configuration Overview

Operators get a compact view of monolith configuration and domain modes:

- Endpoint: `GET /admin/info` (admin / superadmin only via `_require_admin_v2`).
- Response includes, among other fields:
  - `env` – e.g. `dev`, `staging`, `prod`.
  - `monolith` – boolean flag whether monolith mode is active (`MONOLITH_MODE`).
  - `security_headers` – whether security headers are enabled.
  - `domains` – map per domain (payments, taxi, bus, food, stays, commerce,
    doctors, flights, agriculture, livestock) with:
    - `internal` – whether `*_INTERNAL_MODE` is active / in‑process mode is used.
    - `base_url` – configured external base URL (if any).

This endpoint is a good foundation for operations dashboards and quick
verification that a deployment is running in the expected mode.

## 6. Tests & Quality Assurance

Critical security and operational features are covered by pytest tests, e.g.:

- Login / OTP:
  - rate limiting on `/auth/request_code` and `/auth/verify`,
  - hiding the code when `AUTH_EXPOSE_CODES=false`.
- Security headers:
  - tests assert that responses contain `X-Content-Type-Options`,
    `X-Frame-Options` and `Referrer-Policy`.
- Maintenance mode:
  - normal routes return 503 while admin routes remain reachable.
- Admin info:
  - access restricted to admins; response checked for the expected structure
    (`env`, `monolith`, `domains`).

Together these mechanisms provide a solid baseline to run Shamell securely and
operationally reliably – not just as a demo, but as a reference‑grade
Shamell deployment.
