CREATE TABLE IF NOT EXISTS auth_coach_catalog_import_run_issues (
    issue_id TEXT PRIMARY KEY,
    import_run_id TEXT NOT NULL REFERENCES auth_coach_catalog_import_runs(import_run_id) ON DELETE CASCADE,
    severity TEXT NOT NULL,
    stage TEXT NOT NULL,
    code TEXT NOT NULL,
    message TEXT NOT NULL,
    file_name TEXT,
    row_reference TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_coach_catalog_import_run_issues_severity_known CHECK (
        severity IN ('error', 'warning')
    ),
    CONSTRAINT chk_auth_coach_catalog_import_run_issues_stage_known CHECK (
        stage IN ('load_feed', 'parse_csv', 'build_catalog', 'persist_catalog', 'feed_health')
    ),
    CONSTRAINT chk_auth_coach_catalog_import_run_issues_code_nonempty CHECK (
        LENGTH(BTRIM(code)) > 0
    ),
    CONSTRAINT chk_auth_coach_catalog_import_run_issues_message_nonempty CHECK (
        LENGTH(BTRIM(message)) > 0
    ),
    CONSTRAINT chk_auth_coach_catalog_import_run_issues_file_name_nonempty CHECK (
        file_name IS NULL OR LENGTH(BTRIM(file_name)) > 0
    ),
    CONSTRAINT chk_auth_coach_catalog_import_run_issues_row_reference_nonempty CHECK (
        row_reference IS NULL OR LENGTH(BTRIM(row_reference)) > 0
    )
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_catalog_import_run_issues_import_run
    ON auth_coach_catalog_import_run_issues (import_run_id, created_at ASC, issue_id ASC);

CREATE INDEX IF NOT EXISTS idx_auth_coach_catalog_import_run_issues_severity
    ON auth_coach_catalog_import_run_issues (severity, created_at DESC);
