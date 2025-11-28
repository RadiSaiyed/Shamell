# Shamell Contributor Guide – How to extend the app

This guide is for engineers who want to add new features or domains to
the Shamell monolith while keeping a high quality bar.

It assumes you are familiar with Python, FastAPI and Flutter.

---

## 1. High-Level Architecture (Recap)

- **Monolith backend**: `apps/monolith/app/main.py`
  - Mounts the BFF at `/` (`apps/bff/app/main.py`).
  - Includes all domain routers under prefixes (`/taxi`, `/bus`,
    `/payments`, `/stays`, `/food`, `/commerce`, etc.).

- **BFF**: `apps/bff/app/main.py`
  - Central API surface for all clients.
  - Talks to domain services either:
    - in-process (internal) via Python imports and sessions, or
    - via HTTP when `*_BASE_URL` is configured.
  - Handles auth, roles, snapshots, aggregates, guardrails, metrics.

- **Domains**: `apps/*/app/main.py`
  - Each domain exposes a FastAPI `APIRouter` and uses `shamell_shared`
    for logging, CORS and health.
  - Own DB engine and `get_session()` helpers.

- **Frontend**:
  - Flutter app: `clients/shamell_flutter`.
  - Ops-Admin Flutter: `clients/ops_admin_flutter`.
  - Web shell (Nginx): `apps/web`.

---

## 2. Adding or Extending a Domain (Backend)

### 2.1 Domain Router

For a new domain (or extending an existing one), follow the pattern in
e.g. `apps/stays/app/main.py` or `apps/food/app/main.py`:

- Create or extend `apps/<domain>/app/main.py`:
  - Use `shamell_shared`:
    - `setup_json_logging()`
    - `RequestIDMiddleware`
    - `configure_cors(app, ...)`
    - `add_standard_health(app)`
  - Create `router = APIRouter()` and move HTTP endpoints onto the
    router.
  - At the bottom: `app.include_router(router)`.

The monolith already includes domain routers; as long as your router is
exposed from `apps.<domain>.app.main`, it will be mounted.

### 2.2 Internalization in BFF

To make the BFF call the domain in-process instead of HTTP:

1. In `apps/bff/app/main.py`:
   - Add internal imports and flags similar to Bus/Food/Carrental:
     - `_DOMAIN_INTERNAL_AVAILABLE`
     - `_use_domain_internal()` reading `<DOMAIN>_INTERNAL_MODE`.
     - `_domain_internal_session()` using the domain engine and Session.
   - Import Pydantic models and handlers from
     `apps.<domain>.app.main`.

2. For each BFF endpoint that currently uses HTTP:
   - First, check `_use_domain_internal()`:
     - If `True`, build the domain request model, open a session, and
       call the in-process handler.
     - Else, keep the existing `httpx` call as fallback.

This pattern ensures:

- Monolith mode uses fast, in-process calls.
- Legacy/microservice deployments can still use HTTP via `*_BASE_URL`.

### 2.3 Tests for the Domain

Add tests in `tests/` following existing patterns:

- **Domain-level** (direct imports):
  - Use an isolated SQLite engine and call domain functions directly.
  - Assert invariants (e.g. balances, availability, idempotency).

- **BFF-level** (stubs):
  - Monkeypatch `_use_<domain>_internal()` to `True`.
  - Stub exported functions from the domain in `apps.bff.app.main`.
  - Exercise BFF endpoints and assert JSON contracts and invariants.

See:

- `tests/test_payments_transfer_domain.py`
- `tests/test_stays_quote_book_bff.py`
- `tests/test_bus_book_bff.py`
- `tests/test_food_orders_bff_and_domain.py`

---

## 3. Extending the Flutter Superapp

All core flows live under `clients/shamell_flutter/lib`:

- Entry point: `main.dart` (`SuperApp`, `HomePage`, `LoginPage`).
- Shared components: `core/ui_kit.dart`, `core/status_banner.dart`,
  `core/l10n.dart`.
- Feature modules:
  - Payments: `core/payments_*`.
  - Taxi: `core/taxi/*`.
  - Moblity history: `core/mobility_history.dart`.
  - Journey view: `core/journey_page.dart`.

### 3.1 UI building blocks

To keep the UX unified, use:

- `FormSection` for grouped content sections.
- `StandardListTile` for list rows.
- `StatusBanner` for info/success/warning/error messages.
- `PrimaryButton` for main actions on a screen.

Do **not** invent new card/button styles without a strong reason; the
goal is one coherent product.

### 3.2 Localization (EN/AR)

- All user-visible strings should come from `core/l10n.dart` (`L10n`).
- Add new getters for new texts, e.g.:

  ```dart
  String get foodTitle => isArabic ? 'الطعام' : 'Food';
  ```

- Use `L10n.of(context)` in widgets:

  ```dart
  final l = L10n.of(context);
  Text(l.foodTitle);
  ```

### 3.3 Wiring a new screen

1. Add a new page in `core/` (e.g. `core/my_feature_page.dart`).
2. Use the shared UI kit and `L10n`.
3. Make HTTP calls via the BFF, not directly to domain services.
4. Add a navigation entry:
   - Either via `HomeActions` and `home_routes.dart`, or directly in
     `HomePage._buildHomeRoute`.

---

## 4. Tests & Quality Gates

- **Backend**:
  - All tests live under `tests/`.
  - `ci.yml` runs `pytest` on every push/PR.
  - Use the existing patterns for:
    - BFF-level scenario tests,
    - Domain-level invariants tests,
    - Guardrail tests (e.g. taxi payout/cancel caps).

- **Frontend**:
  - `flutter analyze` should stay clean for new files.
  - If you add critical UI elements, consider simple widget tests
    (outside the scope of this guide, but keep it in mind).

---

## 5. Performance & Guardrails

When adding or changing flows:

- Emit performance events via `Perf.action` / `Perf.sample` where it
  matters (see `docs/performance_guide.md`).
- Check `/admin/metrics` to see how your changes behave in real usage.
- For money/mobility flows:
  - Consider rate limits and per-entity guardrails (similar to taxi
    payout/cancel).
  - Use `_audit` for security-relevant actions; avoid logging secrets.

---

## 6. Rollout & Environments

Before shipping:

- Ensure tests pass locally (`pytest`) and CI is green.
- Use staging environments to validate:
  - Health endpoints (`/health`, `/upstreams/health`).
  - Guardrails (`/admin/guardrails`).
  - Performance (`/admin/metrics`).

Only after that promote the Docker image/config to production via the
existing deploy workflows.

By following these patterns you keep Shamell consistent, secure and
fast – and help it live up to its goal as a high‑quality reference implementation.
