ALTER TABLE auth_rate_limits
    ADD COLUMN IF NOT EXISTS window_start_at TIMESTAMPTZ;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = ANY(current_schemas(false))
          AND table_name = 'auth_rate_limits'
          AND column_name = 'window_start_epoch'
    ) THEN
        EXECUTE $sql$
            UPDATE auth_rate_limits
            SET window_start_at = TO_TIMESTAMP(window_start_epoch::double precision)
            WHERE window_start_at IS NULL
        $sql$;
    END IF;
END $$;

ALTER TABLE auth_rate_limits
    ALTER COLUMN window_start_at SET DEFAULT NOW();

ALTER TABLE auth_rate_limits
    ALTER COLUMN window_start_at SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_rate_limits_updated_at_after_window_start_at'
          AND conrelid = 'auth_rate_limits'::regclass
    ) THEN
        ALTER TABLE auth_rate_limits
            ADD CONSTRAINT chk_auth_rate_limits_updated_at_after_window_start_at
            CHECK (updated_at >= window_start_at) NOT VALID;
    END IF;
END $$;
