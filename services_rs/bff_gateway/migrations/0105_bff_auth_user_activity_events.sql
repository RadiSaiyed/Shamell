CREATE TABLE IF NOT EXISTS auth_user_activity_events (
    id BIGSERIAL PRIMARY KEY,
    account_id VARCHAR(64),
    shamell_user_id VARCHAR(16),
    username VARCHAR(32),
    phone VARCHAR(32),
    event_type VARCHAR(64) NOT NULL,
    module_id VARCHAR(64),
    action VARCHAR(128),
    route VARCHAR(256),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    device_id_hash VARCHAR(16),
    client_ip_hash VARCHAR(16),
    user_agent_hash VARCHAR(16),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_auth_user_activity_events_account_id
        FOREIGN KEY (account_id) REFERENCES auth_accounts(account_id) ON DELETE SET NULL,
    CONSTRAINT chk_auth_user_activity_events_event_type_present
        CHECK (BTRIM(event_type) <> ''),
    CONSTRAINT chk_auth_user_activity_events_metadata_object
        CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE INDEX IF NOT EXISTS idx_auth_user_activity_events_created_id
    ON auth_user_activity_events(created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_auth_user_activity_events_account_created_id
    ON auth_user_activity_events(account_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_auth_user_activity_events_event_created_id
    ON auth_user_activity_events(event_type, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_auth_user_activity_events_username_created_id
    ON auth_user_activity_events(username, created_at DESC, id DESC)
    WHERE username IS NOT NULL;
