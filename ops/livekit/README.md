# LiveKit (Dedicated Host)

This directory contains a minimal, hardened LiveKit deployment intended to run
on a **separate host** from the Shamell API.

## Why A Separate Host

LiveKit uses WebRTC media ports (UDP) which are typically not compatible with
standard HTTP reverse proxies. Even if you proxy `443/tcp`, the RTC ports still
expose the host IP to participants via ICE candidates.

Keeping LiveKit on its own host reduces blast radius if it is DDoS'd or
misconfigured.

## DNS

For `livekit.shamell.online`:

- set the DNS record to **DNS-only** (not Cloudflare proxied) unless you use a
  Spectrum-like TCP/UDP proxy.

## Firewall (UFW)

On the LiveKit host, you generally need:

- `80/tcp` and `443/tcp` open to the internet (ACME + WSS signaling)
- `7881/tcp` and `7882/udp` open to the internet (WebRTC media)
- SSH only over Tailscale (recommended)

If you use the repo sync script:

```bash
scripts/sync_hetzner_ufw.sh <livekit-host-alias> --direct-web --allow-livekit
```

## Nginx TLS Termination

Use the vhost template:

- `ops/hetzner/nginx/sites-available/livekit.shamell.online`

It proxies `https://livekit.shamell.online` to `http://127.0.0.1:7880`.

## Run LiveKit

1. Create an env file on the LiveKit host:
   - start from `ops/livekit/env.example`
2. Start the service:

```bash
docker compose --env-file ops/livekit/.env -f ops/livekit/docker-compose.yml up -d
```

## BFF Configuration (Token Minting)

On the Shamell API/BFF host, configure:

- `LIVEKIT_PUBLIC_URL=wss://livekit.shamell.online`
- `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` (same values as LiveKit)
- `LIVEKIT_TOKEN_ENDPOINT_ENABLED=true`
- `CALLING_ENABLED=true` (to enable `/calls/*` and call-scoped token minting)

