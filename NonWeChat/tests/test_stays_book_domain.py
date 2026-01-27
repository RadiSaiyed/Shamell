from __future__ import annotations

import uuid
from datetime import datetime

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session

import apps.stays.app.main as stays  # type: ignore[import]


@pytest.fixture()
def stays_engine():
    """
    Isolated SQLite engine for Stays domain tests.
    Uses the Stays models without modifying the global engine.
    """

    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        pool_pre_ping=True,
    )
    stays.Base.metadata.create_all(engine)
    return engine


def _create_simple_listing(session: Session) -> int:
    l = stays.Listing(
        title="Test Stay",
        city="Damascus",
        address=None,
        description=None,
        image_urls=None,
        price_per_night_cents=10_000,
        operator_id=None,
        owner_wallet_id=None,
        property_type=None,
        room_type_id=None,
        property_id=None,
    )
    session.add(l)
    session.commit()
    session.refresh(l)
    return int(l.id)


def test_stays_quote_basic_nights_and_amount(stays_engine):
    engine = stays_engine

    with Session(engine) as s:
        lid = _create_simple_listing(s)
        req = stays.QuoteReq(listing_id=lid, from_iso="2024-01-01", to_iso="2024-01-04")
        out = stays.quote(req=req, s=s)

        assert out.nights == 3
        assert out.amount_cents == 3 * 10_000
        assert out.currency
        assert out.days is not None
        assert len(out.days) == 3


def test_stays_book_rejects_overlapping_booking(stays_engine):
    engine = stays_engine

    with Session(engine) as s:
        lid = _create_simple_listing(s)
        # First booking 2024-03-01 to 2024-03-04
        req1 = stays.BookReq(
            listing_id=lid,
            guest_name="Guest1",
            guest_phone="+491700000910",
            guest_wallet_id=None,
            from_iso="2024-03-01",
            to_iso="2024-03-04",
            confirm=False,
        )
        stays.book(req=req1, idempotency_key=None, s=s)

        # Second booking with overlapping dates must raise HTTPException 409
        req2 = stays.BookReq(
            listing_id=lid,
            guest_name="Guest2",
            guest_phone="+491700000911",
            guest_wallet_id=None,
            from_iso="2024-03-02",
            to_iso="2024-03-05",
            confirm=False,
        )
        with pytest.raises(HTTPException) as excinfo:
            stays.book(req=req2, idempotency_key=None, s=s)
        assert excinfo.value.status_code == 409
        assert "not available" in str(excinfo.value.detail)
