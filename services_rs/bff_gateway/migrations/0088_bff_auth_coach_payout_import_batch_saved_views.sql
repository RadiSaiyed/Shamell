CREATE TABLE IF NOT EXISTS auth_coach_settlement_payout_import_batch_saved_views (
    view_id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL REFERENCES auth_accounts(account_id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    operator_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT auth_coach_settlement_payout_import_batch_saved_views_operator_id_nonempty
        CHECK (btrim(operator_id) <> '')
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_settlement_payout_import_batch_saved_views_account_updated
    ON auth_coach_settlement_payout_import_batch_saved_views (account_id, updated_at DESC, view_id DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_auth_coach_settlement_payout_import_batch_saved_views_account_name_lower
    ON auth_coach_settlement_payout_import_batch_saved_views (account_id, lower(name));
