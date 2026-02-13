from __future__ import annotations

import uuid
from datetime import datetime, timezone, timedelta

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session

import apps.bus.app.main as bus  # type: ignore[import]


@pytest.fixture()
def bus_engine():
    """
    Isolated SQLite engine for Bus domain tests.
    Uses the Bus models without modifying the global engine.
    """

    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        pool_pre_ping=True,
    )
    bus.Base.metadata.create_all(engine)
    return engine


def _setup_basic_trip(session: Session) -> str:
    c1 = bus.City(id=str(uuid.uuid4()), name="Origin", country=None)
    c2 = bus.City(id=str(uuid.uuid4()), name="Dest", country=None)
    op = bus.Operator(id=str(uuid.uuid4()), name="BusCo", wallet_id=None, is_online=1)
    session.add_all([c1, c2, op])
    session.commit()

    rt = bus.Route(id=str(uuid.uuid4()), origin_city_id=c1.id, dest_city_id=c2.id, operator_id=op.id)
    session.add(rt)
    session.commit()

    dep = datetime.now(timezone.utc) + timedelta(days=1)
    arr = dep + timedelta(hours=2)
    t = bus.Trip(
        id=str(uuid.uuid4()),
        route_id=rt.id,
        depart_at=dep,
        arrive_at=arr,
        price_cents=20_000,
        currency="SYP",
        seats_total=12,
        seats_available=12,
    )
    session.add(t)
    session.commit()
    return t.id


def test_operator_offline_blocks_trip_create_and_publish(bus_engine):
    with Session(bus_engine) as s:
        # Cities
        c1 = bus.City(id=str(uuid.uuid4()), name="Origin", country=None)
        c2 = bus.City(id=str(uuid.uuid4()), name="Dest", country=None)
        s.add_all([c1, c2]); s.commit()
        # Operator offline
        op = bus.Operator(id=str(uuid.uuid4()), name="OffCo", wallet_id=None, is_online=0)
        s.add(op); s.commit()
        # Route
        rt = bus.Route(id=str(uuid.uuid4()), origin_city_id=c1.id, dest_city_id=c2.id, operator_id=op.id)
        s.add(rt); s.commit()
        # Trip create should fail while operator offline
        body = bus.TripIn(route_id=rt.id, depart_at_iso=datetime.now(timezone.utc).isoformat(), arrive_at_iso=(datetime.now(timezone.utc)+timedelta(hours=1)).isoformat(), price_cents=1000, currency="SYP", seats_total=10)
        with pytest.raises(HTTPException):
            bus.create_trip(body=body, s=s)
        # Bring operator online, now create succeeds
        op.is_online = 1; s.add(op); s.commit(); s.refresh(op)
        trip = bus.create_trip(body=body, s=s)
        assert trip.status == "draft"
        # Publish while online works
        pub = bus.publish_trip(trip_id=trip.id, s=s)
        assert pub.status == "published"


def test_book_trip_reduces_available_seats_and_creates_booking(bus_engine):
    engine = bus_engine

    with Session(engine) as s:
        trip_id = _setup_basic_trip(s)

        body = bus.BookReq(seats=3, wallet_id=None, customer_phone="+491700000801")
        booking = bus.book_trip(trip_id=trip_id, body=body, idempotency_key=None, s=s)

        assert booking.trip_id == trip_id
        assert booking.seats == 3
        assert booking.status == "pending"

        # seats_available reduced
        t = s.get(bus.Trip, trip_id)
        assert t is not None
        assert t.seats_total == 12
        assert t.seats_available == 9

        # Exactly one booking row
        rows = s.execute(select(bus.Booking)).scalars().all()
        assert len(rows) == 1
        b0 = rows[0]
        assert b0.seats == 3
        assert b0.status == "pending"


def test_book_trip_idempotency(bus_engine):
    engine = bus_engine

    with Session(engine) as s:
        trip_id = _setup_basic_trip(s)
        body = bus.BookReq(seats=2, wallet_id=None, customer_phone="+491700000804")
        key = f"idem-{uuid.uuid4().hex[:8]}"

        first = bus.book_trip(trip_id=trip_id, body=body, idempotency_key=key, s=s)
        second = bus.book_trip(trip_id=trip_id, body=body, idempotency_key=key, s=s)

        assert first.id == second.id
        assert first.seats == second.seats
        assert first.status == second.status

        # Only one booking row and seats_available reduced only once
        rows = s.execute(select(bus.Booking)).scalars().all()
        assert len(rows) == 1
        t = s.get(bus.Trip, trip_id)
        assert t is not None
        assert t.seats_available == 10  # 12 - 2
