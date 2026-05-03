ALTER TABLE auth_coach_settlement_payout_import_preview_saved_views
    ADD COLUMN IF NOT EXISTS visibility_scope TEXT NOT NULL DEFAULT 'personal';

ALTER TABLE auth_coach_settlement_payout_import_preview_saved_views
    DROP CONSTRAINT IF EXISTS auth_coach_settlement_payout_import_preview_saved_views_visibility_scope_check;

ALTER TABLE auth_coach_settlement_payout_import_preview_saved_views
    ADD CONSTRAINT auth_coach_settlement_payout_import_preview_saved_views_visibility_scope_check
    CHECK (visibility_scope IN ('personal', 'shared_ops'));

DROP INDEX IF EXISTS idx_auth_coach_settlement_payout_import_preview_saved_views_account_name_lower;

CREATE UNIQUE INDEX IF NOT EXISTS idx_auth_coach_settlement_payout_import_preview_saved_views_personal_name_lower
    ON auth_coach_settlement_payout_import_preview_saved_views (account_id, lower(name))
    WHERE visibility_scope = 'personal';

CREATE UNIQUE INDEX IF NOT EXISTS idx_auth_coach_settlement_payout_import_preview_saved_views_shared_name_lower
    ON auth_coach_settlement_payout_import_preview_saved_views (lower(name))
    WHERE visibility_scope = 'shared_ops';
