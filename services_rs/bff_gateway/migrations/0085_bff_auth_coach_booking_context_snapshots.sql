ALTER TABLE auth_coach_offer_snapshots
    ADD COLUMN IF NOT EXISTS journey_payload JSONB;

ALTER TABLE auth_coach_bookings
    ADD COLUMN IF NOT EXISTS offer_payload JSONB,
    ADD COLUMN IF NOT EXISTS hold_payload JSONB,
    ADD COLUMN IF NOT EXISTS journey_summary_payload JSONB,
    ADD COLUMN IF NOT EXISTS passengers_manifest_payload JSONB;
