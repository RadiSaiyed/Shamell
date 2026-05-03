DO $$
DECLARE
    canonical_regex CONSTANT TEXT := '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$';
    rec RECORD;
    predicate TEXT;
BEGIN
    FOR rec IN
        SELECT *
        FROM (
            VALUES
                ('devices', 'created_at', 'chk_devices_created_at_text_timestamp', FALSE),
                ('device_auth', 'rotated_at', 'chk_device_auth_rotated_at_text_timestamp', FALSE),
                ('messages', 'created_at', 'chk_messages_created_at_text_timestamp', FALSE),
                ('messages', 'delivered_at', 'chk_messages_delivered_at_text_timestamp', TRUE),
                ('messages', 'read_at', 'chk_messages_read_at_text_timestamp', TRUE),
                ('messages', 'expire_at', 'chk_messages_expire_at_text_timestamp', TRUE),
                ('groups', 'created_at', 'chk_groups_created_at_text_timestamp', FALSE),
                ('group_members', 'joined_at', 'chk_group_members_joined_at_text_timestamp', FALSE),
                ('group_messages', 'created_at', 'chk_group_messages_created_at_text_timestamp', FALSE),
                ('group_messages', 'expire_at', 'chk_group_messages_expire_at_text_timestamp', TRUE),
                ('group_key_events', 'created_at', 'chk_group_key_events_created_at_text_timestamp', FALSE),
                ('device_key_events', 'created_at', 'chk_device_key_events_created_at_text_timestamp', FALSE),
                ('chat_identity_keys', 'updated_at', 'chk_chat_identity_keys_updated_at_text_timestamp', FALSE),
                ('chat_signed_prekeys', 'updated_at', 'chk_chat_signed_prekeys_updated_at_text_timestamp', FALSE),
                ('chat_one_time_prekeys', 'created_at', 'chk_chat_one_time_prekeys_created_at_text_timestamp', FALSE),
                ('chat_one_time_prekeys', 'consumed_at', 'chk_chat_one_time_prekeys_consumed_at_text_timestamp', TRUE),
                ('chat_device_protocol_state', 'updated_at', 'chk_chat_device_protocol_state_updated_at_text_timestamp', FALSE),
                ('chat_mailboxes', 'created_at', 'chk_chat_mailboxes_created_at_text_timestamp', FALSE),
                ('chat_mailboxes', 'rotated_at', 'chk_chat_mailboxes_rotated_at_text_timestamp', TRUE),
                ('chat_mailbox_messages', 'created_at', 'chk_chat_mailbox_messages_created_at_text_timestamp', FALSE),
                ('chat_mailbox_messages', 'expire_at', 'chk_chat_mailbox_messages_expire_at_text_timestamp', TRUE),
                ('chat_mailbox_messages', 'consumed_at', 'chk_chat_mailbox_messages_consumed_at_text_timestamp', TRUE),
                ('push_tokens', 'created_at', 'chk_push_tokens_created_at_text_timestamp', FALSE),
                ('push_tokens', 'last_seen_at', 'chk_push_tokens_last_seen_at_text_timestamp', FALSE),
                ('contact_rules', 'created_at', 'chk_contact_rules_created_at_text_timestamp', FALSE),
                ('contact_rules', 'updated_at', 'chk_contact_rules_updated_at_text_timestamp', FALSE),
                ('group_prefs', 'created_at', 'chk_group_prefs_created_at_text_timestamp', FALSE),
                ('group_prefs', 'updated_at', 'chk_group_prefs_updated_at_text_timestamp', FALSE)
        ) AS defs(table_name, column_name, constraint_name, optional)
    LOOP
        IF EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = '__CHAT_SCHEMA__'
              AND table_name = rec.table_name
              AND column_name = rec.column_name
              AND data_type = 'text'
        ) THEN
            EXECUTE format(
                'UPDATE __CHAT_SCHEMA__.%1$I
                 SET %2$I = to_char((%2$I::timestamptz AT TIME ZONE ''UTC''), ''YYYY-MM-DD"T"HH24:MI:SS"Z"'')
                 WHERE %2$I IS NOT NULL AND BTRIM(%2$I) <> ''''',
                rec.table_name,
                rec.column_name
            );

            IF rec.optional THEN
                predicate := format(
                    '(%1$I IS NULL OR BTRIM(%1$I)='''' OR %1$I ~ %2$L)',
                    rec.column_name,
                    canonical_regex
                );
            ELSE
                predicate := format('%1$I ~ %2$L', rec.column_name, canonical_regex);
            END IF;

            IF EXISTS (
                SELECT 1
                FROM pg_constraint
                WHERE conrelid = to_regclass(format('__CHAT_SCHEMA__.%I', rec.table_name))
                  AND conname = rec.constraint_name
            ) THEN
                EXECUTE format(
                    'ALTER TABLE __CHAT_SCHEMA__.%1$I DROP CONSTRAINT %2$I',
                    rec.table_name,
                    rec.constraint_name
                );
            END IF;

            EXECUTE format(
                'ALTER TABLE __CHAT_SCHEMA__.%1$I ADD CONSTRAINT %2$I CHECK (%3$s) NOT VALID',
                rec.table_name,
                rec.constraint_name,
                predicate
            );
        END IF;
    END LOOP;
END $$;
