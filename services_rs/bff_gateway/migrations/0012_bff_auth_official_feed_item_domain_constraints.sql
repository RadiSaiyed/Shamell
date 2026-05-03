DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_off_feed_items_item_id_format'
          AND conrelid = 'auth_official_feed_items'::regclass
    ) THEN
        ALTER TABLE auth_official_feed_items
            ADD CONSTRAINT chk_auth_off_feed_items_item_id_format
            CHECK (item_id ~ '^[a-z0-9._-]+$') NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_off_feed_items_title_not_blank'
          AND conrelid = 'auth_official_feed_items'::regclass
    ) THEN
        ALTER TABLE auth_official_feed_items
            ADD CONSTRAINT chk_auth_off_feed_items_title_not_blank
            CHECK (char_length(btrim(title)) > 0) NOT VALID;
    END IF;
END $$;
