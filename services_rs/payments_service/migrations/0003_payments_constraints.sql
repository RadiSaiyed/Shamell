DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_users_kyc_level_non_negative'
          AND conrelid = '__PAYMENTS_SCHEMA__.users'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.users
            ADD CONSTRAINT chk_users_kyc_level_non_negative
            CHECK (kyc_level >= 0) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_wallets_user_id'
          AND conrelid = '__PAYMENTS_SCHEMA__.wallets'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __PAYMENTS_SCHEMA__.wallets child_row
            WHERE child_row.user_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __PAYMENTS_SCHEMA__.users parent_row
                    WHERE parent_row.id = child_row.user_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned payments references block ensure_schema: wallets.user_id -> users.id';
        END IF;
        ALTER TABLE __PAYMENTS_SCHEMA__.wallets
            ADD CONSTRAINT fk_wallets_user_id
            FOREIGN KEY (user_id) REFERENCES __PAYMENTS_SCHEMA__.users(id) ON DELETE RESTRICT;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_idempotency_amount_cents_positive'
          AND conrelid = '__PAYMENTS_SCHEMA__.idempotency'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.idempotency
            ADD CONSTRAINT chk_idempotency_amount_cents_positive
            CHECK (amount_cents IS NULL OR amount_cents > 0) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_idempotency_balance_cents_non_negative'
          AND conrelid = '__PAYMENTS_SCHEMA__.idempotency'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.idempotency
            ADD CONSTRAINT chk_idempotency_balance_cents_non_negative
            CHECK (balance_cents IS NULL OR balance_cents >= 0) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_wallets_balance_cents_non_negative'
          AND conrelid = '__PAYMENTS_SCHEMA__.wallets'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.wallets
            ADD CONSTRAINT chk_wallets_balance_cents_non_negative
            CHECK (balance_cents >= 0) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_txns_from_wallet_id'
          AND conrelid = '__PAYMENTS_SCHEMA__.txns'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __PAYMENTS_SCHEMA__.txns child_row
            WHERE child_row.from_wallet_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __PAYMENTS_SCHEMA__.wallets parent_row
                    WHERE parent_row.id = child_row.from_wallet_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned payments references block ensure_schema: txns.from_wallet_id -> wallets.id';
        END IF;
        ALTER TABLE __PAYMENTS_SCHEMA__.txns
            ADD CONSTRAINT fk_txns_from_wallet_id
            FOREIGN KEY (from_wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE RESTRICT;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_txns_to_wallet_id'
          AND conrelid = '__PAYMENTS_SCHEMA__.txns'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __PAYMENTS_SCHEMA__.txns child_row
            WHERE child_row.to_wallet_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __PAYMENTS_SCHEMA__.wallets parent_row
                    WHERE parent_row.id = child_row.to_wallet_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned payments references block ensure_schema: txns.to_wallet_id -> wallets.id';
        END IF;
        ALTER TABLE __PAYMENTS_SCHEMA__.txns
            ADD CONSTRAINT fk_txns_to_wallet_id
            FOREIGN KEY (to_wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE RESTRICT;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_txns_amount_cents_positive'
          AND conrelid = '__PAYMENTS_SCHEMA__.txns'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.txns
            ADD CONSTRAINT chk_txns_amount_cents_positive
            CHECK (amount_cents > 0) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_txns_fee_cents_non_negative'
          AND conrelid = '__PAYMENTS_SCHEMA__.txns'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.txns
            ADD CONSTRAINT chk_txns_fee_cents_non_negative
            CHECK (fee_cents >= 0) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_txns_kind_known'
          AND conrelid = '__PAYMENTS_SCHEMA__.txns'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.txns
            ADD CONSTRAINT chk_txns_kind_known
            CHECK (kind = ANY (ARRAY['topup','transfer'])) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_ledger_entries_wallet_id'
          AND conrelid = '__PAYMENTS_SCHEMA__.ledger_entries'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __PAYMENTS_SCHEMA__.ledger_entries child_row
            WHERE child_row.wallet_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __PAYMENTS_SCHEMA__.wallets parent_row
                    WHERE parent_row.id = child_row.wallet_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned payments references block ensure_schema: ledger_entries.wallet_id -> wallets.id';
        END IF;
        ALTER TABLE __PAYMENTS_SCHEMA__.ledger_entries
            ADD CONSTRAINT fk_ledger_entries_wallet_id
            FOREIGN KEY (wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE RESTRICT;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_ledger_entries_txn_id'
          AND conrelid = '__PAYMENTS_SCHEMA__.ledger_entries'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __PAYMENTS_SCHEMA__.ledger_entries child_row
            WHERE child_row.txn_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __PAYMENTS_SCHEMA__.txns parent_row
                    WHERE parent_row.id = child_row.txn_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned payments references block ensure_schema: ledger_entries.txn_id -> txns.id';
        END IF;
        ALTER TABLE __PAYMENTS_SCHEMA__.ledger_entries
            ADD CONSTRAINT fk_ledger_entries_txn_id
            FOREIGN KEY (txn_id) REFERENCES __PAYMENTS_SCHEMA__.txns(id) ON DELETE RESTRICT;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_payment_requests_amount_cents_positive'
          AND conrelid = '__PAYMENTS_SCHEMA__.payment_requests'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.payment_requests
            ADD CONSTRAINT chk_payment_requests_amount_cents_positive
            CHECK (amount_cents > 0) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_payment_requests_status_known'
          AND conrelid = '__PAYMENTS_SCHEMA__.payment_requests'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.payment_requests
            ADD CONSTRAINT chk_payment_requests_status_known
            CHECK (status = ANY (ARRAY['pending','accepted','canceled','expired'])) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_idempotency_wallet_id'
          AND conrelid = '__PAYMENTS_SCHEMA__.idempotency'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __PAYMENTS_SCHEMA__.idempotency child_row
            WHERE child_row.wallet_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __PAYMENTS_SCHEMA__.wallets parent_row
                    WHERE parent_row.id = child_row.wallet_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned payments references block ensure_schema: idempotency.wallet_id -> wallets.id';
        END IF;
        ALTER TABLE __PAYMENTS_SCHEMA__.idempotency
            ADD CONSTRAINT fk_idempotency_wallet_id
            FOREIGN KEY (wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE RESTRICT;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_idempotency_txn_id'
          AND conrelid = '__PAYMENTS_SCHEMA__.idempotency'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __PAYMENTS_SCHEMA__.idempotency child_row
            WHERE child_row.txn_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __PAYMENTS_SCHEMA__.txns parent_row
                    WHERE parent_row.id = child_row.txn_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned payments references block ensure_schema: idempotency.txn_id -> txns.id';
        END IF;
        ALTER TABLE __PAYMENTS_SCHEMA__.idempotency
            ADD CONSTRAINT fk_idempotency_txn_id
            FOREIGN KEY (txn_id) REFERENCES __PAYMENTS_SCHEMA__.txns(id) ON DELETE RESTRICT;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_aliases_user_id'
          AND conrelid = '__PAYMENTS_SCHEMA__.aliases'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.aliases
            ADD CONSTRAINT fk_aliases_user_id
            FOREIGN KEY (user_id) REFERENCES __PAYMENTS_SCHEMA__.users(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_aliases_wallet_id'
          AND conrelid = '__PAYMENTS_SCHEMA__.aliases'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.aliases
            ADD CONSTRAINT fk_aliases_wallet_id
            FOREIGN KEY (wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_favorites_owner_wallet_id'
          AND conrelid = '__PAYMENTS_SCHEMA__.favorites'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.favorites
            ADD CONSTRAINT fk_favorites_owner_wallet_id
            FOREIGN KEY (owner_wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_favorites_favorite_wallet_id'
          AND conrelid = '__PAYMENTS_SCHEMA__.favorites'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.favorites
            ADD CONSTRAINT fk_favorites_favorite_wallet_id
            FOREIGN KEY (favorite_wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_favorites_owner_not_self'
          AND conrelid = '__PAYMENTS_SCHEMA__.favorites'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.favorites
            ADD CONSTRAINT chk_favorites_owner_not_self
            CHECK (owner_wallet_id <> favorite_wallet_id) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_payment_requests_from_wallet_id'
          AND conrelid = '__PAYMENTS_SCHEMA__.payment_requests'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.payment_requests
            ADD CONSTRAINT fk_payment_requests_from_wallet_id
            FOREIGN KEY (from_wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_payment_requests_to_wallet_id'
          AND conrelid = '__PAYMENTS_SCHEMA__.payment_requests'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.payment_requests
            ADD CONSTRAINT fk_payment_requests_to_wallet_id
            FOREIGN KEY (to_wallet_id) REFERENCES __PAYMENTS_SCHEMA__.wallets(id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_roles_role_known'
          AND conrelid = '__PAYMENTS_SCHEMA__.roles'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.roles
            ADD CONSTRAINT chk_roles_role_known
            CHECK (
                role = ANY (ARRAY['merchant','qr_seller','cashout_operator','admin','superadmin','seller','ops'])
                OR role ~ '^official_owner:(\*|[a-z0-9_.-]{1,64})$'
            ) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_admin_rate_limits_window_start_epoch_non_negative'
          AND conrelid = '__PAYMENTS_SCHEMA__.admin_rate_limits'::regclass
    )
    AND EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = '__PAYMENTS_SCHEMA__'
          AND table_name = 'admin_rate_limits'
          AND column_name = 'window_start_epoch'
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.admin_rate_limits
            ADD CONSTRAINT chk_admin_rate_limits_window_start_epoch_non_negative
            CHECK (window_start_epoch >= 0) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_admin_rate_limits_request_count_non_negative'
          AND conrelid = '__PAYMENTS_SCHEMA__.admin_rate_limits'::regclass
    ) THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.admin_rate_limits
            ADD CONSTRAINT chk_admin_rate_limits_request_count_non_negative
            CHECK (request_count >= 0) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_roles_account_id'
          AND conrelid = '__PAYMENTS_SCHEMA__.roles'::regclass
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM __PAYMENTS_SCHEMA__.roles child_row
            WHERE child_row.account_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM __PAYMENTS_SCHEMA__.users parent_row
                    WHERE parent_row.account_id = child_row.account_id
                )
        ) THEN
            RAISE EXCEPTION 'orphaned payments references block ensure_schema: roles.account_id -> users.account_id';
        END IF;
        ALTER TABLE __PAYMENTS_SCHEMA__.roles
            ADD CONSTRAINT fk_roles_account_id
            FOREIGN KEY (account_id) REFERENCES __PAYMENTS_SCHEMA__.users(account_id) ON DELETE CASCADE;
    END IF;
END $$;
