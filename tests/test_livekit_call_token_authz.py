from __future__ import annotations

import apps.bff.app.main as bff  # type: ignore[import]


def test_livekit_call_token_requires_participant(client, monkeypatch):
    monkeypatch.setattr(bff, "LIVEKIT_TOKEN_ENDPOINT_ENABLED", True, raising=False)
    monkeypatch.setattr(bff, "LIVEKIT_PUBLIC_URL", "wss://livekit.example", raising=False)
    monkeypatch.setattr(bff, "LIVEKIT_API_KEY", "testkey", raising=False)
    monkeypatch.setattr(bff, "LIVEKIT_API_SECRET", "testsecret", raising=False)
    monkeypatch.setattr(bff, "CALLING_ENABLED", True, raising=False)

    caller = "+491700111111"
    callee = "+491700222222"
    attacker = "+491700333333"

    r0 = client.post(
        "/calls/start",
        json={"to_phone": callee, "mode": "audio"},
        headers={"X-Test-Phone": caller},
    )
    assert r0.status_code == 200
    call_id = r0.json().get("call_id")
    assert isinstance(call_id, str) and call_id

    r_in = client.get("/calls/incoming", headers={"X-Test-Phone": callee})
    assert r_in.status_code == 200
    calls = r_in.json().get("calls") or []
    assert isinstance(calls, list)
    assert any(isinstance(c, dict) and c.get("call_id") == call_id for c in calls)

    r_bad = client.post(
        "/livekit/token",
        json={"call_id": call_id, "ttl_secs": 60},
        headers={"X-Test-Phone": attacker},
    )
    assert r_bad.status_code == 403

    r_ok1 = client.post(
        "/livekit/token",
        json={"call_id": call_id, "ttl_secs": 60},
        headers={"X-Test-Phone": caller},
    )
    assert r_ok1.status_code == 200

    r_ok2 = client.post(
        "/livekit/token",
        json={"call_id": call_id, "ttl_secs": 60},
        headers={"X-Test-Phone": callee},
    )
    assert r_ok2.status_code == 200

    r_end = client.post(
        f"/calls/{call_id}/end",
        headers={"X-Test-Phone": caller},
    )
    assert r_end.status_code == 200

    r_after = client.post(
        "/livekit/token",
        json={"call_id": call_id, "ttl_secs": 60},
        headers={"X-Test-Phone": caller},
    )
    assert r_after.status_code in (400, 404)

