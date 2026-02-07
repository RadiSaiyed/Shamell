import os
import uuid
from datetime import datetime, timedelta
from math import radians, cos, sin, asin, sqrt
import random
import asyncio
from contextlib import asynccontextmanager
from typing import List, Optional, Dict, Any

from fastapi import APIRouter, Depends, FastAPI, HTTPException, WebSocket, WebSocketDisconnect, Header, Request
from pydantic import BaseModel, Field
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column
import httpx
import csv
from io import StringIO
from starlette.responses import StreamingResponse

from shamell_shared import RequestIDMiddleware, add_standard_health, configure_cors, setup_json_logging
from .ws import queue_broadcast
from .routes import router_ws, drain_queue_forever


def _env(key: str, default: str) -> str:
    v = os.getenv(key)
    return v if v is not None else default


DB_URL = _env("COURIER_DB_URL", "sqlite+pysqlite:////tmp/courier.db")
MAX_DISTANCE_KM = float(_env("COURIER_MAX_DISTANCE_KM", "200"))
# Ultra-late cutoff defaults to 23:59
SAME_DAY_CUTOFF_HOUR = int(_env("COURIER_SAME_DAY_CUTOFF_HOUR", "23"))
SAME_DAY_CUTOFF_MINUTE = int(_env("COURIER_SAME_DAY_CUTOFF_MINUTE", "59"))
MAPBOX_TOKEN = os.getenv("MAPBOX_TOKEN", "")
WHAT3WORDS_TOKEN = os.getenv("WHAT3WORDS_TOKEN", "")
BFF_BASE_URL = os.getenv("BFF_BASE_URL", "")
MAPBOX_PROFILE = os.getenv("MAPBOX_PROFILE", "mapbox/driving-traffic")
PTV_ROUTING_URL = os.getenv("PTV_ROUTING_URL", "")
PTV_API_KEY = os.getenv("PTV_API_KEY", "")
EMISSION_G_PER_KM = float(_env("COURIER_EMISSION_G_PER_KM", "100"))
MIN_DRIVER_BATTERY = int(_env("COURIER_MIN_DRIVER_BATTERY", "0"))
ADMIN_TOKEN = os.getenv("COURIER_ADMIN_TOKEN", "")
ADMIN_IP_ALLOWLIST = {ip.strip() for ip in (os.getenv("COURIER_ADMIN_IPS", "") or "").split(",") if ip.strip()}
INTERNAL_SECRET = os.getenv("COURIER_INTERNAL_SECRET", "")
WEBHOOK_URL = os.getenv("COURIER_WEBHOOK_URL", "")

@asynccontextmanager
async def _lifespan(app: FastAPI):
    on_startup()
    task = None
    try:
        task = asyncio.create_task(drain_queue_forever())
    except Exception:
        task = None
    try:
        yield
    finally:
        if task:
            task.cancel()
            try:
                await task
            except Exception:
                pass


app = FastAPI(title="Courier-lite", version="0.1.0", lifespan=_lifespan)
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", "*"))
add_standard_health(app)
router = APIRouter()


@app.middleware("http")
async def _internal_secret_guard(request: Request, call_next):
    if not INTERNAL_SECRET:
        return await call_next(request)
    path = request.url.path
    # allow public tracking/health/ws without secret
    if any(path.startswith(p) for p in ("/courier/track/public", "/health", "/_health", "/metrics")) or "ws" in path:
        return await call_next(request)
    hdr = request.headers.get("X-Internal-Secret")
    if hdr != INTERNAL_SECRET:
        return Response(status_code=403, content="forbidden")
    return await call_next(request)


class Base(DeclarativeBase):
    pass


class Order(Base):
    __tablename__ = "courier_orders"
    id: Mapped[str] = mapped_column(primary_key=True)
    created_at: Mapped[datetime] = mapped_column(default=datetime.utcnow)
    tracking_token: Mapped[str] = mapped_column(default=lambda: str(uuid.uuid4()))
    pickup_lat: Mapped[float]
    pickup_lng: Mapped[float]
    drop_lat: Mapped[float]
    drop_lng: Mapped[float]
    customer_name: Mapped[str]
    customer_phone: Mapped[str]
    drop_address: Mapped[Optional[str]] = mapped_column(default=None)
    status: Mapped[str] = mapped_column(default="created")
    distance_km: Mapped[float] = mapped_column(default=0.0)
    price_cents: Mapped[int] = mapped_column(default=0)
    currency: Mapped[str] = mapped_column(default="EUR")
    eta_ts: Mapped[Optional[datetime]] = mapped_column(default=None)
    driver_id: Mapped[Optional[int]] = mapped_column(default=None)
    service_type: Mapped[str] = mapped_column(default="same_day")  # same_day|next_day
    window_start: Mapped[Optional[datetime]] = mapped_column(default=None)
    window_end: Mapped[Optional[datetime]] = mapped_column(default=None)
    instructions: Mapped[Optional[str]] = mapped_column(default=None)
    pin_code: Mapped[Optional[str]] = mapped_column(default=None)
    failed_attempts: Mapped[int] = mapped_column(default=0)
    return_required: Mapped[bool] = mapped_column(default=False)
    delivered_at: Mapped[Optional[datetime]] = mapped_column(default=None)
    co2_grams: Mapped[Optional[int]] = mapped_column(default=None)
    retry_window_start: Mapped[Optional[datetime]] = mapped_column(default=None)
    retry_window_end: Mapped[Optional[datetime]] = mapped_column(default=None)
    validated_address: Mapped[Optional[str]] = mapped_column(default=None)
    address_confidence: Mapped[Optional[float]] = mapped_column(default=None)
    hub_id: Mapped[Optional[str]] = mapped_column(default=None)
    short_term_storage: Mapped[bool] = mapped_column(default=False)
    sla_due_at: Mapped[Optional[datetime]] = mapped_column(default=None)
    on_promise: Mapped[bool] = mapped_column(default=True)
    carrier: Mapped[Optional[str]] = mapped_column(default=None)
    vehicle_type: Mapped[Optional[str]] = mapped_column(default=None)  # bike/van/ev
    aftership_tracking: Mapped[Optional[str]] = mapped_column(default=None)
    apomap_id: Mapped[Optional[str]] = mapped_column(default=None)
    validated_lat: Mapped[Optional[float]] = mapped_column(default=None)
    validated_lng: Mapped[Optional[float]] = mapped_column(default=None)
    last_scan_code: Mapped[Optional[str]] = mapped_column(default=None)
    partner_id: Mapped[Optional[str]] = mapped_column(default=None)


class Event(Base):
    __tablename__ = "courier_events"
    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    order_id: Mapped[str]
    status: Mapped[str]
    note: Mapped[Optional[str]]
    created_at: Mapped[datetime] = mapped_column(default=datetime.utcnow)
    proof_url: Mapped[Optional[str]] = mapped_column(default=None)
    barcode: Mapped[Optional[str]] = mapped_column(default=None)
    signature: Mapped[Optional[str]] = mapped_column(default=None)


