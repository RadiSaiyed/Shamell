from __future__ import annotations


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


def test_logout_revokes_header_session(client):
    phone = "+491700000123"
    sid = _otp_login(client, phone)
    headers = {"sa_cookie": f"sa_session={sid}"}

    body = {"origin": {"lat": 33.5, "lon": 36.3}, "stops": [{"id": "s1", "lat": 33.51, "lon": 36.31}]}

    r0 = client.post("/fleet/optimize_stops", json=body, headers=headers)
    assert r0.status_code == 200

    r1 = client.post("/auth/logout", headers=headers)
    assert r1.status_code == 200

    r2 = client.post("/fleet/optimize_stops", json=body, headers=headers)
    assert r2.status_code == 401
