from fastapi import FastAPI, HTTPException, Depends, Header, Request, Response, APIRouter
from pydantic import BaseModel, Field, ConfigDict
from typing import Optional, List
import os
from shamell_shared import RequestIDMiddleware, configure_cors, add_standard_health, setup_json_logging
import json
import csv
from io import StringIO
from sqlalchemy import create_engine, String, Float, Integer, DateTime, BigInteger, func, Boolean
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, Session
from sqlalchemy import select
import httpx
import uuid
from datetime import datetime, timedelta
import math

from .fcm import send_fcm_v1


def _env_or(key: str, default: str) -> str:
    v = os.getenv(key)
    return v if v is not None else default


app = FastAPI(title="Taxi API", version="0.1.0")
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", "*"))
add_standard_health(app)

router = APIRouter()

# Internal write-guard: require X-Internal-Secret when configured.
INTERNAL_API_SECRET = os.getenv("INTERNAL_API_SECRET", "")

def _require_internal(request: Request | None):
    if not INTERNAL_API_SECRET:
        return
    try:
        hdr = request.headers.get("X-Internal-Secret") if request and hasattr(request, 'headers') else None
    except Exception:
        hdr = None
    if hdr != INTERNAL_API_SECRET:
        raise HTTPException(status_code=403, detail="forbidden")


# Default to local SQLite; in production (e.g. Cloud SQL Postgres) set
# DB_URL accordingly, for example:
# postgresql+psycopg2://USER:PASS@/taxi?host=/cloudsql/PROJECT:REGION:INSTANCE
DB_URL = _env_or("TAXI_DB_URL", _env_or("DB_URL", "sqlite+pysqlite:////tmp/taxi.db"))
DB_SCHEMA = os.getenv("DB_SCHEMA") if not DB_URL.startswith("sqlite") else None
PAYMENTS_BASE = _env_or("PAYMENTS_BASE_URL", "")
OSRM_BASE = _env_or("OSRM_BASE_URL", "")
TOMTOM_BASE = _env_or("TOMTOM_BASE_URL", "https://api.tomtom.com")
TOMTOM_API_KEY = os.getenv("TOMTOM_API_KEY", "")
CASH_ONLY = int(_env_or("TAXI_CASH_ONLY", "0"))
FARE_BASE_CENTS = int(_env_or("TAXI_FARE_BASE_CENTS", "5000"))
FARE_PER_KM_CENTS = float(_env_or("TAXI_FARE_PER_KM_CENTS", "800"))
MIN_FARE_CENTS = int(_env_or("TAXI_MIN_FARE_CENTS", "5000"))
# Brokerage / platform fee as fraction of fare (e.g. 0.10 = 10%)
BROKERAGE_RATE = float(_env_or("TAXI_BROKERAGE_RATE", "0.10"))


class Base(DeclarativeBase):
    pass


class TaxiConfig(Base):
    __tablename__ = "taxi_config"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    value: Mapped[Optional[str]] = mapped_column(String(256), nullable=True)


class Driver(Base):
    __tablename__ = "drivers"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    name: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    phone: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    vehicle_make: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    vehicle_plate: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    status: Mapped[str] = mapped_column(String(16), default="offline")  # offline|online
    lat: Mapped[Optional[float]] = mapped_column(Float, default=None)
    lon: Mapped[Optional[float]] = mapped_column(Float, default=None)
    # New fields
    vehicle_class: Mapped[Optional[str]] = mapped_column(String(16), default=None)
    vehicle_color: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    is_blocked: Mapped[bool] = mapped_column(Boolean, default=False)
    balance_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    fcm_token: Mapped[Optional[str]] = mapped_column(String(256), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class Ride(Base):
    __tablename__ = "rides"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    rider_phone: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    rider_wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    rider_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    pickup_lat: Mapped[float] = mapped_column(Float)
    pickup_lon: Mapped[float] = mapped_column(Float)
    dropoff_lat: Mapped[float] = mapped_column(Float)
    dropoff_lon: Mapped[float] = mapped_column(Float)
    driver_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    status: Mapped[str] = mapped_column(String(16), default="requested")  # requested|assigned|accepted|on_trip|completed|canceled
    requested_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    assigned_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), nullable=True)
    accepted_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), nullable=True)
    started_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), nullable=True)
    completed_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), nullable=True)
    canceled_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), nullable=True)
    fare_cents: Mapped[Optional[int]] = mapped_column(BigInteger, nullable=True)
    payments_txn_id: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    payments_status: Mapped[Optional[str]] = mapped_column(String(16), nullable=True)
    driver_fee_hold_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    requested_vehicle_class: Mapped[Optional[str]] = mapped_column(String(16), nullable=True)
    rider_rating: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    rider_rating_comment: Mapped[Optional[str]] = mapped_column(String(512), nullable=True)


class Idempotency(Base):
    __tablename__ = "idempotency"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    key: Mapped[str] = mapped_column(String(120), primary_key=True)
    ride_id: Mapped[Optional[str]] = mapped_column(String(36), nullable=True)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class TaxiTopupQrLog(Base):
    __tablename__ = "taxi_topup_qr_logs"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    driver_id: Mapped[str] = mapped_column(String(36))
    driver_phone: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    amount_cents: Mapped[int] = mapped_column(BigInteger)
    created_by: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    redeemed: Mapped[bool] = mapped_column(Boolean, default=False)
    redeemed_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), nullable=True)
    redeemed_by: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    payload: Mapped[str] = mapped_column(String(512))


engine = create_engine(DB_URL, future=True)


def get_session() -> Session:
    with Session(engine) as s:
        yield s


def _startup():
    Base.metadata.create_all(engine)
    # lightweight migration for sqlite: add new columns if missing
    try:
        if DB_URL.startswith("sqlite"):
            with engine.begin() as conn:
                cols = set([row[1] for row in conn.exec_driver_sql("PRAGMA table_info(drivers)")])
                def add(col, ddl):
                    if col not in cols:
                        try:
                            conn.exec_driver_sql(f"ALTER TABLE drivers ADD COLUMN {col} {ddl}")
                        except Exception:
                            pass
                add('vehicle_class', 'VARCHAR(16)')
                add('vehicle_color', 'VARCHAR(32)')
                add('is_blocked', 'BOOLEAN DEFAULT 0')
                add('balance_cents', 'BIGINT DEFAULT 0')
                add('fcm_token', 'VARCHAR(256)')
                # rides table columns
                cols_r = set([row[1] for row in conn.exec_driver_sql("PRAGMA table_info(rides)")])
                if 'driver_fee_hold_cents' not in cols_r:
                    try:
                        conn.exec_driver_sql("ALTER TABLE rides ADD COLUMN driver_fee_hold_cents BIGINT DEFAULT 0")
                    except Exception:
                        pass
                if 'requested_vehicle_class' not in cols_r:
                    try:
                        conn.exec_driver_sql("ALTER TABLE rides ADD COLUMN requested_vehicle_class VARCHAR(16)")
                    except Exception:
                        pass
                if 'rider_id' not in cols_r:
                    try:
                        conn.exec_driver_sql("ALTER TABLE rides ADD COLUMN rider_id VARCHAR(36)")
                    except Exception:
                        pass
                if 'rider_rating' not in cols_r:
                    try:
                        conn.exec_driver_sql("ALTER TABLE rides ADD COLUMN rider_rating INTEGER")
                    except Exception:
                        pass
                if 'rider_rating_comment' not in cols_r:
                    try:
                        conn.exec_driver_sql("ALTER TABLE rides ADD COLUMN rider_rating_comment VARCHAR(512)")
                    except Exception:
                        pass
    except Exception:
        pass


