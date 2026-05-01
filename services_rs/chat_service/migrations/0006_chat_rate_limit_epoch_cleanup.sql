DROP INDEX IF EXISTS __CHAT_SCHEMA__.idx_chat_rate_limits_updated_epoch;

ALTER TABLE __CHAT_SCHEMA__.chat_rate_limits
    DROP CONSTRAINT IF EXISTS chk_chat_rate_limits_window_start_epoch_non_negative;

ALTER TABLE __CHAT_SCHEMA__.chat_rate_limits
    DROP CONSTRAINT IF EXISTS chk_chat_rate_limits_updated_at_epoch_non_negative;

ALTER TABLE __CHAT_SCHEMA__.chat_rate_limits
    DROP COLUMN IF EXISTS window_start_epoch;

ALTER TABLE __CHAT_SCHEMA__.chat_rate_limits
    DROP COLUMN IF EXISTS updated_at_epoch;
