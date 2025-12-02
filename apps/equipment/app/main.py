from fastapi import FastAPI, HTTPException, Depends, Request, Header, APIRouter
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field, ConfigDict
from typing import Optional, List
import os
import uuid
import math
from datetime import datetime, timezone, timedelta
import httpx
from shamell_shared import RequestIDMiddleware, configure_cors, add_standard_health, setup_json_logging
from sqlalchemy import create_engine, String, Integer, BigInteger, DateTime, Float, func, text, inspect
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, Session
from sqlalchemy import select
from math import radians, sin, cos, sqrt, atan2


def _env_or(key: str, default: str) -> str:
    v = os.getenv(key)
    return v if v is not None else default


app = FastAPI(title="Equipment Rental API", version="0.1.0")
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", "*"))
add_standard_health(app)

router = APIRouter()


DB_URL = _env_or("DB_URL", "sqlite+pysqlite:////tmp/equipment.db")
DB_SCHEMA = os.getenv("DB_SCHEMA") if not DB_URL.startswith("sqlite") else None
PAYMENTS_BASE = _env_or("PAYMENTS_BASE_URL", "")
DELIVERY_BASE_CENTS = int(_env_or("EQUIPMENT_DELIVERY_BASE_CENTS", "0"))
DELIVERY_PER_KM_CENTS = float(_env_or("EQUIPMENT_DELIVERY_PER_KM_CENTS", "0"))
DEFAULT_DEPOSIT_PCT = float(_env_or("EQUIPMENT_DEFAULT_DEPOSIT_PCT", "0"))
ORS_BASE = _env_or("ORS_BASE_URL", "")
ORS_API_KEY = os.getenv("ORS_API_KEY", "")
MEDIA_BASE_URL = _env_or("MEDIA_BASE_URL", "")
MEDIA_DIR = _env_or("EQUIPMENT_MEDIA_DIR", "/tmp/equipment_media")


class Base(DeclarativeBase):
    pass


class Equipment(Base):
    __tablename__ = "equipment"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(200))
    category: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    subcategory: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    brand: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    model: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    year: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    city: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    latitude: Mapped[Optional[float]] = mapped_column(Float, default=None)
    longitude: Mapped[Optional[float]] = mapped_column(Float, default=None)
    daily_rate_cents: Mapped[Optional[int]] = mapped_column(BigInteger, default=None)
    weekly_rate_cents: Mapped[Optional[int]] = mapped_column(BigInteger, default=None)
    monthly_rate_cents: Mapped[Optional[int]] = mapped_column(BigInteger, default=None)
    delivery_fee_cents: Mapped[Optional[int]] = mapped_column(BigInteger, default=None)
    delivery_per_km_cents: Mapped[Optional[float]] = mapped_column(Float, default=None)
    deposit_cents: Mapped[Optional[int]] = mapped_column(BigInteger, default=None)
    currency: Mapped[str] = mapped_column(String(3), default="SYP")
    quantity: Mapped[int] = mapped_column(Integer, default=1)
    status: Mapped[str] = mapped_column(String(24), default="available")  # available|maintenance|reserved|retired
    tags: Mapped[Optional[str]] = mapped_column(String(200), default=None)
    image_url: Mapped[Optional[str]] = mapped_column(String(512), default=None)
    owner_wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    notes: Mapped[Optional[str]] = mapped_column(String(500), default=None)
    specs: Mapped[Optional[str]] = mapped_column(String(500), default=None)
    weight_kg: Mapped[Optional[float]] = mapped_column(Float, default=None)
    power_kw: Mapped[Optional[float]] = mapped_column(Float, default=None)
    min_rental_days: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    max_rental_days: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    weekend_surcharge_pct: Mapped[Optional[float]] = mapped_column(Float, default=None)
    longterm_discount_pct: Mapped[Optional[float]] = mapped_column(Float, default=None)
    min_notice_hours: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Booking(Base):
    __tablename__ = "equipment_bookings"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    equipment_id: Mapped[int] = mapped_column(Integer)
    renter_name: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    renter_phone: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    renter_wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    from_ts: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True))
    to_ts: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True))
    quantity: Mapped[int] = mapped_column(Integer, default=1)
    status: Mapped[str] = mapped_column(String(20), default="requested")  # requested|confirmed|active|completed|canceled
    amount_cents: Mapped[Optional[int]] = mapped_column(BigInteger, default=None)
    currency: Mapped[str] = mapped_column(String(3), default="SYP")
    payments_txn_id: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    delivery_required: Mapped[bool] = mapped_column(Integer, default=0)
    delivery_address: Mapped[Optional[str]] = mapped_column(String(300), default=None)
    delivery_lat: Mapped[Optional[float]] = mapped_column(Float, default=None)
    delivery_lon: Mapped[Optional[float]] = mapped_column(Float, default=None)
    pickup_address: Mapped[Optional[str]] = mapped_column(String(300), default=None)
    notes: Mapped[Optional[str]] = mapped_column(String(500), default=None)
    attachments: Mapped[Optional[str]] = mapped_column(String(500), default=None)
    project: Mapped[Optional[str]] = mapped_column(String(200), default=None)
    po: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    insurance: Mapped[bool] = mapped_column(Integer, default=0)
    damage_waiver: Mapped[bool] = mapped_column(Integer, default=0)
    delivery_window_start: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), default=None)
    delivery_window_end: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), default=None)
    invoice_id: Mapped[Optional[str]] = mapped_column(String(40), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class AvailabilityBlock(Base):
    __tablename__ = "equipment_availability"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    equipment_id: Mapped[int] = mapped_column(Integer)
    from_ts: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True))
    to_ts: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True))
    reason: Mapped[Optional[str]] = mapped_column(String(200), default=None)  # maintenance|external|hold
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class DeliveryTask(Base):
    __tablename__ = "equipment_tasks"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    booking_id: Mapped[str] = mapped_column(String(36))
    kind: Mapped[str] = mapped_column(String(16))  # delivery|pickup
    status: Mapped[str] = mapped_column(String(20), default="pending")  # pending|en_route|completed|canceled
    scheduled_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), default=None)
    address: Mapped[Optional[str]] = mapped_column(String(300), default=None)
    lat: Mapped[Optional[float]] = mapped_column(Float, default=None)
    lon: Mapped[Optional[float]] = mapped_column(Float, default=None)
    assignee: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    notes: Mapped[Optional[str]] = mapped_column(String(500), default=None)
    window_start: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), default=None)
    window_end: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), default=None)
    eta_minutes: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    driver_name: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    driver_phone: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    route_geojson: Mapped[Optional[str]] = mapped_column(String(4000), default=None)
    distance_km: Mapped[Optional[float]] = mapped_column(Float, default=None)
    arrived_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), default=None)
    completed_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), default=None)
    proof_photo_url: Mapped[Optional[str]] = mapped_column(String(500), default=None)
    proof_note: Mapped[Optional[str]] = mapped_column(String(500), default=None)
    signature_name: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Invoice(Base):
    __tablename__ = "equipment_invoices"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    booking_id: Mapped[str] = mapped_column(String(36))
    amount_cents: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), default="SYP")
    status: Mapped[str] = mapped_column(String(16), default="open")  # open|paid|canceled
    issued_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    due_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), default=None)
    paid_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), default=None)


class Idempotency(Base):
    __tablename__ = "equipment_idempotency"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    key: Mapped[str] = mapped_column(String(120), primary_key=True)
    ref_id: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


engine = create_engine(DB_URL, future=True)


def get_session() -> Session:
    with Session(engine) as s:
        yield s


