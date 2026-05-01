CREATE SCHEMA IF NOT EXISTS __PAYMENTS_SCHEMA__;

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.users (
    id VARCHAR(36) PRIMARY KEY,
    account_id VARCHAR(64),
    phone VARCHAR(32),
    kyc_level INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT chk_users_kyc_level_non_negative CHECK (kyc_level >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone
    ON __PAYMENTS_SCHEMA__.users(phone);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_account_id
    ON __PAYMENTS_SCHEMA__.users(account_id);

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.wallets (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    balance_cents BIGINT NOT NULL DEFAULT 0,
    currency VARCHAR(3) NOT NULL,
    CONSTRAINT fk_wallets_user_id
        FOREIGN KEY (user_id) REFERENCES __PAYMENTS_SCHEMA__.users(id) ON DELETE RESTRICT,
    CONSTRAINT chk_wallets_balance_cents_non_negative CHECK (balance_cents >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_wallets_user_id
    ON __PAYMENTS_SCHEMA__.wallets(user_id);

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.txns (
    id VARCHAR(36) PRIMARY KEY,
    from_wallet_id VARCHAR(36),
    to_wallet_id VARCHAR(36) NOT NULL,
    amount_cents BIGINT NOT NULL,
    kind VARCHAR(32) NOT NULL,
    fee_cents BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_txns_from_wallet_id
        FOREIGN KEY (from_wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE RESTRICT,
    CONSTRAINT fk_txns_to_wallet_id
        FOREIGN KEY (to_wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE RESTRICT,
    CONSTRAINT chk_txns_amount_cents_positive CHECK (amount_cents > 0),
    CONSTRAINT chk_txns_fee_cents_non_negative CHECK (fee_cents >= 0),
    CONSTRAINT chk_txns_kind_known CHECK (kind = ANY (ARRAY['topup', 'transfer']))
);

CREATE INDEX IF NOT EXISTS idx_txns_from_wallet_created_id
    ON __PAYMENTS_SCHEMA__.txns(from_wallet_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_txns_to_wallet_created_id
    ON __PAYMENTS_SCHEMA__.txns(to_wallet_id, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.ledger_entries (
    id VARCHAR(36) PRIMARY KEY,
    wallet_id VARCHAR(36),
    amount_cents BIGINT NOT NULL,
    txn_id VARCHAR(36),
    description VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_ledger_entries_wallet_id
        FOREIGN KEY (wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE RESTRICT,
    CONSTRAINT fk_ledger_entries_txn_id
        FOREIGN KEY (txn_id) REFERENCES __PAYMENTS_SCHEMA__.txns(id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_ledger_txn_id
    ON __PAYMENTS_SCHEMA__.ledger_entries(txn_id);

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.idempotency (
    id VARCHAR(36) PRIMARY KEY,
    ikey VARCHAR(128) NOT NULL,
    endpoint TEXT NOT NULL,
    txn_id VARCHAR(36),
    amount_cents BIGINT,
    currency VARCHAR(3),
    wallet_id VARCHAR(36),
    balance_cents BIGINT,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_idempotency_txn_id
        FOREIGN KEY (txn_id) REFERENCES __PAYMENTS_SCHEMA__.txns(id) ON DELETE RESTRICT,
    CONSTRAINT fk_idempotency_wallet_id
        FOREIGN KEY (wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE RESTRICT,
    CONSTRAINT chk_idempotency_amount_cents_positive
        CHECK (amount_cents IS NULL OR amount_cents > 0),
    CONSTRAINT chk_idempotency_balance_cents_non_negative
        CHECK (balance_cents IS NULL OR balance_cents >= 0)
);

CREATE INDEX IF NOT EXISTS idx_idempotency_ikey_created
    ON __PAYMENTS_SCHEMA__.idempotency(ikey, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_idempotency_ikey_endpoint
    ON __PAYMENTS_SCHEMA__.idempotency(ikey, endpoint);

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.favorites (
    id VARCHAR(36) PRIMARY KEY,
    owner_wallet_id VARCHAR(36) NOT NULL,
    favorite_wallet_id VARCHAR(36) NOT NULL,
    alias VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_favorites_owner_wallet_id
        FOREIGN KEY (owner_wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE,
    CONSTRAINT fk_favorites_favorite_wallet_id
        FOREIGN KEY (favorite_wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE,
    CONSTRAINT chk_favorites_owner_not_self CHECK (owner_wallet_id <> favorite_wallet_id)
);

CREATE INDEX IF NOT EXISTS idx_favorites_owner_created_id
    ON __PAYMENTS_SCHEMA__.favorites(owner_wallet_id, created_at DESC, id DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_favorites_owner_favorite
    ON __PAYMENTS_SCHEMA__.favorites(owner_wallet_id, favorite_wallet_id);

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.payment_requests (
    id VARCHAR(36) PRIMARY KEY,
    from_wallet_id VARCHAR(36) NOT NULL,
    to_wallet_id VARCHAR(36) NOT NULL,
    amount_cents BIGINT NOT NULL,
    currency VARCHAR(3) NOT NULL,
    message VARCHAR(255),
    status VARCHAR(16) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ,
    CONSTRAINT fk_payment_requests_from_wallet_id
        FOREIGN KEY (from_wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE,
    CONSTRAINT fk_payment_requests_to_wallet_id
        FOREIGN KEY (to_wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE,
    CONSTRAINT chk_payment_requests_amount_cents_positive CHECK (amount_cents > 0),
    CONSTRAINT chk_payment_requests_status_known
        CHECK (status = ANY (ARRAY['pending', 'accepted', 'canceled', 'expired']))
);

CREATE INDEX IF NOT EXISTS idx_requests_from_wallet_created_id
    ON __PAYMENTS_SCHEMA__.payment_requests(from_wallet_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_requests_to_wallet_created_id
    ON __PAYMENTS_SCHEMA__.payment_requests(to_wallet_id, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.aliases (
    id VARCHAR(36) PRIMARY KEY,
    handle VARCHAR(32) NOT NULL,
    display VARCHAR(32) NOT NULL,
    user_id VARCHAR(36) NOT NULL,
    wallet_id VARCHAR(36) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'pending',
    code_hash VARCHAR(64),
    code_expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_aliases_user_id
        FOREIGN KEY (user_id) REFERENCES __PAYMENTS_SCHEMA__.users(id) ON DELETE CASCADE,
    CONSTRAINT fk_aliases_wallet_id
        FOREIGN KEY (wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_aliases_handle
    ON __PAYMENTS_SCHEMA__.aliases(handle);

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.roles (
    id VARCHAR(36) PRIMARY KEY,
    account_id VARCHAR(64),
    phone VARCHAR(32),
    role VARCHAR(32) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_roles_account_id
        FOREIGN KEY (account_id) REFERENCES __PAYMENTS_SCHEMA__.users(account_id) ON DELETE CASCADE,
    CONSTRAINT chk_roles_role_known
        CHECK (
            role = ANY (
                ARRAY['merchant', 'qr_seller', 'cashout_operator', 'admin', 'superadmin', 'seller', 'ops']
            )
            OR role ~ '^official_owner:([*]|[a-z0-9_.-]{1,64})$'
        )
);

CREATE INDEX IF NOT EXISTS idx_roles_account_created_id
    ON __PAYMENTS_SCHEMA__.roles(account_id, created_at DESC, id DESC)
    WHERE account_id IS NOT NULL AND account_id <> '';
CREATE INDEX IF NOT EXISTS idx_roles_phone_created_id
    ON __PAYMENTS_SCHEMA__.roles(phone, created_at DESC, id DESC)
    WHERE phone IS NOT NULL AND phone <> '';
CREATE INDEX IF NOT EXISTS idx_roles_role_created_id
    ON __PAYMENTS_SCHEMA__.roles(role, created_at DESC, id DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_roles_account_role
    ON __PAYMENTS_SCHEMA__.roles(account_id, role)
    WHERE account_id IS NOT NULL AND account_id <> '';
CREATE UNIQUE INDEX IF NOT EXISTS idx_roles_phone_role
    ON __PAYMENTS_SCHEMA__.roles(phone, role)
    WHERE phone IS NOT NULL AND phone <> '';

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.admin_rate_limits (
    limit_key TEXT PRIMARY KEY,
    window_start_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    request_count BIGINT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT chk_admin_rate_limits_request_count_non_negative
        CHECK (request_count >= 0),
    CONSTRAINT chk_admin_rate_limits_updated_at_after_window_start_at
        CHECK (updated_at >= window_start_at)
);

CREATE INDEX IF NOT EXISTS idx_admin_rate_limits_updated_at
    ON __PAYMENTS_SCHEMA__.admin_rate_limits(updated_at);
