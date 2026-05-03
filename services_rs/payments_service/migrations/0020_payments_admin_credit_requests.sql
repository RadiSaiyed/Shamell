CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.admin_credit_requests (
    id VARCHAR(36) PRIMARY KEY,
    wallet_id VARCHAR(36) NOT NULL,
    account_id VARCHAR(64),
    requested_by_account_id VARCHAR(64) NOT NULL,
    approved_by_account_id VARCHAR(64),
    amount_cents BIGINT NOT NULL,
    currency VARCHAR(3) NOT NULL,
    balance_cents BIGINT,
    reason VARCHAR(96) NOT NULL,
    note VARCHAR(255),
    status VARCHAR(24) NOT NULL,
    txn_id VARCHAR(36) UNIQUE,
    requested_at TIMESTAMPTZ NOT NULL,
    approved_at TIMESTAMPTZ,
    credited_at TIMESTAMPTZ,
    rejected_at TIMESTAMPTZ,
    CONSTRAINT fk_admin_credit_requests_wallet_id
        FOREIGN KEY (wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE RESTRICT,
    CONSTRAINT fk_admin_credit_requests_txn_id
        FOREIGN KEY (txn_id) REFERENCES __PAYMENTS_SCHEMA__.txns(id) ON DELETE RESTRICT,
    CONSTRAINT chk_admin_credit_requests_amount_cents_positive CHECK (amount_cents > 0),
    CONSTRAINT chk_admin_credit_requests_balance_cents_non_negative
        CHECK (balance_cents IS NULL OR balance_cents >= 0),
    CONSTRAINT chk_admin_credit_requests_reason_present CHECK (BTRIM(reason) <> ''),
    CONSTRAINT chk_admin_credit_requests_status_known
        CHECK (status = ANY (ARRAY['pending_approval', 'credited', 'rejected'])),
    CONSTRAINT chk_admin_credit_requests_approver_distinct
        CHECK (approved_by_account_id IS NULL OR approved_by_account_id <> requested_by_account_id),
    CONSTRAINT chk_admin_credit_requests_credited_shape
        CHECK (status <> 'credited' OR (txn_id IS NOT NULL AND balance_cents IS NOT NULL AND credited_at IS NOT NULL)),
    CONSTRAINT chk_admin_credit_requests_pending_shape
        CHECK (status <> 'pending_approval' OR (txn_id IS NULL AND balance_cents IS NULL AND approved_by_account_id IS NULL AND approved_at IS NULL AND credited_at IS NULL)),
    CONSTRAINT chk_admin_credit_requests_approved_at_not_before_requested
        CHECK (approved_at IS NULL OR approved_at >= requested_at),
    CONSTRAINT chk_admin_credit_requests_credited_at_not_before_requested
        CHECK (credited_at IS NULL OR credited_at >= requested_at),
    CONSTRAINT chk_admin_credit_requests_rejected_at_not_before_requested
        CHECK (rejected_at IS NULL OR rejected_at >= requested_at)
);

CREATE INDEX IF NOT EXISTS idx_admin_credit_requests_requested_at_id
    ON __PAYMENTS_SCHEMA__.admin_credit_requests(requested_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_admin_credit_requests_wallet_requested_id
    ON __PAYMENTS_SCHEMA__.admin_credit_requests(wallet_id, requested_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_admin_credit_requests_operator_requested_id
    ON __PAYMENTS_SCHEMA__.admin_credit_requests(requested_by_account_id, requested_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_admin_credit_requests_status_requested_id
    ON __PAYMENTS_SCHEMA__.admin_credit_requests(status, requested_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_admin_credit_requests_account_requested_id
    ON __PAYMENTS_SCHEMA__.admin_credit_requests(account_id, requested_at DESC, id DESC)
    WHERE account_id IS NOT NULL;
