CREATE TABLE IF NOT EXISTS auth_coach_offer_snapshots (
    account_id TEXT NOT NULL,
    offer_id TEXT NOT NULL,
    seats_requested SMALLINT NOT NULL,
    source_kind TEXT NOT NULL,
    source_reference TEXT,
    expires_at TIMESTAMPTZ NOT NULL,
    offer_payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT pk_auth_coach_offer_snapshots
        PRIMARY KEY (account_id, offer_id, seats_requested),
    CONSTRAINT chk_auth_coach_offer_snapshots_account_id_len
        CHECK (char_length(account_id) BETWEEN 3 AND 128),
    CONSTRAINT chk_auth_coach_offer_snapshots_offer_id_len
        CHECK (char_length(offer_id) BETWEEN 3 AND 128),
    CONSTRAINT chk_auth_coach_offer_snapshots_seats_positive
        CHECK (seats_requested > 0),
    CONSTRAINT chk_auth_coach_offer_snapshots_source_kind_known
        CHECK (source_kind IN ('catalog', 'seeded'))
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_offer_snapshots_account_expires
    ON auth_coach_offer_snapshots(account_id, expires_at DESC, updated_at DESC);

CREATE TABLE IF NOT EXISTS auth_coach_holds (
    hold_id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL,
    offer_id TEXT NOT NULL,
    seats_requested SMALLINT NOT NULL,
    operator_reference TEXT NOT NULL,
    status TEXT NOT NULL,
    request_fingerprint TEXT NOT NULL,
    hold_ttl_seconds INTEGER NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    hold_payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    converted_at TIMESTAMPTZ,
    released_at TIMESTAMPTZ,
    expired_at TIMESTAMPTZ,
    CONSTRAINT chk_auth_coach_holds_account_id_len
        CHECK (char_length(account_id) BETWEEN 3 AND 128),
    CONSTRAINT chk_auth_coach_holds_offer_id_len
        CHECK (char_length(offer_id) BETWEEN 3 AND 128),
    CONSTRAINT chk_auth_coach_holds_operator_reference_len
        CHECK (char_length(operator_reference) BETWEEN 3 AND 128),
    CONSTRAINT chk_auth_coach_holds_seats_positive
        CHECK (seats_requested > 0),
    CONSTRAINT chk_auth_coach_holds_status_known
        CHECK (status IN ('active', 'expired', 'converted', 'released')),
    CONSTRAINT chk_auth_coach_holds_ttl_positive
        CHECK (hold_ttl_seconds > 0),
    CONSTRAINT chk_auth_coach_holds_terminal_timestamps_exclusive
        CHECK (
            ((converted_at IS NOT NULL)::int +
             (released_at IS NOT NULL)::int +
             (expired_at IS NOT NULL)::int) <= 1
        )
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_holds_account_status_expires
    ON auth_coach_holds(account_id, status, expires_at DESC, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_auth_coach_holds_offer_account
    ON auth_coach_holds(account_id, offer_id, created_at DESC);
