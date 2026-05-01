# Definition Of Done

A change is done only if all items below are satisfied.

1. Product scope is explicit (`in` and `out`).
2. Acceptance criteria are testable.
3. Code follows feature-first architecture.
4. Public APIs/contracts are versioned and documented.
5. Lint/format/analyze pass locally and in CI.
6. Unit tests cover critical branches.
7. Integration tests cover cross-layer behavior.
8. UI has empty/loading/error/success states.
9. Telemetry events are defined and emitted.
10. Security and privacy checks are complete.
11. Performance impact is measured (p95 latency/render).
12. Rollout and rollback strategy are documented.
13. Feature flag is used for risky or user-visible rollouts.
14. Migration notes are added if old code paths are affected.
15. Code owner review is completed.

## Exit Criteria
A PR may be merged only when every applicable item is green or has a documented exception in the PR body.
