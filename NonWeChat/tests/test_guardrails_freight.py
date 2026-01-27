from __future__ import annotations

from fastapi.testclient import TestClient


def _make_client():
    # Use the standalone Freight API app for focused tests.
    from apps.freight.app.main import app as freight_app  # type: ignore[import]

    return TestClient(freight_app)


def test_freight_book_amount_guardrail(monkeypatch):
    """
    Booking with confirm=True and amount above FREIGHT_MAX_PER_SHIPMENT_CENTS
    must be blocked with a 403 guardrail error (best-effort anti-fraud).
    """
    import apps.freight.app.main as freight  # type: ignore[import]

    # Set a low max-per-shipment threshold so our test booking exceeds it.
    monkeypatch.setattr(freight, "FREIGHT_MAX_PER_SHIPMENT_CENTS", 1_000)

    client = _make_client()

    body = {
        "title": "Test shipment",
        "from_lat": 0.0,
        "from_lon": 0.0,
        "to_lat": 0.0,
        "to_lon": 0.0,
        "weight_kg": 100.0,
        "payer_wallet_id": "payer-1",
        "carrier_wallet_id": "carrier-1",
        "confirm": True,
    }
    resp = client.post("/book", json=body)
    assert resp.status_code == 403
    data = resp.json()
    # Detail string is intentionally simple; we assert the core text.
    assert "freight amount exceeds guardrail" in str(data.get("detail", "")), data


def test_freight_book_distance_guardrail(monkeypatch):
    """
    Booking with confirm=True and distance above FREIGHT_MAX_DISTANCE_KM
    must be blocked with a 403 guardrail error.
    """
    import apps.freight.app.main as freight  # type: ignore[import]

    # Disable amount guardrail and weight guardrail, focus on distance.
    monkeypatch.setattr(freight, "FREIGHT_MAX_PER_SHIPMENT_CENTS", 0)
    monkeypatch.setattr(freight, "FREIGHT_MAX_WEIGHT_KG", 0.0)
    # Require a very small maximum distance to trigger easily.
    monkeypatch.setattr(freight, "FREIGHT_MAX_DISTANCE_KM", 1.0)

    client = _make_client()

    body = {
        "title": "Far shipment",
        # Coordinates roughly ~157 km apart (should exceed 1 km limit clearly).
        "from_lat": 0.0,
        "from_lon": 0.0,
        "to_lat": 1.0,
        "to_lon": 1.0,
        "weight_kg": 1.0,
        "payer_wallet_id": "payer-2",
        "carrier_wallet_id": "carrier-2",
        "confirm": True,
    }
    resp = client.post("/book", json=body)
    assert resp.status_code == 403
    data = resp.json()
    assert "freight distance exceeds guardrail" in str(data.get("detail", "")), data
