DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_payment_requests_expires_at_not_before_created_at'
          AND conrelid = '__PAYMENTS_SCHEMA__.payment_requests'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.payment_requests
            ADD CONSTRAINT chk_payment_requests_expires_at_not_before_created_at
            CHECK (expires_at IS NULL OR expires_at >= created_at) NOT VALID;
    END IF;
END
$$;
