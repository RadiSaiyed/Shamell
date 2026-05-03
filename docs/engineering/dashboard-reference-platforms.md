# Dashboard Reference Platforms For Shamell

## Purpose
This document fixes the reference direction for Shamell dashboards.

We will not design Shamell dashboards from scratch in a vacuum. We will borrow
tested interaction patterns from strong platforms and adapt them to Shamell's
actual roles:

- owner
- internal admins
- ride operations staff
- coach operators
- boarding staff
- cash-in and cash-out agents

Benchmarked on April 16, 2026 from official product pages and docs.

## The Platforms We Should Copy From

### 1. Uber Business / Uber Central
Official sources:

- https://www.uber.com/us/en/business/products/business-hub/
- https://www.uber.com/us/en/business/products/central/

What to borrow:

- A control-plane home that is operational, not decorative.
- One clear command surface for dispatch, exceptions, and active work.
- Fast drill-down from summary into a live incident, trip, or person.
- Admin tasks separated from day-to-day operations.

What this means for Shamell:

- `Shamell Control` should feel like an operations desk, not a generic admin portal.
- Active queues and exceptions must dominate the first screen.
- Search for rider, driver, bus trip, operator, wallet, or account must be global.

### 2. Samsara
Official source:

- https://www.samsara.com/blog/meet-the-new-samsara-platform-experience/

What to borrow:

- Navigation grouped by responsibility instead of by raw data model.
- A map-plus-table operating pattern for live fleets.
- Fast context switching between overview, asset detail, alerts, and history.
- Strong emphasis on operational freshness and exceptions.

What this means for Shamell:

- Ride ops and coach ops should use map/list split views where live movement matters.
- Alerts, SLA freshness, and unresolved incidents should stay pinned and visible.
- Operator staff should not need to jump through many screens to resolve one issue.

### 3. FlixBus / Flix Partner and marketplace-style coach operations
Official source:

- https://www.flixbus.com/company/flix-for-business

What to borrow:

- Self-service operator flows.
- Capacity, route, trip, and sales-oriented management.
- A business-facing tone for partners rather than an internal engineering tone.

What this means for Shamell:

- The coach operator dashboard should behave like a partner portal.
- It should prioritize routes, manifests, occupancy, settlements, boarding, and disruptions.
- It should not look like the internal superadmin dashboard with fewer buttons.

### 4. Stripe Dashboard / Stripe Connect
Official sources:

- https://docs.stripe.com/dashboard/basics
- https://stripe.com/connect/features

What to borrow:

- Very clear money surfaces: balances, payouts, disputes, verification, timeline.
- A task-driven home with risk and compliance work surfaced early.
- Strong separation between read-only finance visibility and write-capable finance actions.
- Excellent transaction detail pages with auditability.

What this means for Shamell:

- Cash and wallet dashboards should be ledger-first.
- Agent, branch, finance, and admin views must each have different default homes.
- Every money mutation should show status, actor, timestamp, reference, and reason.

### 5. GrabMerchant
Official source:

- https://www.grab.com/sg/merchant/

What to borrow:

- One entry dashboard for business users who are not technical.
- Daily work first: orders, issues, support, performance, payouts.
- Friendly but operational UI with minimal jargon.

What this means for Shamell:

- Coach operators and cash agents need simpler homes than internal staff.
- First screens should answer:
  - what needs my attention now?
  - what happened today?
  - what am I allowed to do?

### 6. Cloudflare Zero Trust
Official sources:

- https://developers.cloudflare.com/cloudflare-one/
- https://developers.cloudflare.com/cloudflare-one/access-controls/policies/

What to borrow:

- Task-based navigation for access, policies, devices, and audit.
- Clean separation between identity, policy, application, and audit layers.
- Consistent visibility of scope and enforcement state.

What this means for Shamell:

- Access administration must be explicit about scope.
- Every access-assignment screen must show who, what role, what scope, who granted it, and when.
- We should never hide important scope decisions behind vague labels like `admin`.

## Shamell Dashboard Direction

### A. Shamell Control
Reference mix:

- Uber Central
- Samsara
- Cloudflare Zero Trust
- Stripe Dashboard

Primary purpose:

- Run the platform in real time.

The first screen must contain:

