ALTER TABLE auth_coach_settlement_payout_import_report_artifacts
    ADD COLUMN IF NOT EXISTS artifact_kind TEXT NOT NULL DEFAULT 'source_report';

ALTER TABLE auth_coach_settlement_payout_import_report_artifacts
    DROP CONSTRAINT IF EXISTS uq_auth_coach_payout_import_report_artifacts_batch;

ALTER TABLE auth_coach_settlement_payout_import_report_artifacts
    DROP CONSTRAINT IF EXISTS chk_auth_coach_payout_import_report_artifacts_artifact_kind_known;

ALTER TABLE auth_coach_settlement_payout_import_report_artifacts
    ADD CONSTRAINT chk_auth_coach_payout_import_report_artifacts_artifact_kind_known
        CHECK (artifact_kind IN ('source_report', 'failed_row_rework'));

ALTER TABLE auth_coach_settlement_payout_import_report_artifacts
    ADD CONSTRAINT uq_auth_coach_payout_import_report_artifacts_batch_kind
        UNIQUE (batch_id, artifact_kind);