class Driver(Base):
    __tablename__ = "courier_drivers"
    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    name: Mapped[str]
    phone: Mapped[str]
    status: Mapped[str] = mapped_column(default="idle")  # idle/busy/offline
    lat: Mapped[float] = mapped_column(default=0.0)
    lng: Mapped[float] = mapped_column(default=0.0)
    updated_at: Mapped[datetime] = mapped_column(default=datetime.utcnow, onupdate=datetime.utcnow)
    battery_pct: Mapped[Optional[int]] = mapped_column(default=None)


class Partner(Base):
    __tablename__ = "courier_partners"
    id: Mapped[str] = mapped_column(primary_key=True)
    name: Mapped[str]
    brand_text: Mapped[Optional[str]] = mapped_column(default=None)
    logo_url: Mapped[Optional[str]] = mapped_column(default=None)
    carrier: Mapped[Optional[str]] = mapped_column(default=None)
    contact_email: Mapped[Optional[str]] = mapped_column(default=None)


class CourierIdempotency(Base):
    __tablename__ = "courier_idempotency"
    key: Mapped[str] = mapped_column(primary_key=True)
    endpoint: Mapped[Optional[str]] = mapped_column(default=None)
    order_id: Mapped[Optional[str]] = mapped_column(default=None)
    payload_hash: Mapped[Optional[str]] = mapped_column(default=None)
    created_at: Mapped[datetime] = mapped_column(default=datetime.utcnow)


class CourierApplication(Base):
    __tablename__ = "courier_applications"
    id: Mapped[str] = mapped_column(primary_key=True)
    name: Mapped[str]
    phone: Mapped[str]
    city: Mapped[Optional[str]] = mapped_column(default=None)
    vehicle_type: Mapped[Optional[str]] = mapped_column(default=None)
    experience_years: Mapped[Optional[int]] = mapped_column(default=None)
    status: Mapped[str] = mapped_column(default="pending")  # pending|approved|rejected
    note: Mapped[Optional[str]] = mapped_column(default=None)
    created_at: Mapped[datetime] = mapped_column(default=datetime.utcnow)


class PartnerIn(BaseModel):
    id: Optional[str] = None
    name: str
    brand_text: Optional[str] = None
    logo_url: Optional[str] = None
    carrier: Optional[str] = None
    contact_email: Optional[str] = None


class PartnerOut(BaseModel):
    id: str
    name: str
    brand_text: Optional[str] = None
    logo_url: Optional[str] = None
    carrier: Optional[str] = None
    contact_email: Optional[str] = None
    model_config = {"from_attributes": True}


class CourierApply(BaseModel):
    name: str
    phone: str
    city: Optional[str] = None
    vehicle_type: Optional[str] = None
    experience_years: Optional[int] = Field(default=None, ge=0, le=50)
    note: Optional[str] = None


class CourierApplicationOut(BaseModel):
    id: str
    name: str
    phone: str
    city: Optional[str] = None
    vehicle_type: Optional[str] = None
    experience_years: Optional[int] = None
    status: str
    note: Optional[str] = None
    created_at: datetime
    model_config = {"from_attributes": True}


class DriverLocation(BaseModel):
    lat: float
    lng: float
    status: str = "idle"
    battery_pct: Optional[int] = Field(default=None, ge=0, le=100)


def _require_admin(request: Request):
    if not ADMIN_TOKEN and not ADMIN_IP_ALLOWLIST:
        return
    try:
        hdr = request.headers.get("X-Admin-Token") if request else None
    except Exception:
        hdr = None
    client_ip = None
    try:
        client_ip = request.client.host  # type: ignore[attr-defined]
    except Exception:
        client_ip = None
    token_ok = (not ADMIN_TOKEN) or hdr == ADMIN_TOKEN
    ip_ok = (not ADMIN_IP_ALLOWLIST) or (client_ip in ADMIN_IP_ALLOWLIST)
    if not (token_ok and ip_ok):
        raise HTTPException(status_code=403, detail="admin token or IP required")


engine = create_engine(DB_URL, future=True)


def get_session():
    with Session(engine) as s:
        yield s


def on_startup():
    Base.metadata.create_all(engine)
    # migrations: ensure new columns exist
    from sqlalchemy import inspect, text
    insp = inspect(engine)
    if insp.has_table("courier_orders"):
        cols = {c["name"] for c in insp.get_columns("courier_orders")}
        tbl = "courier_orders"
        for col, ddl in [
            ("driver_id", "INTEGER"),
            ("tracking_token", "VARCHAR"),
            ("service_type", "VARCHAR"),
            ("window_start", "DATETIME"),
            ("window_end", "DATETIME"),
            ("instructions", "VARCHAR"),
            ("pin_code", "VARCHAR"),
            ("failed_attempts", "INTEGER"),
            ("return_required", "BOOLEAN"),
            ("delivered_at", "DATETIME"),
            ("co2_grams", "INTEGER"),
            ("retry_window_start", "DATETIME"),
            ("retry_window_end", "DATETIME"),
            ("validated_lat", "FLOAT"),
            ("validated_lng", "FLOAT"),
            ("last_scan_code", "VARCHAR"),
            ("partner_id", "VARCHAR"),
        ]:
            if col not in cols:
                try:
                    with engine.begin() as conn:
                        conn.execute(text(f"ALTER TABLE {tbl} ADD COLUMN {col} {ddl}"))
                except Exception:
                    pass
    if not insp.has_table("courier_drivers"):
        Driver.__table__.create(engine)
    else:
        cols_d = {c["name"] for c in insp.get_columns("courier_drivers")}
        if "battery_pct" not in cols_d:
            try:
                with engine.begin() as conn:
                    conn.execute(text("ALTER TABLE courier_drivers ADD COLUMN battery_pct INTEGER"))
            except Exception:
                pass
    if not insp.has_table("courier_partners"):
        Partner.__table__.create(engine)
    if not insp.has_table("courier_idempotency"):
        CourierIdempotency.__table__.create(engine)
    if not insp.has_table("courier_applications"):
        CourierApplication.__table__.create(engine)
    if insp.has_table("courier_events"):
        cols = {c["name"] for c in insp.get_columns("courier_events")}
        tbl = "courier_events"
        for col, ddl in [("proof_url", "VARCHAR"), ("barcode", "VARCHAR"), ("signature", "VARCHAR")]:
            if col not in cols:
                try:
                    with engine.begin() as conn:
                        conn.execute(text(f"ALTER TABLE {tbl} ADD COLUMN {col} {ddl}"))
                except Exception:
                    pass