- live operations queue
- exceptions queue
- finance exceptions
- trust and safety issues
- global search
- KPI strip for "right now", not vanity metrics

The left navigation should be:

- Overview
- Live Ops
- Coach Ops
- Payments
- Access
- Audit
- Support

Not this:

- random feature links
- mixed internal and partner tasks
- duplicated admin pages

### B. Coach Operator Dashboard
Reference mix:

- Flix-style operator portal
- GrabMerchant
- Samsara

Primary purpose:

- Let operators run their own business inside Shamell.

The first screen must contain:

- today's departures
- boarding status
- occupancy and sold seats
- delayed and disrupted trips
- settlement summary
- unresolved issues

The navigation should be:

- Today
- Trips
- Routes
- Boarding
- Sales
- Settlements
- Team
- Support

Critical rule:

- internal platform controls must not leak into this surface

### C. Boarding / Crew Dashboard
Reference mix:

- airline or terminal-style operational scanning flow
- Samsara detail-first task execution

Primary purpose:

- finish one operational task quickly under time pressure

The first screen must contain:

- active manifest
- scan action
- passenger exceptions
- bus departure countdown

This screen should be:

- mobile-first
- one task per view
- very low navigation depth

### D. Cash Agent Dashboard
Reference mix:

- Stripe Dashboard
- Square-style operational cash surfaces
- GrabMerchant simplicity

Primary purpose:

- handle cash safely with minimal confusion

The first screen must contain:

- shift status
- available cash actions
- pending redemptions
- today's volume
- discrepancies or blocked actions

The navigation should be:

- Home
- Redeem
- Deposit
- Ledger
- Settlement
- Help

Critical rule:

- cash agents must never see platform-wide admin furniture

### E. Access Administration
Reference mix:

- Cloudflare Zero Trust
- Stripe roles and finance separation

Primary purpose:

- assign the correct access with the smallest possible scope

The first screen must contain:

- pending invites
- recent grants and revocations
- expiring access
- searchable people and organizations

Every assignment row should show:

- subject
- role
- scope
- granted by
- granted at
- expires at
- last used

## Non-Negotiable Design Rules

### 1. One role, one home
Do not force owner, operator, boarding staff, and cash agents into the same home
experience.

### 2. Work queues before analytics
If a role performs real-time work, the queue comes before charts.

### 3. Scope must be visible
Every dashboard must make scope visible:

- platform
- organization
- operator
- branch
- city
- official account

### 4. Search must be universal
All serious dashboards need fast search for people, trips, vehicles, payments,
accounts, and incidents.

### 5. Audit trails are product features
Audit is not a hidden compliance page. It should be reachable from the places
where sensitive action happens.

### 6. Partner portals must feel different from internal control
Internal staff can handle denser multi-panel tools. Operators and agents need
more guided dashboards.

## What We Should Avoid

- giant generic KPI walls
- one dashboard reused for every role
- role checks that hide buttons but leave navigation conceptually unchanged
- analytics-heavy homes that bury urgent action
- vague labels such as `admin`, `ops`, or `manager` without visible scope
- mixing platform settings with frontline workflow

## Concrete Shamell Implementation Order

1. Redesign `Shamell Control` around live operations, exceptions, and search.
2. Split the coach operator dashboard into a true partner portal, not a reduced internal admin page.
3. Simplify boarding into a focused operational flow.
4. Rebuild cash-agent surfaces around shift, redeem, ledger, and settlement.
5. Make access administration visibly scope-first everywhere.

## Sources

- Uber Business Hub: https://www.uber.com/us/en/business/products/business-hub/
- Uber Central: https://www.uber.com/us/en/business/products/central/
- Samsara platform experience: https://www.samsara.com/blog/meet-the-new-samsara-platform-experience/
- Flix for Business: https://www.flixbus.com/company/flix-for-business
- Stripe Dashboard basics: https://docs.stripe.com/dashboard/basics
- Stripe Connect features: https://stripe.com/connect/features
- GrabMerchant: https://www.grab.com/sg/merchant/
- Cloudflare One: https://developers.cloudflare.com/cloudflare-one/
- Cloudflare Access policies: https://developers.cloudflare.com/cloudflare-one/access-controls/policies/
