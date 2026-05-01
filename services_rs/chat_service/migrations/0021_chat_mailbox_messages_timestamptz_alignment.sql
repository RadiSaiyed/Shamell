ALTER TABLE __CHAT_SCHEMA__.chat_mailbox_messages
    DROP CONSTRAINT IF EXISTS chk_chat_mailbox_messages_created_at_text_timestamp;

ALTER TABLE __CHAT_SCHEMA__.chat_mailbox_messages
    DROP CONSTRAINT IF EXISTS chk_chat_mailbox_messages_expire_at_text_timestamp;

ALTER TABLE __CHAT_SCHEMA__.chat_mailbox_messages
    DROP CONSTRAINT IF EXISTS chk_chat_mailbox_messages_consumed_at_text_timestamp;

DROP INDEX IF EXISTS __CHAT_SCHEMA__.idx_chat_mailbox_messages_consumed_at_gc;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'chat_mailbox_messages'
          AND column_name = 'created_at'
          AND data_type = 'text'
    ) THEN
        UPDATE __CHAT_SCHEMA__.chat_mailbox_messages
        SET created_at = to_char((NOW() AT TIME ZONE 'UTC'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
        WHERE created_at IS NULL OR BTRIM(created_at) = '';

        ALTER TABLE __CHAT_SCHEMA__.chat_mailbox_messages
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
          AND table_name = 'chat_mailbox_messages'
          AND column_name = 'expire_at'
          AND data_type = 'text'
    ) THEN
        UPDATE __CHAT_SCHEMA__.chat_mailbox_messages
        SET expire_at = NULL
        WHERE expire_at IS NOT NULL AND BTRIM(expire_at) = '';

        ALTER TABLE __CHAT_SCHEMA__.chat_mailbox_messages
            ALTER COLUMN expire_at TYPE TIMESTAMPTZ
            USING NULLIF(BTRIM(expire_at), '')::timestamptz;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'chat_mailbox_messages'
          AND column_name = 'consumed_at'
          AND data_type = 'text'
    ) THEN
        UPDATE __CHAT_SCHEMA__.chat_mailbox_messages
        SET consumed_at = NULL
        WHERE consumed_at IS NOT NULL AND BTRIM(consumed_at) = '';

        ALTER TABLE __CHAT_SCHEMA__.chat_mailbox_messages
            ALTER COLUMN consumed_at TYPE TIMESTAMPTZ
            USING NULLIF(BTRIM(consumed_at), '')::timestamptz;
    END IF;
END $$;

ALTER TABLE __CHAT_SCHEMA__.chat_mailbox_messages
    ALTER COLUMN created_at SET DEFAULT NOW();

ALTER TABLE __CHAT_SCHEMA__.chat_mailbox_messages
    ALTER COLUMN created_at SET NOT NULL;

ALTER TABLE __CHAT_SCHEMA__.chat_mailbox_messages
    DROP CONSTRAINT IF EXISTS chk_chat_mailbox_messages_expire_at_after_created_at;

ALTER TABLE __CHAT_SCHEMA__.chat_mailbox_messages
    ADD CONSTRAINT chk_chat_mailbox_messages_expire_at_after_created_at
    CHECK (expire_at IS NULL OR expire_at >= created_at) NOT VALID;

ALTER TABLE __CHAT_SCHEMA__.chat_mailbox_messages
    DROP CONSTRAINT IF EXISTS chk_chat_mailbox_messages_consumed_at_after_created_at;

ALTER TABLE __CHAT_SCHEMA__.chat_mailbox_messages
    ADD CONSTRAINT chk_chat_mailbox_messages_consumed_at_after_created_at
    CHECK (consumed_at IS NULL OR consumed_at >= created_at) NOT VALID;

CREATE INDEX IF NOT EXISTS idx_chat_mailbox_messages_consumed_at_gc
    ON __CHAT_SCHEMA__.chat_mailbox_messages(consumed_at)
    WHERE consumed_at IS NOT NULL;
