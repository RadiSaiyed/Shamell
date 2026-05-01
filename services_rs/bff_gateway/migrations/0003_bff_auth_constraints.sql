DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_device_login_challenges_status_known'
          AND conrelid = 'device_login_challenges'::regclass
    ) THEN
        ALTER TABLE device_login_challenges
            ADD CONSTRAINT chk_device_login_challenges_status_known
            CHECK (status IN ('pending', 'approved')) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_official_accounts_kind_known'
          AND conrelid = 'auth_official_accounts'::regclass
    ) THEN
        ALTER TABLE auth_official_accounts
            ADD CONSTRAINT chk_auth_official_accounts_kind_known
            CHECK (kind IN ('service', 'subscription')) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_official_template_messages_kind_known'
          AND conrelid = 'auth_official_template_messages'::regclass
    ) THEN
        ALTER TABLE auth_official_template_messages
            ADD CONSTRAINT chk_auth_official_template_messages_kind_known
            CHECK (kind = 'service') NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_official_auto_replies_kind_known'
          AND conrelid = 'auth_official_auto_replies'::regclass
    ) THEN
        ALTER TABLE auth_official_auto_replies
            ADD CONSTRAINT chk_auth_official_auto_replies_kind_known
            CHECK (kind IN ('welcome', 'keyword')) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_official_notification_modes_mode_known'
          AND conrelid = 'auth_official_notification_modes'::regclass
    ) THEN
        ALTER TABLE auth_official_notification_modes
            ADD CONSTRAINT chk_auth_official_notification_modes_mode_known
            CHECK (mode IN ('full', 'summary', 'muted')) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_official_service_sessions_status_known'
          AND conrelid = 'auth_official_service_sessions'::regclass
    ) THEN
        ALTER TABLE auth_official_service_sessions
            ADD CONSTRAINT chk_auth_official_service_sessions_status_known
            CHECK (status IN ('open', 'closed')) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_rate_limits_window_start_epoch_non_negative'
          AND conrelid = 'auth_rate_limits'::regclass
    )
    AND EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = ANY(current_schemas(false))
          AND table_name = 'auth_rate_limits'
          AND column_name = 'window_start_epoch'
    ) THEN
        ALTER TABLE auth_rate_limits
            ADD CONSTRAINT chk_auth_rate_limits_window_start_epoch_non_negative
            CHECK (window_start_epoch >= 0) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_rate_limits_request_count_non_negative'
          AND conrelid = 'auth_rate_limits'::regclass
    ) THEN
        ALTER TABLE auth_rate_limits
            ADD CONSTRAINT chk_auth_rate_limits_request_count_non_negative
            CHECK (request_count >= 0) NOT VALID;
    END IF;
END $$;
