# Hetzner Nginx (IaC)

This directory stores the canonical Nginx vhost configs for the Hetzner host
serving:

- `api.shamell.online`
- `staging-api.shamell.online`
- `online.shamell.online`
- `livekit.shamell.online`
- `media.shamell.online`
- `shamell.online`

## Why

This prevents configuration drift (for example, proxying to the wrong upstream
port and causing `502 Bad Gateway`).

## Apply

Use the helper script from the repository root:

```bash
scripts/sync_hetzner_nginx.sh
```

Validate hardening invariants locally (and in CI):

```bash
scripts/check_nginx_edge_hardening.sh
```

Optional host override (SSH host alias):

```bash
scripts/sync_hetzner_nginx.sh shamell
```

Optional docs/openapi allowlist override (office/VPN IPs/CIDRs):

```bash
DOCS_ALLOWLIST_IPS="83.137.6.187,203.0.113.0/24" scripts/sync_hetzner_nginx.sh shamell
```

Internal-auth snippet rendering (recommended):

```bash
# Source INTERNAL_API_SECRET from an env file (default: ops/pi/.env)
NGINX_SYNC_ENV_FILE=ops/pi/.env scripts/sync_hetzner_nginx.sh shamell

# Or pass it explicitly for one-off syncs (do not commit this):
NGINX_INTERNAL_API_SECRET="..." scripts/sync_hetzner_nginx.sh shamell
```

The script:

1. copies versioned files to `/etc/nginx/sites-available/`,
2. installs versioned snippets to `/etc/nginx/snippets/`,
3. refreshes symlinks in `/etc/nginx/sites-enabled/`,
4. runs `nginx -t`,
5. reloads Nginx,
6. verifies `https://api.shamell.online/health` locally on the host.

## Security notes

- Keep upstream targets pinned to `127.0.0.1:8080` for BFF traffic.
- Keep a dedicated `location ^~ /internal/ { return 404; }` block on public API
  vhosts so internal-only BFF routes are not Internet-reachable.
- Keep `/docs` and `/openapi.json` on `api.shamell.online` and
  `staging-api.shamell.online` restricted with
  `/etc/nginx/snippets/shamell_docs_allowlist.local.conf` + `deny all`.
- Manage docs allowlist entries via `DOCS_ALLOWLIST_IPS` when running
  `scripts/sync_hetzner_nginx.sh` (or edit the host-local snippet directly).
- Keep `shamell_bff_edge_hardening.conf` enabled on public BFF vhosts so
  `X-Internal-Secret`, `X-Internal-Service-Id`, `X-Auth-Roles`, `X-Roles`, and
  `X-Role-Auth` are never trusted from client traffic.
- Keep edge injection of `X-Shamell-Client-IP` enabled so BFF auth/rate-limit
  logic uses an edge-attested client IP instead of client-controlled proxy
  headers.
- Keep Nginx access logs configured to omit query strings (`shamell_noquery`)
  to avoid leaking secrets carried in URLs (e.g., QR payload tokens).
- Set a host-local `/etc/nginx/snippets/shamell_bff_internal_auth.local.conf`
  that injects trusted `X-Internal-Secret` matching BFF `INTERNAL_API_SECRET`.
  Keep this file root-owned (`0600`) and never commit the real secret.
- For admin/operator role routing, set a host-local
  `/etc/nginx/snippets/shamell_bff_role_attestation.local.conf` that injects a
  trusted `X-Role-Auth` matching `BFF_ROLE_HEADER_SECRET` (and role claims from
  your trusted auth edge). Do not commit that secret file to git.
- Do not loosen admin route allowlists without explicit approval.
- Keep TLS certificate paths managed by Certbot on-host.
- If using Cloudflare in front of the origin, keep the Real-IP snippet in sync
  so rate-limits and allowlists see the true client IP.
