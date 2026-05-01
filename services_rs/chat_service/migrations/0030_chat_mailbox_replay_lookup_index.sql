CREATE INDEX IF NOT EXISTS idx_chat_mailbox_messages_replay_lookup
    ON __CHAT_SCHEMA__.chat_mailbox_messages(token_hash, md5(envelope_b64), created_at DESC)
    WHERE consumed_at IS NULL;
