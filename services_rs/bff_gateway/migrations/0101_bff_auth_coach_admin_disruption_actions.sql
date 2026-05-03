CREATE TABLE IF NOT EXISTS auth_coach_admin_disruption_actions (
    trip_id TEXT PRIMARY KEY,
    workflow_status TEXT NOT NULL,
    disruption_kind TEXT,
    last_action TEXT NOT NULL,
    delay_minutes BIGINT,
    queued_reaccommodation_count BIGINT NOT NULL DEFAULT 0,
    reason TEXT,
    updated_at TIMESTAMPTZ NOT NULL,
    updated_by_account_id TEXT NOT NULL,
    note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_auth_coach_admin_disruption_actions_workflow_status
        CHECK (workflow_status IN ('scheduled', 'monitoring', 'action_required', 'resolved')),
    CONSTRAINT chk_auth_coach_admin_disruption_actions_kind
        CHECK (disruption_kind IS NULL OR disruption_kind IN ('delay', 'cancelled')),
    CONSTRAINT chk_auth_coach_admin_disruption_actions_last_action
        CHECK (last_action IN ('mark_delayed', 'mark_cancelled', 'queue_reaccommodation', 'resolve', 'seed')),
    CONSTRAINT chk_auth_coach_admin_disruption_actions_delay_minutes
        CHECK (delay_minutes IS NULL OR delay_minutes BETWEEN 1 AND 720),
    CONSTRAINT chk_auth_coach_admin_disruption_actions_queue_count
        CHECK (queued_reaccommodation_count >= 0)
);

CREATE INDEX IF NOT EXISTS idx_auth_coach_admin_disruption_actions_workflow_status
    ON auth_coach_admin_disruption_actions(workflow_status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_auth_coach_admin_disruption_actions_kind
    ON auth_coach_admin_disruption_actions(disruption_kind, updated_at DESC);
