from fastapi import FastAPI, HTTPException, Depends, Request, Header, APIRouter
from pydantic import BaseModel, Field
from typing import Optional, List
import os, math, uuid, time, logging
from shamell_shared import RequestIDMiddleware, configure_cors, add_standard_health, setup_json_logging
from sqlalchemy import create_engine, String, Integer, BigInteger, DateTime, Float, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, Session
from sqlalchemy import select
from datetime import datetime
import httpx


def _env_or(key: str, default: str) -> str:
    v = os.getenv(key)
    return v if v is not None else default


app = FastAPI(title="Freight API", version="0.1.0")
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", "*"))
add_standard_health(app)

_freight_audit_logger = logging.getLogger("shamell.audit")

router = APIRouter()


DB_URL = _env_or("DB_URL", "sqlite+pysqlite:////tmp/freight.db")
DB_SCHEMA = os.getenv("DB_SCHEMA") if not DB_URL.startswith("sqlite") else None
PAYMENTS_BASE = _env_or("PAYMENTS_BASE_URL", "")
FARE_PER_KM_CENTS = float(_env_or("FREIGHT_FARE_PER_KM_CENTS", "500"))
FARE_PER_KG_CENTS = float(_env_or("FREIGHT_FARE_PER_KG_CENTS", "20"))
MIN_FARE_CENTS = int(_env_or("FREIGHT_MIN_FARE_CENTS", "10000"))

# In-memory guardrails for freight/courier payments (best-effort).
_FREIGHT_VELOCITY_PAYER: dict[str, list[float]] = {}
_FREIGHT_VELOCITY_DEVICE: dict[str, list[float]] = {}
FREIGHT_VELOCITY_WINDOW_SECS = int(_env_or("FREIGHT_VELOCITY_WINDOW_SECS", "60"))
FREIGHT_VELOCITY_MAX_PER_PAYER = int(_env_or("FREIGHT_VELOCITY_MAX_PER_PAYER", "20"))
FREIGHT_VELOCITY_MAX_PER_DEVICE = int(_env_or("FREIGHT_VELOCITY_MAX_PER_DEVICE", "40"))
FREIGHT_MAX_PER_SHIPMENT_CENTS = int(_env_or("FREIGHT_MAX_PER_SHIPMENT_CENTS", "0"))  # 0 = disabled
FREIGHT_MAX_DISTANCE_KM = float(_env_or("FREIGHT_MAX_DISTANCE_KM", "0"))  # 0 = disabled
FREIGHT_MAX_WEIGHT_KG = float(_env_or("FREIGHT_MAX_WEIGHT_KG", "0"))  # 0 = disabled


def _freight_audit(action: str, **extra: object) -> None:
    """
    Lightweight audit logger for Freight/Courier guardrails.
    Writes structured entries into the JSON log stream.
    """
    try:
        payload: dict[str, object] = {
            "event": "audit",
            "domain": "freight",
            "action": action,
            "ts_ms": int(time.time() * 1000),
        }
        for k, v in extra.items():
            if v is not None:
                payload[k] = v
        _freight_audit_logger.info(payload)
    except Exception:
        # Audit must never break normal flows
        pass


class Base(DeclarativeBase):
    pass


class Shipment(Base):
    __tablename__ = "shipments"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    title: Mapped[str] = mapped_column(String(200))
    from_lat: Mapped[float] = mapped_column(Float)
    from_lon: Mapped[float] = mapped_column(Float)
    to_lat: Mapped[float] = mapped_column(Float)
    to_lon: Mapped[float] = mapped_column(Float)
    weight_kg: Mapped[float] = mapped_column(Float)
    distance_km: Mapped[float] = mapped_column(Float)
    amount_cents: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), default="SYP")
    payer_wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    carrier_wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    status: Mapped[str] = mapped_column(String(16), default="requested")  # requested|booked|in_transit|delivered|canceled
    payments_txn_id: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Idempotency(Base):
    __tablename__ = "idempotency"
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

app.router.on_startup.append(_startup)


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat/2)**2 + math.cos(math.radians(lat1))*math.cos(math.radians(lat2))*math.sin(dlon/2)**2
    c = 2*math.atan2(math.sqrt(a), math.sqrt(1-a))
    return r * c


class QuoteReq(BaseModel):
    title: str
    from_lat: float
    from_lon: float
    to_lat: float
    to_lon: float
    weight_kg: float = Field(gt=0)


class QuoteOut(BaseModel):
    distance_km: float
    amount_cents: int
    currency: str


