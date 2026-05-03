ALTER TABLE auth_coach_settlement_payout_import_preview_saved_views
    ADD COLUMN IF NOT EXISTS is_default BOOLEAN NOT NULL DEFAULT FALSE;

CREATE UNIQUE INDEX IF NOT EXISTS idx_auth_coach_settlement_payout_import_preview_saved_views_default_per_account
    ON auth_coach_settlement_payout_import_preview_saved_views (account_id)
    WHERE is_default = TRUE;
