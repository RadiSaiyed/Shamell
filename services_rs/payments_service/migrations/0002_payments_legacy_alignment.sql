ALTER TABLE __PAYMENTS_SCHEMA__.txns
    ADD COLUMN IF NOT EXISTS fee_cents BIGINT DEFAULT 0;

ALTER TABLE __PAYMENTS_SCHEMA__.payment_requests
    ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

ALTER TABLE __PAYMENTS_SCHEMA__.aliases
    ADD COLUMN IF NOT EXISTS code_expires_at TIMESTAMPTZ;

ALTER TABLE __PAYMENTS_SCHEMA__.idempotency
    ADD COLUMN IF NOT EXISTS amount_cents BIGINT;

ALTER TABLE __PAYMENTS_SCHEMA__.idempotency
    ADD COLUMN IF NOT EXISTS currency VARCHAR(3);

ALTER TABLE __PAYMENTS_SCHEMA__.idempotency
    ADD COLUMN IF NOT EXISTS wallet_id VARCHAR(36);

ALTER TABLE __PAYMENTS_SCHEMA__.idempotency
    ADD COLUMN IF NOT EXISTS balance_cents BIGINT;

ALTER TABLE __PAYMENTS_SCHEMA__.idempotency
    ALTER COLUMN endpoint TYPE TEXT;

UPDATE __PAYMENTS_SCHEMA__.idempotency
SET endpoint = CONCAT('topup:', wallet_id)
WHERE endpoint = 'topup'
  AND wallet_id IS NOT NULL
  AND wallet_id <> '';

ALTER TABLE __PAYMENTS_SCHEMA__.idempotency
    DROP CONSTRAINT IF EXISTS idempotency_ikey_key;

DROP INDEX IF EXISTS __PAYMENTS_SCHEMA__.idx_idempotency_ikey;

CREATE UNIQUE INDEX IF NOT EXISTS idx_idempotency_ikey_endpoint
    ON __PAYMENTS_SCHEMA__.idempotency(ikey, endpoint);

ALTER TABLE __PAYMENTS_SCHEMA__.users
    ADD COLUMN IF NOT EXISTS account_id VARCHAR(64);

ALTER TABLE __PAYMENTS_SCHEMA__.users
    ALTER COLUMN phone DROP NOT NULL;

ALTER TABLE __PAYMENTS_SCHEMA__.roles
    ADD COLUMN IF NOT EXISTS account_id VARCHAR(64);

ALTER TABLE __PAYMENTS_SCHEMA__.roles
    ALTER COLUMN phone DROP NOT NULL;

UPDATE __PAYMENTS_SCHEMA__.aliases AS a
SET user_id = w.user_id
FROM __PAYMENTS_SCHEMA__.wallets AS w
WHERE a.wallet_id = w.id
  AND a.user_id <> w.user_id;

DELETE FROM __PAYMENTS_SCHEMA__.aliases AS a
WHERE NOT EXISTS (
        SELECT 1
        FROM __PAYMENTS_SCHEMA__.wallets AS w
        WHERE w.id = a.wallet_id
    )
   OR NOT EXISTS (
        SELECT 1
        FROM __PAYMENTS_SCHEMA__.users AS u
        WHERE u.id = a.user_id
    );

UPDATE __PAYMENTS_SCHEMA__.roles AS r
SET account_id = u.account_id
FROM __PAYMENTS_SCHEMA__.users AS u
WHERE r.phone = u.phone
  AND (r.account_id IS NULL OR r.account_id = '')
  AND u.account_id IS NOT NULL
  AND u.account_id <> '';

WITH ranked AS (
    SELECT ctid,
           row_number() OVER (
               PARTITION BY account_id, role
               ORDER BY (phone IS NULL), created_at DESC, id DESC
           ) AS rn
    FROM __PAYMENTS_SCHEMA__.roles
    WHERE account_id IS NOT NULL AND account_id <> ''
)
DELETE FROM __PAYMENTS_SCHEMA__.roles AS r
USING ranked AS d
WHERE r.ctid = d.ctid
  AND d.rn > 1;

WITH ranked AS (
    SELECT ctid,
           row_number() OVER (
               PARTITION BY phone, role
               ORDER BY (account_id IS NULL OR account_id = ''), created_at DESC, id DESC
           ) AS rn
    FROM __PAYMENTS_SCHEMA__.roles
    WHERE phone IS NOT NULL AND phone <> ''
)
DELETE FROM __PAYMENTS_SCHEMA__.roles AS r
USING ranked AS d
WHERE r.ctid = d.ctid
  AND d.rn > 1;

WITH ranked AS (
    SELECT ctid,
           row_number() OVER (
               PARTITION BY owner_wallet_id, favorite_wallet_id
               ORDER BY (alias IS NULL), created_at DESC, id DESC
           ) AS rn
    FROM __PAYMENTS_SCHEMA__.favorites
)
DELETE FROM __PAYMENTS_SCHEMA__.favorites AS f
USING ranked AS r
WHERE f.ctid = r.ctid
  AND r.rn > 1;

DELETE FROM __PAYMENTS_SCHEMA__.favorites AS f
WHERE NOT EXISTS (
        SELECT 1
        FROM __PAYMENTS_SCHEMA__.wallets AS w
        WHERE w.id = f.owner_wallet_id
    )
   OR NOT EXISTS (
        SELECT 1
        FROM __PAYMENTS_SCHEMA__.wallets AS w
        WHERE w.id = f.favorite_wallet_id
    );

DELETE FROM __PAYMENTS_SCHEMA__.payment_requests AS r
WHERE NOT EXISTS (
        SELECT 1
        FROM __PAYMENTS_SCHEMA__.wallets AS w
        WHERE w.id = r.from_wallet_id
    )
   OR NOT EXISTS (
        SELECT 1
        FROM __PAYMENTS_SCHEMA__.wallets AS w
        WHERE w.id = r.to_wallet_id
    );

DELETE FROM __PAYMENTS_SCHEMA__.roles AS r
WHERE r.account_id IS NOT NULL
  AND r.account_id <> ''
  AND NOT EXISTS (
        SELECT 1
        FROM __PAYMENTS_SCHEMA__.users AS u
        WHERE u.account_id = r.account_id
    );

CREATE UNIQUE INDEX IF NOT EXISTS idx_favorites_owner_favorite
    ON __PAYMENTS_SCHEMA__.favorites(owner_wallet_id, favorite_wallet_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_roles_account_role
    ON __PAYMENTS_SCHEMA__.roles(account_id, role)
    WHERE account_id IS NOT NULL AND account_id <> '';

CREATE UNIQUE INDEX IF NOT EXISTS idx_roles_phone_role
    ON __PAYMENTS_SCHEMA__.roles(phone, role)
    WHERE phone IS NOT NULL AND phone <> '';
