# Shamell Monolith

Run all domains and the BFF in a single process.

This repository now treats the monolith as the **einzige** Backend‑Struktur:
- keine separaten Deployments mehr für Taxi/Bus/Payments/etc.
- alle Domains laufen als Module im Monolith‑Prozess.

## Quick start

1. Copy the sample env and adjust as needed:
   ```bash
   cp apps/monolith/.env.example .env
   ```
   This forces all domains into internal mode and uses a single SQLite DB at `/tmp/shamell-monolith.db`. Point `MONOLITH_DB_URL` to Postgres for production.

2. Start the monolith:
   ```bash
   python -m apps.monolith --reload
   # or
   uvicorn apps.monolith.app.main:app --reload
   ```

## Notes
- Internal modes (`*_INTERNAL_MODE=on`) ensure the BFF calls all domains in-process (keine externen `*_BASE_URL` nötig).
- `INTERNAL_API_SECRET` and `PAYMENTS_INTERNAL_SECRET` are shared so cross-domain calls succeed without extra config.
- The monolith startup best-effort initialises schemas for Payments, Stays, Bus, Taxi, Commerce, and Food. For Postgres, prefer proper migrations.

## Deployment

- Baue nur noch das Monolith‑Image (`apps/monolith/Dockerfile`).
- Frontends (Flutter/Web) sprechen immer gegen den Monolith‑BFF (z.B. `https://api.deine-domain.tld`).
- Alte Microservice‑Dockerfiles und Ops‑Scripts (Taxi/Bus/Payments/BFF als getrennte Services) wurden entfernt.
