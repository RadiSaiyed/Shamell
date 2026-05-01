DELETE FROM __CHAT_SCHEMA__.push_tokens stale
USING (
    SELECT token
    FROM (
        SELECT token,
               ROW_NUMBER() OVER (
                   PARTITION BY device_id
                   ORDER BY last_seen_at DESC, created_at DESC, token DESC
               ) AS row_rank
        FROM __CHAT_SCHEMA__.push_tokens
    ) ranked
    WHERE row_rank > 1
) duplicate_rows
WHERE stale.token = duplicate_rows.token;

DROP INDEX IF EXISTS __CHAT_SCHEMA__.idx_push_tokens_device;

CREATE UNIQUE INDEX IF NOT EXISTS uq_push_tokens_device_id
    ON __CHAT_SCHEMA__.push_tokens(device_id);
