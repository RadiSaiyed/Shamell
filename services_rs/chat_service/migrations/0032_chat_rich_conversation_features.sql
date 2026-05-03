CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.message_reactions (
    message_id VARCHAR(36) NOT NULL REFERENCES __CHAT_SCHEMA__.messages(id) ON DELETE CASCADE,
    actor_device_id VARCHAR(24) NOT NULL REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE,
    emoji VARCHAR(32) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (message_id, actor_device_id),
    CONSTRAINT chk_message_reactions_emoji_nonempty CHECK (char_length(trim(emoji)) BETWEEN 1 AND 16)
);

CREATE INDEX IF NOT EXISTS idx_message_reactions_message_updated
    ON __CHAT_SCHEMA__.message_reactions(message_id, updated_at DESC, actor_device_id ASC);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.message_pins (
    message_id VARCHAR(36) NOT NULL REFERENCES __CHAT_SCHEMA__.messages(id) ON DELETE CASCADE,
    device_id VARCHAR(24) NOT NULL REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE,
    peer_id VARCHAR(24) NOT NULL REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE,
    pinned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (message_id, device_id)
);

CREATE INDEX IF NOT EXISTS idx_message_pins_device_peer_pinned
    ON __CHAT_SCHEMA__.message_pins(device_id, peer_id, pinned_at DESC, message_id DESC);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.message_reports (
    id VARCHAR(36) PRIMARY KEY,
    message_id VARCHAR(36) NOT NULL REFERENCES __CHAT_SCHEMA__.messages(id) ON DELETE CASCADE,
    reporter_device_id VARCHAR(24) NOT NULL REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE,
    reason VARCHAR(64) NOT NULL,
    note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (message_id, reporter_device_id),
    CONSTRAINT chk_message_reports_reason_nonempty CHECK (char_length(trim(reason)) BETWEEN 1 AND 64)
);

CREATE INDEX IF NOT EXISTS idx_message_reports_reporter_created
    ON __CHAT_SCHEMA__.message_reports(reporter_device_id, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.call_logs (
    id VARCHAR(64) NOT NULL,
    device_id VARCHAR(24) NOT NULL REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE,
    peer_id VARCHAR(24) NOT NULL REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE,
    direction VARCHAR(8) NOT NULL,
    kind VARCHAR(8) NOT NULL,
    accepted BOOLEAN NOT NULL DEFAULT FALSE,
    duration_seconds INTEGER NOT NULL DEFAULT 0,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (id, device_id),
    CONSTRAINT chk_call_logs_direction CHECK (direction IN ('in', 'out')),
    CONSTRAINT chk_call_logs_kind CHECK (kind IN ('voice', 'video')),
    CONSTRAINT chk_call_logs_duration CHECK (duration_seconds BETWEEN 0 AND 86400)
);

CREATE INDEX IF NOT EXISTS idx_call_logs_device_peer_started
    ON __CHAT_SCHEMA__.call_logs(device_id, peer_id, started_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS __CHAT_SCHEMA__.voice_transcripts (
    message_id VARCHAR(36) NOT NULL REFERENCES __CHAT_SCHEMA__.messages(id) ON DELETE CASCADE,
    device_id VARCHAR(24) NOT NULL REFERENCES __CHAT_SCHEMA__.devices(id) ON DELETE CASCADE,
    transcript TEXT NOT NULL,
    language VARCHAR(16),
    confidence DOUBLE PRECISION,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (message_id, device_id),
    CONSTRAINT chk_voice_transcripts_transcript_nonempty CHECK (char_length(trim(transcript)) BETWEEN 1 AND 4000),
    CONSTRAINT chk_voice_transcripts_confidence CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1))
);

CREATE INDEX IF NOT EXISTS idx_voice_transcripts_device_updated
    ON __CHAT_SCHEMA__.voice_transcripts(device_id, updated_at DESC, message_id DESC);
