# Runtime Hardening (BFF / Monolith)

This doc lists the main security-related environment variables and recommended defaults.

## Client IP Trust (Rate Limits / Audits)

The BFF uses client IPs for best-effort in-memory rate limiting. Proxy headers are only trusted when configured.

Environment variables:
- `TRUST_PROXY_HEADERS`: `auto` (default), `off`, or `on`
  - `auto`: trust proxy headers only when the immediate peer is a trusted proxy (CIDR allowlist) or a private hop
  - `off`: never trust proxy headers
  - `on`: always trust proxy headers (not recommended unless your origin only accepts traffic from a trusted proxy)
- `TRUST_PRIVATE_PROXY_HOPS`: `true|false` (default: `true`)
  - when enabled, loopback peers (e.g. Nginx on `127.0.0.1`) are treated as trusted hops too
- `TRUSTED_PROXY_CIDRS`: comma-separated CIDRs/IPs (e.g. `10.0.0.0/8,192.168.0.0/16`)

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
- `MAPS_TAXI_STANDS_MAX_PER_IP_AUTH`, `MAPS_TAXI_STANDS_MAX_PER_IP_ANON`

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

## CSRF Guard (Cookie Sessions)

The BFF supports cookie-based browser sessions (`sa_session`). For defense-in-depth,
cookie-authenticated non-idempotent requests are blocked unless they come from an
allowed origin (or the request is clearly same-host).

Environment variables:
- `CSRF_GUARD_ENABLED`: `true|false` (default: `true` in `prod|staging`, else `false`)
- `ALLOWED_ORIGINS`: comma-separated origin allowlist (scheme + host + optional port)
  - must include your web app origin(s) if you rely on cookie sessions (e.g. `https://online.shamell.online`)
  - `*` disables the allowlist check (not recommended)

## Host Header Allowlist (Trusted Hosts)

The monolith enables Starlette's `TrustedHostMiddleware` when `ALLOWED_HOSTS` is set.
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
