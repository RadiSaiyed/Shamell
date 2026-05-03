DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_off_feed_items_created_after_ts'
          AND conrelid = 'auth_official_feed_items'::regclass
    ) THEN
        ALTER TABLE auth_official_feed_items
            ADD CONSTRAINT chk_auth_off_feed_items_created_after_ts
            CHECK (created_at >= ts) NOT VALID;
    END IF;
END $$;
