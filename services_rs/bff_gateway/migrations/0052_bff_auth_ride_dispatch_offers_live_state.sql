CREATE TABLE IF NOT EXISTS auth_ride_dispatch_offers (
    id BIGSERIAL PRIMARY KEY,
    offer_id TEXT NOT NULL UNIQUE,
    ride_id TEXT NOT NULL REFERENCES auth_ride_trips(ride_id) ON DELETE CASCADE,
    driver_account_id TEXT NOT NULL,
    driver_name TEXT NOT NULL,
    car_plate TEXT NOT NULL,
    status TEXT NOT NULL,
    response_reason TEXT,
    offered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    responded_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_ride_dispatch_offers_status_known
        CHECK (status IN ('pending', 'accepted', 'rejected', 'expired', 'cancelled')),
    CONSTRAINT chk_auth_ride_dispatch_offers_expiry_after_offer
        CHECK (expires_at >= offered_at),
    CONSTRAINT chk_auth_ride_dispatch_offers_responded_consistency
        CHECK (
            (status = 'pending' AND responded_at IS NULL)
            OR (status <> 'pending' AND responded_at IS NOT NULL)
        ),
    CONSTRAINT chk_auth_ride_dispatch_offers_reason_len
        CHECK (response_reason IS NULL OR char_length(response_reason) <= 160)
);

CREATE INDEX IF NOT EXISTS idx_auth_ride_dispatch_offers_driver_status_expires
    ON auth_ride_dispatch_offers(driver_account_id, status, expires_at, offered_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_auth_ride_dispatch_offers_ride_status_offered
    ON auth_ride_dispatch_offers(ride_id, status, offered_at DESC, id DESC);

CREATE UNIQUE INDEX IF NOT EXISTS uq_auth_ride_dispatch_offers_pending_ride_driver
    ON auth_ride_dispatch_offers(ride_id, driver_account_id)
    WHERE status = 'pending';

CREATE TABLE IF NOT EXISTS auth_ride_trip_live_state (
    ride_id TEXT PRIMARY KEY REFERENCES auth_ride_trips(ride_id) ON DELETE CASCADE,
    rider_account_id TEXT NOT NULL,
    driver_account_id TEXT,
    driver_name TEXT,
    car_plate TEXT,
    stage TEXT NOT NULL,
    driver_location_lat DOUBLE PRECISION,
    driver_location_lon DOUBLE PRECISION,
    accuracy_meters INTEGER,
    speed_kmh INTEGER,
    heading_degrees INTEGER,
    last_location_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_ride_trip_live_state_stage_known
        CHECK (
            stage IN (
                'ride_requested',
                'matching',
                'driver_assigned',
                'driver_arriving',
                'driver_arrived',
                'trip_started',
                'trip_in_progress',
                'payment_failed',
                'trip_completed',
                'cancelled'
            )
        ),
    CONSTRAINT chk_auth_ride_trip_live_state_location_pair
        CHECK (
            (driver_location_lat IS NULL AND driver_location_lon IS NULL)
            OR (driver_location_lat IS NOT NULL AND driver_location_lon IS NOT NULL)
        ),
    CONSTRAINT chk_auth_ride_trip_live_state_lat_bounds
        CHECK (
            driver_location_lat IS NULL
            OR (driver_location_lat >= -90 AND driver_location_lat <= 90)
        ),
    CONSTRAINT chk_auth_ride_trip_live_state_lon_bounds
        CHECK (
            driver_location_lon IS NULL
            OR (driver_location_lon >= -180 AND driver_location_lon <= 180)
        ),
    CONSTRAINT chk_auth_ride_trip_live_state_accuracy_bounds
        CHECK (
            accuracy_meters IS NULL
            OR (accuracy_meters >= 0 AND accuracy_meters <= 5000)
        ),
    CONSTRAINT chk_auth_ride_trip_live_state_speed_bounds
        CHECK (
            speed_kmh IS NULL
            OR (speed_kmh >= 0 AND speed_kmh <= 320)
        ),
    CONSTRAINT chk_auth_ride_trip_live_state_heading_bounds
        CHECK (
            heading_degrees IS NULL
            OR (heading_degrees >= 0 AND heading_degrees <= 360)
        )
);

CREATE INDEX IF NOT EXISTS idx_auth_ride_trip_live_state_driver_stage_updated
    ON auth_ride_trip_live_state(driver_account_id, stage, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_auth_ride_trip_live_state_stage_updated
    ON auth_ride_trip_live_state(stage, updated_at DESC);