def _startup():
    Base.metadata.create_all(engine)
    insp = inspect(engine)
    try:
        os.makedirs(MEDIA_DIR, exist_ok=True)
    except Exception:
        pass
    if insp.has_table("equipment", schema=DB_SCHEMA):
        cols = {c["name"] for c in insp.get_columns("equipment", schema=DB_SCHEMA)}
        tbl = f'{"%s." % DB_SCHEMA if DB_SCHEMA else ""}equipment'

        def _add(col_sql: str):
            try:
                with engine.begin() as conn:
                    conn.execute(text(col_sql))
            except Exception:
                pass
        if "delivery_per_km_cents" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN delivery_per_km_cents FLOAT")
        if "notes" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN notes VARCHAR(500)")
        if "monthly_rate_cents" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN monthly_rate_cents BIGINT")
        if "subcategory" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN subcategory VARCHAR(64)")
        if "specs" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN specs VARCHAR(500)")
        if "weight_kg" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN weight_kg FLOAT")
        if "power_kw" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN power_kw FLOAT")
        if "min_rental_days" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN min_rental_days INTEGER")
        if "max_rental_days" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN max_rental_days INTEGER")
        if "weekend_surcharge_pct" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN weekend_surcharge_pct FLOAT")
        if "longterm_discount_pct" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN longterm_discount_pct FLOAT")
        if "min_notice_hours" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN min_notice_hours INTEGER")
    if insp.has_table("equipment_bookings", schema=DB_SCHEMA):
        cols = {c["name"] for c in insp.get_columns("equipment_bookings", schema=DB_SCHEMA)}
        tbl = f'{"%s." % DB_SCHEMA if DB_SCHEMA else ""}equipment_bookings'
        def _add(col_sql: str):
            try:
                with engine.begin() as conn:
                    conn.execute(text(col_sql))
            except Exception:
                pass
        if "quantity" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN quantity INTEGER DEFAULT 1")
        if "notes" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN notes VARCHAR(500)")
        if "pickup_address" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN pickup_address VARCHAR(300)")
        if "delivery_lat" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN delivery_lat FLOAT")
        if "delivery_lon" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN delivery_lon FLOAT")
        if "currency" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN currency VARCHAR(3) DEFAULT 'SYP'")
        if "attachments" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN attachments VARCHAR(500)")
        if "project" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN project VARCHAR(200)")
        if "po" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN po VARCHAR(120)")
        if "insurance" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN insurance INTEGER DEFAULT 0")
        if "damage_waiver" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN damage_waiver INTEGER DEFAULT 0")
        if "delivery_window_start" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN delivery_window_start TIMESTAMPTZ")
        if "delivery_window_end" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN delivery_window_end TIMESTAMPTZ")
    # Ensure availability table exists
    if not insp.has_table("equipment_availability", schema=DB_SCHEMA):
        Base.metadata.create_all(engine, tables=[AvailabilityBlock.__table__])
    # Ensure task columns
    if insp.has_table("equipment_tasks", schema=DB_SCHEMA):
        cols = {c["name"] for c in insp.get_columns("equipment_tasks", schema=DB_SCHEMA)}
        tbl = f'{"%s." % DB_SCHEMA if DB_SCHEMA else ""}equipment_tasks'
        def _add(col_sql: str):
            try:
                with engine.begin() as conn:
                    conn.execute(text(col_sql))
            except Exception:
                pass
        if "window_start" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN window_start TIMESTAMPTZ")
        if "window_end" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN window_end TIMESTAMPTZ")
        if "eta_minutes" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN eta_minutes INTEGER")
        if "driver_name" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN driver_name VARCHAR(120)")
        if "driver_phone" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN driver_phone VARCHAR(32)")
        if "route_geojson" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN route_geojson VARCHAR(4000)")
        if "distance_km" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN distance_km FLOAT")
        if "arrived_at" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN arrived_at TIMESTAMPTZ")
        if "completed_at" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN completed_at TIMESTAMPTZ")
        if "proof_photo_url" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN proof_photo_url VARCHAR(500)")
        if "proof_note" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN proof_note VARCHAR(500)")
        if "signature_name" not in cols:
            _add(f"ALTER TABLE {tbl} ADD COLUMN signature_name VARCHAR(120)")

app.router.on_startup.append(_startup)


def _parse_dt(raw: str) -> datetime:
    return datetime.fromisoformat(raw.replace("Z", "+00:00")).astimezone(timezone.utc)


def _overlaps(a_start: datetime, a_end: datetime, b_start: datetime, b_end: datetime) -> bool:
    return (a_start < b_end) and (a_end > b_start)


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371.0
    dlat = radians(lat2 - lat1)
    dlon = radians(lon2 - lon1)
    a = sin(dlat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon / 2) ** 2
    c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return r * c


def _route_info(start_lat: float, start_lon: float, end_lat: float, end_lon: float) -> tuple[float, list[list[float]]]:
    """
    Best-effort routing distance (km) and polyline using ORS when configured, otherwise haversine fallback.
    """
    try:
        points: list[list[float]] = []
        if ORS_BASE:
            import json
            url = ORS_BASE.rstrip("/") + "/v2/directions/driving-car"
            headers = {"accept": "application/json", "content-type": "application/json"}
            if ORS_API_KEY:
                headers["Authorization"] = ORS_API_KEY
            body = {"coordinates": [[start_lon, start_lat], [end_lon, end_lat]], "geometry": True}
            r = httpx.post(url, json=body, headers=headers, timeout=10)
            if r.status_code < 300:
                data = r.json()
                routes = data.get("routes") or data.get("features") or []
                if routes:
                    route = routes[0]
                    summary = route.get("summary") or {}
                    try:
                        dist_m = float(summary.get("distance") or summary.get("lengthInMeters") or 0.0)
                    except Exception:
                        dist_m = 0.0
                    # geometry
                    try:
                        geom = route.get("geometry")
                        coords = []
                        if isinstance(geom, dict):
                            coords = geom.get("coordinates") or []
                        elif isinstance(geom, list):
                            coords = geom
                        for c in coords:
                            if isinstance(c, (list, tuple)) and len(c) >= 2:
                                lon, lat = float(c[0]), float(c[1])
                                points.append([lat, lon])
                    except Exception:
                        points = []
                    if dist_m > 0:
                        return round(dist_m / 1000.0, 2), points
        km = round(_haversine_km(start_lat, start_lon, end_lat, end_lon), 2)
        # simple straight line poly
        points = [[start_lat, start_lon], [end_lat, end_lon]]
        return km, points
    except Exception:
        km = round(_haversine_km(start_lat, start_lon, end_lat, end_lon), 2)
        return km, [[start_lat, start_lon], [end_lat, end_lon]]


def _available_quantity(equipment_id: int, start: datetime, end: datetime, s: Session) -> int:
    reserved = 0
    rows = s.execute(
        select(Booking).where(
            Booking.equipment_id == equipment_id,
            Booking.status.in_(["requested", "confirmed", "active"]),
        )
    ).scalars().all()
    for b in rows:
        if b.from_ts and b.to_ts and _overlaps(start, end, b.from_ts, b.to_ts):
            reserved += int(b.quantity or 0)
    eq = s.get(Equipment, equipment_id)
    total = int(eq.quantity if eq and eq.quantity else 1)
    return max(0, total - reserved)


def _quote_amount(
    eq: Equipment,
    start: datetime,
    end: datetime,
    quantity: int,
    delivery_required: bool,
    delivery_km: Optional[float],
    delivery_lat: Optional[float],
    delivery_lon: Optional[float],
    eq_lat: Optional[float],
    eq_lon: Optional[float],
    include_deposit: bool,
    ignore_min_days: bool = False,
) -> tuple[int, int, int, str, int, float, int, Optional[list[list[float]]]]:
    hours = max(0.0, (end - start).total_seconds() / 3600.0)
    days = math.ceil(hours / 24.0) if hours > 0 else 1
    if eq.min_rental_days and not ignore_min_days:
        days = max(days, int(eq.min_rental_days))
    weekend_days = 0
    try:
        d = start
        while d < end:
            if d.weekday() >= 4:  # Fri/Sat/Sun
                weekend_days += 1
            d += timedelta(days=1)
    except Exception:
        weekend_days = 0
    daily = eq.daily_rate_cents or 0
    weekly = eq.weekly_rate_cents or 0
    monthly = eq.monthly_rate_cents or 0
    rental = 0
    if monthly > 0 and days >= 30:
        rental = monthly * math.ceil(days / 30.0)
        # Compare to weekly/daily for better price to renter
        if weekly > 0:
            rental = min(rental, weekly * math.ceil(days / 7.0))
        if daily > 0:
            rental = min(rental, daily * days)
    elif weekly > 0 and days >= 7:
        rental = min(daily * days if daily > 0 else weekly * math.ceil(days / 7.0), weekly * math.ceil(days / 7.0))
    elif daily > 0:
        rental = daily * days
    if rental < 0:
        rental = 0
    rental *= max(1, quantity)
    if eq.weekend_surcharge_pct and eq.weekend_surcharge_pct > 0 and daily > 0 and weekend_days > 0:
        rental += int(math.ceil(daily * weekend_days * (eq.weekend_surcharge_pct / 100.0)))
    if eq.longterm_discount_pct and eq.longterm_discount_pct > 0 and days >= 14:
        rental = int(max(0, rental - math.floor(rental * (eq.longterm_discount_pct / 100.0))))
    delivery = 0
    route_points: Optional[list[list[float]]] = None
    if delivery_required:
        if eq.delivery_fee_cents:
            delivery += int(eq.delivery_fee_cents)
        else:
            delivery += DELIVERY_BASE_CENTS
        km_val = delivery_km if delivery_km is not None else 0
        if km_val == 0 and delivery_lat is not None and delivery_lon is not None and eq_lat is not None and eq_lon is not None:
            try:
                km_val, pts = _route_info(eq_lat, eq_lon, delivery_lat, delivery_lon)
                route_points = pts or None
            except Exception:
                km_val = 0
        per_km = eq.delivery_per_km_cents if eq.delivery_per_km_cents is not None else DELIVERY_PER_KM_CENTS
        if per_km and km_val and km_val > 0:
            delivery += int(math.ceil(per_km * km_val))
    deposit = 0
    if include_deposit:
        if eq.deposit_cents:
            deposit = int(eq.deposit_cents)
        elif DEFAULT_DEPOSIT_PCT > 0:
            deposit = int(math.ceil(rental * DEFAULT_DEPOSIT_PCT / 100.0))
    if eq.max_rental_days and days > eq.max_rental_days:
        raise HTTPException(status_code=400, detail="exceeds max rental days")
    total = rental + delivery + deposit
    currency = eq.currency or "SYP"
    return rental, delivery, deposit, currency, total, hours, days, route_points


