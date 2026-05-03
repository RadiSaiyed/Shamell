CREATE TABLE IF NOT EXISTS auth_coach_saved_view_usage (
    account_id TEXT NOT NULL REFERENCES auth_accounts(account_id) ON DELETE CASCADE,
    collection_key TEXT NOT NULL CHECK (
        collection_key IN (
            'catalog_import_run_saved_views',
            'catalog_import_run_issue_saved_views',
            'payout_import_preview_saved_views',
            'payout_import_batch_saved_views'
        )
    ),
    view_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    used_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (account_id, collection_key, view_id)
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_saved_view_usage_account_collection_used_at
    ON auth_coach_saved_view_usage(account_id, collection_key, used_at DESC, view_id DESC);
