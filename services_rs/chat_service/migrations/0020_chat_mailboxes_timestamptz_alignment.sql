ALTER TABLE __CHAT_SCHEMA__.chat_mailboxes
    DROP CONSTRAINT IF EXISTS chk_chat_mailboxes_created_at_text_timestamp;

ALTER TABLE __CHAT_SCHEMA__.chat_mailboxes
    DROP CONSTRAINT IF EXISTS chk_chat_mailboxes_rotated_at_text_timestamp;

DROP INDEX IF EXISTS __CHAT_SCHEMA__.idx_chat_mailboxes_inactive_gc;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'chat_mailboxes'
          AND column_name = 'created_at'
          AND data_type = 'text'
    ) THEN
        UPDATE __CHAT_SCHEMA__.chat_mailboxes
        SET created_at = to_char((NOW() AT TIME ZONE 'UTC'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
        WHERE created_at IS NULL OR BTRIM(created_at) = '';

        ALTER TABLE __CHAT_SCHEMA__.chat_mailboxes
            ALTER COLUMN created_at TYPE TIMESTAMPTZ
            USING NULLIF(BTRIM(created_at), '')::timestamptz;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'chat_mailboxes'
          AND column_name = 'rotated_at'
          AND data_type = 'text'
    ) THEN
        UPDATE __CHAT_SCHEMA__.chat_mailboxes
        SET rotated_at = NULL
        WHERE rotated_at IS NOT NULL AND BTRIM(rotated_at) = '';

        ALTER TABLE __CHAT_SCHEMA__.chat_mailboxes
            ALTER COLUMN rotated_at TYPE TIMESTAMPTZ
            USING NULLIF(BTRIM(rotated_at), '')::timestamptz;
    END IF;
END $$;

ALTER TABLE __CHAT_SCHEMA__.chat_mailboxes
    ALTER COLUMN created_at SET DEFAULT NOW();

ALTER TABLE __CHAT_SCHEMA__.chat_mailboxes
    ALTER COLUMN created_at SET NOT NULL;

ALTER TABLE __CHAT_SCHEMA__.chat_mailboxes
    DROP CONSTRAINT IF EXISTS chk_chat_mailboxes_rotated_at_after_created_at;

ALTER TABLE __CHAT_SCHEMA__.chat_mailboxes
    ADD CONSTRAINT chk_chat_mailboxes_rotated_at_after_created_at
    CHECK (rotated_at IS NULL OR rotated_at >= created_at) NOT VALID;

CREATE INDEX IF NOT EXISTS idx_chat_mailboxes_inactive_gc
    ON __CHAT_SCHEMA__.chat_mailboxes((COALESCE(rotated_at, created_at)))
    WHERE active = 0;
