ALTER TABLE __CHAT_SCHEMA__.messages
    DROP CONSTRAINT IF EXISTS chk_messages_created_at_text_timestamp;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'messages'
          AND column_name = 'created_at'
          AND data_type = 'text'
    ) THEN
        UPDATE __CHAT_SCHEMA__.messages
        SET created_at = to_char((NOW() AT TIME ZONE 'UTC'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
        WHERE created_at IS NULL OR BTRIM(created_at) = '';

        ALTER TABLE __CHAT_SCHEMA__.messages
            ALTER COLUMN created_at TYPE TIMESTAMPTZ
            USING NULLIF(BTRIM(created_at), '')::timestamptz;
    END IF;
END $$;

ALTER TABLE __CHAT_SCHEMA__.messages
    ALTER COLUMN created_at SET DEFAULT NOW();

ALTER TABLE __CHAT_SCHEMA__.messages
    ALTER COLUMN created_at SET NOT NULL;

ALTER TABLE __CHAT_SCHEMA__.messages
    DROP CONSTRAINT IF EXISTS chk_messages_delivered_at_after_created_at;

ALTER TABLE __CHAT_SCHEMA__.messages
    ADD CONSTRAINT chk_messages_delivered_at_after_created_at
    CHECK (delivered_at IS NULL OR delivered_at >= created_at) NOT VALID;

ALTER TABLE __CHAT_SCHEMA__.messages
    DROP CONSTRAINT IF EXISTS chk_messages_read_at_after_created_at;

ALTER TABLE __CHAT_SCHEMA__.messages
    ADD CONSTRAINT chk_messages_read_at_after_created_at
    CHECK (read_at IS NULL OR read_at >= created_at) NOT VALID;

ALTER TABLE __CHAT_SCHEMA__.messages
    DROP CONSTRAINT IF EXISTS chk_messages_expire_at_after_created_at;

ALTER TABLE __CHAT_SCHEMA__.messages
    ADD CONSTRAINT chk_messages_expire_at_after_created_at
    CHECK (expire_at IS NULL OR expire_at >= created_at) NOT VALID;
