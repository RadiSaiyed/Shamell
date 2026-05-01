DO $$
DECLARE
    column_type TEXT;
BEGIN
    SELECT data_type
    INTO column_type
    FROM information_schema.columns
    WHERE table_schema = '__PAYMENTS_SCHEMA__'
      AND table_name = 'txns'
      AND column_name = 'created_at';

    IF column_type IS NULL THEN
        RAISE EXCEPTION 'required payments timestamp column missing before migration: __PAYMENTS_SCHEMA__.txns.created_at';
    ELSIF column_type = 'timestamp with time zone' THEN
        NULL;
    ELSIF column_type IN ('text', 'character varying') THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.txns
            ALTER COLUMN created_at TYPE TIMESTAMPTZ
            USING CASE
                WHEN created_at IS NULL OR btrim(created_at) = '' THEN NULL
                ELSE created_at::timestamptz
            END;
    ELSIF column_type = 'timestamp without time zone' THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.txns
            ALTER COLUMN created_at TYPE TIMESTAMPTZ
            USING created_at AT TIME ZONE 'UTC';
    ELSE
        RAISE EXCEPTION 'unsupported payments timestamp column type for __PAYMENTS_SCHEMA__.txns.created_at: %', column_type;
    END IF;
END $$;

DO $$
DECLARE
    column_type TEXT;
BEGIN
    SELECT data_type
    INTO column_type
    FROM information_schema.columns
    WHERE table_schema = '__PAYMENTS_SCHEMA__'
      AND table_name = 'ledger_entries'
      AND column_name = 'created_at';

    IF column_type IS NULL THEN
        RAISE EXCEPTION 'required payments timestamp column missing before migration: __PAYMENTS_SCHEMA__.ledger_entries.created_at';
    ELSIF column_type = 'timestamp with time zone' THEN
        NULL;
    ELSIF column_type IN ('text', 'character varying') THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.ledger_entries
            ALTER COLUMN created_at TYPE TIMESTAMPTZ
            USING CASE
                WHEN created_at IS NULL OR btrim(created_at) = '' THEN NULL
                ELSE created_at::timestamptz
            END;
    ELSIF column_type = 'timestamp without time zone' THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.ledger_entries
            ALTER COLUMN created_at TYPE TIMESTAMPTZ
            USING created_at AT TIME ZONE 'UTC';
    ELSE
        RAISE EXCEPTION 'unsupported payments timestamp column type for __PAYMENTS_SCHEMA__.ledger_entries.created_at: %', column_type;
    END IF;
END $$;

DO $$
DECLARE
    column_type TEXT;
BEGIN
    SELECT data_type
    INTO column_type
    FROM information_schema.columns
    WHERE table_schema = '__PAYMENTS_SCHEMA__'
      AND table_name = 'idempotency'
      AND column_name = 'created_at';

    IF column_type IS NULL THEN
        RAISE EXCEPTION 'required payments timestamp column missing before migration: __PAYMENTS_SCHEMA__.idempotency.created_at';
    ELSIF column_type = 'timestamp with time zone' THEN
        NULL;
    ELSIF column_type IN ('text', 'character varying') THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.idempotency
            ALTER COLUMN created_at TYPE TIMESTAMPTZ
            USING CASE
                WHEN created_at IS NULL OR btrim(created_at) = '' THEN NULL
                ELSE created_at::timestamptz
            END;
    ELSIF column_type = 'timestamp without time zone' THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.idempotency
            ALTER COLUMN created_at TYPE TIMESTAMPTZ
            USING created_at AT TIME ZONE 'UTC';
    ELSE
        RAISE EXCEPTION 'unsupported payments timestamp column type for __PAYMENTS_SCHEMA__.idempotency.created_at: %', column_type;
    END IF;
END $$;

DO $$
DECLARE
    column_type TEXT;