class EquipmentCreate(BaseModel):
    title: str
    category: Optional[str] = None
    subcategory: Optional[str] = None
    brand: Optional[str] = None
    model: Optional[str] = None
    year: Optional[int] = Field(default=None, ge=1950, le=2100)
    city: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    daily_rate_cents: Optional[int] = Field(default=None, ge=0)
    weekly_rate_cents: Optional[int] = Field(default=None, ge=0)
    monthly_rate_cents: Optional[int] = Field(default=None, ge=0)
    delivery_fee_cents: Optional[int] = Field(default=None, ge=0)
    delivery_per_km_cents: Optional[float] = Field(default=None, ge=0)
    deposit_cents: Optional[int] = Field(default=None, ge=0)
    currency: str = Field(default="SYP", min_length=3, max_length=3)
    quantity: int = Field(default=1, ge=1, le=500)
    status: str = Field(default="available")
    tags: Optional[str] = None
    image_url: Optional[str] = None
    owner_wallet_id: Optional[str] = None
    notes: Optional[str] = None
    specs: Optional[str] = None
    weight_kg: Optional[float] = Field(default=None, ge=0)
    power_kw: Optional[float] = Field(default=None, ge=0)
    min_rental_days: Optional[int] = Field(default=None, ge=1, le=365)
    max_rental_days: Optional[int] = Field(default=None, ge=1, le=365)
    weekend_surcharge_pct: Optional[float] = Field(default=None, ge=0, le=200)
    longterm_discount_pct: Optional[float] = Field(default=None, ge=0, le=100)
    min_notice_hours: Optional[int] = Field(default=None, ge=0, le=720)


class EquipmentUpdate(BaseModel):
    title: Optional[str] = None
    category: Optional[str] = None
    subcategory: Optional[str] = None
    brand: Optional[str] = None
    model: Optional[str] = None
    year: Optional[int] = Field(default=None, ge=1950, le=2100)
    city: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    daily_rate_cents: Optional[int] = Field(default=None, ge=0)
    weekly_rate_cents: Optional[int] = Field(default=None, ge=0)
    monthly_rate_cents: Optional[int] = Field(default=None, ge=0)
    delivery_fee_cents: Optional[int] = Field(default=None, ge=0)
    delivery_per_km_cents: Optional[float] = Field(default=None, ge=0)
    deposit_cents: Optional[int] = Field(default=None, ge=0)
    currency: Optional[str] = Field(default=None, min_length=3, max_length=3)
    quantity: Optional[int] = Field(default=None, ge=1, le=500)
    status: Optional[str] = None
    tags: Optional[str] = None
    image_url: Optional[str] = None
    owner_wallet_id: Optional[str] = None
    notes: Optional[str] = None
    specs: Optional[str] = None
    weight_kg: Optional[float] = Field(default=None, ge=0)
    power_kw: Optional[float] = Field(default=None, ge=0)
    min_rental_days: Optional[int] = Field(default=None, ge=1, le=365)
    max_rental_days: Optional[int] = Field(default=None, ge=1, le=365)
    weekend_surcharge_pct: Optional[float] = Field(default=None, ge=0, le=200)
    longterm_discount_pct: Optional[float] = Field(default=None, ge=0, le=100)
    min_notice_hours: Optional[int] = Field(default=None, ge=0, le=720)


class EquipmentOut(BaseModel):
    id: int
    title: str
    category: Optional[str]
    subcategory: Optional[str]
    brand: Optional[str]
    model: Optional[str]
    year: Optional[int]
    city: Optional[str]
    latitude: Optional[float]
    longitude: Optional[float]
    daily_rate_cents: Optional[int]
    weekly_rate_cents: Optional[int]
    monthly_rate_cents: Optional[int]
    delivery_fee_cents: Optional[int]
    delivery_per_km_cents: Optional[float]
    deposit_cents: Optional[int]
    currency: str
    quantity: int
    status: str
    tags: Optional[str]
    image_url: Optional[str]
    owner_wallet_id: Optional[str]
    notes: Optional[str]
    specs: Optional[str]
    weight_kg: Optional[float]
    power_kw: Optional[float]
    min_rental_days: Optional[int]
    max_rental_days: Optional[int]
    weekend_surcharge_pct: Optional[float]
    longterm_discount_pct: Optional[float]
    min_notice_hours: Optional[int]
    available_quantity: Optional[int] = None
    distance_km: Optional[float] = None
    model_config = ConfigDict(from_attributes=True)


class QuoteReq(BaseModel):
    equipment_id: int
    from_iso: str
    to_iso: str
    quantity: int = Field(default=1, ge=1, le=500)
    delivery_required: bool = False
    delivery_km: Optional[float] = Field(default=None, ge=0)
    delivery_lat: Optional[float] = None
    delivery_lon: Optional[float] = None
    include_deposit: bool = True
    ignore_min_days: bool = False


class QuoteOut(BaseModel):
    hours: float
    days: float
    rental_cents: int
    delivery_cents: int
    deposit_cents: int
    total_cents: int
    currency: str
    min_days_applied: Optional[int] = None
    weekend_days: Optional[int] = None
    longterm_discount_pct: Optional[float] = None
    delivery_distance_km: Optional[float] = None
    delivery_route: Optional[list[list[float]]] = None


class BookReq(QuoteReq):
    renter_name: Optional[str] = None
    renter_phone: Optional[str] = None
    renter_wallet_id: Optional[str] = None
    confirm: bool = False
    delivery_address: Optional[str] = None
    pickup_address: Optional[str] = None
    delivery_scheduled_iso: Optional[str] = None
    pickup_scheduled_iso: Optional[str] = None
    delivery_window_start_iso: Optional[str] = None
    delivery_window_end_iso: Optional[str] = None
    notes: Optional[str] = None
    project: Optional[str] = None
    po: Optional[str] = None
    insurance: Optional[bool] = None
    damage_waiver: Optional[bool] = None
    attachments: Optional[list[str]] = None


class TaskOut(BaseModel):
    id: str
    kind: str
    status: str
    scheduled_iso: Optional[str] = None
    address: Optional[str] = None
    lat: Optional[float] = None
    lon: Optional[float] = None
    assignee: Optional[str] = None
    window_start_iso: Optional[str] = None
    window_end_iso: Optional[str] = None
    eta_minutes: Optional[int] = None
    driver_name: Optional[str] = None
    driver_phone: Optional[str] = None
    route: Optional[list[list[float]]] = None
    distance_km: Optional[float] = None
    arrived_iso: Optional[str] = None
    completed_iso: Optional[str] = None
    proof_photo_url: Optional[str] = None
    proof_note: Optional[str] = None
    signature_name: Optional[str] = None


class InvoiceOut(BaseModel):
    id: str
    status: str
    amount_cents: int
    currency: str
    due_iso: Optional[str] = None
    paid_iso: Optional[str] = None
    issued_iso: Optional[str] = None
    pdf_url: Optional[str] = None


class BookingOut(BaseModel):
    id: str
    equipment_id: int
    renter_name: Optional[str]
    renter_phone: Optional[str]
    renter_wallet_id: Optional[str]
    from_iso: str
    to_iso: str
    quantity: int
    status: str
    amount_cents: Optional[int]
    currency: str
    payments_txn_id: Optional[str]
    delivery_required: bool
    delivery_address: Optional[str]
    delivery_lat: Optional[float] = None
    delivery_lon: Optional[float] = None
    delivery_distance_km: Optional[float] = None
    pickup_address: Optional[str]
    notes: Optional[str]
    attachments: Optional[list[str]] = None
    project: Optional[str] = None
    po: Optional[str] = None
    insurance: Optional[bool] = None
    damage_waiver: Optional[bool] = None
    delivery_window_start_iso: Optional[str] = None
    delivery_window_end_iso: Optional[str] = None
    tasks: List[TaskOut] = []
    invoice: Optional[InvoiceOut] = None
    model_config = ConfigDict(from_attributes=False)


