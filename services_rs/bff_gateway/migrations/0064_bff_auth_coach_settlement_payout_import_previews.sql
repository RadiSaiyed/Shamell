CREATE TABLE IF NOT EXISTS auth_coach_settlement_payout_import_previews (
    preview_token text PRIMARY KEY,
    account_id text NOT NULL,
    import_source text NOT NULL,
    report_name text NOT NULL,
    report_format text NOT NULL,
    rework_of_batch_id text NULL,
    report_checksum_sha256 text NOT NULL,
    request_fingerprint text NOT NULL,
    preview_status text NOT NULL DEFAULT 'active',
    created_at timestamptz NOT NULL DEFAULT NOW(),
    expires_at timestamptz NOT NULL,
    consumed_at timestamptz NULL,
    CONSTRAINT chk_auth_coach_payout_import_previews_source_known CHECK (
        import_source IN ('bank_report', 'psp_report', 'manual_upload')
    ),
    CONSTRAINT chk_auth_coach_payout_import_previews_report_format_known CHECK (
        report_format IN ('csv')
    ),
    CONSTRAINT chk_auth_coach_payout_import_previews_status_known CHECK (
        preview_status IN ('active', 'consumed', 'expired')
    ),
    CONSTRAINT chk_auth_coach_payout_import_previews_consumed_requires_timestamp CHECK (
        preview_status <> 'consumed' OR consumed_at IS NOT NULL
    ),
    CONSTRAINT fk_auth_coach_payout_import_previews_rework_of_batch
        FOREIGN KEY (rework_of_batch_id)
        REFERENCES auth_coach_settlement_payout_import_batches (batch_id)
        ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_payout_import_previews_account_created_at
    ON auth_coach_settlement_payout_import_previews (account_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_auth_coach_payout_import_previews_account_status_expires_at
    ON auth_coach_settlement_payout_import_previews (account_id, preview_status, expires_at DESC);
