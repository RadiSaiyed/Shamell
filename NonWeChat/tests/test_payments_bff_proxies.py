from __future__ import annotations

import uuid
from typing import Any, Dict

import apps.bff.app.main as bff  # type: ignore[import]
from fastapi.testclient import TestClient
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


@pytest.fixture()
def client():
    return TestClient(bff.app)


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
    monkeypatch.setattr(bff, "_auth_phone", lambda request: "+491700000001", raising=False)
    monkeypatch.setattr(bff, "_resolve_wallet_id_for_phone", lambda phone: "w1", raising=False)

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
    monkeypatch.setattr(bff, "_auth_phone", lambda request: "+491700000001", raising=False)
    monkeypatch.setattr(bff, "_resolve_wallet_id_for_phone", lambda phone: "w1", raising=False)

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
    monkeypatch.setattr(bff, "_require_admin_v2", lambda *args, **kwargs: "admin", raising=False)
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
    monkeypatch.setattr(bff, "_require_admin_v2", lambda *args, **kwargs: "admin", raising=False)
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


def test_bff_payments_transfer_rejects_wallet_mismatch(client, monkeypatch):
    monkeypatch.setattr(bff, "_auth_phone", lambda request: "+491700000001", raising=False)
    monkeypatch.setattr(bff, "_resolve_wallet_id_for_phone", lambda phone: "w1", raising=False)

    resp = client.post(
        "/payments/transfer",
        json={"from_wallet_id": "other-wallet", "to_wallet_id": "w2", "amount_cents": 100},
    )
    assert resp.status_code == 403
    assert "does not belong to caller" in resp.json().get("detail", "")


def test_bff_payments_request_rejects_from_wallet_override(client, monkeypatch):
    monkeypatch.setattr(bff, "_auth_phone", lambda request: "+491700000001", raising=False)
    monkeypatch.setattr(bff, "_resolve_wallet_id_for_phone", lambda phone: "w1", raising=False)

    resp = client.post(
        "/payments/requests",
        json={"from_wallet_id": "other-wallet", "to_wallet_id": "w2", "amount_cents": 200},
    )
    assert resp.status_code == 403
    assert "does not belong to caller" in resp.json().get("detail", "")


def test_bff_payments_request_accept_binds_to_caller_wallet(client, monkeypatch):
    calls: Dict[str, Any] = {}

    def fake_accept_core(rid=None, ikey=None, s=None, to_wallet_id=None):
        calls["rid"] = rid
        calls["to_wallet_id"] = to_wallet_id
        calls["ikey"] = ikey
        return {"ok": True, "wallet_id": to_wallet_id, "balance_cents": 111, "currency": "SYP"}

    monkeypatch.setattr(bff, "_auth_phone", lambda request: "+491700000001", raising=False)
    monkeypatch.setattr(bff, "_resolve_wallet_id_for_phone", lambda phone: "w1", raising=False)
    monkeypatch.setattr(bff, "_use_pay_internal", lambda: True, raising=False)
    monkeypatch.setattr(bff, "_PAY_INTERNAL_AVAILABLE", True, raising=False)
    monkeypatch.setattr(bff, "_pay_internal_session", lambda: _DummyPaySessionCtx(), raising=False)
    monkeypatch.setattr(bff, "_pay_accept_request_core", fake_accept_core, raising=False)

    resp = client.post("/payments/requests/rid-1/accept", headers={"Idempotency-Key": "idem-a1"}, json={})
    assert resp.status_code == 200
    assert calls["rid"] == "rid-1"
    assert calls["to_wallet_id"] == "w1"
    assert calls["ikey"] == "idem-a1"


def test_bff_payments_requests_write_rate_limited(client, monkeypatch):
    def _stub_request_create(data: Any, s: Any | None = None):
        return {"ok": True}

    bff._PAY_API_RATE_WALLET.clear()  # type: ignore[attr-defined]
    bff._PAY_API_RATE_IP.clear()  # type: ignore[attr-defined]
    monkeypatch.setattr(bff, "_auth_phone", lambda request: "+491700000001", raising=False)
    monkeypatch.setattr(bff, "_resolve_wallet_id_for_phone", lambda phone: "w1", raising=False)
    monkeypatch.setattr(bff, "_use_pay_internal", lambda: True, raising=False)
    monkeypatch.setattr(bff, "_PAY_INTERNAL_AVAILABLE", True, raising=False)
    monkeypatch.setattr(bff, "_pay_internal_session", lambda: _DummyPaySessionCtx(), raising=False)
    monkeypatch.setattr(bff, "_pay_create_request", _stub_request_create, raising=False)
    monkeypatch.setattr(bff, "PAY_API_REQ_WRITE_MAX_PER_WALLET", 1, raising=False)
    monkeypatch.setattr(bff, "PAY_API_REQ_WRITE_MAX_PER_IP", 9999, raising=False)

    r1 = client.post("/payments/requests", json={"from_wallet_id": "w1", "to_wallet_id": "w2", "amount_cents": 111})
    r2 = client.post("/payments/requests", json={"from_wallet_id": "w1", "to_wallet_id": "w2", "amount_cents": 111})
    assert r1.status_code == 200
    assert r2.status_code == 429


