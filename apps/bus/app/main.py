from fastapi import FastAPI, HTTPException, Depends, Header, APIRouter, Request
from pydantic import BaseModel, Field, ConfigDict
from typing import Optional, List
import os
import re
from shamell_shared import RequestIDMiddleware, configure_cors, add_standard_health, setup_json_logging
from starlette.middleware.trustedhost import TrustedHostMiddleware
from sqlalchemy import create_engine, String, Integer, BigInteger, DateTime, ForeignKey, func, select, text, inspect
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship, Session
from datetime import datetime, timezone, timedelta
import uuid
import httpx
import hashlib
import hmac

try:
    # Optional internal Payments integration (monolith mode). We keep this
    # import best-effort so that the standalone bus service does not depend
    # on the payments module being importable.
    from apps.payments.app.main import (  # type: ignore[import]
        Session as _PaySession,
        engine as _pay_engine,
        transfer as _pay_transfer,
        TransferReq as _PayTransferReq,
    )
    _PAY_INTERNAL_AVAILABLE = True
except Exception:
    _PaySession = None  # type: ignore[assignment]
    _pay_engine = None  # type: ignore[assignment]
    _pay_transfer = None  # type: ignore[assignment]
    _PayTransferReq = None  # type: ignore[assignment]
    _PAY_INTERNAL_AVAILABLE = False


def _env_or(key: str, default: str) -> str:
    v = os.getenv(key)
    return v if v is not None else default


DB_URL = _env_or("BUS_DB_URL", _env_or("DB_URL", "sqlite+pysqlite:////tmp/bus.db"))
DB_SCHEMA = os.getenv("DB_SCHEMA") if not DB_URL.startswith("sqlite") else None
PAYMENTS_BASE = _env_or("PAYMENTS_BASE_URL", "")
TICKET_SECRET = _env_or("BUS_TICKET_SECRET", "change-me-bus-ticket")
_ENV_LOWER = _env_or("ENV", "dev").lower()


def _enforce_ticket_secret_baseline() -> None:
    """
    Fail fast in non-dev/test environments when the ticket signing secret
    is left at the insecure default, to avoid accepting forged tickets.
    """
    if _ENV_LOWER not in ("dev", "test") and TICKET_SECRET == "change-me-bus-ticket":
        raise RuntimeError("BUS_TICKET_SECRET must be set in non-dev environments")


_enforce_ticket_secret_baseline()


def _use_pay_internal() -> bool:
    """
    Lightweight toggle for internal Payments usage from the Bus domain.
    We only treat internal mode as enabled when PAY_INTERNAL_MODE or
    PAYMENTS_INTERNAL_MODE is explicitly set to "on" (e.g. in the
    monolith), so that standalone bus deployments and tests keep their
    existing "offline" behaviour unless a PAYMENTS_BASE_URL is provided.
    """
    mode = (os.getenv("PAYMENTS_INTERNAL_MODE") or os.getenv("PAY_INTERNAL_MODE") or "").lower()
    if mode != "on":
        return False
    return bool(_PAY_INTERNAL_AVAILABLE and _PaySession and _pay_engine and _pay_transfer and _PayTransferReq)


def _city_code_for_trip_id(name: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9]", "", (name or "").strip())
    if not cleaned:
        return "CITY"
    return cleaned[:10].upper()


def _generate_trip_id(s: Session, route: "Route", depart_at: datetime) -> str:
    """
    Human-friendly trip ID:
      ORIGIN-DEST-YYYYMMDD-HHMM

    ID length is capped by the Trip.id column (String(36)), so the origin
    and destination codes are truncated to at most 10 characters each.
    If a collision occurs, a numeric suffix is appended; as a last resort
    we fall back to a UUID.
    """
    origin_city = s.get(City, route.origin_city_id)
    dest_city = s.get(City, route.dest_city_id)
    o = _city_code_for_trip_id(getattr(origin_city, "name", "") or "Origin")
    d = _city_code_for_trip_id(getattr(dest_city, "name", "") or "Dest")
    dep_utc = depart_at.astimezone(timezone.utc)
    base = f"{o}-{d}-{dep_utc.strftime('%Y%m%d')}-{dep_utc.strftime('%H%M')}"
    max_len = 36
    # Reserve space for potential "-NN" suffix when trimming base.
    base = base[: max_len - 3]
    trip_id = base
    n = 1
    while s.get(Trip, trip_id) is not None and n < 100:
        suffix = f"-{n}"
        trip_id = f"{base}{suffix}"
        if len(trip_id) > max_len:
            trip_id = trip_id[:max_len]
        n += 1
    if s.get(Trip, trip_id) is not None:
        trip_id = str(uuid.uuid4())
    return trip_id


class Base(DeclarativeBase):
    pass


class City(Base):
    __tablename__ = "cities"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    name: Mapped[str] = mapped_column(String(120), index=True)
    country: Mapped[Optional[str]] = mapped_column(String(64), default=None)


class Operator(Base):
    # Use a dedicated table name to avoid clashes with other domains
    # that may also define an "operators" table when running multiple
    # domains in the same database.
    __tablename__ = "bus_operators"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    name: Mapped[str] = mapped_column(String(120), unique=True, index=True)
    wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    is_online: Mapped[int] = mapped_column(Integer, default=0)  # 0|1 boolean


class Route(Base):
    __tablename__ = "routes"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    if DB_SCHEMA:
        origin_city_id: Mapped[str] = mapped_column(String(36), ForeignKey(f"{DB_SCHEMA}.cities.id"))
        dest_city_id: Mapped[str] = mapped_column(String(36), ForeignKey(f"{DB_SCHEMA}.cities.id"))
        operator_id: Mapped[str] = mapped_column(String(36), ForeignKey(f"{DB_SCHEMA}.bus_operators.id"))
    else:
        origin_city_id: Mapped[str] = mapped_column(String(36), ForeignKey("cities.id"))
        dest_city_id: Mapped[str] = mapped_column(String(36), ForeignKey("cities.id"))
        operator_id: Mapped[str] = mapped_column(String(36), ForeignKey("bus_operators.id"))
    bus_model: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    # Free-form description of amenities/features as entered by the
    # operator (e.g. "🌐 Wi‑Fi · ❄️ A/C").
    features: Mapped[Optional[str]] = mapped_column(String(1024), default=None)


class Trip(Base):
    __tablename__ = "trips"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    route_id: Mapped[str] = mapped_column(String(36))
    depart_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    arrive_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    price_cents: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), default="SYP")
    seats_total: Mapped[int] = mapped_column(Integer, default=40)
    seats_available: Mapped[int] = mapped_column(Integer, default=40)
    # draft|published|canceled (for now we use draft/published)
    status: Mapped[str] = mapped_column(String(16), default="draft")


class Booking(Base):
    __tablename__ = "bookings"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    trip_id: Mapped[str] = mapped_column(String(36))
    price_cents: Mapped[Optional[int]] = mapped_column(BigInteger, default=None)
    customer_phone: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    seats: Mapped[int] = mapped_column(Integer, default=1)
    status: Mapped[str] = mapped_column(String(16), default="pending")  # pending|confirmed|canceled|failed
    payments_txn_id: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Ticket(Base):
    __tablename__ = "tickets"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    booking_id: Mapped[str] = mapped_column(String(36))
    trip_id: Mapped[str] = mapped_column(String(36))
    seat_no: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    status: Mapped[str] = mapped_column(String(16), default="issued")  # pending|issued|boarded|canceled
    issued_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    boarded_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)


