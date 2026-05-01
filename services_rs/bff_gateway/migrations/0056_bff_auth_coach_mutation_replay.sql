CREATE TABLE IF NOT EXISTS auth_coach_mutation_replays (
    account_id TEXT NOT NULL,
    command TEXT NOT NULL,
    idempotency_key TEXT NOT NULL,
    request_fingerprint TEXT NOT NULL,
    response_json JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (account_id, command, idempotency_key),
    CONSTRAINT chk_auth_coach_mutation_replays_account_id_nonempty
        CHECK (btrim(account_id) <> ''),
    CONSTRAINT chk_auth_coach_mutation_replays_command_nonempty
        CHECK (btrim(command) <> ''),
    CONSTRAINT chk_auth_coach_mutation_replays_idempotency_key_nonempty
        CHECK (btrim(idempotency_key) <> ''),
    CONSTRAINT chk_auth_coach_mutation_replays_request_fingerprint_nonempty
        CHECK (btrim(request_fingerprint) <> '')
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_mutation_replays_created
    ON auth_coach_mutation_replays(created_at DESC);
