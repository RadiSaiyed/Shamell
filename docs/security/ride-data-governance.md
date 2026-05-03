# Shamell Ride Data Governance

This document records the repository-backed controls for ride data, identity data, and privileged operator access used by Shamell Ride, Shamell Driver, and Shamell Control.

## 1. Data at Rest

Confirmed from code:

- Mobile session and security state uses platform-protected storage through `flutter_secure_storage` with Android encrypted shared preferences and Apple secure keychain accessibility:
  - `clients/shamell_flutter/lib/core/capabilities.dart`
  - `clients/shamell_flutter/lib/core/session_cookie_store.dart`
  - `clients/shamell_flutter/lib/core/biometric_preference_store.dart`
  - `clients/shamell_flutter/lib/core/biometric_login.dart`
- Android release builds disable app backup and cleartext transport:
  - `clients/shamell_flutter/android/app/src/main/AndroidManifest.xml`
  - `clients/shamell_flutter/android/app/src/main/res/xml/network_security_config.xml`
- Server-side session state stores hashed session identifiers rather than raw session tokens:
  - `services_rs/bff_gateway/migrations/0001_bff_auth_baseline.sql`

Confirmed from repository operations code:

- Encrypted ride/auth database backups are produced by `scripts/ride_db_backup.sh`.
- Backup encryption is fail-closed: the script only allows `age` or `gpg` encryption and exits if encryption material is not configured.
- Hetzner timer units exist for scheduled encrypted backups:
  - `ops/hetzner/systemd/shamell-ride-db-backup.service`
  - `ops/hetzner/systemd/shamell-ride-db-backup.timer`

Inferred from code structure:

- The repository treats encrypted backups as the mandatory at-rest protection path that is directly enforceable from application operations code.

Not confirmed from code:

- The application cannot directly attest block-device or managed-volume encryption of the live database host. That remains a deployment responsibility and must be verified during infrastructure review.

## 2. Retention, Deletion, and No-Hard-Delete Policy

Confirmed from code:

- Authentication/session cleanup windows are runtime-configurable and enforced by the BFF maintenance loop:
  - `AUTH_MAINTENANCE_INTERVAL_SECS`
  - `AUTH_SESSION_CLEANUP_GRACE_SECS`
  - `AUTH_DEVICE_LOGIN_CLEANUP_GRACE_SECS`
  - `AUTH_DEVICE_SESSION_RETENTION_SECS`
  - `AUTH_RATE_LIMIT_RETENTION_SECS`
  - implementation in `services_rs/bff_gateway/src/auth.rs`
- Auth cleanup paths are backed by schema/index contracts and tests in `services_rs/bff_gateway/src/auth.rs`.
- The encrypted backup workflow rotates old backup artifacts according to `RIDE_DB_BACKUP_RETENTION_DAYS`.

Repository policy:

- Ride operational records are retained for auditability and operational traceability.
- Hard-delete automation is not required by policy for ride records.
- Backup rotation deletes only expired encrypted backup artifacts; it does not delete live operational records.

Inferred from code structure:

- Ride records are intended to be retained and audited rather than destructively purged during normal operation.

## 3. Role-Based Access Restrictions

Confirmed from code:

- Route-level role guards exist for ride operator, support, compliance, finance, driver, and pricing paths in `services_rs/bff_gateway/src/auth.rs`.
- Sensitive detail responses are reduced by role in `services_rs/bff_gateway/src/handlers.rs`, including:
  - support-ticket body redaction
  - case-detail redaction
  - role-dependent location precision
  - role-dependent finance/document detail exposure
- Public admin role mutation is restricted:
  - only superadmin may grant or remove `admin` and `superadmin`
  - lower-privilege roles remain visible/mutable only within allowed policy
  - validation/tests live in `services_rs/bff_gateway/src/handlers.rs`
- Sensitive operator actions on the client require local device authentication on supported platforms:
  - `clients/shamell_flutter/lib/core/rides/ride_operator_console_page.dart`
  - `clients/shamell_flutter/lib/core/superadmin_control_access_page.dart`
  - `clients/shamell_flutter/lib/src/main_ops.dart`
- Regulator-facing extraction can be routed through a dedicated snapshot database instead of live reads:
  - `docs/security/regulatory-reporting-access.md`
  - `scripts/regulatory_reporting_snapshot.sh`
  - `ops/pi/postgres/regulatory_reporting_bootstrap.sql`

## 4. Monitoring, Alerting, and Incident Response

Confirmed from code and ops artifacts:

- Runtime security alert ingestion exists in the BFF:
  - `POST /internal/security/alerts`
  - config and enforcement in `services_rs/bff_gateway/src/main.rs`, `config.rs`, `auth.rs`, and `handlers.rs`
- Periodic security event evaluation is automated:
  - `scripts/security_events_report.sh`
  - `ops/hetzner/systemd/shamell-security-events-report.service`
  - `ops/hetzner/systemd/shamell-security-events-report.timer`
- Periodic ride operational audit exists:
  - `scripts/ride_ops_report.sh`
  - `ops/hetzner/systemd/shamell-ride-ops-report.service`
  - `ops/hetzner/systemd/shamell-ride-ops-report.timer`
- Sensitive ride and admin mutations emit structured security events with hashed identifiers:
  - `services_rs/bff_gateway/src/handlers.rs`
  - `services_rs/bff_gateway/src/auth.rs`
- Backup execution is automated and journaled via a dedicated systemd service/timer:
  - `ops/hetzner/systemd/shamell-ride-db-backup.service`
  - `ops/hetzner/systemd/shamell-ride-db-backup.timer`
- Incident handling guidance is versioned in:
  - `docs/security/incident-runbook.md`

## 5. Deployment Requirements Recorded in Repository

Confirmed from code:

- Production and staging env templates now require explicit ride/auth backup configuration and storage-encryption declaration:
  - `ops/pi/env.prod.example`
  - `ops/pi/env.staging.example`
- Deployment invariants validate the presence of these controls:
  - `scripts/check_deploy_env_invariants.sh`

Operational expectation:

- Use encrypted backups for all ride/auth database snapshots.
- Keep host storage encryption enabled for the live database volume.
- Keep security event timer, ride ops timer, and backup timer enabled in production.
