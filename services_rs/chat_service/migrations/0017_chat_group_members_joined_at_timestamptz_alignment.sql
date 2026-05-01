ALTER TABLE __CHAT_SCHEMA__.group_members
    DROP CONSTRAINT IF EXISTS chk_group_members_joined_at_text_timestamp;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__CHAT_SCHEMA__'
          AND table_name = 'group_members'
          AND column_name = 'joined_at'
          AND data_type = 'text'
    ) THEN
        UPDATE __CHAT_SCHEMA__.group_members
        SET joined_at = to_char((NOW() AT TIME ZONE 'UTC'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
        WHERE joined_at IS NULL OR BTRIM(joined_at) = '';

        ALTER TABLE __CHAT_SCHEMA__.group_members
            ALTER COLUMN joined_at TYPE TIMESTAMPTZ
            USING NULLIF(BTRIM(joined_at), '')::timestamptz;
    END IF;
END $$;

ALTER TABLE __CHAT_SCHEMA__.group_members
    ALTER COLUMN joined_at SET DEFAULT NOW();

ALTER TABLE __CHAT_SCHEMA__.group_members
    ALTER COLUMN joined_at SET NOT NULL;