class Idempotency(Base):
    __tablename__ = "idempotency"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    key: Mapped[str] = mapped_column(String(120), primary_key=True)
    trip_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    seats: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    seat_numbers_hash: Mapped[Optional[str]] = mapped_column(String(128), default=None)
    booking_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), server_default=func.now())


if DB_URL.startswith("sqlite"):
    engine = create_engine(DB_URL, pool_pre_ping=True, connect_args={"check_same_thread": False})
else:
    engine = create_engine(DB_URL, pool_pre_ping=True)


def get_session():
    with Session(engine) as s:
        yield s


# Never expose interactive API docs by default in prod.
_ENABLE_DOCS = _ENV_LOWER in ("dev", "test") or os.getenv("ENABLE_API_DOCS_IN_PROD", "").lower() in (
    "1",
    "true",
    "yes",
    "on",
)
app = FastAPI(
    title="Bus API",
    version="0.1.0",
    docs_url="/docs" if _ENABLE_DOCS else None,
    redoc_url="/redoc" if _ENABLE_DOCS else None,
    openapi_url="/openapi.json" if _ENABLE_DOCS else None,
)
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", ""))
add_standard_health(app)

# Trusted hosts: mitigate Host header attacks and misrouting.
_allowed_hosts_raw = (os.getenv("ALLOWED_HOSTS") or "").strip()
if _allowed_hosts_raw:
    _allowed_hosts = [h.strip() for h in _allowed_hosts_raw.split(",") if h.strip()]
    # Keep local health checks working even if ALLOWED_HOSTS is minimal.
    for _extra in ("localhost", "127.0.0.1"):
        if _extra not in _allowed_hosts:
            _allowed_hosts.append(_extra)
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=_allowed_hosts)

BUS_INTERNAL_SECRET = os.getenv("BUS_INTERNAL_SECRET") or ""

# ---- Internal-only guard (defense-in-depth) ----
# In production/staging the Bus service should not be directly exposed to end
# users. The public surface is the BFF; Bus is an internal service.
_require_internal_raw = _env_or("BUS_REQUIRE_INTERNAL_SECRET", "").strip().lower()
if _require_internal_raw in ("0", "false", "no", "off"):
    BUS_REQUIRE_INTERNAL_SECRET = False
elif _require_internal_raw:
    BUS_REQUIRE_INTERNAL_SECRET = True
else:
    BUS_REQUIRE_INTERNAL_SECRET = _ENV_LOWER in ("prod", "production", "staging")


def _require_internal_secret(request: Request) -> None:
    if not BUS_REQUIRE_INTERNAL_SECRET:
        return
    # nosemgrep: semgrep.rules.shamell.authz.trusting-client-internal-headers
    # The value is treated as untrusted input and verified using constant-time
    # comparison against a server-side secret.
    provided = (request.headers.get("X-Internal-Secret") or "").strip()  # nosemgrep: semgrep.rules.shamell.authz.trusting-client-internal-headers
    if not BUS_INTERNAL_SECRET:
        # Misconfiguration: fail closed so the service is not accidentally exposed.
        raise HTTPException(status_code=503, detail="internal auth not configured")
    if not provided or not hmac.compare_digest(provided, BUS_INTERNAL_SECRET):
        raise HTTPException(status_code=401, detail="internal auth required")


router = APIRouter(dependencies=[Depends(_require_internal_secret)])


def _ensure_trips_status_column() -> None:
    """
    Lightweight SQLite migration: ensure that the 'status' column exists on
    the trips table and backfill NULLs with 'draft'.

    In production (non-SQLite) a proper migration tool should be used.
    """
    if not DB_URL.startswith("sqlite"):
        return
    try:
        with engine.begin() as conn:
            insp = inspect(conn)
            # trips.status
            cols = [c["name"] for c in insp.get_columns("trips", schema=DB_SCHEMA)]
            if "status" not in cols:
                conn.execute(text("ALTER TABLE trips ADD COLUMN status VARCHAR(16) DEFAULT 'draft'"))
            # Backfill any NULL statuses to 'draft'
            conn.execute(text("UPDATE trips SET status='draft' WHERE status IS NULL"))
            # routes.bus_model / routes.features
            cols_routes = [c["name"] for c in insp.get_columns("routes", schema=DB_SCHEMA)]
            if "bus_model" not in cols_routes:
                try:
                    conn.execute(text("ALTER TABLE routes ADD COLUMN bus_model VARCHAR(120)"))
                except Exception:
                    pass
            if "features" not in cols_routes:
                try:
                    conn.execute(text("ALTER TABLE routes ADD COLUMN features VARCHAR(1024)"))
                except Exception:
                    pass
    except Exception:
        # Best-effort; if this fails, table creation will still work but
        # new trips may error until schema is fixed manually.
        pass


def _ensure_booking_trip_columns() -> None:
    """
    SQLite migration to add missing trip_id columns on legacy deployments.

    Older DBs may have bookings/tickets without trip_id; new code relies on
    it for joins and reporting.
    """
    if not DB_URL.startswith("sqlite"):
        return
    try:
        with engine.begin() as conn:
            insp = inspect(conn)
            # bookings.trip_id
            cols_bookings = [c["name"] for c in insp.get_columns("bookings", schema=DB_SCHEMA)]
            if "trip_id" not in cols_bookings:
                conn.execute(text("ALTER TABLE bookings ADD COLUMN trip_id VARCHAR(36)"))
            # tickets.trip_id
            cols_tickets = [c["name"] for c in insp.get_columns("tickets", schema=DB_SCHEMA)]
            if "trip_id" not in cols_tickets:
                conn.execute(text("ALTER TABLE tickets ADD COLUMN trip_id VARCHAR(36)"))
    except Exception:
        # Best-effort: if this fails, caller will still have tables; admin can fix manually.
        pass


def on_startup():
    Base.metadata.create_all(engine)
    _ensure_trips_status_column()
    _ensure_booking_trip_columns()
    # SQLite migration for is_online on operators
    try:
        if DB_URL.startswith("sqlite"):
            with engine.begin() as conn:
                cols_op = [row[1] for row in conn.exec_driver_sql("PRAGMA table_info(bus_operators)")]
                if "is_online" not in cols_op:
                    try:
                        conn.exec_driver_sql("ALTER TABLE bus_operators ADD COLUMN is_online INTEGER DEFAULT 0")
                    except Exception:
                        pass
    except Exception:
        pass

app.router.on_startup.append(on_startup)


# ---- Schemas ----
class CityIn(BaseModel):
    name: str
    country: Optional[str] = None


class CityOut(BaseModel):
    id: str
    name: str
    country: Optional[str]
    model_config = ConfigDict(from_attributes=True)


class OperatorIn(BaseModel):
    name: str
    wallet_id: Optional[str] = None


class OperatorOut(BaseModel):
    id: str
    name: str
    wallet_id: Optional[str]
    is_online: bool = False
    model_config = ConfigDict(from_attributes=True)


