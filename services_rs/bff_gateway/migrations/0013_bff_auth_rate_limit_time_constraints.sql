DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_rate_limits_updated_at_after_window_start'
          AND conrelid = 'auth_rate_limits'::regclass
    )
    AND EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = ANY(current_schemas(false))
          AND table_name = 'auth_rate_limits'
          AND column_name = 'window_start_epoch'
    ) THEN
        ALTER TABLE auth_rate_limits
            ADD CONSTRAINT chk_auth_rate_limits_updated_at_after_window_start
            CHECK (EXTRACT(EPOCH FROM updated_at) >= window_start_epoch::double precision) NOT VALID;
    END IF;
END $$;
