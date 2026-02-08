from __future__ import annotations

from fastapi.testclient import TestClient


def test_chat_internal_secret_guard_enforces_auth(monkeypatch):
    """
    Regression: Chat must be deployable as an internal-only service in
    prod/staging. When enabled, all non-health requests require
    X-Internal-Secret.
    """
    import apps.chat.app.main as chat  # type: ignore[import]

    monkeypatch.setattr(chat, "CHAT_REQUIRE_INTERNAL_SECRET", True, raising=False)
    monkeypatch.setattr(chat, "INTERNAL_API_SECRET", "test-internal-secret", raising=False)

    client = TestClient(chat.app)

    assert client.get("/health").status_code == 200
    assert client.get("/devices/does-not-exist").status_code == 401

    ok = client.get(
        "/devices/does-not-exist",
        headers={"X-Internal-Secret": "test-internal-secret"},
    )
    assert ok.status_code == 404


def test_bff_chat_http_calls_include_internal_secret(monkeypatch):
    """
    Regression: when the BFF falls back to CHAT_BASE_URL over HTTP, it must
    always attach X-Internal-Secret so Chat can stay internal-only.
    """
    import apps.bff.app.main as bff  # type: ignore[import]

    monkeypatch.setattr(bff, "_use_chat_internal", lambda: False, raising=False)
    monkeypatch.setattr(bff, "CHAT_BASE", "https://chat.example", raising=False)
    monkeypatch.setattr(bff, "INTERNAL_API_SECRET", "test-internal-secret", raising=False)

    captured: dict[str, object] = {}

    class _DummyResp:
        def json(self):  # pragma: no cover - trivial
            return {"device_id": "d_test", "public_key_b64": "k", "name": None}

    def _fake_get(url, headers=None, timeout=None, **kwargs):  # type: ignore[no-untyped-def]
        captured["url"] = url
        captured["headers"] = headers or {}
        return _DummyResp()

    monkeypatch.setattr(bff.httpx, "get", _fake_get, raising=True)

    client = TestClient(bff.app)
    resp = client.get("/chat/devices/d_test", headers={"X-Internal-Secret": "evil"})
    assert resp.status_code == 200

    hdrs = captured.get("headers") or {}
    assert isinstance(hdrs, dict)
    assert hdrs.get("X-Internal-Secret") == "test-internal-secret"

