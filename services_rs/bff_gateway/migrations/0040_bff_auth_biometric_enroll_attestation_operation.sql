DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_auth_payment_attestation_challenges_operation_known'
          AND conrelid = 'auth_payment_attestation_challenges'::regclass
    ) THEN
        ALTER TABLE auth_payment_attestation_challenges
            DROP CONSTRAINT chk_auth_payment_attestation_challenges_operation_known;
    END IF;

    ALTER TABLE auth_payment_attestation_challenges
        ADD CONSTRAINT chk_auth_payment_attestation_challenges_operation_known
        CHECK (
            operation IN (
                'payments_transfer',
                'payments_topup',
                'payments_requests_accept',
                'biometric_enroll'
            )
        ) NOT VALID;
END $$;
