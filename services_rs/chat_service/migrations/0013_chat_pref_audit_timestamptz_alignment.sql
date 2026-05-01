ALTER TABLE __CHAT_SCHEMA__.contact_rules
    DROP CONSTRAINT IF EXISTS chk_contact_rules_created_at_text_timestamp;

ALTER TABLE __CHAT_SCHEMA__.contact_rules
    DROP CONSTRAINT IF EXISTS chk_contact_rules_updated_at_text_timestamp;

ALTER TABLE __CHAT_SCHEMA__.group_prefs
    DROP CONSTRAINT IF EXISTS chk_group_prefs_created_at_text_timestamp;

ALTER TABLE __CHAT_SCHEMA__.group_prefs
    DROP CONSTRAINT IF EXISTS chk_group_prefs_updated_at_text_timestamp;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'contact_rules'
          AND column_name = 'created_at'
          AND data_type = 'text'
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.contact_rules
            ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at::timestamptz;
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
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.contact_rules
            ALTER COLUMN updated_at TYPE TIMESTAMPTZ USING updated_at::timestamptz;
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
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.group_prefs
            ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at::timestamptz;
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
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.group_prefs
            ALTER COLUMN updated_at TYPE TIMESTAMPTZ USING updated_at::timestamptz;
    END IF;
END $$;

ALTER TABLE __CHAT_SCHEMA__.contact_rules
    ALTER COLUMN created_at SET DEFAULT NOW();

ALTER TABLE __CHAT_SCHEMA__.contact_rules
    ALTER COLUMN updated_at SET DEFAULT NOW();

ALTER TABLE __CHAT_SCHEMA__.group_prefs
    ALTER COLUMN created_at SET DEFAULT NOW();

ALTER TABLE __CHAT_SCHEMA__.group_prefs
    ALTER COLUMN updated_at SET DEFAULT NOW();

ALTER TABLE __CHAT_SCHEMA__.contact_rules
    ALTER COLUMN created_at SET NOT NULL;

ALTER TABLE __CHAT_SCHEMA__.contact_rules
    ALTER COLUMN updated_at SET NOT NULL;

ALTER TABLE __CHAT_SCHEMA__.group_prefs
    ALTER COLUMN created_at SET NOT NULL;

ALTER TABLE __CHAT_SCHEMA__.group_prefs
    ALTER COLUMN updated_at SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_contact_rules_updated_at_after_created_at'
          AND conrelid = '__CHAT_SCHEMA__.contact_rules'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.contact_rules
            ADD CONSTRAINT chk_contact_rules_updated_at_after_created_at
            CHECK (updated_at >= created_at) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_group_prefs_updated_at_after_created_at'
          AND conrelid = '__CHAT_SCHEMA__.group_prefs'::regclass
    ) THEN
        ALTER TABLE __CHAT_SCHEMA__.group_prefs
            ADD CONSTRAINT chk_group_prefs_updated_at_after_created_at
            CHECK (updated_at >= created_at) NOT VALID;
    END IF;
END $$;
