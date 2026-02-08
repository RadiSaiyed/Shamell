from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List

import pytest

import apps.bff.app.main as bff  # type: ignore[import]


class _DummySessionCtx:
    def __enter__(self) -> object:  # pragma: no cover - trivial
        return object()

    def __exit__(self, exc_type, exc, tb) -> bool:  # pragma: no cover - trivial
        return False


def _setup_bus_stub(monkeypatch):
    """
    Stub the Bus domain in the BFF so that /bus/trips/search, /bus/trips/{id}/book
    and /bus/bookings/{id} can be tested deterministically without real
    Bus DB access or Payments.
    """

    now = datetime.now(timezone.utc)
    dep = now + timedelta(days=1)
    arr = dep + timedelta(hours=2)
    trip = {
        "id": "trip_1",
        "route_id": "route_1",
        "depart_at": dep.isoformat().replace("+00:00", "Z"),
        "arrive_at": arr.isoformat().replace("+00:00", "Z"),
        "price_cents": 20_000,
        "currency": "SYP",
        "seats_total": 40,
        "seats_available": 40,
    }
    state: Dict[str, Any] = {
        "trip": trip,
        "bookings": {},  # booking_id -> booking dict
    }

    def fake_search_trips(origin_city_id: str, dest_city_id: str, date: str, s: object):
        return [
            {
                "trip": trip,
                "origin": {"id": origin_city_id, "name": "Origin", "country": None},
                "dest": {"id": dest_city_id, "name": "Dest", "country": None},
                "operator": {"id": "op_1", "name": "BusCo", "wallet_id": "w_op"},
            }
        ]

    def fake_trip_detail(trip_id: str, s: object):
        if trip_id != trip["id"]:
            raise RuntimeError("unknown trip in stub")
        return trip

    class _BookReq:
        def __init__(self, seats: int = 1, wallet_id: str | None = None, customer_phone: str | None = None):
            self.seats = seats
            self.wallet_id = wallet_id
            self.customer_phone = customer_phone

    def fake_book_trip(trip_id: str, body: Any, idempotency_key: str | None, s: object):
        if trip_id != trip["id"]:
            raise RuntimeError("unknown trip in stub")
        if body.seats < 1 or body.seats > 10:
            raise RuntimeError("invalid seats")
        # Idempotency: same key -> same booking
        if idempotency_key and idempotency_key in state["bookings"]:
            return state["bookings"][idempotency_key]
        bid = f"bus_{uuid.uuid4().hex[:8]}"
        status = "confirmed" if body.wallet_id else "pending"
        booking = {
            "id": bid,
            "trip_id": trip_id,
            "seats": body.seats,
            "status": status,
            "wallet_id": body.wallet_id,
            "payments_txn_id": None,
            "created_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "tickets": [],
        }
        if idempotency_key:
            state["bookings"][idempotency_key] = booking
        return booking

    def fake_booking_status(booking_id: str, s: object):
        for b in state["bookings"].values():
            if b["id"] == booking_id:
                return b
        raise RuntimeError("not found in stub")

    monkeypatch.setattr(bff, "_use_bus_internal", lambda: True)
    monkeypatch.setattr(bff, "_BUS_INTERNAL_AVAILABLE", True, raising=False)
    monkeypatch.setattr(bff, "_bus_internal_session", lambda: _DummySessionCtx())
    # Stable wallet ownership for authz checks on /bus/bookings/* endpoints.
    monkeypatch.setattr(bff, "_resolve_wallet_id_for_phone", lambda phone: "w_user", raising=False)
    monkeypatch.setattr(bff, "_bus_search_trips", fake_search_trips, raising=False)
    monkeypatch.setattr(bff, "_bus_trip_detail", fake_trip_detail, raising=False)
    monkeypatch.setattr(bff, "_BusBookReq", _BookReq, raising=False)
    monkeypatch.setattr(bff, "_bus_book_trip", fake_book_trip, raising=False)
    monkeypatch.setattr(bff, "_bus_booking_status", fake_booking_status, raising=False)


def test_bus_search_and_book_flow_via_bff(client, monkeypatch):
    """
    Bus quote/book end-to-end test via the BFF with stubs:

    - /bus/trips/search returns a trip result
    - /bus/trips/{id}/book creates a booking with seats and status
    - /bus/bookings/{id} returns that booking
    """

    _setup_bus_stub(monkeypatch)

    origin = "city_o"
    dest = "city_d"
    today = datetime.now().date().isoformat()

    resp_s = client.get(f"/bus/trips/search?origin_city_id={origin}&dest_city_id={dest}&date={today}")
    assert resp_s.status_code == 200
    trips: List[Dict[str, Any]] = resp_s.json()
    assert len(trips) == 1
    t0 = trips[0]["trip"]
    trip_id = t0["id"]

    # Booking with wallet (should be confirmed)
    idem = f"bus-{uuid.uuid4().hex[:8]}"
    resp_b = client.post(
        f"/bus/trips/{trip_id}/book",
        json={"seats": 2, "wallet_id": "w_user", "customer_phone": "+491700000999"},
        headers={"Idempotency-Key": idem},
    )
    assert resp_b.status_code == 200
    b = resp_b.json()
    assert b["trip_id"] == trip_id
    assert b["seats"] == 2
    assert b["status"] == "confirmed"
    bid = b["id"]

    resp_status = client.get(f"/bus/bookings/{bid}", headers={"X-Test-Phone": "+491700000999"})
    assert resp_status.status_code == 200
    st = resp_status.json()
    assert st["id"] == bid
    assert st["trip_id"] == trip_id


def test_bus_book_idempotency_via_bff(client, monkeypatch):
    """
    Verify idempotency of /bus/trips/{id}/book via BFF:
    same Idempotency-Key returns the same booking.
    """

    _setup_bus_stub(monkeypatch)

    origin = "city_o"
    dest = "city_d"
    today = datetime.now().date().isoformat()
    resp_s = client.get(f"/bus/trips/search?origin_city_id={origin}&dest_city_id={dest}&date={today}")
    assert resp_s.status_code == 200
    trips: List[Dict[str, Any]] = resp_s.json()
    trip_id = trips[0]["trip"]["id"]

    body = {"seats": 1, "wallet_id": "w_user", "customer_phone": "+491700000998"}
    idem = f"bus-{uuid.uuid4().hex[:8]}"

    resp1 = client.post(f"/bus/trips/{trip_id}/book", json=body, headers={"Idempotency-Key": idem})
    assert resp1.status_code == 200
    b1 = resp1.json()

    resp2 = client.post(f"/bus/trips/{trip_id}/book", json=body, headers={"Idempotency-Key": idem})
    assert resp2.status_code == 200
    b2 = resp2.json()

    assert b1["id"] == b2["id"]
    assert b1["seats"] == b2["seats"]
    assert b1["status"] == b2["status"]
