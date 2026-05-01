ALTER TABLE auth_coach_catalog_import_run_saved_views
    ADD COLUMN IF NOT EXISTS issue_severity_filter TEXT NOT NULL DEFAULT 'all';

ALTER TABLE auth_coach_catalog_import_run_saved_views
    ADD COLUMN IF NOT EXISTS issue_stage_filter TEXT NOT NULL DEFAULT 'all';
