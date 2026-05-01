ALTER TABLE __PAYMENTS_SCHEMA__.txns
    DROP CONSTRAINT IF EXISTS chk_txns_kind_known;

ALTER TABLE __PAYMENTS_SCHEMA__.txns
    ADD CONSTRAINT chk_txns_kind_known CHECK (
        kind = ANY (
            ARRAY[
                'topup',
                'transfer',
                'exchange_debit',
                'exchange_credit',
                'refund'
            ]
        )
    );

ALTER TABLE __PAYMENTS_SCHEMA__.users
    ADD COLUMN IF NOT EXISTS kyc_status VARCHAR(24) NOT NULL DEFAULT 'unverified';

ALTER TABLE __PAYMENTS_SCHEMA__.users
    DROP CONSTRAINT IF EXISTS chk_users_kyc_status_known;

ALTER TABLE __PAYMENTS_SCHEMA__.users
    ADD CONSTRAINT chk_users_kyc_status_known CHECK (
        kyc_status = ANY (ARRAY['unverified', 'basic', 'verified', 'business', 'rejected'])
    );

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.wallet_controls (
    wallet_id VARCHAR(36) PRIMARY KEY,
    frozen BOOLEAN NOT NULL DEFAULT FALSE,
    reason VARCHAR(255),
    operator_account_id VARCHAR(64),
    updated_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_wallet_controls_wallet_id
        FOREIGN KEY (wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.wallet_holds (
    id VARCHAR(36) PRIMARY KEY,
    wallet_id VARCHAR(36) NOT NULL,
    amount_cents BIGINT NOT NULL,
    currency VARCHAR(3) NOT NULL,
    reason VARCHAR(255),
    status VARCHAR(16) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ,
    released_at TIMESTAMPTZ,
    CONSTRAINT fk_wallet_holds_wallet_id
        FOREIGN KEY (wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE,
    CONSTRAINT chk_wallet_holds_amount_positive CHECK (amount_cents > 0),
    CONSTRAINT chk_wallet_holds_status_known
        CHECK (status = ANY (ARRAY['active', 'released', 'expired']))
);

CREATE INDEX IF NOT EXISTS idx_wallet_holds_wallet_status_created
    ON __PAYMENTS_SCHEMA__.wallet_holds(wallet_id, status, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.exchange_quotes (
    id VARCHAR(36) PRIMARY KEY,
    from_wallet_id VARCHAR(36) NOT NULL,
    to_wallet_id VARCHAR(36) NOT NULL,
    from_currency VARCHAR(3) NOT NULL,
    to_currency VARCHAR(3) NOT NULL,
    amount_cents BIGINT NOT NULL,
    expected_amount_cents BIGINT NOT NULL,
    rate_bps BIGINT NOT NULL,
    fee_bps BIGINT NOT NULL DEFAULT 0,
    status VARCHAR(16) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ,
    debit_txn_id VARCHAR(36),
    credit_txn_id VARCHAR(36),
    CONSTRAINT fk_exchange_quotes_from_wallet_id
        FOREIGN KEY (from_wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE RESTRICT,
    CONSTRAINT fk_exchange_quotes_to_wallet_id
        FOREIGN KEY (to_wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE RESTRICT,
    CONSTRAINT fk_exchange_quotes_debit_txn_id
        FOREIGN KEY (debit_txn_id) REFERENCES __PAYMENTS_SCHEMA__.txns(id) ON DELETE RESTRICT,
    CONSTRAINT fk_exchange_quotes_credit_txn_id
        FOREIGN KEY (credit_txn_id) REFERENCES __PAYMENTS_SCHEMA__.txns(id) ON DELETE RESTRICT,
    CONSTRAINT chk_exchange_quotes_amounts_positive
        CHECK (amount_cents > 0 AND expected_amount_cents > 0),
    CONSTRAINT chk_exchange_quotes_rate_positive CHECK (rate_bps > 0),
    CONSTRAINT chk_exchange_quotes_fee_non_negative CHECK (fee_bps >= 0),
    CONSTRAINT chk_exchange_quotes_status_known
        CHECK (status = ANY (ARRAY['quoted', 'executed', 'expired', 'canceled']))
);

CREATE INDEX IF NOT EXISTS idx_exchange_quotes_from_wallet_created
    ON __PAYMENTS_SCHEMA__.exchange_quotes(from_wallet_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_exchange_quotes_to_wallet_created
    ON __PAYMENTS_SCHEMA__.exchange_quotes(to_wallet_id, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.payment_refunds (
    id VARCHAR(36) PRIMARY KEY,
    original_txn_id VARCHAR(36) NOT NULL,
    requester_wallet_id VARCHAR(36) NOT NULL,
    from_wallet_id VARCHAR(36) NOT NULL,
    to_wallet_id VARCHAR(36) NOT NULL,
    amount_cents BIGINT NOT NULL,
    currency VARCHAR(3) NOT NULL,
    reason VARCHAR(255),
    status VARCHAR(16) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    resolved_at TIMESTAMPTZ,
    approver_account_id VARCHAR(64),
    refund_txn_id VARCHAR(36),
    CONSTRAINT fk_payment_refunds_original_txn_id
        FOREIGN KEY (original_txn_id) REFERENCES __PAYMENTS_SCHEMA__.txns(id) ON DELETE RESTRICT,
    CONSTRAINT fk_payment_refunds_requester_wallet_id
        FOREIGN KEY (requester_wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE RESTRICT,
    CONSTRAINT fk_payment_refunds_from_wallet_id
        FOREIGN KEY (from_wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE RESTRICT,
    CONSTRAINT fk_payment_refunds_to_wallet_id
        FOREIGN KEY (to_wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE RESTRICT,
    CONSTRAINT fk_payment_refunds_refund_txn_id
        FOREIGN KEY (refund_txn_id) REFERENCES __PAYMENTS_SCHEMA__.txns(id) ON DELETE RESTRICT,
    CONSTRAINT chk_payment_refunds_amount_positive CHECK (amount_cents > 0),
    CONSTRAINT chk_payment_refunds_status_known
        CHECK (status = ANY (ARRAY['pending', 'approved', 'rejected']))
);

CREATE INDEX IF NOT EXISTS idx_payment_refunds_wallet_status_created
    ON __PAYMENTS_SCHEMA__.payment_refunds(requester_wallet_id, status, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.recurring_payments (
    id VARCHAR(36) PRIMARY KEY,
    from_wallet_id VARCHAR(36) NOT NULL,
    to_wallet_id VARCHAR(36) NOT NULL,
    amount_cents BIGINT NOT NULL,
    currency VARCHAR(3) NOT NULL,
    interval_days INTEGER NOT NULL,
    note VARCHAR(255),
    status VARCHAR(16) NOT NULL,
    next_run_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_recurring_payments_from_wallet_id
        FOREIGN KEY (from_wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE,
    CONSTRAINT fk_recurring_payments_to_wallet_id
        FOREIGN KEY (to_wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE,
    CONSTRAINT chk_recurring_payments_amount_positive CHECK (amount_cents > 0),
    CONSTRAINT chk_recurring_payments_interval_positive CHECK (interval_days > 0),
    CONSTRAINT chk_recurring_payments_status_known
        CHECK (status = ANY (ARRAY['active', 'paused', 'canceled']))
);

CREATE INDEX IF NOT EXISTS idx_recurring_payments_wallet_status_next
    ON __PAYMENTS_SCHEMA__.recurring_payments(from_wallet_id, status, next_run_at, id);

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.merchant_profiles (
    wallet_id VARCHAR(36) PRIMARY KEY,
    merchant_name VARCHAR(96) NOT NULL,
    category VARCHAR(64),
    settlement_wallet_id VARCHAR(36),
    status VARCHAR(16) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_merchant_profiles_wallet_id
        FOREIGN KEY (wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE,
    CONSTRAINT fk_merchant_profiles_settlement_wallet_id
        FOREIGN KEY (settlement_wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE SET NULL,
    CONSTRAINT chk_merchant_profiles_status_known
        CHECK (status = ANY (ARRAY['active', 'paused']))
);

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.mini_payment_intents (
    id VARCHAR(36) PRIMARY KEY,
    wallet_id VARCHAR(36) NOT NULL,
    amount_cents BIGINT NOT NULL,
    currency VARCHAR(3) NOT NULL,
    merchant_reference VARCHAR(96),
    status VARCHAR(16) NOT NULL,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_mini_payment_intents_wallet_id
        FOREIGN KEY (wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE,
    CONSTRAINT chk_mini_payment_intents_amount_positive CHECK (amount_cents > 0),
    CONSTRAINT chk_mini_payment_intents_status_known
        CHECK (status = ANY (ARRAY['pending', 'authorized', 'captured', 'canceled', 'expired']))
);

CREATE INDEX IF NOT EXISTS idx_mini_payment_intents_wallet_created
    ON __PAYMENTS_SCHEMA__.mini_payment_intents(wallet_id, created_at DESC, id DESC);
