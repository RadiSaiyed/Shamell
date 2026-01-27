from __future__ import annotations

from typing import Any, Dict

import apps.bff.app.main as bff  # type: ignore[import]


def test_admin_stats_requires_admin(client, user_auth, admin_auth):
  # Unprivileged user -> 401/403
  resp = client.get("/admin/stats", headers=user_auth.headers())
  assert resp.status_code in (401, 403)

  # Admin/Superadmin via env/roles
  def fake_roles(phone: str) -> list[str]:
    if phone == admin_auth.phone:
      return ["admin"]
    return []

  bff._AUDIT_EVENTS.clear()  # type: ignore[attr-defined]
  bff._METRICS.clear()       # type: ignore[attr-defined]

  # Inject simple metrics
  bff._METRICS.extend([  # type: ignore[attr-defined]
      {"type": "sample", "data": {"metric": "pay_send_ms", "value_ms": 100.0}},
      {"type": "sample", "data": {"metric": "pay_send_ms", "value_ms": 200.0}},
      {"type": "action", "data": {"label": "pay_send_ok"}},
  ])

  # Inject some guardrail audit events
  bff._AUDIT_EVENTS.extend(  # type: ignore[attr-defined]
      [
          {"action": "taxi_payout_guardrail", "driver_id": "drv1"},
          {"action": "taxi_cancel_guardrail", "driver_id": "drv1"},
          {"action": "taxi_cancel_guardrail", "driver_id": "drv2"},
      ]
  )

  # Monkeypatch roles
  import apps.bff.app.main as bff_mod  # type: ignore[import]
  bff_mod._get_effective_roles = fake_roles  # type: ignore[assignment]

  resp2 = client.get("/admin/stats", headers=admin_auth.headers())
  assert resp2.status_code == 200
  data: Dict[str, Any] = resp2.json()

  assert data.get("total_events") == 3
  samples = data.get("samples") or {}
  pay = samples.get("pay_send_ms") or {}
  # Zwei Samples -> count=2, avg=150, min=100, max=200
  assert int(pay.get("count") or 0) == 2
  assert 140 <= pay.get("avg_ms", 0) <= 160
  assert int(pay.get("min_ms") or 0) == 100
  assert int(pay.get("max_ms") or 0) == 200

  guardrails = data.get("guardrails") or {}
  # Expect 1 payout guardrail and 2 cancel guardrails
  assert guardrails.get("taxi_payout_guardrail") == 1
  assert guardrails.get("taxi_cancel_guardrail") == 2
