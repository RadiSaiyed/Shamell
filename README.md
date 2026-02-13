# Shamell Platform

This repository hosts Shamell backend services, clients, and ops tooling.

## Layout
- apps/ - FastAPI services (BFF, chat, payments, bus)
- libs/ - Shared libraries (Python)
- clients/ - Flutter client
- tests/ - Python test suite (pytest)
- ops/ - deployment + environment tooling (Hetzner Nginx IaC, pi compose, livekit)
- docs/ - runbooks + security docs
- scripts/ - ops helpers (deploy checks, sync scripts, etc.)

## Runtime modes
- Microservices (default local dev): `./scripts/ops.sh dev up`
- Server (Hetzner/edge): `./scripts/ops.sh pi deploy` (uses `ops/pi/docker-compose.yml`)
- Server (Hetzner/edge, Postgres): `./scripts/ops.sh pipg deploy` (uses `ops/pi/docker-compose.postgres.yml`)

Useful commands:
- `./scripts/ops.sh dev health`
- `./scripts/ops.sh dev ps`
- `./scripts/ops.sh dev down`

`dev` builds the shared `shamell-core` image once and reuses it across BFF, chat, payments, and bus.

## Local dev
Use the Makefile:
```bash
make venv
make test
make iterate   # ITERATIONS=100 by default
```

## Operations helper
`scripts/ops.sh` supports `dev` and server environments (`pi`, `pipg`) with shared commands for health checks, deploy, migrations, backups, and reports.

## Workspace
The workspace root `.gitignore` mirrors common platform ignore patterns for shared tooling artifacts.
