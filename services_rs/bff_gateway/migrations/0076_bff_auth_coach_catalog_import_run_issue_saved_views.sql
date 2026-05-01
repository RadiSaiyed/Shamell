CREATE TABLE IF NOT EXISTS auth_coach_catalog_import_run_issue_saved_views (
    view_id text PRIMARY KEY,
    account_id text NOT NULL,
    name text NOT NULL,
    severity_filter text NOT NULL,
    stage_filter text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_catalog_import_run_issue_saved_views_account_updated
    ON auth_coach_catalog_import_run_issue_saved_views (account_id, updated_at DESC, view_id DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_auth_coach_catalog_import_run_issue_saved_views_account_name_lower
    ON auth_coach_catalog_import_run_issue_saved_views (account_id, lower(name));
