from typing import Any, Dict, List

import apps.bff.app.main as bff


def test_me_bus_history_requires_auth(client):
    resp = client.get("/me/bus_history")
    assert resp.status_code == 401


def test_me_bus_history_filters_by_phone_and_status(client, user_auth, monkeypatch):
    """
    /me/bus_history must filter bookings by customer_phone and optionally
    by status, based on the logged-in user.
    """

    phone = user_auth.phone

    def fake_bus_booking_search(
        wallet_id: str | None = None,
        phone: str | None = None,
        limit: int = 20,
    ) -> List[Dict[str, Any]]:
        # Ignore incoming phone argument and return mixed data
        # so we can test the additional BFF-side filtering.
        return [
            {"id": "b1", "customer_phone": phone, "status": "confirmed"},
            {"id": "b2", "customer_phone": "+49170000999", "status": "confirmed"},
            {"id": "b3", "customer_phone": phone, "status": "canceled"},
        ]

    monkeypatch.setattr(bff, "bus_booking_search", fake_bus_booking_search)

    # Without status filter both b1 and b3 should pass
    resp = client.get("/me/bus_history", headers=user_auth.headers())
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, list)
    ids = {item.get("id") for item in data}
    assert ids == {"b1", "b3"}

    # With status=confirmed only b1 remains
    resp2 = client.get("/me/bus_history?status=confirmed", headers=user_auth.headers())
    assert resp2.status_code == 200
    data2 = resp2.json()
    ids2 = {item.get("id") for item in data2}
    assert ids2 == {"b1"}
