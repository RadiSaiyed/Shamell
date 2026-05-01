CREATE TABLE IF NOT EXISTS auth_coach_ops_reviews (
    request_id TEXT PRIMARY KEY,
    request_kind TEXT NOT NULL,
    decision TEXT NOT NULL,
    queue_status TEXT NOT NULL,
    reviewed_at TIMESTAMPTZ NOT NULL,
    reviewed_by_account_id TEXT NOT NULL,
    review_note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_coach_ops_reviews_request_id_nonempty
        CHECK (btrim(request_id) <> ''),
    CONSTRAINT chk_auth_coach_ops_reviews_request_kind_known
        CHECK (request_kind IN ('refund_request', 'change_request')),
    CONSTRAINT chk_auth_coach_ops_reviews_decision_known
        CHECK (decision IN ('approve', 'reject')),
    CONSTRAINT chk_auth_coach_ops_reviews_queue_status_known
        CHECK (queue_status IN ('approved', 'rejected')),
    CONSTRAINT chk_auth_coach_ops_reviews_reviewed_by_account_id_nonempty
        CHECK (btrim(reviewed_by_account_id) <> '')
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_ops_reviews_kind_status_reviewed
    ON auth_coach_ops_reviews(request_kind, queue_status, reviewed_at DESC);

CREATE TABLE IF NOT EXISTS auth_coach_boarding_events (
    trip_id TEXT NOT NULL,
    ticket_id TEXT NOT NULL,
    boarding_event_id TEXT NOT NULL UNIQUE,
    scan_status TEXT NOT NULL,
    captured_at TIMESTAMPTZ NOT NULL,
    offline_captured BOOLEAN NOT NULL DEFAULT FALSE,
    device_id TEXT,
    note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (trip_id, ticket_id),
    CONSTRAINT chk_auth_coach_boarding_events_trip_id_nonempty
        CHECK (btrim(trip_id) <> ''),
    CONSTRAINT chk_auth_coach_boarding_events_ticket_id_nonempty
        CHECK (btrim(ticket_id) <> ''),
    CONSTRAINT chk_auth_coach_boarding_events_boarding_event_id_nonempty
        CHECK (btrim(boarding_event_id) <> ''),
    CONSTRAINT chk_auth_coach_boarding_events_scan_status_known
        CHECK (scan_status IN ('scanned', 'duplicate', 'denied', 'revoked', 'no_show'))
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_boarding_events_trip_captured
    ON auth_coach_boarding_events(trip_id, captured_at DESC);
