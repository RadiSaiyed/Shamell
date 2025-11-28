from __future__ import annotations

from typing import Any, Dict

import apps.bff.app.main as bff  # type: ignore[import]


def test_admin_guardrails_dashboard_lists_only_guardrail_actions(client, monkeypatch):
    """
    Feed the audit buffer with guardrail and non-guardrail events and
    check that /admin/guardrails only renders guardrail actions.
    """

    # Simulate a few audit events
    bff._AUDIT_EVENTS.clear()  # type: ignore[attr-defined]
    bff._audit("taxi_payout_guardrail", phone="+491700000001", driver_id="drv1", ride_id="r1", amount_cents=50000)
    bff._audit("taxi_cancel_guardrail", phone="+491700000002", driver_id="drv2", ride_id="r2", amount_cents=400000)
    bff._audit("admin_role_add", phone="+491700000003", target_phone="+491700000004")

    # Bypass the admin gate for this test
    monkeypatch.setattr(bff, "_require_admin_v2", lambda request: "admin@test", raising=False)

    resp = client.get("/admin/guardrails")
    assert resp.status_code == 200
    html = resp.text

    # Guardrail actions must be visible
    assert "taxi_payout_guardrail" in html
    assert "taxi_cancel_guardrail" in html

    # Other audit actions must not appear in the guardrail table
    assert "admin_role_add" not in html
