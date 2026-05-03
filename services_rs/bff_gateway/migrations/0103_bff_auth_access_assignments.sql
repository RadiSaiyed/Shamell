CREATE TABLE IF NOT EXISTS auth_role_definitions (
    role_id VARCHAR(96) PRIMARY KEY,
    legacy_role VARCHAR(128),
    scope_mode VARCHAR(32) NOT NULL DEFAULT 'none',
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_role_definitions_role_id_non_empty
        CHECK (char_length(btrim(role_id)) > 0),
    CONSTRAINT chk_auth_role_definitions_scope_mode_known
        CHECK (scope_mode IN ('none', 'platform', 'operator', 'official_account'))
);

CREATE TABLE IF NOT EXISTS auth_role_assignments (
    id BIGSERIAL PRIMARY KEY,
    subject_account_id VARCHAR(64) REFERENCES auth_accounts(account_id) ON DELETE CASCADE,
    subject_phone VARCHAR(32),
    role_id VARCHAR(96) NOT NULL REFERENCES auth_role_definitions(role_id) ON DELETE RESTRICT,
    created_by_account_id VARCHAR(64) REFERENCES auth_accounts(account_id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_by_account_id VARCHAR(64) REFERENCES auth_accounts(account_id) ON DELETE SET NULL,
    revoked_at TIMESTAMPTZ,
    revoke_reason TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT chk_auth_role_assignments_subject_present
        CHECK (subject_account_id IS NOT NULL OR char_length(btrim(COALESCE(subject_phone, ''))) > 0),
    CONSTRAINT chk_auth_role_assignments_revoked_after_created
        CHECK (revoked_at IS NULL OR revoked_at >= created_at)
);

CREATE INDEX IF NOT EXISTS idx_auth_role_assignments_subject_account_active_created
    ON auth_role_assignments(subject_account_id, created_at DESC, id DESC)
    WHERE revoked_at IS NULL AND subject_account_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_auth_role_assignments_subject_phone_active_created
    ON auth_role_assignments(subject_phone, created_at DESC, id DESC)
    WHERE revoked_at IS NULL AND subject_phone IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_auth_role_assignments_role_active_created
    ON auth_role_assignments(role_id, created_at DESC, id DESC)
    WHERE revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS auth_scope_assignments (
    id BIGSERIAL PRIMARY KEY,
    role_assignment_id BIGINT NOT NULL REFERENCES auth_role_assignments(id) ON DELETE CASCADE,
    scope_kind VARCHAR(32) NOT NULL,
    scope_value VARCHAR(128),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_scope_assignments_scope_kind_known
        CHECK (scope_kind IN ('platform', 'operator', 'official_account')),
    CONSTRAINT chk_auth_scope_assignments_platform_value_null
        CHECK (
            (scope_kind = 'platform' AND scope_value IS NULL)
            OR
            (scope_kind IN ('operator', 'official_account') AND char_length(btrim(COALESCE(scope_value, ''))) > 0)
        )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_auth_scope_assignments_role_kind_value
    ON auth_scope_assignments(role_assignment_id, scope_kind, COALESCE(scope_value, ''));

CREATE INDEX IF NOT EXISTS idx_auth_scope_assignments_scope_lookup
    ON auth_scope_assignments(scope_kind, scope_value, role_assignment_id);

INSERT INTO auth_role_definitions (role_id, legacy_role, scope_mode, description)
VALUES
    ('owner.daily_admin', 'superadmin', 'platform', 'Daily owner role for internal Shamell administration'),
    ('platform.admin', 'admin', 'platform', 'Platform administrator'),
    ('platform.ops_manager', 'ops', 'platform', 'Platform operations manager'),
    ('platform.support_l1', 'support_l1', 'platform', 'Platform support L1'),
    ('platform.support_l2', 'support_l2', 'platform', 'Platform support L2'),
    ('platform.finance_admin', 'finance', 'platform', 'Platform finance administrator'),
    ('platform.compliance_admin', 'compliance_risk', 'platform', 'Platform compliance administrator'),
    ('audit.readonly', 'bi_audit_read_only', 'platform', 'Audit read-only access'),
    ('rides.driver', 'ride_driver', 'none', 'Ride driver access'),
    ('rides.driver_ops', 'driver_ops', 'none', 'Ride operator access'),
    ('rides.city_manager', 'city_manager', 'none', 'Ride city manager access'),
    ('wallet.operator', 'merchant', 'none', 'Wallet operator access'),
    ('wallet.cash_agent', 'cashout_operator', 'none', 'Cash agent access'),
    ('legacy.seller', 'seller', 'platform', 'Legacy seller compatibility role'),
    ('legacy.marketing', 'marketing', 'none', 'Legacy marketing compatibility role'),
    ('official.account_owner', NULL, 'official_account', 'Official account scoped owner'),
    ('coach.operator_admin', NULL, 'operator', 'Coach operator admin'),
    ('coach.operator_staff', NULL, 'operator', 'Coach operator staff'),
    ('coach.boarding_agent', NULL, 'operator', 'Coach boarding agent'),
    ('coach.settlement_readonly', NULL, 'operator', 'Coach settlement read-only'),
    ('legacy.coach_operator_scope', NULL, 'operator', 'Legacy coach operator scope compatibility')
ON CONFLICT (role_id) DO UPDATE
SET legacy_role = EXCLUDED.legacy_role,
    scope_mode = EXCLUDED.scope_mode,
    description = EXCLUDED.description;
