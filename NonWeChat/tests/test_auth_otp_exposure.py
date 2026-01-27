from __future__ import annotations

import apps.bff.app.main as bff  # type: ignore[import]


def test_auth_request_code_exposes_code_in_dev_mode(client, monkeypatch):
    """
    When AUTH_EXPOSE_CODES=True, the OTP code should appear in the JSON body.
    This is intended for dev/test use only and must only be enabled there.
    """

    monkeypatch.setattr(bff, "AUTH_EXPOSE_CODES", True, raising=False)

    resp = client.post("/auth/request_code", json={"phone": "+491700000001"})
    assert resp.status_code == 200
    data = resp.json()
    assert data.get("ok") is True
    assert data.get("phone") == "+491700000001"
    # In Dev/Test erwarten wir das Feld "code".
    assert "code" in data
    assert isinstance(data["code"], str)
    assert len(data["code"]) >= 4


def test_auth_request_code_hides_code_when_exposure_disabled(client, monkeypatch):
    """
    When AUTH_EXPOSE_CODES=False, the OTP code must not be present
    in the response body (prod-like mode).
    """

    monkeypatch.setattr(bff, "AUTH_EXPOSE_CODES", False, raising=False)

    resp = client.post("/auth/request_code", json={"phone": "+491700000002"})
    assert resp.status_code == 200
    data = resp.json()
    assert data.get("ok") is True
    assert data.get("phone") == "+491700000002"
    # In prod-like environments we explicitly expect NO "code" field.
    assert "code" not in data
