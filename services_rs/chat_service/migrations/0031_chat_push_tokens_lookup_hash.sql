ALTER TABLE __CHAT_SCHEMA__.push_tokens
    ADD COLUMN IF NOT EXISTS token_lookup_hash VARCHAR(64);

CREATE UNIQUE INDEX IF NOT EXISTS uq_push_tokens_lookup_hash
    ON __CHAT_SCHEMA__.push_tokens(token_lookup_hash);
