ALTER TABLE __PAYMENTS_SCHEMA__.txns
    DROP CONSTRAINT IF EXISTS chk_txns_kind_wallet_shape;

ALTER TABLE __PAYMENTS_SCHEMA__.txns
    ADD CONSTRAINT chk_txns_kind_wallet_shape CHECK (
        (kind = 'topup' AND from_wallet_id IS NULL)
        OR (
            kind = ANY (ARRAY['transfer', 'refund'])
            AND from_wallet_id IS NOT NULL
            AND from_wallet_id <> to_wallet_id
        )
        OR (
            kind = ANY (ARRAY['exchange_debit', 'exchange_credit'])
            AND from_wallet_id IS NOT NULL
            AND from_wallet_id = to_wallet_id
        )
    ) NOT VALID;
