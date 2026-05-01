DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_acct_create_chal_expires_after_created'
          AND conrelid = 'auth_account_create_challenges'::regclass
    ) THEN
        ALTER TABLE auth_account_create_challenges
            ADD CONSTRAINT chk_auth_acct_create_chal_expires_after_created
            CHECK (expires_at > created_at) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_acct_create_chal_consumed_after_created'
          AND conrelid = 'auth_account_create_challenges'::regclass
    ) THEN
        ALTER TABLE auth_account_create_challenges
            ADD CONSTRAINT chk_auth_acct_create_chal_consumed_after_created
            CHECK (consumed_at IS NULL OR consumed_at >= created_at) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_acct_create_chal_consumed_before_expires'
          AND conrelid = 'auth_account_create_challenges'::regclass
    ) THEN
        ALTER TABLE auth_account_create_challenges
            ADD CONSTRAINT chk_auth_acct_create_chal_consumed_before_expires
            CHECK (consumed_at IS NULL OR consumed_at <= expires_at) NOT VALID;
    END IF;
END $$;
