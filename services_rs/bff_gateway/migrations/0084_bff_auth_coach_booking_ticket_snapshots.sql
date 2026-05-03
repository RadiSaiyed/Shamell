CREATE TABLE IF NOT EXISTS auth_coach_bookings (
    booking_id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL,
    offer_id TEXT NOT NULL,
    hold_id TEXT,
    state TEXT NOT NULL,
    request_fingerprint TEXT NOT NULL,
    booking_payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ticketed_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    refunded_at TIMESTAMPTZ,
    CONSTRAINT chk_auth_coach_bookings_account_id_len
        CHECK (char_length(account_id) BETWEEN 3 AND 128),
    CONSTRAINT chk_auth_coach_bookings_offer_id_len
        CHECK (char_length(offer_id) BETWEEN 3 AND 128),
    CONSTRAINT chk_auth_coach_bookings_state_known
        CHECK (
            state IN (
                'booking_pending',
                'payment_pending',
                'payment_authorized',
                'ticketed',
                'partially_ticketed',
                'cancelled',
                'refund_requested',
                'refund_approved',
                'refunded'
            )
        )
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_bookings_account_state_created
    ON auth_coach_bookings(account_id, state, created_at DESC);

CREATE TABLE IF NOT EXISTS auth_coach_tickets (
    ticket_id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL,
    booking_id TEXT NOT NULL REFERENCES auth_coach_bookings(booking_id) ON DELETE CASCADE,
    passenger_id TEXT NOT NULL,
    status TEXT NOT NULL,
    boarding_state TEXT NOT NULL,
    ticket_payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    issued_at TIMESTAMPTZ,
    voided_at TIMESTAMPTZ,
    refunded_at TIMESTAMPTZ,
    CONSTRAINT chk_auth_coach_tickets_account_id_len
        CHECK (char_length(account_id) BETWEEN 3 AND 128),
    CONSTRAINT chk_auth_coach_tickets_passenger_id_len
        CHECK (char_length(passenger_id) BETWEEN 3 AND 128),
    CONSTRAINT chk_auth_coach_tickets_status_known
        CHECK (status IN ('active', 'voided', 'refunded')),
    CONSTRAINT chk_auth_coach_tickets_boarding_state_known
        CHECK (boarding_state IN ('not_boarded', 'boarded', 'denied', 'no_show'))
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_tickets_account_booking
    ON auth_coach_tickets(account_id, booking_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_auth_coach_tickets_account_status
    ON auth_coach_tickets(account_id, status, created_at DESC);
