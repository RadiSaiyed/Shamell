# V2 Target Architecture

## Principles
- Prefer simple modular boundaries over distributed complexity.
- Contract-first API design.
- Clear layering and ownership.
- Migration by strangler pattern.

## Domains
- `auth`
- `chat`
- `payments`

## Cross-cutting
- Feature flags for rollout control.
- Typed telemetry and KPI ownership.
- Security and privacy gates in CI.
