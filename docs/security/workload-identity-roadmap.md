# Workload Identity & mTLS Roadmap

This document defines the security migration path from shared internal secrets
to workload identity and mTLS for Shamell microservices.

## Scope

- BFF gateway
- Chat service
- Payments service
- Bus service
- Internal automation calling `/internal/*` routes

## Phase 0 (Now): Secret Segmentation + Guardrails

Goals:
- Remove single shared secret blast radius.
- Ensure production defaults reject weak/internal legacy auth paths.

Controls:
- Dedicated internal secrets per hop/service:
  - `INTERNAL_API_SECRET` (edge -> BFF)
  - `PAYMENTS_INTERNAL_SECRET` (BFF -> Payments)
  - `CHAT_INTERNAL_SECRET` (BFF -> Chat)
  - `BUS_INTERNAL_SECRET` (BFF -> Bus)
- User session auth is cookie-only (`__Host-sa_session` / optional legacy `sa_session` migration switch).
- Nginx blocks public `/internal/*` and strips trusted headers from edge traffic.

## Phase 1 (Short Term): Service Identity Assertion (Implemented Baseline)

Goals:
- Bind calls to service identity, not only to bearer secret knowledge.

Controls:
- Add `X-Internal-Service-Id` on all internal calls (`bff`, `payments`, `chat`, `bus`, `security-timer`).
- On receivers, enforce:
  - secret is valid for that caller, and
  - caller id is in explicit allowlist per route group.
- Add route-level allowlists (example):
  - Payments internal routes: only `bff`.
  - Bus write/admin routes: only `bff`.
  - BFF `/internal/security/alerts`: only `security-timer` and `bff`.
- Emit structured auth decision logs for denied caller-id/secret mismatches.

Current baseline in repo:
- `InternalAuthLayer` enforces `X-Internal-Service-Id` allowlists when configured.
- Prod/staging defaults:
  - BFF public API routes accept `edge`
  - BFF `/internal/security/alerts` accepts `security-reporter`
  - Chat accepts `bff`
  - Bus accepts `bff`
  - Payments `/transfer` accepts only `bff`
  - Payments `/internal/bus/bookings/transfer` accepts only `bus` and requires `BUS_PAYMENTS_INTERNAL_SECRET`

## Phase 2 (Target): mTLS Workload Identity

Goals:
- Cryptographic workload identity and mutual authentication.

Controls:
- Deploy mTLS workload identity with SPIFFE/SPIRE (best-practice target).
- Policy by identity (not IP/headers):
  - `spiffe://shamell/prod/bff` -> payments/chat/bus
  - `spiffe://shamell/prod/security-timer` -> bff/internal alerts
- Rotate certificates automatically; short-lived certs preferred.
- Keep shared header secrets only as temporary compatibility fallback.

## Exit Criteria (Phase 2 Complete)

- Internal routes no longer trust shared bearer secret as primary control.
- All service-to-service traffic authenticated/authorized by workload identity.
- Secret-based fallback disabled in prod.
- CI/deploy checks fail if fallback is reintroduced.
