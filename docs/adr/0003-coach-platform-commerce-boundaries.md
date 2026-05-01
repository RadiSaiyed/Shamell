# ADR-0003: Coach Commerce Boundaries And Transit Module Split

- Status: Accepted
- Date: 2026-04-07
- Owners: Shamell platform

## Context
Shamell is expanding from ride hailing into a multi-carrier coach-bus platform. The new product includes catalog feeds, realtime enrichment, availability, booking, ticketing, boarding, and partner settlement. Coach passenger payments are collected centrally inside Shamell App via Shamell Pay, and Shamell retains a 1% application fee before downstream operator settlement. If these concerns are modeled as one mutable "booking" record, later requirements such as seat holds, partial ticketing, offline boarding, reissue, chargebacks, and partner payout reconciliation become brittle.

## Decision
Adopt the following hard boundaries for the coach platform:
- `offer` is separate from `booking`
- `booking` is separate from `ticket`
- `ticket` is separate from `boarding`
- `settlement` is derived from ledgered commercial and operational facts, not from mutable ticket or booking balances

Adopt the following v2 backend split:
- `transit_catalog`
- `transit_offers`
- `transit_orders`
- `transit_ticketing`
- `transit_boarding`
- `transit_settlement`
- `partner_connectivity`

## Alternatives considered
- Single transit module with one shared booking aggregate: rejected due to state explosion and ownership ambiguity
- Fold ticketing and boarding into orders: rejected because operational scan evidence has different latency, offline, and audit requirements
- Fold settlement into payments only: rejected because operator payout logic depends on transport-specific states and contract basis

## Consequences
- Positive:
  - Clear ownership boundaries for commerce, operations, and finance
  - Safer support, refund, reissue, and reconciliation workflows
  - Better fit for GTFS / NeTEx catalog data and GTFS-RT / SIRI realtime data
  - Finance flows stay aligned with central Shamell Pay collection and downstream operator settlement
- Negative:
  - More modules and integration events to manage
  - Higher upfront modeling cost than a single booking table
- Risks:
  - Cross-module orchestration can become opaque if events and idempotency keys are not standardized

## Rollout
Ship the coach passenger flow first as a Shamell miniprogram backed by the new transit modules. Keep operator, boarding, and settlement surfaces behind staged delivery milestones. Add partner adapters incrementally, starting with static feeds and read-only search before live ticketing.

## Validation
- Unit tests lock lifecycle transitions and ledger invariants
- Integration tests cover payment-to-ticketing compensation
- Reconciliation reports match Shamell Pay and operator statements in pilot
- Feed freshness dashboards show operator SLA compliance
