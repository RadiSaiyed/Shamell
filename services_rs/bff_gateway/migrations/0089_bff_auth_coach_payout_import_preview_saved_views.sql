CREATE TABLE IF NOT EXISTS auth_coach_settlement_payout_import_preview_saved_views (
    view_id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL REFERENCES auth_accounts(account_id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    status_filter TEXT NOT NULL DEFAULT 'all',
    from_created_at TIMESTAMPTZ NULL,
    to_created_at TIMESTAMPTZ NULL,
    operator_id TEXT NOT NULL DEFAULT 'all',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT auth_coach_settlement_payout_import_preview_saved_views_status_filter_nonempty
        CHECK (btrim(status_filter) <> ''),
    CONSTRAINT auth_coach_settlement_payout_import_preview_saved_views_operator_id_nonempty
        CHECK (btrim(operator_id) <> ''),
    CONSTRAINT auth_coach_settlement_payout_import_preview_saved_views_created_at_range
        CHECK (
            from_created_at IS NULL
            OR to_created_at IS NULL
            OR from_created_at <= to_created_at
        )
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_settlement_payout_import_preview_saved_views_account_updated
    ON auth_coach_settlement_payout_import_preview_saved_views (account_id, updated_at DESC, view_id DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_auth_coach_settlement_payout_import_preview_saved_views_account_name_lower
    ON auth_coach_settlement_payout_import_preview_saved_views (account_id, lower(name));
