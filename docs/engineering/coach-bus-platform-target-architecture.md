# Shamell Coach Bus Platform Target Architecture

## 1. Goal
Build a multi-carrier coach-bus platform that fits Shamell's superapp model while keeping transport catalog data, commercial booking state, operational boarding state, and partner finance separate.

The passenger experience is intended to ship later as a Shamell miniprogram. The platform core must therefore stay reusable across:
- Shamell passenger miniprogram
- Operator portal
- Crew / boarding app
- Admin console

## 2. Non-Negotiable Domain Boundary
Do not collapse these concepts into one record:
- `offer`
- `booking`
- `ticket`
- `boarding`
- `settlement`

Required interpretation:
- `offer`: priced, time-bound commercial quote
- `hold`: temporary inventory reservation for checkout
- `booking`: customer order / commercial contract
- `ticket`: travel entitlement per passenger and segment
- `boarding`: operational scan / usage evidence
- `settlement`: what Shamell owes or deducts per operator

Consequence:
- ticket reissue must not mutate the original booking into an unreadable state
- boarding scans must not be derived from payment state
- refunds and chargebacks must not directly rewrite operator payout balances

## 3. Product Surfaces
- Passenger miniprogram in Shamell: search, compare, book, pay, manage tickets, self-service changes, live journey day
- Operator portal: schedule, fares, quotas, seat maps, manifests, disruptions, refund handling, settlement statements
- Crew / boarding app: manifest, offline scan, no-show, denied boarding, incident capture
- Admin console: live ops, support, partner onboarding, finance, audit, risk, CMS, analytics

## 4. Runtime Architecture
```text
Passenger Miniprogram / Operator Portal / Crew App / Admin Console
-> API Edge
   - AuthN / RBAC context
   - WAF / rate limits
   - upload controls
   - websocket / SSE auth
-> Product Facades
   - Passenger API
   - Partner API
   - Crew API
   - Admin API
-> Core Modules
   - auth
   - payments
   - transit_catalog
   - transit_offers
   - transit_orders
   - transit_ticketing
   - transit_boarding
   - transit_settlement
   - partner_connectivity
   - notifications
   - support
-> Data Plane
   - relational source-of-truth database
   - search index
   - cache
   - event bus / queue
   - object storage
   - warehouse
-> External Integrations
   - GTFS / NeTEx
   - GTFS-Realtime / SIRI
   - operator APIs
   - Shamell Pay in Shamell App
   - operator payout rails
   - Apple Wallet / Google Wallet
   - email / push / SMS
   - ERP / BI / DATEV
```

## 5. Repo-Aligned V2 Module Split
The transport slice should enter the Shamell v2 backend with the following boundaries:

### `transit_catalog`
- canonical stops, stop clusters, cities, lines, trips, calendars, fare products, amenities, baggage rules
- station alias resolution and search read models
- static feed normalization from GTFS / NeTEx via `partner_connectivity`

### `transit_offers`
- live availability
- seat maps
- quote generation
- hold creation / expiry
- price TTL enforcement

### `transit_orders`
- passenger details
- checkout orchestration
- booking creation
- change / cancel / refund eligibility decisions
- payment-to-ticketing compensation flow orchestration

### `transit_ticketing`
- ticket / coupon issuance
- QR or barcode payload references
- wallet-pass artifacts
- reissue / void history

### `transit_boarding`
- manifests
- scan events
- duplicate-use detection
- offline sync
- boarded / denied / no_show evidence

### `transit_settlement`
- operator payables
- commission and fee deductions
- settlement runs
- negative settlement carry-forward
- reconciliation and statements

### `partner_connectivity`
- GTFS / NeTEx ingest
- GTFS-RT / SIRI realtime adapters
- operator API adapters
- certification / sandbox
- replay and reconciliation tooling

## 6. Search And Booking Flow
The passenger journey should execute as:

1. Station resolution
2. Catalog search over indexed trips
3. Realtime enrichment for delays, cancellations, platform changes
4. Live availability and price refresh for top candidates only
5. Offer creation with TTL
6. Hold creation when supported
7. Payment authorization / collection via Shamell Pay in Shamell App
8. Booking finalization
9. Ticket issuance
10. Ticket artifact delivery: app, PDF, wallet pass, notifications
11. Settlement accrual

Commercial assumption for the current coach rollout:
- customer payment collection happens centrally inside Shamell App via Shamell Pay
- Shamell retains a 1% application fee on coach bookings
- operator payout happens downstream from Shamell-side collection and reconciliation

Compensation is mandatory:
- if payment succeeds and ticketing fails, move into a compensating workflow
- the workflow may retry ticketing, automatically void, or route to support based on partner capabilities

## 7. Realtime SLA And Feed Health
Realtime ingest must treat freshness as a product concern, not just an infrastructure concern.

Target freshness budget:
- trip updates: at most 90 seconds old
- vehicle positions: at most 90 seconds old
- service alerts: at most 10 minutes old

Operational consequences:
- expose freshness per operator in admin and operator dashboards
- downgrade journey confidence when freshness is stale
- suppress vehicle-position UI when the source is outside budget

## 8. Canonical Data Model
`partner_connectivity` must normalize:
- operator stop IDs
- city aliases
- stop clusters
- brand / operator names
- route identifiers
- fare product naming

Canonical stop resolution is required before search ranking; otherwise the same city or terminal will fragment into partner-specific results.

## 9. Payment, Ticketing, And Settlement Rules
Payment, booking, ticketing, and settlement must stay decoupled.

Required commercial sequence:
- hold inventory
- authorize or collect payment
- finalize booking
- issue tickets
- accrue operator payable
- accrue Shamell app fee revenue and liabilities

Required finance model:
- never store a single mutable partner balance as the source of truth
- use a journal / subledger for liabilities, payables, fees, reserves, and adjustments

Minimum settlement accounts:
- customer cash liability
- promo liability
- refund credit liability
- gift card liability
- Shamell Pay clearing
- operator payable
- Shamell app fee revenue
- booking fee revenue
- tax payable
- chargeback reserve
- settlement in transit
- unreconciled items
- manual adjustments

## 10. Passenger Miniprogram Integration In Shamell
The first passenger slice should ship as a Shamell miniprogram, not a standalone surface.

Recommended miniprogram scope:
- home/search
- results
- journey detail
- checkout
- ticket wallet
- rebook / cancel self-service
- day-of-travel live status

Recommended BFF route group:
- `/me/coach/search`
- `/me/coach/offers`
- `/me/coach/holds`
- `/me/coach/bookings`
- `/me/coach/tickets`
- `/me/coach/journeys/:journey_id/live`

Shamell-specific rules:
- gate the feature behind a dedicated capability flag
- keep ticket QR available offline in the miniprogram cache
- treat wallet passes and PDF generation as artifact delivery, not as the ticket source of truth
- keep operator and admin workflows outside the passenger miniprogram

## 11. Delivery Phases
### Phase 1
- catalog ingest
- search
- live offers
- booking
- ticket display in Shamell

### Phase 2
- self-service cancel / change
- operator portal
- crew scanning
- wallet passes

### Phase 3
- multi-segment reissue
- automated disruption reaccommodation
- full settlement automation
- partner certification tooling

## 12. Risks To Avoid
- mixing search DTOs with booking state
- using ticket status as the only proof of boarding
- deriving operator payout from a mutable balance instead of journal entries
- fan-out availability calls for every search result
- lacking idempotency on payment, booking, ticketing, refund, and settlement mutations
