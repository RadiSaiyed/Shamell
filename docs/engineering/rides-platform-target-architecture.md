# Shamell Taxi Miniprogram Target Architecture

## 1) Product Surfaces
- Rider App: booking, live tracking, communication, payment, wallet, support/self-service.
- Driver App: online/offline, dispatch acceptance, navigation, trip lifecycle, earnings, payout, reserve/debt, documents.
- Admin/Operator Console: live ops, support, compliance/risk, finance, pricing/config, audit, BI.

## 2) Runtime Architecture
```
Rider App / Driver App / Admin Web
-> API Edge (AuthN, RBAC context, rate limits, WAF, websocket auth, upload controls)
-> BFF Facades (rider-facing, driver-facing, admin-facing route groups)
-> Core Domains
   - Identity & Roles
   - Rider/Driver/Fleet Profiles
   - Vehicles & Documents
   - Pricing / Tariff Engine
   - Dispatch / Matching
   - Trip Lifecycle
   - Payments / Wallets / Topups
   - Driver Earnings / Payouts / Reserve
   - Promotions / Credits
   - Notifications / Chat / Masked Calling
   - Support / Tickets / Refunds
   - Risk / Fraud / Compliance
   - Reporting / Warehouse
-> Data Plane
   - Relational DB (source of truth)
   - Cache + Geo read store
   - Object storage (documents/media)
   - Event bus / queue
   - Search index
   - Warehouse / BI
-> External Integrations
   - Map display: MapLibre + OSM vector tiles
   - Routing/ETA/search/traffic: TomTom
   - PSP + marketplace payouts
   - KYC/document verification
   - SMS/email/push
   - ERP/BI
```

## 3) Required Configuration (tenant/city scoped)
- Country, currency, language, tax model.
- Cities, zones, airports, pickup/dropoff geofences.
- Service classes: economy/xl/premium/delivery/corporate.
- Fare rules: base, per-km, per-minute, minimum, booking fee, wait, cancellation, airport surcharge, surge.
- Commission, bonus, cashback/promo rules.
- Payment methods: card, wallet, cash, corporate.
- Payout policy: daily/weekly/on-demand, reserve/hold.
- Driver document requirements by service type.
- Security/risk lists and fraud thresholds.
- Support SLA and escalation policy.

## 4) Operator Roles (non-negotiable)
- super_admin
- city_manager
- support_l1
- support_l2
- driver_ops
- finance
- compliance_risk
- marketing
- bi_audit_read_only

Every backoffice write-action requires:
- Role permission check.
- Reason code.
- Immutable audit log event.

## 5) Rider Lifecycle State Machine
- `idle`
- `quote_shown`
- `ride_requested`
- `matching`
- `driver_assigned`
- `driver_arriving`
- `driver_arrived`
- `trip_started`
- `trip_in_progress`
- `trip_completed`
- `cancelled`
- `payment_failed`

Invalid transitions must be fail-closed.

## 6) Wallet & Ledger Invariants
- Rider buckets are strictly separated:
  - `cash_balance`
  - `promo_credit`
  - `refund_credit`
  - `corporate_credit`
- Promo credit must never be merged with cash balance.
- Driver ledger keeps distinct balances:
  - `earnings_available`
  - `held_reserve`
  - `debt`
  - `payout_pending`
  - `bonuses`
  - `cash_collected`

## 7) BFF API Facades (target split)
- Rider API: quote, request/cancel, trip tracking, payment, wallet, ticket/refund.
- Driver API: availability, offer accept/decline, trip progression, earnings, payout, docs.
- Admin API: ops dashboards, refunds, payout controls, pricing/risk configs, audit export.

Current baseline in this repo:
- `/me/rides/search`
- `/me/rides/route`
- `/me/rides/traffic`

Next phase must add write-safe trip, payout, and support endpoints with idempotency keys.

