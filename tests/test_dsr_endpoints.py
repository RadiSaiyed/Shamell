from __future__ import annotations

import apps.bff.app.main as bff  # type: ignore[import]


def test_me_dsr_endpoints_require_auth(client):
  # Ohne Auth (kein X-Test-Phone / Cookie) -> 401
  resp_exp = client.post("/me/dsr/export", json={"reason": "test"})
  resp_del = client.post("/me/dsr/delete", json={"reason": "test"})
  assert resp_exp.status_code == 401
  assert resp_del.status_code == 401


def test_me_dsr_export_and_delete_emit_audit(client, monkeypatch):
  # Lege Audit-Puffer frei und injiziere Test-Phone via Header (ENV=test)
  bff._AUDIT_EVENTS.clear()  # type: ignore[attr-defined]

  headers = {"X-Test-Phone": "+491700000999"}

  resp_exp = client.post(
      "/me/dsr/export",
      json={"reason": "export all", "contact": "user@example.com"},
      headers=headers,
  )
  resp_del = client.post(
      "/me/dsr/delete",
      json={"reason": "delete me", "contact": "user@example.com"},
      headers=headers,
  )

  assert resp_exp.status_code == 200
  assert resp_exp.json()["kind"] == "export"
  assert resp_del.status_code == 200
  assert resp_del.json()["kind"] == "delete"

  # Stelle sicher, dass Audit-Events geschrieben wurden
  actions = [e.get("action") for e in bff._AUDIT_EVENTS]
  assert "dsr_export_request" in actions
  assert "dsr_delete_request" in actions