class RouteIn(BaseModel):
    origin_city_id: str
    dest_city_id: str
    operator_id: str
    id: Optional[str] = None
    bus_model: Optional[str] = None
    features: Optional[str] = None


class RouteOut(BaseModel):
    id: str
    origin_city_id: str
    dest_city_id: str
    operator_id: str
    bus_model: Optional[str] = None
    features: Optional[str] = None
    model_config = ConfigDict(from_attributes=True)


class TripIn(BaseModel):
    route_id: str
    depart_at_iso: str
    arrive_at_iso: str
    price_cents: int = Field(..., gt=0)
    currency: str = "SYP"
    seats_total: int = Field(default=40, ge=1)


class TripOut(BaseModel):
    id: str
    route_id: str
    depart_at: datetime
    arrive_at: datetime
    price_cents: int
    currency: str
    seats_total: int
    seats_available: int
    status: str
    model_config = ConfigDict(from_attributes=True)


class TripSearchOut(BaseModel):
    trip: TripOut
    origin: CityOut
    dest: CityOut
    operator: OperatorOut
    features: Optional[str] = None


class QuoteOut(BaseModel):
    trip_id: str
    seats: int
    total_cents: int
    currency: str


class BookReq(BaseModel):
    seats: int = Field(default=1, ge=1, le=10)
    wallet_id: Optional[str] = None
    customer_phone: Optional[str] = None
    # Optional explicit seat selection; if provided, the number of
    # unique seat numbers must match `seats` and each seat must be
    # within 1..seats_total and not already booked.
    seat_numbers: Optional[List[int]] = None


class BookingOut(BaseModel):
    id: str
    trip_id: str
    seats: int
    status: str
    payments_txn_id: Optional[str]
    created_at: Optional[datetime]
    wallet_id: Optional[str] = None
    customer_phone: Optional[str] = None
    tickets: Optional[List[dict]] = None


def _booking_out_from_db(b: "Booking", s: Session, include_tickets: bool = True) -> BookingOut:
    tickets = None
    if include_tickets:
        tks = s.execute(select(Ticket).where(Ticket.booking_id == b.id)).scalars().all()
        tickets = [{"id": tk.id, "payload": _ticket_payload(tk)} for tk in tks]
    return BookingOut(
        id=b.id,
        trip_id=b.trip_id,
        seats=b.seats,
        status=b.status,
        payments_txn_id=b.payments_txn_id,
        created_at=b.created_at,
        wallet_id=b.wallet_id,
        customer_phone=b.customer_phone,
        tickets=tickets,
    )


class BookingCancelOut(BaseModel):
    booking: BookingOut
    refund_cents: int
    refund_currency: str
    refund_pct: int


# ---- CRUD/list/search ----
@router.get("/cities", response_model=List[CityOut])
def list_cities(q: str = "", limit: int = 50, s: Session = Depends(get_session)):
    stmt = select(City)
    if q:
        try:
            stmt = stmt.where(City.name.ilike(f"%{q}%"))
        except Exception:
            stmt = stmt.where(City.name.like(f"%{q}%"))
    stmt = stmt.order_by(City.name.asc()).limit(max(1, min(limit, 200)))
    return s.execute(stmt).scalars().all()


@router.post("/cities", response_model=CityOut)
def create_city(body: CityIn, s: Session = Depends(get_session)):
    c = City(id=str(uuid.uuid4()), name=body.name.strip(), country=(body.country or None))
    s.add(c); s.commit(); s.refresh(c)
    return c


@router.get("/operators", response_model=List[OperatorOut])
def list_operators(limit: int = 50, s: Session = Depends(get_session)):
    stmt = select(Operator).order_by(Operator.name.asc()).limit(max(1, min(limit, 200)))
    return s.execute(stmt).scalars().all()

@router.post("/operators/{operator_id}/online")
def operator_online(operator_id: str, s: Session = Depends(get_session)):
    op = s.get(Operator, operator_id)
    if not op:
        raise HTTPException(status_code=404, detail="operator not found")
    op.is_online = 1
    s.add(op); s.commit(); s.refresh(op)
    return {"ok": True, "is_online": bool(op.is_online)}


@router.post("/operators/{operator_id}/offline")
def operator_offline(operator_id: str, s: Session = Depends(get_session)):
    op = s.get(Operator, operator_id)
    if not op:
        raise HTTPException(status_code=404, detail="operator not found")
    op.is_online = 0
    s.add(op); s.commit(); s.refresh(op)
    return {"ok": True, "is_online": bool(op.is_online)}


@router.post("/operators", response_model=OperatorOut)
def create_operator(body: OperatorIn, s: Session = Depends(get_session)):
    op = Operator(id=str(uuid.uuid4()), name=body.name.strip(), wallet_id=(body.wallet_id or None), is_online=0)
    s.add(op); s.commit(); s.refresh(op)
    return op


@router.post("/routes", response_model=RouteOut)
def create_route(body: RouteIn, s: Session = Depends(get_session)):
    rid = (body.id or "").strip() or str(uuid.uuid4())
    r = Route(
        id=rid,
        origin_city_id=body.origin_city_id,
        dest_city_id=body.dest_city_id,
        operator_id=body.operator_id,
        bus_model=(body.bus_model or "").strip() or None,
        features=(body.features or "").strip() or None,
    )
    s.add(r); s.commit(); s.refresh(r)
    return r


@router.get("/routes", response_model=List[RouteOut])
def list_routes(origin_city_id: Optional[str] = None, dest_city_id: Optional[str] = None, s: Session = Depends(get_session)):
    stmt = select(Route)
    if origin_city_id:
        stmt = stmt.where(Route.origin_city_id == origin_city_id)
    if dest_city_id:
        stmt = stmt.where(Route.dest_city_id == dest_city_id)
    return s.execute(stmt).scalars().all()


@router.post("/trips", response_model=TripOut)
def create_trip(body: TripIn, s: Session = Depends(get_session)):
    try:
        dep = datetime.fromisoformat(body.depart_at_iso.replace("Z", "+00:00"))
        arr = datetime.fromisoformat(body.arrive_at_iso.replace("Z", "+00:00"))
    except Exception:
        raise HTTPException(status_code=400, detail="invalid date format; use ISO8601")
    # Operator must be online to create trips (resolve via route)
    rt = s.scalar(select(Route).where(Route.id == body.route_id))
    if not rt:
        raise HTTPException(status_code=404, detail="route not found")
    op = s.get(Operator, rt.operator_id)
    if not op:
        raise HTTPException(status_code=404, detail="operator not found")
    if not getattr(op, "is_online", 0):
        raise HTTPException(status_code=403, detail="operator offline")
    # New trips get a human-friendly ID of the form
    # ORIGIN-DEST-YYYYMMDD-HHMM and start as draft; the operator can
    # publish them explicitly.
    trip_id = _generate_trip_id(s, rt, dep)
    t = Trip(
        id=trip_id,
        route_id=body.route_id,
        depart_at=dep,
        arrive_at=arr,
        price_cents=body.price_cents,
        currency=body.currency,
        seats_total=body.seats_total,
        seats_available=body.seats_total,
        status="draft",
    )
    s.add(t); s.commit(); s.refresh(t)
    return t


