ALTER TABLE __PAYMENTS_SCHEMA__.roles
    DROP CONSTRAINT IF EXISTS chk_roles_role_known;

ALTER TABLE __PAYMENTS_SCHEMA__.roles
    ADD CONSTRAINT chk_roles_role_known
    CHECK (
        role = ANY (
            ARRAY[
                'merchant',
                'qr_seller',
                'cashout_operator',
                'driver',
                'ride_driver',
                'driver_ops',
                'city_manager',
                'support_l1',
                'support_l2',
                'finance',
                'compliance_risk',
                'marketing',
                'bi_audit_read_only',
                'admin',
                'superadmin',
                'seller',
                'ops'
            ]
        )
        OR role ~ '^official_owner:([*]|[a-z0-9_.-]{1,64})$'
    ) NOT VALID;
