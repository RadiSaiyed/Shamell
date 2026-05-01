ALTER TABLE auth_rate_limits
    DROP CONSTRAINT IF EXISTS chk_auth_rate_limits_updated_at_after_window_start;

ALTER TABLE auth_rate_limits
    DROP CONSTRAINT IF EXISTS chk_auth_rate_limits_window_start_epoch_non_negative;

ALTER TABLE auth_rate_limits
    DROP COLUMN IF EXISTS window_start_epoch;
