from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from typing import Any, Dict, List

import pytest

import apps.bff.app.main as bff  # type: ignore[import]


class _DummySessionCtx:
    def __enter__(self) -> object:  # pragma: no cover - trivial
        return object()

    def __exit__(self, exc_type, exc, tb) -> bool:  # pragma: no cover - trivial
        return False


def _setup_stays_stub(monkeypatch):
    """
    Replace internal Stays calls in the BFF with simple in-memory stubs
    so that /stays/quote and /stays/book can be tested deterministically
    without requiring a real Stays DB.
    """

    state: Dict[str, Any] = {
        "currency": "SYP",
        "price_per_night": 10_000,
        "bookings": {},  # booking_id -> booking dict
    }

    class _QReq:
        def __init__(self, listing_id: int, from_iso: str, to_iso: str):
            self.listing_id = listing_id
            self.from_iso = from_iso
            self.to_iso = to_iso

    class _BReq:
        def __init__(
            self,
            listing_id: int,
            guest_name: str | None,
            guest_phone: str | None,
            guest_wallet_id: str | None,
            from_iso: str,
            to_iso: str,
            confirm: bool,
        ):
            self.listing_id = listing_id
            self.guest_name = guest_name
            self.guest_phone = guest_phone
            self.guest_wallet_id = guest_wallet_id
            self.from_iso = from_iso
            self.to_iso = to_iso
            self.confirm = confirm

    def _night_count(a: str, b: str) -> int:
        da = datetime.fromisoformat(a).date()
        db = datetime.fromisoformat(b).date()
        return max(0, (db - da).days)

    def fake_quote(req: Any, s: object):
        nights = _night_count(req.from_iso, req.to_iso)
        amount = state["price_per_night"] * nights
        return {
            "nights": nights,
            "amount_cents": amount,
            "currency": state["currency"],
            "days": [
                {
                    "date": (datetime.fromisoformat(req.from_iso) + timedelta(days=i)).date().isoformat(),
                    "price_cents": state["price_per_night"],
                    "closed": False,
                    "sold_out": False,
                }
                for i in range(nights)
            ],
        }

    def fake_book(req: Any, idempotency_key: str | None, s: object):
        nights = _night_count(req.from_iso, req.to_iso)
        amount = state["price_per_night"] * nights
        # Idempotenz auf booking_id-Mapping
        if idempotency_key and idempotency_key in state["bookings"]:
            return state["bookings"][idempotency_key]
        bid = f"stay_{uuid.uuid4().hex[:8]}"
        booking = {
            "id": bid,
            "listing_id": req.listing_id,
            "guest_name": req.guest_name,
            "guest_phone": req.guest_phone,
            "from_iso": req.from_iso,
            "to_iso": req.to_iso,
            "nights": nights,
            "amount_cents": amount,
            "status": "confirmed" if req.confirm else "requested",
            "payments_txn_id": None,
        }
        if idempotency_key:
            state["bookings"][idempotency_key] = booking
        return booking

    def fake_get_booking(booking_id: str, s: object):
        # Suche innerhalb des idempotency-Mappings
        for b in state["bookings"].values():
            if b["id"] == booking_id:
                return b
        raise RuntimeError("not found in stub")

    monkeypatch.setattr(bff, "_use_stays_internal", lambda: True)
    monkeypatch.setattr(bff, "_STAYS_INTERNAL_AVAILABLE", True, raising=False)
    monkeypatch.setattr(bff, "_stays_internal_session", lambda: _DummySessionCtx())
    monkeypatch.setattr(bff, "_StaysQuoteReq", _QReq, raising=False)
    monkeypatch.setattr(bff, "_StaysBookReq", _BReq, raising=False)
    monkeypatch.setattr(bff, "_stays_quote", fake_quote, raising=False)
    monkeypatch.setattr(bff, "_stays_book", fake_book, raising=False)
    monkeypatch.setattr(bff, "_stays_get_booking", fake_get_booking, raising=False)


def test_stays_quote_and_book_flow_via_bff(client, monkeypatch):
    """
    Stays quote/book end-to-end test via the BFF with stubs:

    - /stays/quote returns nights + amount consistent with the stub logic
    - /stays/book creates a booking with the same nights + amount
    - /stays/bookings/{id} returns that booking
    """

    _setup_stays_stub(monkeypatch)

    body = {
        "listing_id": 1,
        "from_iso": "2024-01-01",
        "to_iso": "2024-01-04",
    }
    resp_q = client.post("/stays/quote", json=body)
    assert resp_q.status_code == 200
    q = resp_q.json()
    assert q["nights"] == 3
    assert q["amount_cents"] == 3 * 10_000

    book_body = {
        **body,
        "guest_name": "Test Guest",
        "guest_phone": "+491700000900",
        "guest_wallet_id": "w_guest",
        "confirm": True,
    }
    idem = f"stay-{uuid.uuid4().hex[:8]}"
    resp_b = client.post("/stays/book", json=book_body, headers={"Idempotency-Key": idem})
    assert resp_b.status_code == 200
    b = resp_b.json()
    assert b["nights"] == 3
    assert b["amount_cents"] == 3 * 10_000
    assert b["status"] == "confirmed"
    bid = b["id"]

    # Status-Endpoint
    resp_status = client.get(f"/stays/bookings/{bid}")
    assert resp_status.status_code == 200
    st = resp_status.json()
    assert st["id"] == bid
    assert st["amount_cents"] == b["amount_cents"]


def test_stays_book_idempotency_via_bff(client, monkeypatch):
    """
    Verify idempotency of /stays/book via BFF: same
    Idempotency-Key must return the same booking.
    """

    _setup_stays_stub(monkeypatch)

    body = {
        "listing_id": 2,
        "from_iso": "2024-02-10",
        "to_iso": "2024-02-12",
        "guest_name": "Repeat Guest",
        "guest_phone": "+491700000901",
        "guest_wallet_id": "w_repeat",
        "confirm": False,
    }
    idem = f"stay-{uuid.uuid4().hex[:8]}"
    resp1 = client.post("/stays/book", json=body, headers={"Idempotency-Key": idem})
    assert resp1.status_code == 200
    b1 = resp1.json()

    resp2 = client.post("/stays/book", json=body, headers={"Idempotency-Key": idem})
    assert resp2.status_code == 200
    b2 = resp2.json()

    # Both responses must represent the same booking
    assert b1["id"] == b2["id"]
    assert b1["amount_cents"] == b2["amount_cents"]
    assert b1["nights"] == b2["nights"]