@router.post("/quote", response_model=QuoteOut)
def quote(req: QuoteReq):
    km = _haversine_km(req.from_lat, req.from_lon, req.to_lat, req.to_lon)
    amt = int(round(max(MIN_FARE_CENTS, FARE_PER_KM_CENTS*km + FARE_PER_KG_CENTS*req.weight_kg)))
    return QuoteOut(distance_km=round(km,2), amount_cents=amt, currency="SYP")


class BookReq(QuoteReq):
    payer_wallet_id: Optional[str] = None
    carrier_wallet_id: Optional[str] = None
    confirm: bool = False


class ShipmentOut(BaseModel):
    id: str
    title: str
    distance_km: float
    amount_cents: int
    status: str
    payments_txn_id: Optional[str]


def _freight_guardrails(
    payer_wallet_id: Optional[str],
    amount_cents: int,
    request: Optional[Request],
    distance_km: Optional[float] = None,
    weight_kg: Optional[float] = None,
) -> None:
    """
    Best-effort anti-fraud guardrails for Freight/Courier:
      - optional max amount per shipment
      - simple velocity limits per wallet and per device over a short window
    """
    try:
        now = time.time()
        amt = int(amount_cents or 0)
        pw = (payer_wallet_id or "").strip()

        dev: Optional[str] = None
        ip: Optional[str] = None
        try:
            if request is not None:
                dev = request.headers.get("X-Device-ID")
                if request.client and request.client.host:
                    ip = request.client.host
        except Exception:
            dev = dev or None
            ip = ip or None
        dev = (dev or "").strip()

        # Guardrail 0: optional caps for distance and weight
        if distance_km is not None and FREIGHT_MAX_DISTANCE_KM > 0 and distance_km > FREIGHT_MAX_DISTANCE_KM:
            _freight_audit(
                "freight_distance_guardrail_block",
                payer_wallet_id=pw or None,
                amount_cents=amt,
                distance_km=distance_km,
                device_id=dev or None,
                ip=ip,
            )
            raise HTTPException(status_code=403, detail="freight distance exceeds guardrail")
        if weight_kg is not None and FREIGHT_MAX_WEIGHT_KG > 0 and weight_kg > FREIGHT_MAX_WEIGHT_KG:
            _freight_audit(
                "freight_weight_guardrail_block",
                payer_wallet_id=pw or None,
                amount_cents=amt,
                weight_kg=weight_kg,
                device_id=dev or None,
                ip=ip,
            )
            raise HTTPException(status_code=403, detail="freight weight exceeds guardrail")

        # Guardrail 1: Maximalbetrag pro Shipment (wenn konfiguriert)
        if FREIGHT_MAX_PER_SHIPMENT_CENTS > 0 and amt > FREIGHT_MAX_PER_SHIPMENT_CENTS:
            _freight_audit(
                "freight_amount_guardrail_block",
                payer_wallet_id=pw or None,
                amount_cents=amt,
                distance_km=distance_km,
                weight_kg=weight_kg,
                device_id=dev or None,
                ip=ip,
            )
            raise HTTPException(status_code=403, detail="freight amount exceeds guardrail")

        window = max(1, FREIGHT_VELOCITY_WINDOW_SECS)

        # Guardrail 2: Velocity pro Wallet
        if pw:
            events = _FREIGHT_VELOCITY_PAYER.get(pw) or []
            events = [ts for ts in events if ts >= now - window]
            if len(events) >= max(1, FREIGHT_VELOCITY_MAX_PER_PAYER):
                _FREIGHT_VELOCITY_PAYER[pw] = events
                _freight_audit(
                    "freight_velocity_guardrail_payer_block",
                    payer_wallet_id=pw,
                    amount_cents=amt,
                    distance_km=distance_km,
                    weight_kg=weight_kg,
                    device_id=dev or None,
                    ip=ip,
                    window_secs=window,
                )
                raise HTTPException(status_code=429, detail="freight velocity guardrail (payer)")
            events.append(now)
            _FREIGHT_VELOCITY_PAYER[pw] = events

        # Guardrail 3: Velocity pro Device
        if dev:
            events_d = _FREIGHT_VELOCITY_DEVICE.get(dev) or []
            events_d = [ts for ts in events_d if ts >= now - window]
            if len(events_d) >= max(1, FREIGHT_VELOCITY_MAX_PER_DEVICE):
                _FREIGHT_VELOCITY_DEVICE[dev] = events_d
                _freight_audit(
                    "freight_velocity_guardrail_device_block",
                    payer_wallet_id=pw or None,
                    amount_cents=amt,
                    distance_km=distance_km,
                    weight_kg=weight_kg,
                    device_id=dev,
                    ip=ip,
                    window_secs=window,
                )
                raise HTTPException(status_code=429, detail="freight velocity guardrail (device)")
            events_d.append(now)
            _FREIGHT_VELOCITY_DEVICE[dev] = events_d
    except HTTPException:
        # Guardrail intentionally blocking request
        raise
    except Exception:
        # Guardrails must not hard-break regular flows
        return


