DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_sessions_expires_after_created'
          AND conrelid = 'auth_sessions'::regclass
    ) THEN
        ALTER TABLE auth_sessions
            ADD CONSTRAINT chk_auth_sessions_expires_after_created
            CHECK (expires_at > created_at) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_sessions_last_seen_after_created'
          AND conrelid = 'auth_sessions'::regclass
    ) THEN
        ALTER TABLE auth_sessions
            ADD CONSTRAINT chk_auth_sessions_last_seen_after_created
            CHECK (last_seen_at >= created_at) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_sessions_revoked_after_created'
          AND conrelid = 'auth_sessions'::regclass
    ) THEN
        ALTER TABLE auth_sessions
            ADD CONSTRAINT chk_auth_sessions_revoked_after_created
            CHECK (revoked_at IS NULL OR revoked_at >= created_at) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_bio_tokens_expires_after_created'
          AND conrelid = 'auth_biometric_tokens'::regclass
    ) THEN
        ALTER TABLE auth_biometric_tokens
            ADD CONSTRAINT chk_auth_bio_tokens_expires_after_created
            CHECK (expires_at > created_at) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_bio_tokens_last_used_after_created'
          AND conrelid = 'auth_biometric_tokens'::regclass
    ) THEN
        ALTER TABLE auth_biometric_tokens
            ADD CONSTRAINT chk_auth_bio_tokens_last_used_after_created
            CHECK (last_used_at IS NULL OR last_used_at >= created_at) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_bio_tokens_revoked_after_created'
          AND conrelid = 'auth_biometric_tokens'::regclass
    ) THEN
        ALTER TABLE auth_biometric_tokens
            ADD CONSTRAINT chk_auth_bio_tokens_revoked_after_created
            CHECK (revoked_at IS NULL OR revoked_at >= created_at) NOT VALID;
    END IF;
END $$;
