from __future__ import annotations

import apps.bff.app.main as bff  # type: ignore[import]


class _DummyResp:
    def __init__(self, status_code: int = 200, json_data=None, headers=None, text: str = ""):
        self.status_code = status_code
        self._json_data = json_data
        self.headers = headers or {"content-type": "application/json"}
        self.text = text

    def json(self):
        return self._json_data

    def raise_for_status(self):
        # For these authz tests we keep upstream responses "successful".
        return None


def _auth(phone: str) -> dict[str, str]:
    return {"X-Test-Phone": phone}


def test_bus_booking_endpoints_require_auth(client):
    assert client.get("/bus/bookings/b1").status_code == 401
    assert client.get("/bus/bookings/b1/tickets").status_code == 401
    assert client.get("/bus/bookings/search").status_code == 401


def test_bus_booking_status_enforces_wallet_ownership(client, monkeypatch):
    # Force external-mode path so httpx stubs are exercised (monolith defaults to internal).
    monkeypatch.setattr(bff, "_use_bus_internal", lambda: False, raising=False)
    monkeypatch.setattr(bff, "BUS_BASE", "http://bus.local", raising=False)
    monkeypatch.setattr(bff, "_resolve_wallet_id_for_phone", lambda phone: "w-caller", raising=False)

    def fake_get(url, *args, **kwargs):
        if url.endswith("/bookings/b1"):
            return _DummyResp(json_data={"id": "b1", "wallet_id": "w-other"})
        return _DummyResp(json_data={})

    monkeypatch.setattr(bff.httpx, "get", fake_get, raising=True)

    r = client.get("/bus/bookings/b1", headers=_auth("+491700000001"))
    assert r.status_code == 403


def test_bus_booking_tickets_enforces_wallet_ownership(client, monkeypatch):
    # Force external-mode path so httpx stubs are exercised (monolith defaults to internal).
    monkeypatch.setattr(bff, "_use_bus_internal", lambda: False, raising=False)
    monkeypatch.setattr(bff, "BUS_BASE", "http://bus.local", raising=False)
    monkeypatch.setattr(bff, "_resolve_wallet_id_for_phone", lambda phone: "w-caller", raising=False)

    def fake_get(url, *args, **kwargs):
        if url.endswith("/bookings/b1"):
            return _DummyResp(json_data={"id": "b1", "wallet_id": "w-other"})
        if url.endswith("/bookings/b1/tickets"):
            return _DummyResp(json_data=[{"id": "t1"}])
        return _DummyResp(json_data={})

    monkeypatch.setattr(bff.httpx, "get", fake_get, raising=True)

    r = client.get("/bus/bookings/b1/tickets", headers=_auth("+491700000001"))
    assert r.status_code == 403


def test_bus_booking_search_blocks_cross_wallet_queries(client, monkeypatch):
    # Force external-mode path so httpx stubs are exercised (monolith defaults to internal).
    monkeypatch.setattr(bff, "_use_bus_internal", lambda: False, raising=False)
    monkeypatch.setattr(bff, "BUS_BASE", "http://bus.local", raising=False)
    monkeypatch.setattr(bff, "_resolve_wallet_id_for_phone", lambda phone: "w-caller", raising=False)

    def fake_get(url, *args, **kwargs):
        if url.endswith("/bookings/search"):
            return _DummyResp(json_data=[{"id": "b1", "wallet_id": "w-caller"}])
        return _DummyResp(json_data=[])

    monkeypatch.setattr(bff.httpx, "get", fake_get, raising=True)

    # Caller must not query someone else's wallet_id.
    r = client.get("/bus/bookings/search", params={"wallet_id": "w-other"}, headers=_auth("+491700000001"))
    assert r.status_code == 403

    # Caller can query own bookings (filters are enforced server-side).
    ok = client.get("/bus/bookings/search", headers=_auth("+491700000001"))
    assert ok.status_code == 200
