import httpx
from fastapi.testclient import TestClient

import apps.bff.app.main as bff  # type: ignore[import]


class FakeResponse:
    def __init__(self, payload: dict, status_code: int = 200):
        self._payload = payload
        self.status_code = status_code

    def json(self) -> dict:
        return self._payload

    def raise_for_status(self) -> None:
        if self.status_code >= 400:
            raise httpx.HTTPError(f"status {self.status_code}")


def test_bff_courier_quote_proxies(monkeypatch):
    captured = {}
    bff.COURIER_BASE = "http://courier"

    def fake_post(url, json=None, timeout=None, headers=None):
        captured["url"] = url
        captured["json"] = json
        captured["headers"] = headers
        return FakeResponse({"distance_km": 1.2, "price_cents": 500, "window_start": "2024-01-01T10:00:00"})

    monkeypatch.setattr(httpx, "post", fake_post)
    client = TestClient(bff.app)

    body = {
        "pickup_lat": 0.0,
        "pickup_lng": 0.0,
        "drop_lat": 0.1,
        "drop_lng": 0.1,
        "customer_name": "Test",
        "customer_phone": "+491700000111",
    }
    r = client.post("/courier/quote", json=body)
    assert r.status_code == 200
    assert captured["url"].endswith("/quote")
    assert captured["json"]["pickup_lat"] == 0.0
    assert r.json()["price_cents"] == 500


def test_bff_courier_book_forwards_idempotency(monkeypatch):
    captured = {}
    bff.COURIER_BASE = "http://courier"

    def fake_post(url, json=None, timeout=None, headers=None):
        captured["url"] = url
        captured["json"] = json
        captured["headers"] = headers
        return FakeResponse({"id": "ord-1"})

    monkeypatch.setattr(httpx, "post", fake_post)
    client = TestClient(bff.app)

    body = {
        "pickup_lat": 0.0,
        "pickup_lng": 0.0,
        "drop_lat": 0.1,
        "drop_lng": 0.1,
        "customer_name": "Test",
        "customer_phone": "+491700000111",
    }
    r = client.post("/courier/book", json=body, headers={"Idempotency-Key": "idem-1"})
    assert r.status_code == 200
    assert captured["url"].endswith("/orders")
    assert captured["headers"]["Idempotency-Key"] == "idem-1"
    assert r.json()["id"] == "ord-1"


def test_bff_courier_track_public(monkeypatch):
    captured = {}
    bff.COURIER_BASE = "http://courier"

    def fake_get(url, params=None, timeout=None):
        captured["url"] = url
        captured["params"] = params
        return FakeResponse({"status": "delivering", "tracking_token": "tok"})

    monkeypatch.setattr(httpx, "get", fake_get)
    client = TestClient(bff.app)

    r = client.get("/courier/track/token-123")
    assert r.status_code == 200
    assert captured["url"].endswith("/track/public/token-123")
    assert r.json()["status"] == "delivering"


def test_bff_courier_stats_filters(monkeypatch):
    captured = {}
    bff.COURIER_BASE = "http://courier"

    def fake_get(url, params=None, timeout=None, headers=None):
        captured["url"] = url
        captured["params"] = params
        captured["headers"] = headers
        return FakeResponse({"total": 1, "delivered": 1, "on_promise": 1, "on_promise_rate": 1.0, "return_required": 0, "avg_distance_km": 1.0, "avg_co2_grams": 10})

    monkeypatch.setattr(httpx, "get", fake_get)
    client = TestClient(bff.app)

    r = client.get("/courier/stats", params={"carrier": "urbify", "partner_id": "p1", "service_type": "same_day"})
    assert r.status_code == 200
    assert captured["params"]["carrier"] == "urbify"
    assert captured["params"]["partner_id"] == "p1"
    assert captured["params"]["service_type"] == "same_day"
    assert r.json()["delivered"] == 1


