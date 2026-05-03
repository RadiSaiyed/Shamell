# V2 Backend Skeleton (Modular Monolith) — module layout reference

This directory captures the *target* module layout for the V2 backend
(strangler migration). It is **documentation**, not code: every entry is
a README describing the responsibilities of a hexagonal layer.

The same tree was previously checked in at `services_rs/v2_core/`, which
made it look like a real Cargo crate even though no `Cargo.toml` or
`*.rs` files lived there. The layout was moved to `docs/` so the
repository's `services_rs/` directory only contains buildable crates.

## Target module structure

```text
docs/v2/architecture/modules/
  auth/
    domain/
    application/
    infrastructure/
    api/
  chat/
    domain/
    application/
    infrastructure/
    api/
  payments/
    domain/
    application/
    infrastructure/
    api/
  shared/
```

Current scaffolded modules:
- `auth/`
- `chat/`
- `payments/`
- `shared/`

## Rules
- Cross-module calls are explicit through application interfaces.
- HTTP handlers are only in `api/`.
- DB and external clients are only in `infrastructure/`.
- Domain remains framework-agnostic.
