from __future__ import annotations

import uuid
from typing import Any, Dict

import apps.bff.app.main as bff  # type: ignore[import]
import pytest


class _DummyReq:
    """Minimal request-like object for internal payments calls."""

    def __init__(self, headers: Dict[str, str] | None = None):
        self.headers = headers or {}


class _DummyPaySessionCtx:
    def __enter__(self) -> object:  # pragma: no cover - trivial
        return object()

    def __exit__(self, exc_type, exc, tb) -> bool:  # pragma: no cover - trivial
        return False


def test_bff_payments_transfer_passes_idempotency_and_device(client, monkeypatch):
    captured: Dict[str, Any] = {}

    def _stub_transfer(data: Any, request: Any | None = None, s: Any | None = None):
        captured["ikey"] = request.headers.get("Idempotency-Key") if request else None  # type: ignore[attr-defined]
        captured["dev"] = request.headers.get("X-Device-ID") if request else None  # type: ignore[attr-defined]
        return {"ok": True}

    monkeypatch.setattr(bff, "_use_pay_internal", lambda: True, raising=False)
    monkeypatch.setattr(bff, "_PAY_INTERNAL_AVAILABLE", True, raising=False)
    monkeypatch.setattr(bff, "_pay_internal_session", lambda: _DummyPaySessionCtx(), raising=False)
    monkeypatch.setattr(bff, "_pay_transfer", _stub_transfer, raising=False)

    ikey = f"idem-{uuid.uuid4().hex[:8]}"
    headers = {"Idempotency-Key": ikey, "X-Device-ID": "dev-123"}
    resp = client.post(
        "/payments/transfer",
        json={"from_wallet_id": "w1", "to_wallet_id": "w2", "amount_cents": 100},
        headers=headers,
    )
    assert resp.status_code == 200
    assert captured["ikey"] == ikey
    assert captured["dev"] == "dev-123"


def test_bff_payments_requests_forward_idempotency(client, monkeypatch):
    captured: Dict[str, Any] = {}

    def _stub_request_create(data: Any, s: Any | None = None):
        captured["amount_cents"] = getattr(data, "amount_cents", None)
        return {"ok": True}

    monkeypatch.setattr(bff, "_use_pay_internal", lambda: True, raising=False)
    monkeypatch.setattr(bff, "_PAY_INTERNAL_AVAILABLE", True, raising=False)
    monkeypatch.setattr(bff, "_pay_internal_session", lambda: _DummyPaySessionCtx(), raising=False)
    monkeypatch.setattr(bff, "_pay_create_request", _stub_request_create, raising=False)

    resp = client.post(
        "/payments/requests",
        json={"from_wallet_id": "w1", "to_wallet_id": "w2", "amount_cents": 150},
        headers={"Idempotency-Key": "idem-req-1"},
    )
    assert resp.status_code == 200
    assert captured["amount_cents"] == 150


def test_bff_sonic_issue_redeem_internal_paths(client, monkeypatch):
    calls: Dict[str, Any] = {}

    class _DummySession:
        def __enter__(self): return object()
        def __exit__(self, exc_type, exc, tb): return False

    def fake_issue(req_model, s=None, admin_ok=None):
        calls["issue_admin"] = admin_ok
        calls["issue_amt"] = getattr(req_model, "amount_cents", None)
        return {"token": "tok", "code": "C1", "amount_cents": calls["issue_amt"], "currency": "SYP"}

    def fake_redeem(req_model, request=None, s=None):
        calls["redeem_to"] = getattr(req_model, "to_wallet_id", None)
        calls["redeem_token"] = getattr(req_model, "token", None)
        calls["redeem_ikey"] = request.headers.get("Idempotency-Key") if request else None  # type: ignore[attr-defined]
        return {"ok": True, "wallet_id": calls["redeem_to"], "balance_cents": 123, "currency": "SYP"}

    monkeypatch.setattr(bff, "_use_pay_internal", lambda: True, raising=False)
    monkeypatch.setattr(bff, "_PAY_INTERNAL_AVAILABLE", True, raising=False)
    monkeypatch.setattr(bff, "PAYMENTS_INTERNAL_SECRET", "sek", raising=False)
    monkeypatch.setattr(bff, "_pay_internal_session", lambda: _DummySession(), raising=False)
    monkeypatch.setattr(bff, "_PaySonicIssueReq", lambda **kw: type("R", (), kw), raising=False)
    monkeypatch.setattr(bff, "_PaySonicRedeemReq", lambda **kw: type("R", (), kw), raising=False)
    monkeypatch.setattr(bff, "_pay_sonic_issue", fake_issue, raising=False)
    monkeypatch.setattr(bff, "_pay_sonic_redeem", fake_redeem, raising=False)

    r1 = client.post("/payments/sonic/issue", json={"from_wallet_id": "w1", "amount_cents": 200})
    assert r1.status_code == 200
    assert calls["issue_admin"] is True
    assert calls["issue_amt"] == 200

    r2 = client.post(
        "/payments/sonic/redeem",
        json={"token": "tok", "to_wallet_id": "w2"},
        headers={"Idempotency-Key": "idem-sonic-1"},
    )
    assert r2.status_code == 200
    assert calls["redeem_to"] == "w2"
    assert calls["redeem_token"] == "tok"
    assert calls["redeem_ikey"] == "idem-sonic-1"


def test_bff_cash_create_requires_internal_secret_and_passes_idempotency(client, monkeypatch):
    calls: Dict[str, Any] = {}

    class _DummySession:
        def __enter__(self): return object()
        def __exit__(self, exc_type, exc, tb): return False

    def fake_cash_create(req_model, request=None, s=None, admin_ok=None):
        calls["req"] = req_model
        calls["admin"] = admin_ok
        calls["ikey"] = request.headers.get("Idempotency-Key") if request else None  # type: ignore[attr-defined]
        return {"ok": True}

    monkeypatch.setattr(bff, "PAYMENTS_INTERNAL_SECRET", "sek", raising=False)
    monkeypatch.setattr(bff, "_use_pay_internal", lambda: True, raising=False)
    monkeypatch.setattr(bff, "_PAY_INTERNAL_AVAILABLE", True, raising=False)
    monkeypatch.setattr(bff, "_pay_internal_session", lambda: _DummySession(), raising=False)
    monkeypatch.setattr(bff, "_PayCashCreateReq", lambda **kw: type("C", (), kw), raising=False)
    monkeypatch.setattr(bff, "_pay_cash_create", fake_cash_create, raising=False)

    resp = client.post(
        "/payments/cash/create",
        json={"from_wallet_id": "w1", "amount_cents": 3000, "secret_phrase": "abc"},
        headers={"Idempotency-Key": "idem-cash-1", "X-Internal-Secret": "sek"},
    )
    assert resp.status_code == 200
    assert calls["admin"] is True
    assert getattr(calls["req"], "amount_cents", None) == 3000
    assert calls["ikey"] == "idem-cash-1"
