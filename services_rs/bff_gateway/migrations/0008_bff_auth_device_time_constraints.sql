DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_chat_devices_last_seen_after_created'
          AND conrelid = 'auth_chat_devices'::regclass
    ) THEN
        ALTER TABLE auth_chat_devices
            ADD CONSTRAINT chk_auth_chat_devices_last_seen_after_created
            CHECK (last_seen_at >= created_at) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_chat_devices_revoked_after_created'
          AND conrelid = 'auth_chat_devices'::regclass
    ) THEN
        ALTER TABLE auth_chat_devices
            ADD CONSTRAINT chk_auth_chat_devices_revoked_after_created
            CHECK (revoked_at IS NULL OR revoked_at >= created_at) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_device_sessions_last_seen_after_created'
          AND conrelid = 'device_sessions'::regclass
    ) THEN
        ALTER TABLE device_sessions
            ADD CONSTRAINT chk_device_sessions_last_seen_after_created
            CHECK (last_seen_at >= created_at) NOT VALID;
    END IF;
END $$;
