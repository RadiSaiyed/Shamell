# Shamell Testing Strategy

This document summarizes how the Shamell monolith is tested today and which
invariants are considered critical for "bank‑level" stability.

## 1. Test Layers

We use three complementary layers:

- **BFF/API tests** (via `TestClient` on the monolith):
  - Exercise public HTTP routes exposed from `apps/bff/app/main.py`.
  - Stub internal services (Payments, Stays, Bus, etc.) when we want to test
    contracts and control flows without depending on real databases or external
    APIs.
- **Domain‑level tests** (direct imports):
  - Call domain functions like `apps.payments.app.main.transfer` or
    `apps.stays.app.main.book` directly with an isolated SQLite engine.
  - Verify invariants such as balances, fees, availability and idempotency at
    the core business logic layer.
- **Unit‑like helpers**:
  - Small tests that verify pure helpers or filter functions in the BFF (e.g.
    `/me/taxi_history` filtering).

All tests run against the monolith codebase without requiring external
infrastructure.

## 2. Payments

### 2.1 BFF‑Level

- `tests/test_payments_e2e_bff.py`
  - Uses an in‑memory stub for Payments inside `apps.bff.app.main`:
    - Overrides `_use_pay_internal()`, `_pay_create_user`, `_pay_get_wallet`,
      `_pay_transfer` and `_pay_list_txns`.
    - Maintains a simple `state["wallets"]` and `state["txns"]`.
  - Scenario:
    - Create two users via `POST /payments/users`.
    - Top up wallet A from a synthetic `sys` wallet via
      `POST /payments/transfer`.
    - Transfer from A to B via `POST /payments/transfer`.
    - Verify balances via `GET /wallets/{wallet_id}/snapshot`:
      - A balance: `topup_amount - transfer_amount`.
      - B balance: `transfer_amount`.

### 2.2 Domain‑Level

- `tests/test_payments_transfer_domain.py`
  - Uses its own in‑memory SQLite engine; calls `pay.transfer()` directly.
  - Invariants:
    - Sender is debited by the full `amount_cents`.
    - Receiver is credited by `amount_cents - fee_cents` where
      `fee_cents = amount * MERCHANT_FEE_BPS / 10_000`.
    - Exactly one `Txn` is written with `kind="transfer"`.
    - Idempotency:
      - Two calls with the same `Idempotency-Key` yield only one `Txn`.
      - Balances are updated only once.

- `tests/test_payments_topup_domain.py`
  - Tests `pay.topup()` directly.
  - Invariants:
    - Wallet balance increases by `amount_cents`.
    - Exactly one `Txn` with `kind="topup"` is written.
    - Two `LedgerEntry` rows are created: one credit for the wallet, one debit
      for an external wallet (`wallet_id=None`).
    - Idempotency:
      - Two calls with identical `Idempotency-Key` produce only one `Txn` and
        a single balance increase.

## 3. Stays

### 3.1 BFF‑Level (Quote & Book)

- `tests/test_stays_quote_book_bff.py`
  - Stubs internal Stays calls in the BFF:
    - `_use_stays_internal()` → `True`, `_STAYS_INTERNAL_AVAILABLE` → `True`.
    - `_stays_internal_session()` → dummy context.
    - `_StaysQuoteReq`, `_StaysBookReq`, `_stays_quote`, `_stays_book`,
      `_stays_get_booking` → in‑memory implementations.
  - Business rules in the stub:
    - Fixed price per night: `10_000` SYP.
    - `quote` and `book` both compute:
      - `nights = to_iso - from_iso`.
      - `amount_cents = nights * 10_000`.
    - `book`:
      - `status = "confirmed"` when `confirm=True`.
      - `status = "requested"` otherwise.
      - Idempotency: `Idempotency-Key` maps to a single booking instance.
  - Tests:
    - Quote & Book:
      - `POST /stays/quote` and `POST /stays/book` must agree on `nights` and
        `amount_cents`.
      - `GET /stays/bookings/{id}` must return the same booking.
    - Idempotency:
      - Two `POST /stays/book` calls with the same key must return the same
        booking (`id`, `nights`, `amount_cents`, `status`).

### 3.2 Domain‑Level

- `tests/test_stays_book_domain.py`
  - Uses own in‑memory engine; calls `stays.quote()` and `stays.book()`:
  - Invariants:
    - `quote`:
      - Computes `nights` and `amount_cents` based on `price_per_night_cents`
        and date range.
    - `book`:
      - Overlapping bookings for the same listing and overlapping dates
        result in `HTTPException(409, "not available")`.

## 4. Bus

### 4.1 BFF‑Level

