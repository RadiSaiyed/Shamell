CREATE TABLE IF NOT EXISTS auth_coach_catalog_import_runs (
    import_run_id TEXT PRIMARY KEY,
    feed_kind TEXT NOT NULL,
    source_kind TEXT NOT NULL,
    trigger_kind TEXT NOT NULL,
    feed_locator TEXT,
    status TEXT NOT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    finished_at TIMESTAMPTZ,
    operator_count BIGINT NOT NULL DEFAULT 0,
    city_count BIGINT NOT NULL DEFAULT 0,
    stop_cluster_count BIGINT NOT NULL DEFAULT 0,
    stop_count BIGINT NOT NULL DEFAULT 0,
    line_count BIGINT NOT NULL DEFAULT 0,
    service_calendar_count BIGINT NOT NULL DEFAULT 0,
    trip_count BIGINT NOT NULL DEFAULT 0,
    fare_product_count BIGINT NOT NULL DEFAULT 0,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_coach_catalog_import_runs_feed_kind_known CHECK (
        feed_kind IN ('static_catalog')
    ),
    CONSTRAINT chk_auth_coach_catalog_import_runs_source_kind_known CHECK (
        source_kind IN ('gtfs', 'netex', 'manual_seed')
    ),
    CONSTRAINT chk_auth_coach_catalog_import_runs_trigger_kind_known CHECK (
        trigger_kind IN ('startup', 'manual', 'scheduled')
    ),
    CONSTRAINT chk_auth_coach_catalog_import_runs_status_known CHECK (
        status IN ('running', 'succeeded', 'failed')
    ),
    CONSTRAINT chk_auth_coach_catalog_import_runs_feed_locator_nonempty CHECK (
        feed_locator IS NULL OR LENGTH(BTRIM(feed_locator)) > 0
    ),
    CONSTRAINT chk_auth_coach_catalog_import_runs_counts_non_negative CHECK (
        operator_count >= 0
        AND city_count >= 0
        AND stop_cluster_count >= 0
        AND stop_count >= 0
        AND line_count >= 0
        AND service_calendar_count >= 0
        AND trip_count >= 0
        AND fare_product_count >= 0
    ),
    CONSTRAINT chk_auth_coach_catalog_import_runs_failed_requires_error CHECK (
        status <> 'failed' OR (error_message IS NOT NULL AND LENGTH(BTRIM(error_message)) > 0)
    ),
    CONSTRAINT chk_auth_coach_catalog_import_runs_finished_at_required_for_terminal CHECK (
        status = 'running' OR finished_at IS NOT NULL
    )
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_catalog_import_runs_started_at
    ON auth_coach_catalog_import_runs (started_at DESC, import_run_id DESC);

CREATE INDEX IF NOT EXISTS idx_auth_coach_catalog_import_runs_status
    ON auth_coach_catalog_import_runs (status, started_at DESC);

