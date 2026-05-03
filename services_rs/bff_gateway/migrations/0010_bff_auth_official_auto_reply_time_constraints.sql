DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_off_auto_replies_updated_after_created'
          AND conrelid = 'auth_official_auto_replies'::regclass
    ) THEN
        ALTER TABLE auth_official_auto_replies
            ADD CONSTRAINT chk_auth_off_auto_replies_updated_after_created
            CHECK (updated_at >= created_at) NOT VALID;
    END IF;
END $$;
