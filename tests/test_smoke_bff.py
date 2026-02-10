from __future__ import annotations

"""
Very small smoke tests to ensure the BFF is wired and basic health
endpoints respond as expected.

These are not a replacement for full invariants, but they catch obvious
startup/config issues early in CI.
"""


def test_root_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data.get("status") == "ok"
    assert data.get("service") in ("Shamell BFF", "bff", "shamell-bff")


def test_bff_upstreams_health_shape(client, monkeypatch):
    # Ensure BASE_URLs are empty so no real HTTP calls happen here.
    import apps.bff.app.main as bff  # type: ignore[import]

    for name in [
        "PAYMENTS_BASE",
        "BUS_BASE",
        "CHAT_BASE",
    ]:
        monkeypatch.setattr(bff, name, "")

    resp = client.get("/upstreams/health")
    assert resp.status_code == 200
    data = resp.json()
    # At least the known keys should be present, even if they carry errors.
    for svc in [
        "payments",
        "bus",
        "chat",
        "livekit",
    ]:
        assert svc in data
