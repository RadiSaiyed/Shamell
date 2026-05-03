ALTER TABLE auth_sessions
    ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE auth_sessions
    ADD COLUMN IF NOT EXISTS account_id VARCHAR(64);
ALTER TABLE auth_sessions
    ALTER COLUMN phone DROP NOT NULL;
CREATE INDEX IF NOT EXISTS idx_auth_sessions_expires_at
    ON auth_sessions(expires_at);
CREATE INDEX IF NOT EXISTS idx_auth_sessions_last_seen_at
    ON auth_sessions(last_seen_at);
CREATE INDEX IF NOT EXISTS idx_auth_sessions_account_device_active
    ON auth_sessions(account_id, device_id)
    WHERE revoked_at IS NULL;

ALTER TABLE auth_user_ids
    ADD COLUMN IF NOT EXISTS id BIGSERIAL;
UPDATE auth_user_ids
SET id = DEFAULT
WHERE id IS NULL;
ALTER TABLE auth_user_ids
    ALTER COLUMN id SET NOT NULL;
ALTER TABLE auth_user_ids
    ALTER COLUMN phone SET NOT NULL;

DO $$
DECLARE
    pk_name text;
    pk_cols text[];
BEGIN
    SELECT
        c.conname,
        array_agg(a.attname ORDER BY a.attnum)
    INTO pk_name, pk_cols
    FROM pg_constraint c
    JOIN pg_class t ON c.conrelid = t.oid
    JOIN unnest(c.conkey) AS k(attnum) ON true
    JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum
    WHERE t.relname = 'auth_user_ids' AND c.contype = 'p'
    GROUP BY c.conname
    LIMIT 1;

    IF pk_cols IS NULL THEN
        EXECUTE 'ALTER TABLE auth_user_ids ADD CONSTRAINT auth_user_ids_pkey PRIMARY KEY (id)';
    ELSIF array_length(pk_cols, 1) = 1 AND pk_cols[1] = 'id' THEN
        NULL;
    ELSE
        EXECUTE format('ALTER TABLE auth_user_ids DROP CONSTRAINT %I', pk_name);
        EXECUTE 'ALTER TABLE auth_user_ids ADD CONSTRAINT auth_user_ids_pkey PRIMARY KEY (id)';
    END IF;
END $$;

ALTER TABLE auth_chat_devices
    ADD COLUMN IF NOT EXISTS account_id VARCHAR(64);
ALTER TABLE auth_chat_devices
    ALTER COLUMN phone DROP NOT NULL;
CREATE INDEX IF NOT EXISTS idx_auth_chat_devices_account_active_last_seen
    ON auth_chat_devices(account_id, last_seen_at DESC, id DESC)
    WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_auth_chat_devices_account_client_device_active
    ON auth_chat_devices(account_id, client_device_id)
    WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_auth_chat_devices_phone_active_last_seen
    ON auth_chat_devices(phone, last_seen_at DESC, id DESC)
    WHERE revoked_at IS NULL;

ALTER TABLE auth_contact_invites
    ADD COLUMN IF NOT EXISTS issuer_account_id VARCHAR(64);
ALTER TABLE auth_contact_invites
    ALTER COLUMN issuer_phone DROP NOT NULL;
CREATE INDEX IF NOT EXISTS idx_auth_contact_invites_expires_at
    ON auth_contact_invites(expires_at);

CREATE INDEX IF NOT EXISTS idx_auth_account_create_challenges_gc_at
    ON auth_account_create_challenges(COALESCE(consumed_at, expires_at));


ALTER TABLE auth_biometric_tokens
    ADD COLUMN IF NOT EXISTS account_id VARCHAR(64);
ALTER TABLE auth_biometric_tokens
    ALTER COLUMN phone DROP NOT NULL;
