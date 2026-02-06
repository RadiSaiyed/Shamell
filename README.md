# Shamell Platform

This repository hosts Shamell backend services, clients, mini-programs, and ops tooling.

## Layout
- src/ - Python packages (shamell_bff, shamell_chat, shamell_payments, shamell_monolith, shamell_shared)
- clients/ - Flutter clients
- mini-programs/ - Mini-program assets and runtime bundles
- ops/ - Deployment and environment tooling
- docs/ - Architecture and runbooks
- configs/ - Example environment configs

## Runtime modes
- Microservices (default local dev): `./scripts/ops.sh dev up`
- Legacy monolith (fallback): `./scripts/ops.sh devmono up`

Useful commands:
- `./scripts/ops.sh dev health`
- `./scripts/ops.sh dev ps`
- `./scripts/ops.sh dev down`
- `./scripts/ops.sh devmono health`

## Local dev dependencies
From `platform/shamell-app`:
```
pip install -r requirements.txt
pip install -e ../../packages/shamell-shared
pip install -e .
```
Or use the Makefile:
```
make venv
make run
```

## Operations helper
`scripts/ops.sh` supports `dev`, `devmono`, `prod`, and `pi` with shared commands for deploy, health checks, migrations, backups, and reports.

## Workspace
The workspace root `.gitignore` mirrors common platform ignore patterns for shared tooling artifacts.
