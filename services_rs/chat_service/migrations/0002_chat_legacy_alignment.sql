ALTER TABLE __CHAT_SCHEMA__.messages
    ADD COLUMN IF NOT EXISTS protocol_version VARCHAR(24) DEFAULT 'v1_legacy';

ALTER TABLE __CHAT_SCHEMA__.messages
    ADD COLUMN IF NOT EXISTS sealed_sender BOOLEAN DEFAULT FALSE;

ALTER TABLE __CHAT_SCHEMA__.messages
    ALTER COLUMN sealed_sender DROP DEFAULT;

ALTER TABLE __CHAT_SCHEMA__.messages
    ALTER COLUMN sealed_sender TYPE BOOLEAN
    USING CASE
        WHEN sealed_sender::text IN ('1', 't', 'true', 'TRUE') THEN TRUE
        ELSE FALSE
    END;

UPDATE __CHAT_SCHEMA__.messages
SET sealed_sender = FALSE
WHERE sealed_sender IS NULL;

ALTER TABLE __CHAT_SCHEMA__.messages
    ALTER COLUMN sealed_sender SET DEFAULT FALSE;

ALTER TABLE __CHAT_SCHEMA__.messages
    ALTER COLUMN sealed_sender SET NOT NULL;

UPDATE __CHAT_SCHEMA__.messages
SET protocol_version = 'v1_legacy'
WHERE protocol_version IS NULL
   OR TRIM(protocol_version) = '';

ALTER TABLE __CHAT_SCHEMA__.messages
    ALTER COLUMN box_b64 TYPE TEXT;

ALTER TABLE __CHAT_SCHEMA__.group_messages
    ADD COLUMN IF NOT EXISTS protocol_version VARCHAR(24) DEFAULT 'v1_legacy';

UPDATE __CHAT_SCHEMA__.group_messages
SET protocol_version = 'v1_legacy'
WHERE protocol_version IS NULL
   OR TRIM(protocol_version) = '';

ALTER TABLE __CHAT_SCHEMA__.chat_device_protocol_state
    ADD COLUMN IF NOT EXISTS protocol_floor VARCHAR(24) DEFAULT 'v1_legacy';

ALTER TABLE __CHAT_SCHEMA__.chat_device_protocol_state
    ADD COLUMN IF NOT EXISTS supports_v2 INTEGER DEFAULT 0;

ALTER TABLE __CHAT_SCHEMA__.chat_device_protocol_state
    ADD COLUMN IF NOT EXISTS v2_only INTEGER DEFAULT 0;

ALTER TABLE __CHAT_SCHEMA__.chat_device_protocol_state
    ADD COLUMN IF NOT EXISTS updated_at TEXT;

ALTER TABLE __CHAT_SCHEMA__.chat_mailboxes
    ADD COLUMN IF NOT EXISTS rotated_at TEXT;

ALTER TABLE __CHAT_SCHEMA__.chat_mailboxes
    ADD COLUMN IF NOT EXISTS active INTEGER DEFAULT 1;

