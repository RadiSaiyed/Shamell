ALTER TABLE auth_coach_catalog_import_run_saved_views
    ADD COLUMN IF NOT EXISTS operator_ids JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE auth_coach_catalog_import_run_issue_saved_views
    ADD COLUMN IF NOT EXISTS operator_ids JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE auth_coach_catalog_import_run_saved_views
    DROP CONSTRAINT IF EXISTS chk_auth_coach_catalog_import_run_saved_views_operator_ids_array;

ALTER TABLE auth_coach_catalog_import_run_saved_views
    ADD CONSTRAINT chk_auth_coach_catalog_import_run_saved_views_operator_ids_array
    CHECK (jsonb_typeof(operator_ids) = 'array');

ALTER TABLE auth_coach_catalog_import_run_issue_saved_views
    DROP CONSTRAINT IF EXISTS chk_auth_coach_catalog_import_run_issue_saved_views_operator_ids_array;

ALTER TABLE auth_coach_catalog_import_run_issue_saved_views
    ADD CONSTRAINT chk_auth_coach_catalog_import_run_issue_saved_views_operator_ids_array
    CHECK (jsonb_typeof(operator_ids) = 'array');

CREATE INDEX IF NOT EXISTS idx_auth_coach_catalog_import_run_saved_views_operator_ids_gin
    ON auth_coach_catalog_import_run_saved_views USING GIN (operator_ids);

CREATE INDEX IF NOT EXISTS idx_auth_coach_catalog_import_run_issue_saved_views_operator_ids_gin
    ON auth_coach_catalog_import_run_issue_saved_views USING GIN (operator_ids);
