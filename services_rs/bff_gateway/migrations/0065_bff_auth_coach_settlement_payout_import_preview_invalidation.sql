ALTER TABLE auth_coach_settlement_payout_import_previews
    ADD COLUMN IF NOT EXISTS invalidated_at timestamptz NULL;

ALTER TABLE auth_coach_settlement_payout_import_previews
    DROP CONSTRAINT IF EXISTS chk_auth_coach_payout_import_previews_status_known;

ALTER TABLE auth_coach_settlement_payout_import_previews
    ADD CONSTRAINT chk_auth_coach_payout_import_previews_status_known CHECK (
        preview_status IN ('active', 'consumed', 'expired', 'invalidated')
    );

ALTER TABLE auth_coach_settlement_payout_import_previews
    DROP CONSTRAINT IF EXISTS chk_auth_coach_payout_import_previews_consumed_requires_timestamp;

ALTER TABLE auth_coach_settlement_payout_import_previews
    ADD CONSTRAINT chk_auth_coach_payout_import_previews_consumed_requires_timestamp CHECK (
        preview_status <> 'consumed' OR consumed_at IS NOT NULL
    );

ALTER TABLE auth_coach_settlement_payout_import_previews
    ADD CONSTRAINT chk_auth_coach_payout_import_previews_invalidated_requires_timestamp CHECK (
        preview_status <> 'invalidated' OR invalidated_at IS NOT NULL
    );

ALTER TABLE auth_coach_settlement_payout_import_previews
    ADD CONSTRAINT chk_auth_coach_payout_import_previews_terminal_timestamps_exclusive CHECK (
        consumed_at IS NULL OR invalidated_at IS NULL
    );
