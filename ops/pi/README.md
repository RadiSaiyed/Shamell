# Shamell Pi Deployment Notes

This folder contains the production/staging **microservices** compose file for Pi/edge deployments:

- `docker-compose.yml` (BFF + Chat + Payments + Taxi + LiveKit)

An optional Postgres-backed variant is available for production-hardening and multi-instance readiness:

- `docker-compose.postgres.yml` (Postgres + BFF + Chat + Payments + Taxi + LiveKit + `migrate-sqlite-to-postgres`)

For rollback and reference, the legacy monolith stack is preserved as:

- `docker-compose.monolith.yml` (Monolith + LiveKit)

Security baseline env templates are provided for staged rollout:

- `env.staging.example`
- `env.prod.example`

Both templates focus on:

- payments edge rate limits (`PAY_API_*`)
- runtime security alerting (`SECURITY_ALERT_*`)
- ensuring strong payments secrets are configured (no `change-me-*` defaults in prod/staging)
- avoiding dangerous schema auto-create in prod/staging (`AUTO_CREATE_SCHEMA=false`)
- disabling OTP/alias code exposure in non-dev environments
- trusted host allowlist (`ALLOWED_HOSTS`) to mitigate Host header attacks
- disabling interactive API docs in staging/prod (unless explicitly enabled)
- keeping raw domain routers disabled in prod/staging (BFF-only public surface)
- disabling dev-only wallet websocket stream in prod/staging
- protecting (or disabling) metrics ingest in prod/staging

## Additional Runtime Flags

These are intentionally fail-closed defaults for staging/prod:

- `EXPOSE_PAYMENTS_ROUTER` / `EXPOSE_CHAT_ROUTER`: keep `false` in staging/prod so only the BFF is public.
- `ENABLE_WALLET_WS_IN_PROD`: keep `false` unless you explicitly want the dev wallet stream exposed.
- `METRICS_INGEST_SECRET`: when set, `/metrics` ingest requires the secret; when empty, ingest is disabled (403).

## LiveKit Notes

This repo assumes:

- LiveKit is publicly reachable for WebRTC media, but clients must only join using **server-minted tokens**.
- LiveKit's HTTP/WebSocket API (`7880`) should be private and served over TLS via Nginx.

Practical implications:

- Keep `LIVEKIT_HTTP_PUBLISH_ADDR=127.0.0.1` (default in `ops/pi/docker-compose*.yml`) and proxy `443 -> 127.0.0.1:7880` in Nginx (see `ops/hetzner/nginx/sites-available/livekit.shamell.online`).
- WebRTC media still requires public reachability for `7881/tcp` and `7882/udp`. If you run Cloudflare-only origin lockdown, you must either:
  - run LiveKit on a separate host/IP, or
  - use a proxy that supports arbitrary TCP/UDP (e.g. Cloudflare Spectrum), or
  - explicitly open these ports on the origin firewall (note: this exposes the origin IP to participants).

To enable the token mint endpoint (`POST /livekit/token`):

- set `LIVEKIT_TOKEN_ENDPOINT_ENABLED=true`
- set `LIVEKIT_PUBLIC_URL` to the client-facing `wss://...` URL
- set strong `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` (non-dev values)

## Data Migration Note (Monolith -> Microservices)

`docker-compose.yml` includes a `bootstrap-perms` init container that:

- seeds the new service volumes from the previous monolith volume (`monolith_data`) on first run
- never overwrites existing destination DB files (idempotent)
- fixes volume ownership to the non-root runtime UID/GID (10001:10001)

This enables a low-risk cutover while keeping the old monolith volume intact for rollback/backups.

## Postgres Migration Note (SQLite -> Postgres)

`docker-compose.postgres.yml` includes:

- a `db` service (Postgres 16)
- a one-shot `migrate-sqlite-to-postgres` service that reads the legacy SQLite volumes (`bff_data`, `chat_data`, `payments_data`, `taxi_data`) and inserts rows into Postgres

Best practice rollout is staging-first, with a full SQLite volume backup immediately before cutover.

## Recommended Rollout

1. Copy one template into `ops/pi/.env` and keep existing secrets unchanged.
2. Enable `SECURITY_ALERT_WEBHOOK_URL` before tightening limits.
3. Deploy to staging first and run smoke + core payment flows for at least 24h.
4. Deploy to production with canary traffic first, then full rollout after clean metrics.

Suggested canary gates:

1. 10% traffic for 30-60 minutes.
2. 50% traffic for 2-4 hours.
3. 100% traffic if no sustained alert spikes or elevated `429` on legit flows.

## Tuning Heuristics

Use a 60-second limiter window (`PAY_API_RATE_WINDOW_SECS=60`) and tune by observed p95:

1. If legitimate `429` exceeds 0.3% for an action family over 15 minutes, raise that family by 15-25%.
2. If abuse telemetry stays low for 7 days, lower high-risk families (`resolve`, write paths) by 10-15%.
3. Keep `*_PER_IP` roughly 4x `*_PER_WALLET` to curb spray attacks while preserving NAT users.
4. Keep staging stricter than prod to catch regressions early.