DO $$
DECLARE
    rotated_at_is_text BOOLEAN;
    active_is_boolean BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'chat_mailboxes'
          AND column_name = 'rotated_at'
          AND data_type = 'text'
    ) INTO rotated_at_is_text;

    SELECT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'chat_mailboxes'
          AND column_name = 'active'
          AND data_type = 'boolean'
    ) INTO active_is_boolean;

    IF rotated_at_is_text THEN
        IF active_is_boolean THEN
            EXECUTE $mailboxes_text_bool$
                WITH ranked AS (
                    SELECT token_hash,
                           ROW_NUMBER() OVER (
                               PARTITION BY owner_device_id
                               ORDER BY created_at DESC, token_hash DESC
                           ) AS rn
                    FROM __CHAT_SCHEMA__.chat_mailboxes
                    WHERE active IS TRUE
                )
                UPDATE __CHAT_SCHEMA__.chat_mailboxes AS mailbox
                SET active = FALSE,
                    rotated_at = COALESCE(NULLIF(TRIM(mailbox.rotated_at), ''), mailbox.created_at)
                FROM ranked
                WHERE mailbox.token_hash = ranked.token_hash
                  AND ranked.rn > 1
            $mailboxes_text_bool$;
        ELSE
            EXECUTE $mailboxes_text_int$
                WITH ranked AS (
                    SELECT token_hash,
                           ROW_NUMBER() OVER (
                               PARTITION BY owner_device_id
                               ORDER BY created_at DESC, token_hash DESC
                           ) AS rn
                    FROM __CHAT_SCHEMA__.chat_mailboxes
                    WHERE active = 1
                )
                UPDATE __CHAT_SCHEMA__.chat_mailboxes AS mailbox
                SET active = 0,
                    rotated_at = COALESCE(NULLIF(TRIM(mailbox.rotated_at), ''), mailbox.created_at)
                FROM ranked
                WHERE mailbox.token_hash = ranked.token_hash
                  AND ranked.rn > 1
            $mailboxes_text_int$;
        END IF;
    ELSE
        IF active_is_boolean THEN
            EXECUTE $mailboxes_ts_bool$
                WITH ranked AS (
                    SELECT token_hash,
                           ROW_NUMBER() OVER (
                               PARTITION BY owner_device_id
                               ORDER BY created_at DESC, token_hash DESC
                           ) AS rn
                    FROM __CHAT_SCHEMA__.chat_mailboxes
                    WHERE active IS TRUE
                )
                UPDATE __CHAT_SCHEMA__.chat_mailboxes AS mailbox
                SET active = FALSE,
                    rotated_at = COALESCE(mailbox.rotated_at, mailbox.created_at)
                FROM ranked
                WHERE mailbox.token_hash = ranked.token_hash
                  AND ranked.rn > 1
            $mailboxes_ts_bool$;
        ELSE
            EXECUTE $mailboxes_ts_int$
                WITH ranked AS (
                    SELECT token_hash,
                           ROW_NUMBER() OVER (
                               PARTITION BY owner_device_id
                               ORDER BY created_at DESC, token_hash DESC
                           ) AS rn
                    FROM __CHAT_SCHEMA__.chat_mailboxes
                    WHERE active = 1
                )
                UPDATE __CHAT_SCHEMA__.chat_mailboxes AS mailbox
                SET active = 0,
                    rotated_at = COALESCE(mailbox.rotated_at, mailbox.created_at)
                FROM ranked
                WHERE mailbox.token_hash = ranked.token_hash
                  AND ranked.rn > 1
            $mailboxes_ts_int$;
        END IF;
    END IF;
END $$;

ALTER TABLE __CHAT_SCHEMA__.chat_mailbox_messages
    ADD COLUMN IF NOT EXISTS sender_hint VARCHAR(64);

ALTER TABLE __CHAT_SCHEMA__.chat_mailbox_messages
    ADD COLUMN IF NOT EXISTS consumed_at TEXT;

ALTER TABLE __CHAT_SCHEMA__.chat_identity_keys
    ADD COLUMN IF NOT EXISTS identity_signing_key_b64 TEXT;

UPDATE __CHAT_SCHEMA__.chat_device_protocol_state
SET protocol_floor = 'v1_legacy'
WHERE protocol_floor IS NULL
   OR TRIM(protocol_floor) = '';

UPDATE __CHAT_SCHEMA__.chat_device_protocol_state
SET supports_v2 = 0
WHERE supports_v2 IS NULL;

UPDATE __CHAT_SCHEMA__.chat_device_protocol_state
SET v2_only = 0
WHERE v2_only IS NULL;

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
        EXECUTE $sql$
            UPDATE __CHAT_SCHEMA__.chat_device_protocol_state
            SET updated_at = NOW()::text
            WHERE updated_at IS NULL
               OR TRIM(updated_at) = ''
        $sql$;
    END IF;
END $$;

ALTER TABLE __CHAT_SCHEMA__.contact_rules
    ADD COLUMN IF NOT EXISTS muted INTEGER DEFAULT 0;

ALTER TABLE __CHAT_SCHEMA__.contact_rules
    ADD COLUMN IF NOT EXISTS starred INTEGER DEFAULT 0;

ALTER TABLE __CHAT_SCHEMA__.contact_rules
    ADD COLUMN IF NOT EXISTS pinned INTEGER DEFAULT 0;

ALTER TABLE __CHAT_SCHEMA__.group_messages
    ADD COLUMN IF NOT EXISTS attachment_b64 TEXT;

ALTER TABLE __CHAT_SCHEMA__.group_messages
    ADD COLUMN IF NOT EXISTS attachment_mime VARCHAR(64);

ALTER TABLE __CHAT_SCHEMA__.group_messages
    ADD COLUMN IF NOT EXISTS voice_secs INTEGER;

ALTER TABLE __CHAT_SCHEMA__.groups
    ADD COLUMN IF NOT EXISTS avatar_b64 TEXT;

ALTER TABLE __CHAT_SCHEMA__.groups
    ADD COLUMN IF NOT EXISTS avatar_mime VARCHAR(64);