def test_bff_resolve_phone_requires_auth(client):
    r = client.get("/payments/resolve/phone/%2B491700000002")
    assert r.status_code == 401


def test_bff_resolve_phone_masks_non_admin_lookup(client, monkeypatch):
    monkeypatch.setattr(bff, "_auth_phone", lambda request: "+491700000001", raising=False)
    monkeypatch.setattr(bff, "_resolve_wallet_id_for_phone", lambda phone: "w1", raising=False)
    monkeypatch.setattr(bff, "_is_admin", lambda phone: False, raising=False)
    monkeypatch.setattr(bff, "_use_pay_internal", lambda: True, raising=False)
    monkeypatch.setattr(bff, "_PAY_INTERNAL_AVAILABLE", True, raising=False)
    monkeypatch.setattr(bff, "_pay_internal_session", lambda: _DummyPaySessionCtx(), raising=False)

    def _fake_resolve_phone(phone: str, s: Any | None = None):
        return type("Resolve", (), {"wallet_id": "w2", "user_id": "u2", "phone": phone})()

    monkeypatch.setattr(bff, "_pay_resolve_phone", _fake_resolve_phone, raising=False)
    r = client.get("/payments/resolve/phone/%2B491700000002")
    assert r.status_code == 200
    assert r.json() == {"wallet_id": "w2"}


def test_bff_resolve_phone_validates_format(client, monkeypatch):
    monkeypatch.setattr(bff, "_auth_phone", lambda request: "+491700000001", raising=False)
    monkeypatch.setattr(bff, "_resolve_wallet_id_for_phone", lambda phone: "w1", raising=False)
    r = client.get("/payments/resolve/phone/not-a-phone")
    assert r.status_code == 400


def test_bff_alias_request_binds_wallet_to_caller(client, monkeypatch):
    calls: Dict[str, Any] = {}

    def fake_alias_request(req_model, s=None):
        calls["handle"] = getattr(req_model, "handle", None)
        calls["wallet_id"] = getattr(req_model, "wallet_id", None)
        return {"ok": True, "handle": "@alice", "code": "123456"}

    monkeypatch.setattr(bff, "_auth_phone", lambda request: "+491700000001", raising=False)
    monkeypatch.setattr(bff, "_resolve_wallet_id_for_phone", lambda phone: "w1", raising=False)
    monkeypatch.setattr(bff, "_use_pay_internal", lambda: True, raising=False)
    monkeypatch.setattr(bff, "_PAY_INTERNAL_AVAILABLE", True, raising=False)
    monkeypatch.setattr(bff, "_pay_internal_session", lambda: _DummyPaySessionCtx(), raising=False)
    monkeypatch.setattr(bff, "_PayAliasRequest", lambda **kw: type("A", (), kw), raising=False)
    monkeypatch.setattr(bff, "_pay_alias_request", fake_alias_request, raising=False)

    resp = client.post("/payments/alias/request", json={"handle": "alice"})
    assert resp.status_code == 200
    assert calls["handle"] == "alice"
    assert calls["wallet_id"] == "w1"


def test_bff_favorites_create_binds_owner_to_caller(client, monkeypatch):
    calls: Dict[str, Any] = {}

    def fake_create_favorite(req_model, s=None):
        calls["owner_wallet_id"] = getattr(req_model, "owner_wallet_id", None)
        calls["favorite_wallet_id"] = getattr(req_model, "favorite_wallet_id", None)
        return {"id": "fav-1", "owner_wallet_id": calls["owner_wallet_id"], "favorite_wallet_id": calls["favorite_wallet_id"]}

    monkeypatch.setattr(bff, "_auth_phone", lambda request: "+491700000001", raising=False)
    monkeypatch.setattr(bff, "_resolve_wallet_id_for_phone", lambda phone: "w1", raising=False)
    monkeypatch.setattr(bff, "_use_pay_internal", lambda: True, raising=False)
    monkeypatch.setattr(bff, "_PAY_INTERNAL_AVAILABLE", True, raising=False)
    monkeypatch.setattr(bff, "_pay_internal_session", lambda: _DummyPaySessionCtx(), raising=False)
    monkeypatch.setattr(bff, "_PayFavoriteCreate", lambda **kw: type("F", (), kw), raising=False)
    monkeypatch.setattr(bff, "_pay_create_favorite", fake_create_favorite, raising=False)

    resp = client.post("/payments/favorites", json={"favorite_wallet_id": "w2"})
    assert resp.status_code == 200
    assert calls["owner_wallet_id"] == "w1"
    assert calls["favorite_wallet_id"] == "w2"


