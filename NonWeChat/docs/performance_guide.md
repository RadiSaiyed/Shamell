# Shamell Superapp – Performance Guide

This document summarises the key performance goals and metrics for the Shamell
Superapp. It is aimed at people operating or evolving the system.

## 1. Targets & Budgets (Guidelines)

- **App start**
  - Cold start → first frame of home: ≤ 1.5s (mid‑range Android),
    ≤ 1.0s (iOS).
  - Login → home snapshot (from cache) visible: ≤ 0.8s.

- **Payments**
  - “Send” / “Scan & Pay”:
    - user feedback (button feedback, review sheet): ≤ 0.5s,
    - end‑to‑end transfer (server response): ≤ 1.5s.

- **Mobility**
  - Taxi rider:
    - route & fare estimate: ≤ 1.2s,
    - ride booking: ≤ 1.5s.
  - Bus booking:
    - trip search: ≤ 1.2s,
    - booking: ≤ 1.5s.

- **Stays / Food**
  - Stays:
    - quote: ≤ 1.2s,
    - booking: ≤ 1.5s.
  - Food:
    - order creation: ≤ 1.2s.

These are target values – in poor network conditions it can be slower, but
under normal conditions they should hold.

## 2. Perf Client (Flutter)

The Flutter client sends performance events to the BFF:

- `Perf.action(label)`  
  - sends an `"action"` event with `label` and optional `ms_since_start`.
- `Perf.sample(metric, value_ms)`  
  - sends a `"sample"` event with `metric` and `value_ms` (latency in ms).

Both also log via `dart:developer` to support local profiling tools.

### 2.1 Key Actions & Samples

Selected metrics already wired in:

- **Payments**
  - `pay_send_ok`, `pay_send_fail`, `pay_send_queued`
  - `pay_send_ms` (sample)

- **Taxi**
  - `taxi_quote_ok`, `taxi_quote_fail`, `taxi_quote_error`
  - `taxi_quote_ms` (sample)
  - `taxi_book_ok`, `taxi_book_fail`, `taxi_book_error`
  - `taxi_book_ms` (sample)
  - `taxi_status_ok`, `taxi_status_fail`, `taxi_status_error`
  - `taxi_status_ms` (sample)
  - `taxi_route_ok`, `taxi_route_fail`, `taxi_route_error`
  - `taxi_geocode_error`

- **Bus**
  - `bus_search_ok`, `bus_search_error`
  - `bus_search_ms` (sample)
  - `bus_book_ok`, `bus_book_fail`, `bus_book_error`
  - `bus_book_ms` (sample)

- **Stays**
  - `stays_quote_ok`, `stays_quote_fail`
  - `stays_quote_ms` (sample)
  - `stays_book_ok`, `stays_book_fail`
  - `stays_book_ms` (sample)

- **Food**
  - `food_order_ok`, `food_order_fail`, `food_order_queued`
  - `food_order_ms` (sample)

- **Snapshots / System**
  - `home_snapshot_ok/fail/error`
  - `wallet_snapshot_ok/fail/error`
  - `payments_overview_*`
  - `system_status_ok/fail/error`

These cover the critical money and mobility flows.

## 3. BFF Metrics & Admin View

The BFF accepts metrics at `/metrics` and keeps them in an in‑memory ring
buffer (`_METRICS`).

- `POST /metrics`  
  - payload: `{"type": "action"|"sample"|..., "data": {...}, "device": "...", "ts": "..."}`.

- `GET /metrics`  
  - returns the last N raw events as JSON.

### 3.1 `/admin/metrics` – HTML view (legacy)

Accessible only to admins (`_require_admin_v2`). In the monolith, this route
now simply shows a minimal page pointing to Shamell, but the underlying
JSON is still useful:

- **Samples (`value_ms`)**  
  - aggregated statistics per metric:
    - `metric`, `count`, `avg_ms`, `min_ms`, `max_ms`.

- **Action counts**  
  - counts per `label` (e.g. `taxi_book_ok`, `pay_send_fail`).

- **Raw events**  
  - last events (ts/type/label/ms/device), handy for debugging.

### 3.2 Typical Evaluation

- Use `pay_send_ms`, `taxi_book_ms`, `bus_book_ms`, `stays_book_ms`,
  `food_order_ms`:
  - check 95/99 percentiles vs. budgets from section 1.
- Combine with:
  - `/upstreams/health` (domain health),
  - `/admin/guardrails` (guardrail activity).

Slow metrics + frequent guardrail activity usually point to either upstream
issues or mis‑configured guardrail thresholds.
