# Shamell CI/CD Pipeline Overview

This document describes a pragmatic CI/CD setup for the Shamell
monolith, building on the existing deploy workflows in `.github/workflows`.

The goals:

- Enforce automated tests and basic quality gates on every push/PR.
- Keep Docker images for the monolith backend and web frontend building.
- Reuse the existing deploy workflows for services and mobile apps.

---

## 1. Continuous Integration (CI)

CI is implemented via `.github/workflows/ci.yml`.

### 1.1 Python tests (backend + BFF)

Job: `python-tests`

- Runs on `ubuntu-latest`.
- Steps:
  - Checkout repository.
  - Set up Python 3.11.
  - Install backend dependencies:
    - `pip install -r apps/monolith/requirements.txt`
    - `pip install ./libs/shamell_shared/python`
    - `pip install pytest`
  - Run `pytest -q` with:
    - `ENV=test`
    - `MONOLITH_MODE=1`

This picks up the full test suite in `tests/`, which:

- Instantiates the monolith app from `apps.monolith.app.main`.
- Exercises BFF endpoints (auth, roles, payments, taxi, bus, stays,
  food, carrental, mobility history, guardrails, metrics).

### 1.2 Docker builds (backend + web)

Job: `docker-build`

- Depends on `python-tests` (runs only if tests succeed).
- Steps:
  - Checkout repository.
  - Build backend monolith image:
    - `docker build -t shamell-monolith apps/monolith`
  - Build web frontend image:
    - `docker build -t shamell-web apps/web`

This ensures that any changes to backend or web code keep the Docker
builds healthy.

---

## 2. Continuous Delivery (CD)

Aktuell gibt es drei zentrale Deploy‑Workflows in `.github/workflows`:

- `ci.yml` – Tests + Docker‑Builds für **Monolith** und **Web‑Frontend**.
- `flutter-android-beta.yml`, `flutter-ios-beta.yml` – mobile Beta‑Builds.

Ein dedizierter Deploy‑Workflow für den Monolith (z.B. nach Cloud Run,
Kubernetes oder VM) hängt von deiner Infrastruktur ab und ist nicht im Repo
vorgegeben. Übliche Variante:

- nutze das in CI gebaute Image `shamell-monolith` und deploye es mit deinem
  bestehenden Infra‑Stack (Helm, Terraform, Cloud Run, etc.).

### 2.1 Mobile deploy

- `flutter-android-beta.yml`:
  - Builds Android `appbundle` via `flutter build appbundle --release`.
  - Uses Fastlane to upload to Play Internal track when credentials are
    configured.
- `flutter-ios-beta.yml`:
  - Builds iOS release and, with Fastlane configuration, can ship to
    TestFlight.

---

## 3. Recommended Rollout Strategy

While the exact rollout depends on your infrastructure and risk appetite,
the following pattern is recommended:

- **Staging environment**
  - Separate Cloud Run / Kubernetes service für den **Monolith**
    (z.B. `shamell-monolith-staging`) mit eigener Datenbank‑Instanz
    und Config.
  - Mirror of production CI, but with different env vars (e.g. lower
    `AUTH_MAX_PER_PHONE`, dummy payment endpoints).

- **Canary in Production**
  - Für den Monolith bevorzugt neue Revisionen / Deployments, die
    zunächst nur einen kleinen Teil des Traffics bekommen.
  - Use `/health`, `/upstreams/health`, `/admin/metrics` and
    `/admin/guardrails` to monitor canary behavior before full rollout.

- **Mobile**
  - Use Internal / Alpha / Beta tracks in Play Store and TestFlight
    before promoting builds to production.
  - Keep the app resilient to partial backend rollout (feature flags,
    tolerant error handling).

---

## 4. How to Extend

When adding a new domain or major feature:

1. Add tests in `tests/` that assert invariants and guardrails.
2. Ensure tests pass under `pytest` locally.
3. CI will automatically enforce tests on every push/PR.
4. For mobile/UI changes:
   - Rely on `flutter-*-beta.yml` workflows for building and shipping
     to testers.

This keeps Shamell’s CI/CD pipeline simple, repeatable, and aligned with
the goal of being an accessible reference implementation.
