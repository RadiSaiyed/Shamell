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
scripts/check_cloudflare_realip_freshness.sh
```

Refresh Cloudflare trusted proxy ranges when the freshness guard fails:

```bash
scripts/update_cloudflare_ip_ranges.sh
```

`scripts/sync_hetzner_nginx.sh` now refuses to push a stale
`shamell_cloudflare_realip.conf`; refresh it first, then sync.

Generate and publish the mobile app-link artifacts before syncing production
Nginx:

```bash
scripts/generate_mobile_well_known.sh
scripts/sync_hetzner_nginx.sh
```

Android sideload distribution uses the same `shamell.online` static root. The
Nginx `conf.d` payload now ships a dedicated `.apk` MIME type so direct APK
downloads are served correctly from:

```text
https://shamell.online/downloads/android/
```

The same static site now also hosts the Flutter web console for `Shamell Control`
with SPA fallback routing at:

```text
https://shamell.online/control/
```

Typical release flow:

```bash
./scripts/build_android_release_apks.sh --output-dir .artifacts/android-apk-release
./scripts/sync_hetzner_nginx.sh shamell
./scripts/publish_android_apk_downloads.sh --source-dir .artifacts/android-apk-release --host shamell
```

Typical Shamell Control web flow:

```bash
./scripts/build_control_web_release.sh --output-dir .artifacts/control-web-release
./scripts/sync_hetzner_nginx.sh shamell
./scripts/publish_control_web_release.sh --source-dir .artifacts/control-web-release --host shamell
```

If the host requires a sudo password, export it once before syncing/publishing:

```bash
export REMOTE_SUDO_PASSWORD='...'
./scripts/sync_hetzner_nginx.sh shamell
./scripts/publish_android_apk_downloads.sh --source-dir .artifacts/android-apk-release --host shamell
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
  `X-Internal-Secret`, `X-Internal-Service-Id`, `X-Internal-Audience`,
  `X-Internal-Identity-*`, `X-Auth-Roles`, `X-Roles`, `X-Role-Auth`, and
  `X-Shamell-Client-IP-Attested` are never trusted from client traffic.
- Keep `X-Forwarded-For` forwarding enabled and set `BFF_TRUSTED_PROXY_CIDRS`
  so the BFF can derive the real client IP from trusted proxy hops; bespoke
  `X-Shamell-Client-IP*` headers should stay cleared.
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
- Keep `/var/www/shamell/.well-known/apple-app-site-association` and
  `/var/www/shamell/.well-known/assetlinks.json` in sync with the currently
  shipped iOS bundle ID/team ID and Android release signing fingerprint.
- Keep `/var/www/shamell/downloads/android/` limited to signed release APKs and
  the generated manifest/index bundle. Do not drop debug builds or unsigned
  artifacts there.
- Keep `/var/www/shamell/control/` limited to the generated Flutter web release
  bundle and versioned release snapshots under `/var/www/shamell/control/releases/`.
