CREATE INDEX IF NOT EXISTS idx_auth_chat_devices_revoked_at
    ON auth_chat_devices(revoked_at);
