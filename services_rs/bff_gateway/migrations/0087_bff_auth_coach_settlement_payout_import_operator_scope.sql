ALTER TABLE auth_coach_settlement_payout_import_batches
    ADD COLUMN IF NOT EXISTS operator_ids JSONB NOT NULL DEFAULT '[]'::jsonb;

UPDATE auth_coach_settlement_payout_import_batches AS batch
SET operator_ids = COALESCE(
    (
        SELECT jsonb_agg(operator_id)
        FROM (
            SELECT DISTINCT operator_id
            FROM (
                SELECT jsonb_array_elements_text(COALESCE(run.operator_ids, '[]'::jsonb)) AS operator_id
                FROM jsonb_array_elements_text(COALESCE(batch.payout_run_ids, '[]'::jsonb)) AS payout_run_ref(value)
                JOIN auth_coach_settlement_payout_runs AS run
                    ON run.payout_run_id = payout_run_ref.value
            ) scoped
            WHERE btrim(operator_id) <> ''
            ORDER BY operator_id
        ) deduped
    ),
    '[]'::jsonb
)
WHERE jsonb_array_length(COALESCE(batch.operator_ids, '[]'::jsonb)) = 0;

ALTER TABLE auth_coach_settlement_payout_import_batches
    DROP CONSTRAINT IF EXISTS chk_auth_coach_payout_import_batches_operator_ids_array;

ALTER TABLE auth_coach_settlement_payout_import_batches
    ADD CONSTRAINT chk_auth_coach_payout_import_batches_operator_ids_array
    CHECK (jsonb_typeof(operator_ids) = 'array');

CREATE INDEX IF NOT EXISTS idx_auth_coach_payout_import_batches_operator_ids_gin
    ON auth_coach_settlement_payout_import_batches USING GIN (operator_ids);

ALTER TABLE auth_coach_settlement_payout_import_report_artifacts
    ADD COLUMN IF NOT EXISTS operator_ids JSONB NOT NULL DEFAULT '[]'::jsonb;

UPDATE auth_coach_settlement_payout_import_report_artifacts AS artifact
SET operator_ids = COALESCE(batch.operator_ids, '[]'::jsonb)
FROM auth_coach_settlement_payout_import_batches AS batch
WHERE batch.batch_id = artifact.batch_id
  AND jsonb_array_length(COALESCE(artifact.operator_ids, '[]'::jsonb)) = 0;

ALTER TABLE auth_coach_settlement_payout_import_report_artifacts
    DROP CONSTRAINT IF EXISTS chk_auth_coach_payout_import_report_artifacts_operator_ids_array;

ALTER TABLE auth_coach_settlement_payout_import_report_artifacts
    ADD CONSTRAINT chk_auth_coach_payout_import_report_artifacts_operator_ids_array
    CHECK (jsonb_typeof(operator_ids) = 'array');

CREATE INDEX IF NOT EXISTS idx_auth_coach_payout_import_report_artifacts_operator_ids_gin
    ON auth_coach_settlement_payout_import_report_artifacts USING GIN (operator_ids);

ALTER TABLE auth_coach_settlement_payout_import_previews
    ADD COLUMN IF NOT EXISTS operator_ids JSONB NOT NULL DEFAULT '[]'::jsonb;

UPDATE auth_coach_settlement_payout_import_previews AS preview
SET operator_ids = COALESCE(batch.operator_ids, '[]'::jsonb)
FROM auth_coach_settlement_payout_import_batches AS batch
WHERE batch.batch_id = preview.rework_of_batch_id
  AND jsonb_array_length(COALESCE(preview.operator_ids, '[]'::jsonb)) = 0;

ALTER TABLE auth_coach_settlement_payout_import_previews
    DROP CONSTRAINT IF EXISTS chk_auth_coach_payout_import_previews_operator_ids_array;

ALTER TABLE auth_coach_settlement_payout_import_previews
    ADD CONSTRAINT chk_auth_coach_payout_import_previews_operator_ids_array
    CHECK (jsonb_typeof(operator_ids) = 'array');

CREATE INDEX IF NOT EXISTS idx_auth_coach_payout_import_previews_operator_ids_gin
    ON auth_coach_settlement_payout_import_previews USING GIN (operator_ids);
