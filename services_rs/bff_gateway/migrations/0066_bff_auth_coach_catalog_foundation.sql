CREATE TABLE IF NOT EXISTS auth_coach_catalog_operators (
    operator_id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    integration_mode TEXT NOT NULL,
    country_code VARCHAR(2),
    active BOOLEAN NOT NULL DEFAULT TRUE,
    metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_coach_catalog_operators_operator_id_nonempty
        CHECK (btrim(operator_id) <> ''),
    CONSTRAINT chk_auth_coach_catalog_operators_display_name_nonempty
        CHECK (btrim(display_name) <> ''),
    CONSTRAINT chk_auth_coach_catalog_operators_integration_mode_known
        CHECK (integration_mode IN ('feed', 'api', 'hybrid'))
);

CREATE TABLE IF NOT EXISTS auth_coach_catalog_cities (
    city_id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    country_code VARCHAR(2) NOT NULL,
    timezone_name TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_coach_catalog_cities_city_id_nonempty
        CHECK (btrim(city_id) <> ''),
    CONSTRAINT chk_auth_coach_catalog_cities_display_name_nonempty
        CHECK (btrim(display_name) <> ''),
    CONSTRAINT chk_auth_coach_catalog_cities_country_code_len
        CHECK (char_length(country_code) = 2),
    CONSTRAINT chk_auth_coach_catalog_cities_timezone_name_nonempty
        CHECK (btrim(timezone_name) <> '')
);

CREATE TABLE IF NOT EXISTS auth_coach_catalog_stop_clusters (
    stop_cluster_id TEXT PRIMARY KEY,
    city_id TEXT NOT NULL REFERENCES auth_coach_catalog_cities(city_id) ON DELETE CASCADE,
    canonical_name TEXT NOT NULL,
    lat DOUBLE PRECISION,
    lon DOUBLE PRECISION,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_coach_catalog_stop_clusters_id_nonempty
        CHECK (btrim(stop_cluster_id) <> ''),
    CONSTRAINT chk_auth_coach_catalog_stop_clusters_city_id_nonempty
        CHECK (btrim(city_id) <> ''),
    CONSTRAINT chk_auth_coach_catalog_stop_clusters_name_nonempty
        CHECK (btrim(canonical_name) <> ''),
    CONSTRAINT chk_auth_coach_catalog_stop_clusters_lat_range
        CHECK (lat IS NULL OR lat BETWEEN -90.0 AND 90.0),
    CONSTRAINT chk_auth_coach_catalog_stop_clusters_lon_range
        CHECK (lon IS NULL OR lon BETWEEN -180.0 AND 180.0)
);

CREATE TABLE IF NOT EXISTS auth_coach_catalog_stops (
    stop_id TEXT PRIMARY KEY,
    stop_cluster_id TEXT NOT NULL REFERENCES auth_coach_catalog_stop_clusters(stop_cluster_id) ON DELETE CASCADE,
    city_id TEXT NOT NULL REFERENCES auth_coach_catalog_cities(city_id) ON DELETE CASCADE,
    canonical_name TEXT NOT NULL,
    platform_code TEXT,
    lat DOUBLE PRECISION,
    lon DOUBLE PRECISION,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_coach_catalog_stops_id_nonempty
        CHECK (btrim(stop_id) <> ''),
    CONSTRAINT chk_auth_coach_catalog_stops_cluster_nonempty
        CHECK (btrim(stop_cluster_id) <> ''),
    CONSTRAINT chk_auth_coach_catalog_stops_city_nonempty
        CHECK (btrim(city_id) <> ''),
    CONSTRAINT chk_auth_coach_catalog_stops_name_nonempty
        CHECK (btrim(canonical_name) <> ''),
    CONSTRAINT chk_auth_coach_catalog_stops_lat_range
        CHECK (lat IS NULL OR lat BETWEEN -90.0 AND 90.0),
    CONSTRAINT chk_auth_coach_catalog_stops_lon_range
        CHECK (lon IS NULL OR lon BETWEEN -180.0 AND 180.0)
);

CREATE TABLE IF NOT EXISTS auth_coach_catalog_lines (
    line_id TEXT PRIMARY KEY,
    operator_id TEXT NOT NULL REFERENCES auth_coach_catalog_operators(operator_id) ON DELETE CASCADE,
    public_code TEXT,
    marketing_name TEXT NOT NULL,
    vehicle_class TEXT,
    amenities_json JSONB NOT NULL DEFAULT '[]'::jsonb,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_coach_catalog_lines_id_nonempty
        CHECK (btrim(line_id) <> ''),
    CONSTRAINT chk_auth_coach_catalog_lines_operator_nonempty
        CHECK (btrim(operator_id) <> ''),
    CONSTRAINT chk_auth_coach_catalog_lines_marketing_name_nonempty
        CHECK (btrim(marketing_name) <> ''),
    CONSTRAINT chk_auth_coach_catalog_lines_amenities_array
        CHECK (jsonb_typeof(amenities_json) = 'array')
);

CREATE TABLE IF NOT EXISTS auth_coach_catalog_service_calendars (
    service_calendar_id TEXT PRIMARY KEY,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    monday BOOLEAN NOT NULL DEFAULT FALSE,
    tuesday BOOLEAN NOT NULL DEFAULT FALSE,
    wednesday BOOLEAN NOT NULL DEFAULT FALSE,
    thursday BOOLEAN NOT NULL DEFAULT FALSE,
    friday BOOLEAN NOT NULL DEFAULT FALSE,
    saturday BOOLEAN NOT NULL DEFAULT FALSE,
    sunday BOOLEAN NOT NULL DEFAULT FALSE,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_coach_catalog_service_calendars_id_nonempty
        CHECK (btrim(service_calendar_id) <> ''),
    CONSTRAINT chk_auth_coach_catalog_service_calendars_date_range
        CHECK (start_date <= end_date),
    CONSTRAINT chk_auth_coach_catalog_service_calendars_has_active_day
        CHECK (monday OR tuesday OR wednesday OR thursday OR friday OR saturday OR sunday)
);

