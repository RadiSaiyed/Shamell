CREATE TABLE IF NOT EXISTS auth_coach_settlement_payout_import_report_artifacts (
    artifact_id TEXT PRIMARY KEY,
    batch_id TEXT NOT NULL,
    import_source TEXT NOT NULL,
    report_name TEXT NOT NULL,
    report_format TEXT NOT NULL,
    file_name TEXT NOT NULL,
    mime_type TEXT NOT NULL,
    download_path TEXT NOT NULL,
    checksum_sha256 TEXT NOT NULL,
    content_length_bytes BIGINT NOT NULL,
    report_body TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by_account_id TEXT NOT NULL,
    note TEXT,
    CONSTRAINT fk_auth_coach_payout_import_report_artifacts_batch
        FOREIGN KEY (batch_id)
        REFERENCES auth_coach_settlement_payout_import_batches(batch_id)
        ON DELETE CASCADE,
    CONSTRAINT chk_auth_coach_payout_import_report_artifacts_artifact_id_nonempty
        CHECK (btrim(artifact_id) <> ''),
    CONSTRAINT chk_auth_coach_payout_import_report_artifacts_batch_id_nonempty
        CHECK (btrim(batch_id) <> ''),
    CONSTRAINT chk_auth_coach_payout_import_report_artifacts_import_source_known
        CHECK (import_source IN ('bank_report', 'psp_report', 'manual_upload')),
    CONSTRAINT chk_auth_coach_payout_import_report_artifacts_report_name_nonempty
        CHECK (btrim(report_name) <> ''),
    CONSTRAINT chk_auth_coach_payout_import_report_artifacts_report_format_known
        CHECK (report_format IN ('csv')),
    CONSTRAINT chk_auth_coach_payout_import_report_artifacts_file_name_nonempty
        CHECK (btrim(file_name) <> ''),
    CONSTRAINT chk_auth_coach_payout_import_report_artifacts_mime_type_nonempty
        CHECK (btrim(mime_type) <> ''),
    CONSTRAINT chk_auth_coach_payout_import_report_artifacts_download_path_nonempty
        CHECK (btrim(download_path) <> ''),
    CONSTRAINT chk_auth_coach_payout_import_report_artifacts_checksum_nonempty
        CHECK (btrim(checksum_sha256) <> ''),
    CONSTRAINT chk_auth_coach_payout_import_report_artifacts_content_length_nonnegative
        CHECK (content_length_bytes >= 0),
    CONSTRAINT chk_auth_coach_payout_import_report_artifacts_report_body_nonempty
        CHECK (btrim(report_body) <> ''),
    CONSTRAINT chk_auth_coach_payout_import_report_artifacts_created_by_nonempty
        CHECK (btrim(created_by_account_id) <> ''),
    CONSTRAINT uq_auth_coach_payout_import_report_artifacts_batch
        UNIQUE (batch_id)
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_payout_import_report_artifacts_created
    ON auth_coach_settlement_payout_import_report_artifacts(created_at DESC);
