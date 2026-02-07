# Shamell Monolith – Architecture & Deployment Overview

This document describes the current monolith variant of the Shamell Superapp:
a single FastAPI process that bundles the BFF and all domain services (Taxi,
Bus, Payments, Stays, Food, etc.) under one host.

## 1. Components

- **BFF (Backend‑for‑Frontend)** – `apps/bff/app/main.py`
  - Auth (OTP), session management, aggregation API for the Flutter clients.
  - Contains HTML admin UIs (Taxi admin, Payments debug, operator tools).
  - In the monolith it continues to live at `/`.

- **Domain services** (each a FastAPI app with routers, wired through the
  monolith):
  - Taxi – `apps/taxi/app/main.py` – `/taxi/*`
  - Bus – `apps/bus/app/main.py` – `/bus/*`
  - Payments – `apps/payments/app/main.py` – `/payments/*`
  - Stays – `apps/stays/app/main.py` – `/stays/*`
  - Food – `apps/food/app/main.py` – `/food/*`
  - Commerce – `apps/commerce/app/main.py` – `/commerce/*`
  - Carmarket – `apps/carmarket/app/main.py` – `/carmarket/*`
  - Carrental – `apps/carrental/app/main.py` – `/carrental/*`
  - RealEstate – `apps/realestate/app/main.py` – `/realestate/*`
  - Livestock – `apps/livestock/app/main.py` – `/livestock/*`
  - Agriculture – `apps/agriculture/app/main.py` – `/agriculture/*`
  - Freight – `apps/freight/app/main.py` – `/freight/*`
  - Doctors – `apps/doctors/app/main.py` – `/doctors/*`
  - Flights – `apps/flights/app/main.py` – `/flights/*`
  - Chat – `apps/chat/app/main.py` – `/chat/*`
  - Jobs – `apps/jobs/app/main.py` – `/jobs/*`
  - Agents – `apps/agents/app/main.py` – `/agents/*`
    (small health‑style service, mounted as sub‑app)

- **Shared library** – `libs/shamell_shared`
  - Shared middleware (RequestID, CORS, health).
  - Logging configuration (JSON logs).
  - Security / env helpers (e.g. rate limiting, HMAC, JWKS verify, OTP utils).

- **Monolith entry point** – `apps/monolith/app/main.py`
  - Creates the central FastAPI app `root_app` (title “Shamell Monolith”).
  - Mounts the BFF as a sub‑app at `/`.
  - Includes all domain API routers under their prefixes (e.g. `/taxi`,
    `/payments`).
  - Exposes a dedicated health endpoint: `GET /health`.

## 2. Runtime Structure

- **Top‑level app**: `apps.monolith.app.main:app`
  - `/` – BFF (unchanged routes, including `/auth/*`, HTML UIs).
  - `/<domain>` – domain APIs (e.g. `/taxi/rides/*`, `/payments/transfer`,
    `/bus/trips/*`).
  - `/health` – health for the entire monolith (`status`, `env`, `service`,
    `version`).

- **Domain health**:
  - Each domain service uses `add_standard_health(app)`.
  - Domain‑specific health: `GET /<domain>/health` (e.g. `/taxi/health`).

- **Middleware & logging**:
  - All services use `setup_json_logging()`, `RequestIDMiddleware`, and CORS
    via `configure_cors`.
  - Logs are JSON‑formatted and include request IDs for end‑to‑end tracing.

## 3. Monolith Docker Image

### Dockerfile

- Path: `apps/monolith/Dockerfile`
- Base: `python:3.11-slim`
- System packages:
  - `build-essential`, `gcc` – for C extensions (SQLAlchemy, psycopg2, etc.).
  - `fonts-dejavu-core` – for PDFs/Reportlab and QR rendering in the BFF.
- Python dependencies:
  - `apps/monolith/requirements.txt`
  - Contains unified versions of:
    - `fastapi`, `uvicorn[standard]`, `prometheus-client`
    - `SQLAlchemy`, `httpx`, `psycopg2-binary`, `alembic`
    - `Pillow`, `qrcode`, `reportlab`
- Shared library:
  - `libs/shamell_shared/python` is installed with
    `pip install /app/libs/shamell_shared/python`.
- App code:
  - `COPY apps /app/apps`
  - Includes BFF, all domain services and the monolith entry point.
- Start command:
  - `uvicorn apps.monolith.app.main:app --host 0.0.0.0 --port 8080`

## 3.1 Frontend Monolith (Superapp + Ops Admin)

The web frontend (Flutter web builds) runs as a separate Nginx monolith that
serves both the end‑user Superapp and the Ops‑Admin app.

### Structure

- Dockerfile: `apps/web/Dockerfile`
  - Base: `nginx:1.25-alpine`
  - Copies Flutter web builds:
    - `clients/shamell_flutter/build/web/` → `/usr/share/nginx/html/`
    - `clients/ops_admin_flutter/build/web/` → `/usr/share/nginx/html/ops-admin/`
  - Loads Nginx configuration from `apps/web/nginx.conf`.
  - Exposes port `8080`.

