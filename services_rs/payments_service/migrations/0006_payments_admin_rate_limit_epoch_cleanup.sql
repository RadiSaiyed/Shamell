ALTER TABLE __PAYMENTS_SCHEMA__.admin_rate_limits
    DROP CONSTRAINT IF EXISTS chk_admin_rate_limits_window_start_epoch_non_negative;

ALTER TABLE __PAYMENTS_SCHEMA__.admin_rate_limits
    DROP COLUMN IF EXISTS window_start_epoch;
