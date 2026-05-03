CREATE TABLE IF NOT EXISTS auth_coach_catalog_source_artifacts (
    artifact_id TEXT PRIMARY KEY,
    feed_kind TEXT NOT NULL,
    source_kind TEXT NOT NULL,
    source_label TEXT NOT NULL,
    file_name TEXT NOT NULL,
    file_checksum_sha256 TEXT NOT NULL,
    content_length_bytes BIGINT NOT NULL,
    extracted_file_count BIGINT NOT NULL,
    feed_locator TEXT NOT NULL,
    created_by_account_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_coach_catalog_source_artifacts_feed_kind_known CHECK (
        feed_kind IN ('static_catalog')
    ),
    CONSTRAINT chk_auth_coach_catalog_source_artifacts_source_kind_known CHECK (
        source_kind IN ('gtfs')
    ),
    CONSTRAINT chk_auth_coach_catalog_source_artifacts_source_label_nonempty CHECK (
        LENGTH(BTRIM(source_label)) > 0
    ),
    CONSTRAINT chk_auth_coach_catalog_source_artifacts_file_name_nonempty CHECK (
        LENGTH(BTRIM(file_name)) > 0
    ),
    CONSTRAINT chk_auth_coach_catalog_source_artifacts_checksum_shape CHECK (
        LENGTH(BTRIM(file_checksum_sha256)) = 64
    ),
    CONSTRAINT chk_auth_coach_catalog_source_artifacts_content_length_positive CHECK (
        content_length_bytes > 0
    ),
    CONSTRAINT chk_auth_coach_catalog_source_artifacts_extracted_count_non_negative CHECK (
        extracted_file_count >= 0
    ),
    CONSTRAINT chk_auth_coach_catalog_source_artifacts_feed_locator_nonempty CHECK (
        LENGTH(BTRIM(feed_locator)) > 0
    ),
    CONSTRAINT chk_auth_coach_catalog_source_artifacts_created_by_nonempty CHECK (
        LENGTH(BTRIM(created_by_account_id)) > 0
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_auth_coach_catalog_source_artifacts_locator
    ON auth_coach_catalog_source_artifacts (feed_kind, source_kind, feed_locator);

CREATE INDEX IF NOT EXISTS idx_auth_coach_catalog_source_artifacts_created_at
    ON auth_coach_catalog_source_artifacts (created_at DESC, artifact_id DESC);

ALTER TABLE auth_coach_catalog_import_configs
    ADD COLUMN IF NOT EXISTS source_artifact_id TEXT;

ALTER TABLE auth_coach_catalog_import_runs
    ADD COLUMN IF NOT EXISTS source_artifact_id TEXT;

CREATE INDEX IF NOT EXISTS idx_auth_coach_catalog_import_configs_source_artifact_id
    ON auth_coach_catalog_import_configs (source_artifact_id);

CREATE INDEX IF NOT EXISTS idx_auth_coach_catalog_import_runs_source_artifact_id
    ON auth_coach_catalog_import_runs (source_artifact_id);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_auth_coach_catalog_import_configs_source_artifact'
    ) THEN
        ALTER TABLE auth_coach_catalog_import_configs
            ADD CONSTRAINT fk_auth_coach_catalog_import_configs_source_artifact
            FOREIGN KEY (source_artifact_id)
            REFERENCES auth_coach_catalog_source_artifacts (artifact_id)
            ON DELETE SET NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_auth_coach_catalog_import_runs_source_artifact'
    ) THEN
        ALTER TABLE auth_coach_catalog_import_runs
            ADD CONSTRAINT fk_auth_coach_catalog_import_runs_source_artifact
            FOREIGN KEY (source_artifact_id)
            REFERENCES auth_coach_catalog_source_artifacts (artifact_id)
            ON DELETE SET NULL;
    END IF;
END $$;
