CREATE TABLE IF NOT EXISTS auth_coach_settlement_exports (
    export_id TEXT PRIMARY KEY,
    payout_run_id TEXT NOT NULL,
    export_format TEXT NOT NULL,
    status TEXT NOT NULL,
    file_name TEXT NOT NULL,
    mime_type TEXT NOT NULL,
    download_path TEXT NOT NULL,
    checksum_sha256 TEXT NOT NULL,
    content_length_bytes BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    created_by_account_id TEXT NOT NULL,
    statement_ids JSONB NOT NULL,
    operator_ids JSONB NOT NULL,
    note TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_coach_settlement_exports_export_id_nonempty
        CHECK (btrim(export_id) <> ''),
    CONSTRAINT chk_auth_coach_settlement_exports_payout_run_id_nonempty
        CHECK (btrim(payout_run_id) <> ''),
    CONSTRAINT chk_auth_coach_settlement_exports_export_format_known
        CHECK (export_format IN ('csv', 'datev_json')),
    CONSTRAINT chk_auth_coach_settlement_exports_status_known
        CHECK (status IN ('ready', 'revoked')),
    CONSTRAINT chk_auth_coach_settlement_exports_file_name_nonempty
        CHECK (btrim(file_name) <> ''),
    CONSTRAINT chk_auth_coach_settlement_exports_mime_type_nonempty
        CHECK (btrim(mime_type) <> ''),
    CONSTRAINT chk_auth_coach_settlement_exports_download_path_nonempty
        CHECK (btrim(download_path) <> ''),
    CONSTRAINT chk_auth_coach_settlement_exports_checksum_nonempty
        CHECK (btrim(checksum_sha256) <> ''),
    CONSTRAINT chk_auth_coach_settlement_exports_content_length_nonnegative
        CHECK (content_length_bytes >= 0),
    CONSTRAINT chk_auth_coach_settlement_exports_created_by_nonempty
        CHECK (btrim(created_by_account_id) <> ''),
    CONSTRAINT chk_auth_coach_settlement_exports_statement_ids_array
        CHECK (jsonb_typeof(statement_ids) = 'array'),
    CONSTRAINT chk_auth_coach_settlement_exports_operator_ids_array
        CHECK (jsonb_typeof(operator_ids) = 'array'),
    CONSTRAINT uq_auth_coach_settlement_exports_run_format
        UNIQUE (payout_run_id, export_format)
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_settlement_exports_payout_run_created
    ON auth_coach_settlement_exports(payout_run_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_auth_coach_settlement_exports_created
    ON auth_coach_settlement_exports(created_at DESC);