def test_bff_courier_status_forwards_idempotency(monkeypatch):
    captured = {}
    bff.COURIER_BASE = "http://courier"
    monkeypatch.setattr(bff, "_require_operator", lambda *args, **kwargs: "ops")

    def fake_post(url, json=None, timeout=None, headers=None):
        captured["url"] = url
        captured["json"] = json
        captured["headers"] = headers
        return FakeResponse({"status": "delivered"})

    monkeypatch.setattr(httpx, "post", fake_post)
    client = TestClient(bff.app)

    r = client.post("/courier/shipments/oid-1/status", json={"status": "delivered"}, headers={"Idempotency-Key": "idem-2"})
    assert r.status_code == 200
    assert captured["url"].endswith("/orders/oid-1/status")
    assert captured["headers"]["Idempotency-Key"] == "idem-2"
    assert r.json()["status"] == "delivered"


def test_bff_courier_contact(monkeypatch):
    captured = {}
    bff.COURIER_BASE = "http://courier"

    def fake_post(url, json=None, timeout=None, headers=None):
        captured["url"] = url
        captured["json"] = json
        return FakeResponse({"ok": True})

    monkeypatch.setattr(httpx, "post", fake_post)
    client = TestClient(bff.app)

    r = client.post("/courier/orders/ord-1/contact", json={"message": "help"})
    assert r.status_code == 200
    assert captured["url"].endswith("/orders/ord-1/contact")
    assert captured["json"]["message"] == "help"


def test_bff_courier_reschedule(monkeypatch):
    captured = {}
    bff.COURIER_BASE = "http://courier"

    def fake_post(url, json=None, timeout=None, headers=None):
        captured["url"] = url
        captured["json"] = json
        return FakeResponse({"status": "rescheduled"})

    monkeypatch.setattr(httpx, "post", fake_post)
    client = TestClient(bff.app)

    r = client.post("/courier/orders/ord-2/reschedule", json={"window_start": "2024-01-01T10:00:00", "window_end": "2024-01-01T11:00:00"})
    assert r.status_code == 200
    assert captured["url"].endswith("/orders/ord-2/reschedule")
    assert captured["json"]["window_end"].endswith("11:00:00")


def test_bff_courier_address_validate(monkeypatch):
    captured = {}
    bff.COURIER_BASE = "http://courier"

    def fake_get(url, params=None, timeout=None):
        captured["url"] = url
        captured["params"] = params
        return FakeResponse({"validated_lat": 1.0, "validated_lng": 2.0})

    monkeypatch.setattr(httpx, "get", fake_get)
    client = TestClient(bff.app)

    r = client.get("/courier/address/validate", params={"lat": 1.0, "lng": 2.0, "address": "abc"})
    assert r.status_code == 200
    assert captured["url"].endswith("/address/validate")
    assert captured["params"]["address"] == "abc"
    assert r.json()["validated_lat"] == 1.0


def test_bff_courier_slots(monkeypatch):
    captured = {}
    bff.COURIER_BASE = "http://courier"

    def fake_get(url, params=None, timeout=None):
        captured["url"] = url
        captured["params"] = params
        return FakeResponse({"service_type": "next_day", "slots": []})

    monkeypatch.setattr(httpx, "get", fake_get)
    client = TestClient(bff.app)

    r = client.get("/courier/slots", params={"service_type": "next_day"})
    assert r.status_code == 200
    assert captured["url"].endswith("/slots")
    assert captured["params"]["service_type"] == "next_day"
    assert r.json()["service_type"] == "next_day"


def test_bff_courier_partners(monkeypatch):
    created = {}
    listed = {}
    bff.COURIER_BASE = "http://courier"

    def fake_post(url, json=None, timeout=None, headers=None):
        created["url"] = url
        created["json"] = json
        return FakeResponse({"id": "p1", **(json or {})})

    def fake_get(url, params=None, timeout=None):
        listed["url"] = url
        return FakeResponse([{"id": "p1", "name": "Retailer"}])

    monkeypatch.setattr(httpx, "post", fake_post)
    monkeypatch.setattr(httpx, "get", fake_get)
    client = TestClient(bff.app)

    r1 = client.post("/courier/partners", json={"name": "Retailer"})
    assert r1.status_code == 200
    assert created["url"].endswith("/partners")
    assert created["json"]["name"] == "Retailer"

    r2 = client.get("/courier/partners")
    assert r2.status_code == 200
    assert listed["url"].endswith("/partners")
    assert r2.json()[0]["name"] == "Retailer"


