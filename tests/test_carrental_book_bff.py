from __future__ import annotations

from datetime import date
from typing import Any, Dict

import apps.bff.app.main as bff  # type: ignore[import]


class _DummySessionCtx:
    def __enter__(self) -> object:  # pragma: no cover - trivial
        return object()

    def __exit__(self, exc_type, exc, tb) -> bool:  # pragma: no cover - trivial
        return False


def _setup_carrental_stub(monkeypatch):
    """
    Stub the carrental domain in the BFF so that /carrental/book and
    /carrental/bookings/{id} can be tested deterministically, including
    idempotency and price calculation (days * price-per-day).
    """

    price_per_day_cents = 20_000
    state: Dict[str, Any] = {
        "bookings": {},  # idem_key -> booking dict
        "by_id": {},     # booking_id -> booking dict
    }

    def _nights(from_iso: str, to_iso: str) -> int:
        try:
            d_from = date.fromisoformat(from_iso)
            d_to = date.fromisoformat(to_iso)
            diff = (d_to - d_from).days
            return max(1, diff)
        except Exception:
            return 1

    class _BookReq:
        def __init__(
            self,
            car_id: int,
            renter_name: str = "",
            renter_phone: str | None = None,
            renter_wallet_id: str | None = None,
            from_iso: str = "",
            to_iso: str = "",
            confirm: bool = False,
        ) -> None:
            self.car_id = car_id
            self.renter_name = renter_name
            self.renter_phone = renter_phone
            self.renter_wallet_id = renter_wallet_id
            self.from_iso = from_iso
            self.to_iso = to_iso
            self.confirm = confirm

    def fake_book(req: Any, idempotency_key: str | None, s: object):
        nights = _nights(req.from_iso, req.to_iso)
        amount = nights * price_per_day_cents
        if idempotency_key and idempotency_key in state["bookings"]:
            return state["bookings"][idempotency_key]
        status = "confirmed" if req.renter_wallet_id else "pending"
        booking_id = f"cr_{len(state['bookings'])+1}"
        booking = {
            "id": booking_id,
            "car_id": req.car_id,
            "nights": nights,
            "amount_cents": amount,
            "status": status,
        }
        if idempotency_key:
            state["bookings"][idempotency_key] = booking
        state["by_id"][booking_id] = booking
        return booking

    def fake_get_booking(booking_id: str, s: object):
        b = state["by_id"].get(booking_id)
        if not b:
            raise RuntimeError("not found in stub")
        return b

    def fake_cancel_booking(booking_id: str, s: object):
        b = state["by_id"].get(booking_id)
        if not b:
            raise RuntimeError("not found in stub")
        b = dict(b)
        b["status"] = "cancelled"
        state["by_id"][booking_id] = b
        return b

    def fake_confirm_booking(booking_id: str, req: Any, s: object):
        b = state["by_id"].get(booking_id)
        if not b:
            raise RuntimeError("not found in stub")
        b = dict(b)
        b["status"] = "confirmed"
        state["by_id"][booking_id] = b
        return b

    monkeypatch.setattr(bff, "_use_carrental_internal", lambda: True)
    monkeypatch.setattr(bff, "_CARRENTAL_INTERNAL_AVAILABLE", True, raising=False)
    monkeypatch.setattr(bff, "_carrental_internal_session", lambda: _DummySessionCtx())
    monkeypatch.setattr(bff, "_CarrentalBookReq", _BookReq, raising=False)
    monkeypatch.setattr(bff, "_carrental_book", fake_book, raising=False)
    monkeypatch.setattr(bff, "_carrental_get_booking", fake_get_booking, raising=False)
    monkeypatch.setattr(bff, "_carrental_cancel_booking", fake_cancel_booking, raising=False)

    return state


def test_carrental_book_flow_and_idempotency_via_bff(client, monkeypatch):
    """
    Bank-like invariant for carrental via the BFF:

    - price = nights * price-per-day
    - booking with same Idempotency-Key is not created twice
    - /carrental/bookings/{id} returns the same booking
    """

    _setup_carrental_stub(monkeypatch)

    body = {
        "car_id": 1,
        "renter_name": "Test User",
        "renter_phone": "+491700000777",
        "renter_wallet_id": "w_user",
        "from_iso": "2025-01-01",
        "to_iso": "2025-01-04",  # 3 nights
        "confirm": True,
    }
    idem = "cr-test-123"

    resp1 = client.post("/carrental/book", json=body, headers={"Idempotency-Key": idem})
    assert resp1.status_code == 200
    b1 = resp1.json()

    assert b1["car_id"] == 1
    assert b1["nights"] == 3
    assert b1["amount_cents"] == 3 * 20_000
    assert b1["status"] == "confirmed"

    # Idempotent repetition with same key -> same booking.
    resp2 = client.post("/carrental/book", json=body, headers={"Idempotency-Key": idem})
    assert resp2.status_code == 200
    b2 = resp2.json()

    assert b1["id"] == b2["id"]
    assert b1["amount_cents"] == b2["amount_cents"]
    assert b1["status"] == b2["status"]

    # Detail endpoint must return the same booking.
    resp_status = client.get(f"/carrental/bookings/{b1['id']}")
    assert resp_status.status_code == 200
    st = resp_status.json()
    assert st["id"] == b1["id"]
    assert st["amount_cents"] == 3 * 20_000


def test_carrental_cancel_flow_via_bff(client, monkeypatch):
    """
    Story: Book and cancel a carrental booking via BFF with internal stubs.

    - Initial booking is confirmed.
    - Cancel endpoint flips status to 'cancelled'.
    """

    state = _setup_carrental_stub(monkeypatch)

    body = {
        "car_id": 2,
        "renter_name": "Story User",
        "renter_phone": "+491700000888",
        "renter_wallet_id": "w_user_story",
        "from_iso": "2025-02-10",
        "to_iso": "2025-02-12",  # 2 nights
        "confirm": True,
    }
    idem = "cr-story-1"

    resp = client.post("/carrental/book", json=body, headers={"Idempotency-Key": idem})
    assert resp.status_code == 200
    booking = resp.json()
    bid = booking["id"]
    assert booking["status"] == "confirmed"

    # Cancel booking
    resp_cancel = client.post(f"/carrental/bookings/{bid}/cancel")
    assert resp_cancel.status_code == 200
    b_cancel = resp_cancel.json()
    assert b_cancel["id"] == bid
    assert b_cancel["status"] == "cancelled"
