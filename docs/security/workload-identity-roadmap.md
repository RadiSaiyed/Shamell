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

## Phase 1 (Implemented): Service Identity Assertion

Goals:
- Bind calls to service identity, not only to bearer secret knowledge.

Controls:
- Add `X-Internal-Service-Id` on all internal calls (`bff`, `payments`, `chat`, `bus`, `security-timer`).
- Sign internal requests with Ed25519 over:
  - caller id
  - HTTP method
  - path + query
  - timestamp
  - nonce
  - SHA-256 of the request body
- On receivers, enforce:
  - signature validates against the configured caller public key set,
  - timestamp skew is within the configured replay window, and
  - nonce replay is rejected per service instance, and
  - caller id is in explicit allowlist per route group.
- Add route-level allowlists (example):
  - Payments internal routes: only `bff`.
  - Bus write/admin routes: only `bff`.
  - BFF `/internal/security/alerts`: only `security-timer` and `bff`.
- Emit structured auth decision logs for denied caller-id/signature mismatches.

Current baseline in repo:
- `InternalAuthLayer` supports signed internal identity verification with optional legacy secret fallback and optional v2-only enforcement.
- BFF signs outbound Chat/Payments calls with `BFF_INTERNAL_IDENTITY_SIGNING_SEED_B64`.
- BFF `/internal/security/alerts` can verify signed `security-reporter` identities via `BFF_SECURITY_ALERT_INTERNAL_IDENTITY_PUBLIC_KEYS`.
- Chat and Payments verify caller-bound, audience-bound public keys via `*_INTERNAL_IDENTITY_PUBLIC_KEYS`.
- The current rollout path remains dual-sign, but prod/staging receivers now require audience-bound v2 and keep v1 only as an explicit local rollback switch.
- Prod/staging defaults:
  - BFF public API routes accept `edge`
  - BFF `/internal/security/alerts` accepts `security-reporter`
  - Chat accepts `bff`
  - Bus accepts `bff`
  - Payments internal routes accept only `bff`

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
