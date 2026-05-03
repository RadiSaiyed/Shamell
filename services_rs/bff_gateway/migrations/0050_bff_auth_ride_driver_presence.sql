CREATE TABLE IF NOT EXISTS auth_ride_driver_presence (
    driver_account_id TEXT PRIMARY KEY,
    availability_status TEXT NOT NULL,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_online_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    location_lat DOUBLE PRECISION,
    location_lon DOUBLE PRECISION,
    CONSTRAINT chk_auth_ride_driver_presence_status_known
        CHECK (availability_status IN ('online', 'offline')),
    CONSTRAINT chk_auth_ride_driver_presence_location_pair
        CHECK (
            (location_lat IS NULL AND location_lon IS NULL)
            OR (location_lat IS NOT NULL AND location_lon IS NOT NULL)
        ),
    CONSTRAINT chk_auth_ride_driver_presence_online_timestamp
        CHECK (
            availability_status = 'offline'
            OR last_online_at IS NOT NULL
        )
);

CREATE INDEX IF NOT EXISTS idx_auth_ride_driver_presence_status_updated
    ON auth_ride_driver_presence(availability_status, updated_at DESC);
