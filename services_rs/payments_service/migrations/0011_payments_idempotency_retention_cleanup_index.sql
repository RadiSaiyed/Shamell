CREATE INDEX IF NOT EXISTS idx_idempotency_created_at
    ON __PAYMENTS_SCHEMA__.idempotency(created_at);
