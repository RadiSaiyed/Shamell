CREATE TABLE IF NOT EXISTS auth_coach_admin_risk_actions (
    risk_id TEXT PRIMARY KEY,
    workflow_status TEXT NOT NULL,
    owner_account_id TEXT,
    snoozed_until TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL,
    updated_by_account_id TEXT NOT NULL,
    note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_coach_admin_risk_actions_workflow_status
        CHECK (workflow_status IN ('active', 'acknowledged', 'snoozed'))
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_admin_risk_actions_workflow_status
    ON auth_coach_admin_risk_actions(workflow_status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_auth_coach_admin_risk_actions_owner
    ON auth_coach_admin_risk_actions(owner_account_id, updated_at DESC);