app.router.on_startup.append(_startup)

def _get_brokerage_rate(s: Session | None = None) -> float:
    try:
        if s is not None:
            cfg = s.get(TaxiConfig, "brokerage_rate")
            if cfg and (cfg.value or "").strip():
                return float(cfg.value)
        else:
            with Session(engine) as sx:
                cfg = sx.get(TaxiConfig, "brokerage_rate")
                if cfg and (cfg.value or "").strip():
                    return float(cfg.value)
    except Exception:
        pass
    return BROKERAGE_RATE


# ---- Schemas ----
class DriverRegisterReq(BaseModel):
    name: Optional[str] = None
    phone: Optional[str] = None
    vehicle_make: Optional[str] = None
    vehicle_plate: Optional[str] = None
    vehicle_class: Optional[str] = None
    vehicle_color: Optional[str] = None


class DriverOut(BaseModel):
    id: str
    name: Optional[str]
    phone: Optional[str]
    vehicle_make: Optional[str]
    vehicle_plate: Optional[str]
    status: str
    lat: Optional[float]
    lon: Optional[float]
    wallet_id: Optional[str]
    vehicle_class: Optional[str]
    vehicle_color: Optional[str]
    is_blocked: bool
    balance_cents: int
    fcm_token: Optional[str]
    model_config = ConfigDict(from_attributes=True)


class LocationReq(BaseModel):
    lat: float
    lon: float


class RideRequest(BaseModel):
    rider_phone: Optional[str] = None
    rider_wallet_id: Optional[str] = None
    rider_id: Optional[str] = None
    pickup_lat: float
    pickup_lon: float
    dropoff_lat: float
    dropoff_lon: float
    vehicle_class: Optional[str] = None


class RideOut(BaseModel):
    id: str
    rider_phone: Optional[str]
    rider_id: Optional[str]
    rider_wallet_id: Optional[str]
    pickup_lat: float
    pickup_lon: float
    dropoff_lat: float
    dropoff_lon: float
    driver_id: Optional[str]
    status: str
    requested_at: Optional[datetime]
    assigned_at: Optional[datetime]
    accepted_at: Optional[datetime]
    started_at: Optional[datetime]
    completed_at: Optional[datetime]
    canceled_at: Optional[datetime]
    fare_cents: Optional[int]
    payments_txn_id: Optional[str]
    payments_status: Optional[str]
    driver_fee_hold_cents: int
    requested_vehicle_class: Optional[str]
    broker_fee_cents: Optional[int] = None
    driver_payout_cents: Optional[int] = None
    rider_rating: Optional[int] = None
    rider_rating_comment: Optional[str] = None
    model_config = ConfigDict(from_attributes=True)


class RideRatingReq(BaseModel):
    rating: int = Field(ge=1, le=5)
    comment: Optional[str] = Field(default=None, max_length=512)


class TaxiTopupQrLogOut(BaseModel):
    id: str
    driver_id: str
    driver_phone: Optional[str]
    amount_cents: int
    created_by: Optional[str]
    created_at: Optional[datetime]
    redeemed: bool
    redeemed_at: Optional[datetime]
    redeemed_by: Optional[str]
    payload: str
    driver_balance_cents: Optional[int] = None
    model_config = ConfigDict(from_attributes=True)


# ---- Helpers ----
def _distance2(a_lat: float, a_lon: float, b_lat: float, b_lon: float) -> float:
    # crude squared distance for nearest-neighbour selection
    return (a_lat - b_lat) ** 2 + (a_lon - b_lon) ** 2


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    # Returns great-circle distance in kilometers
    r = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat/2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return r * c


def _route_distance_eta_km(lat1: float, lon1: float, lat2: float, lon2: float) -> tuple[float, int]:
    """
    Best-effort route distance and ETA.

    Preference order:
      1) TomTom Routing API (traffic-aware, if TOMTOM_API_KEY set)
      2) OSRM (if configured)
      3) Haversine fallback

    Returns (km, eta_minutes).
    """
    try:
        if TOMTOM_API_KEY and TOMTOM_BASE:
            # Prefer TomTom Routing API when a key is available so that
            # ETAs match the BFF /osm/route behaviour (traffic-aware).
            base = TOMTOM_BASE.rstrip('/')
            url = base + f"/routing/1/calculateRoute/{lat1},{lon1}:{lat2},{lon2}/json"
            params = {
                "key": TOMTOM_API_KEY,
                "traffic": "true",
                "travelMode": "car",
                "computeBestOrder": "false",
            }
            r = httpx.get(url, params=params, timeout=5)
            r.raise_for_status()
            j = r.json()
            routes = j.get("routes") or []
            if routes:
                summary = routes[0].get("summary") or {}
                dist_m = summary.get("lengthInMeters") or 0
                dur_s = summary.get("travelTimeInSeconds") or summary.get("trafficTravelTimeInSeconds") or 0
                km = max(0.0, float(dist_m) / 1000.0)
                eta_min = max(1, int(round(float(dur_s) / 60.0)))
                return km, eta_min
        if OSRM_BASE:
            url = OSRM_BASE.rstrip('/') + f"/route/v1/driving/{lon1},{lat1};{lon2},{lat2}?overview=false"
            r = httpx.get(url, timeout=5)
            r.raise_for_status()
            j = r.json()
            routes = j.get('routes') or []
            if routes:
                dist_m = routes[0].get('distance') or 0
                dur_s = routes[0].get('duration') or 0
                km = max(0.0, float(dist_m) / 1000.0)
                eta_min = max(1, int(round(float(dur_s) / 60.0)))
                return km, eta_min
    except Exception:
        pass
    km = _haversine_km(lat1, lon1, lat2, lon2)
    eta_min = _eta_min_from_km(km)
    return km, eta_min


# ---- Tariff / Pricing helpers ----
def _tariffs() -> dict:
    try:
        raw = os.getenv("TAXI_TARIFFS")
        if raw:
            return json.loads(raw)
    except Exception:
        pass
    return {
        "classic": {"base": 6000, "per_km": 900,  "per_min": 150, "min": 6000, "mult": 1.0},
        "comfort": {"base": 7000, "per_km": 1100, "per_min": 170, "min": 7000, "mult": 1.2},
        "yellow":  {"base": 6000, "per_km": 900,  "per_min": 150, "min": 6000, "mult": 1.0},
        "vip":     {"base": 8000, "per_km": 1400, "per_min": 220, "min": 8000, "mult": 1.5},
        "van":     {"base": 8000, "per_km": 1300, "per_min": 200, "min": 8000, "mult": 1.4},
    }


def _get_tariff(vclass: Optional[str]) -> dict:
    t = _tariffs()
    if vclass and vclass.lower() in t:
        return t[vclass.lower()]
    return t["classic"]


