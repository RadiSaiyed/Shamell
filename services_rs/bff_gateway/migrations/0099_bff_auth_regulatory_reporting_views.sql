CREATE SCHEMA IF NOT EXISTS regulatory_reporting;

REVOKE ALL ON SCHEMA regulatory_reporting FROM PUBLIC;

CREATE OR REPLACE FUNCTION regulatory_reporting.pseudonymize_text(raw_value TEXT)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
    SELECT CASE
        WHEN raw_value IS NULL OR btrim(raw_value) = '' THEN NULL
        ELSE 'psn_' || substr(
            md5(
                COALESCE(
                    NULLIF(current_setting('app.reg_reporting_salt', true), ''),
                    'dev-reg-reporting-salt'
                ) || ':' || btrim(raw_value)
            ),
            1,
            24
        )
    END
$$;

CREATE OR REPLACE FUNCTION regulatory_reporting.rounded_minute(raw_value TIMESTAMPTZ)
RETURNS TIMESTAMPTZ
LANGUAGE sql
STABLE
AS $$
    SELECT CASE
        WHEN raw_value IS NULL THEN NULL
        ELSE date_trunc('minute', raw_value)
    END
$$;

CREATE OR REPLACE FUNCTION regulatory_reporting.zone_bucket(lat DOUBLE PRECISION, lon DOUBLE PRECISION)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN lat IS NULL OR lon IS NULL THEN NULL
        ELSE format(
            'zone_%s_%s',
            round(lat::numeric, 1),
            round(lon::numeric, 1)
        )
    END
$$;

CREATE OR REPLACE FUNCTION regulatory_reporting.approx_distance_km(
    pickup_lat DOUBLE PRECISION,
    pickup_lon DOUBLE PRECISION,
    destination_lat DOUBLE PRECISION,
    destination_lon DOUBLE PRECISION
)
RETURNS NUMERIC(10,2)
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN pickup_lat IS NULL
            OR pickup_lon IS NULL
            OR destination_lat IS NULL
            OR destination_lon IS NULL
        THEN NULL
        ELSE round(
            (
                6371.0 * 2.0 * asin(
                    sqrt(
                        power(sin(radians((destination_lat - pickup_lat) / 2.0)), 2)
                        + cos(radians(pickup_lat))
                        * cos(radians(destination_lat))
                        * power(sin(radians((destination_lon - pickup_lon) / 2.0)), 2)
                    )
                )
            )::numeric,
            2
        )
    END
$$;

CREATE OR REPLACE VIEW regulatory_reporting.vw_reg_trips AS
SELECT
    trip.ride_id AS trip_id,
    regulatory_reporting.pseudonymize_text(trip.rider_account_id) AS rider_id,
    regulatory_reporting.pseudonymize_text(trip.driver_account_id) AS driver_id,
    regulatory_reporting.rounded_minute(trip.created_at) AS request_time,
    regulatory_reporting.rounded_minute(trip.assigned_at) AS accept_time,
    regulatory_reporting.rounded_minute(trip.started_at) AS pickup_time,
    regulatory_reporting.rounded_minute(
        COALESCE(trip.completed_at, trip.terminal_at)
    ) AS dropoff_time,
    regulatory_reporting.zone_bucket(trip.pickup_lat, trip.pickup_lon) AS pickup_zone,
    regulatory_reporting.zone_bucket(
        trip.destination_lat,
        trip.destination_lon
    ) AS dropoff_zone,
    trip.status AS trip_status,
    CASE
        WHEN trip.status <> 'cancelled' THEN NULL
        WHEN COALESCE(trip.cancel_reason_code, '') LIKE 'rider_%' THEN 'rider'
        WHEN COALESCE(trip.cancel_reason_code, '') LIKE 'driver_%' THEN 'driver'
        WHEN COALESCE(trip.cancel_reason_code, '') LIKE 'operator_%' THEN 'operator'
        WHEN COALESCE(trip.cancel_reason_code, '') LIKE 'system_%' THEN 'system'
        WHEN trip.driver_account_id IS NULL THEN 'rider_or_system'
        ELSE 'unknown'
    END AS cancellation_actor,
    NULLIF(trip.cancel_reason_code, '') AS cancellation_reason,
    trip.fare_estimate_cents AS fare_estimate_minor_units,
    round((trip.fare_estimate_cents::numeric / 100.0), 2) AS fare_amount,
    NULL::TEXT AS currency,
    NULL::NUMERIC(6,2) AS surge_multiplier,
    regulatory_reporting.approx_distance_km(
        trip.pickup_lat,
        trip.pickup_lon,
        trip.destination_lat,
        trip.destination_lon
    ) AS distance_km,
    CASE
        WHEN trip.started_at IS NULL OR COALESCE(trip.completed_at, trip.terminal_at) IS NULL THEN NULL
        WHEN COALESCE(trip.completed_at, trip.terminal_at) < trip.started_at THEN NULL
        ELSE EXTRACT(
            EPOCH FROM (COALESCE(trip.completed_at, trip.terminal_at) - trip.started_at)
        )::BIGINT
    END AS duration_sec,
    trip.ride_class
