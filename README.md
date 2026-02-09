# Shamell Platform

This repository hosts Shamell backend services, clients, and ops tooling.

## Layout
- apps/ - FastAPI services (BFF, chat, payments, monolith)
- libs/ - Shared libraries (Python)
- clients/ - Flutter client
- NonWeChat/ - legacy domain apps + tests (imported by the monolith when present)
- ops/ - deployment + environment tooling (Hetzner Nginx IaC, pi compose, livekit)
- docs/ - runbooks + security docs
- scripts/ - ops helpers (deploy checks, sync scripts, etc.)

## Runtime modes
- Microservices (default local dev): `./scripts/ops.sh dev up`
- Legacy monolith (fallback): `./scripts/ops.sh devmono up`
- Server (Hetzner/edge): `./scripts/ops.sh pi deploy` (uses `ops/pi/docker-compose.yml`)

Useful commands:
- `./scripts/ops.sh dev health`
- `./scripts/ops.sh dev ps`
- `./scripts/ops.sh dev down`
- `./scripts/ops.sh devmono health`

`dev` builds the shared `shamell-core` image once and reuses it across BFF, chat, and payments.

## Local dev
Use the Makefile:
```bash
make venv
make test
make iterate   # ITERATIONS=100 by default
```

## Operations helper
`scripts/ops.sh` supports `dev`, `devmono`, and `pi` with shared commands for health checks, deploy, migrations, backups, and reports.

## Workspace
The workspace root `.gitignore` mirrors common platform ignore patterns for shared tooling artifacts.