@router.get("/trips/search", response_model=List[TripSearchOut])
def search_trips(origin_city_id: str, dest_city_id: str, date: str, s: Session = Depends(get_session)):
    # date is YYYY-MM-DD; match depart_at same day
    try:
        d0 = datetime.fromisoformat(date + "T00:00:00+00:00")
        d1 = d0 + timedelta(days=1)
    except Exception:
        raise HTTPException(status_code=400, detail="invalid date (YYYY-MM-DD)")
    # find routes then trips
    rts = s.execute(select(Route).where(Route.origin_city_id == origin_city_id, Route.dest_city_id == dest_city_id)).scalars().all()
    if not rts:
        return []
    rids = [r.id for r in rts]
    trips = s.execute(
        select(Trip)
        .where(
            Trip.route_id.in_(rids),
            Trip.depart_at >= d0,
            Trip.depart_at < d1,
            Trip.status == "published",
        )
        .order_by(Trip.depart_at.asc())
    ).scalars().all()
    # attach city/operator info
    cities = {c.id: c for c in s.execute(select(City).where(City.id.in_({origin_city_id, dest_city_id}))).scalars().all()}
    ops = {o.id: o for o in s.execute(select(Operator)).scalars().all()}
    out: List[TripSearchOut] = []
    for t in trips:
        # find route to resolve operator + features
        rt = next((r for r in rts if r.id == t.route_id), None)
        if not rt:
            continue
        op = ops.get(rt.operator_id)
        out.append(TripSearchOut(
            trip=t,
            origin=cities.get(origin_city_id) or CityOut(id=origin_city_id, name="", country=None),
            dest=cities.get(dest_city_id) or CityOut(id=dest_city_id, name="", country=None),
            operator=op or OperatorOut(id=rt.operator_id, name="", wallet_id=None),
            features=getattr(rt, "features", None),
        ))
    return out


@router.get("/operators/{operator_id}/trips", response_model=List[TripSearchOut])
def operator_trips(
    operator_id: str,
    status: Optional[str] = None,
    from_date: Optional[str] = None,
    to_date: Optional[str] = None,
    limit: int = 100,
    order: str = "desc",
    s: Session = Depends(get_session),
):
    """
    List trips for a given operator (includes drafts).

    Dates are YYYY-MM-DD in UTC; `to_date` is inclusive.
    """
    order = (order or "desc").strip().lower()
    if order not in ("asc", "desc"):
        raise HTTPException(status_code=400, detail="invalid order (asc|desc)")

    if status is not None:
        status = (status or "").strip().lower()
        if status in ("", "all"):
            status = None
        elif status not in ("draft", "published", "canceled"):
            raise HTTPException(status_code=400, detail="invalid status")

    start: Optional[datetime] = None
    end: Optional[datetime] = None
    if from_date:
        try:
            start = datetime.fromisoformat(from_date + "T00:00:00+00:00")
        except Exception:
            raise HTTPException(status_code=400, detail="invalid from_date (YYYY-MM-DD)")
    if to_date:
        try:
            end = datetime.fromisoformat(to_date + "T00:00:00+00:00") + timedelta(days=1)
        except Exception:
            raise HTTPException(status_code=400, detail="invalid to_date (YYYY-MM-DD)")

    routes = s.execute(select(Route).where(Route.operator_id == operator_id)).scalars().all()
    if not routes:
        return []
    route_by_id = {r.id: r for r in routes}
    route_ids = list(route_by_id.keys())

    q = select(Trip).where(Trip.route_id.in_(route_ids))
    if start is not None:
        q = q.where(Trip.depart_at >= start)
    if end is not None:
        q = q.where(Trip.depart_at < end)
    if status is not None:
        q = q.where(Trip.status == status)
    q = q.order_by(Trip.depart_at.asc() if order == "asc" else Trip.depart_at.desc()).limit(max(1, min(limit, 200)))
    trips = s.execute(q).scalars().all()
    if not trips:
        return []

    city_ids: set[str] = set()
    for r in routes:
        city_ids.add(r.origin_city_id)
        city_ids.add(r.dest_city_id)
    cities = {}
    if city_ids:
        cities = {c.id: c for c in s.execute(select(City).where(City.id.in_(city_ids))).scalars().all()}

    op = s.get(Operator, operator_id)
    out: List[TripSearchOut] = []
    for t in trips:
        rt = route_by_id.get(t.route_id)
        if not rt:
            continue
        out.append(
            TripSearchOut(
                trip=t,
                origin=cities.get(rt.origin_city_id) or CityOut(id=rt.origin_city_id, name="", country=None),
                dest=cities.get(rt.dest_city_id) or CityOut(id=rt.dest_city_id, name="", country=None),
                operator=op or OperatorOut(id=rt.operator_id, name="", wallet_id=None),
                features=getattr(rt, "features", None),
            )
        )
    return out


@router.get("/trips/{trip_id}", response_model=TripOut)
def trip_detail(trip_id: str, s: Session = Depends(get_session)):
    t = s.get(Trip, trip_id)
    if not t:
        raise HTTPException(status_code=404, detail="trip not found")
    return t


@router.post("/trips/{trip_id}/publish", response_model=TripOut)
def publish_trip(trip_id: str, s: Session = Depends(get_session)):
    """
    Mark a trip as published so that it appears in end-user search results.
    """
    t = s.get(Trip, trip_id)
    if not t:
        raise HTTPException(status_code=404, detail="trip not found")
    if t.status == "canceled":
        raise HTTPException(status_code=400, detail="trip canceled")
    # Check operator status
    rt = s.scalar(select(Route).where(Route.id == t.route_id))
    if not rt:
        raise HTTPException(status_code=404, detail="route not found")
    op = s.get(Operator, rt.operator_id)
    if not op:
        raise HTTPException(status_code=404, detail="operator not found")
    if not getattr(op, "is_online", 0):
        raise HTTPException(status_code=403, detail="operator offline")
    if t.status == "published":
        return t
    t.status = "published"
    s.add(t)
    s.commit()
    s.refresh(t)
    return t


@router.post("/trips/{trip_id}/unpublish", response_model=TripOut)
def unpublish_trip(trip_id: str, s: Session = Depends(get_session)):
    """
    Mark a trip as draft so that it does not appear in passenger search.
    """
    t = s.get(Trip, trip_id)
    if not t:
        raise HTTPException(status_code=404, detail="trip not found")
    if t.status == "canceled":
        raise HTTPException(status_code=400, detail="trip canceled")
    if t.status == "draft":
        return t
    t.status = "draft"
    s.add(t)
    s.commit()
    s.refresh(t)
    return t


@router.post("/trips/{trip_id}/cancel", response_model=TripOut)
def cancel_trip(trip_id: str, s: Session = Depends(get_session)):
    """
    Cancel a trip. This prevents future bookings (because only published trips can be booked).
    """
    t = s.get(Trip, trip_id)
    if not t:
        raise HTTPException(status_code=404, detail="trip not found")
    if t.status == "canceled":
        return t
    t.status = "canceled"
    s.add(t)
    s.commit()
    s.refresh(t)
    return t


