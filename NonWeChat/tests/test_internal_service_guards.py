from __future__ import annotations

from fastapi.testclient import TestClient


def test_payments_internal_secret_guard_enforces_auth(monkeypatch):
    """
    Regression: Payments must be deployable as an internal-only service in
    prod/staging. When enabled, all non-health requests require
    X-Internal-Secret.
    """
    import apps.payments.app.main as payments  # type: ignore[import]

    monkeypatch.setattr(payments, "PAYMENTS_REQUIRE_INTERNAL_SECRET", True, raising=False)
    monkeypatch.setattr(payments, "INTERNAL_API_SECRET", "test-internal-secret", raising=False)

    client = TestClient(payments.app)

    assert client.get("/health").status_code == 200
    assert client.get("/wallets/does-not-exist").status_code == 401

    ok = client.get(
        "/wallets/does-not-exist",
        headers={"X-Internal-Secret": "test-internal-secret"},
    )
    # No wallet exists in the empty test DB, but the auth guard must allow the request through.
    assert ok.status_code == 404


def test_taxi_internal_secret_guard_enforces_auth(monkeypatch):
    """
    Regression: Taxi must be deployable as an internal-only service in
    prod/staging. When enabled, all non-health requests require
    X-Internal-Secret.
    """
    import apps.taxi.app.main as taxi  # type: ignore[import]

    monkeypatch.setattr(taxi, "TAXI_INTERNAL_SECRET", "test-internal-secret", raising=False)

    client = TestClient(taxi.app)

    assert client.get("/health").status_code == 200
    assert client.get("/drivers/does-not-exist").status_code == 403

    ok = client.get(
        "/drivers/does-not-exist",
        headers={"X-Internal-Secret": "test-internal-secret"},
    )
    # No driver exists in the empty test DB, but the auth guard must allow the request through.
    assert ok.status_code == 404


def test_bff_payments_http_calls_include_internal_secret(monkeypatch):
    """
    Regression: when the BFF falls back to PAYMENTS_BASE_URL over HTTP, it must
    always attach X-Internal-Secret so the Payments service can stay internal-only.
    """
    import apps.bff.app.main as bff  # type: ignore[import]

    monkeypatch.setattr(bff, "_use_pay_internal", lambda: False, raising=False)
    monkeypatch.setattr(bff, "PAYMENTS_BASE", "https://payments.example", raising=False)
    monkeypatch.setattr(bff, "PAYMENTS_INTERNAL_SECRET", "test-internal-secret", raising=False)

    captured: dict[str, object] = {}

    class _DummyResp:
        def json(self):  # pragma: no cover - trivial
            return {"wallet_id": "w_test"}

    def _fake_post(url, json=None, headers=None, timeout=None, **kwargs):  # type: ignore[no-untyped-def]
        captured["url"] = url
        captured["headers"] = headers or {}
        return _DummyResp()

    monkeypatch.setattr(bff.httpx, "post", _fake_post, raising=True)

    client = TestClient(bff.app)
    resp = client.post("/payments/users", json={"phone": "+491700000999"})
    assert resp.status_code == 200

    hdrs = captured.get("headers") or {}
    assert isinstance(hdrs, dict)
    assert hdrs.get("X-Internal-Secret") == "test-internal-secret"

    # Extra safety: caller-provided header values must never override the internal secret.
    assert bff._payments_headers({"X-Internal-Secret": "evil"}).get("X-Internal-Secret") == "test-internal-secret"


def test_bff_taxi_http_calls_include_internal_secret(monkeypatch):
    """
    Regression: when the BFF falls back to TAXI_BASE_URL over HTTP, it must
    always attach X-Internal-Secret so Taxi can stay internal-only.
    """
    import apps.bff.app.main as bff  # type: ignore[import]

    monkeypatch.setattr(bff, "_use_taxi_internal", lambda: False, raising=False)
    monkeypatch.setattr(bff, "TAXI_BASE", "https://taxi.example", raising=False)
    monkeypatch.setattr(bff, "TAXI_INTERNAL_SECRET", "test-internal-secret", raising=False)
    monkeypatch.setattr(bff, "_resolve_wallet_id_for_phone", lambda phone: "w_test", raising=False)

    captured: list[dict[str, object]] = []

    class _DummyResp:
        headers = {"content-type": "application/json"}
        status_code = 200
        text = "ok"

        def json(self):  # pragma: no cover - trivial
            return {"ok": True}

    def _fake_post(url, json=None, headers=None, timeout=None, **kwargs):  # type: ignore[no-untyped-def]
        captured.append({"url": url, "headers": headers or {}})
        return _DummyResp()

    monkeypatch.setattr(bff.httpx, "post", _fake_post, raising=True)

    client = TestClient(bff.app)

    r1 = client.post(
        "/taxi/rides/quote",
        json={
            "pickup_lat": 0.0,
            "pickup_lon": 0.0,
            "dropoff_lat": 0.01,
            "dropoff_lon": 0.0,
        },
    )
    assert r1.status_code == 200
    assert isinstance(captured[0]["headers"], dict)
    assert captured[0]["headers"].get("X-Internal-Secret") == "test-internal-secret"

    captured.clear()
    r2 = client.post(
        "/taxi/rides/book_pay",
        headers={"X-Test-Phone": "+491700000001"},
        json={
            "pickup_lat": 0.0,
            "pickup_lon": 0.0,
            "dropoff_lat": 0.01,
            "dropoff_lon": 0.0,
        },
    )
    assert r2.status_code == 200
    assert isinstance(captured[0]["headers"], dict)
    assert captured[0]["headers"].get("X-Internal-Secret") == "test-internal-secret"


def test_taxi_payments_http_calls_include_internal_secret(monkeypatch):
    """
    Regression: Taxi must attach X-Internal-Secret when calling the internal
    Payments service, otherwise Payments would need to be exposed publicly or
    the integration would break in prod/staging.
    """
    import apps.taxi.app.main as taxi  # type: ignore[import]

    monkeypatch.setattr(taxi, "PAYMENTS_BASE", "https://payments.example", raising=False)
    monkeypatch.setattr(taxi, "PAYMENTS_INTERNAL_SECRET", "test-payments-secret", raising=False)

    captured: list[dict[str, object]] = []

    class _DummyResp:
        def raise_for_status(self):  # pragma: no cover - trivial
            return None

        def json(self):  # pragma: no cover - trivial
            return {"id": "t_test", "wallet_id": "w_test"}

    def _fake_post(url, json=None, headers=None, timeout=None, **kwargs):  # type: ignore[no-untyped-def]
        captured.append({"url": url, "headers": headers or {}})
        return _DummyResp()

    monkeypatch.setattr(taxi.httpx, "post", _fake_post, raising=True)

    taxi._payments_transfer("w_from", "w_to", 123, ikey="idem-x", ref="ref-x")
    taxi._payments_create_user("+491700000777")

    assert len(captured) == 2
    for call in captured:
        hdrs = call.get("headers") or {}
        assert isinstance(hdrs, dict)
        assert hdrs.get("X-Internal-Secret") == "test-payments-secret"
