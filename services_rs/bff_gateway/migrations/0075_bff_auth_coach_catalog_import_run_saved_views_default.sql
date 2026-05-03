ALTER TABLE auth_coach_catalog_import_run_saved_views
    ADD COLUMN IF NOT EXISTS is_default BOOLEAN NOT NULL DEFAULT FALSE;

CREATE UNIQUE INDEX IF NOT EXISTS idx_auth_coach_catalog_import_run_saved_views_account_default
    ON auth_coach_catalog_import_run_saved_views (account_id)
    WHERE is_default = TRUE;