def _pay(from_wallet: str, to_wallet: str, amount_cents: int, ikey: str, ref: str) -> dict:
    if not PAYMENTS_BASE: raise RuntimeError("PAYMENTS_BASE_URL not configured")
    url = PAYMENTS_BASE.rstrip('/') + '/transfer'
    headers = {"Content-Type": "application/json", "Idempotency-Key": ikey, "X-Merchant": "freight", "X-Ref": ref}
    r = httpx.post(url, json={"from_wallet_id": from_wallet, "to_wallet_id": to_wallet, "amount_cents": amount_cents}, headers=headers, timeout=10)
    r.raise_for_status(); return r.json()


@router.post("/book", response_model=ShipmentOut)
def book(request: Request, req: BookReq, idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"), s: Session = Depends(get_session)):
    km = _haversine_km(req.from_lat, req.from_lon, req.to_lat, req.to_lon)
    amt = int(round(max(MIN_FARE_CENTS, FARE_PER_KM_CENTS*km + FARE_PER_KG_CENTS*req.weight_kg)))
    if idempotency_key:
        ie = s.get(Idempotency, idempotency_key)
        if ie and ie.ref_id:
            sh0 = s.get(Shipment, ie.ref_id)
            if sh0:
                return ShipmentOut(id=sh0.id, title=sh0.title, distance_km=round(sh0.distance_km,2), amount_cents=sh0.amount_cents, status=sh0.status, payments_txn_id=sh0.payments_txn_id)
    sid = str(uuid.uuid4())
    status = "requested"
    txn = None
    if req.confirm and req.payer_wallet_id and req.carrier_wallet_id and amt > 0:
        _freight_guardrails(req.payer_wallet_id, amt, request, distance_km=km, weight_kg=req.weight_kg)
        resp = _pay(req.payer_wallet_id, req.carrier_wallet_id, amt, ikey=f"ship-{sid}", ref=f"ship-{sid}")
        txn = str(resp.get("id") or resp.get("txn_id") or "")
        status = "booked"
    sh = Shipment(id=sid, title=req.title.strip(), from_lat=req.from_lat, from_lon=req.from_lon, to_lat=req.to_lat, to_lon=req.to_lon, weight_kg=req.weight_kg, distance_km=km, amount_cents=amt, payer_wallet_id=(req.payer_wallet_id or None), carrier_wallet_id=(req.carrier_wallet_id or None), status=status, payments_txn_id=txn)
    s.add(sh); s.commit(); s.refresh(sh)
    if idempotency_key:
        try: s.add(Idempotency(key=idempotency_key, ref_id=sh.id)); s.commit()
        except Exception: pass
    return ShipmentOut(id=sh.id, title=sh.title, distance_km=round(sh.distance_km,2), amount_cents=sh.amount_cents, status=sh.status, payments_txn_id=sh.payments_txn_id)


@router.get("/shipments/{sid}", response_model=ShipmentOut)
def get_shipment(sid: str, s: Session = Depends(get_session)):
    sh = s.get(Shipment, sid)
    if not sh: raise HTTPException(status_code=404, detail="not found")
    return ShipmentOut(id=sh.id, title=sh.title, distance_km=round(sh.distance_km,2), amount_cents=sh.amount_cents, status=sh.status, payments_txn_id=sh.payments_txn_id)


class StatusReq(BaseModel):
    status: str


@router.post("/shipments/{sid}/status", response_model=ShipmentOut)
def set_status(sid: str, req: StatusReq, s: Session = Depends(get_session)):
    sh = s.get(Shipment, sid)
    if not sh: raise HTTPException(status_code=404, detail="not found")
    if req.status not in ("booked","in_transit","delivered","canceled"):
        raise HTTPException(status_code=400, detail="invalid status")
    sh.status = req.status
    s.add(sh); s.commit(); s.refresh(sh)
    return ShipmentOut(id=sh.id, title=sh.title, distance_km=round(sh.distance_km,2), amount_cents=sh.amount_cents, status=sh.status, payments_txn_id=sh.payments_txn_id)


app.include_router(router)
