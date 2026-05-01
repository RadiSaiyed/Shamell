CREATE TABLE IF NOT EXISTS auth_coach_admin_partner_onboarding_actions (
    operator_id TEXT PRIMARY KEY,
    workflow_status TEXT NOT NULL,
    last_action TEXT NOT NULL,
    owner_account_id TEXT,
    due_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL,
    updated_by_account_id TEXT NOT NULL,
    note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_coach_admin_partner_onboarding_actions_workflow_status
        CHECK (workflow_status IN ('draft', 'in_review', 'action_required', 'approved', 'suspended')),
    CONSTRAINT chk_auth_coach_admin_partner_onboarding_actions_last_action
        CHECK (last_action IN ('claim', 'start_review', 'request_documents', 'approve', 'suspend', 'reset'))
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_admin_partner_onboarding_actions_workflow_status
    ON auth_coach_admin_partner_onboarding_actions(workflow_status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_auth_coach_admin_partner_onboarding_actions_owner
    ON auth_coach_admin_partner_onboarding_actions(owner_account_id, updated_at DESC);
