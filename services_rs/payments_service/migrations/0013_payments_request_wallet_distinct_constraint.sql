DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_payment_requests_distinct_wallets'
          AND conrelid = '__PAYMENTS_SCHEMA__.payment_requests'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.payment_requests
            ADD CONSTRAINT chk_payment_requests_distinct_wallets
            CHECK (from_wallet_id <> to_wallet_id) NOT VALID;
    END IF;
END $$;
