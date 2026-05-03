CREATE TABLE IF NOT EXISTS auth_coach_subledger_entries (
    entry_id TEXT PRIMARY KEY,
    occurred_at TIMESTAMPTZ NOT NULL,
    event_type TEXT NOT NULL,
    title TEXT NOT NULL,
    status TEXT NOT NULL,
    operator_id TEXT,
    operator_name TEXT,
    booking_id TEXT,
    statement_id TEXT,
    payout_run_id TEXT,
    request_id TEXT,
    import_id TEXT,
    reference_label TEXT,
    currency TEXT NOT NULL,
    primary_amount_minor_units BIGINT NOT NULL,
    needs_attention BOOLEAN NOT NULL DEFAULT FALSE,
    next_action TEXT,
    detail_lines JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_coach_subledger_entries_currency_len
        CHECK (char_length(currency) = 3),
    CONSTRAINT chk_auth_coach_subledger_entries_detail_lines_array
        CHECK (jsonb_typeof(detail_lines) = 'array')
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_subledger_entries_occurred_at
    ON auth_coach_subledger_entries(occurred_at DESC, entry_id DESC);

CREATE INDEX IF NOT EXISTS idx_auth_coach_subledger_entries_booking
    ON auth_coach_subledger_entries(booking_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_auth_coach_subledger_entries_payout_run
    ON auth_coach_subledger_entries(payout_run_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_auth_coach_subledger_entries_request
    ON auth_coach_subledger_entries(request_id, occurred_at DESC);

CREATE TABLE IF NOT EXISTS auth_coach_subledger_postings (
    posting_id TEXT PRIMARY KEY,
    entry_id TEXT NOT NULL REFERENCES auth_coach_subledger_entries(entry_id) ON DELETE CASCADE,
    account_code TEXT NOT NULL,
    account_label TEXT NOT NULL,
    direction TEXT NOT NULL,
    amount_minor_units BIGINT NOT NULL,
    signed_minor_units BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_coach_subledger_postings_direction_known
        CHECK (direction IN ('increase', 'decrease')),
    CONSTRAINT chk_auth_coach_subledger_postings_amount_non_negative
        CHECK (amount_minor_units >= 0),
    CONSTRAINT chk_auth_coach_subledger_postings_amount_matches_signed
        CHECK (amount_minor_units = ABS(signed_minor_units))
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_subledger_postings_entry
    ON auth_coach_subledger_postings(entry_id, created_at ASC);

CREATE INDEX IF NOT EXISTS idx_auth_coach_subledger_postings_account_code
    ON auth_coach_subledger_postings(account_code, created_at DESC);
