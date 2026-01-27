import uuid
from datetime import datetime, timezone

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

import apps.taxi.app.main as taxi  # type: ignore[import]


@pytest.fixture()
def taxi_engine(monkeypatch):
    """
    Isolated in-memory SQLite engine for Taxi domain tests.
    """
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        future=True,
    )
    taxi.Base.metadata.create_all(engine)
    # Keep fares deterministic
    monkeypatch.setattr(taxi, "_notify_driver_new_ride", lambda *args, **kwargs: None, raising=False)
    monkeypatch.setattr(taxi, "_surge_multiplier", lambda *args, **kwargs: 1.0, raising=False)
    # Cash mode avoids wallet plumbing in these unit tests.
    monkeypatch.setattr(taxi, "CASH_ONLY", 1, raising=False)
    return engine


def _add_driver(session: Session, **overrides):
    d = taxi.Driver(
        id=str(uuid.uuid4()),
        name="Driver",
        phone=overrides.get("phone") or "+491700000300",
        status="online",
        lat=overrides.get("lat", 0.0),
        lon=overrides.get("lon", 0.0),
        is_blocked=False,
        balance_cents=overrides.get("balance_cents", 1_000_000),
        wallet_id=overrides.get("wallet_id") or "wallet_driver",
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )
    session.add(d)
    session.commit()
    session.refresh(d)
    return d


def test_idempotency_is_endpoint_scoped(taxi_engine):
    """
    Same idempotency key works for the same endpoint, but reusing it
    across different endpoints is rejected with 409.
    """
    with Session(taxi_engine) as s:
        _add_driver(s)
        req = taxi.RideRequest(
            pickup_lat=0.0,
            pickup_lon=0.0,
            dropoff_lat=0.01,
            dropoff_lon=0.0,
            rider_phone="+491700000301",
            rider_wallet_id=None,
        )
        ride1 = taxi.request_ride(req=req, idempotency_key="idem-x", s=s)
        ride2 = taxi.request_ride(req=req, idempotency_key="idem-x", s=s)
        assert ride1.id == ride2.id

        with pytest.raises(HTTPException) as excinfo:
            taxi.book_and_pay(req=req, idempotency_key="idem-x", s=s)
        assert excinfo.value.status_code == 409


def test_driver_with_active_ride_is_not_reassigned(taxi_engine):
    """
    A driver already on an active ride is skipped for new assignments.
    """
    with Session(taxi_engine) as s:
        _add_driver(s)
        req = taxi.RideRequest(
            pickup_lat=0.0,
            pickup_lon=0.0,
            dropoff_lat=0.02,
            dropoff_lon=0.0,
            rider_phone="+491700000302",
            rider_wallet_id=None,
        )
        ride1 = taxi.request_ride(req=req, idempotency_key=None, s=s)
        assert ride1.driver_id is not None
        assert ride1.status == "assigned"

        ride2 = taxi.request_ride(req=req, idempotency_key="idem-new", s=s)
        assert ride2.driver_id is None
        assert ride2.status == "requested"


def test_book_and_pay_uses_tariff_fare(taxi_engine):
    """
    book_and_pay should use the tariff-based fare estimation.
    """
    with Session(taxi_engine) as s:
        _add_driver(s)
        req = taxi.RideRequest(
            pickup_lat=0.0,
            pickup_lon=0.0,
            dropoff_lat=0.05,
            dropoff_lon=0.0,
            rider_phone="+491700000303",
            rider_wallet_id=None,
            vehicle_class="classic",
        )
        km = taxi._haversine_km(req.pickup_lat, req.pickup_lon, req.dropoff_lat, req.dropoff_lon)
        eta_min = taxi._eta_min_from_km(km)
        expected_fare = taxi._estimate_fare_cents(km, eta_min, req.vehicle_class)

        ride = taxi.book_and_pay(req=req, idempotency_key=None, s=s)

        assert ride.fare_cents == expected_fare
        assert ride.driver_id is not None
        assert ride.status == "assigned"