def _surge_multiplier(now_hour: Optional[int] = None, weekday: Optional[int] = None) -> float:
    try:
        h = now_hour if now_hour is not None else datetime.now().hour
        wd = weekday if weekday is not None else datetime.now().weekday()  # 0=Mon..6=Sun
        night_from = int(_env_or("TAXI_NIGHT_FROM_HOUR", "22"))
        night_to = int(_env_or("TAXI_NIGHT_TO_HOUR", "6"))
        night_factor = float(_env_or("TAXI_NIGHT_FACTOR", "1.2"))
        weekend_factor = float(_env_or("TAXI_WEEKEND_FACTOR", "1.1"))
        mult = 1.0
        if (h >= night_from) or (h < night_to):
            mult *= night_factor
        # Weekend in Syria: Friday(4) and Saturday(5)
        if wd in (4, 5):
            mult *= weekend_factor
        return mult
    except Exception:
        return 1.0


def _eta_min_from_km(km: float) -> int:
    avg_speed = float(_env_or("TAXI_AVG_SPEED_KMH", "30"))
    return max(1, int(round((km / max(0.1, avg_speed)) * 60)))


def _estimate_fare_cents(km: float, minutes: int, vclass: Optional[str]) -> int:
    tf = _get_tariff(vclass)
    # Tariffs are defined in SYP (major units); convert to "cents"
    # (SYP * 100) for all downstream consumers.
    base_syp = float(tf.get("base", 0))
    per_km_syp = float(tf.get("per_km", 0))
    per_min_syp = float(tf.get("per_min", 0))
    min_fare_syp = float(tf.get("min", 0))
    mult = float(tf.get("mult", 1.0))
    surge = _surge_multiplier()
    # Compute fare in SYP and then scale to cents.
    fare_syp = base_syp + (per_km_syp * km) + (per_min_syp * minutes)
    fare_syp = fare_syp * mult * surge
    if fare_syp < min_fare_syp:
        fare_syp = min_fare_syp
    return int(round(fare_syp * 100))


def _surge_flags(now_hour: Optional[int] = None, weekday: Optional[int] = None) -> tuple[float, bool, bool]:
    try:
        h = now_hour if now_hour is not None else datetime.now().hour
        wd = weekday if weekday is not None else datetime.now().weekday()
        night_from = int(_env_or("TAXI_NIGHT_FROM_HOUR", "22"))
        night_to = int(_env_or("TAXI_NIGHT_TO_HOUR", "6"))
        night_factor = float(_env_or("TAXI_NIGHT_FACTOR", "1.2"))
        weekend_factor = float(_env_or("TAXI_WEEKEND_FACTOR", "1.1"))
        mult = 1.0
        night = (h >= night_from) or (h < night_to)
        weekend = (wd in (4, 5))
        if night:
            mult *= night_factor
        if weekend:
            mult *= weekend_factor
        return mult, night, weekend
    except Exception:
        return 1.0, False, False


# ---- Driver endpoints ----
@router.post("/drivers", response_model=DriverOut)
def register_driver(req: DriverRegisterReq, s: Session = Depends(get_session)):
    d = Driver(
        id=str(uuid.uuid4()),
        name=req.name,
        phone=req.phone,
        vehicle_make=req.vehicle_make,
        vehicle_plate=req.vehicle_plate,
        vehicle_class=req.vehicle_class,
        vehicle_color=req.vehicle_color,
        status="offline",
    )
    s.add(d)
    s.commit()
    s.refresh(d)
    # Auto-create a payments wallet for the driver based on phone number.
    # This is used both for non-cash payouts and for commission settlement /
    # topups when the app runs in cash-only mode.
    if PAYMENTS_BASE and (req.phone or "").strip():
        try:
            wallet_id = _payments_create_user((req.phone or "").strip())
            if wallet_id:
                d.wallet_id = wallet_id
                s.add(d)
                s.commit()
                s.refresh(d)
        except Exception:
            # Non-fatal: continue without wallet
            pass
    return d


@router.post("/drivers/{driver_id}/online")
def driver_online(driver_id: str, request: Request, s: Session = Depends(get_session)):
    _require_internal(request)
    d = s.get(Driver, driver_id)
    if not d:
        raise HTTPException(status_code=404, detail="driver not found")
    if d.is_blocked:
        raise HTTPException(status_code=403, detail="driver blocked")
    d.status = "online"
    s.add(d); s.commit()
    return {"ok": True}


@router.post("/drivers/{driver_id}/offline")
def driver_offline(driver_id: str, request: Request, s: Session = Depends(get_session)):
    _require_internal(request)
    d = s.get(Driver, driver_id)
    if not d:
        raise HTTPException(status_code=404, detail="driver not found")
    d.status = "offline"
    s.add(d); s.commit()
    return {"ok": True}


@router.post("/drivers/{driver_id}/location")
def driver_location(driver_id: str, req: LocationReq, request: Request, s: Session = Depends(get_session)):
    _require_internal(request)
    d = s.get(Driver, driver_id)
    if not d:
        raise HTTPException(status_code=404, detail="driver not found")
    d.lat = req.lat; d.lon = req.lon
    s.add(d); s.commit()
    return {"ok": True}


class SetWalletReq(BaseModel):
    wallet_id: str = Field(min_length=3)


@router.post("/drivers/{driver_id}/wallet")
def driver_set_wallet(driver_id: str, req: SetWalletReq, request: Request, s: Session = Depends(get_session)):
    _require_internal(request)
    d = s.get(Driver, driver_id)
    if not d:
        raise HTTPException(status_code=404, detail="driver not found")
    d.wallet_id = req.wallet_id.strip()
    s.add(d); s.commit(); s.refresh(d)
    return {"ok": True, "wallet_id": d.wallet_id}


@router.post("/drivers/{driver_id}/push_token")
async def driver_push_token(driver_id: str, request: Request, s: Session = Depends(get_session)):
    _require_internal(request)
    try:
        body = await request.json()
    except Exception:
        body = None
    if not isinstance(body, dict):
        body = {}
    token = (body.get("fcm_token") or "").strip()
    d = s.get(Driver, driver_id)
    if not d:
        raise HTTPException(status_code=404, detail="driver not found")
    d.fcm_token = token or None
    s.add(d); s.commit(); s.refresh(d)
    return {"ok": True, "driver_id": d.id, "has_token": bool(d.fcm_token)}


class DriverUpdateReq(BaseModel):
    name: Optional[str] = None
    vehicle_make: Optional[str] = None
    vehicle_plate: Optional[str] = None
    vehicle_class: Optional[str] = None
    vehicle_color: Optional[str] = None
    phone: Optional[str] = None


@router.post("/drivers/{driver_id}/update", response_model=DriverOut)
def driver_update(driver_id: str, req: DriverUpdateReq, s: Session = Depends(get_session)):
    d = s.get(Driver, driver_id)
    if not d:
        raise HTTPException(status_code=404, detail="driver not found")
    if (req.name or "").strip(): d.name = req.name.strip()
    if (req.vehicle_make or "").strip(): d.vehicle_make = req.vehicle_make.strip()
    if (req.vehicle_plate or "").strip(): d.vehicle_plate = req.vehicle_plate.strip()
    if (req.vehicle_class or "").strip(): d.vehicle_class = req.vehicle_class.strip()
    if (req.vehicle_color or "").strip(): d.vehicle_color = req.vehicle_color.strip()
    if (req.phone or "").strip(): d.phone = req.phone.strip()
    s.add(d); s.commit(); s.refresh(d)
    return d


@router.get("/drivers/{driver_id}", response_model=DriverOut)
def get_driver(driver_id: str, s: Session = Depends(get_session)):
    d = s.get(Driver, driver_id)
    if not d:
        raise HTTPException(status_code=404, detail="driver not found")
    return d