def test_bff_courier_partner_kpis(monkeypatch):
    captured = {}
    bff.COURIER_BASE = "http://courier"

    def fake_get(url, params=None, timeout=None, headers=None):
        captured["url"] = url
        captured["params"] = params
        captured["headers"] = headers
        return FakeResponse([{"partner_id": "p1", "total": 2, "on_promise_rate": 0.5}])

    monkeypatch.setattr(httpx, "get", fake_get)
    client = TestClient(bff.app)

    r = client.get("/courier/kpis/partners", params={"start_iso": "2024-01-01T00:00:00", "end_iso": "2024-01-02T00:00:00", "carrier": "urbify"})
    assert r.status_code == 200
    assert captured["url"].endswith("/kpis/partners")
    assert captured["params"]["carrier"] == "urbify"
    assert r.json()[0]["partner_id"] == "p1"


def test_bff_courier_partner_kpis_export(monkeypatch):
    captured = {}
    bff.COURIER_BASE = "http://courier"

    class FakeRespBytes:
        def __init__(self):
            self.content = b"csv"
            self.headers = {"Content-Disposition": "attachment; filename=partner_kpis.csv"}

    def fake_get(url, params=None, timeout=None, headers=None):
        captured["url"] = url
        captured["params"] = params
        captured["headers"] = headers
        return FakeRespBytes()

    monkeypatch.setattr(httpx, "get", fake_get)
    client = TestClient(bff.app)

    r = client.get("/courier/kpis/partners/export", params={"carrier": "urbify"})
    assert r.status_code == 200
    assert captured["url"].endswith("/kpis/partners/export")
    assert captured["params"]["carrier"] == "urbify"


def test_bff_courier_apply(monkeypatch):
    captured = {}
    bff.COURIER_BASE = "http://courier"

    def fake_post(url, json=None, timeout=None):
        captured["url"] = url
        captured["json"] = json
        return FakeResponse({"id": "app1"})

    monkeypatch.setattr(httpx, "post", fake_post)
    client = TestClient(bff.app)

    r = client.post("/courier/apply", json={"name": "Courier", "phone": "+4917"})
    assert r.status_code == 200
    assert captured["url"].endswith("/apply")
    assert captured["json"]["name"] == "Courier"


def test_bff_courier_admin_applications(monkeypatch):
    captured = {}
    bff.COURIER_BASE = "http://courier"

    def fake_get(url, params=None, timeout=None, headers=None):
        captured["url"] = url
        captured["params"] = params
        captured["headers"] = headers
        return FakeResponse([{"id": "app1"}])

    monkeypatch.setattr(httpx, "get", fake_get)
    client = TestClient(bff.app)

    r = client.get("/courier/admin/applications", params={"status": "pending"})
    assert r.status_code == 200
    assert captured["url"].endswith("/admin/applications")
    assert captured["params"]["status"] == "pending"

def test_bff_courier_stats_export(monkeypatch):
    captured = {}
    bff.COURIER_BASE = "http://courier"

    class FakeRespBytes:
        def __init__(self):
            self.content = b"csv"
            self.headers = {"Content-Disposition": "attachment; filename=stats.csv"}

    def fake_get(url, params=None, timeout=None, headers=None):
        captured["url"] = url
        captured["params"] = params
        captured["headers"] = headers
        return FakeRespBytes()

    monkeypatch.setattr(httpx, "get", fake_get)
    client = TestClient(bff.app)

    r = client.get("/courier/stats/export", params={"carrier": "urbify"})
    assert r.status_code == 200
    assert captured["url"].endswith("/stats/export")
    assert captured["params"]["carrier"] == "urbify"