FROM auth_ride_trips trip;

CREATE OR REPLACE VIEW regulatory_reporting.vw_reg_drivers AS
WITH driver_population AS (
    SELECT driver_account_id
    FROM auth_ride_driver_presence
    UNION
    SELECT driver_account_id
    FROM auth_ride_driver_documents
    UNION
    SELECT driver_account_id
    FROM auth_ride_trips
    WHERE driver_account_id IS NOT NULL
),
document_status AS (
    SELECT
        driver_account_id,
        max(
            CASE
                WHEN document_type = 'driver_license' THEN
                    CASE
                        WHEN expires_at IS NOT NULL AND expires_at < NOW() THEN 'expired'
                        ELSE status
                    END
            END
        ) AS license_verification_status,
        max(
            CASE
                WHEN document_type = 'insurance' THEN
                    CASE
                        WHEN expires_at IS NOT NULL AND expires_at < NOW() THEN 'expired'
                        ELSE status
                    END
            END
        ) AS insurance_verification_status,
        max(
            CASE
                WHEN document_type = 'vehicle_registration' THEN
                    CASE
                        WHEN expires_at IS NOT NULL AND expires_at < NOW() THEN 'expired'
                        ELSE status
                    END
            END
        ) AS vehicle_registration_status,
        max(
            CASE
                WHEN document_type = 'identity_card' THEN
                    CASE
                        WHEN expires_at IS NOT NULL AND expires_at < NOW() THEN 'expired'
                        ELSE status
                    END
            END
        ) AS identity_verification_status,
        max(CASE WHEN document_type = 'driver_license' THEN reviewed_at END) AS license_reviewed_at,
        max(CASE WHEN document_type = 'insurance' THEN reviewed_at END) AS insurance_reviewed_at,
        max(CASE WHEN document_type = 'vehicle_registration' THEN reviewed_at END) AS vehicle_registration_reviewed_at,
        max(CASE WHEN document_type = 'identity_card' THEN reviewed_at END) AS identity_reviewed_at
    FROM auth_ride_driver_documents
    GROUP BY driver_account_id
),
driver_trip_summary AS (
    SELECT DISTINCT ON (driver_account_id)
        driver_account_id,
        ride_class AS latest_ride_class,
        updated_at AS last_trip_updated_at
    FROM auth_ride_trips
    WHERE driver_account_id IS NOT NULL
    ORDER BY driver_account_id, updated_at DESC, id DESC
)
SELECT
    regulatory_reporting.pseudonymize_text(pop.driver_account_id) AS driver_id,
    CASE
        WHEN doc.driver_account_id IS NULL THEN 'unverified'
        WHEN COALESCE(doc.license_verification_status, 'missing') IN ('rejected', 'expired')
            OR COALESCE(doc.insurance_verification_status, 'missing') IN ('rejected', 'expired')
            OR COALESCE(doc.vehicle_registration_status, 'missing') IN ('rejected', 'expired')
            OR COALESCE(doc.identity_verification_status, 'missing') IN ('rejected', 'expired')
        THEN 'restricted'
        WHEN COALESCE(doc.license_verification_status, 'missing') = 'approved'
            AND COALESCE(doc.insurance_verification_status, 'missing') = 'approved'
            AND COALESCE(doc.vehicle_registration_status, 'missing') = 'approved'
            AND COALESCE(doc.identity_verification_status, 'missing') = 'approved'
        THEN 'active'
        WHEN COALESCE(doc.license_verification_status, 'missing') = 'pending'
            OR COALESCE(doc.insurance_verification_status, 'missing') = 'pending'
            OR COALESCE(doc.vehicle_registration_status, 'missing') = 'pending'
            OR COALESCE(doc.identity_verification_status, 'missing') = 'pending'
        THEN 'pending_review'
        ELSE 'incomplete'
    END AS onboarding_status,
    COALESCE(doc.license_verification_status, 'missing') AS license_verification_status,
    COALESCE(doc.insurance_verification_status, 'missing') AS insurance_verification_status,
    COALESCE(doc.vehicle_registration_status, 'missing') AS vehicle_registration_status,
    COALESCE(doc.identity_verification_status, 'missing') AS identity_verification_status,
    COALESCE(presence.availability_status, 'offline') AS availability_status,
    regulatory_reporting.rounded_minute(
        CASE
            WHEN COALESCE(doc.license_verification_status, 'missing') = 'approved'
                AND COALESCE(doc.insurance_verification_status, 'missing') = 'approved'
                AND COALESCE(doc.vehicle_registration_status, 'missing') = 'approved'
                AND COALESCE(doc.identity_verification_status, 'missing') = 'approved'
            THEN GREATEST(
                COALESCE(doc.license_reviewed_at, '-infinity'::timestamptz),
                COALESCE(doc.insurance_reviewed_at, '-infinity'::timestamptz),
                COALESCE(doc.vehicle_registration_reviewed_at, '-infinity'::timestamptz),
                COALESCE(doc.identity_reviewed_at, '-infinity'::timestamptz)
            )
        END
    ) AS activation_date,
    CASE
        WHEN COALESCE(doc.license_verification_status, 'missing') = 'rejected'
            OR COALESCE(doc.insurance_verification_status, 'missing') = 'rejected'
            OR COALESCE(doc.vehicle_registration_status, 'missing') = 'rejected'
            OR COALESCE(doc.identity_verification_status, 'missing') = 'rejected'
        THEN 'suspended'
        WHEN COALESCE(doc.license_verification_status, 'missing') = 'expired'
            OR COALESCE(doc.insurance_verification_status, 'missing') = 'expired'
            OR COALESCE(doc.vehicle_registration_status, 'missing') = 'expired'
            OR COALESCE(doc.identity_verification_status, 'missing') = 'expired'
        THEN 'document_expired'
        ELSE 'clear'
    END AS suspension_status,
    regulatory_reporting.rounded_minute(presence.last_seen_at) AS last_seen_at,
    regulatory_reporting.rounded_minute(summary.last_trip_updated_at) AS last_trip_activity_at,
    summary.latest_ride_class