class DriverStatsOut(BaseModel):
    driver_id: str
    period: str
    from_iso: str
    to_iso: str
    rides_completed: int
    rides_canceled: int
    total_fare_cents: int
    total_driver_payout_cents: int
    broker_fee_cents: int
    avg_rating: Optional[float] = None


@router.get("/drivers/{driver_id}/stats", response_model=DriverStatsOut)
def driver_stats(driver_id: str, period: str = "today", s: Session = Depends(get_session)):
    now = datetime.utcnow()
    if period == "7d":
        start = now.replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(days=6)
    elif period == "30d":
        start = now.replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(days=29)
    else:
        # default: today
        start = now.replace(hour=0, minute=0, second=0, microsecond=0)
        period = "today"
    end = now
    stmt = select(Ride).where(
        Ride.driver_id == driver_id,
        Ride.requested_at >= start,
        Ride.requested_at <= end,
    )
    rides = s.execute(stmt).scalars().all()
    completed = [r for r in rides if r.status == "completed"]
    canceled = [r for r in rides if r.status == "canceled" and r.driver_id]
    total_fare = sum(int(r.fare_cents or 0) for r in completed)
    rate = _get_brokerage_rate(s)
    broker_fee = int(round(total_fare * rate))
    payout = max(0, total_fare - broker_fee)
    ratings = [int(r.rider_rating or 0) for r in completed if getattr(r, "rider_rating", None)]
    avg_rating = None
    if ratings:
        avg_rating = sum(ratings) / len(ratings)
    return DriverStatsOut(
        driver_id=driver_id,
        period=period,
        from_iso=start.isoformat() + "Z",
        to_iso=end.isoformat() + "Z",
        rides_completed=len(completed),
        rides_canceled=len(canceled),
        total_fare_cents=total_fare,
        total_driver_payout_cents=payout,
        broker_fee_cents=broker_fee,
        avg_rating=avg_rating,
    )


class TaxiAdminSummaryOut(BaseModel):
    rides_total: int
    rides_today: int
    rides_completed_today: int
    rides_canceled_today: int
    total_fare_cents_today: int
    total_driver_payout_cents_today: int
    broker_fee_cents_today: int


@router.get("/admin/summary", response_model=TaxiAdminSummaryOut)
def taxi_admin_summary(s: Session = Depends(get_session)):
    now = datetime.utcnow()
    start_today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    end_today = start_today + timedelta(days=1)
    total = s.execute(select(func.count(Ride.id))).scalar() or 0
    today_all = s.execute(
        select(Ride).where(
            Ride.requested_at >= start_today,
            Ride.requested_at < end_today,
        )
    ).scalars().all()
    rides_today = len(today_all)
    completed_today = [r for r in today_all if r.status == "completed"]
    canceled_today = [r for r in today_all if r.status == "canceled"]
    total_fare = sum(int(r.fare_cents or 0) for r in completed_today)
    rate = _get_brokerage_rate(s)
    broker_fee = int(round(total_fare * rate))
    payout = max(0, total_fare - broker_fee)
    return TaxiAdminSummaryOut(
        rides_total=int(total),
        rides_today=rides_today,
        rides_completed_today=len(completed_today),
        rides_canceled_today=len(canceled_today),
        total_fare_cents_today=total_fare,
        total_driver_payout_cents_today=payout,
        broker_fee_cents_today=broker_fee,
    )


@router.get("/drivers", response_model=List[DriverOut])
def list_drivers(status: str = "", limit: int = 50, s: Session = Depends(get_session)):
    stmt = select(Driver)
    if status:
        stmt = stmt.where(Driver.status == status)
    stmt = stmt.order_by(Driver.created_at.desc()).limit(max(1, min(limit, 200)))
    return s.execute(stmt).scalars().all()


@router.get("/drivers/lookup", response_model=DriverOut)
def driver_lookup(phone: Optional[str] = None, vehicle_plate: Optional[str] = None, request: Request = None, s: Session = Depends(get_session)):
    """
    Internal helper: find a single driver by phone or vehicle plate.
    """
    _require_internal(request)
    if not phone and not vehicle_plate:
        raise HTTPException(status_code=400, detail="phone or vehicle_plate required")
    stmt = select(Driver)
    if phone:
        stmt = stmt.where(Driver.phone == phone)
    if vehicle_plate:
        stmt = stmt.where(Driver.vehicle_plate == vehicle_plate)
    d = s.execute(stmt.order_by(Driver.created_at.desc()).limit(1)).scalars().first()
    if not d:
        raise HTTPException(status_code=404, detail="driver not found")
    return d


# ---- Rider registry ----
class Rider(Base):
    __tablename__ = "riders"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    name: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    phone: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class RiderRegisterReq(BaseModel):
    name: Optional[str] = None
    phone: str
    wallet_id: Optional[str] = None


class RiderOut(BaseModel):
    id: str
    name: Optional[str]
    phone: Optional[str]
    wallet_id: Optional[str]
    model_config = ConfigDict(from_attributes=True)


def _get_rider_by_phone(s: Session, phone: str) -> Optional[Rider]:
    try:
        stmt = select(Rider).where(Rider.phone == phone).limit(1)
        return s.execute(stmt).scalars().first()
    except Exception:
        return None


@router.post("/riders", response_model=RiderOut)
def register_rider(req: RiderRegisterReq, s: Session = Depends(get_session)):
    phone = req.phone.strip()
    r0 = _get_rider_by_phone(s, phone)
    if r0:
        if (req.name or "").strip():
            r0.name = req.name.strip()
        if (req.wallet_id or "").strip():
            r0.wallet_id = req.wallet_id.strip()
        s.add(r0); s.commit(); s.refresh(r0)
        return r0
    r = Rider(id=str(uuid.uuid4()), name=(req.name or None), phone=phone, wallet_id=((req.wallet_id or None)))
    s.add(r); s.commit(); s.refresh(r)
    return r


@router.get("/riders/{rider_id}", response_model=RiderOut)
def get_rider(rider_id: str, s: Session = Depends(get_session)):
    r = s.get(Rider, rider_id)
    if not r:
        raise HTTPException(status_code=404, detail="rider not found")
    return r


@router.post("/drivers/{driver_id}/block")
def driver_block(driver_id: str, request: Request, s: Session = Depends(get_session)):
    _require_internal(request)
    d = s.get(Driver, driver_id)
    if not d:
        raise HTTPException(status_code=404, detail="driver not found")
    d.is_blocked = True
    d.status = "offline"
    s.add(d); s.commit(); s.refresh(d)
    return {"ok": True, "is_blocked": d.is_blocked}


@router.post("/drivers/{driver_id}/unblock")
def driver_unblock(driver_id: str, request: Request, s: Session = Depends(get_session)):
    _require_internal(request)
    d = s.get(Driver, driver_id)
    if not d:
        raise HTTPException(status_code=404, detail="driver not found")
    d.is_blocked = False
    s.add(d); s.commit(); s.refresh(d)
    return {"ok": True, "is_blocked": d.is_blocked}


class BalanceSetReq(BaseModel):
    set_cents: Optional[int] = None
    delta_cents: Optional[int] = None