@router.post("/trips/{trip_id}/quote", response_model=QuoteOut)
def quote(trip_id: str, seats: int = 1, s: Session = Depends(get_session)):
    t = s.get(Trip, trip_id)
    if not t:
        raise HTTPException(status_code=404, detail="trip not found")
    if seats < 1 or seats > 10:
        raise HTTPException(status_code=400, detail="invalid seats")
    total = t.price_cents * seats
    return QuoteOut(trip_id=trip_id, seats=seats, total_cents=total, currency=t.currency)


def _payments_transfer(from_wallet: str, to_wallet: str, amount_cents: int, ikey: str, ref: Optional[str] = None) -> dict:
    # Prefer internal Payments when explicitly enabled (monolith mode).
    if _use_pay_internal():
        if not (_PAY_INTERNAL_AVAILABLE and _PaySession and _pay_engine and _pay_transfer and _PayTransferReq):
            raise RuntimeError("payments internal not available")

        class _ReqStub:
            def __init__(self, key: str):
                self.headers = {"Idempotency-Key": key} if key else {}

        req_model = _PayTransferReq(from_wallet_id=from_wallet, to_wallet_id=to_wallet, amount_cents=amount_cents)  # type: ignore[call-arg]
        with _PaySession(_pay_engine) as ps:  # type: ignore[call-arg]
            resp = _pay_transfer(req_model, request=_ReqStub(ikey), s=ps)  # type: ignore[call-arg]
        # FastAPI/Pydantic response model → plain dict for consistency with HTTPX flow.
        if hasattr(resp, "model_dump"):
            return resp.model_dump()  # type: ignore[return-value]
        if hasattr(resp, "dict"):
            return resp.dict()  # type: ignore[return-value]
        return resp  # type: ignore[return-value]

    if not PAYMENTS_BASE:
        raise RuntimeError("PAYMENTS_BASE_URL not configured")
    url = PAYMENTS_BASE.rstrip('/') + '/transfer'
    headers = {"Content-Type": "application/json", "Idempotency-Key": ikey, "X-Merchant": "bus"}
    if ref:
        headers["X-Ref"] = ref
    payload = {"from_wallet_id": from_wallet, "to_wallet_id": to_wallet, "amount_cents": amount_cents}
    r = httpx.post(url, json=payload, headers=headers, timeout=15)
    r.raise_for_status()
    return r.json()


def _ticket_payload(tk: "Ticket") -> str:
    msg = f"{tk.id}:{tk.booking_id}:{tk.trip_id}:{tk.seat_no or 0}".encode()
    sig = hmac.new(TICKET_SECRET.encode(), msg, hashlib.sha256).hexdigest()
    return f"TICKET|id={tk.id}|b={tk.booking_id}|trip={tk.trip_id}|seat={tk.seat_no or 0}|sig={sig}"


def _refund_pct_for_departure(now: datetime, depart_at: datetime) -> float:
    """
    Compute refund percentage for cancellations/exchanges based on time
    left until departure.

    Policy (Redeemable voucher):
      - >=30 days before departure  -> 100%
      - >=7 days before departure   -> 70%
      - >=48 hours before departure -> 40%
      - >=0 hours before departure  -> 20%
      - after departure             -> 0% (not cancelable)
    """
    delta = depart_at - now
    if delta.total_seconds() < 0:
        return 0.0
    days = delta.total_seconds() / 86400.0
    hours = delta.total_seconds() / 3600.0
    if days >= 30:
        return 1.0
    if days >= 7:
        return 0.7
    if hours >= 48:
        return 0.4
    return 0.2


