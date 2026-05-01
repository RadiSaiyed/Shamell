# V2 Backend Skeleton (Modular Monolith)

This folder contains the v2 backend module skeleton used for strangler migration.

## Target module structure

```text
services_rs/v2_core/
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