@router.post("/drivers/{driver_id}/balance")
def driver_balance(driver_id: str, req: BalanceSetReq, request: Request, s: Session = Depends(get_session)):
    _require_internal(request)
    d = s.get(Driver, driver_id)
    if not d:
        raise HTTPException(status_code=404, detail="driver not found")
    if req.set_cents is not None:
        d.balance_cents = max(0, int(req.set_cents))
    elif req.delta_cents is not None:
        d.balance_cents = max(0, int(d.balance_cents or 0) + int(req.delta_cents))
    else:
        raise HTTPException(status_code=400, detail="set_cents or delta_cents required")
    s.add(d); s.commit(); s.refresh(d)
    return {"ok": True, "balance_cents": int(d.balance_cents or 0)}


class BalanceIdentityReq(BaseModel):
    phone: Optional[str] = None
    vehicle_plate: Optional[str] = None
    set_cents: Optional[int] = None
    delta_cents: Optional[int] = None


@router.post("/drivers/balance_by_identity")
def driver_balance_by_identity(req: BalanceIdentityReq, request: Request, s: Session = Depends(get_session)):
    _require_internal(request)
    if not req.phone and not req.vehicle_plate:
        raise HTTPException(status_code=400, detail="phone or vehicle_plate required")
    stmt = select(Driver)
    if req.phone:
        stmt = stmt.where(Driver.phone == req.phone)
    if req.vehicle_plate:
        stmt = stmt.where(Driver.vehicle_plate == req.vehicle_plate)
    d = s.execute(stmt.limit(2)).scalars().first()
    if not d:
        raise HTTPException(status_code=404, detail="driver not found")
    if req.set_cents is not None:
        d.balance_cents = max(0, int(req.set_cents))
    elif req.delta_cents is not None:
        d.balance_cents = max(0, int(d.balance_cents or 0) + int(req.delta_cents))
    else:
        raise HTTPException(status_code=400, detail="set_cents or delta_cents required")
    s.add(d); s.commit(); s.refresh(d)
    return {"ok": True, "driver_id": d.id, "balance_cents": int(d.balance_cents or 0)}


@router.delete("/drivers/{driver_id}")
def driver_delete(driver_id: str, request: Request, s: Session = Depends(get_session)):
    _require_internal(request)
    d = s.get(Driver, driver_id)
    if not d:
        raise HTTPException(status_code=404, detail="driver not found")
    s.delete(d); s.commit()
    return {"ok": True}


class TaxiSettings(BaseModel):
    brokerage_rate: float


@router.get("/settings", response_model=TaxiSettings)
def get_settings(s: Session = Depends(get_session)):
    rate = _get_brokerage_rate(s)
    return TaxiSettings(brokerage_rate=rate)


class TaxiSettingsUpdate(BaseModel):
    brokerage_rate: float


@router.post("/settings", response_model=TaxiSettings)
def update_settings(req: TaxiSettingsUpdate, request: Request, s: Session = Depends(get_session)):
    _require_internal(request)
    rate = req.brokerage_rate
    if not (0.0 <= rate <= 0.5):
        raise HTTPException(status_code=400, detail="brokerage_rate must be between 0.0 and 0.5")
    cfg = s.get(TaxiConfig, "brokerage_rate")
    if not cfg:
        cfg = TaxiConfig(key="brokerage_rate", value=str(rate))
    else:
        cfg.value = str(rate)
    s.add(cfg); s.commit(); s.refresh(cfg)
    return TaxiSettings(brokerage_rate=float(cfg.value or BROKERAGE_RATE))


@router.get("/drivers/{driver_id}/rides", response_model=List[RideOut])
def driver_rides(driver_id: str, status: str = "", limit: int = 10, s: Session = Depends(get_session)):
    stmt = select(Ride).where(Ride.driver_id == driver_id)
    if status:
        stmt = stmt.where(Ride.status == status)
    stmt = stmt.order_by(Ride.requested_at.desc()).limit(max(1, min(limit, 50)))
    return s.execute(stmt).scalars().all()


