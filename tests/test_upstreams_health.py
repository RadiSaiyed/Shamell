from typing import Any, Dict

import apps.bff.app.main as bff
import httpx


def test_upstreams_health_returns_mapping_even_without_base_urls(client, monkeypatch):
    # Ensure all BASE_URLs are empty so that the handler does not attempt
    # real HTTP calls in this unit test.
    for name in [
        "PAYMENTS_BASE",
        "BUS_BASE",
        "CHAT_BASE",
    ]:
        monkeypatch.setattr(bff, name, "")

    resp = client.get("/upstreams/health")
    assert resp.status_code == 200
    data = resp.json()
    # Basic shape: mapping service -> {error: "..."} when BASE_URL is missing.
    for service in ["payments", "bus", "chat"]:
        assert service in data
        assert isinstance(data[service], dict)
        # With empty BASE_URL we expect an error field.
        assert "error" in data[service]
    livekit = data.get("livekit") or {}
    assert isinstance(livekit, dict)
    assert "configured" in livekit


def test_upstreams_health_includes_status_code_and_body_when_base_url_set(
    client, monkeypatch
):
    # Simulate a successfully reachable upstream health for one domain (payments).
    monkeypatch.setattr(bff, "PAYMENTS_BASE", "http://payments.local")
    # Alle anderen Services bleiben ohne BASE_URL, damit sie als "error" erscheinen.
    for name in [
        "BUS_BASE",
        "CHAT_BASE",
    ]:
        monkeypatch.setattr(bff, name, "")

    class _DummyResponse:
        def __init__(self) -> None:
            self.status_code = 200
            self.headers: Dict[str, str] = {"content-type": "application/json"}

        def json(self) -> Dict[str, Any]:
            return {"status": "ok", "service": "payments"}

    def fake_get(url: str, timeout: float = 5.0) -> _DummyResponse:  # type: ignore[override]
        # The BFF calls "<base>/health"; we assert that the composed URL is correct
        # and then return our dummy response.
        assert url == "http://payments.local/health"
        return _DummyResponse()

    monkeypatch.setattr(httpx, "get", fake_get)

    resp = client.get("/upstreams/health")
    assert resp.status_code == 200
    data = resp.json()

    # For payments we expect a structured response with status code and body.
    payments = data.get("payments") or {}
    assert payments.get("status_code") == 200
    assert isinstance(payments.get("body"), dict)
    assert payments["body"].get("status") == "ok"
    bus = data.get("bus") or {}
    assert "error" in bus
    chat = data.get("chat") or {}
    assert "error" in chat
    livekit = data.get("livekit") or {}
    assert "configured" in livekit


def test_upstreams_health_hidden_in_prod_for_unauthenticated(client, monkeypatch):
    # Best practice: ops endpoint should not be publicly enumerable in prod.
    monkeypatch.setenv("ENV", "prod")
    resp = client.get("/upstreams/health")
    assert resp.status_code == 404
