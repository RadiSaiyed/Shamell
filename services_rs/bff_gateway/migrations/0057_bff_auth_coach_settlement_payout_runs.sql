CREATE TABLE IF NOT EXISTS auth_coach_settlement_payout_runs (
    payout_run_id TEXT PRIMARY KEY,
    status TEXT NOT NULL,
    currency TEXT NOT NULL,
    statement_ids JSONB NOT NULL,
    operator_ids JSONB NOT NULL,
    operator_names JSONB NOT NULL,
    statement_count BIGINT NOT NULL,
    gross_minor_units BIGINT NOT NULL,
    reserve_minor_units BIGINT NOT NULL,
    net_payable_minor_units BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    paid_at TIMESTAMPTZ,
    created_by_account_id TEXT NOT NULL,
    paid_by_account_id TEXT,
    payment_reference TEXT,
    note TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_coach_settlement_payout_runs_payout_run_id_nonempty
        CHECK (btrim(payout_run_id) <> ''),
    CONSTRAINT chk_auth_coach_settlement_payout_runs_status_known
        CHECK (status IN ('queued', 'paid', 'failed')),
    CONSTRAINT chk_auth_coach_settlement_payout_runs_currency_len
        CHECK (char_length(btrim(currency)) = 3),
    CONSTRAINT chk_auth_coach_settlement_payout_runs_statement_ids_array
        CHECK (jsonb_typeof(statement_ids) = 'array'),
    CONSTRAINT chk_auth_coach_settlement_payout_runs_operator_ids_array
        CHECK (jsonb_typeof(operator_ids) = 'array'),
    CONSTRAINT chk_auth_coach_settlement_payout_runs_operator_names_array
        CHECK (jsonb_typeof(operator_names) = 'array'),
    CONSTRAINT chk_auth_coach_settlement_payout_runs_statement_count_positive
        CHECK (statement_count > 0),
    CONSTRAINT chk_auth_coach_settlement_payout_runs_created_by_nonempty
        CHECK (btrim(created_by_account_id) <> '')
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_settlement_payout_runs_status_created
    ON auth_coach_settlement_payout_runs(status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_auth_coach_settlement_payout_runs_created
    ON auth_coach_settlement_payout_runs(created_at DESC);
