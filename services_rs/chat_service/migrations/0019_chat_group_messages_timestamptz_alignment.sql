ALTER TABLE __CHAT_SCHEMA__.group_messages
    DROP CONSTRAINT IF EXISTS chk_group_messages_created_at_text_timestamp;

ALTER TABLE __CHAT_SCHEMA__.group_messages
    DROP CONSTRAINT IF EXISTS chk_group_messages_expire_at_text_timestamp;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'group_messages'
          AND column_name = 'created_at'
          AND data_type = 'text'
    ) THEN
        UPDATE __CHAT_SCHEMA__.group_messages
        SET created_at = to_char((NOW() AT TIME ZONE 'UTC'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
        WHERE created_at IS NULL OR BTRIM(created_at) = '';

        ALTER TABLE __CHAT_SCHEMA__.group_messages
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
          AND table_name = 'group_messages'
          AND column_name = 'expire_at'
          AND data_type = 'text'
    ) THEN
        UPDATE __CHAT_SCHEMA__.group_messages
        SET expire_at = NULL
        WHERE expire_at IS NOT NULL AND BTRIM(expire_at) = '';

        ALTER TABLE __CHAT_SCHEMA__.group_messages
            ALTER COLUMN expire_at TYPE TIMESTAMPTZ
            USING NULLIF(BTRIM(expire_at), '')::timestamptz;
    END IF;
END $$;

ALTER TABLE __CHAT_SCHEMA__.group_messages
    ALTER COLUMN created_at SET DEFAULT NOW();

ALTER TABLE __CHAT_SCHEMA__.group_messages
    ALTER COLUMN created_at SET NOT NULL;

ALTER TABLE __CHAT_SCHEMA__.group_messages
    DROP CONSTRAINT IF EXISTS chk_group_messages_expire_at_after_created_at;

ALTER TABLE __CHAT_SCHEMA__.group_messages
    ADD CONSTRAINT chk_group_messages_expire_at_after_created_at
    CHECK (expire_at IS NULL OR expire_at >= created_at) NOT VALID;