@router.post("/trips/{trip_id}/book", response_model=BookingOut)
def book_trip(trip_id: str, body: BookReq, idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"), s: Session = Depends(get_session)):
    t = s.get(Trip, trip_id)
    if not t:
        raise HTTPException(status_code=404, detail="trip not found")
    env_test = os.getenv("ENV", "dev").lower() == "test"
    if t.status != "published" and not env_test:
        raise HTTPException(status_code=400, detail="trip not published")
    wallet_id = (body.wallet_id or "").strip() or None

    seat_numbers: list[int] = []
    if body.seat_numbers:
        try:
            seat_numbers = [int(x) for x in body.seat_numbers]  # type: ignore[arg-type]
        except Exception:
            raise HTTPException(status_code=400, detail="seat_numbers must be integers")
        if len(seat_numbers) == 0:
            raise HTTPException(status_code=400, detail="seat_numbers cannot be empty")
        if len(set(seat_numbers)) != len(seat_numbers):
            raise HTTPException(status_code=400, detail="seat_numbers must be unique")
        for sn in seat_numbers:
            if sn < 1 or sn > t.seats_total:
                raise HTTPException(status_code=400, detail="seat_numbers out of range")
    else:
        seats_requested = body.seats

    if seat_numbers:
        seats_requested = len(seat_numbers)

    if seats_requested < 1 or seats_requested > 10:
        raise HTTPException(status_code=400, detail="invalid seats")

    seat_numbers_hash: Optional[str] = None
    if seat_numbers:
        normalized = ",".join(str(sn) for sn in sorted(seat_numbers))
        seat_numbers_hash = hashlib.sha256(normalized.encode()).hexdigest()

    require_payment = (bool(PAYMENTS_BASE) or _use_pay_internal()) and not env_test
    if require_payment and not wallet_id:
        raise HTTPException(status_code=400, detail="wallet_id required for booking")

    existing_booking: Optional[Booking] = None
    if idempotency_key:
        existed = s.get(Idempotency, idempotency_key)
        if existed:
            if (
                existed.trip_id != trip_id
                or (existed.wallet_id or "") != (wallet_id or "")
                or existed.seats != seats_requested
                or (existed.seat_numbers_hash or "") != (seat_numbers_hash or "")
            ):
                raise HTTPException(status_code=409, detail="Idempotency-Key reused with different parameters")
            if existed.booking_id:
                b_existing = s.get(Booking, existed.booking_id)
                if b_existing:
                    if require_payment and b_existing.status == "pending":
                        existing_booking = b_existing
                    else:
                        return _booking_out_from_db(b_existing, s)
        else:
            s.add(
                Idempotency(
                    key=idempotency_key,
                    trip_id=trip_id,
                    wallet_id=wallet_id,
                    seats=seats_requested,
                    seat_numbers_hash=seat_numbers_hash,
                )
            )
            s.commit()

    def _reserve_seats(ticket_status: str) -> tuple[Booking, list[Ticket]]:
        t_locked = (
            s.execute(select(Trip).where(Trip.id == trip_id).with_for_update()).scalars().first()
            if not DB_URL.startswith("sqlite")
            else t
        )
        taken_query = select(Ticket.seat_no).where(
            Ticket.trip_id == trip_id,
            Ticket.seat_no.is_not(None),
            Ticket.status != "canceled",
        )
        if not DB_URL.startswith("sqlite"):
            taken_query = taken_query.with_for_update()
        taken_seats = {sn for sn in s.execute(taken_query).scalars().all() if sn}
        if t_locked.seats_available < seats_requested:
            raise HTTPException(status_code=400, detail="not enough seats")
        if seat_numbers:
            conflict = [sn for sn in seat_numbers if sn in taken_seats]
            if conflict:
                raise HTTPException(status_code=400, detail="one or more selected seats already booked")
            assigned = seat_numbers
        else:
            assigned = []
            for sn in range(1, t.seats_total + 1):
                if sn in taken_seats:
                    continue
                assigned.append(sn)
                if len(assigned) == seats_requested:
                    break
            if len(assigned) != seats_requested:
                raise HTTPException(status_code=400, detail="not enough seats")
        t_locked.seats_available -= seats_requested
        b_local = Booking(
            id=str(uuid.uuid4()),
            trip_id=trip_id,
            price_cents=t.price_cents,
            customer_phone=(body.customer_phone or None),
            wallet_id=wallet_id,
            seats=seats_requested,
            status="pending",
        )
        s.add(t_locked)
        s.add(b_local)
        tickets_local: list[Ticket] = []
        for sn in assigned:
            tid = str(uuid.uuid4())
            tk = Ticket(id=tid, booking_id=b_local.id, trip_id=t.id, seat_no=sn, status=ticket_status)
            s.add(tk)
            tickets_local.append(tk)
        if idempotency_key:
            idem = s.get(Idempotency, idempotency_key)
            if idem:
                idem.booking_id = b_local.id
                s.add(idem)
        s.commit()
        s.refresh(b_local)
        return b_local, tickets_local

    def _fail_booking_and_release(booking_id: str):
        b_fail = s.get(Booking, booking_id)
        if not b_fail:
            return
        t_fail = (
            s.execute(select(Trip).where(Trip.id == b_fail.trip_id).with_for_update()).scalars().first()
            if not DB_URL.startswith("sqlite")
            else s.get(Trip, b_fail.trip_id)
        )
        tickets_fail = s.execute(select(Ticket).where(Ticket.booking_id == booking_id)).scalars().all()
        if t_fail:
            seats_back = b_fail.seats or 0
            t_fail.seats_available = min(t_fail.seats_total, t_fail.seats_available + seats_back)
            s.add(t_fail)
        for tk in tickets_fail:
            tk.status = "canceled"
            s.add(tk)
        b_fail.status = "failed"
        s.add(b_fail)
        s.commit()

    if not require_payment:
        booking, _ = _reserve_seats(ticket_status="issued")
        return _booking_out_from_db(booking, s, include_tickets=True)

    booking = existing_booking
    tickets_for_booking: list[Ticket] = []
    if not booking:
        booking, tickets_for_booking = _reserve_seats(ticket_status="pending")
    else:
        seats_requested = booking.seats
        tickets_for_booking = s.execute(select(Ticket).where(Ticket.booking_id == booking.id)).scalars().all()

    rt = s.execute(select(Route).where(Route.id == t.route_id)).scalars().first()
    op = s.execute(select(Operator).where(Operator.id == rt.operator_id)).scalars().first() if rt else None
    amount = t.price_cents * seats_requested

    payment_resp: Optional[dict] = None
    try:
        if not op or not op.wallet_id:
            raise HTTPException(status_code=500, detail="operator wallet not configured")
        if wallet_id == op.wallet_id:
            pass
        else:
            payment_resp = _payments_transfer(wallet_id, op.wallet_id, amount, ikey=f"bus-book-{booking.id}", ref=f"booking-{booking.id}")
    except httpx.HTTPStatusError as e:
        msg = ""
        try:
            if e.response is not None:
                try:
                    j = e.response.json()
                    if isinstance(j, dict) and "detail" in j:
                        msg = str(j.get("detail") or "")
                    else:
                        msg = e.response.text or ""
                except Exception:
                    msg = e.response.text or ""
            else:
                msg = str(e)
        except Exception:
            msg = str(e)
        _fail_booking_and_release(booking.id)
        low = msg.lower()
        if "insufficient funds" in low or ("insufficient" in low and "balance" in low):
            raise HTTPException(status_code=400, detail="insufficient funds")
        if "cannot transfer to same wallet" in low:
            raise HTTPException(status_code=400, detail="cannot transfer to same wallet")
        raise HTTPException(status_code=500, detail="payment failed")
    except HTTPException as e:
        _fail_booking_and_release(booking.id)
        msg = str(getattr(e, "detail", "") or "")
        low = msg.lower()
        if "insufficient funds" in low or ("insufficient" in low and "balance" in low):
            raise HTTPException(status_code=400, detail="insufficient funds")
        if "cannot transfer to same wallet" in low:
            raise HTTPException(status_code=400, detail="cannot transfer to same wallet")
        raise HTTPException(status_code=500, detail="payment failed")
    except Exception:
        _fail_booking_and_release(booking.id)
        raise HTTPException(status_code=500, detail="payment failed")

    t_confirm = (
        s.execute(select(Trip).where(Trip.id == trip_id).with_for_update()).scalars().first()
        if not DB_URL.startswith("sqlite")
        else s.get(Trip, trip_id)
    )
    booking = s.get(Booking, booking.id)
    tickets_for_booking = s.execute(select(Ticket).where(Ticket.booking_id == booking.id)).scalars().all()
    if booking:
        booking.status = "confirmed"
        if isinstance(payment_resp, dict):
            booking.payments_txn_id = str(payment_resp.get("id") or payment_resp.get("txn_id") or "")
        s.add(booking)
    for tk in tickets_for_booking:
        tk.status = "issued"
        if not tk.issued_at:
            tk.issued_at = datetime.now(timezone.utc)
        s.add(tk)
    if t_confirm:
        s.add(t_confirm)
    s.commit()
    if booking:
        s.refresh(booking)
        return _booking_out_from_db(booking, s, include_tickets=True)
    raise HTTPException(status_code=500, detail="booking confirmation failed")


@router.get("/bookings/{booking_id}", response_model=BookingOut)
def booking_status(booking_id: str, s: Session = Depends(get_session)):
    b = s.get(Booking, booking_id)
    if not b:
        raise HTTPException(status_code=404, detail="not found")
    return _booking_out_from_db(b, s, include_tickets=True)


@router.post("/bookings/{booking_id}/cancel", response_model=BookingCancelOut)
def cancel_booking(booking_id: str, s: Session = Depends(get_session)):
    """
    Cancel a confirmed booking and apply a time-based refund policy.

    Refund rules (voucher-style, applied as wallet refund when payments
    are enabled):

      - >=30 days before departure  -> 100% refund
      - >=7 days before departure   -> 70% refund
      - >=48 hours before departure -> 40% refund
      - >=0 hours before departure  -> 20% refund

    After departure, cancellations are rejected.
    """
    b = (
        s.execute(select(Booking).where(Booking.id == booking_id).with_for_update()).scalars().first()
        if not DB_URL.startswith("sqlite")
        else s.get(Booking, booking_id)
    )
    if not b:
        raise HTTPException(status_code=404, detail="not found")
    if b.status == "canceled":
        raise HTTPException(status_code=400, detail="booking already canceled")
    t = (
        s.execute(select(Trip).where(Trip.id == b.trip_id).with_for_update()).scalars().first()
        if not DB_URL.startswith("sqlite")
        else s.get(Trip, b.trip_id)
    )
    if not t:
        raise HTTPException(status_code=404, detail="trip not found")
    now = datetime.now(timezone.utc)
    pct = _refund_pct_for_departure(now, t.depart_at)
    if pct <= 0:
        raise HTTPException(status_code=400, detail="departure passed; cannot cancel")
    # Prevent cancel if any ticket already boarded
    has_boarded = s.execute(
        select(Ticket).where(Ticket.booking_id == booking_id, Ticket.status == "boarded")
    ).scalars().first()
    if has_boarded:
        raise HTTPException(status_code=400, detail="one or more tickets already boarded")
    amount = int(b.price_cents or t.price_cents or 0) * int(b.seats or 0)
    refund_cents = int(round(amount * pct))
    currency = t.currency
    # Release seats
    t.seats_available = min(t.seats_total, int(t.seats_available or 0) + int(b.seats or 0))
    # Cancel tickets
    tickets_q = select(Ticket).where(Ticket.booking_id == booking_id)
    if not DB_URL.startswith("sqlite"):
        tickets_q = tickets_q.with_for_update()
    tickets = s.execute(tickets_q).scalars().all()
    for tk in tickets:
        if tk.status != "boarded":
            tk.status = "canceled"
            s.add(tk)
    # Apply wallet refund only when payments are configured and both wallets are known.
    payments_enabled = bool(PAYMENTS_BASE) or _use_pay_internal()
    if payments_enabled and refund_cents > 0 and b.wallet_id:
        # Resolve operator wallet via route
        rt = s.execute(select(Route).where(Route.id == t.route_id)).scalars().first()
        op = s.execute(select(Operator).where(Operator.id == rt.operator_id)).scalars().first() if rt else None
        if not op or not op.wallet_id:
            raise HTTPException(status_code=500, detail="operator wallet not configured for refund")
        try:
            _payments_transfer(
                op.wallet_id,
                b.wallet_id,
                refund_cents,
                ikey=f"bus-refund-{b.id}",
                ref=f"booking-refund-{b.id}",
            )
        except httpx.HTTPStatusError as e:
            msg = ""
            try:
                if e.response is not None:
                    try:
                        j = e.response.json()
                        if isinstance(j, dict) and "detail" in j:
                            msg = str(j.get("detail") or "")
                        else:
                            msg = e.response.text or ""
                    except Exception:
                        msg = e.response.text or ""
                else:
                    msg = str(e)
            except Exception:
                msg = str(e)
            raise HTTPException(status_code=502, detail=f"refund failed: {msg}")
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=502, detail=f"refund failed: {e}")
    # Mark booking as canceled regardless of payments mode.
    b.status = "canceled"
    s.add(b)
    s.add(t)
    s.commit()
    s.refresh(b)
    return BookingCancelOut(
        booking=BookingOut(
            id=b.id,
            trip_id=b.trip_id,
            seats=b.seats,
            status=b.status,
            payments_txn_id=b.payments_txn_id,
            created_at=b.created_at,
            wallet_id=b.wallet_id,
            customer_phone=b.customer_phone,
        ),
        refund_cents=refund_cents,
        refund_currency=currency,
        refund_pct=int(round(pct * 100)),
    )


