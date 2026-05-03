ALTER TABLE auth_ride_driver_presence
    ADD COLUMN IF NOT EXISTS driver_name TEXT,
    ADD COLUMN IF NOT EXISTS car_plate TEXT;
