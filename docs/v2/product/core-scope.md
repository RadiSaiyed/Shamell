# Core Scope (V2)

## In scope (core flows)
1. Auth and session lifecycle.
2. Chat (1:1, groups, core messaging).
3. Payments (wallet, transfer, history).

## Explicitly out of scope for initial V2
1. Legacy removed modules/domains.
2. Experimental partner surfaces.
3. Non-core admin consoles in mobile app shell.

## Product rules
- Any new feature must map to one of the 3 core flows.
- Non-core work must be behind a feature flag and must not block core stability.
- UX prioritizes speed-to-first-success and repeat usefulness.

## Scope-first planning workflow
1. Classify request as `auth`, `chat`, `payments`, or `non-core`.
2. Reject or defer work with no mapping to the 3 core flows.
3. For `non-core`, require a feature flag, owner, and rollback note before implementation.
4. Define acceptance criteria and KPI impact before code changes.

## Core-flow-first sequencing
1. Deliver and stabilize `auth` first.
2. Deliver and stabilize `chat` second.
3. Deliver and stabilize `payments` third.
4. Non-core work can ship only if it does not delay the current core-flow milestone.