class BookingStatusUpdate(BaseModel):
    status: str
    assignee: Optional[str] = None
    notes: Optional[str] = None


class TaskUpdate(BaseModel):
    kind: str  # delivery|pickup
    scheduled_iso: Optional[str] = None
    status: Optional[str] = None
    address: Optional[str] = None
    assignee: Optional[str] = None
    notes: Optional[str] = None
    window_start_iso: Optional[str] = None
    window_end_iso: Optional[str] = None
    eta_minutes: Optional[int] = Field(default=None, ge=0)
    driver_name: Optional[str] = None
    driver_phone: Optional[str] = None
    route: Optional[list[list[float]]] = None
    distance_km: Optional[float] = Field(default=None, ge=0)
    proof_photo_url: Optional[str] = None
    proof_note: Optional[str] = None
    signature_name: Optional[str] = None
    proof_photo_b64: Optional[str] = None  # optionally submit base64 image; stored best-effort
    proof_filename: Optional[str] = None
    pod_signed: Optional[bool] = None


def _pay_transfer(from_wallet: str, to_wallet: str, amount_cents: int, ikey: str, ref: str) -> dict:
    if not PAYMENTS_BASE:
        raise RuntimeError("PAYMENTS_BASE_URL not configured")
    url = PAYMENTS_BASE.rstrip("/") + "/transfer"
    headers = {
        "Content-Type": "application/json",
        "Idempotency-Key": ikey,
        "X-Merchant": "equipment",
        "X-Ref": ref,
    }
    payload = {"from_wallet_id": from_wallet, "to_wallet_id": to_wallet, "amount_cents": amount_cents}
    r = httpx.post(url, json=payload, headers=headers, timeout=10)
    r.raise_for_status()
    return r.json()


def _booking_to_out(b: Booking, s: Session) -> BookingOut:
    tasks = s.execute(select(DeliveryTask).where(DeliveryTask.booking_id == b.id)).scalars().all()
    task_out: List[TaskOut] = []
    delivery_distance = None
    for t in tasks:
        route = None
        try:
            import json
            route = json.loads(t.route_geojson) if t.route_geojson else None
        except Exception:
            route = None
        if t.kind == "delivery" and t.distance_km is not None:
            delivery_distance = t.distance_km
        task_out.append(
            TaskOut(
                id=t.id,
                kind=t.kind,
                status=t.status,
                scheduled_iso=t.scheduled_at.isoformat() if t.scheduled_at else None,
                address=t.address,
                lat=t.lat,
                lon=t.lon,
                assignee=t.assignee,
                window_start_iso=t.window_start.isoformat() if t.window_start else None,
                window_end_iso=t.window_end.isoformat() if t.window_end else None,
                eta_minutes=t.eta_minutes,
                driver_name=t.driver_name,
                driver_phone=t.driver_phone,
                route=route,
                distance_km=t.distance_km,
                arrived_iso=t.arrived_at.isoformat() if t.arrived_at else None,
                completed_iso=t.completed_at.isoformat() if t.completed_at else None,
                proof_photo_url=t.proof_photo_url,
                proof_note=t.proof_note,
                signature_name=t.signature_name,
            )
        )
    inv = None
    if b.invoice_id:
        inv_row = s.get(Invoice, b.invoice_id)
        if inv_row:
            inv = InvoiceOut(
                id=inv_row.id,
                status=inv_row.status,
                amount_cents=inv_row.amount_cents,
                currency=inv_row.currency,
                due_iso=inv_row.due_at.isoformat() if inv_row.due_at else None,
                paid_iso=inv_row.paid_at.isoformat() if inv_row.paid_at else None,
                issued_iso=inv_row.issued_at.isoformat() if inv_row.issued_at else None,
                pdf_url=f"/equipment/invoices/{inv_row.id}/pdf",
            )
    att_list = None
    try:
        att_list = [a for a in (b.attachments or "").split(",") if a]
    except Exception:
        att_list = None
    return BookingOut(
        id=b.id,
        equipment_id=b.equipment_id,
        renter_name=b.renter_name,
        renter_phone=b.renter_phone,
        renter_wallet_id=b.renter_wallet_id,
        from_iso=b.from_ts.isoformat() if b.from_ts else "",
        to_iso=b.to_ts.isoformat() if b.to_ts else "",
        quantity=b.quantity,
        status=b.status,
        amount_cents=b.amount_cents,
        currency=b.currency,
        payments_txn_id=b.payments_txn_id,
        delivery_required=bool(b.delivery_required),
        delivery_address=b.delivery_address,
        delivery_lat=b.delivery_lat,
        delivery_lon=b.delivery_lon,
        delivery_distance_km=delivery_distance,
        pickup_address=b.pickup_address,
        notes=b.notes,
        attachments=att_list,
        project=b.project,
        po=b.po,
        insurance=bool(b.insurance) if b.insurance is not None else None,
        damage_waiver=bool(b.damage_waiver) if b.damage_waiver is not None else None,
        delivery_window_start_iso=b.delivery_window_start.isoformat() if b.delivery_window_start else None,
        delivery_window_end_iso=b.delivery_window_end.isoformat() if b.delivery_window_end else None,
        tasks=task_out,
        invoice=inv,
    )


@router.post("/assets", response_model=EquipmentOut)
def create_asset(req: EquipmentCreate, s: Session = Depends(get_session)):
    e = Equipment(
        title=req.title.strip(),
        category=(req.category or None),
        brand=(req.brand or None),
        model=(req.model or None),
        year=req.year,
        city=(req.city or None),
        latitude=req.latitude,
        longitude=req.longitude,
        daily_rate_cents=req.daily_rate_cents,
        weekly_rate_cents=req.weekly_rate_cents,
        monthly_rate_cents=req.monthly_rate_cents,
        delivery_fee_cents=req.delivery_fee_cents,
        delivery_per_km_cents=req.delivery_per_km_cents,
        deposit_cents=req.deposit_cents,
        currency=req.currency.upper(),
        quantity=req.quantity,
        status=req.status,
        tags=(req.tags or None),
        image_url=(req.image_url or None),
        owner_wallet_id=(req.owner_wallet_id or None),
        notes=(req.notes or None),
        subcategory=(req.subcategory or None),
        specs=(req.specs or None),
        weight_kg=req.weight_kg,
        power_kw=req.power_kw,
        min_rental_days=req.min_rental_days,
        max_rental_days=req.max_rental_days,
    )
    s.add(e)
    s.commit()
    s.refresh(e)
    return EquipmentOut.model_validate(e, from_attributes=True)


