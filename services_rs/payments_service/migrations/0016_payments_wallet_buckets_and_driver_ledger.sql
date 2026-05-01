ALTER TABLE __PAYMENTS_SCHEMA__.wallets
    ADD COLUMN IF NOT EXISTS cash_balance_cents BIGINT NOT NULL DEFAULT 0;

ALTER TABLE __PAYMENTS_SCHEMA__.wallets
    ADD COLUMN IF NOT EXISTS promo_credit_cents BIGINT NOT NULL DEFAULT 0;

ALTER TABLE __PAYMENTS_SCHEMA__.wallets
    ADD COLUMN IF NOT EXISTS refund_credit_cents BIGINT NOT NULL DEFAULT 0;

ALTER TABLE __PAYMENTS_SCHEMA__.wallets
    ADD COLUMN IF NOT EXISTS corporate_credit_cents BIGINT NOT NULL DEFAULT 0;

UPDATE __PAYMENTS_SCHEMA__.wallets
SET cash_balance_cents = balance_cents
WHERE cash_balance_cents <> balance_cents;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_wallets_cash_balance_cents_non_negative'
          AND conrelid = '__PAYMENTS_SCHEMA__.wallets'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.wallets
            ADD CONSTRAINT chk_wallets_cash_balance_cents_non_negative
            CHECK (cash_balance_cents >= 0) NOT VALID;
    END IF;
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_wallets_promo_credit_cents_non_negative'
          AND conrelid = '__PAYMENTS_SCHEMA__.wallets'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.wallets
            ADD CONSTRAINT chk_wallets_promo_credit_cents_non_negative
            CHECK (promo_credit_cents >= 0) NOT VALID;
    END IF;
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_wallets_refund_credit_cents_non_negative'
          AND conrelid = '__PAYMENTS_SCHEMA__.wallets'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.wallets
            ADD CONSTRAINT chk_wallets_refund_credit_cents_non_negative
            CHECK (refund_credit_cents >= 0) NOT VALID;
    END IF;
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_wallets_corporate_credit_cents_non_negative'
          AND conrelid = '__PAYMENTS_SCHEMA__.wallets'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.wallets
            ADD CONSTRAINT chk_wallets_corporate_credit_cents_non_negative
            CHECK (corporate_credit_cents >= 0) NOT VALID;
    END IF;
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_wallets_balance_matches_cash_bucket'
          AND conrelid = '__PAYMENTS_SCHEMA__.wallets'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.wallets
            ADD CONSTRAINT chk_wallets_balance_matches_cash_bucket
            CHECK (balance_cents = cash_balance_cents) NOT VALID;
    END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.driver_wallet_ledgers (
    wallet_id VARCHAR(36) PRIMARY KEY,
    earnings_available_cents BIGINT NOT NULL DEFAULT 0,
    held_reserve_cents BIGINT NOT NULL DEFAULT 0,
    debt_cents BIGINT NOT NULL DEFAULT 0,
    payout_pending_cents BIGINT NOT NULL DEFAULT 0,
    bonuses_cents BIGINT NOT NULL DEFAULT 0,
    cash_collected_cents BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_driver_wallet_ledgers_wallet_id
        FOREIGN KEY (wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE,
    CONSTRAINT chk_driver_wallet_ledgers_earnings_available_non_negative
        CHECK (earnings_available_cents >= 0),
    CONSTRAINT chk_driver_wallet_ledgers_held_reserve_non_negative
        CHECK (held_reserve_cents >= 0),
    CONSTRAINT chk_driver_wallet_ledgers_debt_non_negative
        CHECK (debt_cents >= 0),
    CONSTRAINT chk_driver_wallet_ledgers_payout_pending_non_negative
        CHECK (payout_pending_cents >= 0),
    CONSTRAINT chk_driver_wallet_ledgers_bonuses_non_negative
        CHECK (bonuses_cents >= 0),
    CONSTRAINT chk_driver_wallet_ledgers_cash_collected_non_negative
        CHECK (cash_collected_cents >= 0),
    CONSTRAINT chk_driver_wallet_ledgers_updated_at_after_created_at
        CHECK (updated_at >= created_at)
);

CREATE INDEX IF NOT EXISTS idx_driver_wallet_ledgers_updated_at
    ON __PAYMENTS_SCHEMA__.driver_wallet_ledgers(updated_at);
