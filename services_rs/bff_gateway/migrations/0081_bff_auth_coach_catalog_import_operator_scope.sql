ALTER TABLE auth_coach_catalog_source_artifacts
    ADD COLUMN IF NOT EXISTS operator_ids JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE auth_coach_catalog_import_runs
    ADD COLUMN IF NOT EXISTS operator_ids JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE auth_coach_catalog_source_artifacts
    DROP CONSTRAINT IF EXISTS chk_auth_coach_catalog_source_artifacts_operator_ids_array;

ALTER TABLE auth_coach_catalog_source_artifacts
    ADD CONSTRAINT chk_auth_coach_catalog_source_artifacts_operator_ids_array
    CHECK (jsonb_typeof(operator_ids) = 'array');

ALTER TABLE auth_coach_catalog_import_runs
    DROP CONSTRAINT IF EXISTS chk_auth_coach_catalog_import_runs_operator_ids_array;

ALTER TABLE auth_coach_catalog_import_runs
    ADD CONSTRAINT chk_auth_coach_catalog_import_runs_operator_ids_array
    CHECK (jsonb_typeof(operator_ids) = 'array');

CREATE INDEX IF NOT EXISTS idx_auth_coach_catalog_source_artifacts_operator_ids_gin
    ON auth_coach_catalog_source_artifacts USING GIN (operator_ids);

CREATE INDEX IF NOT EXISTS idx_auth_coach_catalog_import_runs_operator_ids_gin
    ON auth_coach_catalog_import_runs USING GIN (operator_ids);