BEGIN
    SELECT data_type
    INTO column_type
    FROM information_schema.columns
    WHERE table_schema = '__PAYMENTS_SCHEMA__'
      AND table_name = 'favorites'
      AND column_name = 'created_at';

    IF column_type IS NULL THEN
        RAISE EXCEPTION 'required payments timestamp column missing before migration: __PAYMENTS_SCHEMA__.favorites.created_at';
    ELSIF column_type = 'timestamp with time zone' THEN
        NULL;
    ELSIF column_type IN ('text', 'character varying') THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.favorites
            ALTER COLUMN created_at TYPE TIMESTAMPTZ
            USING CASE
                WHEN created_at IS NULL OR btrim(created_at) = '' THEN NULL
                ELSE created_at::timestamptz
            END;
    ELSIF column_type = 'timestamp without time zone' THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.favorites
            ALTER COLUMN created_at TYPE TIMESTAMPTZ
            USING created_at AT TIME ZONE 'UTC';
    ELSE
        RAISE EXCEPTION 'unsupported payments timestamp column type for __PAYMENTS_SCHEMA__.favorites.created_at: %', column_type;
    END IF;
END $$;

DO $$
DECLARE
    column_type TEXT;
BEGIN
    SELECT data_type
    INTO column_type
    FROM information_schema.columns
    WHERE table_schema = '__PAYMENTS_SCHEMA__'
      AND table_name = 'payment_requests'
      AND column_name = 'created_at';

    IF column_type IS NULL THEN
        RAISE EXCEPTION 'required payments timestamp column missing before migration: __PAYMENTS_SCHEMA__.payment_requests.created_at';
    ELSIF column_type = 'timestamp with time zone' THEN
        NULL;
    ELSIF column_type IN ('text', 'character varying') THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.payment_requests
            ALTER COLUMN created_at TYPE TIMESTAMPTZ
            USING CASE
                WHEN created_at IS NULL OR btrim(created_at) = '' THEN NULL
                ELSE created_at::timestamptz
            END;
    ELSIF column_type = 'timestamp without time zone' THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.payment_requests
            ALTER COLUMN created_at TYPE TIMESTAMPTZ
            USING created_at AT TIME ZONE 'UTC';
    ELSE
        RAISE EXCEPTION 'unsupported payments timestamp column type for __PAYMENTS_SCHEMA__.payment_requests.created_at: %', column_type;
    END IF;
END $$;

DO $$
DECLARE
    column_type TEXT;
BEGIN
    SELECT data_type
    INTO column_type
    FROM information_schema.columns
    WHERE table_schema = '__PAYMENTS_SCHEMA__'
      AND table_name = 'payment_requests'
      AND column_name = 'expires_at';

    IF column_type IS NULL THEN
        RAISE EXCEPTION 'required payments timestamp column missing before migration: __PAYMENTS_SCHEMA__.payment_requests.expires_at';
    ELSIF column_type = 'timestamp with time zone' THEN
        NULL;
    ELSIF column_type IN ('text', 'character varying') THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.payment_requests
            ALTER COLUMN expires_at TYPE TIMESTAMPTZ
            USING CASE
                WHEN expires_at IS NULL OR btrim(expires_at) = '' THEN NULL
                ELSE expires_at::timestamptz
            END;
    ELSIF column_type = 'timestamp without time zone' THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.payment_requests
            ALTER COLUMN expires_at TYPE TIMESTAMPTZ
            USING expires_at AT TIME ZONE 'UTC';
    ELSE
        RAISE EXCEPTION 'unsupported payments timestamp column type for __PAYMENTS_SCHEMA__.payment_requests.expires_at: %', column_type;
    END IF;
END $$;

DO $$
DECLARE
    column_type TEXT;
BEGIN
    SELECT data_type
    INTO column_type
    FROM information_schema.columns
    WHERE table_schema = '__PAYMENTS_SCHEMA__'
      AND table_name = 'aliases'
      AND column_name = 'code_expires_at';

    IF column_type IS NULL THEN
        RAISE EXCEPTION 'required payments timestamp column missing before migration: __PAYMENTS_SCHEMA__.aliases.code_expires_at';
    ELSIF column_type = 'timestamp with time zone' THEN
        NULL;
    ELSIF column_type IN ('text', 'character varying') THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.aliases
            ALTER COLUMN code_expires_at TYPE TIMESTAMPTZ
            USING CASE
                WHEN code_expires_at IS NULL OR btrim(code_expires_at) = '' THEN NULL
                ELSE code_expires_at::timestamptz
            END;
    ELSIF column_type = 'timestamp without time zone' THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.aliases
            ALTER COLUMN code_expires_at TYPE TIMESTAMPTZ
            USING code_expires_at AT TIME ZONE 'UTC';
    ELSE
        RAISE EXCEPTION 'unsupported payments timestamp column type for __PAYMENTS_SCHEMA__.aliases.code_expires_at: %', column_type;
    END IF;
