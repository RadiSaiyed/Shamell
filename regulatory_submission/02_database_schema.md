# Database Schema

## 1. Store Inventory

| Store | Role | Evidence | Classification |
| --- | --- | --- | --- |
| `postgresql_core_store` | Authoritative system of record for identity, sessions, rides, driver presence, driver documents, support cases, tracking, and pricing | `services_rs/bff_gateway/migrations/*.sql` | Confirmed from code |
| `mobile_secure_storage` | Client-side protected persistence for session state, biometric preferences, device-scoped identity state | `clients/shamell_flutter/lib/core/*.dart` | Confirmed from code |
| `mobile_shared_preferences` | Client-side convenience persistence for scoped non-authoritative state | `clients/shamell_flutter/lib/core/*.dart` | Confirmed from code |
| `encrypted_backup_artifacts` | Encrypted backup copies of the authoritative ride/auth PostgreSQL store | `scripts/ride_db_backup.sh`, `ops/hetzner/systemd/shamell-ride-db-backup.*` | Confirmed from code |


## 2. Canonical Entity Model

### Identity and Session Layer

- `auth_accounts`: canonical account identifier, human-facing user identifier, phone, creation timestamp
- `auth_sessions`: server-side session records keyed by hashed session identifier with expiry, last-seen, revocation, and optional device binding
- `auth_user_ids`: phone-to-user-id linkage helper
- `auth_account_create_challenges`: one-time account-creation challenge state
- `auth_biometric_tokens`: device-bound biometric re-login tokens
- `auth_rate_limits`: persistent rate-limit counters
- `device_login_challenges`: QR/device-login challenge state, approval state, redemption state, replay-resistant metadata, browser binding
- `device_sessions`: device inventory bound to an account and session history

### Ride and Dispatch Layer

- `auth_ride_trips`: canonical ride record for rider, driver, route labels, route coordinates, status, and time milestones
- `auth_ride_trip_commands`: command history and idempotency record for ride mutations
- `auth_ride_dispatch_offers`: per-driver dispatch offer state and response tracking
- `auth_ride_trip_live_state`: current ride-stage and latest driver telemetry snapshot
- `auth_ride_trip_tracking_events`: append-oriented tracking history and operator notes
- `auth_ride_driver_presence`: current driver availability and latest coarse/precise presence location

### Driver Onboarding and Oversight Layer

- `auth_ride_driver_documents`: driver and vehicle-verification document inventory, review status, review note, and reviewer identity
- `auth_ride_support_tickets`: rider support cases with ride linkage, ticket text, status, and resolution metadata
- `auth_ride_pricing_policies`: ride-class pricing and fare configuration

## 3. Key Relationships and Constraints

- `auth_sessions.account_id` references `auth_accounts.account_id`.
- `device_login_challenges.account_id` references `auth_accounts.account_id`.
- `device_sessions.account_id` references `auth_accounts.account_id`.
- `auth_ride_trip_commands.ride_id`, `auth_ride_trip_tracking_events.ride_id`, `auth_ride_support_tickets.ride_id`, `auth_ride_dispatch_offers.ride_id`, and `auth_ride_trip_live_state.ride_id` reference `auth_ride_trips.ride_id`.
- `auth_ride_trips` enforces one active ride per rider by partial unique index.
- Route-coordinate pairs, latitude/longitude bounds, speed bounds, and heading bounds are enforced by check constraints.
- Driver-document tables enforce one document per driver and document type.
- Support cases and document reviews enforce status/reviewer consistency.
- Device-login challenges enforce state-transition consistency across `pending`, `approved`, and `redeemed`.

## 4. Sensitive Data Locations

- PII:
  - `auth_accounts.phone`
  - `auth_ride_trips.driver_name`
  - `auth_ride_driver_presence.driver_name`
  - `auth_ride_support_tickets.subject`
  - `auth_ride_support_tickets.body_text`
- Precise location data:
  - `auth_ride_trips.pickup_lat`, `pickup_lon`, `destination_lat`, `destination_lon`
  - `auth_ride_trip_tracking_events.location_lat`, `location_lon`
  - `auth_ride_trip_live_state.driver_location_lat`, `driver_location_lon`
  - `auth_ride_driver_presence.location_lat`, `location_lon`
- Driver verification / KYC data:
  - `auth_ride_driver_documents.document_number`
  - `auth_ride_driver_documents.document_type`
  - `auth_ride_driver_documents.review_note`
- Authentication data:
  - `auth_sessions.sid_hash`
  - `auth_biometric_tokens.token_hash`
  - `auth_account_create_challenges.token_hash`
  - `device_login_challenges.token_hash`
  - `device_login_challenges.browser_binding_hash`
  - `device_login_challenges.redeemed_client_ip_hash`
  - `device_login_challenges.redeemed_user_agent_hash`
- Audit / privileged action data:
  - `auth_ride_trip_commands.request_fingerprint`
  - `auth_ride_trip_commands.response_json`
  - `auth_ride_trip_tracking_events.metadata_json`
  - `auth_ride_support_tickets.resolution_note`
  - document-review and admin-role mutation audit events in handler code

## 5. Retention, Deletion, and Archival Behavior

- Auth/session maintenance windows exist for session cleanup, device-login cleanup, device-session retention, and rate-limit retention in `services_rs/bff_gateway/src/auth.rs`.
- Repository governance files state that hard-delete automation is not required for ride records.
- Encrypted backup artifacts are rotated by retention days in `scripts/ride_db_backup.sh`.

