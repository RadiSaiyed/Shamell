CREATE SCHEMA IF NOT EXISTS __CHAT_SCHEMA__;

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.devices (
    id VARCHAR(24) PRIMARY KEY,
    public_key VARCHAR(255) NOT NULL,
    key_version INTEGER NOT NULL DEFAULT 0,
    name VARCHAR(120),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.device_auth (
    device_id VARCHAR(24) PRIMARY KEY,
    token_hash VARCHAR(64) NOT NULL,
    rotated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.messages (
    id VARCHAR(36) PRIMARY KEY,
    sender_id VARCHAR(24) NOT NULL,
    recipient_id VARCHAR(24) NOT NULL,
    protocol_version VARCHAR(24) NOT NULL DEFAULT 'v1_legacy',
    sender_pubkey VARCHAR(255) NOT NULL,
    sender_dh_pub VARCHAR(255),
    nonce_b64 VARCHAR(64) NOT NULL,
    box_b64 TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    delivered_at TIMESTAMPTZ,
    read_at TIMESTAMPTZ,
    expire_at TIMESTAMPTZ,
    sealed_sender BOOLEAN NOT NULL DEFAULT FALSE,
    sender_hint VARCHAR(64),
    prev_key_id VARCHAR(64),
    key_id VARCHAR(64),
    CONSTRAINT chk_messages_delivered_at_after_created_at
        CHECK (delivered_at IS NULL OR delivered_at >= created_at),
    CONSTRAINT chk_messages_read_at_after_created_at
        CHECK (read_at IS NULL OR read_at >= created_at),
    CONSTRAINT chk_messages_expire_at_after_created_at
        CHECK (expire_at IS NULL OR expire_at >= created_at)
);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.groups (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(120) NOT NULL,
    creator_id VARCHAR(24) NOT NULL,
    key_version INTEGER NOT NULL DEFAULT 0,
    avatar_b64 TEXT,
    avatar_mime VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.group_members (
    group_id VARCHAR(36) NOT NULL,
    device_id VARCHAR(24) NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'member',
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (group_id, device_id)
);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.group_messages (
    id VARCHAR(36) PRIMARY KEY,
    group_id VARCHAR(36) NOT NULL,
    sender_id VARCHAR(24) NOT NULL,
    protocol_version VARCHAR(24) NOT NULL DEFAULT 'v1_legacy',
    text VARCHAR(4096) NOT NULL DEFAULT '',
    kind VARCHAR(20),
    nonce_b64 VARCHAR(64),
    box_b64 TEXT,
    attachment_b64 TEXT,
    attachment_mime VARCHAR(64),
    voice_secs INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expire_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.group_key_events (
    group_id VARCHAR(36) NOT NULL,
    version INTEGER NOT NULL,
    actor_id VARCHAR(24) NOT NULL,
    key_fp VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (group_id, version)
);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.device_key_events (
    device_id VARCHAR(24) NOT NULL,
    version INTEGER NOT NULL,
    old_key_fp VARCHAR(64),
    new_key_fp VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (device_id, version)
);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.chat_identity_keys (
    device_id VARCHAR(24) PRIMARY KEY,
    identity_key_b64 TEXT NOT NULL,
    identity_signing_key_b64 TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.chat_signed_prekeys (
    device_id VARCHAR(24) PRIMARY KEY,
    key_id BIGINT NOT NULL,
    public_key_b64 TEXT NOT NULL,
    signature_b64 TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.chat_one_time_prekeys (
    device_id VARCHAR(24) NOT NULL,
    key_id BIGINT NOT NULL,
    key_b64 TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    consumed_at TIMESTAMPTZ,
    CONSTRAINT chk_chat_one_time_prekeys_consumed_at_after_created_at
        CHECK (consumed_at IS NULL OR consumed_at >= created_at),
    PRIMARY KEY (device_id, key_id)
);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.chat_device_protocol_state (
    device_id VARCHAR(24) PRIMARY KEY,
    protocol_floor VARCHAR(24) NOT NULL DEFAULT 'v1_legacy',
    supports_v2 INTEGER NOT NULL DEFAULT 0,
    v2_only INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.chat_mailboxes (
    token_hash VARCHAR(64) PRIMARY KEY,
    owner_device_id VARCHAR(24) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    rotated_at TIMESTAMPTZ,
    active INTEGER NOT NULL DEFAULT 1,
    CONSTRAINT chk_chat_mailboxes_rotated_at_after_created_at
        CHECK (rotated_at IS NULL OR rotated_at >= created_at)
);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.chat_mailbox_messages (
    id VARCHAR(36) PRIMARY KEY,
    token_hash VARCHAR(64) NOT NULL,
    envelope_b64 TEXT NOT NULL,
    sender_hint VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expire_at TIMESTAMPTZ,
    consumed_at TIMESTAMPTZ,
    CONSTRAINT chk_chat_mailbox_messages_expire_at_after_created_at
        CHECK (expire_at IS NULL OR expire_at >= created_at),
    CONSTRAINT chk_chat_mailbox_messages_consumed_at_after_created_at
        CHECK (consumed_at IS NULL OR consumed_at >= created_at)
);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.chat_rate_limits (
    limit_key TEXT PRIMARY KEY,
    window_start_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    request_count BIGINT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_chat_rate_limits_request_count_non_negative
        CHECK (request_count >= 0),
    CONSTRAINT chk_chat_rate_limits_updated_at_after_window_start_at
        CHECK (updated_at >= window_start_at)
);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.push_tokens (
    token VARCHAR(512) PRIMARY KEY,
    device_id VARCHAR(24) NOT NULL,
    platform VARCHAR(30),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_push_tokens_last_seen_at_after_created_at
        CHECK (last_seen_at >= created_at)
);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.contact_rules (
    device_id VARCHAR(24) NOT NULL,
    peer_id VARCHAR(24) NOT NULL,
    blocked INTEGER NOT NULL DEFAULT 0,
    hidden INTEGER NOT NULL DEFAULT 0,
    muted INTEGER NOT NULL DEFAULT 0,
    starred INTEGER NOT NULL DEFAULT 0,
    pinned INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_contact_rules_updated_at_after_created_at
        CHECK (updated_at >= created_at),
    PRIMARY KEY (device_id, peer_id)
);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.group_prefs (
    device_id VARCHAR(24) NOT NULL,
    group_id VARCHAR(36) NOT NULL,
    muted INTEGER NOT NULL DEFAULT 0,
    pinned INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_group_prefs_updated_at_after_created_at
        CHECK (updated_at >= created_at),
    PRIMARY KEY (device_id, group_id)
);

CREATE INDEX IF NOT EXISTS idx_messages_recipient_created_id
    ON __CHAT_SCHEMA__.messages(recipient_id, created_at DESC, id DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uq_messages_sender_recipient_nonce
    ON __CHAT_SCHEMA__.messages(sender_id, recipient_id, nonce_b64);

CREATE INDEX IF NOT EXISTS idx_group_members_device_group
    ON __CHAT_SCHEMA__.group_members(device_id, group_id);
CREATE INDEX IF NOT EXISTS idx_group_members_group_joined_device
    ON __CHAT_SCHEMA__.group_members(group_id, joined_at, device_id);

CREATE INDEX IF NOT EXISTS idx_group_messages_group_sealed_created_id
    ON __CHAT_SCHEMA__.group_messages(group_id, created_at DESC, id DESC)
    WHERE kind = 'sealed';
CREATE UNIQUE INDEX IF NOT EXISTS uq_group_messages_group_sender_nonce
    ON __CHAT_SCHEMA__.group_messages(group_id, sender_id, nonce_b64);

CREATE INDEX IF NOT EXISTS idx_groups_created_id
    ON __CHAT_SCHEMA__.groups(created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_messages_expire_at_gc
    ON __CHAT_SCHEMA__.messages(expire_at)
    WHERE expire_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_group_messages_expire_at_gc
    ON __CHAT_SCHEMA__.group_messages(expire_at)
    WHERE expire_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_chat_otk_available
    ON __CHAT_SCHEMA__.chat_one_time_prekeys(device_id, consumed_at, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS uq_chat_mailboxes_active_owner
    ON __CHAT_SCHEMA__.chat_mailboxes(owner_device_id)
    WHERE COALESCE(active::text, '') IN ('1', 't', 'true');
CREATE INDEX IF NOT EXISTS idx_chat_mailboxes_inactive_gc
    ON __CHAT_SCHEMA__.chat_mailboxes((COALESCE(rotated_at, created_at)))
    WHERE COALESCE(active::text, '') IN ('0', 'f', 'false');
CREATE INDEX IF NOT EXISTS idx_chat_mailbox_messages_poll
    ON __CHAT_SCHEMA__.chat_mailbox_messages(token_hash, consumed_at, created_at);
CREATE INDEX IF NOT EXISTS idx_chat_mailbox_messages_expire_at_gc
    ON __CHAT_SCHEMA__.chat_mailbox_messages(expire_at)
    WHERE expire_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_chat_mailbox_messages_consumed_at_gc
    ON __CHAT_SCHEMA__.chat_mailbox_messages(consumed_at)
    WHERE consumed_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_chat_rate_limits_updated_at
    ON __CHAT_SCHEMA__.chat_rate_limits(updated_at);

CREATE UNIQUE INDEX IF NOT EXISTS uq_push_tokens_device_id
    ON __CHAT_SCHEMA__.push_tokens(device_id);

CREATE INDEX IF NOT EXISTS idx_contact_rules_device_blocked
    ON __CHAT_SCHEMA__.contact_rules(device_id, peer_id)
    WHERE COALESCE(blocked::text, '') IN ('1', 't', 'true');
CREATE INDEX IF NOT EXISTS idx_contact_rules_device_hidden
    ON __CHAT_SCHEMA__.contact_rules(device_id, peer_id)
    WHERE COALESCE(hidden::text, '') IN ('1', 't', 'true');
CREATE INDEX IF NOT EXISTS idx_contact_rules_device_muted
    ON __CHAT_SCHEMA__.contact_rules(device_id, peer_id)
    WHERE COALESCE(muted::text, '') IN ('1', 't', 'true');

CREATE INDEX IF NOT EXISTS idx_group_prefs_group_id
    ON __CHAT_SCHEMA__.group_prefs(group_id);
