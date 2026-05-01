# Backend Blueprint: Modular Monolith

## Module layout
Each domain module follows:
- `domain/` entities and invariants
- `application/` use-cases and orchestration
- `infrastructure/` db, external clients
- `api/` HTTP/websocket handlers

## Rules
- Domain module dependencies are explicit.
- No framework-specific types in `domain`.
- Async/event delivery only when required by product behavior (e.g. notification fanout, audit).

## Contract-first
- Add/modify endpoints in `docs/v2/contracts/openapi.yaml` first.
- Generate client stubs before implementing handlers.
- The checked-in `openapi.yaml` is currently generated from the live BFF router to keep the route/method surface honest; enrich request/response schemas before using it as a full codegen contract.

## Scaffold location
- Concrete module scaffold lives in `services_rs/v2_core/` with `auth`, `chat`, and `payments` directories.