END $$;

DO $$
DECLARE
    column_type TEXT;
BEGIN
    SELECT data_type
    INTO column_type
    FROM information_schema.columns
    WHERE table_schema = '__PAYMENTS_SCHEMA__'
      AND table_name = 'aliases'
      AND column_name = 'created_at';

    IF column_type IS NULL THEN
        RAISE EXCEPTION 'required payments timestamp column missing before migration: __PAYMENTS_SCHEMA__.aliases.created_at';
    ELSIF column_type = 'timestamp with time zone' THEN
        NULL;
    ELSIF column_type IN ('text', 'character varying') THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.aliases
            ALTER COLUMN created_at TYPE TIMESTAMPTZ
            USING CASE
                WHEN created_at IS NULL OR btrim(created_at) = '' THEN NULL
                ELSE created_at::timestamptz
            END;
    ELSIF column_type = 'timestamp without time zone' THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.aliases
            ALTER COLUMN created_at TYPE TIMESTAMPTZ
            USING created_at AT TIME ZONE 'UTC';
    ELSE
        RAISE EXCEPTION 'unsupported payments timestamp column type for __PAYMENTS_SCHEMA__.aliases.created_at: %', column_type;
    END IF;
END $$;

DO $$
DECLARE
    column_type TEXT;
BEGIN
    SELECT data_type
    INTO column_type
    FROM information_schema.columns
    WHERE table_schema = '__PAYMENTS_SCHEMA__'
      AND table_name = 'roles'
      AND column_name = 'created_at';

    IF column_type IS NULL THEN
        RAISE EXCEPTION 'required payments timestamp column missing before migration: __PAYMENTS_SCHEMA__.roles.created_at';
    ELSIF column_type = 'timestamp with time zone' THEN
        NULL;
    ELSIF column_type IN ('text', 'character varying') THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.roles
            ALTER COLUMN created_at TYPE TIMESTAMPTZ
            USING CASE
                WHEN created_at IS NULL OR btrim(created_at) = '' THEN NULL
                ELSE created_at::timestamptz
            END;
    ELSIF column_type = 'timestamp without time zone' THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.roles
            ALTER COLUMN created_at TYPE TIMESTAMPTZ
            USING created_at AT TIME ZONE 'UTC';
    ELSE
        RAISE EXCEPTION 'unsupported payments timestamp column type for __PAYMENTS_SCHEMA__.roles.created_at: %', column_type;
    END IF;
END $$;

DO $$
DECLARE
    column_type TEXT;
BEGIN
    SELECT data_type
    INTO column_type
    FROM information_schema.columns
    WHERE table_schema = '__PAYMENTS_SCHEMA__'
      AND table_name = 'admin_rate_limits'
      AND column_name = 'updated_at';

    IF column_type IS NULL THEN
        RAISE EXCEPTION 'required payments timestamp column missing before migration: __PAYMENTS_SCHEMA__.admin_rate_limits.updated_at';
    ELSIF column_type = 'timestamp with time zone' THEN
        NULL;
    ELSIF column_type IN ('text', 'character varying') THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.admin_rate_limits
            ALTER COLUMN updated_at TYPE TIMESTAMPTZ
            USING CASE
                WHEN updated_at IS NULL OR btrim(updated_at) = '' THEN NULL
                ELSE updated_at::timestamptz
            END;
    ELSIF column_type = 'timestamp without time zone' THEN
        ALTER TABLE __PAYMENTS_SCHEMA__.admin_rate_limits
            ALTER COLUMN updated_at TYPE TIMESTAMPTZ
            USING updated_at AT TIME ZONE 'UTC';
    ELSE
        RAISE EXCEPTION 'unsupported payments timestamp column type for __PAYMENTS_SCHEMA__.admin_rate_limits.updated_at: %', column_type;
    END IF;
END $$;
