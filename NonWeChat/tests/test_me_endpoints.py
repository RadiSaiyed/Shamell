from typing import Any, Dict

import apps.bff.app.main as bff


def test_me_overview_unauthenticated_returns_401(client):
    resp = client.get("/me/overview")
    assert resp.status_code == 401


def test_me_overview_minimal_authenticated(client, user_auth, monkeypatch):
    # For the positive case enforce an empty role list so that no
    # external Payments backends are required.
    monkeypatch.setattr(bff, "_get_effective_roles", lambda phone: [])

    resp = client.get("/me/overview", headers=user_auth.headers())
    assert resp.status_code in (200, 204)
    if resp.status_code == 200:
        data: Dict[str, Any] = resp.json()
        assert "phone" in data
        assert data["phone"] == user_auth.phone
        # roles may be empty for a plain end user, but must be present
        assert "roles" in data


def test_me_home_snapshot_includes_basic_fields(client, user_auth, monkeypatch):
    monkeypatch.setattr(bff, "_get_effective_roles", lambda phone: [])

    resp = client.get("/me/home_snapshot", headers=user_auth.headers())
    # In some environments without Payments DB this might be 200 with partial data
    assert resp.status_code == 200
    data = resp.json()
    assert data.get("phone") == user_auth.phone
    # roles structure must be present even if empty
    assert "roles" in data
    assert "is_admin" in data
    assert "is_superadmin" in data
    assert "operator_domains" in data


def test_me_roles_reflect_admin_role(client, admin_auth, monkeypatch):
    # Simulate an admin role for this phone number
    def fake_roles(phone: str) -> list[str]:
        if phone == admin_auth.phone:
            return ["admin"]
        return []

    monkeypatch.setattr(bff, "_get_effective_roles", fake_roles)

    resp = client.get("/me/roles", headers=admin_auth.headers())
    assert resp.status_code == 200
    roles = resp.json().get("roles") or []
    assert "admin" in roles


def test_home_snapshot_includes_taxi_operator_kpis_when_operator(
    client, operator_taxi_auth, monkeypatch
):
    # Mark this phone as taxi-operator
    def fake_roles(phone: str) -> list[str]:
        if phone == operator_taxi_auth.phone:
            return ["operator_taxi"]
        return []

    monkeypatch.setattr(bff, "_get_effective_roles", fake_roles)

    # Stub Taxi admin summary to decouple from the real Taxi domain.
    def fake_taxi_admin_summary(request):
        return {"total_rides_today": 0, "completed_today": 0, "revenue_today_cents": 0}

    monkeypatch.setattr(bff, "taxi_admin_summary", fake_taxi_admin_summary)

    resp = client.get("/me/home_snapshot", headers=operator_taxi_auth.headers())
    assert resp.status_code == 200
    data: Dict[str, Any] = resp.json()
    # Operator domains must contain taxi
    assert "operator_domains" in data
    assert "taxi" in (data.get("operator_domains") or [])
    # KPI or error field must be present (best-effort)
    assert ("taxi_admin_summary" in data) or ("taxi_admin_summary_error" in data)


def test_home_snapshot_includes_bus_operator_kpis_when_operator(
    client, operator_taxi_auth, monkeypatch
):
    # Re-use the same phone as bus-operator for this test
    def fake_roles(phone: str) -> list[str]:
        if phone == operator_taxi_auth.phone:
            return ["operator_bus"]
        return []

    monkeypatch.setattr(bff, "_get_effective_roles", fake_roles)

    def fake_bus_admin_summary(request):
        return {"trips_today": 0, "bookings_today": 0, "revenue_today_cents": 0}

    monkeypatch.setattr(bff, "bus_admin_summary", fake_bus_admin_summary)

    resp = client.get("/me/home_snapshot", headers=operator_taxi_auth.headers())
    assert resp.status_code == 200
    data: Dict[str, Any] = resp.json()
    assert "operator_domains" in data
    assert "bus" in (data.get("operator_domains") or [])
    assert ("bus_admin_summary" in data) or ("bus_admin_summary_error" in data)
