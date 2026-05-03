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
                'payments_favorites_create',
                'payments_favorites_delete',
                'payments_requests_create',
                'payments_requests_accept',
                'payments_requests_cancel',
                'biometric_enroll',
                'biometric_login'
            )
        ) NOT VALID;
END $$;
