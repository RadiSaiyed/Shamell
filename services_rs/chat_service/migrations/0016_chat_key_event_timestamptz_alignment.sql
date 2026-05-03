ALTER TABLE __CHAT_SCHEMA__.group_key_events
    DROP CONSTRAINT IF EXISTS chk_group_key_events_created_at_text_timestamp;

ALTER TABLE __CHAT_SCHEMA__.device_key_events
    DROP CONSTRAINT IF EXISTS chk_device_key_events_created_at_text_timestamp;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'group_key_events'
          AND column_name = 'created_at'
          AND data_type = 'text'
    ) THEN
        UPDATE __CHAT_SCHEMA__.group_key_events
        SET created_at = to_char((NOW() AT TIME ZONE 'UTC'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
        WHERE created_at IS NULL OR BTRIM(created_at) = '';

        ALTER TABLE __CHAT_SCHEMA__.group_key_events
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
          AND table_name = 'device_key_events'
          AND column_name = 'created_at'
          AND data_type = 'text'
    ) THEN
        UPDATE __CHAT_SCHEMA__.device_key_events
        SET created_at = to_char((NOW() AT TIME ZONE 'UTC'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
        WHERE created_at IS NULL OR BTRIM(created_at) = '';

        ALTER TABLE __CHAT_SCHEMA__.device_key_events
            ALTER COLUMN created_at TYPE TIMESTAMPTZ
            USING NULLIF(BTRIM(created_at), '')::timestamptz;
    END IF;
END $$;

ALTER TABLE __CHAT_SCHEMA__.group_key_events
    ALTER COLUMN created_at SET DEFAULT NOW();

ALTER TABLE __CHAT_SCHEMA__.group_key_events
    ALTER COLUMN created_at SET NOT NULL;

ALTER TABLE __CHAT_SCHEMA__.device_key_events
    ALTER COLUMN created_at SET DEFAULT NOW();

ALTER TABLE __CHAT_SCHEMA__.device_key_events
    ALTER COLUMN created_at SET NOT NULL;
