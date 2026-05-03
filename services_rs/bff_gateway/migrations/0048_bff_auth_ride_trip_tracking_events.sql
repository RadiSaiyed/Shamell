CREATE TABLE IF NOT EXISTS auth_ride_trip_tracking_events (
    id BIGSERIAL PRIMARY KEY,
    ride_id TEXT NOT NULL REFERENCES auth_ride_trips(ride_id) ON DELETE CASCADE,
    event_kind TEXT NOT NULL,
    status TEXT,
    actor_account_id TEXT,
    location_lat DOUBLE PRECISION,
    location_lon DOUBLE PRECISION,
    accuracy_meters INTEGER,
    speed_kmh INTEGER,
    heading_degrees INTEGER,
    note TEXT,
    metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_ride_trip_tracking_events_kind_known CHECK (
        event_kind IN ('ride_created', 'status_changed', 'driver_location', 'operator_note')
    ),
    CONSTRAINT chk_auth_ride_trip_tracking_events_status_known CHECK (
        status IS NULL
        OR status IN (
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
    CONSTRAINT chk_auth_ride_trip_tracking_events_location_pair CHECK (
        (location_lat IS NULL AND location_lon IS NULL)
        OR (location_lat IS NOT NULL AND location_lon IS NOT NULL)
    ),
    CONSTRAINT chk_auth_ride_trip_tracking_events_lat_bounds CHECK (
        location_lat IS NULL OR (location_lat >= -90 AND location_lat <= 90)
    ),
    CONSTRAINT chk_auth_ride_trip_tracking_events_lon_bounds CHECK (
        location_lon IS NULL OR (location_lon >= -180 AND location_lon <= 180)
    ),
    CONSTRAINT chk_auth_ride_trip_tracking_events_accuracy_bounds CHECK (
        accuracy_meters IS NULL OR (accuracy_meters >= 0 AND accuracy_meters <= 5000)
    ),
    CONSTRAINT chk_auth_ride_trip_tracking_events_speed_bounds CHECK (
        speed_kmh IS NULL OR (speed_kmh >= 0 AND speed_kmh <= 320)
    ),
    CONSTRAINT chk_auth_ride_trip_tracking_events_heading_bounds CHECK (
        heading_degrees IS NULL OR (heading_degrees >= 0 AND heading_degrees <= 360)
    ),
    CONSTRAINT chk_auth_ride_trip_tracking_events_note_len CHECK (
        note IS NULL OR char_length(note) <= 160
    )
);

CREATE INDEX IF NOT EXISTS idx_auth_ride_trip_tracking_events_ride_created
    ON auth_ride_trip_tracking_events(ride_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_auth_ride_trip_tracking_events_driver_location
    ON auth_ride_trip_tracking_events(ride_id, event_kind, created_at DESC, id DESC);
