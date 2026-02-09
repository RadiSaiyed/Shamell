from __future__ import annotations

import apps.bff.app.main as bff  # type: ignore[import]


def _otp_login(client, phone: str) -> str:
    r0 = client.post("/auth/request_code", json={"phone": phone})
    assert r0.status_code == 200
    code = r0.json().get("code")
    assert isinstance(code, str) and code

    r1 = client.post("/auth/verify", json={"phone": phone, "code": code})
    assert r1.status_code == 200
    sid = r1.json().get("session")
    assert isinstance(sid, str) and sid
    return sid


def test_device_login_challenge_persists_in_db_across_memory_clear(client, monkeypatch):
    # Start an unauthenticated device-login challenge (e.g. web).
    r0 = client.post("/auth/device_login/start", json={"label": "Web"})
    assert r0.status_code == 200
    token = r0.json().get("token")
    assert isinstance(token, str) and token

    # Phone logs in via OTP and approves the token.
    phone = "+491700999903"
    sid_phone = _otp_login(client, phone)
    headers_phone = {"sa_cookie": f"sa_session={sid_phone}"}
    r1 = client.post("/auth/device_login/approve", json={"token": token}, headers=headers_phone)
    assert r1.status_code == 200

    # Simulate restart: clear in-memory stores.
    monkeypatch.setattr(bff, "_DEVICE_LOGIN_CHALLENGES", {}, raising=False)
    monkeypatch.setattr(bff, "_SESSIONS", {}, raising=False)

    # New device redeems and receives a fresh session.
    r2 = client.post("/auth/device_login/redeem", json={"token": token})
    assert r2.status_code == 200
    j2 = r2.json()
    assert j2.get("phone") == phone
    sid_new = j2.get("session")
    assert isinstance(sid_new, str) and sid_new

    # The new session must be usable for authenticated endpoints.
    headers_new = {"sa_cookie": f"sa_session={sid_new}"}
    r3 = client.get("/me/roles", headers=headers_new)
    assert r3.status_code == 200
    assert r3.json().get("phone") == phone

    # Token should be one-time (consumed on redeem).
    r4 = client.post("/auth/device_login/redeem", json={"token": token})
    assert r4.status_code == 404

