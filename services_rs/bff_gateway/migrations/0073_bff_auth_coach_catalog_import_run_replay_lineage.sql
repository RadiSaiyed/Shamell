ALTER TABLE auth_coach_catalog_import_runs
    ADD COLUMN IF NOT EXISTS replayed_from_import_run_id TEXT;

CREATE INDEX IF NOT EXISTS idx_auth_coach_catalog_import_runs_replayed_from
    ON auth_coach_catalog_import_runs (replayed_from_import_run_id);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_auth_coach_catalog_import_runs_replayed_from'
    ) THEN
        ALTER TABLE auth_coach_catalog_import_runs
            ADD CONSTRAINT fk_auth_coach_catalog_import_runs_replayed_from
            FOREIGN KEY (replayed_from_import_run_id)
            REFERENCES auth_coach_catalog_import_runs (import_run_id)
            ON DELETE SET NULL;
    END IF;
END $$;
