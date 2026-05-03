ALTER TABLE __CHAT_SCHEMA__.chat_identity_keys
    DROP CONSTRAINT IF EXISTS chk_chat_identity_keys_updated_at_text_timestamp;

ALTER TABLE __CHAT_SCHEMA__.chat_signed_prekeys
    DROP CONSTRAINT IF EXISTS chk_chat_signed_prekeys_updated_at_text_timestamp;

ALTER TABLE __CHAT_SCHEMA__.chat_device_protocol_state
    DROP CONSTRAINT IF EXISTS chk_chat_device_protocol_state_updated_at_text_timestamp;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'chat_identity_keys'
          AND column_name = 'updated_at'
          AND data_type = 'text'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_identity_keys
            ALTER COLUMN updated_at TYPE TIMESTAMPTZ USING updated_at::timestamptz;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'chat_signed_prekeys'
          AND column_name = 'updated_at'
          AND data_type = 'text'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_signed_prekeys
            ALTER COLUMN updated_at TYPE TIMESTAMPTZ USING updated_at::timestamptz;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'chat_device_protocol_state'
          AND column_name = 'updated_at'
          AND data_type = 'text'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_device_protocol_state
            ALTER COLUMN updated_at TYPE TIMESTAMPTZ USING updated_at::timestamptz;
    END IF;
END $$;

ALTER TABLE __CHAT_SCHEMA__.chat_identity_keys
    ALTER COLUMN updated_at SET DEFAULT NOW();

ALTER TABLE __CHAT_SCHEMA__.chat_signed_prekeys
    ALTER COLUMN updated_at SET DEFAULT NOW();

ALTER TABLE __CHAT_SCHEMA__.chat_device_protocol_state
    ALTER COLUMN updated_at SET DEFAULT NOW();

ALTER TABLE __CHAT_SCHEMA__.chat_identity_keys
    ALTER COLUMN updated_at SET NOT NULL;

ALTER TABLE __CHAT_SCHEMA__.chat_signed_prekeys
    ALTER COLUMN updated_at SET NOT NULL;

ALTER TABLE __CHAT_SCHEMA__.chat_device_protocol_state
    ALTER COLUMN updated_at SET NOT NULL;