- `tests/test_bus_book_bff.py`
  - Stubs the Bus domain inside BFF:
    - `_use_bus_internal()` → `True`, `_BUS_INTERNAL_AVAILABLE` → `True`.
    - `_bus_internal_session()` → dummy context.
    - `_bus_search_trips`, `_bus_trip_detail`, `_BusBookReq`, `_bus_book_trip`,
      `_bus_booking_status` → in‑memory.
  - Business rules in the stub:
    - Single trip with known price and capacity.
    - `search_trips` returns that trip.
    - `book_trip`:
      - `status = "confirmed"` when `wallet_id` is provided.
      - `status = "pending"` when `wallet_id` is `None`.
      - Idempotency: same `Idempotency-Key` → same booking.
  - Tests:
    - Search & Book:
      - `GET /bus/trips/search` returns one trip.
      - `POST /bus/trips/{id}/book` creates a booking with expected `seats`
        and status.
      - `GET /bus/bookings/{id}` returns that booking.
    - Idempotency:
      - Two `POST /bus/trips/{id}/book` calls with the same key return the
        same `id`/`seats`/`status`.

### 4.2 Domain‑Level

- `tests/test_bus_book_domain.py`
  - Own in‑memory engine; uses `bus.book_trip()` directly.
  - Invariants:
    - Seats:
      - Booking with `seats=3` against a trip with `seats_total=12` reduces
        `seats_available` to `9`.
      - The created `Booking` row reflects `seats=3`, `status="pending"`.
    - Idempotency:
      - Two calls to `book_trip()` with the same `Idempotency-Key` and body
        create a single booking row.
      - `seats_available` is reduced only once (`12` → `10` for `seats=2`).

## 5. Mobility History & Wallet Snapshots

- `tests/test_taxi_history.py`, `tests/test_bus_history.py`,
  `tests/test_mobility_history.py`:
  - Ensure `/me/taxi_history`, `/me/bus_history`, `/me/mobility_history`
    filter correctly by the authenticated phone and optional status.
  - This guarantees that BFF history endpoints never leak rides/bookings from
    other users.
- `tests/test_wallet_snapshot.py`, `tests/test_payments_txns_filters.py`:
  - Verify that `/wallets/{wallet_id}/snapshot` and the internal helper
    `payments_txns()`:
    - Honor direction (`in`/`out`), kind (`transfer`/`topup`/`cash`/`sonic`)
      and date filters.
    - Return a consistent shape used by the Flutter clients.

## 6. Access Control & Security

- `tests/test_admin_permissions.py`, `tests/test_operator_endpoints.py`:
  - Cover Superadmin/Admin/Operator role checks on critical endpoints:
    - Admin roles, risk endpoints, voucher void, taxi/bus/stays operator
      endpoints.
  - Use the `_get_effective_roles()` helper and env‑based role injection.
- `tests/test_security_headers.py`, `tests/test_maintenance_mode.py`:
  - Verify global security headers and maintenance mode behavior at BFF level.

## 7. Philosophy

The overarching testing philosophy is:

- Test **flows** at the BFF layer, using stubs where necessary, to ensure HTTP
  contracts remain stable for all clients.
- Test **invariants** at the domain layer (Payments, Stays, Bus) using isolated
  SQLite engines, so we can change infrastructure without changing behavior.
- Keep external dependencies (real DB servers, external HTTP APIs) out of CI
  and rely instead on well‑scoped, deterministic tests.

This combination is what enables Shamell to behave with bank‑grade stability while still being fast and easy to run
locally.

## 8. End‑to‑End Scenarios (Golden Flows)

In addition to domain and BFF tests there are lightweight
end‑to‑end scenarios that cover key user journeys:

- `tests/test_e2e_scenarios.py::test_e2e_login_first_payment_and_history`
  - Simulates a real OTP login via `/auth/request_code` and `/auth/verify`.
  - Creates two wallets via `/payments/users` (sender/receiver),
    tops up the sender wallet from a synthetic system wallet and
    performs a first transfer.
  - Verifies balances and transaction history via
    `/wallets/{wallet_id}/snapshot`.

- `tests/test_e2e_scenarios.py::test_e2e_login_and_mobility_history`
  - Also performs the OTP login.
  - Stubs Taxi and Bus backends in the BFF so that there is exactly one
    `completed` ride/booking for the logged‑in phone number.
  - Calls `/me/mobility_history` and verifies that exactly those entries
    are returned for the user.

These tests are intentionally API‑based and lightweight so they run
quickly in CI. For full app tests (including the Flutter UI) they can
later be complemented with instrumentation tests on real devices.
