# Shamell Load Test Plan (Monolith)

This document outlines how to set up load tests for the Shamell monolith API
to exercise the most important money and mobility flows under realistic
conditions.

The scenarios build on existing E2E tests and perf metrics and are meant as an
addition to normal CI.

## 1. Goals

- Verify that the monolith under typical and elevated load:
  - serves login and payments flows within acceptable latency,
  - keeps mobility flows (Taxi/Bus) stable,
  - does not unintentionally trigger guardrails or rate limits.
- Identify bottlenecks:
  - database hot spots,
  - BFF hot spots (slow aggregation endpoints, etc.).

## 2. Tooling (Recommendations)

The code deliberately does not depend on a specific load tool. Two solid
options:

- **k6** – lightweight, JS‑based, very good for HTTP load tests.
- **Locust** – Python‑based, flexible, can share Python test logic.

For many teams k6 is the easiest starting point because it is simple to
install and integrates well with CI/CD.

## 3. Scenarios

### 3.1 Login storm (OTP + verify)

Goal:

- Exercise many parallel logins to:
  - validate rate limits (`AUTH_MAX_PER_PHONE`, `AUTH_MAX_PER_IP`),
  - observe OTP path and sessions under load.

Approach (k6 sketch):

- `POST /auth/request_code` with many different phone numbers
  (e.g. 100–500 distinct numbers).
- `POST /auth/verify` with matching codes (in tests you can use the code
  from the JSON body).
- Abort / alert when:
  - more than ~1% 5xx over a few minutes,
  - repeated 429 rate limits with realistic user behaviour.

### 3.2 Payments send under load

Goal:

- Exercise `POST /payments/transfer` with many concurrent clients:
  - consistency is enforced by the domain logic and tests,
  - here the focus is on latency and stability.

Approach:

- Setup:
  - pre‑create `N` wallets via `/payments/users`,
  - e.g. wallets `w_100...w_199`.
- Test:
  - several VUs (virtual users) that:
    - pick random sender/receiver wallets,
    - transfer small amounts (100–500 SYP),
    - optionally use `Idempotency-Key` to test retry behaviour.
  - Use latency SLOs from `performance_guide.md`:
    - 95% `pay_send_ms < 800 ms`, 99% `< 1500 ms`.

### 3.3 Mobility flows (Taxi/Bus)

Goal:

- Exercise a mix of:
  - `GET /me/mobility_history`
  - `GET /me/taxi_history`
  - `GET /me/bus_history`
  - optionally direct domain endpoints (`/taxi/*`, `/bus/*`) in a separate test.

Approach:

- Use prepared test accounts (phones with existing rides/bookings).
- In parallel:
  - 20–50 VUs call the history endpoints every 5–10 seconds.
  - Additional VUs create new bookings (Taxi/Bus), if domain APIs are ready.
- Observe:
  - `taxi_*_ms` and `bus_*_ms` samples via `/admin/metrics`,
  - guardrails via `/admin/guardrails` (they should not fire in
    realistic load tests).

## 4. Integration with Existing E2E Tests

Existing E2E tests (`tests/test_e2e_scenarios.py`) are deliberately lightweight
and run as part of normal CI. Load tests should:

- Run in a separate job/workflow (e.g. `loadtest.yml`) that:
  - targets a staging environment or a dedicated monolith instance,
  - is clearly separated from regular CI (different triggers: nightly/manual).
- Use the E2E tests as the “definition of done” for flows:
  - Code changes → unit / domain / BFF / E2E tests first.
  - Load tests are run periodically or before large rollouts.

## 5. Example: k6 Sketch (Payments Flow)

A minimal k6 script for the payments flow could look like:

```js
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 50,
  duration: '5m',
};

const BASE_URL = __ENV.BASE_URL || 'https://monolith.example.com';

export default function () {
  const from = 'w_100';
  const to = 'w_101';
  const payload = JSON.stringify({
    from_wallet_id: from,
    to_wallet_id: to,
    amount_cents: 10000,
  });
  const res = http.post(`${BASE_URL}/payments/transfer`, payload, {
    headers: { 'Content-Type': 'application/json' },
  });
  check(res, {
    'status is 200': (r) => r.status === 200,
  });
  sleep(1);
}
```

You can extend this script with:

- randomised wallets and amounts,
- idempotency keys,
- tags/thresholds for SLOs (95/99 percentiles).