CREATE TABLE IF NOT EXISTS auth_coach_catalog_trips (
    trip_id TEXT PRIMARY KEY,
    operator_id TEXT NOT NULL REFERENCES auth_coach_catalog_operators(operator_id) ON DELETE CASCADE,
    line_id TEXT NOT NULL REFERENCES auth_coach_catalog_lines(line_id) ON DELETE CASCADE,
    service_calendar_id TEXT NOT NULL REFERENCES auth_coach_catalog_service_calendars(service_calendar_id) ON DELETE CASCADE,
    origin_stop_cluster_id TEXT NOT NULL REFERENCES auth_coach_catalog_stop_clusters(stop_cluster_id) ON DELETE CASCADE,
    destination_stop_cluster_id TEXT NOT NULL REFERENCES auth_coach_catalog_stop_clusters(stop_cluster_id) ON DELETE CASCADE,
    departure_time_local TEXT NOT NULL,
    arrival_time_local TEXT NOT NULL,
    duration_minutes INTEGER NOT NULL,
    service_timezone TEXT NOT NULL,
    seats_total INTEGER NOT NULL,
    seats_available INTEGER NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_coach_catalog_trips_id_nonempty
        CHECK (btrim(trip_id) <> ''),
    CONSTRAINT chk_auth_coach_catalog_trips_operator_nonempty
        CHECK (btrim(operator_id) <> ''),
    CONSTRAINT chk_auth_coach_catalog_trips_line_nonempty
        CHECK (btrim(line_id) <> ''),
    CONSTRAINT chk_auth_coach_catalog_trips_calendar_nonempty
        CHECK (btrim(service_calendar_id) <> ''),
    CONSTRAINT chk_auth_coach_catalog_trips_origin_nonempty
        CHECK (btrim(origin_stop_cluster_id) <> ''),
    CONSTRAINT chk_auth_coach_catalog_trips_destination_nonempty
        CHECK (btrim(destination_stop_cluster_id) <> ''),
    CONSTRAINT chk_auth_coach_catalog_trips_timezone_nonempty
        CHECK (btrim(service_timezone) <> ''),
    CONSTRAINT chk_auth_coach_catalog_trips_duration_positive
        CHECK (duration_minutes > 0),
    CONSTRAINT chk_auth_coach_catalog_trips_origin_destination_differ
        CHECK (origin_stop_cluster_id <> destination_stop_cluster_id),
    CONSTRAINT chk_auth_coach_catalog_trips_seat_totals_nonnegative
        CHECK (seats_total >= 0 AND seats_available >= 0 AND seats_available <= seats_total),
    CONSTRAINT chk_auth_coach_catalog_trips_departure_format
        CHECK (departure_time_local ~ '^[0-2][0-9]:[0-5][0-9]$'),
    CONSTRAINT chk_auth_coach_catalog_trips_arrival_format
        CHECK (arrival_time_local ~ '^[0-2][0-9]:[0-5][0-9]$')
);

CREATE TABLE IF NOT EXISTS auth_coach_catalog_fare_products (
    fare_product_id TEXT PRIMARY KEY,
    trip_id TEXT NOT NULL REFERENCES auth_coach_catalog_trips(trip_id) ON DELETE CASCADE,
    fare_name TEXT NOT NULL,
    passenger_type TEXT NOT NULL,
    currency CHAR(3) NOT NULL,
    price_minor_units BIGINT NOT NULL,
    hold_supported BOOLEAN NOT NULL DEFAULT FALSE,
    changeable BOOLEAN NOT NULL DEFAULT FALSE,
    refundable BOOLEAN NOT NULL DEFAULT FALSE,
    baggage_rule TEXT,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_coach_catalog_fare_products_id_nonempty
        CHECK (btrim(fare_product_id) <> ''),
    CONSTRAINT chk_auth_coach_catalog_fare_products_trip_nonempty
        CHECK (btrim(trip_id) <> ''),
    CONSTRAINT chk_auth_coach_catalog_fare_products_fare_name_nonempty
        CHECK (btrim(fare_name) <> ''),
    CONSTRAINT chk_auth_coach_catalog_fare_products_passenger_type_nonempty
        CHECK (btrim(passenger_type) <> ''),
    CONSTRAINT chk_auth_coach_catalog_fare_products_price_nonnegative
        CHECK (price_minor_units >= 0)
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_catalog_stop_clusters_city_active
    ON auth_coach_catalog_stop_clusters(city_id, active, canonical_name);

CREATE INDEX IF NOT EXISTS idx_auth_coach_catalog_stops_cluster_active
    ON auth_coach_catalog_stops(stop_cluster_id, active, canonical_name);

CREATE INDEX IF NOT EXISTS idx_auth_coach_catalog_lines_operator_active
    ON auth_coach_catalog_lines(operator_id, active, marketing_name);

CREATE INDEX IF NOT EXISTS idx_auth_coach_catalog_trips_origin_dest_active
    ON auth_coach_catalog_trips(origin_stop_cluster_id, destination_stop_cluster_id, active);

CREATE INDEX IF NOT EXISTS idx_auth_coach_catalog_trips_calendar_active
    ON auth_coach_catalog_trips(service_calendar_id, active);

CREATE INDEX IF NOT EXISTS idx_auth_coach_catalog_fare_products_trip_active_price
    ON auth_coach_catalog_fare_products(trip_id, active, price_minor_units);
