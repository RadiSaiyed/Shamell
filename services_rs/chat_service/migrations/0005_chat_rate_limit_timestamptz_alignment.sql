ALTER TABLE __CHAT_SCHEMA__.chat_rate_limits
    ADD COLUMN IF NOT EXISTS window_start_at TIMESTAMPTZ;

ALTER TABLE __CHAT_SCHEMA__.chat_rate_limits
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'chat_rate_limits'
          AND column_name = 'window_start_epoch'
    ) THEN
        EXECUTE $sql$
            UPDATE __CHAT_SCHEMA__.chat_rate_limits
            SET window_start_at = TO_TIMESTAMP(window_start_epoch::double precision)
            WHERE window_start_at IS NULL
        $sql$;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'chat_rate_limits'
          AND column_name = 'updated_at_epoch'
    ) THEN
        EXECUTE $sql$
            UPDATE __CHAT_SCHEMA__.chat_rate_limits
            SET updated_at = TO_TIMESTAMP(updated_at_epoch::double precision)
            WHERE updated_at IS NULL
        $sql$;
    END IF;
END $$;

ALTER TABLE __CHAT_SCHEMA__.chat_rate_limits
    ALTER COLUMN window_start_at SET DEFAULT NOW();

ALTER TABLE __CHAT_SCHEMA__.chat_rate_limits
    ALTER COLUMN updated_at SET DEFAULT NOW();

ALTER TABLE __CHAT_SCHEMA__.chat_rate_limits
    ALTER COLUMN window_start_at SET NOT NULL;

ALTER TABLE __CHAT_SCHEMA__.chat_rate_limits
    ALTER COLUMN updated_at SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_chat_rate_limits_updated_at
    ON __CHAT_SCHEMA__.chat_rate_limits(updated_at);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_chat_rate_limits_updated_at_after_window_start_at'
          AND conrelid = '__CHAT_SCHEMA__.chat_rate_limits'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_rate_limits
            ADD CONSTRAINT chk_chat_rate_limits_updated_at_after_window_start_at
            CHECK (updated_at >= window_start_at) NOT VALID;
    END IF;
END $$;