@router.get("/assets", response_model=List[EquipmentOut])
def list_assets(
    q: str = "",
    city: str = "",
    category: str = "",
    subcategory: str = "",
    tag: str = "",
    status: str = "",
    available_only: bool = False,
    from_iso: str = "",
    to_iso: str = "",
    min_price: int = None,
    max_price: int = None,
    min_weight: float = None,
    max_weight: float = None,
    min_power: float = None,
    max_power: float = None,
    order: str = "newest",
    near_lat: float = None,
    near_lon: float = None,
    max_distance_km: float = None,
    limit: int = 50,
    s: Session = Depends(get_session),
):
    limit = max(1, min(limit, 200))
    start = end = None
    if from_iso and to_iso:
        try:
            start = _parse_dt(from_iso)
            end = _parse_dt(to_iso)
            if end <= start:
                raise ValueError("range")
        except Exception:
            raise HTTPException(status_code=400, detail="invalid time range")
    stmt = select(Equipment)
    if q:
        stmt = stmt.where(func.lower(Equipment.title).like(f"%{q.lower()}%"))
    if city:
        stmt = stmt.where(func.lower(Equipment.city) == city.lower())
    if category:
        stmt = stmt.where(func.lower(Equipment.category) == category.lower())
    if subcategory:
        stmt = stmt.where(func.lower(Equipment.subcategory) == subcategory.lower())
    if status:
        stmt = stmt.where(Equipment.status == status)
    if min_price is not None:
        stmt = stmt.where((Equipment.daily_rate_cents >= min_price) | (Equipment.weekly_rate_cents >= min_price) | (Equipment.monthly_rate_cents >= min_price))
    if max_price is not None and max_price > 0:
        stmt = stmt.where(
            (Equipment.daily_rate_cents <= max_price)
            | (Equipment.weekly_rate_cents <= max_price)
            | (Equipment.monthly_rate_cents <= max_price)
        )
    if tag:
        stmt = stmt.where(func.coalesce(Equipment.tags, "").ilike(f"%{tag}%"))
    if min_weight is not None:
        stmt = stmt.where(Equipment.weight_kg >= min_weight)
    if max_weight is not None:
        stmt = stmt.where(Equipment.weight_kg <= max_weight)
    if min_power is not None:
        stmt = stmt.where(Equipment.power_kw >= min_power)
    if max_power is not None:
        stmt = stmt.where(Equipment.power_kw <= max_power)
    if order == "price_asc":
        stmt = stmt.order_by(func.coalesce(Equipment.daily_rate_cents, Equipment.weekly_rate_cents, Equipment.monthly_rate_cents))
    elif order == "price_desc":
        stmt = stmt.order_by(func.coalesce(Equipment.daily_rate_cents, Equipment.weekly_rate_cents, Equipment.monthly_rate_cents).desc())
    else:
        stmt = stmt.order_by(Equipment.id.desc())
    stmt = stmt.limit(limit)
    rows = s.execute(stmt).scalars().all()
    out: List[EquipmentOut] = []
    for e in rows:
        avail = None
        if start and end:
            avail = _available_quantity(e.id, start, end, s)
        item = EquipmentOut.model_validate(e, from_attributes=True)
        if near_lat is not None and near_lon is not None and e.latitude is not None and e.longitude is not None:
            try:
                item.distance_km = round(_haversine_km(near_lat, near_lon, float(e.latitude), float(e.longitude)), 2)
            except Exception:
                item.distance_km = None
        item.available_quantity = avail
        if available_only and avail is not None and avail <= 0:
            continue
        if max_distance_km is not None and item.distance_km is not None and item.distance_km > max_distance_km:
            continue
        out.append(item)
    if order == "distance" and near_lat is not None and near_lon is not None:
        out.sort(key=lambda x: (x.distance_km if x.distance_km is not None else 1e9))
    return out


@router.get("/assets/{equipment_id}", response_model=EquipmentOut)
def get_asset(equipment_id: int, s: Session = Depends(get_session)):
    e = s.get(Equipment, equipment_id)
    if not e:
        raise HTTPException(status_code=404, detail="not found")
    return EquipmentOut.model_validate(e, from_attributes=True)


@router.patch("/assets/{equipment_id}", response_model=EquipmentOut)
def update_asset(equipment_id: int, req: EquipmentUpdate, s: Session = Depends(get_session)):
    e = s.get(Equipment, equipment_id)
    if not e:
        raise HTTPException(status_code=404, detail="not found")
    data = req.model_dump(exclude_unset=True)
    for k, v in data.items():
        setattr(e, k, v)
    s.add(e)
    s.commit()
    s.refresh(e)
    return EquipmentOut.model_validate(e, from_attributes=True)


@router.delete("/assets/{equipment_id}")
def delete_asset(equipment_id: int, s: Session = Depends(get_session)):
    e = s.get(Equipment, equipment_id)
    if not e:
        raise HTTPException(status_code=404, detail="not found")
    s.delete(e)
    s.commit()
    return {"ok": True}


@router.post("/quote", response_model=QuoteOut)
def quote(req: QuoteReq, s: Session = Depends(get_session)):
    eq = s.get(Equipment, req.equipment_id)
    if not eq:
        raise HTTPException(status_code=404, detail="equipment not found")
    try:
        start = _parse_dt(req.from_iso)
        end = _parse_dt(req.to_iso)
        if end <= start:
            raise ValueError("range")
    except Exception:
        raise HTTPException(status_code=400, detail="invalid time range")
    rental, delivery, deposit, currency, total, hours, days, route_points = _quote_amount(
        eq,
        start,
        end,
        req.quantity,
        req.delivery_required,
        req.delivery_km,
        req.delivery_lat,
        req.delivery_lon,
        eq.latitude,
        eq.longitude,
        req.include_deposit,
        ignore_min_days=req.ignore_min_days,
    )
    payload = QuoteOut(
        hours=round(hours, 2),
        days=float(days),
        rental_cents=int(rental),
        delivery_cents=int(delivery),
        deposit_cents=int(deposit),
        total_cents=int(total),
        currency=currency,
    )
    if eq.min_rental_days:
        payload.min_days_applied = int(eq.min_rental_days)
    payload.weekend_days = None
    try:
        d = start
        wd = 0
        while d < end:
            if d.weekday() >= 4:
                wd += 1
            d += timedelta(days=1)
        payload.weekend_days = wd
    except Exception:
        pass
    if eq.longterm_discount_pct:
        payload.longterm_discount_pct = eq.longterm_discount_pct
    if req.delivery_required and req.delivery_lat is not None and req.delivery_lon is not None and eq.latitude is not None and eq.longitude is not None:
        try:
            dist, _pts = _route_info(eq.latitude, eq.longitude, req.delivery_lat, req.delivery_lon)
            payload.delivery_distance_km = dist
            if route_points:
                payload.delivery_route = route_points
            elif _pts:
                payload.delivery_route = _pts
        except Exception:
            payload.delivery_distance_km = None
    return payload


@router.post("/book", response_model=BookingOut)
def book(
    req: BookReq,
    idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"),
    s: Session = Depends(get_session),
):
    eq = s.get(Equipment, req.equipment_id)
    if not eq:
        raise HTTPException(status_code=404, detail="equipment not found")
    try:
        start = _parse_dt(req.from_iso)
        end = _parse_dt(req.to_iso)
        if end <= start:
            raise ValueError("range")
    except Exception:
        raise HTTPException(status_code=400, detail="invalid time range")
    if idempotency_key:
        ie = s.get(Idempotency, idempotency_key)
        if ie and ie.ref_id:
            b0 = s.get(Booking, ie.ref_id)
            if b0:
                return _booking_to_out(b0, s)

    avail = _available_quantity(eq.id, start, end, s)
    if avail <= 0 or avail < req.quantity:
        raise HTTPException(status_code=409, detail="not available")

    rental, delivery, deposit, currency, total, _, _, route_points = _quote_amount(
        eq, start, end, req.quantity, req.delivery_required, req.delivery_km, req.delivery_lat, req.delivery_lon, eq.latitude, eq.longitude, req.include_deposit, req.ignore_min_days
    )

    status = "requested"
    payments_txn = None
    if req.confirm and eq.owner_wallet_id and req.renter_wallet_id and total > 0:
        resp = _pay_transfer(
            req.renter_wallet_id,
            eq.owner_wallet_id,
            int(total),
            ikey=f"eq-book-{eq.id}",
            ref=f"equipment-{eq.id}",
        )
        payments_txn = str(resp.get("id") or resp.get("txn_id") or "")
        status = "confirmed"

    booking_id = str(uuid.uuid4())
    inv_id = f"inv-{booking_id[:8]}"
    due_at = start - timedelta(hours=1)
    invoice = Invoice(
        id=inv_id,
        booking_id=booking_id,
        amount_cents=int(total),
        currency=currency,
        status="paid" if payments_txn else "open",
        due_at=due_at,
        paid_at=datetime.now(timezone.utc) if payments_txn else None,
    )
    delivery_window_start = None
    delivery_window_end = None
    try:
        if req.delivery_window_start_iso:
            delivery_window_start = _parse_dt(req.delivery_window_start_iso)
        if req.delivery_window_end_iso:
            delivery_window_end = _parse_dt(req.delivery_window_end_iso)
    except Exception:
        delivery_window_start = delivery_window_start
        delivery_window_end = delivery_window_end
    b = Booking(
        id=booking_id,
        equipment_id=eq.id,
        renter_name=req.renter_name,
        renter_phone=req.renter_phone,
        renter_wallet_id=(req.renter_wallet_id or None),
        from_ts=start,
        to_ts=end,
        quantity=req.quantity,
        status=status,
        amount_cents=int(total),
        currency=currency,
        payments_txn_id=payments_txn,
        delivery_required=req.delivery_required,
        delivery_address=req.delivery_address,
        pickup_address=req.pickup_address,
        delivery_lat=req.delivery_lat,
        delivery_lon=req.delivery_lon,
        notes=req.notes,
        invoice_id=inv_id,
        project=req.project,
        po=req.po,
        insurance=req.insurance,
        damage_waiver=req.damage_waiver,
        attachments=",".join(req.attachments) if req.attachments else None,
        delivery_window_start=delivery_window_start,
        delivery_window_end=delivery_window_end,
    )
    s.add(b)
    s.add(invoice)
    # Create logistics tasks when delivery is needed
    if req.delivery_required:
        delivery_ts = None
        pickup_ts = None
        try:
            if req.delivery_scheduled_iso:
                delivery_ts = _parse_dt(req.delivery_scheduled_iso)
            if req.pickup_scheduled_iso:
                pickup_ts = _parse_dt(req.pickup_scheduled_iso)
        except Exception:
            delivery_ts = delivery_ts
        import json
        route_json = None
        try:
            route_json = json.dumps(route_points) if route_points else None
        except Exception:
            route_json = None
        s.add(
            DeliveryTask(
                id=str(uuid.uuid4()),
                booking_id=booking_id,
                kind="delivery",
                status="pending",
                scheduled_at=delivery_ts or start - timedelta(hours=2),
                address=req.delivery_address,
                lat=req.delivery_lat,
                lon=req.delivery_lon,
                route_geojson=route_json,
                distance_km=(float(req.delivery_km) if req.delivery_km else None),
                window_start=delivery_window_start,
                window_end=delivery_window_end,
            )
        )
        s.add(
            DeliveryTask(
                id=str(uuid.uuid4()),
                booking_id=booking_id,
                kind="pickup",
                status="pending",
                scheduled_at=pickup_ts or end,
                address=req.pickup_address or req.delivery_address,
                lat=req.delivery_lat,
                lon=req.delivery_lon,
            )
        )
    s.commit()
    if idempotency_key:
        try:
            s.add(Idempotency(key=idempotency_key, ref_id=b.id))
            s.commit()
        except Exception:
            pass
    return _booking_to_out(b, s)


