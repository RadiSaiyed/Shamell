\set ON_ERROR_STOP on

BEGIN;

CREATE SCHEMA IF NOT EXISTS regulatory_snapshot;
CREATE SCHEMA IF NOT EXISTS regulatory_reporting;

CREATE TABLE IF NOT EXISTS regulatory_snapshot.snapshot_runs (
    snapshot_id TEXT PRIMARY KEY,
    source_database TEXT NOT NULL,
    source_schema TEXT NOT NULL DEFAULT 'regulatory_reporting',
    source_view_set TEXT NOT NULL DEFAULT 'v1',
    snapshot_cutoff_at TIMESTAMPTZ NOT NULL,
    salt_fingerprint TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'loading',
    trip_rows BIGINT NOT NULL DEFAULT 0,
    driver_rows BIGINT NOT NULL DEFAULT 0,
    fare_rows BIGINT NOT NULL DEFAULT 0,
    incident_rows BIGINT NOT NULL DEFAULT 0,
    audit_rows BIGINT NOT NULL DEFAULT 0,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    exported_by TEXT NOT NULL,
    manifest_path TEXT,
    manifest_sha256 TEXT,
    manifest_signature_path TEXT,
    error_detail TEXT,
    CONSTRAINT chk_regulatory_snapshot_runs_status_known
        CHECK (status IN ('loading', 'ready', 'failed')),
    CONSTRAINT chk_regulatory_snapshot_runs_trip_rows_nonnegative
        CHECK (trip_rows >= 0),
    CONSTRAINT chk_regulatory_snapshot_runs_driver_rows_nonnegative
        CHECK (driver_rows >= 0),
    CONSTRAINT chk_regulatory_snapshot_runs_fare_rows_nonnegative
        CHECK (fare_rows >= 0),
    CONSTRAINT chk_regulatory_snapshot_runs_incident_rows_nonnegative
        CHECK (incident_rows >= 0),
    CONSTRAINT chk_regulatory_snapshot_runs_audit_rows_nonnegative
        CHECK (audit_rows >= 0)
);

CREATE INDEX IF NOT EXISTS idx_regulatory_snapshot_runs_status_completed
    ON regulatory_snapshot.snapshot_runs(status, completed_at DESC, started_at DESC);

CREATE TABLE IF NOT EXISTS regulatory_snapshot.trips (
    snapshot_id TEXT NOT NULL REFERENCES regulatory_snapshot.snapshot_runs(snapshot_id) ON DELETE CASCADE,
    trip_id TEXT NOT NULL,
    rider_id TEXT,
    driver_id TEXT,
    request_time TIMESTAMPTZ,
    accept_time TIMESTAMPTZ,
    pickup_time TIMESTAMPTZ,
    dropoff_time TIMESTAMPTZ,
    pickup_zone TEXT,
    dropoff_zone TEXT,
    trip_status TEXT NOT NULL,
    cancellation_actor TEXT,
    cancellation_reason TEXT,
    fare_estimate_minor_units BIGINT NOT NULL,
    fare_amount NUMERIC(18,2) NOT NULL,
    currency TEXT,
    surge_multiplier NUMERIC(6,2),
    distance_km NUMERIC(10,2),
    duration_sec BIGINT,
    ride_class TEXT NOT NULL,
    PRIMARY KEY (snapshot_id, trip_id)
);

CREATE INDEX IF NOT EXISTS idx_regulatory_snapshot_trips_snapshot_status
    ON regulatory_snapshot.trips(snapshot_id, trip_status, request_time DESC);

CREATE TABLE IF NOT EXISTS regulatory_snapshot.drivers (
    snapshot_id TEXT NOT NULL REFERENCES regulatory_snapshot.snapshot_runs(snapshot_id) ON DELETE CASCADE,
    driver_id TEXT NOT NULL,
    onboarding_status TEXT NOT NULL,
    license_verification_status TEXT NOT NULL,
    insurance_verification_status TEXT NOT NULL,
    vehicle_registration_status TEXT NOT NULL,
    identity_verification_status TEXT NOT NULL,
    availability_status TEXT NOT NULL,
    activation_date TIMESTAMPTZ,
    suspension_status TEXT NOT NULL,
    last_seen_at TIMESTAMPTZ,
    last_trip_activity_at TIMESTAMPTZ,
    latest_ride_class TEXT,
    PRIMARY KEY (snapshot_id, driver_id)
);

CREATE INDEX IF NOT EXISTS idx_regulatory_snapshot_drivers_snapshot_status
    ON regulatory_snapshot.drivers(snapshot_id, onboarding_status, suspension_status);

