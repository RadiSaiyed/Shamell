# Shamell Platform

Rust-first microservices platform for Shamell.

## Layout
- `services_rs/` Rust services (`bff_gateway`, `chat_service`, `payments_service`)
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

Internal end-to-end smoke (2 accounts, backend + DB; optional frontend checks):

```bash
./scripts/e2e_internal.sh
./scripts/e2e_internal.sh --with-frontend
make e2e-internal
```

Latest internal E2E report + reusable release checklist:
- `docs/testing/internal-e2e-report.md`
- Human workforce and partner IAM target architecture:
  - `docs/security/human-identity-access-target-architecture.md`
- Human workforce and partner IAM phase plan:
  - `docs/engineering/human-identity-access-phase1-phase2-plan.md`
- Human workforce IAM staging rollout checklist:
  - `docs/engineering/human-identity-access-staging-rollout-checklist.md`
- Dashboard reference platforms and Shamell design direction:
  - `docs/engineering/dashboard-reference-platforms.md`

`make e2e-internal` options:
- `E2E_WITH_FRONTEND=1|0` (default `1`)
- `E2E_BASE_PORT=<port>` (default `19480`)
- `E2E_ARTIFACT_DIR=<path>` (default `.artifacts/e2e`)

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
  - `scripts/check_cloudflare_realip_freshness.sh`
  - `scripts/check_update_cloudflare_ip_ranges_validation.sh`
  - `scripts/check_cloudflare_sync_freshness_guard.sh`
  - `scripts/check_ops_edge_commands.sh`
  - `scripts/check_cors_hardening.sh`
  - `scripts/check_deploy_env_invariants.sh`
  - `scripts/check_trusted_proxy_smoke_headers.sh`
  - `scripts/check_ci_trusted_proxy_smoke.sh`
  - `scripts/check_dashboard_proxy_trusted_proxy_guard.sh`
  - `scripts/check_frontend_error_sanitization.sh`
  - `scripts/check_no_secrets_in_urls.sh`

## Mobile release runbooks
- Signed mobile release CI verification:
  - `docs/release/mobile-signed-release-ci-runbook.md`
- Ride-hailing release and ops close-out:
  - `docs/release/ride-hailing-release-runbook.md`
- Android Kotlin/plugin upgrade path (`flutter_webrtc`):
  - `docs/release/kotlin-plugin-upgrade-path.md`

## V2 rewrite foundation
- Program index and 36-point implementation checklist:
  - `docs/v2/README.md`
  - `docs/v2/REWRITE_36_CHECKLIST.md`

## Production / Hetzner
Use `ops/pi/docker-compose.postgres.yml` (Postgres is mandatory in production):

```bash
./scripts/ops.sh pipg deploy
```

`pi` and `prod` are aliases of the same Postgres-backed stack.

Useful post-deploy checks:

```bash
./scripts/ops.sh pipg health
./scripts/ops.sh pipg ride-release-gate
./scripts/ops.sh pipg ride-repair-stale-presence --dry-run
bash scripts/check_mobile_firebase_flavors.sh
./scripts/ops.sh pipg cloudflare-status
./scripts/ops.sh pipg report
./scripts/ops.sh pipg smoke-api
./scripts/ops.sh pipg ride-report
./scripts/ops.sh pipg smoke-mailbox
./scripts/ops.sh pipg matrix-api
```

Remote mobile push for `Shamell Ride`, `Shamell Driver`, and `Shamell Control`
also requires valid per-flavor Firebase files under
`clients/shamell_flutter/android/app/src/<flavor>/google-services.json`.
Validate them with `bash scripts/check_mobile_firebase_flavors.sh` and see
`clients/shamell_flutter/FIREBASE_SETUP.md` for the secure install path and
`--dart-define` fallback.

Direct Android APK distribution without Play Store is now first-class. Build the
four signed production APKs locally with:

```bash
./scripts/build_android_release_apks.sh --output-dir .artifacts/android-apk-release
```

Then publish them to the canonical production download page:

```bash
./scripts/sync_hetzner_nginx.sh shamell
./scripts/publish_android_apk_downloads.sh \
  --source-dir .artifacts/android-apk-release \
  --host shamell
```

Users then install from:

```text
https://shamell.online/downloads/android/
```

If the Hetzner deploy user is not passwordless sudo, export
`REMOTE_SUDO_PASSWORD` before the sync/publish step. There is also a manual
GitHub Actions workflow, `Android APK Publish`, that builds the four signed APKs
from secrets and can publish the bundle directly to production.

`Shamell Control` also has a dedicated web console build. Build it locally with:

```bash
./scripts/build_control_web_release.sh --output-dir .artifacts/control-web-release
```

Then publish it to the production static site:

```bash
./scripts/sync_hetzner_nginx.sh shamell
./scripts/publish_control_web_release.sh \
  --source-dir .artifacts/control-web-release \
  --host shamell
```

The canonical production URL is:

```text
https://shamell.online/control/
```

There is also a manual GitHub Actions workflow, `Shamell Control Web Publish`,
that builds the operator web bundle from `lib/main_operator.dart` and can
publish it directly to production.

Canonical edge maintenance:

```bash
./scripts/ops.sh pipg cloudflare-status
./scripts/ops.sh pipg cloudflare-refresh
./scripts/ops.sh pipg sync-nginx shamell
./scripts/ops.sh pipg sync-ufw shamell
./scripts/ops.sh pipg sync-edge shamell
./scripts/ops.sh pipg sync-ride-report-timer shamell --run-now
```

`cloudflare-status` is the canonical local freshness check for the Cloudflare
trusted-proxy CIDR source of truth.

`pipg check` and `pipg deploy` now fail closed on stale Cloudflare trusted-proxy
CIDRs.

`pipg report` now exits non-zero when health or edge freshness checks fail.

`pipg report` also runs `ride-report` on non-dev stacks and, by default, fails
if ride-hailing findings are present.

`pipg ride-release-gate` is the canonical non-dev ride close-out: it runs
`schema-migrate bff`, `schema-migrate payments`, `health`, `smoke-api`, and
`ride-report` with `RIDE_REPORT_FAIL_ON_FINDINGS=1`.

GitHub Actions runs the same gate in the dedicated `ride-gate` CI job and the
scheduled `Ride Gate Nightly` workflow. Both publish an artifact bundle and a
markdown summary; the nightly workflow keeps a single failure issue open while
the gate is red and closes it automatically after recovery.

`pipg sync-nginx` and `pipg sync-edge` now run the same non-dev env preflight
before host changes.

`sync-edge` refreshes the local Cloudflare trusted-proxy CIDR snippet first,
then syncs Hetzner Nginx and UFW in that order. `sync-nginx` forwards the
selected ops env file (`ops/pi/.env` by default) into the host-local
internal-auth snippet render path.

`sync-ride-report-timer` installs a recurring host-side `systemd` timer for the
ride ops audit using the same resolved deploy tree and env file as the host
stack.

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
