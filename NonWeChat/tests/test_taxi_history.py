from typing import Any, Dict, List

import apps.bff.app.main as bff


def test_me_taxi_history_requires_auth(client):
    resp = client.get("/me/taxi_history")
    assert resp.status_code == 401


def test_me_taxi_history_filters_by_rider_phone(client, user_auth, monkeypatch):
    """
    Ensure that /me/taxi_history only returns rides of the logged-in
    user, even if taxi_list_rides returns more data.
    """

    phone = user_auth.phone

    def fake_taxi_list_rides(status: str = "", limit: int = 50) -> List[Dict[str, Any]]:
        return [
            {"id": "r1", "rider_phone": phone, "status": "completed"},
            {"id": "r2", "rider_phone": "+491700000999", "status": "completed"},
            {"id": "r3", "rider_phone": phone, "status": "canceled"},
        ]

    monkeypatch.setattr(bff, "taxi_list_rides", fake_taxi_list_rides)

    resp = client.get("/me/taxi_history", headers=user_auth.headers())
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, list)
    ids = {item.get("id") for item in data}
    # Only r1 and r3 have rider_phone == phone
    assert ids == {"r1", "r3"}
