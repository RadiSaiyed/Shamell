ALTER TABLE auth_coach_settlement_payout_import_batches
    ADD COLUMN IF NOT EXISTS rework_of_batch_id TEXT NULL;

ALTER TABLE auth_coach_settlement_payout_import_batches
    DROP CONSTRAINT IF EXISTS fk_auth_coach_payout_import_batches_rework_of_batch;

ALTER TABLE auth_coach_settlement_payout_import_batches
    ADD CONSTRAINT fk_auth_coach_payout_import_batches_rework_of_batch
        FOREIGN KEY (rework_of_batch_id)
        REFERENCES auth_coach_settlement_payout_import_batches (batch_id)
        ON DELETE SET NULL;

ALTER TABLE auth_coach_settlement_payout_import_batches
    DROP CONSTRAINT IF EXISTS chk_auth_coach_payout_import_batches_rework_not_self;

ALTER TABLE auth_coach_settlement_payout_import_batches
    ADD CONSTRAINT chk_auth_coach_payout_import_batches_rework_not_self
        CHECK (rework_of_batch_id IS NULL OR rework_of_batch_id <> batch_id);

CREATE INDEX IF NOT EXISTS idx_auth_coach_payout_import_batches_rework_of_batch_id
    ON auth_coach_settlement_payout_import_batches (rework_of_batch_id)
    WHERE rework_of_batch_id IS NOT NULL;
