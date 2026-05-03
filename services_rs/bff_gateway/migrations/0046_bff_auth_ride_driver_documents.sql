CREATE TABLE IF NOT EXISTS auth_ride_driver_documents (
    id BIGSERIAL PRIMARY KEY,
    document_id TEXT NOT NULL UNIQUE,
    driver_account_id TEXT NOT NULL,
    document_type TEXT NOT NULL,
    document_number TEXT NOT NULL,
    issuing_country TEXT,
    expires_at TIMESTAMPTZ,
    status TEXT NOT NULL,
    review_note TEXT,
    reviewer_account_id TEXT,
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_ride_driver_documents_type_known
        CHECK (
            document_type IN (
                'driver_license',
                'vehicle_registration',
                'insurance',
                'identity_card'
            )
        ),
    CONSTRAINT chk_auth_ride_driver_documents_status_known
        CHECK (status IN ('pending', 'approved', 'rejected')),
    CONSTRAINT chk_auth_ride_driver_documents_number_len
        CHECK (char_length(document_number) BETWEEN 4 AND 64),
    CONSTRAINT chk_auth_ride_driver_documents_country_len
        CHECK (
            issuing_country IS NULL
            OR char_length(issuing_country) BETWEEN 2 AND 3
        ),
    CONSTRAINT chk_auth_ride_driver_documents_review_consistency
        CHECK (
            (status = 'pending' AND reviewed_at IS NULL AND reviewer_account_id IS NULL)
            OR (status IN ('approved', 'rejected') AND reviewed_at IS NOT NULL AND reviewer_account_id IS NOT NULL)
        ),
    CONSTRAINT chk_auth_ride_driver_documents_updated_after_submitted
        CHECK (updated_at >= submitted_at)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_auth_ride_driver_documents_driver_type
    ON auth_ride_driver_documents(driver_account_id, document_type);

CREATE INDEX IF NOT EXISTS idx_auth_ride_driver_documents_status_updated
    ON auth_ride_driver_documents(status, updated_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_auth_ride_driver_documents_driver_updated
    ON auth_ride_driver_documents(driver_account_id, updated_at DESC, id DESC);
