CREATE TABLE IF NOT EXISTS auth_coach_catalog_import_configs (
    feed_kind text NOT NULL,
    source_kind text NOT NULL,
    feed_locator text NOT NULL,
    updated_by_account_id text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT NOW(),
    updated_at timestamptz NOT NULL DEFAULT NOW(),
    PRIMARY KEY (feed_kind, source_kind),
    CONSTRAINT auth_coach_catalog_import_configs_feed_kind_check
        CHECK (feed_kind IN ('static_catalog')),
    CONSTRAINT auth_coach_catalog_import_configs_source_kind_check
        CHECK (source_kind IN ('gtfs')),
    CONSTRAINT auth_coach_catalog_import_configs_feed_locator_nonempty
        CHECK (char_length(btrim(feed_locator)) > 0),
    CONSTRAINT auth_coach_catalog_import_configs_updated_by_nonempty
        CHECK (char_length(btrim(updated_by_account_id)) > 0)
);

CREATE INDEX IF NOT EXISTS auth_coach_catalog_import_configs_updated_idx
    ON auth_coach_catalog_import_configs (updated_at DESC, feed_kind, source_kind);
