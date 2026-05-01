ALTER TABLE auth_accounts
    ADD COLUMN IF NOT EXISTS username VARCHAR(32);

ALTER TABLE auth_accounts
    ADD COLUMN IF NOT EXISTS password_hash TEXT;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'auth_accounts'::regclass
          AND conname = 'auth_accounts_username_key'
    ) THEN
        ALTER TABLE auth_accounts
            ADD CONSTRAINT auth_accounts_username_key UNIQUE (username);
    END IF;
END $$;
