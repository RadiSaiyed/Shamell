CREATE TABLE IF NOT EXISTS auth_idp_subject_links (
    id BIGSERIAL PRIMARY KEY,
    idp_provider VARCHAR(64) NOT NULL,
    issuer TEXT NOT NULL,
    subject TEXT NOT NULL,
    account_id VARCHAR(64) NOT NULL,
    email VARCHAR(320),
    phone VARCHAR(32),
    display_name VARCHAR(180),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_exchanged_at TIMESTAMPTZ,
    CONSTRAINT fk_auth_idp_subject_links_account_id
        FOREIGN KEY (account_id) REFERENCES auth_accounts(account_id) ON DELETE CASCADE,
    CONSTRAINT uq_auth_idp_subject_links_subject
        UNIQUE (idp_provider, issuer, subject),
    CONSTRAINT chk_auth_idp_subject_links_provider_non_empty
        CHECK (length(btrim(idp_provider)) > 0),
    CONSTRAINT chk_auth_idp_subject_links_issuer_non_empty
        CHECK (length(btrim(issuer)) > 0),
    CONSTRAINT chk_auth_idp_subject_links_subject_non_empty
        CHECK (length(btrim(subject)) > 0)
);

CREATE INDEX IF NOT EXISTS idx_auth_idp_subject_links_account_id
    ON auth_idp_subject_links(account_id);

CREATE INDEX IF NOT EXISTS idx_auth_idp_subject_links_issuer_subject
    ON auth_idp_subject_links(issuer, subject);

CREATE INDEX IF NOT EXISTS idx_auth_idp_subject_links_last_exchanged_at
    ON auth_idp_subject_links(last_exchanged_at DESC NULLS LAST);
