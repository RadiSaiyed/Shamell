CREATE TABLE IF NOT EXISTS auth_payment_attestation_challenges (
    id BIGSERIAL PRIMARY KEY,
    token_hash VARCHAR(64) NOT NULL UNIQUE,
    account_id VARCHAR(64) NOT NULL,
    device_id VARCHAR(128) NOT NULL,
    operation VARCHAR(64) NOT NULL,
    resource_id VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_auth_payment_attestation_challenges_gc_at
    ON auth_payment_attestation_challenges(COALESCE(consumed_at, expires_at));

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_auth_payment_attestation_challenges_account_id'
          AND conrelid = 'auth_payment_attestation_challenges'::regclass
    ) THEN
        ALTER TABLE auth_payment_attestation_challenges
            ADD CONSTRAINT fk_auth_payment_attestation_challenges_account_id
            FOREIGN KEY (account_id) REFERENCES auth_accounts(account_id) ON DELETE CASCADE NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_payment_attestation_challenges_operation_known'
          AND conrelid = 'auth_payment_attestation_challenges'::regclass
    ) THEN
        ALTER TABLE auth_payment_attestation_challenges
            ADD CONSTRAINT chk_auth_payment_attestation_challenges_operation_known
            CHECK (
                operation IN (
                    'payments_transfer',
                    'payments_topup',
                    'payments_requests_accept'
                )
            ) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_payment_attestation_challenges_expires_after_created'
          AND conrelid = 'auth_payment_attestation_challenges'::regclass
    ) THEN
        ALTER TABLE auth_payment_attestation_challenges
            ADD CONSTRAINT chk_auth_payment_attestation_challenges_expires_after_created
            CHECK (expires_at > created_at) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_payment_attestation_challenges_consumed_after_created'
          AND conrelid = 'auth_payment_attestation_challenges'::regclass
    ) THEN
        ALTER TABLE auth_payment_attestation_challenges
            ADD CONSTRAINT chk_auth_payment_attestation_challenges_consumed_after_created
            CHECK ((consumed_at IS NULL) OR (consumed_at >= created_at)) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_payment_attestation_challenges_consumed_before_expires'
          AND conrelid = 'auth_payment_attestation_challenges'::regclass
    ) THEN
        ALTER TABLE auth_payment_attestation_challenges
            ADD CONSTRAINT chk_auth_payment_attestation_challenges_consumed_before_expires
            CHECK ((consumed_at IS NULL) OR (consumed_at <= expires_at)) NOT VALID;
    END IF;
END $$;
