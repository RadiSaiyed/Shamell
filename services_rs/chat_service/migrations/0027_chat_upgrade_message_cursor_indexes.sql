CREATE INDEX IF NOT EXISTS idx_messages_recipient_created_id
    ON __CHAT_SCHEMA__.messages(recipient_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_group_messages_group_sealed_created_id
    ON __CHAT_SCHEMA__.group_messages(group_id, created_at DESC, id DESC)
    WHERE kind = 'sealed';

DROP INDEX IF EXISTS __CHAT_SCHEMA__.idx_messages_recipient_created;
DROP INDEX IF EXISTS __CHAT_SCHEMA__.idx_group_messages_group_created;