@router.get("/bookings/{booking_id}", response_model=BookingOut)
def get_booking(booking_id: str, s: Session = Depends(get_session)):
    b = s.get(Booking, booking_id)
    if not b:
        raise HTTPException(status_code=404, detail="not found")
    return _booking_to_out(b, s)


@router.get("/bookings", response_model=List[BookingOut])
def list_bookings(
    status: str = "",
    renter_wallet_id: str = "",
    equipment_id: Optional[int] = None,
    upcoming_only: bool = False,
    limit: int = 100,
    s: Session = Depends(get_session),
):
    limit = max(1, min(limit, 300))
    stmt = select(Booking)
    if status:
        stmt = stmt.where(Booking.status == status)
    if renter_wallet_id:
        stmt = stmt.where(Booking.renter_wallet_id == renter_wallet_id)
    if equipment_id:
        stmt = stmt.where(Booking.equipment_id == equipment_id)
    if upcoming_only:
        stmt = stmt.where(Booking.to_ts >= datetime.now(timezone.utc))
    stmt = stmt.order_by(Booking.created_at.desc()).limit(limit)
    rows = s.execute(stmt).scalars().all()
    return [_booking_to_out(b, s) for b in rows]


@router.post("/bookings/{booking_id}/status", response_model=BookingOut)
def update_booking_status(booking_id: str, req: BookingStatusUpdate, s: Session = Depends(get_session)):
    b = s.get(Booking, booking_id)
    if not b:
        raise HTTPException(status_code=404, detail="not found")
    allowed = {"requested", "confirmed", "active", "completed", "canceled"}
    if req.status not in allowed:
        raise HTTPException(status_code=400, detail="invalid status")
    b.status = req.status
    if req.notes:
        b.notes = req.notes
    s.add(b)
    s.commit()
    return _booking_to_out(b, s)


@router.post("/bookings/{booking_id}/logistics", response_model=BookingOut)
def update_logistics(booking_id: str, updates: List[TaskUpdate], s: Session = Depends(get_session)):
    b = s.get(Booking, booking_id)
    if not b:
        raise HTTPException(status_code=404, detail="not found")
    for upd in updates:
        if upd.kind not in ("delivery", "pickup"):
            continue
        task = s.execute(
            select(DeliveryTask).where(DeliveryTask.booking_id == booking_id, DeliveryTask.kind == upd.kind)
        ).scalar_one_or_none()
        scheduled = None
        if upd.scheduled_iso:
            try:
                scheduled = _parse_dt(upd.scheduled_iso)
            except Exception:
                scheduled = None
        if not task:
            task = DeliveryTask(
                id=str(uuid.uuid4()),
                booking_id=booking_id,
                kind=upd.kind,
                status=upd.status or "pending",
                scheduled_at=scheduled,
                address=upd.address,
                assignee=upd.assignee,
                notes=upd.notes,
                window_start=_parse_dt(upd.window_start_iso) if upd.window_start_iso else None,
                window_end=_parse_dt(upd.window_end_iso) if upd.window_end_iso else None,
                eta_minutes=upd.eta_minutes,
                driver_name=upd.driver_name,
                driver_phone=upd.driver_phone,
                distance_km=upd.distance_km,
            )
            if upd.route:
                try:
                    import json
                    task.route_geojson = json.dumps(upd.route)
                except Exception:
                    pass
            s.add(task)
        else:
            prev_status = task.status
            if upd.status:
                task.status = upd.status
            if scheduled:
                task.scheduled_at = scheduled
            if upd.address is not None:
                task.address = upd.address
            if upd.assignee is not None:
                task.assignee = upd.assignee
            if upd.notes is not None:
                task.notes = upd.notes
            if upd.window_start_iso:
                try:
                    task.window_start = _parse_dt(upd.window_start_iso)
                except Exception:
                    pass
            if upd.window_end_iso:
                try:
                    task.window_end = _parse_dt(upd.window_end_iso)
                except Exception:
                    pass
            if upd.eta_minutes is not None:
                task.eta_minutes = upd.eta_minutes
            if upd.driver_name is not None:
                task.driver_name = upd.driver_name
            if upd.driver_phone is not None:
                task.driver_phone = upd.driver_phone
            if upd.distance_km is not None:
                task.distance_km = upd.distance_km
            if upd.route:
                try:
                    import json
                    task.route_geojson = json.dumps(upd.route)
                except Exception:
                    pass
            if upd.pod_signed is not None:
                note = task.proof_note or ""
                if "POD" not in note:
                    note = (note + " POD signed").strip()
                task.proof_note = note
            if upd.proof_photo_b64 and not task.proof_photo_url:
                try:
                    import base64, os
                    if MEDIA_BASE_URL:
                        fname = upd.proof_filename or f"equipment-proof-{task.id}.png"
                        path = os.path.join(MEDIA_DIR, fname)
                        os.makedirs(MEDIA_DIR, exist_ok=True)
                        with open(path, "wb") as f:
                            f.write(base64.b64decode(upd.proof_photo_b64))
                        task.proof_photo_url = MEDIA_BASE_URL.rstrip("/") + f"/{fname}"
                except Exception:
                    pass
            if upd.proof_note is not None:
                task.proof_note = upd.proof_note
            if upd.signature_name is not None:
                task.signature_name = upd.signature_name
            # SLA timestamps auto-set
            try:
                now = datetime.now(timezone.utc)
                new_status = upd.status or task.status or prev_status
                if new_status in ("en_route",) and prev_status in (None, "pending"):
                    task.scheduled_at = task.scheduled_at or now
                if new_status in ("on_site", "arrived"):
                    task.arrived_at = task.arrived_at or now
                if new_status in ("completed", "delivered"):
                    task.completed_at = task.completed_at or now
            except Exception:
                pass
            s.add(task)
    s.commit()
    return _booking_to_out(b, s)