- Nginx config: `apps/web/nginx.conf`
  - Superapp (SPA) under `/`:

    ```nginx
    location / {
      try_files $uri $uri/ /index.html;
    }
    ```

  - Ops‑Admin (SPA) under `/ops-admin/`:

    ```nginx
    location /ops-admin/ {
      try_files $uri $uri/ /ops-admin/index.html;
    }
    ```

  - Shared asset rules (caching, gzip) for JS/CSS/images.

### Build & Run (Frontend Monolith)

Preparation (from repo root, Flutter installed):

```bash
cd clients/shamell_flutter
flutter build web --release

cd ../ops_admin_flutter
flutter build web --release
```

Then build and run:

```bash
docker build -f apps/web/Dockerfile -t shamell-frontend-monolith .
docker run --rm -p 8080:8080 shamell-frontend-monolith
```

- Superapp UI: `http://localhost:8080/`
- Ops‑Admin UI: `http://localhost:8080/ops-admin/`

### Backend Monolith Build & Run

Build:

```bash
docker build -f apps/monolith/Dockerfile -t shamell-monolith .
```

Run (example, ENV=prod):

```bash
docker run --rm -p 8080:8080 \
  -e ENV=prod \
  -e PAYMENTS_BASE_URL=http://localhost:8080/payments \
  -e TAXI_BASE_URL=http://localhost:8080/taxi \
  -e BUS_BASE_URL=http://localhost:8080/bus \
  -e REALESTATE_BASE_URL=http://localhost:8080/realestate \
  -e STAYS_BASE_URL=http://localhost:8080/stays \
  -e CARMARKET_BASE_URL=http://localhost:8080/carmarket \
  -e CARRENTAL_BASE_URL=http://localhost:8080/carrental \
  -e FREIGHT_BASE_URL=http://localhost:8080/freight \
  -e CHAT_BASE_URL=http://localhost:8080/chat \
  -e AGRICULTURE_BASE_URL=http://localhost:8080/agriculture \
  -e COMMERCE_BASE_URL=http://localhost:8080/commerce \
  -e DOCTORS_BASE_URL=http://localhost:8080/doctors \
  -e FLIGHTS_BASE_URL=http://localhost:8080/flights \
  -e JOBS_BASE_URL=http://localhost:8080/jobs \
  -e LIVESTOCK_BASE_URL=http://localhost:8080/livestock \
  shamell-monolith
```

The `*_BASE_URL` variables are primarily used by the BFF to correctly route
internal HTTP calls (proxies) to the domain services when they are not running
in‑process.

## 4. BFF ↔ Domains ↔ Clients

- **Clients (Flutter apps)**:
  - Only talk to the BFF (base URL points at the monolith, e.g.
    `https://api.shamell.example`).
  - BFF routes:
    - Auth/OTP (`/auth/request_code`, `/auth/verify`)
    - Feature‑specific endpoints (`/taxi/*`, `/payments/*`, `/bus/*`, …)
      – sometimes directly, sometimes as proxy.

- **BFF ↔ domain services**:
  - HTTP calls via `httpx` to `*_BASE_URL` + path (when internal mode for a
    domain is disabled).
  - When the monolith internal mode is enabled, the BFF calls domain Python
    functions directly in‑process rather than via HTTP.
  - Example (HTTP mode):
    - Taxi: `TAXI_BASE_URL=/taxi` → BFF calls
      `http://monolith/taxi/rides/request` via `httpx`.
    - Payments: `PAYMENTS_BASE_URL=/payments` → BFF calls
      `http://monolith/payments/transfer`.
  - Health aggregation: `GET /upstreams/health` in the BFF calls `/health`
    on each domain via the configured `*_BASE_URL` values.

- **Domains ↔ Payments**:
  - Some domains (Taxi, Bus, Stays, Food, Carrental, Freight, RealEstate)
    call the Payments service directly:
    - e.g. `PAYMENTS_BASE_URL=/payments`, endpoints `/transfer`, `/users`.
  - These internal HTTP calls also run within the monolith using `httpx` and
    the same `*_BASE_URL` conventions.

## 5. Environment Variables (Monolith‑Relevant)

- **General**:
  - `ENV` – environment (`dev`, `staging`, `prod`).
  - `ALLOWED_ORIGINS` – CORS origins (e.g. mobile/web clients).

- **BFF proxy targets**:
  - `PAYMENTS_BASE_URL`, `TAXI_BASE_URL`, `BUS_BASE_URL`,
    `REALESTATE_BASE_URL`, `STAYS_BASE_URL`, `CARMARKET_BASE_URL`,
    `CARRENTAL_BASE_URL`, `FREIGHT_BASE_URL`, `CHAT_BASE_URL`,
    `AGRICULTURE_BASE_URL`, `COMMERCE_BASE_URL`, `DOCTORS_BASE_URL`,
    `FLIGHTS_BASE_URL`, `JOBS_BASE_URL`, `LIVESTOCK_BASE_URL`.
  - Food is internal‑only in the monolith and does not use a `FOOD_BASE_URL`.
  - In pure internal‑mode deployments most of these can remain empty
    (see `*_INTERNAL_MODE` in the BFF).

For a deeper dive into internal vs. external modes, see
`docs/shamell_threat_model.md` and `docs/shamell_security_hardening.md`.
