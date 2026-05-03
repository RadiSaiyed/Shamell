ALTER TABLE auth_biometric_tokens
    ADD COLUMN IF NOT EXISTS next_token_hash VARCHAR(64);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_bio_tokens_next_hash_distinct'
          AND conrelid = 'auth_biometric_tokens'::regclass
    ) THEN
        ALTER TABLE auth_biometric_tokens
            ADD CONSTRAINT chk_auth_bio_tokens_next_hash_distinct
            CHECK (next_token_hash IS NULL OR next_token_hash <> token_hash) NOT VALID;
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_auth_biometric_tokens_next_token_hash
    ON auth_biometric_tokens(next_token_hash)
    WHERE next_token_hash IS NOT NULL;
