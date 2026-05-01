ALTER TABLE auth_ride_trips
    ADD COLUMN IF NOT EXISTS pickup_label TEXT,
    ADD COLUMN IF NOT EXISTS destination_label TEXT,
    ADD COLUMN IF NOT EXISTS pickup_lat DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS pickup_lon DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS destination_lat DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS destination_lon DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS cancel_reason_code TEXT,
    ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS arriving_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS arrived_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

UPDATE auth_ride_trips
SET
    pickup_label = COALESCE(NULLIF(pickup_label, ''), pickup_text),
    destination_label = COALESCE(NULLIF(destination_label, ''), destination_text),
    assigned_at = COALESCE(
        assigned_at,
        CASE
            WHEN status IN (
                'driver_assigned',
                'driver_arriving',
                'driver_arrived',
                'trip_started',
                'trip_in_progress',
                'payment_failed',
                'trip_completed',
                'cancelled'
            ) AND driver_account_id IS NOT NULL
            THEN status_updated_at
        END
    ),
    arriving_at = COALESCE(
        arriving_at,
        CASE
            WHEN status IN (
                'driver_arriving',
                'driver_arrived',
                'trip_started',
                'trip_in_progress',
                'payment_failed',
                'trip_completed',
                'cancelled'
            )
            THEN status_updated_at
        END
    ),
    arrived_at = COALESCE(
        arrived_at,
        CASE
            WHEN status IN (
                'driver_arrived',
                'trip_started',
                'trip_in_progress',
                'payment_failed',
                'trip_completed',
                'cancelled'
            )
            THEN status_updated_at
        END
    ),
    started_at = COALESCE(
        started_at,
        CASE
            WHEN status IN (
                'trip_started',
                'trip_in_progress',
                'payment_failed',
                'trip_completed',
                'cancelled'
            )
            THEN status_updated_at
        END
    ),
    completed_at = COALESCE(
        completed_at,
        CASE
            WHEN status = 'trip_completed'
            THEN COALESCE(terminal_at, status_updated_at, updated_at)
        END
    );

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_auth_ride_trips_pickup_location_pair'
    ) THEN
        ALTER TABLE auth_ride_trips
            ADD CONSTRAINT chk_auth_ride_trips_pickup_location_pair
            CHECK (
                (pickup_lat IS NULL AND pickup_lon IS NULL)
                OR (pickup_lat IS NOT NULL AND pickup_lon IS NOT NULL)
            );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_auth_ride_trips_destination_location_pair'
    ) THEN
        ALTER TABLE auth_ride_trips
            ADD CONSTRAINT chk_auth_ride_trips_destination_location_pair
            CHECK (
                (destination_lat IS NULL AND destination_lon IS NULL)
                OR (destination_lat IS NOT NULL AND destination_lon IS NOT NULL)
            );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_auth_ride_trips_pickup_lat_bounds'
    ) THEN
        ALTER TABLE auth_ride_trips
            ADD CONSTRAINT chk_auth_ride_trips_pickup_lat_bounds
            CHECK (pickup_lat IS NULL OR (pickup_lat >= -90 AND pickup_lat <= 90));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_auth_ride_trips_pickup_lon_bounds'
    ) THEN
        ALTER TABLE auth_ride_trips
            ADD CONSTRAINT chk_auth_ride_trips_pickup_lon_bounds
            CHECK (pickup_lon IS NULL OR (pickup_lon >= -180 AND pickup_lon <= 180));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_auth_ride_trips_destination_lat_bounds'
    ) THEN
        ALTER TABLE auth_ride_trips
            ADD CONSTRAINT chk_auth_ride_trips_destination_lat_bounds
            CHECK (
                destination_lat IS NULL
                OR (destination_lat >= -90 AND destination_lat <= 90)
            );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_auth_ride_trips_destination_lon_bounds'
    ) THEN
        ALTER TABLE auth_ride_trips
            ADD CONSTRAINT chk_auth_ride_trips_destination_lon_bounds
            CHECK (
                destination_lon IS NULL
                OR (destination_lon >= -180 AND destination_lon <= 180)
            );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_auth_ride_trips_cancel_reason_code_len'
    ) THEN
        ALTER TABLE auth_ride_trips
            ADD CONSTRAINT chk_auth_ride_trips_cancel_reason_code_len
            CHECK (
                cancel_reason_code IS NULL
                OR char_length(cancel_reason_code) <= 64
            );
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_auth_ride_trips_status_created
    ON auth_ride_trips(status, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_auth_ride_driver_presence_status_last_seen
    ON auth_ride_driver_presence(availability_status, last_seen_at DESC);

INSERT INTO auth_ride_trip_live_state (
    ride_id,
    rider_account_id,
    driver_account_id,
    driver_name,
    car_plate,
    stage,
    driver_location_lat,
    driver_location_lon,
    accuracy_meters,
    speed_kmh,
    heading_degrees,
    last_location_at,
    updated_at
)
SELECT
    trip.ride_id,
    trip.rider_account_id,
    trip.driver_account_id,
    trip.driver_name,
    trip.car_plate,
    trip.status,
    last_location.location_lat,
    last_location.location_lon,
    last_location.accuracy_meters,
    last_location.speed_kmh,
    last_location.heading_degrees,
    last_location.created_at,
    NOW()
FROM auth_ride_trips trip
LEFT JOIN LATERAL (
    SELECT
        event.location_lat,
        event.location_lon,
        event.accuracy_meters,
        event.speed_kmh,
        event.heading_degrees,
        event.created_at
    FROM auth_ride_trip_tracking_events event
    WHERE event.ride_id = trip.ride_id
      AND event.event_kind = 'driver_location'
      AND event.location_lat IS NOT NULL
      AND event.location_lon IS NOT NULL
    ORDER BY event.created_at DESC, event.id DESC
    LIMIT 1
) AS last_location ON TRUE
WHERE NOT EXISTS (
    SELECT 1
    FROM auth_ride_trip_live_state live
    WHERE live.ride_id = trip.ride_id
);
