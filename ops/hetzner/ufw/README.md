# Hetzner UFW (Origin Lockdown)

This directory documents the intended UFW policy for the Hetzner origin.

## Goal

- Only Cloudflare may reach the origin over `80/tcp` and `443/tcp`.
- SSH is only reachable over Tailscale (no public SSH).
- Everything else is denied by default.

This ensures:

- direct-to-origin traffic is blocked (bypassing Cloudflare WAF/rate-limit),
- origin IP leakage has lower impact,
- admin access does not depend on the public internet.

## Source of truth: Cloudflare CIDRs

We keep Cloudflare CIDRs in:

- `ops/hetzner/nginx/snippets/shamell_cloudflare_realip.conf`

That file is used for both:

- Nginx Real-IP restoration, and
- UFW allowlisting (via the sync script).

To refresh the CIDRs:

```bash
scripts/update_cloudflare_ip_ranges.sh
```

## Apply

Run from the repo root:

```bash
scripts/sync_hetzner_ufw.sh shamell
```

Notes:

- Run this while you are connected over Tailscale (client IP in `100.64.0.0/10`).
- The script is defensive: if it detects your SSH client is not on Tailscale,
  it will *skip* SSH rule changes to avoid locking you out.

## Verify (manual)

On the host:

- `sudo ufw status verbose`
- `curl -skfsS -H 'Host: api.shamell.online' https://127.0.0.1/health`

From outside (non-Cloudflare), the origin should not accept direct connections
to `80/tcp` or `443/tcp`.

## LiveKit Exception (RTC Ports)

LiveKit WebRTC media typically requires public reachability for:

- `7881/tcp`
- `7882/udp`

If you run LiveKit on the same origin, Cloudflare-only origin lockdown cannot
fully hide the origin IP from participants because ICE candidates will include
the origin address.

Best practice options:

- run LiveKit on a separate host/IP (recommended), or
- use a proxy that supports arbitrary TCP/UDP (e.g. Cloudflare Spectrum), or
- explicitly allow the RTC ports on the origin firewall (accept the IP exposure).

This repo keeps the default policy strict. If you intentionally want to open
LiveKit RTC ports, use:

```bash
scripts/sync_hetzner_ufw.sh shamell --allow-livekit
```

### LiveKit On Separate Host (DNS-Only)

If you run LiveKit on a dedicated host and you set `livekit.<domain>` to
**DNS-only** (required for UDP unless you have a Spectrum-like proxy), then the
Cloudflare-only allowlist for `80/443` will block real clients.

On the LiveKit host you typically want:

- `80/tcp` and `443/tcp` open to the public internet (ACME + WSS signaling)
- `7881/tcp` and `7882/udp` open to the public internet (WebRTC media)

Apply that policy with:

```bash
scripts/sync_hetzner_ufw.sh livekit-host-alias --direct-web --allow-livekit
```