FROM driver_population pop
LEFT JOIN document_status doc
    ON doc.driver_account_id = pop.driver_account_id
LEFT JOIN auth_ride_driver_presence presence
    ON presence.driver_account_id = pop.driver_account_id
LEFT JOIN driver_trip_summary summary
    ON summary.driver_account_id = pop.driver_account_id;

CREATE OR REPLACE VIEW regulatory_reporting.vw_reg_fares AS
SELECT
    ride_class,
    base_fare_minor_units,
    per_km_minor_units,
    per_minute_minor_units,
    traffic_delay_per_minute_minor_units,
    booking_fee_minor_units,
    minimum_fare_minor_units,
    driver_share_bps,
    regulatory_reporting.rounded_minute(updated_at) AS updated_at
FROM auth_ride_pricing_policies;

CREATE OR REPLACE VIEW regulatory_reporting.vw_reg_incidents AS
SELECT
    ticket.ticket_id AS incident_id,
    ticket.ride_id AS trip_id,
    regulatory_reporting.pseudonymize_text(ticket.rider_account_id) AS rider_id,
    regulatory_reporting.pseudonymize_text(trip.driver_account_id) AS driver_id,
    ticket.ticket_category AS category,
    regulatory_reporting.rounded_minute(ticket.created_at) AS created_at,
    ticket.status AS resolution_status,
    CASE
        WHEN ticket.resolved_at IS NULL OR ticket.resolved_at < ticket.created_at THEN NULL
        ELSE EXTRACT(EPOCH FROM (ticket.resolved_at - ticket.created_at))::BIGINT
    END AS resolution_time_sec,
    (ticket.ticket_category = 'safety') AS escalation_flag,
    trip.status AS trip_status,
    regulatory_reporting.zone_bucket(trip.pickup_lat, trip.pickup_lon) AS pickup_zone,
    regulatory_reporting.zone_bucket(
        trip.destination_lat,
        trip.destination_lon
    ) AS dropoff_zone
FROM auth_ride_support_tickets ticket
LEFT JOIN auth_ride_trips trip
    ON trip.ride_id = ticket.ride_id;

CREATE OR REPLACE VIEW regulatory_reporting.vw_reg_audit_log AS
SELECT
    format('%s:%s', event.ride_id, event.id) AS audit_id,
    event.ride_id AS trip_id,
    regulatory_reporting.pseudonymize_text(event.actor_account_id) AS actor_id,
    CASE
        WHEN event.event_kind = 'driver_location' THEN 'driver'
        WHEN event.event_kind = 'operator_note' THEN 'operator'
        WHEN event.actor_account_id IS NULL THEN 'system'
        ELSE 'account'
    END AS actor_type,
    event.event_kind,
    event.status AS trip_status,
    regulatory_reporting.rounded_minute(event.created_at) AS event_time,
    CASE
        WHEN COALESCE(event.note, '') <> '' THEN 'note_present'
        ELSE NULL
    END AS note_class,
    CASE
        WHEN event.event_kind = 'driver_location' THEN 'telemetry_redacted'
        WHEN event.event_kind = 'operator_note' THEN 'operator_note_redacted'
        ELSE NULL
    END AS redaction_reason
FROM auth_ride_trip_tracking_events event;
