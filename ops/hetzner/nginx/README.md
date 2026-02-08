# Hetzner Nginx (IaC)

This directory stores the canonical Nginx vhost configs for the Hetzner host
serving:

- `api.shamell.online`
- `online.shamell.online`
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

Optional host override (SSH host alias):

```bash
scripts/sync_hetzner_nginx.sh shamell
```

The script:

1. copies versioned files to `/etc/nginx/sites-available/`,
2. refreshes symlinks in `/etc/nginx/sites-enabled/`,
3. runs `nginx -t`,
4. reloads Nginx,
5. verifies `https://api.shamell.online/health` locally on the host.

## Security notes

- Keep upstream targets pinned to `127.0.0.1:8080` for monolith traffic.
- Do not loosen admin route allowlists without explicit approval.
- Keep TLS certificate paths managed by Certbot on-host.