CREATE INDEX IF NOT EXISTS idx_auth_biometric_tokens_expires_at
    ON auth_biometric_tokens(expires_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_auth_biometric_tokens_account_device
    ON auth_biometric_tokens(account_id, device_id);

CREATE INDEX IF NOT EXISTS idx_auth_official_template_messages_unread_order
    ON auth_official_template_messages(account_id, read_at, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_auth_official_template_messages_account_created
    ON auth_official_template_messages(account_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_auth_official_accounts_chat_peer_id
    ON auth_official_accounts(chat_peer_id);
CREATE INDEX IF NOT EXISTS idx_auth_official_accounts_featured_name_id
    ON auth_official_accounts(featured DESC, name ASC, id ASC);

CREATE INDEX IF NOT EXISTS idx_auth_official_follows_official_id
    ON auth_official_follows(official_id);

CREATE INDEX IF NOT EXISTS idx_auth_official_feed_items_account_ts_id
    ON auth_official_feed_items(account_id, ts DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_auth_official_feed_items_ts_id
    ON auth_official_feed_items(ts DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_auth_official_auto_replies_account_id_order
    ON auth_official_auto_replies(account_id, id ASC);
CREATE INDEX IF NOT EXISTS idx_auth_official_auto_replies_public_welcome
    ON auth_official_auto_replies(account_id, id ASC)
    WHERE enabled = TRUE AND lower(kind) = 'welcome';

ALTER TABLE auth_official_service_sessions
    ADD COLUMN IF NOT EXISTS customer_account_id VARCHAR(64);
ALTER TABLE auth_official_service_sessions
    ADD COLUMN IF NOT EXISTS customer_phone VARCHAR(32);
ALTER TABLE auth_official_service_sessions
    ADD COLUMN IF NOT EXISTS chat_peer_id VARCHAR(128);
ALTER TABLE auth_official_service_sessions
    ADD COLUMN IF NOT EXISTS status VARCHAR(16) NOT NULL DEFAULT 'open';
ALTER TABLE auth_official_service_sessions
    ADD COLUMN IF NOT EXISTS last_message_ts TIMESTAMPTZ;
ALTER TABLE auth_official_service_sessions
    ADD COLUMN IF NOT EXISTS last_message_preview TEXT;
ALTER TABLE auth_official_service_sessions
    ADD COLUMN IF NOT EXISTS unread_by_operator BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE auth_official_service_sessions
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
CREATE INDEX IF NOT EXISTS idx_auth_official_service_sessions_inbox_sort
    ON auth_official_service_sessions(account_id, COALESCE(last_message_ts, created_at) DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_auth_rate_limits_updated_at
    ON auth_rate_limits(updated_at);

ALTER TABLE device_login_challenges
    ADD COLUMN IF NOT EXISTS account_id VARCHAR(64);
CREATE INDEX IF NOT EXISTS idx_device_login_challenges_expires_at
    ON device_login_challenges(expires_at);

ALTER TABLE device_sessions
    ADD COLUMN IF NOT EXISTS account_id VARCHAR(64);
ALTER TABLE device_sessions
    ALTER COLUMN phone DROP NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_device_sessions_account_device
    ON device_sessions(account_id, device_id);
CREATE INDEX IF NOT EXISTS idx_device_sessions_account_last_seen
    ON device_sessions(account_id, last_seen_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_device_sessions_last_seen_at
    ON device_sessions(last_seen_at);

UPDATE auth_sessions child_row
SET account_id = NULL
WHERE child_row.account_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM auth_accounts parent_row
      WHERE parent_row.account_id = child_row.account_id
  );

UPDATE auth_chat_devices child_row
SET account_id = NULL
WHERE child_row.account_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM auth_accounts parent_row
      WHERE parent_row.account_id = child_row.account_id
  );

UPDATE auth_contact_invites child_row
SET issuer_account_id = NULL
WHERE child_row.issuer_account_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM auth_accounts parent_row
      WHERE parent_row.account_id = child_row.issuer_account_id
  );

UPDATE auth_biometric_tokens child_row
SET account_id = NULL
WHERE child_row.account_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM auth_accounts parent_row
      WHERE parent_row.account_id = child_row.account_id
  );

UPDATE device_login_challenges child_row
SET account_id = NULL
WHERE child_row.account_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM auth_accounts parent_row
      WHERE parent_row.account_id = child_row.account_id
  );

UPDATE device_sessions child_row
SET account_id = NULL
WHERE child_row.account_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM auth_accounts parent_row
      WHERE parent_row.account_id = child_row.account_id
  );

UPDATE auth_official_service_sessions child_row
SET customer_account_id = NULL
WHERE child_row.customer_account_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM auth_accounts parent_row
      WHERE parent_row.account_id = child_row.customer_account_id
  );

DELETE FROM auth_contact_invites child_row
WHERE child_row.issuer_chat_device_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM auth_chat_devices parent_row
      WHERE parent_row.chat_device_id = child_row.issuer_chat_device_id
  );

DELETE FROM auth_chat_contacts child_row
WHERE NOT EXISTS (
          SELECT 1
          FROM auth_accounts parent_row
          WHERE parent_row.account_id = child_row.owner_account_id
      )
   OR NOT EXISTS (
          SELECT 1
          FROM auth_chat_devices parent_row
          WHERE parent_row.chat_device_id = child_row.peer_chat_device_id
      );

