# Shamell Operations Runbook

This document describes how to watch the Shamell monolith in production and
what to do when SLO or guardrail alerts fire.

## 1. Watchdog Sidecar

The script `tools/monolith_watchdog.py` is a small, dependency–free watcher
that polls the monolith and checks basic SLOs.

It reads:

- `MONOLITH_BASE_URL` – base URL of the monolith (e.g. `https://api.example.com`)
- SLO thresholds (all in milliseconds, with safe defaults):
  - `WATCHDOG_PAY_SEND_MS` (default `1500`)
  - `WATCHDOG_TAXI_BOOK_MS` (default `2000`)
  - `WATCHDOG_BUS_BOOK_MS` (default `2000`)
  - `WATCHDOG_STAYS_BOOK_MS` (default `2500`)
  - `WATCHDOG_FOOD_ORDER_MS` (default `2000`)
- Optional Gotify integration:
  - `WATCHDOG_GOTIFY_URL` – e.g. `https://gotify.example.com/message`
  - `WATCHDOG_GOTIFY_TOKEN` – API token for Gotify

### What it checks

- `/metrics` (JSON):
  - Aggregates recent `sample` events:
    - `pay_send_ms`, `taxi_book_ms`, `bus_book_ms`, `stays_book_ms`, `food_order_ms`.
  - If the average value of any of these exceeds its threshold, the watcher
    emits an alert (stderr + optional Gotify).

- `/admin/guardrails` (HTML):
  - If the page does **not** contain `No guardrail events yet.`, the watcher
    assumes that there is recent guardrail activity (e.g. taxi payout / cancel
    caps hit) and includes a note in the alert.

### Example: Kubernetes CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: shamell-watchdog
spec:
  schedule: "*/5 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: watchdog
              image: gcr.io/my-project/shamell-monolith:latest
              command: ["python", "-m", "tools.monolith_watchdog"]
              env:
                - name: MONOLITH_BASE_URL
                  value: "https://api.example.com"
                - name: WATCHDOG_GOTIFY_URL
                  valueFrom:
                    secretKeyRef:
                      name: shamell-secrets
                      key: watchdog_gotify_url
                - name: WATCHDOG_GOTIFY_TOKEN
                  valueFrom:
                    secretKeyRef:
                      name: shamell-secrets
                      key: watchdog_gotify_token
```

## 2. When Alerts Fire – What To Do

### 2.1 Latency SLO breach (pay_send_ms, taxi_book_ms, …)

1. Check `/admin/metrics` for detailed histograms:
   - Look at the affected metric and confirm if high values are sustained.
2. Correlate with upstream health:
   - Visit `/upstreams/health` or `/admin/overview` to see if Payments, Taxi,
     Bus, Stays or Food upstreams are degraded.
3. Immediate mitigations:
   - If an upstream is down, consider:
     - Switching the relevant `*_INTERNAL_MODE` to `on` and clearing
       `*_BASE_URL` (to rely on in–process calls where possible).
     - Temporarily lowering rate limits or disabling non‑critical features.
   - If only one flow is slow (e.g. `food_order_ms`):
     - Enable more logging around that flow in a staging or debug build.

### 2.2 Guardrail activity

1. Open `/admin/guardrails`:
   - Identify which actions are firing (`taxi_payout_guardrail`,
     `taxi_cancel_guardrail`, …) and for which drivers / rides.
2. Check the corresponding driver and rides in operator tools.
3. Immediate mitigations:
   - If abuse is suspected:
     - Block the driver account at the domain level (e.g. Taxi service).
     - Increase `TAXI_PAYOUT_MAX_PER_DRIVER_DAY` / `TAXI_CANCEL_MAX_PER_DRIVER_DAY`
       only after careful review.
   - If guardrails are too tight for normal usage:
     - Adjust the env vars with a staged rollout (staging → canary → prod).

### 2.3 Watchdog errors

- If the watcher reports errors fetching `/metrics` or `/admin/guardrails`:
  - Verify that the monolith is reachable (check `/health`).
  - Check network / auth configuration for the watcher pod (e.g. firewall,
    IAP, service mesh).

This runbook should evolve as SLOs and guardrails become richer; treat it as
the operational “cheat sheet” for Shamell.

