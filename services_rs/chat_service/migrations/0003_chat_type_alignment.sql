ALTER TABLE __CHAT_SCHEMA__.devices
    ALTER COLUMN id TYPE VARCHAR(24);

ALTER TABLE __CHAT_SCHEMA__.device_auth
    ALTER COLUMN device_id TYPE VARCHAR(24);

ALTER TABLE __CHAT_SCHEMA__.messages
    ALTER COLUMN sender_id TYPE VARCHAR(24);

ALTER TABLE __CHAT_SCHEMA__.messages
    ALTER COLUMN recipient_id TYPE VARCHAR(24);

ALTER TABLE __CHAT_SCHEMA__.groups
    ALTER COLUMN creator_id TYPE VARCHAR(24);

ALTER TABLE __CHAT_SCHEMA__.group_members
    ALTER COLUMN device_id TYPE VARCHAR(24);

ALTER TABLE __CHAT_SCHEMA__.group_messages
    ALTER COLUMN sender_id TYPE VARCHAR(24);

ALTER TABLE __CHAT_SCHEMA__.group_key_events
    ALTER COLUMN actor_id TYPE VARCHAR(24);

ALTER TABLE __CHAT_SCHEMA__.device_key_events
    ALTER COLUMN device_id TYPE VARCHAR(24);

ALTER TABLE __CHAT_SCHEMA__.chat_identity_keys
    ALTER COLUMN device_id TYPE VARCHAR(24);

ALTER TABLE __CHAT_SCHEMA__.chat_signed_prekeys
    ALTER COLUMN device_id TYPE VARCHAR(24);

ALTER TABLE __CHAT_SCHEMA__.chat_one_time_prekeys
    ALTER COLUMN device_id TYPE VARCHAR(24);

ALTER TABLE __CHAT_SCHEMA__.chat_device_protocol_state
    ALTER COLUMN device_id TYPE VARCHAR(24);

ALTER TABLE __CHAT_SCHEMA__.chat_mailboxes
    ALTER COLUMN owner_device_id TYPE VARCHAR(24);

ALTER TABLE __CHAT_SCHEMA__.push_tokens
    ALTER COLUMN device_id TYPE VARCHAR(24);

ALTER TABLE __CHAT_SCHEMA__.contact_rules
    ALTER COLUMN device_id TYPE VARCHAR(24);

ALTER TABLE __CHAT_SCHEMA__.contact_rules
    ALTER COLUMN peer_id TYPE VARCHAR(24);

ALTER TABLE __CHAT_SCHEMA__.group_prefs
    ALTER COLUMN device_id TYPE VARCHAR(24);

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'devices'
          AND column_name = 'created_at'
          AND data_type <> 'timestamp with time zone'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.devices
            ALTER COLUMN created_at TYPE TEXT USING created_at::text;
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
          AND data_type <> 'timestamp with time zone'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.device_auth
            ALTER COLUMN rotated_at TYPE TEXT USING rotated_at::text;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'messages'
          AND column_name = 'created_at'
          AND data_type <> 'timestamp with time zone'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.messages
            ALTER COLUMN created_at TYPE TEXT USING created_at::text;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'messages'
          AND column_name = 'delivered_at'
          AND data_type <> 'timestamp with time zone'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.messages
            ALTER COLUMN delivered_at TYPE TEXT USING delivered_at::text;
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
          AND data_type <> 'timestamp with time zone'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.messages
            ALTER COLUMN read_at TYPE TEXT USING read_at::text;
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
          AND data_type <> 'timestamp with time zone'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.messages
            ALTER COLUMN expire_at TYPE TEXT USING expire_at::text;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'groups'
          AND column_name = 'created_at'
          AND data_type <> 'timestamp with time zone'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.groups
            ALTER COLUMN created_at TYPE TEXT USING created_at::text;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'group_members'
          AND column_name = 'joined_at'
          AND data_type <> 'timestamp with time zone'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.group_members
            ALTER COLUMN joined_at TYPE TEXT USING joined_at::text;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'group_messages'
          AND column_name = 'created_at'
          AND data_type <> 'timestamp with time zone'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.group_messages
            ALTER COLUMN created_at TYPE TEXT USING created_at::text;
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
          AND data_type <> 'timestamp with time zone'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.group_messages
            ALTER COLUMN expire_at TYPE TEXT USING expire_at::text;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'group_key_events'
          AND column_name = 'created_at'
          AND data_type <> 'timestamp with time zone'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.group_key_events
            ALTER COLUMN created_at TYPE TEXT USING created_at::text;
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
          AND data_type <> 'timestamp with time zone'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.device_key_events
            ALTER COLUMN created_at TYPE TEXT USING created_at::text;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'push_tokens'
          AND column_name = 'created_at'
          AND data_type <> 'timestamp with time zone'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.push_tokens
            ALTER COLUMN created_at TYPE TEXT USING created_at::text;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'push_tokens'
          AND column_name = 'last_seen_at'
          AND data_type <> 'timestamp with time zone'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.push_tokens
            ALTER COLUMN last_seen_at TYPE TEXT USING last_seen_at::text;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'contact_rules'
          AND column_name = 'created_at'
          AND data_type <> 'timestamp with time zone'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.contact_rules
            ALTER COLUMN created_at TYPE TEXT USING created_at::text;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'contact_rules'
          AND column_name = 'updated_at'
          AND data_type <> 'timestamp with time zone'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.contact_rules
            ALTER COLUMN updated_at TYPE TEXT USING updated_at::text;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'group_prefs'
          AND column_name = 'created_at'
          AND data_type <> 'timestamp with time zone'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.group_prefs
            ALTER COLUMN created_at TYPE TEXT USING created_at::text;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'group_prefs'
          AND column_name = 'updated_at'
          AND data_type <> 'timestamp with time zone'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.group_prefs
            ALTER COLUMN updated_at TYPE TEXT USING updated_at::text;
    END IF;
END $$;
