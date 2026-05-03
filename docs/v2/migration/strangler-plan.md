# Strangler Migration Plan

## Rules
1. New implementation behind feature flag.
2. Observe metrics parity before default-on.
3. Keep rollback in one toggle.
4. Delete legacy only after stability window.

## Phases
- Phase 0: foundation (architecture, contracts, tokens, telemetry).
- Phase 1: migrate auth flow.
- Phase 2: migrate chat flow.
- Phase 3: migrate payments flow.
- Phase 4: remove legacy routes/screens and stale data paths.

## Current Status (2026-03-07)
- Phase 1 auth integration is active behind a flag.
- `LoginGate` now switches between legacy and v2 auth paths via persistent toggle.
- v2 auth uses the same account-session bootstrap path as legacy to avoid auth drift.
- Legacy and v2 auth attempts are both benchmarked (`attempts/success/failure/avg`).
- Phase 2 chat pilot is now wired in the existing Chats tab behind a persistent toggle.
- Legacy and v2 chat send attempts are benchmarked (`attempts/success/failure/avg`).
- Phase 2 v2-path now uses the real encrypted direct-chat backbone (`ChatService` + inbox sync), not local-only stub storage.
- Phase 2 v2-path now bootstraps/advances outbound ratchet context (`key_id`, `prev_key_id`, `sender_dh_pub_b64`) before each send.
- Auth and Chat v2 are now default-on; legacy remains available as rollback fallback via persistent toggles.
- Remaining gate for legacy deletion: one full stability window with rollback toggle unused.

## Release gate per phase
- Functional tests green.
- No severity-1 regressions.
- KPI guardrails hold for 7-day window.

## Rollout and rollback gate policy

### Rollout gate (must all pass)
1. Feature flag state and rollback owner are explicitly documented before rollout.
2. Unit/integration tests are green for touched domains.
3. KPI baseline snapshot is captured before exposure.
4. Canary cohort is explicitly bounded.
5. On-call owner and rollback operator are assigned.

### Rollback triggers (any one triggers rollback)
1. Sev-1 incident tied to the v2 path.
2. Error-rate regression above agreed SLO threshold.
3. p95 latency regression above agreed SLO threshold.
4. Core conversion drops outside allowed band.
5. Security/privacy check fails post-rollout.

### Feature-flag-first cutover rule
1. Every user-visible v2 path ships behind a dedicated flag.
2. Default-on decision requires a completed stability window and KPI parity.
3. Legacy deletion is allowed only after the flag has stayed default-on through one full stability window.
