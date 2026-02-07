from typing import Any, Dict, List

import apps.bff.app.main as bff


def test_me_mobility_history_requires_auth(client):
    resp = client.get("/me/mobility_history")
    assert resp.status_code == 401


def test_me_mobility_history_combines_taxi_and_bus(client, user_auth, monkeypatch):
    """
    /me/mobility_history soll die Ergebnisse aus Taxi- und Bus-History
    in einer gemeinsamen Antwort kapseln.
    """

    def fake_taxi(request, status: str = "", limit: int = 50) -> List[Dict[str, Any]]:
        return [{"id": "t1", "status": "completed"}]

    def fake_bus(request, status: str = "", limit: int = 50) -> List[Dict[str, Any]]:
        return [{"id": "b1", "status": "confirmed"}]

    monkeypatch.setattr(bff, "me_taxi_history", fake_taxi)
    monkeypatch.setattr(bff, "me_bus_history", fake_bus)

    resp = client.get("/me/mobility_history", headers=user_auth.headers())
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, dict)
    assert "taxi" in data and "bus" in data
    assert any(item.get("id") == "t1" for item in data["taxi"])
    assert any(item.get("id") == "b1" for item in data["bus"])

