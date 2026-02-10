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


def test_device_remove_revokes_device_bound_sessions(client):
    phone = "+491700999910"
    sid = _otp_login(client, phone)
    headers = {"sa_cookie": f"sa_session={sid}"}

    # Bind current session to a device.
    r0 = client.post(
        "/auth/devices/register",
        json={"device_id": "dev_test_01", "device_type": "mobile"},
        headers=headers,
    )
    assert r0.status_code == 200

    r1 = client.get("/me/roles", headers=headers)
    assert r1.status_code == 200

    # Removing the device should revoke its sessions.
    r2 = client.delete("/auth/devices/dev_test_01", headers=headers)
    assert r2.status_code == 200
    assert r2.json().get("status") == "ok"

    r3 = client.get("/me/roles", headers=headers)
    assert r3.status_code == 401

