from __future__ import annotations

from typing import Any, Dict

import apps.bff.app.main as bff  # type: ignore[import]


def test_me_journey_snapshot_includes_home_and_mobility(client, monkeypatch):
    """
    Basic test for /me/journey_snapshot:

    - Calls /me/home_snapshot and /me/mobility_history internally.
    - Returns an object with keys 'home' and 'mobility_history'.
    """

    # Stub _auth_phone so we don't need a real session.
    monkeypatch.setattr(bff, "_auth_phone", lambda request: "+491700000999", raising=False)

    # Minimally stub home snapshot so the test does not depend on Payments/Taxi.
    async def fake_home(request, response=None):  # type: ignore[override]
        return {
            "phone": "+491700000999",
            "roles": ["end_user"],
            "is_admin": False,
            "is_superadmin": False,
            "operator_domains": [],
        }

    def fake_mobility(request):  # type: ignore[override]
        return {
            "taxi": [],
            "bus": [],
        }

    monkeypatch.setattr(bff, "me_home_snapshot", fake_home, raising=False)
    monkeypatch.setattr(bff, "me_mobility_history", fake_mobility, raising=False)

    resp = client.get("/me/journey_snapshot")
    assert resp.status_code == 200
    data: Dict[str, Any] = resp.json()

    assert "home" in data
    assert "mobility_history" in data

    home = data["home"]
    mobility = data["mobility_history"]

    assert home.get("phone") == "+491700000999"
    assert isinstance(mobility.get("taxi"), list)
    assert isinstance(mobility.get("bus"), list)
