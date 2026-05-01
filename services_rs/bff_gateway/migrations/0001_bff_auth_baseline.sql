CREATE TABLE IF NOT EXISTS auth_accounts (
    account_id VARCHAR(64) PRIMARY KEY,
    shamell_user_id VARCHAR(16) NOT NULL UNIQUE,
    phone VARCHAR(32) UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS auth_official_accounts (
    id VARCHAR(64) PRIMARY KEY,
    kind VARCHAR(32) NOT NULL DEFAULT 'service',
    name VARCHAR(180) NOT NULL,
    description TEXT,
    avatar_url TEXT,
    verified BOOLEAN NOT NULL DEFAULT FALSE,
    featured BOOLEAN NOT NULL DEFAULT FALSE,
    chat_peer_id VARCHAR(128),
    module_app_id VARCHAR(64),
    category VARCHAR(64),
    city VARCHAR(64),
    address TEXT,
    opening_hours VARCHAR(128),
    website_url TEXT,
    qr_payload TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_auth_official_accounts_chat_peer_id
    ON auth_official_accounts(chat_peer_id);
CREATE INDEX IF NOT EXISTS idx_auth_official_accounts_featured_name_id
    ON auth_official_accounts(featured DESC, name ASC, id ASC);

CREATE TABLE IF NOT EXISTS auth_sessions (
    id BIGSERIAL PRIMARY KEY,
    sid_hash VARCHAR(64) NOT NULL UNIQUE,
    account_id VARCHAR(64),
    phone VARCHAR(32),
    device_id VARCHAR(128),
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at TIMESTAMPTZ,
    CONSTRAINT fk_auth_sessions_account_id
        FOREIGN KEY (account_id) REFERENCES auth_accounts(account_id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_auth_sessions_expires_at
    ON auth_sessions(expires_at);
CREATE INDEX IF NOT EXISTS idx_auth_sessions_last_seen_at
    ON auth_sessions(last_seen_at);
CREATE INDEX IF NOT EXISTS idx_auth_sessions_account_device_active
    ON auth_sessions(account_id, device_id) WHERE revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS auth_user_ids (
    id BIGSERIAL PRIMARY KEY,
    phone VARCHAR(32) NOT NULL UNIQUE,
    shamell_user_id VARCHAR(16) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS auth_chat_devices (
    id BIGSERIAL PRIMARY KEY,
    account_id VARCHAR(64),
    phone VARCHAR(32),
    chat_device_id VARCHAR(128) NOT NULL UNIQUE,
    client_device_id VARCHAR(128),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at TIMESTAMPTZ,
    UNIQUE (phone, chat_device_id),
    CONSTRAINT fk_auth_chat_devices_account_id
        FOREIGN KEY (account_id) REFERENCES auth_accounts(account_id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_auth_chat_devices_account_active_last_seen
    ON auth_chat_devices(account_id, last_seen_at DESC, id DESC) WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_auth_chat_devices_account_client_device_active
    ON auth_chat_devices(account_id, client_device_id) WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_auth_chat_devices_phone_active_last_seen
    ON auth_chat_devices(phone, last_seen_at DESC, id DESC) WHERE revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS auth_contact_invites (
    id BIGSERIAL PRIMARY KEY,
    token_hash VARCHAR(64) NOT NULL UNIQUE,
    issuer_account_id VARCHAR(64),
    issuer_phone VARCHAR(32),
    issuer_chat_device_id VARCHAR(128) NOT NULL,
    max_uses INT NOT NULL DEFAULT 1,
    use_count INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_redeemed_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    CONSTRAINT fk_auth_contact_invites_issuer_account_id
        FOREIGN KEY (issuer_account_id) REFERENCES auth_accounts(account_id) ON DELETE SET NULL,
    CONSTRAINT fk_auth_contact_invites_issuer_chat_device_id
        FOREIGN KEY (issuer_chat_device_id) REFERENCES auth_chat_devices(chat_device_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_auth_contact_invites_expires_at
    ON auth_contact_invites(expires_at);

CREATE TABLE IF NOT EXISTS auth_account_create_challenges (
    id BIGSERIAL PRIMARY KEY,
    token_hash VARCHAR(64) NOT NULL UNIQUE,
    device_id VARCHAR(128) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_auth_account_create_challenges_gc_at
    ON auth_account_create_challenges(COALESCE(consumed_at, expires_at));

CREATE TABLE IF NOT EXISTS auth_chat_contacts (
    id BIGSERIAL PRIMARY KEY,
    owner_account_id VARCHAR(64) NOT NULL,
    peer_chat_device_id VARCHAR(128) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at TIMESTAMPTZ,
    UNIQUE (owner_account_id, peer_chat_device_id),
    CONSTRAINT fk_auth_chat_contacts_owner_account_id
        FOREIGN KEY (owner_account_id) REFERENCES auth_accounts(account_id) ON DELETE CASCADE,
    CONSTRAINT fk_auth_chat_contacts_peer_chat_device_id
        FOREIGN KEY (peer_chat_device_id) REFERENCES auth_chat_devices(chat_device_id) ON DELETE CASCADE
);


CREATE TABLE IF NOT EXISTS auth_biometric_tokens (
    id BIGSERIAL PRIMARY KEY,
    token_hash VARCHAR(64) NOT NULL UNIQUE,
    account_id VARCHAR(64),
    phone VARCHAR(32),
    device_id VARCHAR(128) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    UNIQUE (phone, device_id),
    CONSTRAINT fk_auth_biometric_tokens_account_id
        FOREIGN KEY (account_id) REFERENCES auth_accounts(account_id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_auth_biometric_tokens_expires_at
    ON auth_biometric_tokens(expires_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_auth_biometric_tokens_account_device
    ON auth_biometric_tokens(account_id, device_id);

CREATE TABLE IF NOT EXISTS auth_official_template_messages (
    id BIGSERIAL PRIMARY KEY,
    account_id VARCHAR(64) NOT NULL,
    kind VARCHAR(32) NOT NULL DEFAULT 'service',
    title VARCHAR(180) NOT NULL,
    body TEXT NOT NULL,
    deeplink_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    read_at TIMESTAMPTZ,
    CONSTRAINT fk_auth_official_template_messages_account_id
        FOREIGN KEY (account_id) REFERENCES auth_accounts(account_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_auth_official_template_messages_unread_order
    ON auth_official_template_messages(account_id, read_at, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_auth_official_template_messages_account_created
    ON auth_official_template_messages(account_id, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS auth_official_follows (
    id BIGSERIAL PRIMARY KEY,
    account_id VARCHAR(64) NOT NULL,
    official_id VARCHAR(64) NOT NULL,
    followed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (account_id, official_id),
    CONSTRAINT fk_auth_official_follows_account_id
        FOREIGN KEY (account_id) REFERENCES auth_accounts(account_id) ON DELETE CASCADE,
    CONSTRAINT fk_auth_official_follows_official_id
        FOREIGN KEY (official_id) REFERENCES auth_official_accounts(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_auth_official_follows_official_id
    ON auth_official_follows(official_id);

CREATE TABLE IF NOT EXISTS auth_official_feed_items (
    id BIGSERIAL PRIMARY KEY,
    account_id VARCHAR(64) NOT NULL,
    item_id VARCHAR(64) NOT NULL UNIQUE,
    title VARCHAR(220) NOT NULL,
    snippet TEXT,
    thumb_url TEXT,
    ts TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_auth_official_feed_items_account_id
        FOREIGN KEY (account_id) REFERENCES auth_official_accounts(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_auth_official_feed_items_account_ts_id
    ON auth_official_feed_items(account_id, ts DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_auth_official_feed_items_ts_id
    ON auth_official_feed_items(ts DESC, id DESC);

CREATE TABLE IF NOT EXISTS auth_official_auto_replies (
    id BIGSERIAL PRIMARY KEY,
    account_id VARCHAR(64) NOT NULL,
    kind VARCHAR(32) NOT NULL DEFAULT 'welcome',
    keyword VARCHAR(128),
    text TEXT NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_auth_official_auto_replies_account_id
        FOREIGN KEY (account_id) REFERENCES auth_official_accounts(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_auth_official_auto_replies_account_id_order
    ON auth_official_auto_replies(account_id, id ASC);
CREATE INDEX IF NOT EXISTS idx_auth_official_auto_replies_public_welcome
    ON auth_official_auto_replies(account_id, id ASC)
    WHERE enabled = TRUE AND lower(kind) = 'welcome';

CREATE TABLE IF NOT EXISTS auth_official_notification_modes (
    id BIGSERIAL PRIMARY KEY,
    account_id VARCHAR(64) NOT NULL,
    official_id VARCHAR(64) NOT NULL,
    mode VARCHAR(16) NOT NULL DEFAULT 'full',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (account_id, official_id),
    CONSTRAINT fk_auth_official_notification_modes_account_id
        FOREIGN KEY (account_id) REFERENCES auth_accounts(account_id) ON DELETE CASCADE,
    CONSTRAINT fk_auth_official_notification_modes_official_id
        FOREIGN KEY (official_id) REFERENCES auth_official_accounts(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS auth_official_service_sessions (
    id BIGSERIAL PRIMARY KEY,
    account_id VARCHAR(64) NOT NULL,
    customer_account_id VARCHAR(64),
    customer_phone VARCHAR(32),
    chat_peer_id VARCHAR(128),
    status VARCHAR(16) NOT NULL DEFAULT 'open',
    last_message_ts TIMESTAMPTZ,
    last_message_preview TEXT,
    unread_by_operator BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_auth_official_service_sessions_account_id
        FOREIGN KEY (account_id) REFERENCES auth_official_accounts(id) ON DELETE CASCADE,
    CONSTRAINT fk_auth_official_service_sessions_customer_account_id
        FOREIGN KEY (customer_account_id) REFERENCES auth_accounts(account_id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_auth_official_service_sessions_inbox_sort
    ON auth_official_service_sessions(account_id, COALESCE(last_message_ts, created_at) DESC, id DESC);

CREATE TABLE IF NOT EXISTS auth_rate_limits (
    limit_key VARCHAR(255) PRIMARY KEY,
    window_start_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    request_count BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_auth_rate_limits_updated_at
    ON auth_rate_limits(updated_at);

CREATE TABLE IF NOT EXISTS device_login_challenges (
    id BIGSERIAL PRIMARY KEY,
    token_hash VARCHAR(64) NOT NULL UNIQUE,
    label VARCHAR(128),
    status VARCHAR(16) NOT NULL DEFAULT 'pending',
    account_id VARCHAR(64),
    phone VARCHAR(32),
    device_id VARCHAR(128),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    approved_at TIMESTAMPTZ,
    CONSTRAINT fk_device_login_challenges_account_id
        FOREIGN KEY (account_id) REFERENCES auth_accounts(account_id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_device_login_challenges_expires_at
    ON device_login_challenges(expires_at);

CREATE TABLE IF NOT EXISTS device_sessions (
    id BIGSERIAL PRIMARY KEY,
    account_id VARCHAR(64),
    phone VARCHAR(32),
    device_id VARCHAR(128) NOT NULL,
    device_type VARCHAR(32),
    device_name VARCHAR(128),
    platform VARCHAR(32),
    app_version VARCHAR(32),
    last_ip VARCHAR(64),
    user_agent VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_device_sessions_account_id
        FOREIGN KEY (account_id) REFERENCES auth_accounts(account_id) ON DELETE SET NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_device_sessions_account_device
    ON device_sessions(account_id, device_id);
CREATE INDEX IF NOT EXISTS idx_device_sessions_account_last_seen
    ON device_sessions(account_id, last_seen_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_device_sessions_last_seen_at
    ON device_sessions(last_seen_at);
