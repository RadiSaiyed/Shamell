CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.admin_credit_events (
    id VARCHAR(36) PRIMARY KEY,
    txn_id VARCHAR(36) NOT NULL UNIQUE,
    wallet_id VARCHAR(36) NOT NULL,
    account_id VARCHAR(64),
    operator_account_id VARCHAR(64) NOT NULL,
    amount_cents BIGINT NOT NULL,
    currency VARCHAR(3) NOT NULL,
    balance_cents BIGINT NOT NULL,
    reason VARCHAR(96) NOT NULL,
    note VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_admin_credit_events_txn_id
        FOREIGN KEY (txn_id) REFERENCES __PAYMENTS_SCHEMA__.txns(id) ON DELETE RESTRICT,
    CONSTRAINT fk_admin_credit_events_wallet_id
        FOREIGN KEY (wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE RESTRICT,
    CONSTRAINT chk_admin_credit_events_amount_cents_positive CHECK (amount_cents > 0),
    CONSTRAINT chk_admin_credit_events_balance_cents_non_negative CHECK (balance_cents >= 0),
    CONSTRAINT chk_admin_credit_events_reason_present CHECK (BTRIM(reason) <> '')
);

CREATE INDEX IF NOT EXISTS idx_admin_credit_events_wallet_created_id
    ON __PAYMENTS_SCHEMA__.admin_credit_events(wallet_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_admin_credit_events_operator_created_id
    ON __PAYMENTS_SCHEMA__.admin_credit_events(operator_account_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_admin_credit_events_account_created_id
    ON __PAYMENTS_SCHEMA__.admin_credit_events(account_id, created_at DESC, id DESC)
    WHERE account_id IS NOT NULL;