@router.get("/analytics/summary")
def analytics_summary(s: Session = Depends(get_session)):
    total_assets = s.scalar(select(func.count(Equipment.id))) or 0
    active_assets = s.scalar(select(func.count(Equipment.id)).where(Equipment.status == "available")) or 0
    pending = s.scalar(select(func.count(Booking.id)).where(Booking.status.in_(["requested", "confirmed"]))) or 0
    in_field = s.scalar(select(func.count(Booking.id)).where(Booking.status == "active")) or 0
    week_ago = datetime.now(timezone.utc) - timedelta(days=7)
    bookings_week = s.scalar(
        select(func.count(Booking.id)).where(
            Booking.status.in_(["confirmed", "active", "completed"]),
            Booking.created_at >= week_ago,
        )
    ) or 0
    completed_30d = s.scalar(
        select(func.count(Booking.id)).where(
            Booking.status == "completed",
            Booking.created_at >= datetime.now(timezone.utc) - timedelta(days=30),
        )
    ) or 0
    revenue_30d = s.scalar(
        select(func.coalesce(func.sum(Booking.amount_cents), 0)).where(
            Booking.status.in_(["confirmed", "active", "completed"]),
            Booking.created_at >= datetime.now(timezone.utc) - timedelta(days=30),
        )
    ) or 0
    blocks_week = s.scalar(
        select(func.count(AvailabilityBlock.id)).where(
            AvailabilityBlock.created_at >= week_ago,
        )
    ) or 0
    # Utilisation: hours reserved / total hours in window (availability aware via bookings only)
    window_start = datetime.now(timezone.utc) - timedelta(days=30)
    total_hours = 24 * 30
    util = []
    assets = s.execute(select(Equipment).where(Equipment.status == "available")).scalars().all()
    for e in assets:
        hours_reserved = 0.0
        bookings = s.execute(
            select(Booking).where(
                Booking.equipment_id == e.id,
                Booking.status.in_(["confirmed", "active", "completed"]),
                Booking.to_ts >= window_start,
            )
        ).scalars().all()
        for b in bookings:
            start = max(b.from_ts, window_start) if b.from_ts else window_start
            end = b.to_ts or datetime.now(timezone.utc)
            if end > start:
                hours_reserved += (end - start).total_seconds() / 3600.0
        util.append({"equipment_id": e.id, "hours_reserved": round(hours_reserved, 2), "util_pct": round(min(100.0, (hours_reserved / total_hours) * 100), 2)})
    deliveries_open = s.scalar(
        select(func.count(DeliveryTask.id)).where(DeliveryTask.status.in_(["pending", "en_route"]))
    ) or 0
    return {
        "assets_total": int(total_assets),
        "assets_available": int(active_assets),
        "bookings_pending": int(pending),
        "bookings_active": int(in_field),
        "bookings_completed_30d": int(completed_30d),
        "bookings_week": int(bookings_week),
        "revenue_30d_cents": int(revenue_30d),
        "logistics_open": int(deliveries_open),
        "utilisation": util[:10],
        "blocks_week": int(blocks_week),
    }


@router.get("/dashboard")
def dashboard(renter_wallet_id: str = "", owner_wallet_id: str = "", s: Session = Depends(get_session)):
    data: dict[str, object] = {}
    if renter_wallet_id:
        data["my_bookings"] = list_bookings(
            status="",
            renter_wallet_id=renter_wallet_id,
            equipment_id=None,
            upcoming_only=False,
            limit=20,
            s=s,
        )
    if owner_wallet_id:
        qs = select(Booking).where(Booking.status.in_(["requested", "confirmed"]), Booking.amount_cents != None)  # noqa: E711
        data["owner_pending"] = len(s.execute(qs).scalars().all())
    data["analytics"] = analytics_summary(s=s)
    return data


class AvailabilityReq(BaseModel):
    from_iso: str
    to_iso: str
    reason: Optional[str] = None


class AvailabilityOut(BaseModel):
    id: str
    from_iso: str
    to_iso: str
    reason: Optional[str]


@router.get("/availability/{equipment_id}", response_model=dict)
def availability(equipment_id: int, s: Session = Depends(get_session)):
    eq = s.get(Equipment, equipment_id)
    if not eq:
        raise HTTPException(status_code=404, detail="not found")
    blocks = s.execute(select(AvailabilityBlock).where(AvailabilityBlock.equipment_id == equipment_id)).scalars().all()
    bookings = s.execute(select(Booking).where(Booking.equipment_id == equipment_id, Booking.status.in_(["confirmed", "active", "requested"]))).scalars().all()
    return {
        "blocks": [
            AvailabilityOut(id=b.id, from_iso=b.from_ts.isoformat() if b.from_ts else "", to_iso=b.to_ts.isoformat() if b.to_ts else "", reason=b.reason)
            for b in blocks
        ],
        "bookings": [
            {
                "id": b.id,
                "from_iso": b.from_ts.isoformat() if b.from_ts else "",
                "to_iso": b.to_ts.isoformat() if b.to_ts else "",
                "status": b.status,
            }
            for b in bookings
        ],
    }


@router.post("/availability/{equipment_id}", response_model=AvailabilityOut)
def create_block(equipment_id: int, req: AvailabilityReq, s: Session = Depends(get_session)):
    eq = s.get(Equipment, equipment_id)
    if not eq:
        raise HTTPException(status_code=404, detail="not found")
    try:
        start = _parse_dt(req.from_iso)
        end = _parse_dt(req.to_iso)
        if end <= start:
            raise ValueError("range")
    except Exception:
        raise HTTPException(status_code=400, detail="invalid time range")
    # Prevent overlaps with existing blocks
    existing = s.execute(select(AvailabilityBlock).where(AvailabilityBlock.equipment_id == equipment_id)).scalars().all()
    for b in existing:
        if b.from_ts and b.to_ts and _overlaps(start, end, b.from_ts, b.to_ts):
            raise HTTPException(status_code=409, detail="overlaps existing block")
    blk = AvailabilityBlock(
        id=str(uuid.uuid4()),
        equipment_id=equipment_id,
        from_ts=start,
        to_ts=end,
        reason=req.reason or "maintenance",
    )
    s.add(blk)
    s.commit()
    return AvailabilityOut(id=blk.id, from_iso=start.isoformat(), to_iso=end.isoformat(), reason=blk.reason)


@router.delete("/availability/{block_id}")
def delete_block(block_id: str, s: Session = Depends(get_session)):
    blk = s.get(AvailabilityBlock, block_id)
    if not blk:
        raise HTTPException(status_code=404, detail="not found")
    s.delete(blk)
    s.commit()
    return {"ok": True}


@router.get("/calendar/{equipment_id}")
def calendar(equipment_id: int, month: str, s: Session = Depends(get_session)):
    """
    Return day-level availability for a given month (YYYY-MM).
    """
    eq = s.get(Equipment, equipment_id)
    if not eq:
        raise HTTPException(status_code=404, detail="not found")
    try:
        year, mon = month.split("-")
        y = int(year)
        m = int(mon)
        start = datetime(y, m, 1, tzinfo=timezone.utc)
        if m == 12:
            end = datetime(y + 1, 1, 1, tzinfo=timezone.utc)
        else:
            end = datetime(y, m + 1, 1, tzinfo=timezone.utc)
    except Exception:
        raise HTTPException(status_code=400, detail="invalid month")
    blocks = s.execute(select(AvailabilityBlock).where(AvailabilityBlock.equipment_id == equipment_id)).scalars().all()
    bookings = s.execute(select(Booking).where(Booking.equipment_id == equipment_id)).scalars().all()
    days: list[dict[str, object]] = []
    cur = start
    while cur < end:
        nxt = cur + timedelta(days=1)
        blocked = False
        reason = ""
        for b in blocks:
            if b.from_ts and b.to_ts and _overlaps(cur, nxt, b.from_ts, b.to_ts):
                blocked = True
                reason = b.reason or ""
                break
        booked = False
        for bk in bookings:
            if bk.from_ts and bk.to_ts and _overlaps(cur, nxt, bk.from_ts, bk.to_ts) and bk.status in ("requested", "confirmed", "active"):
                booked = True
                break
        days.append(
            {
                "date": cur.date().isoformat(),
                "available": (not blocked) and (not booked),
                "blocked": blocked,
                "blocked_reason": reason,
                "booked": booked,
            }
        )
        cur = nxt
    return {"equipment_id": equipment_id, "month": month, "days": days, "blocks": [
        {"id": b.id, "from_iso": b.from_ts.isoformat() if b.from_ts else "", "to_iso": b.to_ts.isoformat() if b.to_ts else "", "reason": b.reason}
        for b in blocks
    ]}


