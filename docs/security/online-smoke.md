# Online Smoke (Staging/Prod) Checklist

Goal: quick, read-only checks that catch security regressions in the public API boundary
after deploys (especially mis-layered internal-auth that breaks real clients).

## What this covers

- Public client-facing routes must **not** require `X-Internal-Secret`.
- Internal-only routes (e.g. `/internal/*`) must remain **non-public** (blocked at edge) or
  require `X-Internal-Secret` (direct-to-service).

## Run

On the deployment host (recommended):

```bash
./scripts/ops.sh pipg deploy
./scripts/ops.sh pipg smoke-api
```

## CORS preflight canary (staging/prod-safe)

This performs read-only `OPTIONS` checks against public BFF paths and verifies:
- route-scoped CORS header whitelists
- no leaked internal/proxy headers in `Access-Control-Allow-Headers`
- internal route `/internal/security/alerts` does not expose CORS headers

Local/manual:

```bash
SMOKE_BASE_URL="https://staging-api.shamell.online" \
SMOKE_ORIGIN="https://online.shamell.online" \
bash ./scripts/cors_preflight_smoke.sh
```

CI workflow:
- `.github/workflows/cors-preflight-smoke.yml`
- Staging runs on schedule and `workflow_dispatch`
- Production runs on `workflow_dispatch` (or schedule if `CORS_PREFLIGHT_PROD_ENABLED=true`)

Required secrets/vars:
- staging: `STAGING_BFF_BASE_URL`
- production: `PROD_BFF_BASE_URL`
- optional vars:
  - `CORS_PREFLIGHT_STAGING_ORIGIN` (default: `https://online.shamell.online`)
  - `CORS_PREFLIGHT_PROD_ORIGIN` (default: `https://online.shamell.online`)
  - `CORS_PREFLIGHT_MAX_FAILED_CHECKS` (default: `0`)
  - `CORS_PREFLIGHT_TIMEOUT_SECS` (default: `15`)
  - `CORS_PREFLIGHT_CONNECT_TIMEOUT_SECS` (default: `5`)

## Remote smoke (optional)

If you run this from a machine that can reach the target API directly:

- Set `SMOKE_BASE_URL` to your public API origin (no trailing slash), e.g. `https://staging-api.example.tld`
- If you need a specific `Host` header or `--resolve`, use `SMOKE_HOST` / `SMOKE_RESOLVE`.
- For TLS debugging only, set `SMOKE_INSECURE=1`.

Example:

```bash
SMOKE_BASE_URL="https://staging-api.shamell.online" ./scripts/ops.sh pipg smoke-api
```

## Expected results

`smoke-api` performs a small set of requests:

- `GET /health` must succeed
- `GET /me/roles` without a session must return `401/403` and must not return `internal auth required`
- `GET /chat/messages/inbox?device_id=...` without a session must return `401/403` and must not return `internal auth required`
- `POST /internal/security/alerts` without `X-Internal-Secret` must not be accepted
  - acceptable statuses: `401` (internal-auth), `403/404` (edge blocked), `405` (method mismatch)

If any check fails, treat it as a deploy-blocker: it either breaks clients or weakens the internal/public boundary.
