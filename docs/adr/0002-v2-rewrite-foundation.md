# ADR-0002: V2 Rewrite Foundation With Strangler Migration

- Status: Accepted
- Date: 2026-03-04
- Owners: Shamell platform

## Context
The current codebase contains multiple legacy surfaces and mixed patterns that make onboarding and change-safety harder. A big-bang rewrite is high risk for delivery and stability.

## Decision
Adopt a staged v2 foundation:
- Product scope narrowed to core flows (`auth`, `chat`, `payments`).
- Backend target architecture: modular monolith with domain boundaries.
- Flutter target architecture: feature-first modules with design-system primitives.
- Contract-first API via OpenAPI.
- Strangler migration with feature flags for all user-facing cutovers.

## Alternatives considered
- Big-bang rewrite: rejected due to outage and schedule risk.
- Keep patching legacy architecture: rejected due to growing complexity.

## Consequences
- Positive:
  - Better readability, onboarding, and ownership boundaries.
  - Lower rollout risk with feature flags and incremental migration.
- Negative:
  - Temporary dual-path complexity during migration.
- Risks:
  - Incomplete migration if tracking is weak.

## Rollout
Track progress in `docs/v2/REWRITE_36_CHECKLIST.md`, cut over by feature flags, and delete legacy paths only after metric parity is reached.

## Validation
- CI green (analyze/check/tests).
- KPI parity and improvement for activation/retention/latency.
- No rollback-trigger incidents in staged rollout.