@router.post("/seed/demo")
def seed_demo(s: Session = Depends(get_session)):
    """
    Create demo equipment, bookings, holds, and tasks to showcase the ops board/calendar.
    Safe to call multiple times; will not duplicate titles.
    """
    now = datetime.now(timezone.utc)
    demo_assets = [
        {
            "title": "Bagger 5t",
            "city": "Berlin",
            "latitude": 52.52,
            "longitude": 13.405,
            "daily": 12000,
            "weekly": 70000,
            "monthly": 210000,
            "category": "Erdbau",
        },
        {
            "title": "Teleskopstapler",
            "city": "Munich",
            "latitude": 48.1351,
            "longitude": 11.582,
            "daily": 15000,
            "weekly": 85000,
            "monthly": 250000,
            "category": "Logistik",
        },
    ]
    created_ids: list[int] = []
    for d in demo_assets:
        existing = s.execute(select(Equipment).where(Equipment.title == d["title"])).scalar_one_or_none()
        if existing:
            created_ids.append(existing.id)
            continue
        e = Equipment(
            title=d["title"],
            city=d["city"],
            latitude=d["latitude"],
            longitude=d["longitude"],
            daily_rate_cents=d["daily"],
            weekly_rate_cents=d["weekly"],
            monthly_rate_cents=d["monthly"],
            category=d["category"],
            subcategory="Demo",
            quantity=3,
            currency="EUR",
            status="available",
        )
        s.add(e)
        s.commit()
        s.refresh(e)
        created_ids.append(e.id)
    # Seed bookings for first asset
    if created_ids:
        eq_id = created_ids[0]
        existing_booking = s.execute(select(Booking).where(Booking.equipment_id == eq_id)).scalar_one_or_none()
        if not existing_booking:
            b_id = str(uuid.uuid4())
            start = now + timedelta(days=1)
            end = start + timedelta(days=3)
            inv = Invoice(
                id=f"inv-{b_id[:8]}",
                booking_id=b_id,
                amount_cents=240000,
                currency="EUR",
                status="confirmed",
                due_at=start,
            )
            s.add(inv)
            s.add(
                Booking(
                    id=b_id,
                    equipment_id=eq_id,
                    renter_name="Demo Bau GmbH",
                    renter_phone="+49 30 123456",
                    from_ts=start,
                    to_ts=end,
                    quantity=1,
                    status="active",
                    amount_cents=240000,
                    currency="EUR",
                    delivery_required=True,
                    delivery_address="Alexanderplatz, Berlin",
                    delivery_lat=52.5219,
                    delivery_lon=13.4132,
                    invoice_id=inv.id,
                    project="Alexanderplatz",
                    po="PO-12345",
                    insurance=True,
                    damage_waiver=True,
                    attachments="Hydraulikhammer,Schaufel",
                    delivery_window_start=start - timedelta(hours=1),
                    delivery_window_end=start + timedelta(hours=1),
                )
            )
            s.add(
                DeliveryTask(
                    id=str(uuid.uuid4()),
                    booking_id=b_id,
                    kind="delivery",
                    status="en_route",
                    scheduled_at=start - timedelta(hours=2),
                    address="Alexanderplatz, Berlin",
                    lat=52.5219,
                    lon=13.4132,
                    eta_minutes=45,
                    driver_name="Driver One",
                    driver_phone="+49 160 000000",
                )
            )
            s.add(
                DeliveryTask(
                    id=str(uuid.uuid4()),
                    booking_id=b_id,
                    kind="pickup",
                    status="pending",
                    scheduled_at=end,
                    address="Alexanderplatz, Berlin",
                    lat=52.5219,
                    lon=13.4132,
                )
            )
    # Seed a hold on second asset
    if len(created_ids) > 1:
        eq_hold = created_ids[1]
        existing_hold = s.execute(select(AvailabilityBlock).where(AvailabilityBlock.equipment_id == eq_hold)).scalar_one_or_none()
        if not existing_hold:
            s.add(
                AvailabilityBlock(
                    id=str(uuid.uuid4()),
                    equipment_id=eq_hold,
                    from_ts=now + timedelta(days=2),
                    to_ts=now + timedelta(days=4),
                    reason="maintenance",
                )
            )
    s.commit()
    return {"ok": True, "assets": created_ids}


@router.get("/ops/calendar")
def ops_calendar(month: str = "", equipment_id: Optional[int] = None, s: Session = Depends(get_session)):
    """
    Combined calendar for ops: bookings + holds (availability blocks) across the fleet for a given month.
    """
    # default to current month
    dt_now = datetime.now(timezone.utc)
    if not month:
        month = f"{dt_now.year:04d}-{dt_now.month:02d}"
    try:
        year, mon = month.split("-")
        y = int(year)
        m = int(mon)
        start = datetime(y, m, 1, tzinfo=timezone.utc)
        end = datetime(y + 1, 1, 1, tzinfo=timezone.utc) if m == 12 else datetime(y, m + 1, 1, tzinfo=timezone.utc)
    except Exception:
        raise HTTPException(status_code=400, detail="invalid month")
    # prepare equipment lookup
    eq_stmt = select(Equipment)
    if equipment_id:
        eq_stmt = eq_stmt.where(Equipment.id == equipment_id)
    equipment_rows = s.execute(eq_stmt).scalars().all()
    eq_map = {e.id: e for e in equipment_rows}
    events: list[dict[str, object]] = []
    # bookings that overlap the month
    bk_stmt = select(Booking).where(
        Booking.from_ts != None,  # noqa: E711
        Booking.to_ts != None,  # noqa: E711
        Booking.from_ts < end,
        Booking.to_ts > start,
    )
    if equipment_id:
        bk_stmt = bk_stmt.where(Booking.equipment_id == equipment_id)
    bookings = s.execute(bk_stmt).scalars().all()
    task_map: dict[str, list[DeliveryTask]] = {}
    if bookings:
        booking_ids = [b.id for b in bookings]
        task_rows = s.execute(select(DeliveryTask).where(DeliveryTask.booking_id.in_(booking_ids))).scalars().all()
        for t in task_rows:
            task_map.setdefault(t.booking_id, []).append(t)
    for b in bookings:
        eq = eq_map.get(b.equipment_id)
        tasks = task_map.get(b.id, [])
        delivery_task = next((t for t in tasks if t.kind == "delivery"), tasks[0] if tasks else None)
        events.append(
            {
                "type": "booking",
                "id": b.id,
                "equipment_id": b.equipment_id,
                "title": eq.title if eq else "",
                "city": eq.city if eq else "",
                "from_iso": b.from_ts.isoformat() if b.from_ts else "",
                "to_iso": b.to_ts.isoformat() if b.to_ts else "",
                "status": b.status,
                "project": b.project,
                "po": b.po,
                "address": b.delivery_address,
                "lat": b.delivery_lat,
                "lon": b.delivery_lon,
                "delivery_window_start_iso": b.delivery_window_start.isoformat() if b.delivery_window_start else None,
                "delivery_window_end_iso": b.delivery_window_end.isoformat() if b.delivery_window_end else None,
                "attachments": [a for a in (b.attachments or "").split(",") if a],
                "task_status": delivery_task.status if delivery_task else None,
                "driver": delivery_task.driver_name if delivery_task else None,
                "proof_photo_url": delivery_task.proof_photo_url if delivery_task else None,
                "signature_name": delivery_task.signature_name if delivery_task else None,
            }
        )
    # holds / maintenance
    blk_stmt = select(AvailabilityBlock)
    if equipment_id:
        blk_stmt = blk_stmt.where(AvailabilityBlock.equipment_id == equipment_id)
    blocks = s.execute(blk_stmt).scalars().all()
    for blk in blocks:
        if blk.from_ts and blk.to_ts and _overlaps(start, end, blk.from_ts, blk.to_ts):
            events.append(
                {
                    "type": "hold",
                    "id": blk.id,
                    "equipment_id": blk.equipment_id,
                    "title": eq_map.get(blk.equipment_id).title if eq_map.get(blk.equipment_id) else "",
                    "from_iso": blk.from_ts.isoformat(),
                    "to_iso": blk.to_ts.isoformat(),
                    "reason": blk.reason,
                }
            )
    # sort events for readability
    events.sort(key=lambda e: (e.get("from_iso") or ""))
    return {"month": month, "events": events}


@router.get("/invoices/{inv_id}/pdf")
def invoice_pdf(inv_id: str, s: Session = Depends(get_session)):
    inv = s.get(Invoice, inv_id)
    if not inv:
        raise HTTPException(status_code=404, detail="not found")
    try:
        import io
        buf = io.BytesIO()
        content = f"%PDF-1.4\n% Simple invoice\nID: {inv.id}\nAmount: {inv.amount_cents} {inv.currency}\nStatus: {inv.status}\n"
        buf.write(content.encode("utf-8"))
        buf.seek(0)
        headers = {"Content-Disposition": f'inline; filename="invoice_{inv.id}.pdf"'}
        return StreamingResponse(buf, media_type="application/pdf", headers=headers)
    except Exception:
        raise HTTPException(status_code=500, detail="failed to render pdf")


@router.get("/media/{fname}")
def media_file(fname: str):
    # serve proof photos saved in MEDIA_DIR
    import os
    from fastapi.responses import FileResponse
    if ".." in fname or "/" in fname or "\\" in fname:
        raise HTTPException(status_code=400, detail="invalid filename")
    path = os.path.join(MEDIA_DIR, fname)
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="not found")
    return FileResponse(path)


app.include_router(router)
