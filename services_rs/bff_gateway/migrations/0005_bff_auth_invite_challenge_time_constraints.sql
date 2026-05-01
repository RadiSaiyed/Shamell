DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_contact_invites_expires_after_created_at'
          AND conrelid = 'auth_contact_invites'::regclass
    ) THEN
        ALTER TABLE auth_contact_invites
            ADD CONSTRAINT chk_auth_contact_invites_expires_after_created_at
            CHECK (expires_at > created_at) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_contact_invites_last_redeemed_at_after_created_at'
          AND conrelid = 'auth_contact_invites'::regclass
    ) THEN
        ALTER TABLE auth_contact_invites
            ADD CONSTRAINT chk_auth_contact_invites_last_redeemed_at_after_created_at
            CHECK (last_redeemed_at IS NULL OR last_redeemed_at >= created_at) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_contact_invites_last_redeemed_at_before_expires_at'
          AND conrelid = 'auth_contact_invites'::regclass
    ) THEN
        ALTER TABLE auth_contact_invites
            ADD CONSTRAINT chk_auth_contact_invites_last_redeemed_at_before_expires_at
            CHECK (last_redeemed_at IS NULL OR last_redeemed_at <= expires_at) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_contact_invites_revoked_at_after_created_at'
          AND conrelid = 'auth_contact_invites'::regclass
    ) THEN
        ALTER TABLE auth_contact_invites
            ADD CONSTRAINT chk_auth_contact_invites_revoked_at_after_created_at
            CHECK (revoked_at IS NULL OR revoked_at >= created_at) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_contact_invites_revoked_at_before_expires_at'
          AND conrelid = 'auth_contact_invites'::regclass
    ) THEN
        ALTER TABLE auth_contact_invites
            ADD CONSTRAINT chk_auth_contact_invites_revoked_at_before_expires_at
            CHECK (revoked_at IS NULL OR revoked_at <= expires_at) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_device_login_challenges_expires_after_created_at'
          AND conrelid = 'device_login_challenges'::regclass
    ) THEN
        ALTER TABLE device_login_challenges
            ADD CONSTRAINT chk_device_login_challenges_expires_after_created_at
            CHECK (expires_at > created_at) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_device_login_challenges_approved_at_after_created_at'
          AND conrelid = 'device_login_challenges'::regclass
    ) THEN
        ALTER TABLE device_login_challenges
            ADD CONSTRAINT chk_device_login_challenges_approved_at_after_created_at
            CHECK (approved_at IS NULL OR approved_at >= created_at) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_device_login_challenges_approved_at_before_expires_at'
          AND conrelid = 'device_login_challenges'::regclass
    ) THEN
        ALTER TABLE device_login_challenges
            ADD CONSTRAINT chk_device_login_challenges_approved_at_before_expires_at
            CHECK (approved_at IS NULL OR approved_at <= expires_at) NOT VALID;
    END IF;
END $$;
