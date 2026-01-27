# Shamell Threat Model (Monolith)

This document captures the high–level security and privacy model for the
Shamell monolith, with a focus on the BFF and money–adjacent domains
(`payments`, `taxi`, `bus`, `stays`, `food`, `carrental`, `realestate`).

It is intentionally concise and opinionated; it is not a formal STRIDE/
LINDDUN analysis, but a pragmatic map for engineers and reviewers.

---

## 1. Trust Boundaries

- **External clients**
  - Superapp Flutter (mobile/web), Ops–Admin Flutter, and browser users
    talking to the BFF.
  - They are untrusted; all input is validated and authorisation is
    enforced at the BFF.

- **BFF (apps/bff/app/main.py)**
  - Central API surface; enforces auth, roles, rate limits and most
    business–level invariants.
  - Calls domain services either in–process (internal mode) or via HTTP
    when `*_BASE_URL` is configured.

- **Domain services (apps/*/app/main.py)**
  - Own their databases and core logic (payments ledger, taxi rides,
    stays listings, etc.).
  - When running inside the monolith, they share process space with the
    BFF but still have clear API contracts.

- **External dependencies**
  - Map services, SMS/Push, Gotify, etc. are untrusted networks and are
    treated as unreliable and potentially hostile.

---

## 2. Roles & Secrets

### Roles

Roles are resolved in the BFF (via Payments roles + env overrides) and
used for access control:

- **End user**
  - Any authenticated phone without special roles.
  - Allowed to use normal consumer flows (payments, taxi rider, bus
    booking, stays booking, food orders, etc.).

- **Operator (`operator_<domain>`)**
  - E.g. `operator_taxi`, `operator_bus`, `operator_stays`,
    `operator_food`, `operator_commerce`, `operator_carrental`,
    `operator_realestate`, `operator_agriculture`, `operator_livestock`.
  - Allowed to perform domain mutations (create listings, manage
    bookings, operator dashboards).

- **Admin (`admin`)**
  - Elevated access for administrative pages and exports.
  - Protected by `_require_admin_v2`.

- **Superadmin (`superadmin`/`ops`/`seller`)**
  - Full power, including:
    - Role management (`/admin/roles`).
    - Risk management, deny lists.
    - Voucher void and other high–impact mutations.
  - Protected by `_require_superadmin`.

### Secrets

- `INTERNAL_API_SECRET` / `PAYMENTS_INTERNAL_SECRET`
  - Used to authenticate internal HTTP calls between BFF and payments
    when not in internal mode.

- `ESCROW_WALLET_ID`
  - Wallet used for taxi escrow settlement (rider → escrow → driver).
  - Only the BFF knows this ID; it is never returned to clients.

- OTP/login codes
  - Stored in–memory (`_LOGIN_CODES`) as `(code, expires_at)`.
  - Never written to disk or DB.
  - `_check_code` deletes codes immediately upon successful use.
  - `AUTH_EXPOSE_CODES=false` disables returning the code in responses
    outside dev/test.

**Design principle:** secrets and OTPs must never be logged or echoed to
operators; only “who did what” and high–level outcomes belong in logs.

---

## 3. Threats & Mitigations

### 3.1 Abuse of OTP / Login

**Threats**

- Brute forcing OTP codes for a phone.
- Mass request of OTP codes to the same phone or many phones (SMS/WhatsApp
  spam).
- Leaking OTPs via logs or debug responses.

**Mitigations**

- Rate limiting in BFF:
  - `_rate_limit_auth` enforces:
    - Per–phone request caps (`AUTH_MAX_PER_PHONE` per window).
    - Per–IP caps (`AUTH_MAX_PER_IP` per window).
  - Applies to both `/auth/request_code` and `/auth/verify`.
- One–time use codes:
  - `_check_code` deletes codes after successful verification.
- Code exposure control:
  - `AUTH_EXPOSE_CODES` (default `true` for dev/test) controls whether
    the OTP appears in the HTTP response.
  - In production this should be `false` so codes only travel via the
    out–of–band channel (SMS, push, etc.).
- Logging:
  - OTP codes are never written to logs; the code path does not call
    `_audit` or any logger with the code string.

### 3.2 Privilege Escalation via Roles

**Threats**

- Users escalating themselves to `admin` or `superadmin`.
- Misconfigured env–based overrides giving too much power.

**Mitigations**

- Roles are derived from:
  - Payments roles (`roles_list`) and
  - Env–based overrides (`BFF_ADMINS`, `BFF_TOPUP_SELLERS`).
- High–impact endpoints always use the strongest guard:
  - `_require_superadmin` for role mutation, risk, voucher void.
  - `_require_admin_v2` for exports and admin overviews.
  - `_require_operator(request, domain)` for operator flows.
- `/me/roles` and `/me/home_snapshot` are the canonical, test–covered
  way to see effective roles from the client.

### 3.3 Abuse of Money + Mobility Flows

**Threats**

- Automated abuse of taxi payouts (e.g. compromised driver device
  triggering many completes).
- Excessive taxi cancellation fees charged to riders.
- Replay or double–spend of booking and payment requests.

**Mitigations**

- Idempotency:
  - Payments, Stays, Bus, Food, Carrental use explicit `Idempotency-Key`
    headers for transfer/book flows.
  - BFF passes these keys through to the domain or payments so repeated
    requests with the same key do not duplicate effects.

- Taxi escrow settlement:
  - After a ride completes:
    - BFF moves funds `rider_wallet -> ESCROW_WALLET_ID` and then
      `ESCROW_WALLET_ID -> driver_wallet`.
    - Each leg uses a deterministic `Idempotency-Key` based on ride id
      and amount to prevent double–charges even on retries.
  - **Guardrail:** per–driver payout cap per rolling day:
    - Env: `TAXI_PAYOUT_MAX_PER_DRIVER_DAY` (default 50).
    - BFF keeps `_TAXI_PAYOUT_EVENTS[driver_id]` with timestamps.
    - When the cap is reached, settlement is skipped and an audit event
      `taxi_payout_guardrail` is emitted.
    - Ride completion response is not affected (best–effort semantics).

- Taxi cancellation fee:
  - BFF charges a fixed fee (e.g. `TAXI_CANCEL_FEE_SYP` * 100 cents)
    from rider → driver when a ride is cancelled with an assigned driver.
  - `Idempotency-Key` is derived from ride id and amount.
  - **Guardrail:** per–driver daily cap:
    - Env: `TAXI_CANCEL_MAX_PER_DRIVER_DAY` (default 50).
    - `_TAXI_CANCEL_EVENTS[driver_id]` holds recent events.
    - Above the cap, the transfer is skipped and `taxi_cancel_guardrail`
      is logged via `_audit`.

### 3.4 Data Leakage via Logs

**Threats**

- Secrets, tokens, OTP codes appearing in logs.
- Full cardholder–like data or sensitive PII being logged.

**Mitigations**

- Audit logger `shamell.audit` only receives structured payloads with:
  - `action`, `phone`, `ts_ms` and contextual keys (driver_id, ride_id,
    amount_cents, etc.).
  - No code paths pass raw OTP codes, full access tokens, or secrets
    into `_audit`.
- Perf and metrics logs carry only coarse timings and labels, not PII.
- Security guideline: when adding new logging, prefer:
  - IDs/roles/status codes,
  - Never secrets, access tokens, raw codes, or full JSON payloads.

---

## 4. Guardrails: Configuration

The following env vars can be tuned per environment:

- **Auth / OTP**
  - `AUTH_RATE_WINDOW_SECS` – window for rate limiting (default 60s).
  - `AUTH_MAX_PER_PHONE` – max OTP attempts per phone per window.
  - `AUTH_MAX_PER_IP` – max OTP attempts per IP per window.
  - `AUTH_EXPOSE_CODES` – `false` in prod; codes are never returned.

- **Taxi settlement & cancel fees**
  - `ESCROW_WALLET_ID` – escrow wallet for ride payouts.
  - `TAXI_PAYOUT_MAX_PER_DRIVER_DAY` – max payout legs per driver per
    rolling day (default 50).
  - `TAXI_CANCEL_FEE_SYP` – cancel fee in SYP (default 4000).
  - `TAXI_CANCEL_MAX_PER_DRIVER_DAY` – max cancel-fee transfers per
    driver per day (default 50).

These guardrails are **best–effort and per–process**; they are designed
to raise friction for large–scale abuse without blocking normal usage.
For a fully hardened architecture, consider moving these counters into
the domain DB and/or a dedicated risk service.

---

## 5. What to Watch When Extending the App

When adding new endpoints or domains:

1. **Decide the trust boundary**
   - Is this endpoint public, authenticated, operator–only, or admin–
     only? Use `_require_operator`, `_require_admin_v2` or
     `_require_superadmin` accordingly.

2. **Define invariants**
   - For money: idempotency, balance conservation, fee/payout logic.
   - For bookings: availability, overbooking rules.
   - Write tests that assert these invariants at both domain and BFF
     layers (with stubs where needed).

3. **Avoid logging secrets**
   - Never log raw headers, tokens, or OTP codes.
   - Prefer `action` + ids + counts in `_audit`.

4. **Consider rate limits / guardrails**
   - For any write that affects money or availability, consider:
     - Rate limiting per user/phone/IP.
     - Per–entity caps per day/hour (similar to taxi payout/cancel).

This document should be kept up to date as new domains and features are
added; it is a living map of how Shamell approaches security and privacy
in the monolith world.

---

## 6. Production Checklist

Recommended baseline settings for a production–like environment:

- **Auth / OTP**
  - `AUTH_EXPOSE_CODES=false`
  - `AUTH_RATE_WINDOW_SECS=60`
  - `AUTH_MAX_PER_PHONE=5` (or stricter, e.g. 3)
  - `AUTH_MAX_PER_IP=40` (tune based on expected traffic)

- **Taxi settlement / cancel fees**
  - `ESCROW_WALLET_ID` **must be non-empty** and point to a dedicated
    escrow wallet, not used for any other purpose.
  - `TAXI_PAYOUT_MAX_PER_DRIVER_DAY` set to a realistic upper bound
    (e.g. `60` for high–volume drivers).
  - `TAXI_CANCEL_FEE_SYP` set according to business rules (e.g. `4000`).
  - `TAXI_CANCEL_MAX_PER_DRIVER_DAY` set to a reasonable threshold to
    catch abuse (e.g. `40`).

- **Security headers & maintenance**
  - `SECURITY_HEADERS_ENABLED=true` (default) to ensure:
    - `X-Content-Type-Options: nosniff`
    - `X-Frame-Options: DENY`
    - `Referrer-Policy: strict-origin-when-cross-origin`
    - `Content-Security-Policy` with self–only defaults.
  - `MAINTENANCE_MODE=false` in normal operation.
    - When `true`, all non `/admin*` and `/health*` requests return
      `503` with `Retry-After`, allowing controlled maintenance windows.

### Example: docker run (monolith, prod–like)

```bash
docker run --rm -p 8080:8080 \
  -e ENV=prod \
  -e AUTH_EXPOSE_CODES=false \
  -e AUTH_RATE_WINDOW_SECS=60 \
  -e AUTH_MAX_PER_PHONE=5 \
  -e AUTH_MAX_PER_IP=40 \
  -e ESCROW_WALLET_ID=wallet_escrow_prod \
  -e TAXI_PAYOUT_MAX_PER_DRIVER_DAY=60 \
  -e TAXI_CANCEL_FEE_SYP=4000 \
  -e TAXI_CANCEL_MAX_PER_DRIVER_DAY=40 \
  -e SECURITY_HEADERS_ENABLED=true \
  -e MAINTENANCE_MODE=false \
  shamell/monolith:latest
```

### Example: Kubernetes Deployment snippet

```yaml
env:
  - name: ENV
    value: "prod"
  - name: AUTH_EXPOSE_CODES
    value: "false"
  - name: AUTH_RATE_WINDOW_SECS
    value: "60"
  - name: AUTH_MAX_PER_PHONE
    value: "5"
  - name: AUTH_MAX_PER_IP
    value: "40"
  - name: ESCROW_WALLET_ID
    valueFrom:
      secretKeyRef:
        name: shamell-secrets
        key: escrow_wallet_id
  - name: TAXI_PAYOUT_MAX_PER_DRIVER_DAY
    value: "60"
  - name: TAXI_CANCEL_FEE_SYP
    value: "4000"
  - name: TAXI_CANCEL_MAX_PER_DRIVER_DAY
    value: "40"
  - name: SECURITY_HEADERS_ENABLED
    value: "true"
  - name: MAINTENANCE_MODE
    value: "false"
```

These values are a starting point; they should be reviewed against real
traffic patterns and business rules, but they encode the security
assumptions this threat model is built on.