DELETE FROM auth_official_template_messages child_row
WHERE NOT EXISTS (
          SELECT 1
          FROM auth_accounts parent_row
          WHERE parent_row.account_id = child_row.account_id
      );

DELETE FROM auth_official_follows child_row
WHERE NOT EXISTS (
          SELECT 1
          FROM auth_accounts account_row
          WHERE account_row.account_id = child_row.account_id
      )
   OR NOT EXISTS (
          SELECT 1
          FROM auth_official_accounts official_row
          WHERE official_row.id = child_row.official_id
      );

DELETE FROM auth_official_feed_items child_row
WHERE NOT EXISTS (
          SELECT 1
          FROM auth_official_accounts parent_row
          WHERE parent_row.id = child_row.account_id
      );

DELETE FROM auth_official_auto_replies child_row
WHERE NOT EXISTS (
          SELECT 1
          FROM auth_official_accounts parent_row
          WHERE parent_row.id = child_row.account_id
      );

DELETE FROM auth_official_notification_modes child_row
WHERE NOT EXISTS (
          SELECT 1
          FROM auth_accounts account_row
          WHERE account_row.account_id = child_row.account_id
      )
   OR NOT EXISTS (
          SELECT 1
          FROM auth_official_accounts official_row
          WHERE official_row.id = child_row.official_id
      );

