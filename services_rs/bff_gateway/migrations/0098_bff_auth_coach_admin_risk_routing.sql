ALTER TABLE auth_coach_admin_risk_actions
    ADD COLUMN IF NOT EXISTS owner_team TEXT;

ALTER TABLE auth_coach_admin_risk_actions
    ADD COLUMN IF NOT EXISTS snooze_reason TEXT;

CREATE INDEX IF NOT EXISTS idx_auth_coach_admin_risk_actions_owner_team
    ON auth_coach_admin_risk_actions(owner_team, updated_at DESC);