CREATE TABLE IF NOT EXISTS regulatory_snapshot.fares (
    snapshot_id TEXT NOT NULL REFERENCES regulatory_snapshot.snapshot_runs(snapshot_id) ON DELETE CASCADE,
    ride_class TEXT NOT NULL,
    base_fare_minor_units BIGINT NOT NULL,
    per_km_minor_units BIGINT NOT NULL,
    per_minute_minor_units BIGINT NOT NULL,
    traffic_delay_per_minute_minor_units BIGINT NOT NULL,
    booking_fee_minor_units BIGINT NOT NULL,
    minimum_fare_minor_units BIGINT NOT NULL,
    driver_share_bps BIGINT NOT NULL,
    updated_at TIMESTAMPTZ,
    PRIMARY KEY (snapshot_id, ride_class)
);

CREATE TABLE IF NOT EXISTS regulatory_snapshot.incidents (
    snapshot_id TEXT NOT NULL REFERENCES regulatory_snapshot.snapshot_runs(snapshot_id) ON DELETE CASCADE,
    incident_id TEXT NOT NULL,
    trip_id TEXT,
    rider_id TEXT,
    driver_id TEXT,
    category TEXT NOT NULL,
    created_at TIMESTAMPTZ,
    resolution_status TEXT NOT NULL,
    resolution_time_sec BIGINT,
    escalation_flag BOOLEAN NOT NULL,
    trip_status TEXT,
    pickup_zone TEXT,
    dropoff_zone TEXT,
    PRIMARY KEY (snapshot_id, incident_id)
);

CREATE INDEX IF NOT EXISTS idx_regulatory_snapshot_incidents_snapshot_category
    ON regulatory_snapshot.incidents(snapshot_id, category, resolution_status, created_at DESC);

CREATE TABLE IF NOT EXISTS regulatory_snapshot.audit_log (
    snapshot_id TEXT NOT NULL REFERENCES regulatory_snapshot.snapshot_runs(snapshot_id) ON DELETE CASCADE,
    audit_id TEXT NOT NULL,
    trip_id TEXT,
    actor_id TEXT,
    actor_type TEXT NOT NULL,
    event_kind TEXT NOT NULL,
    trip_status TEXT,
    event_time TIMESTAMPTZ,
    note_class TEXT,
    redaction_reason TEXT,
    PRIMARY KEY (snapshot_id, audit_id)
);

CREATE INDEX IF NOT EXISTS idx_regulatory_snapshot_audit_log_snapshot_event
    ON regulatory_snapshot.audit_log(snapshot_id, event_kind, event_time DESC);

CREATE OR REPLACE VIEW regulatory_reporting.vw_reg_trips AS
WITH current_snapshot AS (
    SELECT snapshot_id, snapshot_cutoff_at
    FROM regulatory_snapshot.snapshot_runs
    WHERE status = 'ready'
    ORDER BY completed_at DESC NULLS LAST, started_at DESC, snapshot_id DESC
    LIMIT 1
)
SELECT
    trip.snapshot_id,
    current_snapshot.snapshot_cutoff_at,
    trip.trip_id,
    trip.rider_id,
    trip.driver_id,
    trip.request_time,
    trip.accept_time,
    trip.pickup_time,
    trip.dropoff_time,
    trip.pickup_zone,
    trip.dropoff_zone,
    trip.trip_status,
    trip.cancellation_actor,
    trip.cancellation_reason,
    trip.fare_estimate_minor_units,
    trip.fare_amount,
    trip.currency,
    trip.surge_multiplier,
    trip.distance_km,
    trip.duration_sec,
    trip.ride_class
FROM regulatory_snapshot.trips trip
JOIN current_snapshot
    ON current_snapshot.snapshot_id = trip.snapshot_id;

CREATE OR REPLACE VIEW regulatory_reporting.vw_reg_drivers AS
WITH current_snapshot AS (
    SELECT snapshot_id, snapshot_cutoff_at
    FROM regulatory_snapshot.snapshot_runs
    WHERE status = 'ready'
    ORDER BY completed_at DESC NULLS LAST, started_at DESC, snapshot_id DESC
    LIMIT 1
)
SELECT
    driver.snapshot_id,
    current_snapshot.snapshot_cutoff_at,
    driver.driver_id,
    driver.onboarding_status,
    driver.license_verification_status,
    driver.insurance_verification_status,
    driver.vehicle_registration_status,
    driver.identity_verification_status,
    driver.availability_status,
    driver.activation_date,
    driver.suspension_status,
    driver.last_seen_at,
    driver.last_trip_activity_at,
    driver.latest_ride_class
