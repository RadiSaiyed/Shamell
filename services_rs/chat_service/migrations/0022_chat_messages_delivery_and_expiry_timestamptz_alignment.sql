ALTER TABLE __CHAT_SCHEMA__.messages
    DROP CONSTRAINT IF EXISTS chk_messages_delivered_at_text_timestamp;

ALTER TABLE __CHAT_SCHEMA__.messages
    DROP CONSTRAINT IF EXISTS chk_messages_read_at_text_timestamp;

ALTER TABLE __CHAT_SCHEMA__.messages
    DROP CONSTRAINT IF EXISTS chk_messages_expire_at_text_timestamp;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'messages'
          AND column_name = 'delivered_at'
          AND data_type = 'text'
    ) THEN
        UPDATE __CHAT_SCHEMA__.messages
        SET delivered_at = NULL
        WHERE delivered_at IS NOT NULL AND BTRIM(delivered_at) = '';

        ALTER TABLE __CHAT_SCHEMA__.messages
            ALTER COLUMN delivered_at TYPE TIMESTAMPTZ
            USING NULLIF(BTRIM(delivered_at), '')::timestamptz;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'messages'
          AND column_name = 'read_at'
          AND data_type = 'text'
    ) THEN
        UPDATE __CHAT_SCHEMA__.messages
        SET read_at = NULL
        WHERE read_at IS NOT NULL AND BTRIM(read_at) = '';

        ALTER TABLE __CHAT_SCHEMA__.messages
            ALTER COLUMN read_at TYPE TIMESTAMPTZ
            USING NULLIF(BTRIM(read_at), '')::timestamptz;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'messages'
          AND column_name = 'expire_at'
          AND data_type = 'text'
    ) THEN
        UPDATE __CHAT_SCHEMA__.messages
        SET expire_at = NULL
        WHERE expire_at IS NOT NULL AND BTRIM(expire_at) = '';

        ALTER TABLE __CHAT_SCHEMA__.messages
            ALTER COLUMN expire_at TYPE TIMESTAMPTZ
            USING NULLIF(BTRIM(expire_at), '')::timestamptz;
    END IF;
END $$;

ALTER TABLE __CHAT_SCHEMA__.messages
    DROP CONSTRAINT IF EXISTS chk_messages_delivered_at_after_created_at;

ALTER TABLE __CHAT_SCHEMA__.messages
    ADD CONSTRAINT chk_messages_delivered_at_after_created_at
    CHECK (delivered_at IS NULL OR delivered_at >= created_at::timestamptz) NOT VALID;

ALTER TABLE __CHAT_SCHEMA__.messages
    DROP CONSTRAINT IF EXISTS chk_messages_read_at_after_created_at;

ALTER TABLE __CHAT_SCHEMA__.messages
    ADD CONSTRAINT chk_messages_read_at_after_created_at
    CHECK (read_at IS NULL OR read_at >= created_at::timestamptz) NOT VALID;

ALTER TABLE __CHAT_SCHEMA__.messages
    DROP CONSTRAINT IF EXISTS chk_messages_expire_at_after_created_at;

ALTER TABLE __CHAT_SCHEMA__.messages
    ADD CONSTRAINT chk_messages_expire_at_after_created_at
    CHECK (expire_at IS NULL OR expire_at >= created_at::timestamptz) NOT VALID;
