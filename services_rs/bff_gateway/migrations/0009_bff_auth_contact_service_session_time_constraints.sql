DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_chat_contacts_last_used_after_created'
          AND conrelid = 'auth_chat_contacts'::regclass
    ) THEN
        ALTER TABLE auth_chat_contacts
            ADD CONSTRAINT chk_auth_chat_contacts_last_used_after_created
            CHECK (last_used_at >= created_at) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_off_srv_sess_updated_after_created'
          AND conrelid = 'auth_official_service_sessions'::regclass
    ) THEN
        ALTER TABLE auth_official_service_sessions
            ADD CONSTRAINT chk_auth_off_srv_sess_updated_after_created
            CHECK (updated_at >= created_at) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_off_srv_sess_last_msg_after_created'
          AND conrelid = 'auth_official_service_sessions'::regclass
    ) THEN
        ALTER TABLE auth_official_service_sessions
            ADD CONSTRAINT chk_auth_off_srv_sess_last_msg_after_created
            CHECK (last_message_ts IS NULL OR last_message_ts >= created_at) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_off_srv_sess_updated_after_last_msg'
          AND conrelid = 'auth_official_service_sessions'::regclass
    ) THEN
        ALTER TABLE auth_official_service_sessions
            ADD CONSTRAINT chk_auth_off_srv_sess_updated_after_last_msg
            CHECK (last_message_ts IS NULL OR updated_at >= last_message_ts) NOT VALID;
    END IF;
END $$;