FROM regulatory_snapshot.drivers driver
JOIN current_snapshot
    ON current_snapshot.snapshot_id = driver.snapshot_id;

CREATE OR REPLACE VIEW regulatory_reporting.vw_reg_fares AS
WITH current_snapshot AS (
    SELECT snapshot_id, snapshot_cutoff_at
    FROM regulatory_snapshot.snapshot_runs
    WHERE status = 'ready'
    ORDER BY completed_at DESC NULLS LAST, started_at DESC, snapshot_id DESC
    LIMIT 1
)
SELECT
    fare.snapshot_id,
    current_snapshot.snapshot_cutoff_at,
    fare.ride_class,
    fare.base_fare_minor_units,
    fare.per_km_minor_units,
    fare.per_minute_minor_units,
    fare.traffic_delay_per_minute_minor_units,
    fare.booking_fee_minor_units,
    fare.minimum_fare_minor_units,
    fare.driver_share_bps,
    fare.updated_at
FROM regulatory_snapshot.fares fare
JOIN current_snapshot
    ON current_snapshot.snapshot_id = fare.snapshot_id;

CREATE OR REPLACE VIEW regulatory_reporting.vw_reg_incidents AS
WITH current_snapshot AS (
    SELECT snapshot_id, snapshot_cutoff_at
    FROM regulatory_snapshot.snapshot_runs
    WHERE status = 'ready'
    ORDER BY completed_at DESC NULLS LAST, started_at DESC, snapshot_id DESC
    LIMIT 1
)
SELECT
    incident.snapshot_id,
    current_snapshot.snapshot_cutoff_at,
    incident.incident_id,
    incident.trip_id,
    incident.rider_id,
    incident.driver_id,
    incident.category,
    incident.created_at,
    incident.resolution_status,
    incident.resolution_time_sec,
    incident.escalation_flag,
    incident.trip_status,
    incident.pickup_zone,
    incident.dropoff_zone
FROM regulatory_snapshot.incidents incident
JOIN current_snapshot
    ON current_snapshot.snapshot_id = incident.snapshot_id;

CREATE OR REPLACE VIEW regulatory_reporting.vw_reg_audit_log AS
WITH current_snapshot AS (
    SELECT snapshot_id, snapshot_cutoff_at
    FROM regulatory_snapshot.snapshot_runs
    WHERE status = 'ready'
    ORDER BY completed_at DESC NULLS LAST, started_at DESC, snapshot_id DESC
    LIMIT 1
)
SELECT
    audit.snapshot_id,
    current_snapshot.snapshot_cutoff_at,
    audit.audit_id,
    audit.trip_id,
    audit.actor_id,
    audit.actor_type,
    audit.event_kind,
    audit.trip_status,
    audit.event_time,
    audit.note_class,
    audit.redaction_reason
FROM regulatory_snapshot.audit_log audit
JOIN current_snapshot
    ON current_snapshot.snapshot_id = audit.snapshot_id;

REVOKE ALL ON SCHEMA regulatory_snapshot FROM PUBLIC;
REVOKE ALL ON SCHEMA regulatory_reporting FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA regulatory_snapshot FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA regulatory_reporting FROM PUBLIC;

COMMIT;

SELECT format(
    'DO $$ BEGIN
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = %L) THEN
            ALTER ROLE %I WITH LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
        ELSE
            CREATE ROLE %I WITH LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
        END IF;
    END $$;',
    :'regulator_role',
    :'regulator_role',
    :'regulator_password',
    :'regulator_role',
    :'regulator_password'
) \gexec

SELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC', current_database()) \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', current_database(), :'regulator_role') \gexec
SELECT format(
    'ALTER ROLE %I IN DATABASE %I SET default_transaction_read_only = on',
    :'regulator_role',
    current_database()
) \gexec
SELECT format(
    'ALTER ROLE %I IN DATABASE %I SET search_path = regulatory_reporting',
    :'regulator_role',
    current_database()
) \gexec
SELECT format('GRANT USAGE ON SCHEMA regulatory_reporting TO %I', :'regulator_role') \gexec
SELECT format('GRANT SELECT ON ALL TABLES IN SCHEMA regulatory_reporting TO %I', :'regulator_role') \gexec
SELECT format(
    'ALTER DEFAULT PRIVILEGES IN SCHEMA regulatory_reporting GRANT SELECT ON TABLES TO %I',
    :'regulator_role'
) \gexec
SELECT format('REVOKE ALL ON SCHEMA regulatory_snapshot FROM %I', :'regulator_role') \gexec
SELECT format('REVOKE ALL ON ALL TABLES IN SCHEMA regulatory_snapshot FROM %I', :'regulator_role') \gexec