@router.get("/quote")
def quote(pickup_lat: float, pickup_lng: float, drop_lat: float, drop_lng: float, currency: str = "EUR", service_type: str = "same_day"):
    dist = _haversine(pickup_lat, pickup_lng, drop_lat, drop_lng)
    # Prefer PTV routing if available, then Mapbox
    mb = _ptv_directions((pickup_lat, pickup_lng), (drop_lat, drop_lng))
    if not mb:
        mb = _mapbox_directions((pickup_lat, pickup_lng), (drop_lat, drop_lng))
    if mb:
        dist = mb["distance_km"]
    price = int(300 + dist * 100)  # base 3.00 + 1.00/km
    eta_minutes = int(dist * 3 + 20)
    if mb:
        eta_minutes = max(15, int(mb["duration_min"] + 10))
    eta = datetime.utcnow() + timedelta(minutes=eta_minutes)
    now = datetime.utcnow()
    if service_type == "asap":
        ws = now + timedelta(minutes=30)
        we = now + timedelta(minutes=90)
    elif service_type == "same_day" and (now.hour < SAME_DAY_CUTOFF_HOUR or (now.hour == SAME_DAY_CUTOFF_HOUR and now.minute <= SAME_DAY_CUTOFF_MINUTE)):
        ws = now + timedelta(hours=2)
        we = now + timedelta(hours=3)
    else:
        tomorrow = now + timedelta(days=1)
        ws = tomorrow.replace(hour=16, minute=0, second=0, microsecond=0)
        we = tomorrow.replace(hour=21, minute=0, second=0, microsecond=0)
    co2 = int(round(dist * EMISSION_G_PER_KM))
    return {
        "distance_km": round(dist, 2),
        "price_cents": price,
        "currency": currency,
        "eta_ts": eta.isoformat(),
        "window_start": ws.isoformat(),
        "window_end": we.isoformat(),
        "co2_grams": co2,
        "service_type": service_type,
        "on_promise": _on_promise(we),
        "slots": _available_slots(service_type, now=now),
    }


class OrderCreate(BaseModel):
    pickup_lat: float
    pickup_lng: float
    drop_lat: float
    drop_lng: float
    customer_name: str
    customer_phone: str
    currency: str = "EUR"
    auto_dispatch: bool = False
    service_type: str = Field(default="same_day", pattern="^(same_day|next_day|asap)$")
    instructions: Optional[str] = Field(default=None, max_length=512)
    drop_address: Optional[str] = Field(default=None, max_length=512)
    hub_id: Optional[str] = None
    carrier: Optional[str] = None
    vehicle_type: Optional[str] = None
    aftership_tracking: Optional[str] = None
    apomap_id: Optional[str] = None
    window_start: Optional[datetime] = None
    window_end: Optional[datetime] = None
    partner_id: Optional[str] = None


class OrderOut(BaseModel):
    id: str
    tracking_token: str
    status: str
    distance_km: float
    price_cents: int
    currency: str
    eta_ts: Optional[datetime]
    created_at: datetime
    driver_id: Optional[int]
    service_type: str
    window_start: Optional[datetime]
    window_end: Optional[datetime]
    instructions: Optional[str]
    pin_code: Optional[str]
    failed_attempts: int
    return_required: bool
    delivered_at: Optional[datetime]
    co2_grams: Optional[int] = None
    retry_window_start: Optional[datetime] = None
    retry_window_end: Optional[datetime] = None
    drop_address: Optional[str] = None
    validated_address: Optional[str] = None
    validated_lat: Optional[float] = None
    validated_lng: Optional[float] = None
    address_confidence: Optional[float] = None
    hub_id: Optional[str] = None
    short_term_storage: bool = False
    sla_due_at: Optional[datetime] = None
    on_promise: bool = True
    carrier: Optional[str] = None
    vehicle_type: Optional[str] = None
    aftership_tracking: Optional[str] = None
    apomap_id: Optional[str] = None
    partner_id: Optional[str] = None
    last_scan_code: Optional[str] = None
    model_config = {"from_attributes": True}