class BookingSearchOut(BaseModel):
    id: str
    trip: TripOut
    origin: CityOut
    dest: CityOut
    operator: OperatorOut
    seats: int
    status: str
    created_at: Optional[datetime]
    wallet_id: Optional[str] = None
    customer_phone: Optional[str] = None


@router.get("/bookings/search", response_model=List[BookingSearchOut])
def booking_search(wallet_id: Optional[str] = None, phone: Optional[str] = None, limit: int = 20, s: Session = Depends(get_session)):
    if not wallet_id and not phone:
        raise HTTPException(status_code=400, detail="wallet_id or phone required")
    q = select(Booking)
    if wallet_id:
        q = q.where(Booking.wallet_id == wallet_id)
    if phone:
        q = q.where(Booking.customer_phone == phone)
    q = q.order_by(Booking.created_at.desc()).limit(max(1, min(limit, 100)))
    bookings = s.execute(q).scalars().all()
    if not bookings:
        return []
    trip_ids = {b.trip_id for b in bookings}
    trips = s.execute(select(Trip).where(Trip.id.in_(trip_ids))).scalars().all()
    trip_by_id = {t.id: t for t in trips}
    route_ids = {t.route_id for t in trips}
    routes = s.execute(select(Route).where(Route.id.in_(route_ids))).scalars().all()
    route_by_id = {r.id: r for r in routes}
    city_ids: set[str] = set()
    op_ids: set[str] = set()
    for r in routes:
        city_ids.add(r.origin_city_id)
        city_ids.add(r.dest_city_id)
        op_ids.add(r.operator_id)
    cities = {}
    if city_ids:
        cities = {c.id: c for c in s.execute(select(City).where(City.id.in_(city_ids))).scalars().all()}
    ops = {}
    if op_ids:
        ops = {o.id: o for o in s.execute(select(Operator).where(Operator.id.in_(op_ids))).scalars().all()}
    out: List[BookingSearchOut] = []
    for b in bookings:
        t = trip_by_id.get(b.trip_id)
        if not t:
            continue
        rt = route_by_id.get(t.route_id)
        if rt:
            orig = cities.get(rt.origin_city_id) or CityOut(id=rt.origin_city_id, name="", country=None)
            dst = cities.get(rt.dest_city_id) or CityOut(id=rt.dest_city_id, name="", country=None)
            op = ops.get(rt.operator_id) or OperatorOut(id=rt.operator_id, name="", wallet_id=None)
        else:
            orig = CityOut(id="", name="", country=None)
            dst = CityOut(id="", name="", country=None)
            op = OperatorOut(id="", name="", wallet_id=None)
        out.append(BookingSearchOut(
            id=b.id,
            trip=t,
            origin=orig,
            dest=dst,
            operator=op,
            seats=b.seats,
            status=b.status,
            created_at=b.created_at,
            wallet_id=b.wallet_id,
            customer_phone=b.customer_phone,
        ))
    return out


class TicketOut(BaseModel):
    id: str
    booking_id: str
    trip_id: str
    seat_no: Optional[int]
    status: str
    payload: str


@router.get("/bookings/{booking_id}/tickets", response_model=List[TicketOut])
def booking_tickets(booking_id: str, s: Session = Depends(get_session)):
    rows = s.execute(select(Ticket).where(Ticket.booking_id == booking_id).order_by(Ticket.seat_no.asc())).scalars().all()
    out: List[TicketOut] = []
    import hmac as _hmac, hashlib as _hash
    for tk in rows:
        msg = f"{tk.id}:{tk.booking_id}:{tk.trip_id}:{tk.seat_no or 0}".encode()
        sig = _hmac.new(TICKET_SECRET.encode(), msg, _hash.sha256).hexdigest()
        payload = f"TICKET|id={tk.id}|b={tk.booking_id}|trip={tk.trip_id}|seat={tk.seat_no or 0}|sig={sig}"
        out.append(TicketOut(id=tk.id, booking_id=tk.booking_id, trip_id=tk.trip_id, seat_no=tk.seat_no, status=tk.status, payload=payload))
    return out


class BoardReq(BaseModel):
    payload: str


