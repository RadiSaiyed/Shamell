# Shamell Platform

Rust-first microservices platform for Shamell.

## Layout
- `services_rs/` Rust services (`bff_gateway`, `chat_service`, `payments_service`, `bus_service`)
- `crates_rs/` shared Rust crates (`shamell_common`)
- `clients/` Flutter client
- `ops/` deployment + Nginx + Postgres bootstrap assets
- `scripts/` operations and guard scripts

## Local development
Start the full local stack (Rust services + Postgres + LiveKit):

```bash
./scripts/ops.sh dev up
```

Useful commands:

```bash
./scripts/ops.sh dev health
./scripts/ops.sh dev ps
./scripts/ops.sh dev down
```

## CI-quality checks

```bash
make check
```

This runs:
- `cargo fmt --check`
- `cargo clippy --all-targets --all-features -- -D warnings`
- `cargo test`
- `cargo audit -D warnings` (RustSec advisories; configured via `.cargo/audit.toml`)
- `cargo deny check licenses bans sources` (license/supply-chain gates; configured via `deny.toml`)
- guard scripts:
  - `scripts/check_no_legacy_artifacts.sh`
  - `scripts/check_internal_port_exposure.sh`
  - `scripts/check_nginx_edge_hardening.sh`
  - `scripts/check_cors_hardening.sh`
  - `scripts/check_deploy_env_invariants.sh`
  - `scripts/check_frontend_error_sanitization.sh`
  - `scripts/check_no_secrets_in_urls.sh`

## Production / Hetzner
Use `ops/pi/docker-compose.postgres.yml` (Postgres is mandatory in production):

```bash
./scripts/ops.sh pipg deploy
```

`pi` and `prod` are aliases of the same Postgres-backed stack.

## Security notes
- Keep `BFF_REQUIRE_INTERNAL_SECRET=true` in production.
- Keep `BFF_ENFORCE_ROUTE_AUTHZ=true` in production.
- Set strong `BFF_ROLE_HEADER_SECRET` in production/staging.
- Keep Nginx edge hardening snippet enabled:
  - `ops/hetzner/nginx/snippets/shamell_bff_edge_hardening.conf`
- Keep internal service ports (`8081/8082/8083`) unexposed publicly.
- Keep dependency audit active in CI and review `.cargo/audit.toml` exceptions regularly.
- Workload identity/mTLS roadmap:
  - `docs/security/workload-identity-roadmap.md`
- Chat protocol (libsignal) migration RFC:
  - `docs/security/chat-protocol-libsignal-migration-rfc.md`
- Metadata-hardening roadmap:
  - `docs/security/metadata-hardening-roadmap.md`
