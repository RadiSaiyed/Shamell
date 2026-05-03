ALTER TABLE __PAYMENTS_SCHEMA__.mini_payment_intents
    ADD COLUMN IF NOT EXISTS paid_txn_id VARCHAR(36);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_mini_payment_intents_paid_txn_id'
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.mini_payment_intents
            ADD CONSTRAINT fk_mini_payment_intents_paid_txn_id
            FOREIGN KEY (paid_txn_id) REFERENCES __PAYMENTS_SCHEMA__.txns(id) ON DELETE RESTRICT;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.payment_links (
    id VARCHAR(36) PRIMARY KEY,
    wallet_id VARCHAR(36) NOT NULL,
    amount_cents BIGINT NOT NULL,
    currency VARCHAR(3) NOT NULL,
    purpose VARCHAR(255),
    status VARCHAR(16) NOT NULL,
    url_path VARCHAR(128) NOT NULL UNIQUE,
    paid_txn_id VARCHAR(36),
    created_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ,
    paid_at TIMESTAMPTZ,
    CONSTRAINT fk_payment_links_wallet_id
        FOREIGN KEY (wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE,
    CONSTRAINT fk_payment_links_paid_txn_id
        FOREIGN KEY (paid_txn_id) REFERENCES __PAYMENTS_SCHEMA__.txns(id) ON DELETE RESTRICT,
    CONSTRAINT chk_payment_links_amount_positive CHECK (amount_cents > 0),
    CONSTRAINT chk_payment_links_status_known
        CHECK (status = ANY (ARRAY['active', 'paid', 'expired', 'canceled']))
);

CREATE INDEX IF NOT EXISTS idx_payment_links_wallet_status_created
    ON __PAYMENTS_SCHEMA__.payment_links(wallet_id, status, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.merchant_webhooks (
    id VARCHAR(36) PRIMARY KEY,
    wallet_id VARCHAR(36) NOT NULL,
    url TEXT NOT NULL,
    events JSONB NOT NULL,
    secret_hint VARCHAR(64),
    status VARCHAR(16) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_merchant_webhooks_wallet_id
        FOREIGN KEY (wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE,
    CONSTRAINT chk_merchant_webhooks_status_known
        CHECK (status = ANY (ARRAY['active', 'paused']))
);

CREATE INDEX IF NOT EXISTS idx_merchant_webhooks_wallet_created
    ON __PAYMENTS_SCHEMA__.merchant_webhooks(wallet_id, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.payment_events (
    id VARCHAR(36) PRIMARY KEY,
    wallet_id VARCHAR(36) NOT NULL,
    event_type VARCHAR(64) NOT NULL,
    title VARCHAR(128) NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_payment_events_wallet_id
        FOREIGN KEY (wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_payment_events_wallet_created
    ON __PAYMENTS_SCHEMA__.payment_events(wallet_id, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.merchant_settlements (
    id VARCHAR(36) PRIMARY KEY,
    wallet_id VARCHAR(36) NOT NULL,
    amount_cents BIGINT NOT NULL,
    currency VARCHAR(3) NOT NULL,
    destination_ref VARCHAR(128),
    status VARCHAR(16) NOT NULL,
    operator_account_id VARCHAR(64),
    note VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL,
    resolved_at TIMESTAMPTZ,
    CONSTRAINT fk_merchant_settlements_wallet_id
        FOREIGN KEY (wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE,
    CONSTRAINT chk_merchant_settlements_amount_positive CHECK (amount_cents > 0),
    CONSTRAINT chk_merchant_settlements_status_known
        CHECK (status = ANY (ARRAY['pending', 'approved', 'rejected', 'paid']))
);

CREATE INDEX IF NOT EXISTS idx_merchant_settlements_wallet_status_created
    ON __PAYMENTS_SCHEMA__.merchant_settlements(wallet_id, status, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.risk_rules (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(96) NOT NULL,
    rule_type VARCHAR(32) NOT NULL,
    threshold_cents BIGINT,
    threshold_count BIGINT,
    action VARCHAR(32) NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT chk_risk_rules_type_known
        CHECK (rule_type = ANY (ARRAY['high_value_txn', 'txn_velocity', 'refund_velocity'])),
    CONSTRAINT chk_risk_rules_action_known
        CHECK (action = ANY (ARRAY['alert', 'review', 'freeze']))
);

CREATE INDEX IF NOT EXISTS idx_risk_rules_enabled_created
    ON __PAYMENTS_SCHEMA__.risk_rules(enabled, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.payment_disputes (
    id VARCHAR(36) PRIMARY KEY,
    wallet_id VARCHAR(36) NOT NULL,
    txn_id VARCHAR(36) NOT NULL,
    reason VARCHAR(255) NOT NULL,
    evidence_text TEXT,
    status VARCHAR(16) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    resolved_at TIMESTAMPTZ,
    CONSTRAINT fk_payment_disputes_wallet_id
        FOREIGN KEY (wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE,
    CONSTRAINT fk_payment_disputes_txn_id
        FOREIGN KEY (txn_id) REFERENCES __PAYMENTS_SCHEMA__.txns(id) ON DELETE RESTRICT,
    CONSTRAINT chk_payment_disputes_status_known
        CHECK (status = ANY (ARRAY['open', 'review', 'won', 'lost', 'closed']))
);

CREATE INDEX IF NOT EXISTS idx_payment_disputes_wallet_status_created
    ON __PAYMENTS_SCHEMA__.payment_disputes(wallet_id, status, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.wallet_aliases (
    alias VARCHAR(96) PRIMARY KEY,
    wallet_id VARCHAR(36) NOT NULL,
    alias_type VARCHAR(24) NOT NULL,
    verified BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_wallet_aliases_wallet_id
        FOREIGN KEY (wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE,
    CONSTRAINT chk_wallet_aliases_type_known
        CHECK (alias_type = ANY (ARRAY['username', 'phone', 'merchant', 'qr']))
);

CREATE INDEX IF NOT EXISTS idx_wallet_aliases_wallet_created
    ON __PAYMENTS_SCHEMA__.wallet_aliases(wallet_id, created_at DESC, alias);

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.kyc_documents (
    id VARCHAR(36) PRIMARY KEY,
    wallet_id VARCHAR(36) NOT NULL,
    document_type VARCHAR(32) NOT NULL,
    reference VARCHAR(255) NOT NULL,
    status VARCHAR(16) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_kyc_documents_wallet_id
        FOREIGN KEY (wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE,
    CONSTRAINT chk_kyc_documents_status_known
        CHECK (status = ANY (ARRAY['submitted', 'review', 'approved', 'rejected']))
);

CREATE INDEX IF NOT EXISTS idx_kyc_documents_wallet_created
    ON __PAYMENTS_SCHEMA__.kyc_documents(wallet_id, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.fx_rates (
    id VARCHAR(36) PRIMARY KEY,
    from_currency VARCHAR(3) NOT NULL,
    to_currency VARCHAR(3) NOT NULL,
    rate_bps BIGINT NOT NULL,
    fee_bps BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT chk_fx_rates_rate_positive CHECK (rate_bps > 0),
    CONSTRAINT chk_fx_rates_fee_non_negative CHECK (fee_bps >= 0)
);

CREATE INDEX IF NOT EXISTS idx_fx_rates_pair_created
    ON __PAYMENTS_SCHEMA__.fx_rates(from_currency, to_currency, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.offline_payment_queue (
    id VARCHAR(36) PRIMARY KEY,
    wallet_id VARCHAR(36) NOT NULL,
    operation VARCHAR(32) NOT NULL,
    payload JSONB NOT NULL,
    status VARCHAR(16) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_offline_payment_queue_wallet_id
        FOREIGN KEY (wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE,
    CONSTRAINT chk_offline_payment_queue_status_known
        CHECK (status = ANY (ARRAY['queued', 'submitted', 'failed', 'canceled']))
);

CREATE INDEX IF NOT EXISTS idx_offline_payment_queue_wallet_status_created
    ON __PAYMENTS_SCHEMA__.offline_payment_queue(wallet_id, status, created_at DESC, id DESC);
