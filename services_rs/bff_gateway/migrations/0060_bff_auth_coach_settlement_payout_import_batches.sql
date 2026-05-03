CREATE TABLE IF NOT EXISTS auth_coach_settlement_payout_import_batches (
    batch_id text PRIMARY KEY,
    import_source text NOT NULL,
    report_name text NOT NULL,
    report_format text NOT NULL,
    report_checksum_sha256 text NOT NULL,
    total_rows bigint NOT NULL,
    applied_rows bigint NOT NULL,
    failed_rows bigint NOT NULL,
    payout_run_ids jsonb NOT NULL DEFAULT '[]'::jsonb,
    failure_messages jsonb NOT NULL DEFAULT '[]'::jsonb,
    created_at timestamptz NOT NULL DEFAULT NOW(),
    created_by_account_id text NOT NULL,
    note text NULL,
    updated_at timestamptz NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_coach_payout_import_batches_source_known CHECK (
        import_source IN ('bank_report', 'psp_report', 'manual_upload')
    ),
    CONSTRAINT chk_auth_coach_payout_import_batches_report_format_known CHECK (
        report_format IN ('csv')
    ),
    CONSTRAINT chk_auth_coach_payout_import_batches_row_counts_non_negative CHECK (
        total_rows >= 0
        AND applied_rows >= 0
        AND failed_rows >= 0
    )
);

ALTER TABLE auth_coach_settlement_payout_imports
    ADD COLUMN IF NOT EXISTS import_batch_id text;

CREATE INDEX IF NOT EXISTS idx_auth_coach_payout_import_batches_created_at
    ON auth_coach_settlement_payout_import_batches (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_auth_coach_payout_imports_batch_id
    ON auth_coach_settlement_payout_imports (import_batch_id)
    WHERE import_batch_id IS NOT NULL;
