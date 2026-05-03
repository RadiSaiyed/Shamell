CREATE TABLE IF NOT EXISTS auth_platform_feature_events (
    id BIGSERIAL PRIMARY KEY,
    account_id VARCHAR(64),
    shamell_user_id VARCHAR(16),
    username VARCHAR(32),
    phone VARCHAR(32),
    module_id VARCHAR(64) NOT NULL,
    action VARCHAR(128) NOT NULL,
    feature_key VARCHAR(128) NOT NULL,
    mini_program_id VARCHAR(128),
    role_context VARCHAR(64),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    device_id_hash VARCHAR(16),
    client_ip_hash VARCHAR(16),
    user_agent_hash VARCHAR(16),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_auth_platform_feature_events_account_id
        FOREIGN KEY (account_id) REFERENCES auth_accounts(account_id) ON DELETE SET NULL,
    CONSTRAINT chk_auth_platform_feature_events_module_present
        CHECK (BTRIM(module_id) <> ''),
    CONSTRAINT chk_auth_platform_feature_events_action_present
        CHECK (BTRIM(action) <> ''),
    CONSTRAINT chk_auth_platform_feature_events_feature_present
        CHECK (BTRIM(feature_key) <> ''),
    CONSTRAINT chk_auth_platform_feature_events_metadata_object
        CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE INDEX IF NOT EXISTS idx_auth_platform_feature_events_created_id
    ON auth_platform_feature_events(created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_auth_platform_feature_events_account_created_id
    ON auth_platform_feature_events(account_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_auth_platform_feature_events_module_created_id
    ON auth_platform_feature_events(module_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_auth_platform_feature_events_feature_created_id
    ON auth_platform_feature_events(feature_key, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_auth_platform_feature_events_mini_program_created_id
    ON auth_platform_feature_events(mini_program_id, created_at DESC, id DESC)
    WHERE mini_program_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_auth_platform_feature_events_username_created_id
    ON auth_platform_feature_events(username, created_at DESC, id DESC)
    WHERE username IS NOT NULL;
