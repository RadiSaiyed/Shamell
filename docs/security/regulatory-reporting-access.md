# Shamell Regulatory Reporting Snapshot

This repository now supports a regulator-facing reporting path that avoids direct reads against the live ride database.

## Architecture

- Source of truth remains `shamell_core`.
- A minimized source schema is exposed in the core database as `regulatory_reporting.*` views.
- A separate database, typically `regulator_reporting`, is provisioned for regulator access.
- `scripts/regulatory_reporting_snapshot.sh` copies only the approved views into snapshot tables in the separate database.
- Regulator queries run only against `regulator_reporting.vw_reg_*` views in the target database.

## Source Views

The source-side projection lives in `services_rs/bff_gateway/migrations/0099_bff_auth_regulatory_reporting_views.sql`.

Approved views:

- `regulatory_reporting.vw_reg_trips`
- `regulatory_reporting.vw_reg_drivers`
- `regulatory_reporting.vw_reg_fares`
- `regulatory_reporting.vw_reg_incidents`
- `regulatory_reporting.vw_reg_audit_log`

The views deliberately avoid:

- raw names, phone numbers, emails, or document numbers
- exact pickup/destination addresses
- driver live telemetry and GPS trails
- support-ticket free text and reviewer notes
- internal admin tables, tokens, secrets, and fraud signals

Pseudonymization is stable per snapshot salt via `app.reg_reporting_salt`, so the same rider/driver identifier stays joinable without disclosing the raw account identifier.

## Target Database

The bootstrap SQL at `ops/pi/postgres/regulatory_reporting_bootstrap.sql` creates:

- internal snapshot tables under `regulatory_snapshot`
- regulator-facing views under `regulatory_reporting`
- a dedicated login role, default `regulator_ro`

That role gets only:

- `CONNECT` on the target database
- `USAGE` on schema `regulatory_reporting`
- `SELECT` on `regulatory_reporting.vw_reg_*`

It does not get:

- access to `regulatory_snapshot.*`
- `CREATE`, `ALTER`, `DROP`
- `INSERT`, `UPDATE`, `DELETE`
- temp/schema privileges on the target database

`default_transaction_read_only` is forced on for the regulator role.

## Running a Snapshot

Local default:

```bash
make regulatory-snapshot
```

Ops default:

```bash
ENV_FILE=ops/pi/.env \
COMPOSE_FILE=ops/pi/docker-compose.postgres.yml \
./scripts/regulatory_reporting_snapshot.sh
```

Temporary direct GUI access without an SSH tunnel:

```bash
cd ops/pi
docker compose \
  -f docker-compose.postgres.yml \
  -f docker-compose.postgres.regulator-public.yml \
  --env-file .env \
  up -d db
```

That publishes the regulator database listener on `REGULATOR_POSTGRES_PUBLISH_PORT` (default `55432`) for direct tools such as Postbird or DBeaver. Keep it temporary and remove the override after the audit window closes.

Required configuration:

- `REGULATORY_REPORTING_DB_URL`
- `REGULATORY_REPORTING_SNAPSHOT_SALT`
- `REGULATOR_RO_USERNAME`
- `REGULATOR_RO_PASSWORD`

Optional:

- `REGULATORY_SNAPSHOT_MANIFEST_DIR`
- `REGULATORY_SNAPSHOT_SIGNING_KEY_FILE`
- `REGULATORY_SNAPSHOT_ID`
- `REGULATORY_SNAPSHOT_EXPORTED_BY`

Each run:

- registers a versioned `snapshot_id`
- copies the approved views into the separate database
- records row counts in `regulatory_snapshot.snapshot_runs`
- writes a manifest JSON file
- optionally signs the manifest when `REGULATORY_SNAPSHOT_SIGNING_KEY_FILE` is set

The target views always resolve to the latest snapshot with status `ready` and include `snapshot_id` plus `snapshot_cutoff_at`, so the regulator can see exactly which snapshot is being queried.

## Residual Deployment Controls

Some controls belong in deployment rather than application SQL:

- MFA for regulator identities
- IP allowlisting / jump-host restriction
- query auditing with PostgreSQL logging and optionally `pgaudit`
- account expiry and revocation workflow
- retention and deletion policy for old snapshots

Recommended PostgreSQL settings for the regulator role path:

- `log_connections = on`
- `log_disconnections = on`
- statement logging or `pgaudit.log = 'read,role'` where available

This keeps the regulator workflow aligned with least privilege and snapshot-based evidence handling instead of live mutable reads.