# ---- Rider / rides endpoints ----
@router.post("/rides/request", response_model=RideOut)
def request_ride(req: RideRequest, idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"), request: Request = None, s: Session = Depends(get_session)):
    _require_internal(request)
    # Idempotency: return existing ride if this key was seen
    if idempotency_key:
        ie = s.get(Idempotency, idempotency_key)
        if ie and ie.ride_id:
            r0 = s.get(Ride, ie.ride_id)
            if r0:
                return r0
    # pick nearest eligible driver (online, not blocked, sufficient available balance = balance - active holds)
    # compute fare estimate for reserve (brokerage fee)
    km_est = _haversine_km(req.pickup_lat, req.pickup_lon, req.dropoff_lat, req.dropoff_lon)
    eta_min = _eta_min_from_km(km_est)
    vclass = (req.vehicle_class or 'classic')
    fare_est = _estimate_fare_cents(km_est, eta_min, vclass)
    reserve = int(round(fare_est * _get_brokerage_rate(s)))
    drivers = s.execute(select(Driver).where(Driver.status == "online", Driver.lat.is_not(None), Driver.lon.is_not(None), Driver.is_blocked == False)).scalars().all()
    chosen: Optional[Driver] = None
    best = 1e18
    active_statuses = ("assigned", "accepted", "on_trip")
    for d in drivers:
        # available = balance - sum(active holds)
        try:
            holds = s.execute(select(func.coalesce(func.sum(Ride.driver_fee_hold_cents), 0)).where(Ride.driver_id == d.id, Ride.status.in_(active_statuses))).scalar() or 0
        except Exception:
            holds = 0
        available = int(d.balance_cents or 0) - int(holds or 0)
        if available < reserve:
            continue
        dist = _distance2(req.pickup_lat, req.pickup_lon, d.lat or 0.0, d.lon or 0.0)
        if dist < best:
            best = dist; chosen = d
    ride_id = str(uuid.uuid4())
    # normalize rider fields if rider_id is provided
    rider_phone = req.rider_phone
    rider_wallet_id = req.rider_wallet_id
    if (req.rider_id or "").strip():
        rrec = s.get(Rider, req.rider_id.strip())
        if rrec:
            rider_phone = rrec.phone or rider_phone
            rider_wallet_id = rrec.wallet_id or rider_wallet_id
    r = Ride(
        id=ride_id,
        rider_phone=rider_phone,
        rider_wallet_id=(rider_wallet_id or None),
        rider_id=(req.rider_id or None),
        pickup_lat=req.pickup_lat, pickup_lon=req.pickup_lon,
        dropoff_lat=req.dropoff_lat, dropoff_lon=req.dropoff_lon,
        driver_id=(chosen.id if chosen else None),
        status=("assigned" if chosen else "requested"),
        assigned_at=(datetime.utcnow() if chosen else None),
        requested_vehicle_class=(req.vehicle_class or None)
    )
    # apply hold if assigned
    if chosen is not None:
        r.driver_fee_hold_cents = reserve
    s.add(r); s.commit(); s.refresh(r)
    if idempotency_key:
        try:
            s.add(Idempotency(key=idempotency_key, ride_id=r.id)); s.commit()
        except Exception:
            pass
    return r


def _get_ride_or_404(s: Session, ride_id: str) -> Ride:
    r = s.get(Ride, ride_id)
    if not r:
        raise HTTPException(status_code=404, detail="ride not found")
    return r


@router.get("/rides/{ride_id}", response_model=RideOut)
def get_ride(ride_id: str, s: Session = Depends(get_session)):
    r = _get_ride_or_404(s, ride_id)
    # Attach brokerage info for detail view (not persisted)
    try:
      if getattr(r, "fare_cents", None):
          rate = _get_brokerage_rate(s)
          fare = int(r.fare_cents or 0)
          bf = int(round(fare * rate))
          setattr(r, "broker_fee_cents", bf)
          setattr(r, "driver_payout_cents", max(0, fare - bf))
    except Exception:
      pass
    return r


class QuoteOut(BaseModel):
    km: float
    fare_cents: int
    eta_min: int
    vehicle_class: Optional[str] = None
    surge_multiplier: Optional[float] = None
    night: Optional[bool] = None
    weekend: Optional[bool] = None
    broker_fee_cents: Optional[int] = None
    driver_payout_cents: Optional[int] = None


@router.get("/rides/{ride_id}/quote", response_model=QuoteOut)
def ride_quote(ride_id: str, s: Session = Depends(get_session)):
    r = _get_ride_or_404(s, ride_id)
    km, eta_min = _route_distance_eta_km(r.pickup_lat, r.pickup_lon, r.dropoff_lat, r.dropoff_lon)
    vclass = r.requested_vehicle_class
    if r.driver_id:
        try:
            d = s.get(Driver, r.driver_id)
            if d and d.vehicle_class:
                vclass = d.vehicle_class
        except Exception:
            pass
    fare = _estimate_fare_cents(km, eta_min, vclass)
    mult, night, weekend = _surge_flags()
    broker_fee = int(round(fare * _get_brokerage_rate(s)))
    driver_payout = max(0, fare - broker_fee)
    return QuoteOut(
        km=round(km, 2),
        fare_cents=fare,
        eta_min=eta_min,
        vehicle_class=(vclass or 'classic'),
        surge_multiplier=round(mult, 2),
        night=night,
        weekend=weekend,
        broker_fee_cents=broker_fee,
        driver_payout_cents=driver_payout,
    )


class PreQuoteReq(BaseModel):
    pickup_lat: float
    pickup_lon: float
    dropoff_lat: float
    dropoff_lon: float
    vehicle_class: Optional[str] = None


@router.post("/rides/quote", response_model=QuoteOut)
def pre_quote(req: PreQuoteReq):
    km, eta_min = _route_distance_eta_km(req.pickup_lat, req.pickup_lon, req.dropoff_lat, req.dropoff_lon)
    vclass = (req.vehicle_class or 'classic')
    fare = _estimate_fare_cents(km, eta_min, vclass)
    mult, night, weekend = _surge_flags()
    # Use standalone brokerage rate (no session needed)
    broker_fee = int(round(fare * _get_brokerage_rate(None)))
    driver_payout = max(0, fare - broker_fee)
    return QuoteOut(
        km=round(km, 2),
        fare_cents=fare,
        eta_min=eta_min,
        vehicle_class=vclass,
        surge_multiplier=round(mult, 2),
        night=night,
        weekend=weekend,
        broker_fee_cents=broker_fee,
        driver_payout_cents=driver_payout,
    )


@router.get("/rides", response_model=List[RideOut])
def list_rides(status: str = "", limit: int = 50, s: Session = Depends(get_session)):
    stmt = select(Ride)
    if status:
        stmt = stmt.where(Ride.status == status)
    stmt = stmt.order_by(Ride.requested_at.desc()).limit(max(1, min(limit, 200)))
    rides = s.execute(stmt).scalars().all()
    # Attach brokerage info for admin/operator views (not persisted)
    try:
        rate = _get_brokerage_rate(s)
        for r in rides:
            if getattr(r, "fare_cents", None):
                fare = int(r.fare_cents or 0)
                bf = int(round(fare * rate))
                setattr(r, "broker_fee_cents", bf)
                setattr(r, "driver_payout_cents", max(0, fare - bf))
    except Exception:
        pass
    return rides


@router.post("/rides/{ride_id}/accept", response_model=RideOut)
def accept_ride(ride_id: str, driver_id: str, request: Request, s: Session = Depends(get_session)):
    _require_internal(request)
    r = _get_ride_or_404(s, ride_id)
    if r.status != "assigned" or r.driver_id != driver_id:
        raise HTTPException(status_code=400, detail="not assignable to this driver")
    r.status = "accepted"; r.accepted_at = datetime.utcnow()
    s.add(r); s.commit(); s.refresh(r)
    return r


@router.post("/rides/{ride_id}/assign", response_model=RideOut)
def assign_ride(ride_id: str, driver_id: str, request: Request, s: Session = Depends(get_session)):
    _require_internal(request)
    r = _get_ride_or_404(s, ride_id)
    d = s.get(Driver, driver_id)
    if not d:
        raise HTTPException(status_code=404, detail="driver not found")
    if r.status not in ("requested", "assigned"):
        raise HTTPException(status_code=400, detail="cannot assign now")
    # compute hold reserve and verify available balance
    km_est = _haversine_km(r.pickup_lat, r.pickup_lon, r.dropoff_lat, r.dropoff_lon)
    eta_min = _eta_min_from_km(km_est)
    vclass = r.requested_vehicle_class or (d.vehicle_class if d else None)
    fare_est = _estimate_fare_cents(km_est, eta_min, vclass)
    reserve = int(round(fare_est * _get_brokerage_rate(s)))
    active_statuses = ("assigned", "accepted", "on_trip")
    holds = s.execute(select(func.coalesce(func.sum(Ride.driver_fee_hold_cents), 0)).where(Ride.driver_id == d.id, Ride.status.in_(active_statuses))).scalar() or 0
    available = int(d.balance_cents or 0) - int(holds or 0)
    if d.is_blocked:
        raise HTTPException(status_code=403, detail="driver blocked")
    if available < reserve:
        raise HTTPException(status_code=402, detail="insufficient balance for hold")
    r.driver_id = driver_id
    r.status = "assigned"
    r.assigned_at = datetime.utcnow()
    r.driver_fee_hold_cents = reserve
    s.add(r); s.commit(); s.refresh(r)
    try:
        _notify_driver_new_ride(d, r)
    except Exception:
        pass
    return r


@router.post("/rides/{ride_id}/start", response_model=RideOut)
def start_ride(ride_id: str, driver_id: str, request: Request, s: Session = Depends(get_session)):
    _require_internal(request)
    r = _get_ride_or_404(s, ride_id)
    if r.status != "accepted" or r.driver_id != driver_id:
        raise HTTPException(status_code=400, detail="cannot start")
    r.status = "on_trip"; r.started_at = datetime.utcnow()
    s.add(r); s.commit(); s.refresh(r)
    return r


@router.post("/rides/{ride_id}/complete", response_model=RideOut)
def complete_ride(ride_id: str, driver_id: str, request: Request, s: Session = Depends(get_session)):
    _require_internal(request)
    r = _get_ride_or_404(s, ride_id)
    if r.status != "on_trip" or r.driver_id != driver_id:
        raise HTTPException(status_code=400, detail="cannot complete")
    # distance + time based fare using tariffs
    km = _haversine_km(r.pickup_lat, r.pickup_lon, r.dropoff_lat, r.dropoff_lon)
    try:
        secs = int(((datetime.utcnow()) - (r.started_at or r.accepted_at or r.assigned_at or datetime.utcnow())).total_seconds())
        mins = max(1, int(round(secs / 60.0)))
    except Exception:
        mins = _eta_min_from_km(km)
    d = s.get(Driver, driver_id)
    vclass = r.requested_vehicle_class or (d.vehicle_class if d else None)
    fare = _estimate_fare_cents(km, mins, vclass)
    r.status = "completed"; r.completed_at = datetime.utcnow(); r.fare_cents = fare
    # commission (brokerage fee) at completion
    commission = int(round(fare * _get_brokerage_rate(s)))
    try:
        d = s.get(Driver, driver_id)
        if d:
            d.balance_cents = max(0, int(d.balance_cents or 0) - commission)
            s.add(d)
    except Exception:
        pass
    # release hold
    try:
        r.driver_fee_hold_cents = 0
    except Exception:
        pass
    # Payment logic depends on CASH_ONLY flag
    if CASH_ONLY == 1:
        # Cash payment: mark as cash; no in-app transfer
        r.payments_status = "cash"
    else:
        # Attempt auto-payment if both wallets known and not already pre-paid
        try:
            d = s.get(Driver, driver_id)
            if not r.payments_txn_id:
                if d and d.wallet_id and r.rider_wallet_id and fare > 0 and PAYMENTS_BASE:
                    resp = _payments_transfer(r.rider_wallet_id, d.wallet_id, fare, ikey=f"ride-{r.id}", ref=f"ride-{r.id}")
                    r.payments_txn_id = str(resp.get("id") or resp.get("txn_id") or "")
                    r.payments_status = "ok"
        except Exception as e:
            r.payments_status = "failed"
    s.add(r); s.commit(); s.refresh(r)
    return r


@router.post("/rides/{ride_id}/cancel", response_model=RideOut)
def cancel_ride(ride_id: str, request: Request, s: Session = Depends(get_session)):
    _require_internal(request)
    r = _get_ride_or_404(s, ride_id)
    if r.status in ("on_trip", "completed"):
        raise HTTPException(status_code=400, detail="cannot cancel now")
    r.status = "canceled"; r.canceled_at = datetime.utcnow(); r.driver_fee_hold_cents = 0
    s.add(r); s.commit(); s.refresh(r)
    return r


@router.post("/topup_qr_log", response_model=TaxiTopupQrLogOut)
def create_topup_qr_log(req: TaxiTopupQrLogOut, request: Request, s: Session = Depends(get_session)):
    # Internal-only: called by BFF when a TaxiTopup QR is created
    _require_internal(request)
    log = TaxiTopupQrLog(
        id=req.id or str(uuid.uuid4()),
        driver_id=req.driver_id,
        driver_phone=(req.driver_phone or None),
        amount_cents=req.amount_cents,
        created_by=(req.created_by or None),
        payload=req.payload,
    )
    s.add(log); s.commit(); s.refresh(log)
    return log


class TaxiTopupQrRedeemIn(BaseModel):
    payload: str
    driver_phone: Optional[str] = None
    driver_id: Optional[str] = None


@router.post("/topup_qr_log/redeem", response_model=TaxiTopupQrLogOut)
def mark_topup_qr_redeemed(req: TaxiTopupQrRedeemIn, request: Request, s: Session = Depends(get_session)):
    _require_internal(request)
    payload = (req.payload or "").strip()
    if not payload:
        raise HTTPException(status_code=400, detail="payload required")
    q = select(TaxiTopupQrLog).where(
        TaxiTopupQrLog.payload == payload,
        TaxiTopupQrLog.redeemed == False,  # type: ignore
    ).order_by(TaxiTopupQrLog.created_at.desc())
    log = s.execute(q).scalars().first()
    if not log:
        raise HTTPException(status_code=404, detail="log not found or already redeemed")
    driver_id = (req.driver_id or log.driver_id or "").strip()
    if not driver_id:
        raise HTTPException(status_code=400, detail="driver_id missing for redeem")
    if log.driver_id and log.driver_id != driver_id:
        raise HTTPException(status_code=403, detail="driver mismatch")
    driver = s.get(Driver, driver_id)
    if not driver:
        raise HTTPException(status_code=404, detail="driver not found")
    if req.driver_phone and driver.phone:
        if driver.phone.strip() != req.driver_phone.strip():
            raise HTTPException(status_code=403, detail="QR does not belong to this driver")
    log.redeemed = True
    log.redeemed_at = datetime.utcnow()
    log.redeemed_by = (req.driver_phone or log.redeemed_by or driver.phone or "").strip() or None
    # Apply topup atomically with redeem, so QR codes are single-use.
    driver.balance_cents = max(0, int(driver.balance_cents or 0) + int(log.amount_cents or 0))
    s.add(driver); s.add(log); s.commit(); s.refresh(log)
    try:
        log.driver_balance_cents = int(driver.balance_cents or 0)
    except Exception:
        log.driver_balance_cents = int(driver.balance_cents or 0)
    return log


@router.get("/topup_qr_logs", response_model=List[TaxiTopupQrLogOut])
def list_topup_qr_logs(limit: int = 200, request: Request = None, s: Session = Depends(get_session)):
    # Internal-only; BFF enforces admin/superadmin before proxying
    _require_internal(request)
    q = select(TaxiTopupQrLog).order_by(TaxiTopupQrLog.created_at.desc()).limit(max(1, min(limit, 1000)))
    logs = s.execute(q).scalars().all()
    return logs


@router.get("/topup_qr_logs/export")
def export_topup_qr_logs(limit: int = 1000, status: str = "", request: Request = None, s: Session = Depends(get_session)):
    """
    Export TaxiTopup QR logs as CSV for Superadmin / audit.
    This endpoint is internal; BFF should proxy and handle admin auth.
    """
    _require_internal(request)
    q = select(TaxiTopupQrLog)
    st = (status or "").lower()
    if st == "open":
        q = q.where(TaxiTopupQrLog.redeemed == False)  # type: ignore
    elif st == "redeemed":
        q = q.where(TaxiTopupQrLog.redeemed == True)  # type: ignore
    q = q.order_by(TaxiTopupQrLog.created_at.desc()).limit(max(1, min(limit, 5000)))
    rows = s.execute(q).scalars().all()

    buf = StringIO()
    w = csv.writer(buf)
    w.writerow([
        "id",
        "driver_id",
        "driver_phone",
        "amount_cents",
        "amount_syp",
        "created_by",
        "created_at",
        "redeemed",
        "redeemed_at",
        "redeemed_by",
        "payload",
    ])
    for r in rows:
        try:
            created_at = r.created_at.isoformat() if isinstance(r.created_at, datetime) else (r.created_at or "")
        except Exception:
            created_at = str(r.created_at or "")
        try:
            redeemed_at = r.redeemed_at.isoformat() if isinstance(r.redeemed_at, datetime) else (r.redeemed_at or "")
        except Exception:
            redeemed_at = str(r.redeemed_at or "")
        amount_cents = int(r.amount_cents or 0)
        amount_syp = amount_cents / 100.0
        w.writerow([
            r.id,
            r.driver_id,
            r.driver_phone or "",
            amount_cents,
            f"{amount_syp:.2f}",
            r.created_by or "",
            created_at,
            "true" if r.redeemed else "false",
            redeemed_at,
            r.redeemed_by or "",
            r.payload,
        ])
    csv_data = buf.getvalue()
    headers = {"Content-Disposition": "attachment; filename=taxi_topup_qr_logs.csv"}
    return Response(content=csv_data, media_type="text/csv", headers=headers)


@router.post("/rides/{ride_id}/rating", response_model=RideOut)
def rate_ride(ride_id: str, req: RideRatingReq, request: Request, s: Session = Depends(get_session)):
    # Rating is allowed only for existing rides; typically after completion.
    _require_internal(request)
    r = _get_ride_or_404(s, ride_id)
    r.rider_rating = req.rating
    r.rider_rating_comment = (req.comment or "").strip() or None
    s.add(r); s.commit(); s.refresh(r)
    return r
# Payments helper
def _payments_transfer(from_wallet: str, to_wallet: str, amount_cents: int, ikey: str, ref: Optional[str] = None) -> dict:
    if not PAYMENTS_BASE:
        raise RuntimeError("PAYMENTS_BASE_URL not configured")
    url = PAYMENTS_BASE.rstrip('/') + '/transfer'
    headers = {"Content-Type": "application/json", "Idempotency-Key": ikey, "X-Merchant": "taxi"}
    if ref:
        headers["X-Ref"] = ref
    payload = {"from_wallet_id": from_wallet, "to_wallet_id": to_wallet, "amount_cents": amount_cents}
    r = httpx.post(url, json=payload, headers=headers, timeout=10)
    r.raise_for_status()
    return r.json()


def _payments_create_user(phone: str) -> Optional[str]:
    if not PAYMENTS_BASE:
        return None
    url = PAYMENTS_BASE.rstrip('/') + '/users'
    r = httpx.post(url, json={"phone": phone}, timeout=10)
    r.raise_for_status()
    j = r.json()
    return j.get("wallet_id")


def _send_fcm_to_token(token: str, title: str, body: str, data: Optional[dict] = None) -> None:
    # Best-effort: HTTP v1 API using service account (see fcm.py)
    try:
        str_data = {str(k): str(v) for k, v in (data or {}).items()}
        send_fcm_v1(token, title, body, str_data)
    except Exception:
        return


def _notify_driver_new_ride(driver: Driver, ride: Ride) -> None:
    token = (getattr(driver, "fcm_token", None) or "").strip()
    if not token:
        return
    title = "New ride request"
    try:
        pickup = f"{ride.pickup_lat:.4f},{ride.pickup_lon:.4f}"
    except Exception:
        pickup = ""
    details = []
    if pickup:
        details.append(f"Pickup: {pickup}")
    if ride.rider_phone:
        details.append(f"Rider: {ride.rider_phone}")
    body = " · ".join(details) if details else f"Ride {ride.id}"
    data = {
        "ride_id": ride.id,
        "pickup_lat": str(ride.pickup_lat),
        "pickup_lon": str(ride.pickup_lon),
        "dropoff_lat": str(ride.dropoff_lat),
        "dropoff_lon": str(ride.dropoff_lon),
        "rider_phone": ride.rider_phone or "",
    }
    _send_fcm_to_token(token, title, body, data)


@router.post("/rides/book_pay", response_model=RideOut)
def book_and_pay(req: RideRequest, idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"), request: Request = None, s: Session = Depends(get_session)):
    _require_internal(request)
    # Idempotency: if key exists and maps to a ride, return it
    if idempotency_key:
        ie = s.get(Idempotency, idempotency_key)
        if ie and ie.ride_id:
            r0 = s.get(Ride, ie.ride_id)
            if r0:
                return r0
    # If cash-only, no wallet required; else require wallet
    if CASH_ONLY != 1:
        if not req.rider_wallet_id:
            raise HTTPException(status_code=400, detail="rider_wallet_id required for payment")
    # Estimate fare and reserve broker fee to filter eligible drivers
    km_est = _haversine_km(req.pickup_lat, req.pickup_lon, req.dropoff_lat, req.dropoff_lon)
    eta_min = _eta_min_from_km(km_est)
    vclass = req.vehicle_class or "classic"
    fare_est = _estimate_fare_cents(km_est, eta_min, vclass)
    reserve = int(round(fare_est * _get_brokerage_rate(s)))
    drivers_q = select(Driver).where(
        Driver.status == "online",
        Driver.lat.is_not(None),
        Driver.lon.is_not(None),
        Driver.is_blocked == False,  # type: ignore
    )
    if CASH_ONLY != 1:
        drivers_q = drivers_q.where(Driver.wallet_id.is_not(None))
    drivers = s.execute(drivers_q).scalars().all()
    if not drivers:
        raise HTTPException(status_code=400, detail="no online drivers available")
    chosen: Optional[Driver] = None
    best = 1e18
    active_statuses = ("assigned", "accepted", "on_trip")
    for d in drivers:
        try:
            holds = s.execute(
                select(func.coalesce(func.sum(Ride.driver_fee_hold_cents), 0)).where(
                    Ride.driver_id == d.id,
                    Ride.status.in_(active_statuses),
                )
            ).scalar() or 0
        except Exception:
            holds = 0
        available = int(d.balance_cents or 0) - int(holds or 0)
        if available < reserve:
            continue
        dist = _distance2(req.pickup_lat, req.pickup_lon, d.lat or 0.0, d.lon or 0.0)
        if dist < best:
            best = dist; chosen = d
    if not chosen:
        raise HTTPException(status_code=400, detail="no online drivers available")
    # create ride and compute fare
    ride_id = str(uuid.uuid4())
    km = _haversine_km(req.pickup_lat, req.pickup_lon, req.dropoff_lat, req.dropoff_lon)
    fare = int(round(FARE_BASE_CENTS + FARE_PER_KM_CENTS * km))
    if fare < MIN_FARE_CENTS:
        fare = MIN_FARE_CENTS
    rider_phone = req.rider_phone
    rider_wallet_id = req.rider_wallet_id
    if (req.rider_id or "").strip():
        rrec = s.get(Rider, req.rider_id.strip())
        if rrec:
            rider_phone = rrec.phone or rider_phone
            rider_wallet_id = rrec.wallet_id or rider_wallet_id
    r = Ride(
        id=ride_id,
        rider_phone=rider_phone,
        rider_wallet_id=(rider_wallet_id or None),
        rider_id=(req.rider_id or None),
        pickup_lat=req.pickup_lat,
        pickup_lon=req.pickup_lon,
        dropoff_lat=req.dropoff_lat,
        dropoff_lon=req.dropoff_lon,
        driver_id=chosen.id,
        status="assigned",
        assigned_at=datetime.utcnow(),
        fare_cents=fare,
        requested_vehicle_class=(req.vehicle_class or None),
    )
    r.driver_fee_hold_cents = reserve
    s.add(r)
    s.commit(); s.refresh(r)
    try:
        _notify_driver_new_ride(chosen, r)
    except Exception:
        pass
    if idempotency_key:
        try:
            s.add(Idempotency(key=idempotency_key, ride_id=r.id)); s.commit()
        except Exception:
            pass
    if CASH_ONLY == 1:
        # Cash: mark payments_status as 'cash' and return
        r.payments_status = "cash"
        s.add(r); s.commit(); s.refresh(r)
        return r
    # Non-cash: payment is collected on ride completion; mark pending for now.
    if CASH_ONLY != 1:
        r.payments_status = "pending"
        s.add(r); s.commit(); s.refresh(r)
    return r


app.include_router(router)
