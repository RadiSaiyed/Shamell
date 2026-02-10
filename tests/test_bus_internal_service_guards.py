from __future__ import annotations

from fastapi.testclient import TestClient


def test_bus_internal_secret_guard_enforces_auth(monkeypatch):
    """
    Regression: Bus must be deployable as an internal-only service in
    prod/staging. When enabled, all non-health requests require
    X-Internal-Secret.
    """
    import apps.bus.app.main as bus  # type: ignore[import]

    monkeypatch.setattr(bus, "BUS_REQUIRE_INTERNAL_SECRET", True, raising=False)
    monkeypatch.setattr(bus, "BUS_INTERNAL_SECRET", "test-bus-secret", raising=False)

    client = TestClient(bus.app)

    assert client.get("/health").status_code == 200
    assert client.get("/cities").status_code == 401

    ok = client.get("/cities", headers={"X-Internal-Secret": "test-bus-secret"})
    assert ok.status_code == 200


def test_bff_bus_http_calls_include_internal_secret(monkeypatch):
    """
    Regression: when the BFF falls back to BUS_BASE_URL over HTTP, it must
    always attach X-Internal-Secret so Bus can stay internal-only.
    """
    import apps.bff.app.main as bff  # type: ignore[import]

    monkeypatch.setattr(bff, "_use_bus_internal", lambda: False, raising=False)
    monkeypatch.setattr(bff, "BUS_BASE", "https://bus.example", raising=False)
    monkeypatch.setattr(bff, "BUS_INTERNAL_SECRET", "test-bus-secret", raising=False)

    captured: dict[str, object] = {}

    class _DummyResp:
        headers = {"content-type": "application/json"}

        def json(self):  # pragma: no cover - trivial
            return {"status": "ok"}

    def _fake_get(url, headers=None, timeout=None, **kwargs):  # type: ignore[no-untyped-def]
        captured["url"] = url
        captured["headers"] = headers or {}
        return _DummyResp()

    monkeypatch.setattr(bff.httpx, "get", _fake_get, raising=True)

    client = TestClient(bff.app)
    resp = client.get("/bus/health")
    assert resp.status_code == 200

    hdrs = captured.get("headers") or {}
    assert isinstance(hdrs, dict)
    assert hdrs.get("X-Internal-Secret") == "test-bus-secret"
