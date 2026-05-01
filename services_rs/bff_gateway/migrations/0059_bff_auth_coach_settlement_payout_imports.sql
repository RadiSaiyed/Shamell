CREATE TABLE IF NOT EXISTS auth_coach_settlement_payout_imports (
    import_id TEXT PRIMARY KEY,
    payout_run_id TEXT NOT NULL,
    import_source TEXT NOT NULL,
    external_status TEXT NOT NULL,
    payment_reference TEXT,
    external_reference TEXT,
    imported_at TIMESTAMPTZ NOT NULL,
    imported_by_account_id TEXT NOT NULL,
    previous_run_status TEXT NOT NULL,
    applied_run_status TEXT NOT NULL,
    note TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_coach_settlement_payout_imports_import_id_nonempty
        CHECK (btrim(import_id) <> ''),
    CONSTRAINT chk_auth_coach_settlement_payout_imports_payout_run_id_nonempty
        CHECK (btrim(payout_run_id) <> ''),
    CONSTRAINT chk_auth_coach_settlement_payout_imports_import_source_nonempty
        CHECK (btrim(import_source) <> ''),
    CONSTRAINT chk_auth_coach_settlement_payout_imports_external_status_known
        CHECK (external_status IN ('pending', 'executed', 'failed')),
    CONSTRAINT chk_auth_coach_settlement_payout_imports_imported_by_nonempty
        CHECK (btrim(imported_by_account_id) <> ''),
    CONSTRAINT chk_auth_coach_settlement_payout_imports_previous_run_status_known
        CHECK (previous_run_status IN ('queued', 'paid', 'failed')),
    CONSTRAINT chk_auth_coach_settlement_payout_imports_applied_run_status_known
        CHECK (applied_run_status IN ('queued', 'paid', 'failed'))
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_settlement_payout_imports_run_imported
    ON auth_coach_settlement_payout_imports(payout_run_id, imported_at DESC);

CREATE INDEX IF NOT EXISTS idx_auth_coach_settlement_payout_imports_imported
    ON auth_coach_settlement_payout_imports(imported_at DESC);
