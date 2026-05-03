# Module Layout Contract

## `domain/`
- Entities
- Value objects
- Invariants and policies

## `application/`
- Use-cases
- Transaction orchestration
- Ports to infrastructure

## `infrastructure/`
- Postgres adapters
- External API clients
- Event publishers

## `api/`
- Request/response DTOs
- Auth middleware wiring
- Error mapping to HTTP semantics

## Dependency direction
`api` -> `application` -> `domain`
`infrastructure` can depend on `application` ports and `domain` types.
`domain` depends on nothing except standard library.
