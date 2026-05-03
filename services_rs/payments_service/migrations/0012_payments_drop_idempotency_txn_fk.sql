ALTER TABLE __PAYMENTS_SCHEMA__.idempotency
    DROP CONSTRAINT IF EXISTS fk_idempotency_txn_id;
