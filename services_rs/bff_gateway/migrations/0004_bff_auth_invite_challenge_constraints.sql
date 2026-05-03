DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_contact_invites_max_uses_positive'
          AND conrelid = 'auth_contact_invites'::regclass
    ) THEN
        ALTER TABLE auth_contact_invites
            ADD CONSTRAINT chk_auth_contact_invites_max_uses_positive
            CHECK (max_uses > 0) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_contact_invites_use_count_non_negative'
          AND conrelid = 'auth_contact_invites'::regclass
    ) THEN
        ALTER TABLE auth_contact_invites
            ADD CONSTRAINT chk_auth_contact_invites_use_count_non_negative
            CHECK (use_count >= 0) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_contact_invites_use_count_le_max_uses'
          AND conrelid = 'auth_contact_invites'::regclass
    ) THEN
        ALTER TABLE auth_contact_invites
            ADD CONSTRAINT chk_auth_contact_invites_use_count_le_max_uses
            CHECK (use_count <= max_uses) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_device_login_challenges_approved_at_matches_status'
          AND conrelid = 'device_login_challenges'::regclass
    ) THEN
        ALTER TABLE device_login_challenges
            ADD CONSTRAINT chk_device_login_challenges_approved_at_matches_status
            CHECK (
                (status = 'pending' AND approved_at IS NULL)
                OR (status = 'approved' AND approved_at IS NOT NULL)
            ) NOT VALID;
    END IF;
END $$;
