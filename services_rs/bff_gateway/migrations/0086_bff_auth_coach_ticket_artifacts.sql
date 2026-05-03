CREATE TABLE IF NOT EXISTS auth_coach_ticket_artifacts (
    artifact_id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL,
    booking_id TEXT NOT NULL REFERENCES auth_coach_bookings(booking_id) ON DELETE CASCADE,
    ticket_id TEXT NOT NULL REFERENCES auth_coach_tickets(ticket_id) ON DELETE CASCADE,
    artifact_kind TEXT NOT NULL,
    delivery_channel TEXT NOT NULL,
    file_name TEXT NOT NULL,
    mime_type TEXT NOT NULL,
    content_length_bytes BIGINT NOT NULL DEFAULT 0,
    download_path TEXT NOT NULL,
    artifact_payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_coach_ticket_artifacts_account_id_len
        CHECK (char_length(account_id) BETWEEN 3 AND 128),
    CONSTRAINT chk_auth_coach_ticket_artifacts_kind_known
        CHECK (artifact_kind IN ('qr', 'pdf', 'wallet_pass')),
    CONSTRAINT chk_auth_coach_ticket_artifacts_delivery_channel_known
        CHECK (delivery_channel IN ('qr', 'pdf', 'wallet_pass')),
    CONSTRAINT chk_auth_coach_ticket_artifacts_content_length_non_negative
        CHECK (content_length_bytes >= 0),
    CONSTRAINT uq_auth_coach_ticket_artifacts_ticket_kind
        UNIQUE (ticket_id, artifact_kind)
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_ticket_artifacts_account_booking
    ON auth_coach_ticket_artifacts(account_id, booking_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_auth_coach_ticket_artifacts_account_ticket
    ON auth_coach_ticket_artifacts(account_id, ticket_id, created_at DESC);
