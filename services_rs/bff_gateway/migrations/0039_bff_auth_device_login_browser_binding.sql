ALTER TABLE device_login_challenges
    ADD COLUMN IF NOT EXISTS browser_binding_hash VARCHAR(64);
