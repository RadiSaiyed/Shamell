CREATE TABLE IF NOT EXISTS auth_ride_trips (
    id BIGSERIAL PRIMARY KEY,
    ride_id TEXT NOT NULL UNIQUE,
    rider_account_id TEXT NOT NULL,
    driver_account_id TEXT,
    driver_name TEXT,
    car_plate TEXT,
    pickup_text TEXT NOT NULL,
    destination_text TEXT NOT NULL,
    ride_class TEXT NOT NULL,
    fare_estimate_cents BIGINT NOT NULL,
    eta_seconds BIGINT NOT NULL,
    status TEXT NOT NULL,
    cancel_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    terminal_at TIMESTAMPTZ,
    CONSTRAINT chk_auth_ride_trips_status_known
        CHECK (
            status IN (
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
    CONSTRAINT chk_auth_ride_trips_class_known
        CHECK (
            ride_class IN ('economy', 'xl', 'premium', 'delivery', 'corporate')
        ),
    CONSTRAINT chk_auth_ride_trips_fare_non_negative
        CHECK (fare_estimate_cents >= 0),
    CONSTRAINT chk_auth_ride_trips_eta_non_negative
        CHECK (eta_seconds >= 0),
    CONSTRAINT chk_auth_ride_trips_terminal_state_consistency
        CHECK (
            (status IN ('trip_completed', 'cancelled') AND terminal_at IS NOT NULL)
            OR (status NOT IN ('trip_completed', 'cancelled') AND terminal_at IS NULL)
        ),
    CONSTRAINT chk_auth_ride_trips_updated_after_created
        CHECK (updated_at >= created_at),
    CONSTRAINT chk_auth_ride_trips_status_updated_after_created
        CHECK (status_updated_at >= created_at)
);

CREATE TABLE IF NOT EXISTS auth_ride_trip_commands (
    id BIGSERIAL PRIMARY KEY,
    ride_id TEXT NOT NULL,
    rider_account_id TEXT NOT NULL,
    idempotency_key TEXT NOT NULL,
    command TEXT NOT NULL,
    request_fingerprint TEXT NOT NULL,
    response_json JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_auth_ride_trip_commands_ride_id
        FOREIGN KEY (ride_id)
        REFERENCES auth_ride_trips(ride_id)
        ON DELETE CASCADE
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT uq_auth_ride_trip_commands_rider_idempotency
        UNIQUE (rider_account_id, idempotency_key),
    CONSTRAINT chk_auth_ride_trip_commands_command_known
        CHECK (
            command IN (
                'request_ride',
                'enter_matching',
                'assign_driver',
                'mark_driver_arriving',
                'mark_driver_arrived',
                'start_trip',
                'mark_in_progress',
                'mark_payment_failed',
                'complete_trip',
                'cancel_trip'
            )
        ),
    CONSTRAINT chk_auth_ride_trip_commands_idempotency_key_len
        CHECK (char_length(idempotency_key) BETWEEN 1 AND 128)
);

CREATE INDEX IF NOT EXISTS idx_auth_ride_trips_rider_status_updated
    ON auth_ride_trips(rider_account_id, status_updated_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_auth_ride_trip_commands_ride_created
    ON auth_ride_trip_commands(ride_id, created_at DESC, id DESC);

CREATE UNIQUE INDEX IF NOT EXISTS uq_auth_ride_trips_rider_single_active
    ON auth_ride_trips(rider_account_id)
    WHERE status NOT IN ('trip_completed', 'cancelled');
