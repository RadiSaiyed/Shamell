CREATE TABLE IF NOT EXISTS auth_coach_catalog_operator_feed_health (
    operator_id TEXT NOT NULL REFERENCES auth_coach_catalog_operators(operator_id) ON DELETE CASCADE,
    feed_kind TEXT NOT NULL,
    source_kind TEXT NOT NULL,
    sync_status TEXT NOT NULL,
    freshness_status TEXT NOT NULL,
    last_attempted_at TIMESTAMPTZ,
    last_succeeded_at TIMESTAMPTZ,
    freshness_expires_at TIMESTAMPTZ,
    records_ingested BIGINT NOT NULL DEFAULT 0,
    error_message TEXT,
    metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (operator_id, feed_kind),
    CONSTRAINT chk_auth_coach_catalog_operator_feed_health_feed_kind_known
        CHECK (feed_kind IN (
            'static_catalog',
            'gtfs_rt_trip_updates',
            'gtfs_rt_vehicle_positions',
            'gtfs_rt_service_alerts',
            'siri'
        )),
    CONSTRAINT chk_auth_coach_catalog_operator_feed_health_source_kind_known
        CHECK (source_kind IN ('gtfs', 'netex', 'gtfs_rt', 'siri', 'manual_seed')),
    CONSTRAINT chk_auth_coach_catalog_operator_feed_health_sync_status_known
        CHECK (sync_status IN ('ok', 'degraded', 'failed')),
    CONSTRAINT chk_auth_coach_catalog_operator_feed_health_freshness_status_known
        CHECK (freshness_status IN ('fresh', 'stale', 'missing')),
    CONSTRAINT chk_auth_coach_catalog_operator_feed_health_records_nonnegative
        CHECK (records_ingested >= 0)
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_catalog_operator_feed_health_status
    ON auth_coach_catalog_operator_feed_health(sync_status, freshness_status);

CREATE INDEX IF NOT EXISTS idx_auth_coach_catalog_operator_feed_health_freshness_expires
    ON auth_coach_catalog_operator_feed_health(freshness_expires_at);
