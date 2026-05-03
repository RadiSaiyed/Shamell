CREATE TABLE IF NOT EXISTS auth_ride_support_tickets (
    id BIGSERIAL PRIMARY KEY,
    ticket_id TEXT NOT NULL UNIQUE,
    ride_id TEXT REFERENCES auth_ride_trips(ride_id) ON DELETE SET NULL,
    rider_account_id TEXT NOT NULL,
    ticket_category TEXT NOT NULL,
    subject TEXT NOT NULL,
    body_text TEXT NOT NULL,
    preferred_contact TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'open',
    resolution_note TEXT,
    resolved_by_account_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ,
    CONSTRAINT chk_auth_ride_support_tickets_category_known
        CHECK (ticket_category IN (
            'booking_issue',
            'driver_behavior',
            'safety',
            'payment_issue',
            'lost_item',
            'other'
        )),
    CONSTRAINT chk_auth_ride_support_tickets_contact_known
        CHECK (preferred_contact IN ('in_app', 'email', 'phone')),
    CONSTRAINT chk_auth_ride_support_tickets_status_known
        CHECK (status IN ('open', 'resolved')),
    CONSTRAINT chk_auth_ride_support_tickets_resolution_consistency
        CHECK (
            (status = 'open' AND resolved_at IS NULL AND resolved_by_account_id IS NULL)
            OR (
                status = 'resolved'
                AND resolved_at IS NOT NULL
                AND resolved_by_account_id IS NOT NULL
            )
        )
);

CREATE INDEX IF NOT EXISTS idx_auth_ride_support_tickets_rider_updated
    ON auth_ride_support_tickets(rider_account_id, updated_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_auth_ride_support_tickets_status_updated
    ON auth_ride_support_tickets(status, updated_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_auth_ride_support_tickets_ride_updated
    ON auth_ride_support_tickets(ride_id, updated_at DESC, id DESC);
