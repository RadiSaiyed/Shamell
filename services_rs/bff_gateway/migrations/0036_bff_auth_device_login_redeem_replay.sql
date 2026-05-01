ALTER TABLE device_login_challenges
    ADD COLUMN IF NOT EXISTS redeemed_at TIMESTAMPTZ;

ALTER TABLE device_login_challenges
    ADD COLUMN IF NOT EXISTS redeemed_client_ip_hash VARCHAR(64);

ALTER TABLE device_login_challenges
    ADD COLUMN IF NOT EXISTS redeemed_user_agent_hash VARCHAR(64);

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_device_login_challenges_status_known'
          AND conrelid = 'device_login_challenges'::regclass
    ) THEN
        ALTER TABLE device_login_challenges
            DROP CONSTRAINT chk_device_login_challenges_status_known;
    END IF;

    ALTER TABLE device_login_challenges
        ADD CONSTRAINT chk_device_login_challenges_status_known
        CHECK (status IN ('pending', 'approved', 'redeemed')) NOT VALID;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_device_login_challenges_approved_at_matches_status'
          AND conrelid = 'device_login_challenges'::regclass
    ) THEN
        ALTER TABLE device_login_challenges
            DROP CONSTRAINT chk_device_login_challenges_approved_at_matches_status;
    END IF;

    ALTER TABLE device_login_challenges
        ADD CONSTRAINT chk_device_login_challenges_approved_at_matches_status
        CHECK (
            (
                status = 'pending'
                AND approved_at IS NULL
                AND redeemed_at IS NULL
                AND redeemed_client_ip_hash IS NULL
                AND redeemed_user_agent_hash IS NULL
            )
            OR (
                status = 'approved'
                AND approved_at IS NOT NULL
                AND redeemed_at IS NULL
                AND redeemed_client_ip_hash IS NULL
                AND redeemed_user_agent_hash IS NULL
            )
            OR (
                status = 'redeemed'
                AND approved_at IS NOT NULL
                AND redeemed_at IS NOT NULL
                AND redeemed_client_ip_hash IS NOT NULL
                AND redeemed_user_agent_hash IS NOT NULL
            )
        ) NOT VALID;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_device_login_challenges_redeemed_at_after_approved_at'
          AND conrelid = 'device_login_challenges'::regclass
    ) THEN
        ALTER TABLE device_login_challenges
            ADD CONSTRAINT chk_device_login_challenges_redeemed_at_after_approved_at
            CHECK (
                redeemed_at IS NULL
                OR (approved_at IS NOT NULL AND redeemed_at >= approved_at)
            ) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_device_login_challenges_redeemed_at_before_expires_at'
          AND conrelid = 'device_login_challenges'::regclass
    ) THEN
        ALTER TABLE device_login_challenges
            ADD CONSTRAINT chk_device_login_challenges_redeemed_at_before_expires_at
            CHECK (
                redeemed_at IS NULL OR redeemed_at <= expires_at
            ) NOT VALID;
    END IF;
END $$;
