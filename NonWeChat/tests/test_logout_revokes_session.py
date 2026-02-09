from __future__ import annotations

import apps.bff.app.main as bff  # type: ignore[import]


def test_logout_revokes_header_session(client, monkeypatch):
    # Ensure we don't bypass auth via test header shortcut.
    phone = "+491700000123"
    sid = "a" * 32

    # Isolate session store for this test.
    monkeypatch.setattr(bff, "_SESSIONS", {sid: (phone, bff._now() + 3600)}, raising=False)

    body = {"origin": {"lat": 33.5, "lon": 36.3}, "stops": [{"id": "s1", "lat": 33.51, "lon": 36.31}]}
    headers = {"sa_cookie": f"sa_session={sid}"}

    r0 = client.post("/fleet/optimize_stops", json=body, headers=headers)
    assert r0.status_code == 200

    r1 = client.post("/auth/logout", headers=headers)
    assert r1.status_code == 200

    r2 = client.post("/fleet/optimize_stops", json=body, headers=headers)
    assert r2.status_code == 401

