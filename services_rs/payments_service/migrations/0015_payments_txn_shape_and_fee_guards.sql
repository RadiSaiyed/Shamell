DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_txns_kind_wallet_shape'
          AND conrelid = '__PAYMENTS_SCHEMA__.txns'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.txns
            ADD CONSTRAINT chk_txns_kind_wallet_shape
            CHECK (
                (kind = 'topup' AND from_wallet_id IS NULL)
                OR
                (kind = 'transfer' AND from_wallet_id IS NOT NULL AND from_wallet_id <> to_wallet_id)
            ) NOT VALID;
    END IF;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_txns_fee_not_exceed_amount'
          AND conrelid = '__PAYMENTS_SCHEMA__.txns'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.txns
            ADD CONSTRAINT chk_txns_fee_not_exceed_amount
            CHECK (fee_cents <= amount_cents) NOT VALID;
    END IF;
END
$$;
