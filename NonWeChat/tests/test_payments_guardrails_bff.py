from __future__ import annotations

from typing import Any, Dict

import apps.bff.app.main as bff  # type: ignore[import]


class _DummyPaySessionCtx:
  def __enter__(self) -> object:  # pragma: no cover - trivial
    return object()

  def __exit__(self, exc_type, exc, tb) -> bool:  # pragma: no cover - trivial
    return False


def _stub_pay_transfer(data: Any, request: Any | None = None, s: Any | None = None) -> Dict[str, Any]:
  return {"ok": True, "amount_cents": getattr(data, "amount_cents", None) or data.get("amount_cents")}


def test_payments_guardrail_max_amount_blocks_large_txn(client, admin_auth, monkeypatch):
  # Configure internal payments mode
  monkeypatch.setattr(bff, "_use_pay_internal", lambda: True, raising=False)
  monkeypatch.setattr(bff, "_PAY_INTERNAL_AVAILABLE", True, raising=False)
  monkeypatch.setattr(bff, "_pay_internal_session", lambda: _DummyPaySessionCtx(), raising=False)
  monkeypatch.setattr(bff, "_pay_transfer", _stub_pay_transfer, raising=False)

  # Set a strict max amount
  monkeypatch.setattr(bff, "PAY_MAX_PER_TXN_CENTS", 10_000, raising=False)

  # Clear audit buffer
  bff._AUDIT_EVENTS.clear()  # type: ignore[attr-defined]

  # This payment exceeds the guardrail and should be blocked.
  resp = client.post(
      "/payments/transfer",
      json={"from_wallet_id": "w1", "to_wallet_id": "w2", "amount_cents": 20_000},
  )
  assert resp.status_code == 403
  data = resp.json()
  assert "guardrail" in data.get("detail", "")
  actions = [e.get("action") for e in bff._AUDIT_EVENTS]  # type: ignore[attr-defined]
  assert "pay_amount_guardrail" in actions


def test_payments_guardrail_velocity_blocks_after_limit(client, admin_auth, monkeypatch):
  # Configure internal payments mode
  monkeypatch.setattr(bff, "_use_pay_internal", lambda: True, raising=False)
  monkeypatch.setattr(bff, "_PAY_INTERNAL_AVAILABLE", True, raising=False)
  monkeypatch.setattr(bff, "_pay_internal_session", lambda: _DummyPaySessionCtx(), raising=False)
  monkeypatch.setattr(bff, "_pay_transfer", _stub_pay_transfer, raising=False)

  # Strict velocity limits for test
  monkeypatch.setattr(bff, "PAY_VELOCITY_WINDOW_SECS", 60, raising=False)
  monkeypatch.setattr(bff, "PAY_VELOCITY_MAX_PER_WALLET", 2, raising=False)
  monkeypatch.setattr(bff, "PAY_VELOCITY_MAX_PER_DEVICE", 10, raising=False)

  # Reset in-memory state
  bff._PAY_VELOCITY_WALLET.clear()  # type: ignore[attr-defined]
  bff._PAY_VELOCITY_DEVICE.clear()  # type: ignore[attr-defined]
  bff._AUDIT_EVENTS.clear()         # type: ignore[attr-defined]

  headers = {"X-Device-ID": "dev-1"}

  # First two payments should pass.
  for _ in range(2):
    r = client.post(
        "/payments/transfer",
        json={"from_wallet_id": "w1", "to_wallet_id": "w2", "amount_cents": 1000},
        headers=headers,
    )
    assert r.status_code == 200

  # Third payment within window should hit wallet velocity guardrail.
  r3 = client.post(
      "/payments/transfer",
      json={"from_wallet_id": "w1", "to_wallet_id": "w2", "amount_cents": 1000},
      headers=headers,
  )
  assert r3.status_code == 429
  data3 = r3.json()
  assert "velocity guardrail" in data3.get("detail", "")
  actions = [e.get("action") for e in bff._AUDIT_EVENTS]  # type: ignore[attr-defined]
  assert "pay_velocity_guardrail_wallet" in actions

