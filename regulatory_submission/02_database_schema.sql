-- Sanitized regulator extract.
-- Sources: services_rs/bff_gateway/migrations/*.sql
-- Unqualified table names are shown because the deployed PostgreSQL schema name
-- is not explicitly fixed in the inspected migrations.
-- Out-of-scope enum literals are replaced with '[REDACTED]'.

CREATE TABLE IF NOT EXISTS auth_accounts (
    account_id VARCHAR(64) PRIMARY KEY,
    shamell_user_id VARCHAR(16) NOT NULL UNIQUE,
    phone VARCHAR(32) UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS auth_sessions (
    id BIGSERIAL PRIMARY KEY,
    sid_hash VARCHAR(64) NOT NULL UNIQUE,
    account_id VARCHAR(64),
    phone VARCHAR(32),
    device_id VARCHAR(128),
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at TIMESTAMPTZ,
    CONSTRAINT fk_auth_sessions_account_id
        FOREIGN KEY (account_id) REFERENCES auth_accounts(account_id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_auth_sessions_expires_at
    ON auth_sessions(expires_at);
CREATE INDEX IF NOT EXISTS idx_auth_sessions_last_seen_at
    ON auth_sessions(last_seen_at);
CREATE INDEX IF NOT EXISTS idx_auth_sessions_account_device_active
    ON auth_sessions(account_id, device_id) WHERE revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS auth_user_ids (
    id BIGSERIAL PRIMARY KEY,
    phone VARCHAR(32) NOT NULL UNIQUE,
    shamell_user_id VARCHAR(16) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS auth_account_create_challenges (
    id BIGSERIAL PRIMARY KEY,
    token_hash VARCHAR(64) NOT NULL UNIQUE,
    device_id VARCHAR(128) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_auth_account_create_challenges_gc_at
    ON auth_account_create_challenges(COALESCE(consumed_at, expires_at));

CREATE TABLE IF NOT EXISTS auth_biometric_tokens (
    id BIGSERIAL PRIMARY KEY,
    token_hash VARCHAR(64) NOT NULL UNIQUE,
    account_id VARCHAR(64),
    phone VARCHAR(32),
    device_id VARCHAR(128) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    UNIQUE (phone, device_id),
    CONSTRAINT fk_auth_biometric_tokens_account_id
        FOREIGN KEY (account_id) REFERENCES auth_accounts(account_id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_auth_biometric_tokens_expires_at
    ON auth_biometric_tokens(expires_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_auth_biometric_tokens_account_device
    ON auth_biometric_tokens(account_id, device_id);

CREATE TABLE IF NOT EXISTS auth_rate_limits (
    limit_key VARCHAR(255) PRIMARY KEY,
    window_start_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    request_count BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_auth_rate_limits_updated_at
    ON auth_rate_limits(updated_at);

-- Consolidated final form from 0001 + 0036 + 0039.
CREATE TABLE IF NOT EXISTS device_login_challenges (
    id BIGSERIAL PRIMARY KEY,
    token_hash VARCHAR(64) NOT NULL UNIQUE,
    label VARCHAR(128),
    status VARCHAR(16) NOT NULL DEFAULT 'pending',
    account_id VARCHAR(64),
    phone VARCHAR(32),
    device_id VARCHAR(128),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    approved_at TIMESTAMPTZ,
    redeemed_at TIMESTAMPTZ,
    redeemed_client_ip_hash VARCHAR(64),
    redeemed_user_agent_hash VARCHAR(64),
    browser_binding_hash VARCHAR(64),
    CONSTRAINT fk_device_login_challenges_account_id
        FOREIGN KEY (account_id) REFERENCES auth_accounts(account_id) ON DELETE SET NULL,
    CONSTRAINT chk_device_login_challenges_status_known
        CHECK (status IN ('pending', 'approved', 'redeemed')),
    CONSTRAINT chk_device_login_challenges_approved_at_matches_status
        CHECK (
            (
                status = 'pending'
                AND approved_at IS NULL
                AND redeemed_at IS NULL
                AND redeemed_client_ip_hash IS NULL
                AND redeemed_user_agent_hash IS NULL
            )
            OR (
                status = 'approved'
                AND approved_at IS NOT NULL
                AND redeemed_at IS NULL
                AND redeemed_client_ip_hash IS NULL
                AND redeemed_user_agent_hash IS NULL
            )
            OR (
                status = 'redeemed'
                AND approved_at IS NOT NULL
                AND redeemed_at IS NOT NULL
                AND redeemed_client_ip_hash IS NOT NULL
                AND redeemed_user_agent_hash IS NOT NULL
            )
        ),
    CONSTRAINT chk_device_login_challenges_redeemed_at_after_approved_at
        CHECK (
            redeemed_at IS NULL
            OR (approved_at IS NOT NULL AND redeemed_at >= approved_at)
        ),
    CONSTRAINT chk_device_login_challenges_redeemed_at_before_expires_at
        CHECK (
            redeemed_at IS NULL OR redeemed_at <= expires_at
        )
);

CREATE INDEX IF NOT EXISTS idx_device_login_challenges_expires_at
    ON device_login_challenges(expires_at);

CREATE TABLE IF NOT EXISTS device_sessions (
    id BIGSERIAL PRIMARY KEY,
    account_id VARCHAR(64),
    phone VARCHAR(32),
    device_id VARCHAR(128) NOT NULL,
    device_type VARCHAR(32),
    device_name VARCHAR(128),
    platform VARCHAR(32),
    app_version VARCHAR(32),
    last_ip VARCHAR(64),
    user_agent VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_device_sessions_account_id
        FOREIGN KEY (account_id) REFERENCES auth_accounts(account_id) ON DELETE SET NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_device_sessions_account_device
    ON device_sessions(account_id, device_id);
CREATE INDEX IF NOT EXISTS idx_device_sessions_account_last_seen
    ON device_sessions(account_id, last_seen_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_device_sessions_last_seen_at
    ON device_sessions(last_seen_at);

-- Consolidated final form from 0045 + 0053.
CREATE TABLE IF NOT EXISTS auth_ride_trips (
    id BIGSERIAL PRIMARY KEY,
    ride_id TEXT NOT NULL UNIQUE,
    rider_account_id TEXT NOT NULL,
    driver_account_id TEXT,
    driver_name TEXT,
    car_plate TEXT,
    pickup_text TEXT NOT NULL,
    destination_text TEXT NOT NULL,
    pickup_label TEXT,
    destination_label TEXT,
    pickup_lat DOUBLE PRECISION,
    pickup_lon DOUBLE PRECISION,
    destination_lat DOUBLE PRECISION,
    destination_lon DOUBLE PRECISION,
    ride_class TEXT NOT NULL,
    fare_estimate_cents BIGINT NOT NULL,
    eta_seconds BIGINT NOT NULL,
    status TEXT NOT NULL,
    cancel_reason TEXT,
    cancel_reason_code TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    assigned_at TIMESTAMPTZ,
    arriving_at TIMESTAMPTZ,
    arrived_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
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
                '[REDACTED]',
                'trip_completed',
                'cancelled'
            )
        ),
    CONSTRAINT chk_auth_ride_trips_class_known
        CHECK (ride_class IN ('economy', 'xl', 'premium', 'delivery', 'corporate')),
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
        CHECK (status_updated_at >= created_at),
    CONSTRAINT chk_auth_ride_trips_pickup_location_pair
        CHECK (
            (pickup_lat IS NULL AND pickup_lon IS NULL)
            OR (pickup_lat IS NOT NULL AND pickup_lon IS NOT NULL)
        ),
    CONSTRAINT chk_auth_ride_trips_destination_location_pair
        CHECK (
            (destination_lat IS NULL AND destination_lon IS NULL)
            OR (destination_lat IS NOT NULL AND destination_lon IS NOT NULL)
        ),
    CONSTRAINT chk_auth_ride_trips_pickup_lat_bounds
        CHECK (pickup_lat IS NULL OR (pickup_lat >= -90 AND pickup_lat <= 90)),
    CONSTRAINT chk_auth_ride_trips_pickup_lon_bounds
        CHECK (pickup_lon IS NULL OR (pickup_lon >= -180 AND pickup_lon <= 180)),
    CONSTRAINT chk_auth_ride_trips_destination_lat_bounds
        CHECK (
            destination_lat IS NULL
            OR (destination_lat >= -90 AND destination_lat <= 90)
        ),
    CONSTRAINT chk_auth_ride_trips_destination_lon_bounds
        CHECK (
            destination_lon IS NULL
            OR (destination_lon >= -180 AND destination_lon <= 180)
        ),
    CONSTRAINT chk_auth_ride_trips_cancel_reason_code_len
        CHECK (cancel_reason_code IS NULL OR char_length(cancel_reason_code) <= 64)
);

CREATE INDEX IF NOT EXISTS idx_auth_ride_trips_rider_status_updated
    ON auth_ride_trips(rider_account_id, status_updated_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_auth_ride_trips_status_created
    ON auth_ride_trips(status, created_at DESC, id DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uq_auth_ride_trips_rider_single_active
    ON auth_ride_trips(rider_account_id)
    WHERE status NOT IN ('trip_completed', 'cancelled');

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
                '[REDACTED]',
                'complete_trip',
                'cancel_trip',
                'reassign_trip'
            )
        ),
    CONSTRAINT chk_auth_ride_trip_commands_idempotency_key_len
        CHECK (char_length(idempotency_key) BETWEEN 1 AND 128)
);

CREATE INDEX IF NOT EXISTS idx_auth_ride_trip_commands_ride_created
    ON auth_ride_trip_commands(ride_id, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS auth_ride_driver_documents (
    id BIGSERIAL PRIMARY KEY,
    document_id TEXT NOT NULL UNIQUE,
    driver_account_id TEXT NOT NULL,
    document_type TEXT NOT NULL,
    document_number TEXT NOT NULL,
    issuing_country TEXT,
    expires_at TIMESTAMPTZ,
    status TEXT NOT NULL,
    review_note TEXT,
    reviewer_account_id TEXT,
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_ride_driver_documents_type_known
        CHECK (
            document_type IN (
                'driver_license',
                'vehicle_registration',
                'insurance',
                'identity_card'
            )
        ),
    CONSTRAINT chk_auth_ride_driver_documents_status_known
        CHECK (status IN ('pending', 'approved', 'rejected')),
    CONSTRAINT chk_auth_ride_driver_documents_number_len
        CHECK (char_length(document_number) BETWEEN 4 AND 64),
    CONSTRAINT chk_auth_ride_driver_documents_country_len
        CHECK (
            issuing_country IS NULL
            OR char_length(issuing_country) BETWEEN 2 AND 3
        ),
    CONSTRAINT chk_auth_ride_driver_documents_review_consistency
        CHECK (
            (status = 'pending' AND reviewed_at IS NULL AND reviewer_account_id IS NULL)
            OR (status IN ('approved', 'rejected') AND reviewed_at IS NOT NULL AND reviewer_account_id IS NOT NULL)
        ),
    CONSTRAINT chk_auth_ride_driver_documents_updated_after_submitted
        CHECK (updated_at >= submitted_at)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_auth_ride_driver_documents_driver_type
    ON auth_ride_driver_documents(driver_account_id, document_type);
CREATE INDEX IF NOT EXISTS idx_auth_ride_driver_documents_status_updated
    ON auth_ride_driver_documents(status, updated_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_auth_ride_driver_documents_driver_updated
    ON auth_ride_driver_documents(driver_account_id, updated_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS auth_ride_pricing_policies (
    ride_class TEXT PRIMARY KEY,
    base_fare_minor_units BIGINT NOT NULL CHECK (base_fare_minor_units > 0),
    per_km_minor_units BIGINT NOT NULL CHECK (per_km_minor_units >= 0),
    per_minute_minor_units BIGINT NOT NULL CHECK (per_minute_minor_units >= 0),
    traffic_delay_per_minute_minor_units BIGINT NOT NULL CHECK (traffic_delay_per_minute_minor_units >= 0),
    booking_fee_minor_units BIGINT NOT NULL CHECK (booking_fee_minor_units >= 0),
    minimum_fare_minor_units BIGINT NOT NULL CHECK (minimum_fare_minor_units > 0),
    driver_share_bps BIGINT NOT NULL CHECK (driver_share_bps BETWEEN 1000 AND 9900),
    updated_by_account_id TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (ride_class IN ('economy', 'xl', 'premium', 'delivery', 'corporate'))
);

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
    CONSTRAINT chk_auth_ride_trip_tracking_events_kind_known
        CHECK (event_kind IN ('ride_created', 'status_changed', 'driver_location', 'operator_note')),
    CONSTRAINT chk_auth_ride_trip_tracking_events_status_known
        CHECK (
            status IS NULL
            OR status IN (
                'ride_requested',
                'matching',
                'driver_assigned',
                'driver_arriving',
                'driver_arrived',
                'trip_started',
                'trip_in_progress',
                '[REDACTED]',
                'trip_completed',
                'cancelled'
            )
        ),
    CONSTRAINT chk_auth_ride_trip_tracking_events_location_pair
        CHECK (
            (location_lat IS NULL AND location_lon IS NULL)
            OR (location_lat IS NOT NULL AND location_lon IS NOT NULL)
        ),
    CONSTRAINT chk_auth_ride_trip_tracking_events_lat_bounds
        CHECK (location_lat IS NULL OR (location_lat >= -90 AND location_lat <= 90)),
    CONSTRAINT chk_auth_ride_trip_tracking_events_lon_bounds
        CHECK (location_lon IS NULL OR (location_lon >= -180 AND location_lon <= 180)),
    CONSTRAINT chk_auth_ride_trip_tracking_events_accuracy_bounds
        CHECK (accuracy_meters IS NULL OR (accuracy_meters >= 0 AND accuracy_meters <= 5000)),
    CONSTRAINT chk_auth_ride_trip_tracking_events_speed_bounds
        CHECK (speed_kmh IS NULL OR (speed_kmh >= 0 AND speed_kmh <= 320)),
    CONSTRAINT chk_auth_ride_trip_tracking_events_heading_bounds
        CHECK (heading_degrees IS NULL OR (heading_degrees >= 0 AND heading_degrees <= 360)),
    CONSTRAINT chk_auth_ride_trip_tracking_events_note_len
        CHECK (note IS NULL OR char_length(note) <= 160)
);

CREATE INDEX IF NOT EXISTS idx_auth_ride_trip_tracking_events_ride_created
    ON auth_ride_trip_tracking_events(ride_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_auth_ride_trip_tracking_events_driver_location
    ON auth_ride_trip_tracking_events(ride_id, event_kind, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS auth_ride_support_tickets (
    id BIGSERIAL PRIMARY KEY,
    ticket_id TEXT NOT NULL UNIQUE,
    ride_id TEXT REFERENCES auth_ride_trips(ride_id) ON DELETE SET NULL,
    rider_account_id TEXT NOT NULL,
    ticket_category TEXT NOT NULL,
    subject TEXT NOT NULL,
    body_text TEXT NOT NULL,
    preferred_contact TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'open',
    resolution_note TEXT,
    resolved_by_account_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ,
    CONSTRAINT chk_auth_ride_support_tickets_category_known
        CHECK (
            ticket_category IN (
                'booking_issue',
                'driver_behavior',
                'safety',
                '[REDACTED]',
                'lost_item',
                'other'
            )
        ),
    CONSTRAINT chk_auth_ride_support_tickets_contact_known
        CHECK (preferred_contact IN ('in_app', 'email', 'phone')),
    CONSTRAINT chk_auth_ride_support_tickets_status_known
        CHECK (status IN ('open', 'resolved')),
    CONSTRAINT chk_auth_ride_support_tickets_resolution_consistency
        CHECK (
            (status = 'open' AND resolved_at IS NULL AND resolved_by_account_id IS NULL)
            OR (
                status = 'resolved'
                AND resolved_at IS NOT NULL
                AND resolved_by_account_id IS NOT NULL
            )
        )
);

CREATE INDEX IF NOT EXISTS idx_auth_ride_support_tickets_rider_updated
    ON auth_ride_support_tickets(rider_account_id, updated_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_auth_ride_support_tickets_status_updated
    ON auth_ride_support_tickets(status, updated_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_auth_ride_support_tickets_ride_updated
    ON auth_ride_support_tickets(ride_id, updated_at DESC, id DESC);

-- Consolidated final form from 0050 + 0051.
CREATE TABLE IF NOT EXISTS auth_ride_driver_presence (
    driver_account_id TEXT PRIMARY KEY,
    availability_status TEXT NOT NULL,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_online_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    location_lat DOUBLE PRECISION,
    location_lon DOUBLE PRECISION,
    driver_name TEXT,
    car_plate TEXT,
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
CREATE INDEX IF NOT EXISTS idx_auth_ride_driver_presence_status_last_seen
    ON auth_ride_driver_presence(availability_status, last_seen_at DESC);

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
                '[REDACTED]',
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

