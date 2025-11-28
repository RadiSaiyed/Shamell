import apps.bff.app.main as bff


def test_maintenance_mode_blocks_regular_routes(client, monkeypatch):
    """
    When MAINTENANCE_MODE is enabled, regular routes should return 503.
    """

    monkeypatch.setattr(bff, "MAINTENANCE_MODE_ENABLED", True, raising=False)

    # /metrics is a regular route (no /admin, no /health)
    resp = client.get("/metrics")
    assert resp.status_code == 503
    data = resp.json()
    assert data.get("status") == "maintenance"
    assert resp.headers.get("Retry-After") == "60"


def test_maintenance_mode_allows_admin_routes(client, admin_auth, monkeypatch):
    """
    Admin routes should remain available while maintenance mode is enabled.
    """

    def fake_roles(phone: str) -> list[str]:
        if phone == admin_auth.phone:
            return ["admin"]
        return []

    monkeypatch.setattr(bff, "MAINTENANCE_MODE_ENABLED", True, raising=False)
    monkeypatch.setattr(bff, "_get_effective_roles", fake_roles)

    resp = client.get("/admin/info", headers=admin_auth.headers())
    assert resp.status_code == 200
