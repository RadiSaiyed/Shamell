# V2 Conventions

## Backend
- Use modular-monolith boundaries by domain (`auth`, `chat`, `payments`).
- Each domain has 4 layers: `domain`, `application`, `infrastructure`, `api`.
- Keep business logic in `domain`/`application`; keep framework code in `api`/`infrastructure`.
- Prefer synchronous calls unless async delivery is required.

## Flutter
- Organize by feature, not by widget type.
- Keep widgets presentational; move logic into controllers/use-cases.
- Use one state-management style per feature module.
- Shared visual primitives must come from v2 design system.

## Contracts
- API contract first (`docs/v2/contracts/openapi.yaml`).
- Keep the checked-in OpenAPI surface in sync with the live BFF router; route/method drift is CI-blocking.
- Client/server changes are versioned and backward compatible.

## Observability
- Emit telemetry only via typed event catalog (`docs/v2/metrics/events.yaml`).
- Every new flow must include activation and completion events.

## Delivery
- New risky behavior behind feature flags.
- Strangler migration only: no big-bang cutover.

## Testing (pyramid expectation)
- Default target split: unit-heavy, integration-middle, minimal end-to-end.
- Every change must include unit tests for business logic branches.
- Cross-layer behavior must be covered by integration tests for touched flows.
- End-to-end tests are reserved for critical happy-path and rollback-path checks.
