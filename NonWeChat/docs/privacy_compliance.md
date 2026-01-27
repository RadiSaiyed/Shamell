# Shamell Privacy & Data Requests

This document describes how Shamell exposes privacy–related flows at the API
level and how they connect to the existing audit and guardrail model.

## 1. Data Subject Requests (DSR)

Two lightweight BFF endpoints exist for recording user–initiated privacy
requests:

- `POST /me/dsr/export`
- `POST /me/dsr/delete`

Both endpoints:

- Require authentication (session cookie or `X-Test-Phone` in test mode).
- Accept a small JSON body (optional):
  - `reason` – free–text description provided by the user.
  - `contact` – how to reach the user for the export/deletion (e.g. email).
- Do **not** perform export or deletion themselves.
- Emit an audit event via `_audit`:
  - `action="dsr_export_request"` or `action="dsr_delete_request"`.
  - `phone` is the authenticated phone number.
  - `reason` and `contact` are included as structured fields.

These audit events can be picked up by backoffice tooling or manual processes
to fulfil the actual export/deletion, which will typically involve:

- Payments ledger (wallet + txns).
- Taxi/Bus/Stays/Food bookings.
- Chat messages, etc.

The exact scope of deletion/export is a product/regulatory decision; Shamell
provides the API hook and traceability.

## 2. Retention & Logs

Shamell’s audit and metrics data is designed to be:

- **Ephemeral in process**:
  - `_AUDIT_EVENTS` and `_METRICS` are in–memory ring buffers exposed via
    `/admin/metrics` and `/admin/guardrails`.
- **Persisted outside the app**:
  - JSON logs (including `shamell.audit` events) are typically shipped to a
    central log store (e.g. GCS, S3, Loki, …).

Retention policies for these external stores should be configured at the
infrastructure level. As a starting point:

- Metrics and generic logs: 30–90 days.
- Audit logs: 180–365 days (depending on regulatory and business needs).

When implementing “hard delete” for a user, consider:

- Whether audit logs should be fully removed, or pseudonymised
  (e.g. phone numbers hashed), depending on local regulation.
- How long payment/ledger records must be retained for accounting.

Shamell’s codebase keeps secrets/OTPs out of logs by design; audit entries
contain only IDs, roles and amounts, never raw tokens or codes.