def _haversine(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    lon1, lat1, lon2, lat2 = map(radians, [lon1, lat1, lon2, lat2])
    dlon = lon2 - lon1
    dlat = lat2 - lat1
    a = sin(dlat / 2) ** 2 + cos(lat1) * cos(lat2) * sin(dlon / 2) ** 2
    c = 2 * asin(sqrt(a))
    km = 6371 * c
    return km


def _validate_window(start: datetime, end: datetime) -> None:
    if end <= start:
        raise HTTPException(status_code=400, detail="invalid window")
    if (end - start) > timedelta(hours=8):
        raise HTTPException(status_code=400, detail="window too large")
    if start.tzinfo is not None or end.tzinfo is not None:
        # keep naive UTC for simplicity
        raise HTTPException(status_code=400, detail="window must be naive UTC")
    if (end - start) != timedelta(hours=1):
        raise HTTPException(status_code=400, detail="window must be 1 hour")


def _on_promise(window_end: Optional[datetime]) -> bool:
    if not window_end:
        return True
    return datetime.utcnow() <= window_end


def _bump_sla_on_promise(od: "Order") -> None:
    od.on_promise = _on_promise(od.window_end)
    if od.status == "delivered" and od.window_end and od.delivered_at:
        od.on_promise = od.delivered_at <= od.window_end


def _slotize_same_day(now: datetime, hours_ahead: int = 6) -> list[tuple[datetime, datetime]]:
    slots = []
    start = (now + timedelta(minutes=30)).replace(minute=0, second=0, microsecond=0)
    # generate rolling 1h slots for the next few hours
    for i in range(hours_ahead):
        ws = start + timedelta(hours=i)
        we = ws + timedelta(hours=1)
        slots.append((ws, we))
    return slots


def _slotize_next_day(now: datetime) -> list[tuple[datetime, datetime]]:
    tomorrow = now + timedelta(days=1)
    base = tomorrow.replace(hour=16, minute=0, second=0, microsecond=0)
    slots = []
    for i in range(5):  # 16-17, ..., 20-21
        ws = base + timedelta(hours=i)
        we = ws + timedelta(hours=1)
        slots.append((ws, we))
    return slots


def _available_slots(service_type: str, now: Optional[datetime] = None) -> list[dict]:
    now = now or datetime.utcnow()
    slots: list[tuple[datetime, datetime]] = []
    if service_type == "asap":
        slots = [(now + timedelta(minutes=30), now + timedelta(minutes=90))]
    elif service_type == "same_day":
        slots = _slotize_same_day(now)
    else:
        slots = _slotize_next_day(now)
    return [{"start": ws.isoformat(), "end": we.isoformat()} for ws, we in slots]


def _validate_address_stub(lat: float, lng: float, address: Optional[str]) -> dict:
    # Placeholder for real address validation (Mapbox/what3words/PTV)
    # For now, return same coords with medium confidence if address present.
    return {
        "validated_address": (address or "").strip() or None,
        "validated_lat": lat,
        "validated_lng": lng,
        "address_confidence": 0.6 if address else None,
    }


def _payload_hash(data: dict) -> str:
    try:
        import json
        return str(hash(json.dumps(data, sort_keys=True)))
    except Exception:
        return str(hash(str(data)))


def _notify_webhook(payload: dict) -> None:
    if not WEBHOOK_URL:
        return
    try:
        httpx.post(WEBHOOK_URL, json=payload, timeout=3)
    except Exception:
        return


def _geocode_mapbox(address: str) -> Optional[dict]:
    if not MAPBOX_TOKEN or not address:
        return None
    try:
        url = f"https://api.mapbox.com/geocoding/v5/mapbox.places/{address}.json"
        r = httpx.get(url, params={"access_token": MAPBOX_TOKEN, "limit": 1}, timeout=5)
        r.raise_for_status()
        j = r.json()
        feats = j.get("features") or []
        if not feats:
            return None
        f0 = feats[0]
        center = f0.get("center") or []
        if len(center) != 2:
            return None
        lng, lat = center[0], center[1]
        return {
            "validated_address": f0.get("place_name") or address,
            "validated_lat": lat,
            "validated_lng": lng,
            "address_confidence": f0.get("relevance") or 0.8,
        }
    except Exception:
        return None


def _geocode_w3w(address: str) -> Optional[dict]:
    if not WHAT3WORDS_TOKEN or not address:
        return None
    # Basic check for word.word.word pattern
    if address.count(".") != 2:
        return None
    try:
        url = "https://api.what3words.com/v3/convert-to-coordinates"
        r = httpx.get(url, params={"words": address, "key": WHAT3WORDS_TOKEN}, timeout=5)
        r.raise_for_status()
        j = r.json()
        coords = j.get("coordinates") or {}
        lat = coords.get("lat")
        lng = coords.get("lng")
        if lat is None or lng is None:
            return None
        return {
            "validated_address": j.get("nearestPlace") or address,
            "validated_lat": lat,
            "validated_lng": lng,
            "address_confidence": 0.7,
        }
    except Exception:
        return None


def _mapbox_directions(pickup: tuple[float, float], drop: tuple[float, float]) -> Optional[dict]:
    if not MAPBOX_TOKEN:
        return None
    try:
        plon, plat = pickup[1], pickup[0]
        dlon, dlat = drop[1], drop[0]
        url = f"https://api.mapbox.com/directions/v5/{MAPBOX_PROFILE}/{plon},{plat};{dlon},{dlat}"
        r = httpx.get(url, params={"access_token": MAPBOX_TOKEN, "geometries": "geojson", "overview": "simplified"}, timeout=5)
        r.raise_for_status()
        j = r.json()
        routes = j.get("routes") or []
        if not routes:
            return None
        r0 = routes[0]
        dist_km = float(r0.get("distance", 0) / 1000.0)
        dur_min = float(r0.get("duration", 0) / 60.0)
        return {"distance_km": dist_km, "duration_min": dur_min}
    except Exception:
        return None


def _ptv_directions(pickup: tuple[float, float], drop: tuple[float, float]) -> Optional[dict]:
    if not PTV_ROUTING_URL or not PTV_API_KEY:
        return None
    try:
        body = {
            "waypoints": [
                {"lat": pickup[0], "lon": pickup[1]},
                {"lat": drop[0], "lon": drop[1]},
            ],
            "options": {"vehicle": "BICYCLE"},
        }
        r = httpx.post(PTV_ROUTING_URL, json=body, params={"apiKey": PTV_API_KEY}, timeout=5)
        r.raise_for_status()
        j = r.json()
        routes = j.get("routes") or []
        if not routes:
            return None
        r0 = routes[0]
        dist_m = float(r0.get("distance", 0))
        dur_s = float(r0.get("duration", 0))
        return {"distance_km": dist_m / 1000.0, "duration_min": dur_s / 60.0}
    except Exception:
        return None


@router.post("/orders", response_model=OrderOut)
def create_order(req: OrderCreate, idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"), s: Session = Depends(get_session)):
    if not isinstance(idempotency_key, str):
        idempotency_key = None
    dist = _haversine(req.pickup_lat, req.pickup_lng, req.drop_lat, req.drop_lng)
    mb = _ptv_directions((req.pickup_lat, req.pickup_lng), (req.drop_lat, req.drop_lng))
    if not mb:
        mb = _mapbox_directions((req.pickup_lat, req.pickup_lng), (req.drop_lat, req.drop_lng))
    if mb:
        dist = mb["distance_km"]
    if dist > MAX_DISTANCE_KM:
        raise HTTPException(status_code=400, detail="distance exceeds service area")
    price = int(300 + dist * 100)
    eta_minutes = int(dist * 3 + 20)
    if mb:
        eta_minutes = max(15, int(mb["duration_min"] + 10))
    eta = datetime.utcnow() + timedelta(minutes=eta_minutes)
    # basic slotting: same_day -> next 1-3h; next_day -> tomorrow evening 16-21
    now = datetime.utcnow()
    service_type = req.service_type
    if service_type == "same_day":
        cutoff_passed = (now.hour > SAME_DAY_CUTOFF_HOUR) or (now.hour == SAME_DAY_CUTOFF_HOUR and now.minute > SAME_DAY_CUTOFF_MINUTE)
        if cutoff_passed:
            service_type = "next_day"
    chosen_ws = req.window_start
    chosen_we = req.window_end
    if chosen_ws and chosen_we:
        _validate_window(chosen_ws, chosen_we)
        if chosen_ws < now:
            raise HTTPException(status_code=400, detail="window must be in the future")
        ws, we = chosen_ws, chosen_we
    elif service_type == "asap":
        ws = now + timedelta(minutes=30)
        we = now + timedelta(minutes=90)
    elif service_type == "same_day":
        ws = now + timedelta(hours=2)
        we = now + timedelta(hours=3)
    else:
        tomorrow = now + timedelta(days=1)
        ws = tomorrow.replace(hour=16, minute=0, second=0, microsecond=0)
        we = tomorrow.replace(hour=21, minute=0, second=0, microsecond=0)
    sla_due = we
    pin = f"{random.randint(0, 9999):04d}"
    oid = str(uuid.uuid4())
    co2 = int(round(dist * EMISSION_G_PER_KM))
    payload = req.model_dump()
    payload_hash = _payload_hash(payload)
    if idempotency_key:
        ie = s.get(CourierIdempotency, idempotency_key)
        if ie:
            if ie.endpoint and ie.endpoint != "orders/create":
                raise HTTPException(status_code=409, detail="Idempotency-Key reused for different endpoint")
            if ie.payload_hash and ie.payload_hash != payload_hash:
                raise HTTPException(status_code=409, detail="Idempotency-Key reused with different payload")
            if ie.order_id:
                existing = s.get(Order, ie.order_id)
                if existing:
                    return existing
    addr = _geocode_mapbox(req.drop_address or "") if req.drop_address else None
    if not addr and req.drop_address:
        addr = _geocode_w3w(req.drop_address)
    if not addr:
        addr = _validate_address_stub(req.drop_lat, req.drop_lng, req.drop_address)
    od = Order(
        id=oid,
        tracking_token=str(uuid.uuid4()),
        pickup_lat=req.pickup_lat,
        pickup_lng=req.pickup_lng,
        drop_lat=req.drop_lat,
        drop_lng=req.drop_lng,
        customer_name=req.customer_name,
        customer_phone=req.customer_phone,
        drop_address=(req.drop_address or None),
        distance_km=dist,
        price_cents=price,
        currency=req.currency,
        eta_ts=eta,
        service_type=service_type,
        window_start=ws,
        window_end=we,
        instructions=(req.instructions or None),
        pin_code=pin,
        co2_grams=co2,
        hub_id=req.hub_id or None,
        sla_due_at=sla_due,
        on_promise=_on_promise(we),
        carrier=req.carrier or None,
        vehicle_type=req.vehicle_type or None,
        aftership_tracking=req.aftership_tracking or None,
        apomap_id=req.apomap_id or None,
        partner_id=req.partner_id or None,
        validated_address=addr.get("validated_address"),
        validated_lat=addr.get("validated_lat"),
        validated_lng=addr.get("validated_lng"),
        address_confidence=addr.get("address_confidence"),
    )
    s.add(od)
    s.add(Event(order_id=oid, status="created", note=None))
    if req.auto_dispatch:
        _try_auto_dispatch(s, od)
    s.commit(); s.refresh(od)
    if idempotency_key:
        try:
            ie = s.get(CourierIdempotency, idempotency_key)
            if not ie:
                ie = CourierIdempotency(key=idempotency_key, endpoint="orders/create", order_id=oid, payload_hash=payload_hash)
            else:
                ie.endpoint = ie.endpoint or "orders/create"
                ie.order_id = ie.order_id or oid
                ie.payload_hash = ie.payload_hash or payload_hash
            s.add(ie); s.commit()
        except Exception:
            pass
    _notify_webhook({"event": "order_created", "order_id": od.id, "status": od.status, "service_type": od.service_type})
    return od


class StatusUpdate(BaseModel):
    status: str = Field(examples=["assigned", "pickup", "delivering", "delivered", "failed"])
    note: Optional[str] = None
    driver_lat: Optional[float] = None
    driver_lng: Optional[float] = None
    proof_url: Optional[str] = None
    barcode: Optional[str] = None
    pin: Optional[str] = None
    hub_id: Optional[str] = None
    validated_address: Optional[str] = None
    address_confidence: Optional[float] = Field(default=None, ge=0.0, le=1.0)
    vehicle_type: Optional[str] = None
    aftership_tracking: Optional[str] = None
    apomap_id: Optional[str] = None
    window_start: Optional[datetime] = None
    window_end: Optional[datetime] = None
    short_term_storage: Optional[bool] = None
    scanned_barcode: Optional[str] = None
    signature: Optional[str] = None
    pod_photo_url: Optional[str] = None


@router.post("/orders/{oid}/status", response_model=OrderOut)
def update_status(oid: str, req: StatusUpdate, s: Session = Depends(get_session)):
    od = s.get(Order, oid)
    if not od:
        raise HTTPException(status_code=404, detail="not found")
    # enforce PIN for delivery handover
    if req.status == "delivered":
        if not req.pin or req.pin != (od.pin_code or ""):
            raise HTTPException(status_code=403, detail="invalid pin")
        od.delivered_at = datetime.utcnow()
        if req.hub_id:
            od.hub_id = req.hub_id
        if req.vehicle_type:
            od.vehicle_type = req.vehicle_type
        if req.aftership_tracking:
            od.aftership_tracking = req.aftership_tracking
        if req.apomap_id:
            od.apomap_id = req.apomap_id
        _bump_sla_on_promise(od)
    if req.window_start and req.window_end:
        _validate_window(req.window_start, req.window_end)
        now = datetime.utcnow()
        if req.window_start < now:
            raise HTTPException(status_code=400, detail="window must be in the future")
        od.window_start = req.window_start
        od.window_end = req.window_end
        if req.short_term_storage is not None:
            od.short_term_storage = bool(req.short_term_storage)
    if req.status == "failed":
        od.failed_attempts = int(od.failed_attempts or 0) + 1
        if od.failed_attempts == 1:
            # schedule second attempt next day evening
            tomorrow = datetime.utcnow() + timedelta(days=1)
            od.retry_window_start = tomorrow.replace(hour=16, minute=0, second=0, microsecond=0)
            od.retry_window_end = tomorrow.replace(hour=21, minute=0, second=0, microsecond=0)
            od.status = "retry"
            s.add(Event(order_id=oid, status="retry", note="second attempt scheduled"))
            s.commit()
            s.refresh(od)
            return od
        if od.failed_attempts >= 2:
            od.return_required = True
            od.status = "return"
            s.add(Event(order_id=oid, status="return", note=req.note))
            s.commit()
            s.refresh(od)
            return od
    od.status = req.status
    if req.status == "delivered":
        od.eta_ts = datetime.utcnow()
    if req.driver_lat is not None and req.driver_lng is not None and od.driver_id:
        d = s.get(Driver, od.driver_id)
        if d:
            d.lat = req.driver_lat
            d.lng = req.driver_lng
            d.status = "busy" if req.status in ("pickup", "delivering") else d.status
            d.updated_at = datetime.utcnow()
            queue_broadcast({"type": "driver_location", "id": d.id, "lat": d.lat, "lng": d.lng, "status": d.status})
    if req.validated_address:
        od.validated_address = req.validated_address
        if req.address_confidence is not None:
            od.address_confidence = req.address_confidence
        if req.driver_lat is not None and req.driver_lng is not None:
            od.validated_lat = req.driver_lat
            od.validated_lng = req.driver_lng
    if req.scanned_barcode:
        od.last_scan_code = req.scanned_barcode
    if req.vehicle_type:
        od.vehicle_type = req.vehicle_type
    if req.aftership_tracking:
        od.aftership_tracking = req.aftership_tracking
    if req.apomap_id:
        od.apomap_id = req.apomap_id
    _bump_sla_on_promise(od)
    s.add(Event(order_id=oid, status=req.status, note=req.note, proof_url=req.proof_url or req.pod_photo_url, barcode=req.barcode, signature=req.signature))
    queue_broadcast({"type": "order_status", "id": od.id, "status": od.status})
    s.commit(); s.refresh(od)
    _notify_webhook({
        "event": "order_status",
        "order_id": od.id,
        "status": od.status,
        "proof_url": req.proof_url,
        "barcode": req.barcode or req.scanned_barcode,
        "signature": req.signature,
        "window_start": od.window_start.isoformat() if od.window_start else None,
        "window_end": od.window_end.isoformat() if od.window_end else None,
        "driver_id": od.driver_id,
        "validated_lat": od.validated_lat,
        "validated_lng": od.validated_lng,
        "co2_grams": od.co2_grams,
        "pod_photo_url": req.pod_photo_url,
    })
    return od


class DriverCreate(BaseModel):
    name: str
    phone: str
    lat: float = 0.0
    lng: float = 0.0


class DriverOut(BaseModel):
    id: int
    name: str
    phone: str
    status: str
    lat: float
    lng: float
    updated_at: datetime
    battery_pct: Optional[int] = None
    model_config = {"from_attributes": True}


@router.post("/drivers", response_model=DriverOut)
def create_driver(req: DriverCreate, s: Session = Depends(get_session)):
    d = Driver(name=req.name, phone=req.phone, lat=req.lat, lng=req.lng)
    s.add(d); s.commit(); s.refresh(d)
    return d


@router.get("/drivers", response_model=List[DriverOut])
def list_drivers(status: str = "", s: Session = Depends(get_session)):
    stmt = select(Driver)
    if status:
        stmt = stmt.where(Driver.status == status)
    return s.execute(stmt).scalars().all()


@router.post("/drivers/{did}/location", response_model=DriverOut)
def update_driver_location(did: int, req: DriverLocation, s: Session = Depends(get_session)):
    d = s.get(Driver, did)
    if not d:
        raise HTTPException(status_code=404, detail="not found")
    d.lat = req.lat
    d.lng = req.lng
    d.status = req.status
    if req.battery_pct is not None:
        d.battery_pct = max(0, min(100, int(req.battery_pct)))
    d.updated_at = datetime.utcnow()
    s.commit(); s.refresh(d)
    queue_broadcast({"type": "driver_location", "id": d.id, "lat": d.lat, "lng": d.lng, "status": d.status, "battery_pct": d.battery_pct})
    return d


class AssignReq(BaseModel):
    driver_id: int


@router.post("/orders/{oid}/assign", response_model=OrderOut)
def assign_order(oid: str, req: AssignReq, s: Session = Depends(get_session)):
    od = s.get(Order, oid)
    if not od:
        raise HTTPException(status_code=404, detail="not found")
    dr = s.get(Driver, req.driver_id)
    if not dr:
        raise HTTPException(status_code=404, detail="driver not found")
    od.driver_id = dr.id
    od.status = "assigned"
    s.add(Event(order_id=oid, status="assigned", note=f"driver {dr.id}"))
    dr.status = "busy"
    s.commit(); s.refresh(od)
    return od


def _try_auto_dispatch(s: Session, od: Order):
    drivers = s.execute(select(Driver).where(Driver.status == "idle")).scalars().all()
    if not drivers:
        return
    best = None
    best_dist = 1e9
    vt_pref = (od.vehicle_type or "").strip()
    for d in drivers:
        if MIN_DRIVER_BATTERY and d.battery_pct is not None and d.battery_pct < MIN_DRIVER_BATTERY:
            continue
        if vt_pref and (d.vehicle_class or "").strip() and (d.vehicle_class or "").strip() != vt_pref:
            continue
        dkm = _haversine(d.lat, d.lng, od.pickup_lat, od.pickup_lng)
        if dkm < best_dist:
            best_dist = dkm
            best = d
    if best:
        od.driver_id = best.id
        od.status = "assigned"
        s.add(Event(order_id=od.id, status="assigned", note=f"auto driver {best.id}"))
        best.status = "busy"


@router.get("/orders", response_model=List[OrderOut])
def list_orders(status: str = "", limit: int = 50, s: Session = Depends(get_session)):
    stmt = select(Order)
    if status:
        stmt = stmt.where(Order.status == status)
    stmt = stmt.order_by(Order.created_at.desc()).limit(max(1, min(limit, 200)))
    return s.execute(stmt).scalars().all()


class StatsOut(BaseModel):
    total: int
    delivered: int
    on_promise: int
    on_promise_rate: float
    return_required: int
    avg_distance_km: float
    avg_co2_grams: float
    avg_driver_battery: Optional[float] = None
    service_type: Optional[str] = None
    carrier: Optional[str] = None
    partner_id: Optional[str] = None
    total_co2_grams: Optional[int] = None
    slots: Optional[Dict[str, float]] = None  # slot label -> on_promise_rate


class PartnerKPI(BaseModel):
    partner_id: Optional[str]
    total: int
    delivered: int
    on_promise: int
    on_promise_rate: float
    return_required: int
    carrier: Optional[str] = None
    service_type: Optional[str] = None


class ContactReq(BaseModel):
    message: str = Field(min_length=1, max_length=512)


class RescheduleReq(BaseModel):
    window_start: datetime
    window_end: datetime
    short_term_storage: Optional[bool] = None


class TrackOut(BaseModel):
    id: str
    tracking_token: str
    status: str
    eta_ts: Optional[datetime]
    events: List[dict]
    driver_lat: Optional[float] = None
    driver_lng: Optional[float] = None
    driver_status: Optional[str] = None
    window_start: Optional[datetime] = None
    window_end: Optional[datetime] = None
    instructions: Optional[str] = None
    failed_attempts: int = 0
    return_required: bool = False
    delivered_at: Optional[datetime] = None
    pin_code: Optional[str] = None
    co2_grams: Optional[int] = None
    retry_window_start: Optional[datetime] = None
    retry_window_end: Optional[datetime] = None
    driver_name: Optional[str] = None
    driver_phone: Optional[str] = None
    drop_address: Optional[str] = None
    validated_address: Optional[str] = None
    validated_lat: Optional[float] = None
    validated_lng: Optional[float] = None
    address_confidence: Optional[float] = None
    hub_id: Optional[str] = None
    short_term_storage: bool = False
    sla_due_at: Optional[datetime] = None
    on_promise: bool = True
    carrier: Optional[str] = None
    vehicle_type: Optional[str] = None
    aftership_tracking: Optional[str] = None
    apomap_id: Optional[str] = None
    partner_id: Optional[str] = None
    last_scan_code: Optional[str] = None
    bff_tracking_url: Optional[str] = None
    partner_name: Optional[str] = None
    partner_brand_text: Optional[str] = None
    partner_logo_url: Optional[str] = None
    partner_id: Optional[str] = None
    last_scan_code: Optional[str] = None


@router.get("/track/{oid}", response_model=TrackOut)
def track(oid: str, s: Session = Depends(get_session)):
    od = s.get(Order, oid)
    if not od:
        raise HTTPException(status_code=404, detail="not found")
    ev = s.execute(select(Event).where(Event.order_id == oid).order_by(Event.created_at.asc())).scalars().all()
    _bump_sla_on_promise(od)
    s.add(od); s.commit(); s.refresh(od)
    drv = s.get(Driver, od.driver_id) if od.driver_id else None
    partner = s.get(Partner, od.partner_id) if od.partner_id else None
    return TrackOut(
        id=od.id,
        tracking_token=od.tracking_token,
        status=od.status,
        eta_ts=od.eta_ts,
        events=[{"status": e.status, "note": e.note, "created_at": e.created_at, "proof_url": e.proof_url, "barcode": e.barcode} for e in ev],
        driver_lat=drv.lat if drv else None,
        driver_lng=drv.lng if drv else None,
        driver_status=drv.status if drv else None,
        driver_name=drv.name if drv else None,
        driver_phone=drv.phone if drv else None,
        window_start=od.window_start,
        window_end=od.window_end,
        instructions=od.instructions,
        failed_attempts=od.failed_attempts,
        return_required=od.return_required,
        delivered_at=od.delivered_at,
        pin_code=od.pin_code,
        co2_grams=od.co2_grams,
        retry_window_start=od.retry_window_start,
        retry_window_end=od.retry_window_end,
        drop_address=od.drop_address,
        validated_address=od.validated_address,
        validated_lat=od.validated_lat,
        validated_lng=od.validated_lng,
        address_confidence=od.address_confidence,
        hub_id=od.hub_id,
        short_term_storage=od.short_term_storage,
        sla_due_at=od.sla_due_at,
        on_promise=_on_promise(od.window_end),
        carrier=od.carrier,
        vehicle_type=od.vehicle_type,
        aftership_tracking=od.aftership_tracking,
        apomap_id=od.apomap_id,
        partner_id=od.partner_id,
        last_scan_code=od.last_scan_code,
        bff_tracking_url=(f"{BFF_BASE_URL.rstrip('/')}/courier/track/{od.tracking_token}" if BFF_BASE_URL else None),
        partner_name=partner.name if partner else None,
        partner_brand_text=partner.brand_text if partner else None,
        partner_logo_url=partner.logo_url if partner else None,
    )


@router.get("/track/public/{token}", response_model=TrackOut)
def track_public(token: str, s: Session = Depends(get_session)):
    od = s.execute(select(Order).where(Order.tracking_token == token)).scalars().first()
    if not od:
        raise HTTPException(status_code=404, detail="not found")
    ev = s.execute(select(Event).where(Event.order_id == od.id).order_by(Event.created_at.asc())).scalars().all()
    _bump_sla_on_promise(od)
    s.add(od); s.commit(); s.refresh(od)
    drv = s.get(Driver, od.driver_id) if od.driver_id else None
    partner = s.get(Partner, od.partner_id) if od.partner_id else None
    # Mask PIN in public view
    return TrackOut(
        id=od.id,
        tracking_token=od.tracking_token,
        status=od.status,
        eta_ts=od.eta_ts,
        events=[{"status": e.status, "note": e.note, "created_at": e.created_at, "proof_url": e.proof_url, "barcode": e.barcode} for e in ev],
        driver_lat=drv.lat if drv else None,
        driver_lng=drv.lng if drv else None,
        driver_status=drv.status if drv else None,
        driver_name=drv.name if drv else None,
        driver_phone=None,
        window_start=od.window_start,
        window_end=od.window_end,
        instructions=od.instructions,
        failed_attempts=od.failed_attempts,
        return_required=od.return_required,
        delivered_at=od.delivered_at,
        pin_code=None,
        co2_grams=od.co2_grams,
        retry_window_start=od.retry_window_start,
        retry_window_end=od.retry_window_end,
        drop_address=od.drop_address,
        validated_address=od.validated_address,
        validated_lat=od.validated_lat,
        validated_lng=od.validated_lng,
        address_confidence=od.address_confidence,
        hub_id=od.hub_id,
        short_term_storage=od.short_term_storage,
        sla_due_at=od.sla_due_at,
        on_promise=od.on_promise,
        carrier=od.carrier,
        vehicle_type=od.vehicle_type,
        aftership_tracking=od.aftership_tracking,
        apomap_id=od.apomap_id,
        partner_id=od.partner_id,
        last_scan_code=od.last_scan_code,
        bff_tracking_url=(f"{BFF_BASE_URL.rstrip('/')}/courier/track/{od.tracking_token}" if BFF_BASE_URL else None),
        partner_name=partner.name if partner else None,
        partner_brand_text=partner.brand_text if partner else None,
        partner_logo_url=partner.logo_url if partner else None,
    )


@router.get("/stats", response_model=StatsOut)
def stats(carrier: Optional[str] = None, partner_id: Optional[str] = None, service_type: Optional[str] = None, request: Any = None, s: Session = Depends(get_session)):
    _require_admin(request if isinstance(request, Request) else None)
    qry = select(Order)
    if carrier:
        qry = qry.where(Order.carrier == carrier)
    if partner_id:
        qry = qry.where(Order.partner_id == partner_id)
    if service_type:
        qry = qry.where(Order.service_type == service_type)
    orders = s.execute(qry).scalars().all()
    total = len(orders)
    delivered = sum(1 for o in orders if o.status == "delivered")
    on_promise = sum(1 for o in orders if o.on_promise)
    returns = sum(1 for o in orders if o.return_required)
    avg_dist = float(sum(o.distance_km or 0.0 for o in orders) / total) if total else 0.0
    co2_sum = float(sum(o.co2_grams or 0 for o in orders))
    avg_co2 = float(co2_sum / total) if total else 0.0
    avg_batt = s.execute(select(func.avg(Driver.battery_pct))).scalar()
    rate = float(on_promise) / float(total) if total else 0.0
    # Slot-level on-promise (by window_start hour)
    slot_rates: Dict[str, float] = {}
    slot_counts: Dict[str, int] = {}
    for o in orders:
        if o.window_start:
            label = o.window_start.strftime("%H:00")
            slot_counts[label] = slot_counts.get(label, 0) + 1
            if o.on_promise:
                slot_rates[label] = slot_rates.get(label, 0) + 1
    slot_out: Dict[str, float] = {}
    for k, v in slot_rates.items():
        total_slot = float(slot_counts.get(k, 1))
        slot_out[k] = float(v) / total_slot if total_slot else 0.0
    return StatsOut(
        total=int(total),
        delivered=int(delivered),
        on_promise=int(on_promise),
        on_promise_rate=rate,
        return_required=int(returns),
        avg_distance_km=float(avg_dist),
        avg_co2_grams=float(avg_co2),
        avg_driver_battery=float(avg_batt) if avg_batt is not None else None,
        total_co2_grams=int(co2_sum) if orders else None,
        carrier=carrier,
        partner_id=partner_id,
        service_type=service_type,
        slots=slot_out or None,
    )


@router.get("/stats/export")
def stats_export(carrier: Optional[str] = None, partner_id: Optional[str] = None, service_type: Optional[str] = None, request: Any = None, s: Session = Depends(get_session)):
    st = stats(carrier=carrier, partner_id=partner_id, service_type=service_type, request=request, s=s)
    buf = StringIO()
    w = csv.writer(buf)
    w.writerow(["total", "delivered", "on_promise", "on_promise_rate", "return_required", "avg_distance_km", "avg_co2_grams", "total_co2_grams", "avg_driver_battery"])
    w.writerow([st.total, st.delivered, st.on_promise, st.on_promise_rate, st.return_required, st.avg_distance_km, st.avg_co2_grams, st.total_co2_grams, st.avg_driver_battery])
    if st.slots:
        w.writerow([])
        w.writerow(["slot", "on_promise_rate"])
        for k, v in st.slots.items():
            w.writerow([k, v])
    buf.seek(0)
    return StreamingResponse(buf, media_type="text/csv", headers={"Content-Disposition": "attachment; filename=stats.csv"})


@router.get("/kpis/partners", response_model=List[PartnerKPI])
def kpis_partners(start_iso: Optional[str] = None, end_iso: Optional[str] = None, carrier: Optional[str] = None, service_type: Optional[str] = None, request: Any = None, s: Session = Depends(get_session)):
    _require_admin(request if isinstance(request, Request) else None)
    start_ts = datetime.fromisoformat(start_iso) if start_iso else None
    end_ts = datetime.fromisoformat(end_iso) if end_iso else None
    qry = select(Order)
    if carrier:
        qry = qry.where(Order.carrier == carrier)
    if service_type:
        qry = qry.where(Order.service_type == service_type)
    if start_ts:
        qry = qry.where(Order.window_start >= start_ts)
    if end_ts:
        qry = qry.where(Order.window_end <= end_ts)
    orders = s.execute(qry).scalars().all()
    buckets: dict[Optional[str], dict[str, float]] = {}
    for od in orders:
        pid = od.partner_id
        if pid not in buckets:
            buckets[pid] = {"total": 0, "delivered": 0, "on_promise": 0, "return_required": 0}
        buckets[pid]["total"] += 1
        if od.status == "delivered":
            buckets[pid]["delivered"] += 1
        if od.on_promise:
            buckets[pid]["on_promise"] += 1
        if od.return_required:
            buckets[pid]["return_required"] += 1
    out: list[PartnerKPI] = []
    for pid, vals in buckets.items():
        total = int(vals["total"])
        on_promise = int(vals["on_promise"])
        rate = float(on_promise) / float(total) if total else 0.0
        out.append(
            PartnerKPI(
                partner_id=pid,
                total=total,
                delivered=int(vals["delivered"]),
                on_promise=on_promise,
                on_promise_rate=rate,
                return_required=int(vals["return_required"]),
                carrier=carrier,
                service_type=service_type,
        )
        )
    return out


@router.get("/kpis/partners/export")
def export_partner_kpis(start_iso: Optional[str] = None, end_iso: Optional[str] = None, carrier: Optional[str] = None, service_type: Optional[str] = None, request: Any = None, s: Session = Depends(get_session)):
    rows = kpis_partners(start_iso=start_iso, end_iso=end_iso, carrier=carrier, service_type=service_type, request=request, s=s)
    buf = StringIO()
    w = csv.writer(buf)
    w.writerow(["partner_id", "total", "delivered", "on_promise", "on_promise_rate", "return_required", "carrier", "service_type"])
    for r in rows:
        w.writerow([r.partner_id, r.total, r.delivered, r.on_promise, r.on_promise_rate, r.return_required, r.carrier, r.service_type])
    buf.seek(0)
    return StreamingResponse(buf, media_type="text/csv", headers={"Content-Disposition": "attachment; filename=partner_kpis.csv"})


app.include_router(router, prefix="/courier")
app.include_router(router_ws)


@router.post("/orders/{oid}/contact", response_model=OrderOut)
def contact_support(oid: str, req: ContactReq, s: Session = Depends(get_session)):
    od = s.get(Order, oid)
    if not od:
        raise HTTPException(status_code=404, detail="not found")
    s.add(Event(order_id=oid, status="contact", note=req.message))
    s.commit(); s.refresh(od)
    _notify_webhook({"event": "contact", "order_id": od.id, "message": req.message})
    return od


@router.post("/orders/{oid}/reschedule", response_model=OrderOut)
def reschedule_order(oid: str, req: RescheduleReq, s: Session = Depends(get_session)):
    od = s.get(Order, oid)
    if not od:
        raise HTTPException(status_code=404, detail="not found")
    if od.status in ("delivered", "return"):
        raise HTTPException(status_code=400, detail="cannot reschedule finished order")
    _validate_window(req.window_start, req.window_end)
    if req.window_start < datetime.utcnow():
        raise HTTPException(status_code=400, detail="window must be in the future")
    od.window_start = req.window_start
    od.window_end = req.window_end
    if req.short_term_storage is not None:
        od.short_term_storage = bool(req.short_term_storage)
    _bump_sla_on_promise(od)
    s.add(Event(order_id=oid, status="rescheduled", note=f"{req.window_start.isoformat()}->{req.window_end.isoformat()}"))
    s.commit(); s.refresh(od)
    _notify_webhook({
        "event": "rescheduled",
        "order_id": od.id,
        "window_start": od.window_start.isoformat() if od.window_start else None,
        "window_end": od.window_end.isoformat() if od.window_end else None,
        "short_term_storage": od.short_term_storage,
    })
    return od


@router.get("/address/validate")
def validate_address(lat: float, lng: float, address: Optional[str] = None):
    addr = _geocode_mapbox(address or "") if address else None
    if not addr and address:
        addr = _geocode_w3w(address)
    if addr:
        return addr
    return _validate_address_stub(lat, lng, address)


@router.get("/slots")
def available_slots(service_type: str = "same_day"):
    return {"service_type": service_type, "slots": _available_slots(service_type)}


@router.post("/partners", response_model=PartnerOut)
def create_partner(body: PartnerIn, s: Session = Depends(get_session)):
    pid = body.id or str(uuid.uuid4())
    p = Partner(
        id=pid,
        name=body.name,
        brand_text=body.brand_text,
        logo_url=body.logo_url,
        carrier=body.carrier,
        contact_email=body.contact_email,
    )
    s.add(p); s.commit(); s.refresh(p)
    return p


@router.get("/partners", response_model=List[PartnerOut])
def list_partners(s: Session = Depends(get_session)):
    return s.execute(select(Partner)).scalars().all()


@router.post("/apply", response_model=CourierApplicationOut)
def courier_apply(body: CourierApply, s: Session = Depends(get_session)):
    app_id = str(uuid.uuid4())
    app = CourierApplication(
        id=app_id,
        name=body.name,
        phone=body.phone,
        city=body.city,
        vehicle_type=body.vehicle_type,
        experience_years=body.experience_years,
        note=body.note,
        status="pending",
    )
    s.add(app); s.commit(); s.refresh(app)
    return app


@router.get("/admin/applications", response_model=List[CourierApplicationOut])
def list_courier_applications(status: str = "", request: Any = None, s: Session = Depends(get_session)):
    _require_admin(request if isinstance(request, Request) else None)
    qry = select(CourierApplication)
    if status:
        qry = qry.where(CourierApplication.status == status)
    qry = qry.order_by(CourierApplication.created_at.desc()).limit(200)
    return s.execute(qry).scalars().all()