@router.post("/tickets/board")
def ticket_board(body: BoardReq, s: Session = Depends(get_session)):
    # payload format: TICKET|id=...|b=...|trip=...|seat=...|sig=...
    p = { }
    try:
        parts = body.payload.strip().split('|')
        if not parts or parts[0] != 'TICKET':
            raise ValueError('invalid payload')
        for kv in parts[1:]:
            k, v = kv.split('=', 1)
            p[k] = v
        tid = p.get('id'); bid = p.get('b'); trip = p.get('trip'); seat = int(p.get('seat') or '0')
        sig = p.get('sig') or ''
    except Exception:
        raise HTTPException(status_code=400, detail="invalid payload")
    tk = (
        s.execute(select(Ticket).where(Ticket.id == tid).with_for_update()).scalars().first()
        if not DB_URL.startswith("sqlite")
        else s.get(Ticket, tid)
    )
    if not tk or tk.booking_id != bid or tk.trip_id != trip:
        raise HTTPException(status_code=404, detail="ticket not found")
    if tk.status == "canceled":
        raise HTTPException(status_code=400, detail="ticket canceled")
    # verify signature
    import hmac as _hmac, hashlib as _hash
    expect = _hmac.new(TICKET_SECRET.encode(), f"{tid}:{bid}:{trip}:{seat}".encode(), _hash.sha256).hexdigest()
    if not _hmac.compare_digest(expect, sig):
        raise HTTPException(status_code=401, detail="invalid signature")
    booking = (
        s.execute(select(Booking).where(Booking.id == tk.booking_id).with_for_update()).scalars().first()
        if not DB_URL.startswith("sqlite")
        else s.get(Booking, tk.booking_id)
    )
    if booking and booking.status != "confirmed":
        env = os.getenv("ENV", "dev").lower()
        payments_enabled = bool(PAYMENTS_BASE) or _use_pay_internal()
        # In dev/test or when payments are disabled, allow boarding pending bookings.
        if payments_enabled and env not in ("dev", "test"):
            raise HTTPException(status_code=400, detail="booking not confirmed")
    if tk.status == 'boarded':
        # Ticket was already boarded earlier; surface this explicitly so
        # the operator can detect potential fraud (ticket re-use).
        return {"ok": True, "status": "already_boarded", "boarded_at": tk.boarded_at}
    tk.status = 'boarded'; tk.boarded_at = datetime.now(timezone.utc)
    s.add(tk); s.commit(); s.refresh(tk)
    return {"ok": True, "status": tk.status, "boarded_at": tk.boarded_at}


class OperatorStatsOut(BaseModel):
    operator_id: str
    period: str
    trips: int
    bookings: int
    confirmed_bookings: int
    seats_sold: int
    seats_total: int
    seats_boarded: int
    revenue_cents: int


@router.get("/operators/{operator_id}/stats", response_model=OperatorStatsOut)
def operator_stats(operator_id: str, period: str = "today", s: Session = Depends(get_session)):
    now = datetime.now(timezone.utc)
    if period == "today":
        start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    elif period == "7d":
        start = now - timedelta(days=7)
    elif period == "30d":
        start = now - timedelta(days=30)
    else:
        raise HTTPException(status_code=400, detail="invalid period")
    # routes for operator
    routes = s.execute(select(Route).where(Route.operator_id == operator_id)).scalars().all()
    if not routes:
        return OperatorStatsOut(
            operator_id=operator_id,
            period=period,
            trips=0,
            bookings=0,
            confirmed_bookings=0,
            seats_sold=0,
            seats_total=0,
            seats_boarded=0,
            revenue_cents=0,
        )
    route_ids = [r.id for r in routes]
    trips = s.execute(select(Trip).where(Trip.route_id.in_(route_ids), Trip.depart_at >= start)).scalars().all()
    trip_ids = [t.id for t in trips]
    # bookings in period (by creation date)
    bookings = s.execute(
        select(Booking).where(
            Booking.trip_id.in_(trip_ids),
            Booking.created_at >= start,
        )
    ).scalars().all()
    confirmed = [b for b in bookings if b.status == "confirmed"]
    seats_sold = sum(b.seats for b in confirmed)
    trip_by_id = {t.id: t for t in trips}
    revenue_cents = 0
    for b in confirmed:
        t = trip_by_id.get(b.trip_id)
        if t:
            revenue_cents += t.price_cents * b.seats
    # seats_total for trips in period (by departure date)
    seats_total = 0
    for t in trips:
        if t.depart_at >= start:
            seats_total += t.seats_total
    # Seats boarded (via QR tickets) for this operator in the period
    seats_boarded = s.execute(
        select(func.count(Ticket.id)).where(
            Ticket.trip_id.in_(trip_ids),
            Ticket.status == "boarded",
            Ticket.boarded_at >= start,
        )
    ).scalar() or 0
    return OperatorStatsOut(
        operator_id=operator_id,
        period=period,
        trips=len(trips),
        bookings=len(bookings),
        confirmed_bookings=len(confirmed),
        seats_sold=seats_sold,
        seats_total=seats_total,
        seats_boarded=seats_boarded,
        revenue_cents=revenue_cents,
    )


class AdminSummaryOut(BaseModel):
    operators: int
    routes: int
    trips_total: int
    trips_today: int
    bookings_total: int
    bookings_today: int
    bookings_confirmed_today: int
    revenue_cents_today: int


@router.get("/admin/summary", response_model=AdminSummaryOut)
def admin_summary(s: Session = Depends(get_session)):
    now = datetime.now(timezone.utc)
    start_today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    end_today = start_today + timedelta(days=1)

    ops_count = s.execute(select(func.count(Operator.id))).scalar() or 0
    routes_count = s.execute(select(func.count(Route.id))).scalar() or 0
    trips_total = s.execute(select(func.count(Trip.id))).scalar() or 0
    trips_today = s.execute(
        select(func.count(Trip.id)).where(
            Trip.depart_at >= start_today,
            Trip.depart_at < end_today,
        )
    ).scalar() or 0
    bookings_total = s.execute(select(func.count(Booking.id))).scalar() or 0
    bookings_today = s.execute(
        select(func.count(Booking.id)).where(Booking.created_at >= start_today)
    ).scalar() or 0
    confirmed_today = s.execute(
        select(Booking).where(
            Booking.created_at >= start_today,
            Booking.status == "confirmed",
        )
    ).scalars().all()
    trip_ids = {b.trip_id for b in confirmed_today}
    trips = []
    if trip_ids:
        trips = s.execute(select(Trip).where(Trip.id.in_(trip_ids))).scalars().all()
    trip_by_id = {t.id: t for t in trips}
    revenue_cents_today = 0
    for b in confirmed_today:
        t = trip_by_id.get(b.trip_id)
        if t:
            revenue_cents_today += t.price_cents * b.seats

    return AdminSummaryOut(
        operators=ops_count,
        routes=routes_count,
        trips_total=trips_total,
        trips_today=trips_today,
        bookings_total=bookings_total,
        bookings_today=bookings_today,
        bookings_confirmed_today=len(confirmed_today),
        revenue_cents_today=revenue_cents_today,
    )


app.include_router(router)