def test_bff_favorites_create_rejects_owner_override(client, monkeypatch):
    monkeypatch.setattr(bff, "_auth_phone", lambda request: "+491700000001", raising=False)
    monkeypatch.setattr(bff, "_resolve_wallet_id_for_phone", lambda phone: "w1", raising=False)

    resp = client.post("/payments/favorites", json={"owner_wallet_id": "wX", "favorite_wallet_id": "w2"})
    assert resp.status_code == 403
    assert "does not belong to caller" in resp.json().get("detail", "")


def test_bff_favorites_write_rate_limited(client, monkeypatch):
    def _fake_create_favorite(req_model, s=None):
        return {"id": "fav-1", "owner_wallet_id": getattr(req_model, "owner_wallet_id", None)}

    bff._PAY_API_RATE_WALLET.clear()  # type: ignore[attr-defined]
    bff._PAY_API_RATE_IP.clear()  # type: ignore[attr-defined]
    monkeypatch.setattr(bff, "_auth_phone", lambda request: "+491700000001", raising=False)
    monkeypatch.setattr(bff, "_resolve_wallet_id_for_phone", lambda phone: "w1", raising=False)
    monkeypatch.setattr(bff, "_use_pay_internal", lambda: True, raising=False)
    monkeypatch.setattr(bff, "_PAY_INTERNAL_AVAILABLE", True, raising=False)
    monkeypatch.setattr(bff, "_pay_internal_session", lambda: _DummyPaySessionCtx(), raising=False)
    monkeypatch.setattr(bff, "_PayFavoriteCreate", lambda **kw: type("F", (), kw), raising=False)
    monkeypatch.setattr(bff, "_pay_create_favorite", _fake_create_favorite, raising=False)
    monkeypatch.setattr(bff, "PAY_API_FAV_WRITE_MAX_PER_WALLET", 1, raising=False)
    monkeypatch.setattr(bff, "PAY_API_FAV_WRITE_MAX_PER_IP", 9999, raising=False)

    r1 = client.post("/payments/favorites", json={"favorite_wallet_id": "w2"})
    r2 = client.post("/payments/favorites", json={"favorite_wallet_id": "w3"})
    assert r1.status_code == 200
    assert r2.status_code == 429


def test_bff_alias_request_rejects_wallet_override(client, monkeypatch):
    monkeypatch.setattr(bff, "_auth_phone", lambda request: "+491700000001", raising=False)
    monkeypatch.setattr(bff, "_resolve_wallet_id_for_phone", lambda phone: "w1", raising=False)

    resp = client.post("/payments/alias/request", json={"handle": "alice", "wallet_id": "w2"})
    assert resp.status_code == 403
    assert "does not belong to caller" in resp.json().get("detail", "")


def test_bff_admin_alias_search_requires_superadmin(client):
    resp = client.get("/payments/admin/alias/search")
    assert resp.status_code in (401, 403)


def test_security_alert_webhook_fires_on_threshold(monkeypatch):
    calls: list[dict[str, Any]] = []

    def fake_post(url, json=None, timeout=None):
        calls.append({"url": url, "json": json, "timeout": timeout})
        return type("Resp", (), {"status_code": 200})()

    bff._SECURITY_ALERT_EVENTS.clear()  # type: ignore[attr-defined]
    bff._SECURITY_ALERT_LAST_SENT.clear()  # type: ignore[attr-defined]
    monkeypatch.setattr(bff, "SECURITY_ALERT_WEBHOOK_URL", "https://alerts.example/webhook", raising=False)
    monkeypatch.setattr(bff, "SECURITY_ALERT_WINDOW_SECS", 300, raising=False)
    monkeypatch.setattr(bff, "SECURITY_ALERT_COOLDOWN_SECS", 600, raising=False)
    monkeypatch.setattr(bff, "SECURITY_ALERT_THRESHOLDS", {"payments_transfer_wallet_mismatch": 2}, raising=False)
    monkeypatch.setattr(bff.httpx, "post", fake_post, raising=False)

    bff._maybe_send_security_alert({"action": "payments_transfer_wallet_mismatch", "phone": "+491700000001"})
    bff._maybe_send_security_alert({"action": "payments_transfer_wallet_mismatch", "phone": "+491700000001"})

    assert len(calls) == 1
    assert calls[0]["url"] == "https://alerts.example/webhook"