DELETE FROM auth_official_service_sessions child_row
WHERE NOT EXISTS (
          SELECT 1
          FROM auth_official_accounts official_row
          WHERE official_row.id = child_row.account_id
      );

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM auth_sessions child_row
        WHERE child_row.account_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM auth_accounts parent_row
              WHERE parent_row.account_id = child_row.account_id
          )
    ) THEN
        RAISE EXCEPTION 'orphaned auth references block migration: auth_sessions.account_id -> auth_accounts.account_id';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_auth_sessions_account_id'
          AND conrelid = 'auth_sessions'::regclass
    ) THEN
        ALTER TABLE auth_sessions
            ADD CONSTRAINT fk_auth_sessions_account_id
            FOREIGN KEY (account_id) REFERENCES auth_accounts(account_id) ON DELETE SET NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM auth_chat_devices child_row
        WHERE child_row.account_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM auth_accounts parent_row
              WHERE parent_row.account_id = child_row.account_id
          )
    ) THEN
        RAISE EXCEPTION 'orphaned auth references block migration: auth_chat_devices.account_id -> auth_accounts.account_id';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_auth_chat_devices_account_id'
          AND conrelid = 'auth_chat_devices'::regclass
    ) THEN
        ALTER TABLE auth_chat_devices
            ADD CONSTRAINT fk_auth_chat_devices_account_id
            FOREIGN KEY (account_id) REFERENCES auth_accounts(account_id) ON DELETE SET NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM auth_contact_invites child_row
        WHERE child_row.issuer_account_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM auth_accounts parent_row
              WHERE parent_row.account_id = child_row.issuer_account_id
          )
    ) THEN
        RAISE EXCEPTION 'orphaned auth references block migration: auth_contact_invites.issuer_account_id -> auth_accounts.account_id';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_auth_contact_invites_issuer_account_id'
          AND conrelid = 'auth_contact_invites'::regclass
    ) THEN
        ALTER TABLE auth_contact_invites
            ADD CONSTRAINT fk_auth_contact_invites_issuer_account_id
            FOREIGN KEY (issuer_account_id) REFERENCES auth_accounts(account_id) ON DELETE SET NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM auth_contact_invites child_row
        WHERE child_row.issuer_chat_device_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM auth_chat_devices parent_row
              WHERE parent_row.chat_device_id = child_row.issuer_chat_device_id
          )
    ) THEN
        RAISE EXCEPTION 'orphaned auth references block migration: auth_contact_invites.issuer_chat_device_id -> auth_chat_devices.chat_device_id';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_auth_contact_invites_issuer_chat_device_id'
          AND conrelid = 'auth_contact_invites'::regclass
    ) THEN
        ALTER TABLE auth_contact_invites
            ADD CONSTRAINT fk_auth_contact_invites_issuer_chat_device_id
            FOREIGN KEY (issuer_chat_device_id) REFERENCES auth_chat_devices(chat_device_id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM auth_chat_contacts child_row
        WHERE child_row.owner_account_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM auth_accounts parent_row
              WHERE parent_row.account_id = child_row.owner_account_id
          )
    ) THEN
        RAISE EXCEPTION 'orphaned auth references block migration: auth_chat_contacts.owner_account_id -> auth_accounts.account_id';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_auth_chat_contacts_owner_account_id'
          AND conrelid = 'auth_chat_contacts'::regclass
    ) THEN
        ALTER TABLE auth_chat_contacts
            ADD CONSTRAINT fk_auth_chat_contacts_owner_account_id
            FOREIGN KEY (owner_account_id) REFERENCES auth_accounts(account_id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM auth_chat_contacts child_row
        WHERE child_row.peer_chat_device_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM auth_chat_devices parent_row
              WHERE parent_row.chat_device_id = child_row.peer_chat_device_id
          )
    ) THEN
        RAISE EXCEPTION 'orphaned auth references block migration: auth_chat_contacts.peer_chat_device_id -> auth_chat_devices.chat_device_id';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_auth_chat_contacts_peer_chat_device_id'
          AND conrelid = 'auth_chat_contacts'::regclass
    ) THEN
        ALTER TABLE auth_chat_contacts
            ADD CONSTRAINT fk_auth_chat_contacts_peer_chat_device_id
            FOREIGN KEY (peer_chat_device_id) REFERENCES auth_chat_devices(chat_device_id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM auth_biometric_tokens child_row
        WHERE child_row.account_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM auth_accounts parent_row
              WHERE parent_row.account_id = child_row.account_id
          )
    ) THEN
        RAISE EXCEPTION 'orphaned auth references block migration: auth_biometric_tokens.account_id -> auth_accounts.account_id';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_auth_biometric_tokens_account_id'
          AND conrelid = 'auth_biometric_tokens'::regclass
    ) THEN
        ALTER TABLE auth_biometric_tokens
            ADD CONSTRAINT fk_auth_biometric_tokens_account_id
            FOREIGN KEY (account_id) REFERENCES auth_accounts(account_id) ON DELETE SET NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM device_login_challenges child_row
        WHERE child_row.account_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM auth_accounts parent_row
              WHERE parent_row.account_id = child_row.account_id
          )
    ) THEN
        RAISE EXCEPTION 'orphaned auth references block migration: device_login_challenges.account_id -> auth_accounts.account_id';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_device_login_challenges_account_id'
          AND conrelid = 'device_login_challenges'::regclass
    ) THEN
        ALTER TABLE device_login_challenges
            ADD CONSTRAINT fk_device_login_challenges_account_id
            FOREIGN KEY (account_id) REFERENCES auth_accounts(account_id) ON DELETE SET NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM device_sessions child_row
        WHERE child_row.account_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM auth_accounts parent_row
              WHERE parent_row.account_id = child_row.account_id
          )
    ) THEN
        RAISE EXCEPTION 'orphaned auth references block migration: device_sessions.account_id -> auth_accounts.account_id';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_device_sessions_account_id'
          AND conrelid = 'device_sessions'::regclass
    ) THEN
        ALTER TABLE device_sessions
            ADD CONSTRAINT fk_device_sessions_account_id
            FOREIGN KEY (account_id) REFERENCES auth_accounts(account_id) ON DELETE SET NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM auth_official_template_messages child_row
        WHERE child_row.account_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM auth_accounts parent_row
              WHERE parent_row.account_id = child_row.account_id
          )
    ) THEN
        RAISE EXCEPTION 'orphaned auth references block migration: auth_official_template_messages.account_id -> auth_accounts.account_id';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_auth_official_template_messages_account_id'
          AND conrelid = 'auth_official_template_messages'::regclass
    ) THEN
        ALTER TABLE auth_official_template_messages
            ADD CONSTRAINT fk_auth_official_template_messages_account_id
            FOREIGN KEY (account_id) REFERENCES auth_accounts(account_id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM auth_official_follows child_row
        WHERE child_row.account_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM auth_accounts parent_row
              WHERE parent_row.account_id = child_row.account_id
          )
    ) THEN
        RAISE EXCEPTION 'orphaned auth references block migration: auth_official_follows.account_id -> auth_accounts.account_id';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_auth_official_follows_account_id'
          AND conrelid = 'auth_official_follows'::regclass
    ) THEN
        ALTER TABLE auth_official_follows
            ADD CONSTRAINT fk_auth_official_follows_account_id
            FOREIGN KEY (account_id) REFERENCES auth_accounts(account_id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM auth_official_follows child_row
        WHERE child_row.official_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM auth_official_accounts parent_row
              WHERE parent_row.id = child_row.official_id
          )
    ) THEN
        RAISE EXCEPTION 'orphaned auth references block migration: auth_official_follows.official_id -> auth_official_accounts.id';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_auth_official_follows_official_id'
          AND conrelid = 'auth_official_follows'::regclass
    ) THEN
        ALTER TABLE auth_official_follows
            ADD CONSTRAINT fk_auth_official_follows_official_id
            FOREIGN KEY (official_id) REFERENCES auth_official_accounts(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM auth_official_feed_items child_row
        WHERE child_row.account_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM auth_official_accounts parent_row
              WHERE parent_row.id = child_row.account_id
          )
    ) THEN
        RAISE EXCEPTION 'orphaned auth references block migration: auth_official_feed_items.account_id -> auth_official_accounts.id';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_auth_official_feed_items_account_id'
          AND conrelid = 'auth_official_feed_items'::regclass
    ) THEN
        ALTER TABLE auth_official_feed_items
            ADD CONSTRAINT fk_auth_official_feed_items_account_id
            FOREIGN KEY (account_id) REFERENCES auth_official_accounts(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM auth_official_auto_replies child_row
        WHERE child_row.account_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM auth_official_accounts parent_row
              WHERE parent_row.id = child_row.account_id
          )
    ) THEN
        RAISE EXCEPTION 'orphaned auth references block migration: auth_official_auto_replies.account_id -> auth_official_accounts.id';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_auth_official_auto_replies_account_id'
          AND conrelid = 'auth_official_auto_replies'::regclass
    ) THEN
        ALTER TABLE auth_official_auto_replies
            ADD CONSTRAINT fk_auth_official_auto_replies_account_id
            FOREIGN KEY (account_id) REFERENCES auth_official_accounts(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM auth_official_notification_modes child_row
        WHERE child_row.account_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM auth_accounts parent_row
              WHERE parent_row.account_id = child_row.account_id
          )
    ) THEN
        RAISE EXCEPTION 'orphaned auth references block migration: auth_official_notification_modes.account_id -> auth_accounts.account_id';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_auth_official_notification_modes_account_id'
          AND conrelid = 'auth_official_notification_modes'::regclass
    ) THEN
        ALTER TABLE auth_official_notification_modes
            ADD CONSTRAINT fk_auth_official_notification_modes_account_id
            FOREIGN KEY (account_id) REFERENCES auth_accounts(account_id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM auth_official_notification_modes child_row
        WHERE child_row.official_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM auth_official_accounts parent_row
              WHERE parent_row.id = child_row.official_id
          )
    ) THEN
        RAISE EXCEPTION 'orphaned auth references block migration: auth_official_notification_modes.official_id -> auth_official_accounts.id';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_auth_official_notification_modes_official_id'
          AND conrelid = 'auth_official_notification_modes'::regclass
    ) THEN
        ALTER TABLE auth_official_notification_modes
            ADD CONSTRAINT fk_auth_official_notification_modes_official_id
            FOREIGN KEY (official_id) REFERENCES auth_official_accounts(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM auth_official_service_sessions child_row
        WHERE child_row.account_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM auth_official_accounts parent_row
              WHERE parent_row.id = child_row.account_id
          )
    ) THEN
        RAISE EXCEPTION 'orphaned auth references block migration: auth_official_service_sessions.account_id -> auth_official_accounts.id';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_auth_official_service_sessions_account_id'
          AND conrelid = 'auth_official_service_sessions'::regclass
    ) THEN
        ALTER TABLE auth_official_service_sessions
            ADD CONSTRAINT fk_auth_official_service_sessions_account_id
            FOREIGN KEY (account_id) REFERENCES auth_official_accounts(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM auth_official_service_sessions child_row
        WHERE child_row.customer_account_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM auth_accounts parent_row
              WHERE parent_row.account_id = child_row.customer_account_id
          )
    ) THEN
        RAISE EXCEPTION 'orphaned auth references block migration: auth_official_service_sessions.customer_account_id -> auth_accounts.account_id';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_auth_official_service_sessions_customer_account_id'
          AND conrelid = 'auth_official_service_sessions'::regclass
    ) THEN
        ALTER TABLE auth_official_service_sessions
            ADD CONSTRAINT fk_auth_official_service_sessions_customer_account_id
            FOREIGN KEY (customer_account_id) REFERENCES auth_accounts(account_id) ON DELETE SET NULL;
    END IF;
END $$;
