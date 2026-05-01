CREATE TABLE IF NOT EXISTS auth_coach_saved_view_favorites (
    account_id TEXT NOT NULL REFERENCES auth_accounts(account_id) ON DELETE CASCADE,
    collection_key TEXT NOT NULL,
    view_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (account_id, collection_key, view_id),
    CONSTRAINT auth_coach_saved_view_favorites_collection_key_chk CHECK (
        collection_key IN (
            'catalog_import_run_saved_views',
            'catalog_import_run_issue_saved_views',
            'payout_import_preview_saved_views',
            'payout_import_batch_saved_views'
        )
    )
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_saved_view_favorites_account_collection_updated_at
    ON auth_coach_saved_view_favorites (account_id, collection_key, updated_at DESC, view_id DESC);
