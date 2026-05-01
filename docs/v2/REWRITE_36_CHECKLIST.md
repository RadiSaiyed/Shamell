# Rewrite Program: 36-Point Checklist

All items are implemented in this repository as architecture, process, or code foundation artifacts.
Validation guard: `scripts/v2/check_v2_foundation.sh`.

## Product scope and priorities (1-6)
- [x] 1. Three core flows defined (`auth`, `chat`, `payments`).
- [x] 2. Explicit out-of-scope list documented.
- [x] 3. In/out product rules documented.
- [x] 4. Scope-first planning adopted before feature work.
- [x] 5. Core-flow-first release sequencing defined.
- [x] 6. Non-core work constrained by feature flags.

## Backend architecture (7-12)
- [x] 7. Modular-monolith target defined.
- [x] 8. Domain boundaries (`auth/chat/payments`) defined.
- [x] 9. 4-layer backend module structure defined.
- [x] 10. Framework leakage to domain disallowed by convention.
- [x] 11. Contract-first API process defined.
- [x] 12. Async/events limited to required use-cases.

## Frontend architecture (13-18)
- [x] 13. Feature-first Flutter structure defined.
- [x] 14. UI/application/domain/infrastructure layers defined.
- [x] 15. Shared design system location defined.
- [x] 16. Presentational widget rule documented.
- [x] 17. Single state-management style per feature enforced by convention.
- [x] 18. Standard empty/loading/error/success UX requirement documented.

## Design and UX quality (19-24)
- [x] 19. Design tokens baseline defined.
- [x] 20. Reusable component kit baseline defined.
- [x] 21. Motion guidelines defined.
- [x] 22. First-success in <= 30s objective set.
- [x] 23. Personalized home/engagement loop requirement defined.
- [x] 24. Explicit no-dark-pattern policy documented.

## Engineering rigor (25-30)
- [x] 25. Definition of Done added.
- [x] 26. PR template with quality gates added.
- [x] 27. ADR template and accepted rewrite ADR added.
- [x] 28. Conventions for backend/frontend/contracts added.
- [x] 29. Test pyramid expectation defined.
- [x] 30. Security/privacy/performance checks included in DoD.

## Delivery, observability, migration (31-36)
- [x] 31. Telemetry event catalog defined.
- [x] 32. KPI framework documented.
- [x] 33. Strangler migration phases documented.
- [x] 34. Rollout/rollback gate policy documented.
- [x] 35. Feature-flag-first cutover rule documented.
- [x] 36. Program index document added for team onboarding.

## Evidence map
- Product: `docs/v2/product/core-scope.md`
- Product engagement: `docs/v2/product/engagement-principles.md`
- Architecture: `docs/v2/architecture/target.md`
- Backend: `docs/v2/backend/modular-monolith.md`
- Frontend: `docs/v2/frontend/flutter-feature-first.md`
- Frontend design: `docs/v2/frontend/design-system.md`, `docs/v2/frontend/interaction-principles.md`
- Contracts: `docs/v2/contracts/openapi.yaml`
- Metrics: `docs/v2/metrics/kpi-framework.md`, `docs/v2/metrics/events.yaml`
- Migration: `docs/v2/migration/strangler-plan.md`
- Governance: `docs/engineering/definition_of_done.md`, `docs/engineering/conventions_v2.md`, `.github/pull_request_template.md`, `docs/adr/ADR_TEMPLATE.md`, `docs/adr/0002-v2-rewrite-foundation.md`
