from __future__ import annotations

import apps.bff.app.main as bff  # type: ignore[import]


def _otp_login(client, phone: str) -> str:
    r0 = client.post("/auth/request_code", json={"phone": phone})
    assert r0.status_code == 200
    j0 = r0.json()
    code = j0.get("code")
    assert isinstance(code, str) and code

    r1 = client.post("/auth/verify", json={"phone": phone, "code": code})
    assert r1.status_code == 200
    j1 = r1.json()
    sid = j1.get("session")
    assert isinstance(sid, str) and sid
    return sid


def test_session_persists_via_db_when_memory_cache_cleared(client, monkeypatch):
    phone = "+491700999901"
    sid = _otp_login(client, phone)
    headers = {"sa_cookie": f"sa_session={sid}"}

    r0 = client.get("/me/roles", headers=headers)
    assert r0.status_code == 200
    assert r0.json().get("phone") == phone

    # Simulate a process restart: in-memory cache gone, DB should still authorize.
    monkeypatch.setattr(bff, "_SESSIONS", {}, raising=False)

    r1 = client.get("/me/roles", headers=headers)
    assert r1.status_code == 200
    assert r1.json().get("phone") == phone


def test_logout_revokes_db_backed_session(client, monkeypatch):
    phone = "+491700999902"
    sid = _otp_login(client, phone)
    headers = {"sa_cookie": f"sa_session={sid}"}

    r0 = client.get("/me/roles", headers=headers)
    assert r0.status_code == 200

    r1 = client.post("/auth/logout", headers=headers)
    assert r1.status_code == 200

    # Even if memory is cleared, the DB-backed session should be gone.
    monkeypatch.setattr(bff, "_SESSIONS", {}, raising=False)

    r2 = client.get("/me/roles", headers=headers)
    assert r2.status_code == 401

