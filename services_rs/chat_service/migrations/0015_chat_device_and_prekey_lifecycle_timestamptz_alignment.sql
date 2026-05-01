ALTER TABLE __CHAT_SCHEMA__.devices
    DROP CONSTRAINT IF EXISTS chk_devices_created_at_text_timestamp;

ALTER TABLE __CHAT_SCHEMA__.device_auth
    DROP CONSTRAINT IF EXISTS chk_device_auth_rotated_at_text_timestamp;

ALTER TABLE __CHAT_SCHEMA__.chat_one_time_prekeys
    DROP CONSTRAINT IF EXISTS chk_chat_one_time_prekeys_created_at_text_timestamp;

ALTER TABLE __CHAT_SCHEMA__.chat_one_time_prekeys
    DROP CONSTRAINT IF EXISTS chk_chat_one_time_prekeys_consumed_at_text_timestamp;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'devices'
          AND column_name = 'created_at'
          AND data_type = 'text'
    ) THEN
        UPDATE __CHAT_SCHEMA__.devices
        SET created_at = to_char((NOW() AT TIME ZONE 'UTC'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
        WHERE created_at IS NULL OR BTRIM(created_at) = '';

        ALTER TABLE __CHAT_SCHEMA__.devices
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
          AND table_name = 'device_auth'
          AND column_name = 'rotated_at'
          AND data_type = 'text'
    ) THEN
        UPDATE __CHAT_SCHEMA__.device_auth
        SET rotated_at = to_char((NOW() AT TIME ZONE 'UTC'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
        WHERE rotated_at IS NULL OR BTRIM(rotated_at) = '';

        ALTER TABLE __CHAT_SCHEMA__.device_auth
            ALTER COLUMN rotated_at TYPE TIMESTAMPTZ
            USING NULLIF(BTRIM(rotated_at), '')::timestamptz;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'chat_one_time_prekeys'
          AND column_name = 'created_at'
          AND data_type = 'text'
    ) THEN
        UPDATE __CHAT_SCHEMA__.chat_one_time_prekeys
        SET created_at = to_char((NOW() AT TIME ZONE 'UTC'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
        WHERE created_at IS NULL OR BTRIM(created_at) = '';

        ALTER TABLE __CHAT_SCHEMA__.chat_one_time_prekeys
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
          AND table_name = 'chat_one_time_prekeys'
          AND column_name = 'consumed_at'
          AND data_type = 'text'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_one_time_prekeys
            ALTER COLUMN consumed_at TYPE TIMESTAMPTZ
            USING NULLIF(BTRIM(consumed_at), '')::timestamptz;
    END IF;
END $$;

ALTER TABLE __CHAT_SCHEMA__.devices
    ALTER COLUMN created_at SET DEFAULT NOW();

ALTER TABLE __CHAT_SCHEMA__.devices
    ALTER COLUMN created_at SET NOT NULL;

ALTER TABLE __CHAT_SCHEMA__.device_auth
    ALTER COLUMN rotated_at SET DEFAULT NOW();

ALTER TABLE __CHAT_SCHEMA__.device_auth
    ALTER COLUMN rotated_at SET NOT NULL;

ALTER TABLE __CHAT_SCHEMA__.chat_one_time_prekeys
    ALTER COLUMN created_at SET DEFAULT NOW();

ALTER TABLE __CHAT_SCHEMA__.chat_one_time_prekeys
    ALTER COLUMN created_at SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_chat_one_time_prekeys_consumed_at_after_created_at'
          AND conrelid = '__CHAT_SCHEMA__.chat_one_time_prekeys'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_one_time_prekeys
            ADD CONSTRAINT chk_chat_one_time_prekeys_consumed_at_after_created_at
            CHECK (consumed_at IS NULL OR consumed_at >= created_at) NOT VALID;
    END IF;
END $$;
