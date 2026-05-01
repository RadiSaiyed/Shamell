CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.message_deletions (
    message_id VARCHAR(36) NOT NULL REFERENCES __CHAT_SCHEMA__.messages(id) ON DELETE CASCADE,
    device_id VARCHAR(24) NOT NULL REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE,
    deleted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (message_id, device_id)
);

CREATE INDEX IF NOT EXISTS idx_message_deletions_device_deleted
    ON __CHAT_SCHEMA__.message_deletions(device_id, deleted_at DESC, message_id DESC);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.message_tombstones (
    message_id VARCHAR(36) PRIMARY KEY REFERENCES __CHAT_SCHEMA__.messages(id) ON DELETE CASCADE,
    actor_device_id VARCHAR(24) NOT NULL REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE,
    reason VARCHAR(64),
    deleted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_message_tombstones_actor_deleted
    ON __CHAT_SCHEMA__.message_tombstones(actor_device_id, deleted_at DESC, message_id DESC);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.message_edit_history (
    message_id VARCHAR(36) NOT NULL REFERENCES __CHAT_SCHEMA__.messages(id) ON DELETE CASCADE,
    revision INTEGER NOT NULL,
    editor_device_id VARCHAR(24) NOT NULL REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE,
    protocol_version VARCHAR(24) NOT NULL DEFAULT 'v2_libsignal',
    sender_dh_pub VARCHAR(255),
    nonce_b64 VARCHAR(64) NOT NULL,
    box_b64 TEXT NOT NULL,
    key_id VARCHAR(64),
    prev_key_id VARCHAR(64),
    edited_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (message_id, revision),
    CONSTRAINT chk_message_edit_history_revision CHECK (revision > 0)
);

CREATE INDEX IF NOT EXISTS idx_message_edit_history_message_edited
    ON __CHAT_SCHEMA__.message_edit_history(message_id, edited_at DESC, revision DESC);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.conversation_events (
    id BIGSERIAL PRIMARY KEY,
    device_id VARCHAR(24) NOT NULL REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE,
    peer_id VARCHAR(24),
    event_type VARCHAR(64) NOT NULL,
    resource_id VARCHAR(96) NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_conversation_events_event_type CHECK (char_length(trim(event_type)) BETWEEN 1 AND 64),
    CONSTRAINT chk_conversation_events_resource_id CHECK (char_length(trim(resource_id)) BETWEEN 1 AND 96)
);

CREATE INDEX IF NOT EXISTS idx_conversation_events_device_id
    ON __CHAT_SCHEMA__.conversation_events(device_id, id ASC);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.voice_transcript_jobs (
    id VARCHAR(36) PRIMARY KEY,
    message_id VARCHAR(36) NOT NULL REFERENCES __CHAT_SCHEMA__.messages(id) ON DELETE CASCADE,
    device_id VARCHAR(24) NOT NULL REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE,
    status VARCHAR(16) NOT NULL DEFAULT 'queued',
    language VARCHAR(16),
    error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (message_id, device_id),
    CONSTRAINT chk_voice_transcript_jobs_status CHECK (status IN ('queued', 'processing', 'done', 'failed'))
);

CREATE INDEX IF NOT EXISTS idx_voice_transcript_jobs_device_status_updated
    ON __CHAT_SCHEMA__.voice_transcript_jobs(device_id, status, updated_at DESC, id DESC);

ALTER TABLE __CHAT_SCHEMA__.message_reports
    ADD COLUMN IF NOT EXISTS status VARCHAR(16) NOT NULL DEFAULT 'open',
    ADD COLUMN IF NOT EXISTS resolved_by VARCHAR(24),
    ADD COLUMN IF NOT EXISTS resolution_note TEXT,
    ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMPTZ;

ALTER TABLE __CHAT_SCHEMA__.message_reports
    DROP CONSTRAINT IF EXISTS chk_message_reports_status;

ALTER TABLE __CHAT_SCHEMA__.message_reports
    ADD CONSTRAINT chk_message_reports_status
    CHECK (status IN ('open', 'reviewing', 'resolved', 'dismissed'));

CREATE INDEX IF NOT EXISTS idx_message_reports_status_created
    ON __CHAT_SCHEMA__.message_reports(status, created_at DESC, id DESC);
