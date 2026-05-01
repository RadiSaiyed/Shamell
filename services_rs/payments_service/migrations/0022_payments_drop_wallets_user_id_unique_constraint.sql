ALTER TABLE __PAYMENTS_SCHEMA__.wallets
    DROP CONSTRAINT IF EXISTS wallets_user_id_key;

DROP INDEX IF EXISTS __PAYMENTS_SCHEMA__.idx_wallets_user_id;

CREATE UNIQUE INDEX IF NOT EXISTS idx_wallets_user_currency
    ON __PAYMENTS_SCHEMA__.wallets(user_id, currency);
