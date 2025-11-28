from __future__ import annotations

from typing import Any, Dict

import apps.bff.app.main as bff  # type: ignore[import]


class _DummyPaySessionCtx:
  def __enter__(self) -> object:  # pragma: no cover - trivial
    return object()

  def __exit__(self, exc_type, exc, tb) -> bool:  # pragma: no cover - trivial
    return False


def test_admin_finance_stats_uses_internal_payments(client, admin_auth, monkeypatch):
  # Configure roles so that admin_auth is treated as admin.
  def fake_roles(phone: str) -> list[str]:
    if phone == admin_auth.phone:
      return ["admin"]
    return []

  monkeypatch.setattr(bff, "_get_effective_roles", fake_roles, raising=False)

  # Force internal payments mode.
  monkeypatch.setattr(bff, "_use_pay_internal", lambda: True, raising=False)
  monkeypatch.setattr(bff, "_PAY_INTERNAL_AVAILABLE", True, raising=False)
  monkeypatch.setattr(bff, "_pay_internal_session", lambda: _DummyPaySessionCtx(), raising=False)

  # Stub fees_summary and admin_txns_count
  def fake_fees_summary(from_iso: str | None = None, to_iso: str | None = None, s: object | None = None):
    return {
        "total_fee_cents": 12345,
        "from_ts": from_iso,
        "to_ts": to_iso,
    }

  def fake_admin_txns_count(
      wallet_id: str | None = None,
      from_iso: str | None = None,
      to_iso: str | None = None,
      s: object | None = None,
  ) -> Dict[str, Any]:
    return {"count": 42}

  monkeypatch.setattr(bff, "_pay_fees_summary", fake_fees_summary, raising=False)
  monkeypatch.setattr(bff, "_pay_admin_txns_count", fake_admin_txns_count, raising=False)

  resp = client.get(
      "/admin/finance_stats?from_iso=2025-01-01T00:00:00Z&to_iso=2025-01-02T00:00:00Z",
      headers=admin_auth.headers(),
  )
  assert resp.status_code == 200
  data = resp.json()

  assert data["total_txns"] == 42
  assert data["total_fee_cents"] == 12345
  assert data["from_iso"].startswith("2025-01-01")
  assert data["to_iso"].startswith("2025-01-02")

