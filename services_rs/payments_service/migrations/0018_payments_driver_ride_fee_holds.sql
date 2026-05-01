CREATE TABLE IF NOT EXISTS __PAYMENTS_SCHEMA__.driver_ride_fee_holds (
    ride_id VARCHAR(64) PRIMARY KEY,
    wallet_id VARCHAR(36) NOT NULL,
    amount_cents BIGINT NOT NULL,
    status VARCHAR(16) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    reserved_at TIMESTAMPTZ NOT NULL,
    settled_at TIMESTAMPTZ,
    released_at TIMESTAMPTZ,
    CONSTRAINT fk_driver_ride_fee_holds_wallet_id
        FOREIGN KEY (wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE,
    CONSTRAINT chk_driver_ride_fee_holds_amount_positive
        CHECK (amount_cents > 0),
    CONSTRAINT chk_driver_ride_fee_holds_status_known
        CHECK (status = ANY (ARRAY['reserved', 'settled', 'released'])),
    CONSTRAINT chk_driver_ride_fee_holds_updated_at_after_created_at
        CHECK (updated_at >= created_at)
);

CREATE INDEX IF NOT EXISTS idx_driver_ride_fee_holds_wallet_status_updated_at
    ON __PAYMENTS_SCHEMA__.driver_ride_fee_holds(wallet_id, status, updated_at DESC);
