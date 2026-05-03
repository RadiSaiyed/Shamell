ALTER TABLE __CHAT_SCHEMA__.push_tokens
    DROP CONSTRAINT IF EXISTS chk_push_tokens_created_at_text_timestamp;

ALTER TABLE __CHAT_SCHEMA__.push_tokens
    DROP CONSTRAINT IF EXISTS chk_push_tokens_last_seen_at_text_timestamp;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'push_tokens'
          AND column_name = 'created_at'
          AND data_type = 'text'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.push_tokens
            ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at::timestamptz;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'push_tokens'
          AND column_name = 'last_seen_at'
          AND data_type = 'text'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.push_tokens
            ALTER COLUMN last_seen_at TYPE TIMESTAMPTZ USING last_seen_at::timestamptz;
    END IF;
END $$;

ALTER TABLE __CHAT_SCHEMA__.push_tokens
    ALTER COLUMN created_at SET DEFAULT NOW();

ALTER TABLE __CHAT_SCHEMA__.push_tokens
    ALTER COLUMN last_seen_at SET DEFAULT NOW();

ALTER TABLE __CHAT_SCHEMA__.push_tokens
    ALTER COLUMN created_at SET NOT NULL;

ALTER TABLE __CHAT_SCHEMA__.push_tokens
    ALTER COLUMN last_seen_at SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_push_tokens_last_seen_at_after_created_at'
          AND conrelid = '__CHAT_SCHEMA__.push_tokens'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.push_tokens
            ADD CONSTRAINT chk_push_tokens_last_seen_at_after_created_at
            CHECK (last_seen_at >= created_at) NOT VALID;
    END IF;
END $$;
