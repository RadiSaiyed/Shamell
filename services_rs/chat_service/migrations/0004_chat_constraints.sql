DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_messages_protocol_version_known'
          AND conrelid = '__CHAT_SCHEMA__.messages'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.messages
            ADD CONSTRAINT chk_messages_protocol_version_known
            CHECK (protocol_version = ANY (ARRAY['v1_legacy','v2_libsignal'])) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_group_messages_protocol_version_known'
          AND conrelid = '__CHAT_SCHEMA__.group_messages'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.group_messages
            ADD CONSTRAINT chk_group_messages_protocol_version_known
            CHECK (protocol_version = ANY (ARRAY['v1_legacy','v2_libsignal'])) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_chat_device_protocol_state_protocol_floor_known'
          AND conrelid = '__CHAT_SCHEMA__.chat_device_protocol_state'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_device_protocol_state
            ADD CONSTRAINT chk_chat_device_protocol_state_protocol_floor_known
            CHECK (protocol_floor = ANY (ARRAY['v1_legacy','v2_libsignal'])) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_chat_device_protocol_state_supports_v2_boolean'
          AND conrelid = '__CHAT_SCHEMA__.chat_device_protocol_state'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_device_protocol_state
            ADD CONSTRAINT chk_chat_device_protocol_state_supports_v2_boolean
            CHECK (supports_v2::text IN ('0', '1', 'f', 't', 'false', 'true')) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_chat_device_protocol_state_v2_only_boolean'
          AND conrelid = '__CHAT_SCHEMA__.chat_device_protocol_state'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_device_protocol_state
            ADD CONSTRAINT chk_chat_device_protocol_state_v2_only_boolean
            CHECK (v2_only::text IN ('0', '1', 'f', 't', 'false', 'true')) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_chat_mailboxes_active_boolean'
          AND conrelid = '__CHAT_SCHEMA__.chat_mailboxes'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_mailboxes
            ADD CONSTRAINT chk_chat_mailboxes_active_boolean
            CHECK (active::text IN ('0', '1', 'f', 't', 'false', 'true')) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_contact_rules_blocked_boolean'
          AND conrelid = '__CHAT_SCHEMA__.contact_rules'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.contact_rules
            ADD CONSTRAINT chk_contact_rules_blocked_boolean
            CHECK (blocked::text IN ('0', '1', 'f', 't', 'false', 'true')) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_contact_rules_hidden_boolean'
          AND conrelid = '__CHAT_SCHEMA__.contact_rules'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.contact_rules
            ADD CONSTRAINT chk_contact_rules_hidden_boolean
            CHECK (hidden::text IN ('0', '1', 'f', 't', 'false', 'true')) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_contact_rules_muted_boolean'
          AND conrelid = '__CHAT_SCHEMA__.contact_rules'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.contact_rules
            ADD CONSTRAINT chk_contact_rules_muted_boolean
            CHECK (muted::text IN ('0', '1', 'f', 't', 'false', 'true')) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_contact_rules_starred_boolean'
          AND conrelid = '__CHAT_SCHEMA__.contact_rules'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.contact_rules
            ADD CONSTRAINT chk_contact_rules_starred_boolean
            CHECK (starred::text IN ('0', '1', 'f', 't', 'false', 'true')) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_contact_rules_pinned_boolean'
          AND conrelid = '__CHAT_SCHEMA__.contact_rules'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.contact_rules
            ADD CONSTRAINT chk_contact_rules_pinned_boolean
            CHECK (pinned::text IN ('0', '1', 'f', 't', 'false', 'true')) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_group_prefs_muted_boolean'
          AND conrelid = '__CHAT_SCHEMA__.group_prefs'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.group_prefs
            ADD CONSTRAINT chk_group_prefs_muted_boolean
            CHECK (muted::text IN ('0', '1', 'f', 't', 'false', 'true')) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_group_prefs_pinned_boolean'
          AND conrelid = '__CHAT_SCHEMA__.group_prefs'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.group_prefs
            ADD CONSTRAINT chk_group_prefs_pinned_boolean
            CHECK (pinned::text IN ('0', '1', 'f', 't', 'false', 'true')) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_devices_key_version_non_negative'
          AND conrelid = '__CHAT_SCHEMA__.devices'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.devices
            ADD CONSTRAINT chk_devices_key_version_non_negative
            CHECK (key_version >= 0) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_groups_key_version_non_negative'
          AND conrelid = '__CHAT_SCHEMA__.groups'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.groups
            ADD CONSTRAINT chk_groups_key_version_non_negative
            CHECK (key_version >= 0) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_group_key_events_version_positive'
          AND conrelid = '__CHAT_SCHEMA__.group_key_events'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.group_key_events
            ADD CONSTRAINT chk_group_key_events_version_positive
            CHECK (version > 0) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_device_key_events_version_positive'
          AND conrelid = '__CHAT_SCHEMA__.device_key_events'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.device_key_events
            ADD CONSTRAINT chk_device_key_events_version_positive
            CHECK (version > 0) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_chat_signed_prekeys_key_id_positive'
          AND conrelid = '__CHAT_SCHEMA__.chat_signed_prekeys'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_signed_prekeys
            ADD CONSTRAINT chk_chat_signed_prekeys_key_id_positive
            CHECK (key_id > 0) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_chat_one_time_prekeys_key_id_positive'
          AND conrelid = '__CHAT_SCHEMA__.chat_one_time_prekeys'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_one_time_prekeys
            ADD CONSTRAINT chk_chat_one_time_prekeys_key_id_positive
            CHECK (key_id > 0) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_chat_rate_limits_window_start_epoch_non_negative'
          AND conrelid = '__CHAT_SCHEMA__.chat_rate_limits'::regclass
    )
    AND EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'chat_rate_limits'
          AND column_name = 'window_start_epoch'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_rate_limits
            ADD CONSTRAINT chk_chat_rate_limits_window_start_epoch_non_negative
            CHECK (window_start_epoch >= 0) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_chat_rate_limits_request_count_non_negative'
          AND conrelid = '__CHAT_SCHEMA__.chat_rate_limits'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_rate_limits
            ADD CONSTRAINT chk_chat_rate_limits_request_count_non_negative
            CHECK (request_count >= 0) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_chat_rate_limits_updated_at_epoch_non_negative'
          AND conrelid = '__CHAT_SCHEMA__.chat_rate_limits'::regclass
    )
    AND EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'chat_rate_limits'
          AND column_name = 'updated_at_epoch'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_rate_limits
            ADD CONSTRAINT chk_chat_rate_limits_updated_at_epoch_non_negative
            CHECK (updated_at_epoch >= 0) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_group_members_role_known'
          AND conrelid = '__CHAT_SCHEMA__.group_members'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.group_members
            ADD CONSTRAINT chk_group_members_role_known
            CHECK (role = ANY (ARRAY['member','admin'])) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_group_messages_kind_known'
          AND conrelid = '__CHAT_SCHEMA__.group_messages'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.group_messages
            ADD CONSTRAINT chk_group_messages_kind_known
            CHECK ((kind IS NULL OR TRIM(kind)='' OR kind='sealed')) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'devices'
          AND column_name = 'created_at'
          AND data_type = 'text'
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_devices_created_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.devices'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.devices
            ADD CONSTRAINT chk_devices_created_at_text_timestamp
            CHECK (created_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$') NOT VALID;
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
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_device_auth_rotated_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.device_auth'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.device_auth
            ADD CONSTRAINT chk_device_auth_rotated_at_text_timestamp
            CHECK (rotated_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$') NOT VALID;
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
          AND data_type = 'text'
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_messages_created_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.messages'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.messages
            ADD CONSTRAINT chk_messages_created_at_text_timestamp
            CHECK (created_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$') NOT VALID;
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
          AND data_type = 'text'
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_messages_delivered_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.messages'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.messages
            ADD CONSTRAINT chk_messages_delivered_at_text_timestamp
            CHECK ((delivered_at IS NULL OR TRIM(delivered_at)='' OR delivered_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$')) NOT VALID;
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
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_messages_read_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.messages'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.messages
            ADD CONSTRAINT chk_messages_read_at_text_timestamp
            CHECK ((read_at IS NULL OR TRIM(read_at)='' OR read_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$')) NOT VALID;
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
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_messages_expire_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.messages'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.messages
            ADD CONSTRAINT chk_messages_expire_at_text_timestamp
            CHECK ((expire_at IS NULL OR TRIM(expire_at)='' OR expire_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$')) NOT VALID;
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
          AND data_type = 'text'
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_groups_created_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.groups'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.groups
            ADD CONSTRAINT chk_groups_created_at_text_timestamp
            CHECK (created_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$') NOT VALID;
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
          AND data_type = 'text'
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_group_members_joined_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.group_members'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.group_members
            ADD CONSTRAINT chk_group_members_joined_at_text_timestamp
            CHECK (joined_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$') NOT VALID;
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
          AND data_type = 'text'
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_group_messages_created_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.group_messages'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.group_messages
            ADD CONSTRAINT chk_group_messages_created_at_text_timestamp
            CHECK (created_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$') NOT VALID;
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
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_group_messages_expire_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.group_messages'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.group_messages
            ADD CONSTRAINT chk_group_messages_expire_at_text_timestamp
            CHECK ((expire_at IS NULL OR TRIM(expire_at)='' OR expire_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$')) NOT VALID;
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
          AND data_type = 'text'
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_group_key_events_created_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.group_key_events'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.group_key_events
            ADD CONSTRAINT chk_group_key_events_created_at_text_timestamp
            CHECK (created_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$') NOT VALID;
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
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_device_key_events_created_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.device_key_events'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.device_key_events
            ADD CONSTRAINT chk_device_key_events_created_at_text_timestamp
            CHECK (created_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$') NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'chat_identity_keys'
          AND column_name = 'updated_at'
          AND data_type = 'text'
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_chat_identity_keys_updated_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.chat_identity_keys'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_identity_keys
            ADD CONSTRAINT chk_chat_identity_keys_updated_at_text_timestamp
            CHECK (updated_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$') NOT VALID;
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
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_chat_signed_prekeys_updated_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.chat_signed_prekeys'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_signed_prekeys
            ADD CONSTRAINT chk_chat_signed_prekeys_updated_at_text_timestamp
            CHECK (updated_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$') NOT VALID;
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
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_chat_one_time_prekeys_created_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.chat_one_time_prekeys'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_one_time_prekeys
            ADD CONSTRAINT chk_chat_one_time_prekeys_created_at_text_timestamp
            CHECK (created_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$') NOT VALID;
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
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_chat_one_time_prekeys_consumed_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.chat_one_time_prekeys'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_one_time_prekeys
            ADD CONSTRAINT chk_chat_one_time_prekeys_consumed_at_text_timestamp
            CHECK ((consumed_at IS NULL OR TRIM(consumed_at)='' OR consumed_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$')) NOT VALID;
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
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_chat_device_protocol_state_updated_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.chat_device_protocol_state'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_device_protocol_state
            ADD CONSTRAINT chk_chat_device_protocol_state_updated_at_text_timestamp
            CHECK (updated_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$') NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'chat_mailboxes'
          AND column_name = 'created_at'
          AND data_type = 'text'
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_chat_mailboxes_created_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.chat_mailboxes'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_mailboxes
            ADD CONSTRAINT chk_chat_mailboxes_created_at_text_timestamp
            CHECK (created_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$') NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'chat_mailboxes'
          AND column_name = 'rotated_at'
          AND data_type = 'text'
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_chat_mailboxes_rotated_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.chat_mailboxes'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_mailboxes
            ADD CONSTRAINT chk_chat_mailboxes_rotated_at_text_timestamp
            CHECK ((rotated_at IS NULL OR TRIM(rotated_at)='' OR rotated_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$')) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'chat_mailbox_messages'
          AND column_name = 'created_at'
          AND data_type = 'text'
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_chat_mailbox_messages_created_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.chat_mailbox_messages'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_mailbox_messages
            ADD CONSTRAINT chk_chat_mailbox_messages_created_at_text_timestamp
            CHECK (created_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$') NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'chat_mailbox_messages'
          AND column_name = 'expire_at'
          AND data_type = 'text'
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_chat_mailbox_messages_expire_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.chat_mailbox_messages'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_mailbox_messages
            ADD CONSTRAINT chk_chat_mailbox_messages_expire_at_text_timestamp
            CHECK ((expire_at IS NULL OR TRIM(expire_at)='' OR expire_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$')) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'chat_mailbox_messages'
          AND column_name = 'consumed_at'
          AND data_type = 'text'
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_chat_mailbox_messages_consumed_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.chat_mailbox_messages'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.chat_mailbox_messages
            ADD CONSTRAINT chk_chat_mailbox_messages_consumed_at_text_timestamp
            CHECK ((consumed_at IS NULL OR TRIM(consumed_at)='' OR consumed_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$')) NOT VALID;
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
          AND data_type = 'text'
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_push_tokens_created_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.push_tokens'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.push_tokens
            ADD CONSTRAINT chk_push_tokens_created_at_text_timestamp
            CHECK (created_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$') NOT VALID;
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
          AND data_type = 'text'
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_push_tokens_last_seen_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.push_tokens'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.push_tokens
            ADD CONSTRAINT chk_push_tokens_last_seen_at_text_timestamp
            CHECK (last_seen_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$') NOT VALID;
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
          AND data_type = 'text'
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_contact_rules_created_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.contact_rules'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.contact_rules
            ADD CONSTRAINT chk_contact_rules_created_at_text_timestamp
            CHECK (created_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$') NOT VALID;
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
          AND data_type = 'text'
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_contact_rules_updated_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.contact_rules'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.contact_rules
            ADD CONSTRAINT chk_contact_rules_updated_at_text_timestamp
            CHECK (updated_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$') NOT VALID;
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
          AND data_type = 'text'
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_group_prefs_created_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.group_prefs'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.group_prefs
            ADD CONSTRAINT chk_group_prefs_created_at_text_timestamp
            CHECK (created_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$') NOT VALID;
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
          AND data_type = 'text'
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_group_prefs_updated_at_text_timestamp'
          AND conrelid = '__CHAT_SCHEMA__.group_prefs'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.group_prefs
            ADD CONSTRAINT chk_group_prefs_updated_at_text_timestamp
            CHECK (updated_at ~ '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:[0-9]{2})?))$') NOT VALID;
    END IF;
END $$;

DELETE FROM __CHAT_SCHEMA__.device_auth child_row
WHERE child_row.device_id IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM __CHAT_SCHEMA__.devices parent_row
        WHERE parent_row.id = child_row.device_id
    );

DELETE FROM __CHAT_SCHEMA__.group_members child_row
WHERE child_row.group_id IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM __CHAT_SCHEMA__.groups parent_row
        WHERE parent_row.id = child_row.group_id
    );

DELETE FROM __CHAT_SCHEMA__.group_members child_row
WHERE child_row.device_id IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM __CHAT_SCHEMA__.devices parent_row
        WHERE parent_row.id = child_row.device_id
    );

DELETE FROM __CHAT_SCHEMA__.group_key_events child_row
WHERE child_row.group_id IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM __CHAT_SCHEMA__.groups parent_row
        WHERE parent_row.id = child_row.group_id
    );

DELETE FROM __CHAT_SCHEMA__.group_key_events child_row
WHERE child_row.actor_id IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM __CHAT_SCHEMA__.devices parent_row
        WHERE parent_row.id = child_row.actor_id
    );

DELETE FROM __CHAT_SCHEMA__.device_key_events child_row
WHERE child_row.device_id IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM __CHAT_SCHEMA__.devices parent_row
        WHERE parent_row.id = child_row.device_id
    );

DELETE FROM __CHAT_SCHEMA__.chat_identity_keys child_row
WHERE child_row.device_id IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM __CHAT_SCHEMA__.devices parent_row
        WHERE parent_row.id = child_row.device_id
    );

DELETE FROM __CHAT_SCHEMA__.chat_signed_prekeys child_row
WHERE child_row.device_id IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM __CHAT_SCHEMA__.devices parent_row
        WHERE parent_row.id = child_row.device_id
    );

DELETE FROM __CHAT_SCHEMA__.chat_one_time_prekeys child_row
WHERE child_row.device_id IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM __CHAT_SCHEMA__.devices parent_row
        WHERE parent_row.id = child_row.device_id
    );

DELETE FROM __CHAT_SCHEMA__.chat_device_protocol_state child_row
WHERE child_row.device_id IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM __CHAT_SCHEMA__.devices parent_row
        WHERE parent_row.id = child_row.device_id
    );

DELETE FROM __CHAT_SCHEMA__.chat_mailboxes child_row
WHERE child_row.owner_device_id IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM __CHAT_SCHEMA__.devices parent_row
        WHERE parent_row.id = child_row.owner_device_id
    );

DELETE FROM __CHAT_SCHEMA__.chat_mailbox_messages child_row
WHERE child_row.token_hash IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM __CHAT_SCHEMA__.chat_mailboxes parent_row
        WHERE parent_row.token_hash = child_row.token_hash
    );

DELETE FROM __CHAT_SCHEMA__.push_tokens child_row
WHERE child_row.device_id IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM __CHAT_SCHEMA__.devices parent_row
        WHERE parent_row.id = child_row.device_id
    );

DELETE FROM __CHAT_SCHEMA__.contact_rules child_row
WHERE child_row.device_id IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM __CHAT_SCHEMA__.devices parent_row
        WHERE parent_row.id = child_row.device_id
    );

DELETE FROM __CHAT_SCHEMA__.contact_rules child_row
WHERE child_row.peer_id IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM __CHAT_SCHEMA__.devices parent_row
        WHERE parent_row.id = child_row.peer_id
    );

DELETE FROM __CHAT_SCHEMA__.group_prefs child_row
WHERE child_row.device_id IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM __CHAT_SCHEMA__.devices parent_row
        WHERE parent_row.id = child_row.device_id
    );

DELETE FROM __CHAT_SCHEMA__.group_prefs child_row
WHERE child_row.group_id IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM __CHAT_SCHEMA__.groups parent_row
        WHERE parent_row.id = child_row.group_id
    );

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_device_auth_device_id'
          AND conrelid = '__CHAT_SCHEMA__.device_auth'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __CHAT_SCHEMA__.device_auth child_row
            WHERE child_row.device_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __CHAT_SCHEMA__.devices parent_row
                    WHERE parent_row.id = child_row.device_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned chat references block ensure_schema: device_auth.device_id -> devices.id';
        END IF;
        ALTER TABLE __CHAT_SCHEMA__.device_auth
            ADD CONSTRAINT fk_device_auth_device_id
            FOREIGN KEY (device_id) REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_group_members_group_id'
          AND conrelid = '__CHAT_SCHEMA__.group_members'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __CHAT_SCHEMA__.group_members child_row
            WHERE child_row.group_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __CHAT_SCHEMA__.groups parent_row
                    WHERE parent_row.id = child_row.group_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned chat references block ensure_schema: group_members.group_id -> groups.id';
        END IF;
        ALTER TABLE __CHAT_SCHEMA__.group_members
            ADD CONSTRAINT fk_group_members_group_id
            FOREIGN KEY (group_id) REFERENCES __CHAT_SCHEMA__.groups(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_group_members_device_id'
          AND conrelid = '__CHAT_SCHEMA__.group_members'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __CHAT_SCHEMA__.group_members child_row
            WHERE child_row.device_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __CHAT_SCHEMA__.devices parent_row
                    WHERE parent_row.id = child_row.device_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned chat references block ensure_schema: group_members.device_id -> devices.id';
        END IF;
        ALTER TABLE __CHAT_SCHEMA__.group_members
            ADD CONSTRAINT fk_group_members_device_id
            FOREIGN KEY (device_id) REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_group_key_events_group_id'
          AND conrelid = '__CHAT_SCHEMA__.group_key_events'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __CHAT_SCHEMA__.group_key_events child_row
            WHERE child_row.group_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __CHAT_SCHEMA__.groups parent_row
                    WHERE parent_row.id = child_row.group_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned chat references block ensure_schema: group_key_events.group_id -> groups.id';
        END IF;
        ALTER TABLE __CHAT_SCHEMA__.group_key_events
            ADD CONSTRAINT fk_group_key_events_group_id
            FOREIGN KEY (group_id) REFERENCES __CHAT_SCHEMA__.groups(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_group_key_events_actor_id'
          AND conrelid = '__CHAT_SCHEMA__.group_key_events'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __CHAT_SCHEMA__.group_key_events child_row
            WHERE child_row.actor_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __CHAT_SCHEMA__.devices parent_row
                    WHERE parent_row.id = child_row.actor_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned chat references block ensure_schema: group_key_events.actor_id -> devices.id';
        END IF;
        ALTER TABLE __CHAT_SCHEMA__.group_key_events
            ADD CONSTRAINT fk_group_key_events_actor_id
            FOREIGN KEY (actor_id) REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_device_key_events_device_id'
          AND conrelid = '__CHAT_SCHEMA__.device_key_events'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __CHAT_SCHEMA__.device_key_events child_row
            WHERE child_row.device_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __CHAT_SCHEMA__.devices parent_row
                    WHERE parent_row.id = child_row.device_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned chat references block ensure_schema: device_key_events.device_id -> devices.id';
        END IF;
        ALTER TABLE __CHAT_SCHEMA__.device_key_events
            ADD CONSTRAINT fk_device_key_events_device_id
            FOREIGN KEY (device_id) REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_chat_identity_keys_device_id'
          AND conrelid = '__CHAT_SCHEMA__.chat_identity_keys'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __CHAT_SCHEMA__.chat_identity_keys child_row
            WHERE child_row.device_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __CHAT_SCHEMA__.devices parent_row
                    WHERE parent_row.id = child_row.device_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned chat references block ensure_schema: chat_identity_keys.device_id -> devices.id';
        END IF;
        ALTER TABLE __CHAT_SCHEMA__.chat_identity_keys
            ADD CONSTRAINT fk_chat_identity_keys_device_id
            FOREIGN KEY (device_id) REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_chat_signed_prekeys_device_id'
          AND conrelid = '__CHAT_SCHEMA__.chat_signed_prekeys'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __CHAT_SCHEMA__.chat_signed_prekeys child_row
            WHERE child_row.device_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __CHAT_SCHEMA__.devices parent_row
                    WHERE parent_row.id = child_row.device_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned chat references block ensure_schema: chat_signed_prekeys.device_id -> devices.id';
        END IF;
        ALTER TABLE __CHAT_SCHEMA__.chat_signed_prekeys
            ADD CONSTRAINT fk_chat_signed_prekeys_device_id
            FOREIGN KEY (device_id) REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_chat_one_time_prekeys_device_id'
          AND conrelid = '__CHAT_SCHEMA__.chat_one_time_prekeys'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __CHAT_SCHEMA__.chat_one_time_prekeys child_row
            WHERE child_row.device_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __CHAT_SCHEMA__.devices parent_row
                    WHERE parent_row.id = child_row.device_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned chat references block ensure_schema: chat_one_time_prekeys.device_id -> devices.id';
        END IF;
        ALTER TABLE __CHAT_SCHEMA__.chat_one_time_prekeys
            ADD CONSTRAINT fk_chat_one_time_prekeys_device_id
            FOREIGN KEY (device_id) REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_chat_device_protocol_state_device_id'
          AND conrelid = '__CHAT_SCHEMA__.chat_device_protocol_state'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __CHAT_SCHEMA__.chat_device_protocol_state child_row
            WHERE child_row.device_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __CHAT_SCHEMA__.devices parent_row
                    WHERE parent_row.id = child_row.device_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned chat references block ensure_schema: chat_device_protocol_state.device_id -> devices.id';
        END IF;
        ALTER TABLE __CHAT_SCHEMA__.chat_device_protocol_state
            ADD CONSTRAINT fk_chat_device_protocol_state_device_id
            FOREIGN KEY (device_id) REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_chat_mailboxes_owner_device_id'
          AND conrelid = '__CHAT_SCHEMA__.chat_mailboxes'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __CHAT_SCHEMA__.chat_mailboxes child_row
            WHERE child_row.owner_device_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __CHAT_SCHEMA__.devices parent_row
                    WHERE parent_row.id = child_row.owner_device_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned chat references block ensure_schema: chat_mailboxes.owner_device_id -> devices.id';
        END IF;
        ALTER TABLE __CHAT_SCHEMA__.chat_mailboxes
            ADD CONSTRAINT fk_chat_mailboxes_owner_device_id
            FOREIGN KEY (owner_device_id) REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_chat_mailbox_messages_token_hash'
          AND conrelid = '__CHAT_SCHEMA__.chat_mailbox_messages'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __CHAT_SCHEMA__.chat_mailbox_messages child_row
            WHERE child_row.token_hash IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __CHAT_SCHEMA__.chat_mailboxes parent_row
                    WHERE parent_row.token_hash = child_row.token_hash
                )
        ) THEN
            RAISE EXCEPTION 'orphaned chat references block ensure_schema: chat_mailbox_messages.token_hash -> chat_mailboxes.token_hash';
        END IF;
        ALTER TABLE __CHAT_SCHEMA__.chat_mailbox_messages
            ADD CONSTRAINT fk_chat_mailbox_messages_token_hash
            FOREIGN KEY (token_hash) REFERENCES __CHAT_SCHEMA__.chat_mailboxes(token_hash) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_push_tokens_device_id'
          AND conrelid = '__CHAT_SCHEMA__.push_tokens'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __CHAT_SCHEMA__.push_tokens child_row
            WHERE child_row.device_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __CHAT_SCHEMA__.devices parent_row
                    WHERE parent_row.id = child_row.device_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned chat references block ensure_schema: push_tokens.device_id -> devices.id';
        END IF;
        ALTER TABLE __CHAT_SCHEMA__.push_tokens
            ADD CONSTRAINT fk_push_tokens_device_id
            FOREIGN KEY (device_id) REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_contact_rules_device_id'
          AND conrelid = '__CHAT_SCHEMA__.contact_rules'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __CHAT_SCHEMA__.contact_rules child_row
            WHERE child_row.device_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __CHAT_SCHEMA__.devices parent_row
                    WHERE parent_row.id = child_row.device_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned chat references block ensure_schema: contact_rules.device_id -> devices.id';
        END IF;
        ALTER TABLE __CHAT_SCHEMA__.contact_rules
            ADD CONSTRAINT fk_contact_rules_device_id
            FOREIGN KEY (device_id) REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_contact_rules_peer_id'
          AND conrelid = '__CHAT_SCHEMA__.contact_rules'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __CHAT_SCHEMA__.contact_rules child_row
            WHERE child_row.peer_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __CHAT_SCHEMA__.devices parent_row
                    WHERE parent_row.id = child_row.peer_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned chat references block ensure_schema: contact_rules.peer_id -> devices.id';
        END IF;
        ALTER TABLE __CHAT_SCHEMA__.contact_rules
            ADD CONSTRAINT fk_contact_rules_peer_id
            FOREIGN KEY (peer_id) REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_group_prefs_device_id'
          AND conrelid = '__CHAT_SCHEMA__.group_prefs'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __CHAT_SCHEMA__.group_prefs child_row
            WHERE child_row.device_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __CHAT_SCHEMA__.devices parent_row
                    WHERE parent_row.id = child_row.device_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned chat references block ensure_schema: group_prefs.device_id -> devices.id';
        END IF;
        ALTER TABLE __CHAT_SCHEMA__.group_prefs
            ADD CONSTRAINT fk_group_prefs_device_id
            FOREIGN KEY (device_id) REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_group_prefs_group_id'
          AND conrelid = '__CHAT_SCHEMA__.group_prefs'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __CHAT_SCHEMA__.group_prefs child_row
            WHERE child_row.group_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __CHAT_SCHEMA__.groups parent_row
                    WHERE parent_row.id = child_row.group_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned chat references block ensure_schema: group_prefs.group_id -> groups.id';
        END IF;
        ALTER TABLE __CHAT_SCHEMA__.group_prefs
            ADD CONSTRAINT fk_group_prefs_group_id
            FOREIGN KEY (group_id) REFERENCES __CHAT_SCHEMA__.groups(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_messages_sender_id'
          AND conrelid = '__CHAT_SCHEMA__.messages'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __CHAT_SCHEMA__.messages child_row
            WHERE child_row.sender_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __CHAT_SCHEMA__.devices parent_row
                    WHERE parent_row.id = child_row.sender_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned chat history references block ensure_schema: messages.sender_id -> devices.id';
        END IF;
        ALTER TABLE __CHAT_SCHEMA__.messages
            ADD CONSTRAINT fk_messages_sender_id
            FOREIGN KEY (sender_id) REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE RESTRICT;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_messages_recipient_id'
          AND conrelid = '__CHAT_SCHEMA__.messages'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __CHAT_SCHEMA__.messages child_row
            WHERE child_row.recipient_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __CHAT_SCHEMA__.devices parent_row
                    WHERE parent_row.id = child_row.recipient_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned chat history references block ensure_schema: messages.recipient_id -> devices.id';
        END IF;
        ALTER TABLE __CHAT_SCHEMA__.messages
            ADD CONSTRAINT fk_messages_recipient_id
            FOREIGN KEY (recipient_id) REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE RESTRICT;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_groups_creator_id'
          AND conrelid = '__CHAT_SCHEMA__.groups'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __CHAT_SCHEMA__.groups child_row
            WHERE child_row.creator_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __CHAT_SCHEMA__.devices parent_row
                    WHERE parent_row.id = child_row.creator_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned chat history references block ensure_schema: groups.creator_id -> devices.id';
        END IF;
        ALTER TABLE __CHAT_SCHEMA__.groups
            ADD CONSTRAINT fk_groups_creator_id
            FOREIGN KEY (creator_id) REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE RESTRICT;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_group_messages_group_id'
          AND conrelid = '__CHAT_SCHEMA__.group_messages'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __CHAT_SCHEMA__.group_messages child_row
            WHERE child_row.group_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __CHAT_SCHEMA__.groups parent_row
                    WHERE parent_row.id = child_row.group_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned chat history references block ensure_schema: group_messages.group_id -> groups.id';
        END IF;
        ALTER TABLE __CHAT_SCHEMA__.group_messages
            ADD CONSTRAINT fk_group_messages_group_id
            FOREIGN KEY (group_id) REFERENCES __CHAT_SCHEMA__.groups(id) ON DELETE RESTRICT;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_group_messages_sender_id'
          AND conrelid = '__CHAT_SCHEMA__.group_messages'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __CHAT_SCHEMA__.group_messages child_row
            WHERE child_row.sender_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __CHAT_SCHEMA__.devices parent_row
                    WHERE parent_row.id = child_row.sender_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned chat history references block ensure_schema: group_messages.sender_id -> devices.id';
        END IF;
        ALTER TABLE __CHAT_SCHEMA__.group_messages
            ADD CONSTRAINT fk_group_messages_sender_id
            FOREIGN KEY (sender_id) REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE RESTRICT;
    END IF;
END $$;

DELETE FROM __CHAT_SCHEMA__.messages stale
USING __CHAT_SCHEMA__.messages kept
WHERE stale.id <> kept.id
  AND stale.sender_id = kept.sender_id
  AND stale.recipient_id = kept.recipient_id
  AND stale.nonce_b64 = kept.nonce_b64
  AND (
      kept.created_at < stale.created_at
      OR (kept.created_at = stale.created_at AND kept.id < stale.id)
  );

DELETE FROM __CHAT_SCHEMA__.group_messages stale
USING __CHAT_SCHEMA__.group_messages kept
WHERE stale.id <> kept.id
  AND stale.group_id = kept.group_id
  AND stale.sender_id = kept.sender_id
  AND stale.nonce_b64 IS NOT NULL
  AND kept.nonce_b64 IS NOT NULL
  AND stale.nonce_b64 = kept.nonce_b64
  AND (
      kept.created_at < stale.created_at
      OR (kept.created_at = stale.created_at AND kept.id < stale.id)
  );

CREATE UNIQUE INDEX IF NOT EXISTS uq_messages_sender_recipient_nonce
    ON __CHAT_SCHEMA__.messages(sender_id, recipient_id, nonce_b64);

CREATE UNIQUE INDEX IF NOT EXISTS uq_group_messages_group_sender_nonce
    ON __CHAT_SCHEMA__.group_messages(group_id, sender_id, nonce_b64);
