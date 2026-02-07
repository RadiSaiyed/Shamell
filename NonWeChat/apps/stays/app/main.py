from fastapi import FastAPI, HTTPException, Depends, Request, Header, APIRouter
from pydantic import BaseModel, Field, ConfigDict
from typing import Optional, List
import os
from shamell_shared import RequestIDMiddleware, configure_cors, add_standard_health, setup_json_logging
from sqlalchemy import create_engine, String, Integer, BigInteger, DateTime, Date, func, ForeignKey, text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, Session
from sqlalchemy import select
from datetime import datetime, date, timedelta
import time, uuid
import httpx, json


def _env_or(key: str, default: str) -> str:
    v = os.getenv(key)
    return v if v is not None else default


app = FastAPI(title="Stays API", version="0.1.0")
setup_json_logging()
app.add_middleware(RequestIDMiddleware)
configure_cors(app, os.getenv("ALLOWED_ORIGINS", "*"))
add_standard_health(app)

router = APIRouter()


DB_URL = _env_or("STAYS_DB_URL", _env_or("DB_URL", "sqlite+pysqlite:////tmp/stays.db"))
DB_SCHEMA = os.getenv("DB_SCHEMA") if not DB_URL.startswith("sqlite") else None
PAYMENTS_BASE = _env_or("PAYMENTS_BASE_URL", "")
LOGIN_CODE_TTL_SECS = int(_env_or("OP_LOGIN_CODE_TTL_SECS", "300"))
_OP_LOGIN_CODES: dict[str, tuple[str,int]] = {}


class Base(DeclarativeBase):
    pass


class Operator(Base):
    __tablename__ = "operators"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(160))
    phone: Mapped[str] = mapped_column(String(32))
    username: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    city: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    wallet_id: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())

# --- Hotel PMS models ---
class RoomType(Base):
    __tablename__ = "room_types"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    operator_id: Mapped[int] = mapped_column(Integer, index=True)
    # Multi-property support (optional)
    property_id: Mapped[Optional[int]] = mapped_column(Integer, default=None, index=True)
    title: Mapped[str] = mapped_column(String(160))
    description: Mapped[Optional[str]] = mapped_column(String(2048), default=None)
    base_price_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    max_guests: Mapped[int] = mapped_column(Integer, default=2)
    amenities: Mapped[Optional[str]] = mapped_column(String(4096), default=None)
    image_urls: Mapped[Optional[str]] = mapped_column(String(4096), default=None)
    active: Mapped[int] = mapped_column(Integer, default=1)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())

class Room(Base):
    __tablename__ = "rooms"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    operator_id: Mapped[int] = mapped_column(Integer, index=True)
    # Multi-property support (optional)
    property_id: Mapped[Optional[int]] = mapped_column(Integer, default=None, index=True)
    room_type_id: Mapped[int] = mapped_column(Integer)
    code: Mapped[str] = mapped_column(String(64))
    floor: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    status: Mapped[str] = mapped_column(String(16), default="clean")
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())

class RoomRate(Base):
    __tablename__ = "room_rates"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    operator_id: Mapped[int] = mapped_column(Integer, index=True)
    room_type_id: Mapped[int] = mapped_column(Integer, index=True)
    day: Mapped[date] = mapped_column(Date)
    price_cents: Mapped[Optional[int]] = mapped_column(BigInteger, default=None)
    allotment: Mapped[int] = mapped_column(Integer, default=0)
    closed: Mapped[int] = mapped_column(Integer, default=0)
    # Restrictions
    min_los: Mapped[Optional[int]] = mapped_column(Integer, default=None)  # minimum length of stay (nights)
    max_los: Mapped[Optional[int]] = mapped_column(Integer, default=None)  # maximum length of stay (nights)
    cta: Mapped[int] = mapped_column(Integer, default=0)  # closed to arrival on this day
    ctd: Mapped[int] = mapped_column(Integer, default=0)  # closed to departure on this day
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Listing(Base):
    __tablename__ = "listings"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    # Multi-property support (optional)
    property_id: Mapped[Optional[int]] = mapped_column(Integer, default=None, index=True)
    title: Mapped[str] = mapped_column(String(200))
    city: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    address: Mapped[Optional[str]] = mapped_column(String(255), default=None)
    description: Mapped[Optional[str]] = mapped_column(String(2048), default=None)
    image_urls: Mapped[Optional[str]] = mapped_column(String(4096), default=None)  # JSON array string
    price_per_night_cents: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), default="SYP")
    property_type: Mapped[Optional[str]] = mapped_column(String(64), default=None)  # e.g., Hotel, Apartment, Villa
    operator_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey((f"{DB_SCHEMA}.operators.id" if DB_SCHEMA else "operators.id")), nullable=True)
    room_type_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    owner_wallet_id: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Booking(Base):
    __tablename__ = "bookings"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    listing_id: Mapped[int] = mapped_column(Integer)
    guest_name: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    guest_phone: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    guest_wallet_id: Mapped[Optional[str]] = mapped_column(String(36), default=None)
    from_date: Mapped[Optional[date]] = mapped_column(Date)
    to_date: Mapped[Optional[date]] = mapped_column(Date)
    nights: Mapped[int] = mapped_column(Integer, default=0)
    amount_cents: Mapped[int] = mapped_column(BigInteger, default=0)
    status: Mapped[str] = mapped_column(String(16), default="requested")  # requested|confirmed|canceled|completed
    payments_txn_id: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Idempotency(Base):
    __tablename__ = "idempotency"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    key: Mapped[str] = mapped_column(String(120), primary_key=True)
    ref_id: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())

class OperatorToken(Base):
    __tablename__ = "operator_tokens"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    token: Mapped[str] = mapped_column(String(64), primary_key=True)
    operator_id: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())

# --- Multi-property and roles ---
class Property(Base):
    __tablename__ = "properties"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    operator_id: Mapped[int] = mapped_column(Integer, index=True)
    name: Mapped[str] = mapped_column(String(160))
    city: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    address: Mapped[Optional[str]] = mapped_column(String(255), default=None)
    active: Mapped[int] = mapped_column(Integer, default=1)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())

class OperatorStaff(Base):
    __tablename__ = "operator_staff"
    __table_args__ = ({"schema": DB_SCHEMA} if DB_SCHEMA else {})
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    operator_id: Mapped[int] = mapped_column(Integer, index=True)
    username: Mapped[str] = mapped_column(String(64))
    role: Mapped[str] = mapped_column(String(32))  # owner|frontdesk|housekeeping|revenue
    property_id: Mapped[Optional[int]] = mapped_column(Integer, default=None, index=True)
    phone: Mapped[Optional[str]] = mapped_column(String(32), default=None)
    created_at: Mapped[Optional[str]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    active: Mapped[int] = mapped_column(Integer, default=1)


engine = create_engine(DB_URL, future=True)


def get_session() -> Session:
    with Session(engine) as s:
        yield s


def _ensure_sqlite_migrations():
    # Minimal migration helper for SQLite in local dev
    if not DB_URL.startswith("sqlite"):
        return
    with engine.begin() as conn:
        cols = [row[1] for row in conn.exec_driver_sql("PRAGMA table_info(listings)").fetchall()]
        if "operator_id" not in cols:
            conn.exec_driver_sql("ALTER TABLE listings ADD COLUMN operator_id INTEGER")
        if "address" not in cols:
            conn.exec_driver_sql("ALTER TABLE listings ADD COLUMN address VARCHAR(255)")
        if "description" not in cols:
            conn.exec_driver_sql("ALTER TABLE listings ADD COLUMN description VARCHAR(2048)")
        if "image_urls" not in cols:
            conn.exec_driver_sql("ALTER TABLE listings ADD COLUMN image_urls VARCHAR(4096)")
        if "property_type" not in cols:
            conn.exec_driver_sql("ALTER TABLE listings ADD COLUMN property_type VARCHAR(64)")
        # ensure tables exist
        conn.exec_driver_sql("""
        CREATE TABLE IF NOT EXISTS operators (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name VARCHAR(160) NOT NULL,
            phone VARCHAR(32) NOT NULL,
            username VARCHAR(64),
            city VARCHAR(64),
            wallet_id VARCHAR(64),
            created_at DATETIME DEFAULT (CURRENT_TIMESTAMP)
        )
        """)
        # Add username column if missing
        cols_op = [row[1] for row in conn.exec_driver_sql("PRAGMA table_info(operators)").fetchall()]
        if "username" not in cols_op:
            conn.exec_driver_sql("ALTER TABLE operators ADD COLUMN username VARCHAR(64)")
        # Create a unique index on username if not exists (SQLite allows IF NOT EXISTS)
        conn.exec_driver_sql("CREATE UNIQUE INDEX IF NOT EXISTS ux_operators_username ON operators(username)")
        # add new column room_type_id if missing
        cols2 = [row[1] for row in conn.exec_driver_sql("PRAGMA table_info(listings)").fetchall()]
        if "room_type_id" not in cols2:
            conn.exec_driver_sql("ALTER TABLE listings ADD COLUMN room_type_id INTEGER")
        if "property_id" not in cols2:
            conn.exec_driver_sql("ALTER TABLE listings ADD COLUMN property_id INTEGER")
        conn.exec_driver_sql("""
        CREATE TABLE IF NOT EXISTS operator_tokens (
            token VARCHAR(64) PRIMARY KEY,
            operator_id INTEGER NOT NULL,
            created_at DATETIME DEFAULT (CURRENT_TIMESTAMP)
        )
        """)
        conn.exec_driver_sql("""
        CREATE TABLE IF NOT EXISTS room_types (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            operator_id INTEGER NOT NULL,
            property_id INTEGER,
            title VARCHAR(160) NOT NULL,
            description VARCHAR(2048),
            base_price_cents BIGINT DEFAULT 0,
            max_guests INTEGER DEFAULT 2,
            amenities VARCHAR(4096),
            image_urls VARCHAR(4096),
            active INTEGER DEFAULT 1,
            created_at DATETIME DEFAULT (CURRENT_TIMESTAMP)
        )
        """)
        cols_rt = [row[1] for row in conn.exec_driver_sql("PRAGMA table_info(room_types)").fetchall()]
        if "property_id" not in cols_rt:
            conn.exec_driver_sql("ALTER TABLE room_types ADD COLUMN property_id INTEGER")
        conn.exec_driver_sql("""
        CREATE TABLE IF NOT EXISTS rooms (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            operator_id INTEGER NOT NULL,
            room_type_id INTEGER NOT NULL,
            property_id INTEGER,
            code VARCHAR(64) NOT NULL,
            floor VARCHAR(32),
            status VARCHAR(16) DEFAULT 'clean',
            created_at DATETIME DEFAULT (CURRENT_TIMESTAMP)
        )
        """)
        cols_rm = [row[1] for row in conn.exec_driver_sql("PRAGMA table_info(rooms)").fetchall()]
        if "property_id" not in cols_rm:
            conn.exec_driver_sql("ALTER TABLE rooms ADD COLUMN property_id INTEGER")
        conn.exec_driver_sql("""
        CREATE TABLE IF NOT EXISTS room_rates (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            operator_id INTEGER NOT NULL,
            room_type_id INTEGER NOT NULL,
            day DATE NOT NULL,
            price_cents BIGINT,
            allotment INTEGER DEFAULT 0,
            closed INTEGER DEFAULT 0,
            min_los INTEGER,
            max_los INTEGER,
            cta INTEGER DEFAULT 0,
            ctd INTEGER DEFAULT 0,
            created_at DATETIME DEFAULT (CURRENT_TIMESTAMP)
        )
        """)
        # Add new restriction columns if missing
        cols_rr = [row[1] for row in conn.exec_driver_sql("PRAGMA table_info(room_rates)").fetchall()]
        if "min_los" not in cols_rr:
            conn.exec_driver_sql("ALTER TABLE room_rates ADD COLUMN min_los INTEGER")
        if "max_los" not in cols_rr:
            conn.exec_driver_sql("ALTER TABLE room_rates ADD COLUMN max_los INTEGER")
        if "cta" not in cols_rr:
            conn.exec_driver_sql("ALTER TABLE room_rates ADD COLUMN cta INTEGER DEFAULT 0")
        if "ctd" not in cols_rr:
            conn.exec_driver_sql("ALTER TABLE room_rates ADD COLUMN ctd INTEGER DEFAULT 0")
        # New tables: properties, operator_staff
        conn.exec_driver_sql("""
        CREATE TABLE IF NOT EXISTS properties (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            operator_id INTEGER NOT NULL,
            name VARCHAR(160) NOT NULL,
            city VARCHAR(64),
            address VARCHAR(255),
            active INTEGER DEFAULT 1,
            created_at DATETIME DEFAULT (CURRENT_TIMESTAMP)
        )
        """)
        conn.exec_driver_sql("CREATE INDEX IF NOT EXISTS ix_properties_operator ON properties(operator_id)")
        conn.exec_driver_sql("""
        CREATE TABLE IF NOT EXISTS operator_staff (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            operator_id INTEGER NOT NULL,
            username VARCHAR(64) NOT NULL,
            role VARCHAR(32) NOT NULL,
            property_id INTEGER,
            phone VARCHAR(32),
            created_at DATETIME DEFAULT (CURRENT_TIMESTAMP),
            active INTEGER DEFAULT 1
        )
        """)
        conn.exec_driver_sql("CREATE INDEX IF NOT EXISTS ix_staff_operator ON operator_staff(operator_id)")
        conn.exec_driver_sql("CREATE UNIQUE INDEX IF NOT EXISTS ux_staff_op_user ON operator_staff(operator_id, username)")
        # add active column if missing
        cols_staff = [row[1] for row in conn.exec_driver_sql("PRAGMA table_info(operator_staff)").fetchall()]
        if "active" not in cols_staff:
            conn.exec_driver_sql("ALTER TABLE operator_staff ADD COLUMN active INTEGER DEFAULT 1")

def _startup():
    Base.metadata.create_all(engine)
    _ensure_sqlite_migrations()

app.router.on_startup.append(_startup)


class ListingCreate(BaseModel):
    title: str
    city: Optional[str] = None
    address: Optional[str] = None
    description: Optional[str] = None
    image_urls: Optional[List[str]] = None
    property_type: Optional[str] = None
    price_per_night_cents: int = Field(ge=0)
    owner_wallet_id: Optional[str] = None
    operator_id: Optional[int] = None
    room_type_id: Optional[int] = None
    property_id: Optional[int] = None


class ListingOut(BaseModel):
    id: int
    property_id: Optional[int]
    title: str
    city: Optional[str]
    address: Optional[str]
    description: Optional[str]
    image_urls: Optional[List[str]] = None
    price_per_night_cents: int
    currency: str
    operator_id: Optional[int]
    owner_wallet_id: Optional[str]
    property_type: Optional[str] = None
    room_type_id: Optional[int] = None
    model_config = ConfigDict(from_attributes=True)

    @classmethod
    def model_validate(cls, obj, *args, **kwargs):
        # Extend to coerce image_urls JSON string to list when source is ORM
        m = super().model_validate(obj, *args, **kwargs)
        try:
            # If image_urls came through as a string, parse it
            if isinstance(getattr(obj, 'image_urls', None), str):
                raw = getattr(obj, 'image_urls', None)
                if raw:
                    arr = json.loads(raw)
                    if isinstance(arr, list):
                        m.image_urls = [str(x) for x in arr]
        except Exception:
            pass
        return m


class ListingUpdate(BaseModel):
    title: Optional[str] = None
    city: Optional[str] = None
    address: Optional[str] = None
    description: Optional[str] = None
    image_urls: Optional[List[str]] = None
    property_type: Optional[str] = None
    price_per_night_cents: Optional[int] = Field(default=None, ge=0)
    property_id: Optional[int] = None


class ListingsPage(BaseModel):
    items: List["ListingOut"]
    total: int


@router.post("/listings", response_model=ListingOut)
def create_listing(req: ListingCreate, idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"), s: Session = Depends(get_session)):
    if idempotency_key:
        ie = s.get(Idempotency, idempotency_key)
        if ie and ie.ref_id:
            try:
                l0 = s.get(Listing, int(ie.ref_id))
                if l0: return l0
            except Exception:
                pass
    owner_wallet_id = req.owner_wallet_id or None
    op_id = req.operator_id
    if op_id:
        op = s.get(Operator, op_id)
        if not op:
            raise HTTPException(status_code=404, detail="operator not found")
        owner_wallet_id = op.wallet_id
    img_json = None
    try:
        if req.image_urls:
            img_json = json.dumps([str(u).strip() for u in req.image_urls if str(u).strip()])
    except Exception:
        img_json = None
    # validate room_type
    if req.room_type_id is not None:
        rt = s.get(RoomType, req.room_type_id)
        if not rt or rt.operator_id != op_id:
            raise HTTPException(status_code=400, detail="invalid room_type_id")
        if req.property_id is None and getattr(rt, 'property_id', None) is not None:
            req.property_id = rt.property_id
    l = Listing(
        title=req.title.strip(),
        city=(req.city or None),
        address=(req.address or None),
        description=(req.description or None),
        image_urls=img_json,
        price_per_night_cents=req.price_per_night_cents,
        operator_id=op_id,
        owner_wallet_id=owner_wallet_id,
        property_type=(req.property_type or None),
        room_type_id=(req.room_type_id or None),
        property_id=(req.property_id or None),
    )
    s.add(l); s.commit(); s.refresh(l)
    if idempotency_key:
        try: s.add(Idempotency(key=idempotency_key, ref_id=str(l.id))); s.commit()
        except Exception: pass
    return _mk_listing_out(l)


@router.get("/listings", response_model=List[ListingOut])
def list_listings(q: str = "", city: str = "", limit: int = 50, offset: int = 0, s: Session = Depends(get_session)):
    stmt = select(Listing)
    if q: stmt = stmt.where(func.lower(Listing.title).like(f"%{q.lower()}%"))
    if city: stmt = stmt.where(func.lower(Listing.city) == city.lower())
    lmt = max(1, min(limit, 200))
    off = max(0, offset)
    stmt = stmt.order_by(Listing.id.desc()).limit(lmt).offset(off)
    rows = s.execute(stmt).scalars().all()
    return [_mk_listing_out(l) for l in rows]


def _mk_listing_out(l: "Listing") -> ListingOut:
    imgs: list[str] = []
    try:
        if l.image_urls:
            v = json.loads(l.image_urls)
            if isinstance(v, list):
                imgs = [str(x) for x in v]
    except Exception:
        imgs = []
    return ListingOut(
        id=l.id,
        property_id=getattr(l, "property_id", None),
        title=l.title,
        city=l.city,
        address=l.address,
        description=getattr(l, "description", None),
        image_urls=imgs,
        price_per_night_cents=int(l.price_per_night_cents),
        currency=l.currency,
        operator_id=l.operator_id,
        owner_wallet_id=l.owner_wallet_id,
        property_type=getattr(l, "property_type", None),
        room_type_id=getattr(l, "room_type_id", None),
    )


@router.get("/listings/search", response_model=ListingsPage)
def list_listings_search(
    q: str = "",
    city: str = "",
    type: str = "",
    limit: int = 50,
    offset: int = 0,
    sort_by: str = "created_at",
    order: str = "desc",
    s: Session = Depends(get_session),
):
    base = select(Listing)
    if q: base = base.where(func.lower(Listing.title).like(f"%{q.lower()}%"))
    if city: base = base.where(func.lower(Listing.city) == city.lower())
    if type:
        base = base.where(func.lower(Listing.property_type) == type.lower())
    total = s.execute(select(func.count()).select_from(base.subquery())).scalar() or 0
    lmt = max(1, min(limit, 200))
    off = max(0, offset)
    # Sorting
    sort_map = {
        "created_at": Listing.created_at,
        "price": Listing.price_per_night_cents,
        "title": Listing.title,
        "id": Listing.id,
    }
    col = sort_map.get(sort_by.lower(), Listing.created_at)
    ob = col.desc() if order.lower() == "desc" else col.asc()
    rows = s.execute(base.order_by(ob).limit(lmt).offset(off)).scalars().all()
    items = [_mk_listing_out(l) for l in rows]
    return ListingsPage(items=items, total=int(total))


class QuoteReq(BaseModel):
    listing_id: int
    from_iso: str  # YYYY-MM-DD
    to_iso: str


class QuoteDayOut(BaseModel):
    date: str
    price_cents: Optional[int] = None
    closed: bool = False
    sold_out: Optional[bool] = False

class QuoteOut(BaseModel):
    nights: int
    amount_cents: int
    currency: str
    days: Optional[List[QuoteDayOut]] = None


def _nights_between(a: date, b: date) -> int:
    return max(0, (b - a).days)


@router.post("/quote", response_model=QuoteOut)
def quote(req: QuoteReq, s: Session = Depends(get_session)):
    l = s.get(Listing, req.listing_id)
    if not l: raise HTTPException(status_code=404, detail="listing not found")
    try:
        start = datetime.fromisoformat(req.from_iso).date()
        end = datetime.fromisoformat(req.to_iso).date()
        if end <= start: raise ValueError('range')
    except Exception:
        raise HTTPException(status_code=400, detail="invalid date range")
    days: list[date] = []
    cur = start
    while cur < end:
        days.append(cur)
        cur = cur + timedelta(days=1)
    daily: list[QuoteDayOut] = []
    if l.operator_id and l.room_type_id:
        # include departure day for CTD checks
        qdays = list(days) + [end]
        rows = s.execute(select(RoomRate).where(RoomRate.operator_id == l.operator_id, RoomRate.room_type_id == l.room_type_id, RoomRate.day.in_(qdays))).scalars().all()
        rates = {r.day: r for r in rows}
        # bookings for sold-out calc across same room_type
        lids = [row[0] for row in s.execute(select(Listing.id).where(Listing.room_type_id == l.room_type_id)).all()]
        bookings = s.execute(select(Booking).where(Booking.listing_id.in_(lids), Booking.status.in_(["requested","confirmed"])) ).scalars().all() if lids else []
        # validate restrictions that depend on full stay length
        nights = len(days)
        # Min/Max LOS across touched days
        for d in days:
            rr = rates.get(d)
            closed = bool(rr.closed) if rr else False
            # tally used on that day
            used = 0
            for b in bookings:
                if b.from_date and b.to_date and _overlaps(d, d+timedelta(days=1), b.from_date, b.to_date):
                    used += 1
            allot = int(rr.allotment or 0) if rr else 0
            sold_out = allot > 0 and used >= allot
            # Check LOS restrictions
            if rr and rr.min_los is not None and nights < int(rr.min_los):
                raise HTTPException(status_code=409, detail="min_los")
            if rr and rr.max_los is not None and nights > int(rr.max_los):
                raise HTTPException(status_code=409, detail="max_los")
            # Check CTA on arrival day
            if rr and bool(rr.cta) and d == start:
                raise HTTPException(status_code=409, detail="cta")
            price = int(rr.price_cents) if (rr and rr.price_cents is not None) else int(l.price_per_night_cents)
            daily.append(QuoteDayOut(date=d.isoformat(), price_cents=price, closed=closed, sold_out=sold_out))
        # CTD on departure day (end) if rule exists on that date
        rr_end = rates.get(end)
        if rr_end and bool(rr_end.ctd):
            raise HTTPException(status_code=409, detail="ctd")
        # Reject any closed or sold_out
        if any(x.closed for x in daily) or any(x.sold_out for x in daily):
            raise HTTPException(status_code=409, detail="not available")
    else:
        for d in days:
            daily.append(QuoteDayOut(date=d.isoformat(), price_cents=int(l.price_per_night_cents), closed=False, sold_out=False))
    amount = sum(int(x.price_cents or 0) for x in daily)
    nights = len(daily)
    return QuoteOut(nights=nights, amount_cents=amount, currency=l.currency, days=daily)


def _overlaps(a_start: date, a_end: date, b_start: date, b_end: date) -> bool:
    return (a_start < b_end) and (a_end > b_start)


class BookReq(BaseModel):
    listing_id: int
    guest_name: Optional[str] = None
    guest_phone: Optional[str] = None
    guest_wallet_id: Optional[str] = None
    from_iso: str
    to_iso: str
    confirm: bool = False


class BookingOut(BaseModel):
    id: str
    listing_id: int
    guest_name: Optional[str]
    guest_phone: Optional[str]
    from_iso: str
    to_iso: str
    nights: int
    amount_cents: int
    status: str
    payments_txn_id: Optional[str]


class BookingsPage(BaseModel):
    items: List[BookingOut]
    total: int


def _pay(from_wallet: str, to_wallet: str, amount_cents: int, ikey: str, ref: str) -> dict:
    if not PAYMENTS_BASE: raise RuntimeError("PAYMENTS_BASE_URL not configured")
    url = PAYMENTS_BASE.rstrip('/') + '/transfer'
    headers = {"Content-Type": "application/json", "Idempotency-Key": ikey, "X-Merchant": "stays", "X-Ref": ref}
    r = httpx.post(url, json={"from_wallet_id": from_wallet, "to_wallet_id": to_wallet, "amount_cents": amount_cents}, headers=headers, timeout=10)
    r.raise_for_status(); return r.json()


# ---- Operators (Hotels) ----

class OperatorCreate(BaseModel):
    name: str
    username: Optional[str] = None
    phone: Optional[str] = None
    city: Optional[str] = None


class OperatorOut(BaseModel):
    id: int
    name: str
    phone: str
    username: Optional[str] = None
    city: Optional[str]
    wallet_id: Optional[str]
    model_config = ConfigDict(from_attributes=True)

# --- Multi-property & Staff Schemas ---
class PropertyCreate(BaseModel):
    name: str
    city: Optional[str] = None
    address: Optional[str] = None

class PropertyOut(BaseModel):
    id: int
    operator_id: int
    name: str
    city: Optional[str]
    address: Optional[str]
    active: bool

class StaffCreate(BaseModel):
    username: str
    role: str  # owner|frontdesk|housekeeping|revenue
    property_id: Optional[int] = None
    phone: Optional[str] = None

class StaffOut(BaseModel):
    id: int
    operator_id: int
    username: str
    role: str
    property_id: Optional[int] = None
    phone: Optional[str] = None
    active: bool = True

class StaffUpdate(BaseModel):
    role: Optional[str] = None
    property_id: Optional[int] = None
    phone: Optional[str] = None
    active: Optional[bool] = None

# --- RoomType/Room Schemas ---
class RoomTypeCreate(BaseModel):
    title: str
    description: Optional[str] = None
    base_price_cents: int = Field(default=0, ge=0)
    max_guests: int = Field(default=2, ge=1)
    amenities: Optional[List[str]] = None
    image_urls: Optional[List[str]] = None
    property_id: Optional[int] = None

class RoomTypeOut(BaseModel):
    id: int
    operator_id: int
    property_id: Optional[int] = None
    title: str
    description: Optional[str]
    base_price_cents: int
    max_guests: int
    amenities: Optional[List[str]] = None
    image_urls: Optional[List[str]] = None
    active: bool

class RoomTypeUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    base_price_cents: Optional[int] = Field(default=None, ge=0)
    max_guests: Optional[int] = Field(default=None, ge=1)
    amenities: Optional[List[str]] = None
    image_urls: Optional[List[str]] = None
    active: Optional[bool] = None
    property_id: Optional[int] = None

class RoomCreate(BaseModel):
    room_type_id: int
    code: str
    floor: Optional[str] = None
    status: Optional[str] = None
    property_id: Optional[int] = None

class RoomOut(BaseModel):
    id: int
    operator_id: int
    room_type_id: int
    property_id: Optional[int] = None
    code: str
    floor: Optional[str]
    status: str

class RoomUpdate(BaseModel):
    room_type_id: Optional[int] = None
    code: Optional[str] = None
    floor: Optional[str] = None
    status: Optional[str] = None
    property_id: Optional[int] = None

class DayRateIn(BaseModel):
    date: str  # YYYY-MM-DD
    price_cents: Optional[int] = Field(default=None, ge=0)
    allotment: Optional[int] = Field(default=None, ge=0)
    closed: Optional[bool] = None
    min_los: Optional[int] = Field(default=None, ge=1)
    max_los: Optional[int] = Field(default=None, ge=1)
    cta: Optional[bool] = None
    ctd: Optional[bool] = None
    # Explicit clear flags (set underlying value to NULL)
    clear_price: Optional[bool] = None
    clear_allotment: Optional[bool] = None
    clear_min_los: Optional[bool] = None
    clear_max_los: Optional[bool] = None

class DayRateOut(BaseModel):
    date: str
    price_cents: Optional[int] = None
    allotment: int = 0
    closed: bool = False
    sold_out: Optional[bool] = False
    min_los: Optional[int] = None
    max_los: Optional[int] = None
    cta: Optional[bool] = None
    ctd: Optional[bool] = None

class DayRatesPage(BaseModel):
    items: List[DayRateOut]


def _ensure_wallet(phone: str) -> Optional[str]:
    if not PAYMENTS_BASE:
        return None
    try:
        url = PAYMENTS_BASE.rstrip('/') + '/users'
        r = httpx.post(url, json={"phone": phone}, timeout=10)
        if r.headers.get("content-type","" ).startswith("application/json"):
            j = r.json()
            return j.get("wallet_id")
    except Exception:
        return None
    return None


app.include_router(router)


@router.post("/operators", response_model=OperatorOut)
def create_operator(req: OperatorCreate, idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"), s: Session = Depends(get_session)):
    if idempotency_key:
        ie = s.get(Idempotency, idempotency_key)
        if ie and ie.ref_id:
            try:
                op0 = s.get(Operator, int(ie.ref_id))
                if op0: return op0
            except Exception:
                pass
    # Try find by username (case-insensitive) then by phone
    existing = None
    if (req.username or '').strip():
        existing = s.execute(select(Operator).where(func.lower(Operator.username) == req.username.strip().lower())).scalars().first()
    if not existing and (req.phone or '').strip():
        existing = s.execute(select(Operator).where(Operator.phone == req.phone.strip())).scalars().first()
    if existing:
        # Optionally fill missing username/city
        changed = False
        if (req.username or '').strip() and not (existing.username or '').strip():
            existing.username = req.username.strip()
            changed = True
        if (req.city or '').strip() and not (existing.city or '').strip():
            existing.city = req.city.strip()
            changed = True
        if changed:
            s.add(existing); s.commit(); s.refresh(existing)
        return existing
    # Create new
    phone = (req.phone or '').strip()
    wallet_id = _ensure_wallet(phone) or None if phone else None
    op = Operator(name=req.name.strip(), phone=phone, username=(req.username or None), city=(req.city or None), wallet_id=wallet_id)
    s.add(op); s.commit(); s.refresh(op)
    if idempotency_key:
        try: s.add(Idempotency(key=idempotency_key, ref_id=str(op.id))); s.commit()
        except Exception: pass
    return op


@router.get("/operators/{op_id}", response_model=OperatorOut)
def get_operator(op_id: int, s: Session = Depends(get_session)):
    op = s.get(Operator, op_id)
    if not op: raise HTTPException(status_code=404, detail="operator not found")
    return op


@router.get("/operators/{op_id}/listings", response_model=List[ListingOut])
def operator_listings(op_id: int, request: Request, limit: int = 50, offset: int = 0, q: str = "", city: str = "", property_id: Optional[int] = None, s: Session = Depends(get_session)):
    _require_operator(request.headers.get("authorization"), op_id, s)
    stmt = select(Listing).where(Listing.operator_id == op_id)
    if q: stmt = stmt.where(func.lower(Listing.title).like(f"%{q.lower()}%"))
    if city: stmt = stmt.where(func.lower(Listing.city) == city.lower())
    if property_id:
        stmt = stmt.where(Listing.property_id == property_id)
    lmt = max(1, min(limit, 200))
    off = max(0, offset)
    stmt = stmt.order_by(Listing.id.desc()).limit(lmt).offset(off)
    return s.execute(stmt).scalars().all()


@router.get("/operators/{op_id}/bookings", response_model=List[BookingOut])
def operator_bookings(op_id: int, request: Request, limit: int = 50, offset: int = 0, s: Session = Depends(get_session)):
    _require_operator(request.headers.get("authorization"), op_id, s)
    listing_ids = [row[0] for row in s.execute(select(Listing.id).where(Listing.operator_id == op_id)).all()]
    if not listing_ids:
        return []
    lmt = max(1, min(limit, 200))
    off = max(0, offset)
    stmt = select(Booking).where(Booking.listing_id.in_(listing_ids)).order_by(Booking.created_at.desc()).limit(lmt).offset(off)
    items = s.execute(stmt).scalars().all()
    out: List[BookingOut] = []
    for b in items:
        out.append(BookingOut(
            id=b.id,
            listing_id=b.listing_id,
            guest_name=b.guest_name,
            guest_phone=b.guest_phone,
            from_iso=b.from_date.isoformat() if b.from_date else "",
            to_iso=b.to_date.isoformat() if b.to_date else "",
            nights=b.nights,
            amount_cents=b.amount_cents,
            status=b.status,
            payments_txn_id=b.payments_txn_id,
        ))
    return out


# ---- Simple Operator auth (token) ----
class OperatorLoginReq(BaseModel):
    phone: str
    name: Optional[str] = None
    city: Optional[str] = None

class OperatorLoginOut(BaseModel):
    operator_id: int
    token: str
    role: Optional[str] = None
    property_id: Optional[int] = None

@router.post("/operators/login", response_model=OperatorLoginOut)
def operator_login(req: OperatorLoginReq, s: Session = Depends(get_session)):
    # Ensure operator exists (by phone); optionally update name/city on first login
    op = s.execute(select(Operator).where(Operator.phone == req.phone.strip())).scalars().first()
    if not op:
        wallet_id = _ensure_wallet(req.phone) or None
        op = Operator(name=(req.name or req.phone).strip(), phone=req.phone.strip(), city=(req.city or None), wallet_id=wallet_id)
        s.add(op); s.commit(); s.refresh(op)
    # issue token
    tok = uuid.uuid4().hex
    s.add(OperatorToken(token=tok, operator_id=op.id))
    s.commit()
    return OperatorLoginOut(operator_id=op.id, token=tok)


class OperatorCodeReq(BaseModel):
    username: Optional[str] = None
    phone: Optional[str] = None

class OperatorVerifyReq(BaseModel):
    username: Optional[str] = None
    phone: Optional[str] = None
    code: str
    name: Optional[str] = None
    city: Optional[str] = None

def _otp_key(username: Optional[str], phone: Optional[str]) -> str:
    u = (username or '').strip()
    p = (phone or '').strip()
    if u:
        return f"u:{u.lower()}"
    if p:
        return f"p:{p}"
    raise HTTPException(status_code=400, detail="username or phone required")

def _issue_op_code(username: Optional[str], phone: Optional[str]) -> str:
    code = f"{int(time.time())%1000000:06d}"
    key = _otp_key(username, phone)
    _OP_LOGIN_CODES[key] = (code, int(time.time()) + LOGIN_CODE_TTL_SECS)
    return code

def _check_op_code(username: Optional[str], phone: Optional[str], code: str) -> bool:
    key = _otp_key(username, phone)
    rec = _OP_LOGIN_CODES.get(key)
    return bool(rec and rec[0]==code and rec[1]>=int(time.time()))

def _find_operator(s: Session, username: Optional[str], phone: Optional[str]) -> Optional[Operator]:
    u = (username or '').strip()
    p = (phone or '').strip()
    # Prefer staff username mapping first
    if u:
        staff = s.execute(select(OperatorStaff).where(func.lower(OperatorStaff.username) == u.lower())).scalars().first()
        if staff:
            op = s.get(Operator, staff.operator_id)
            if op:
                return op
    if u:
        op = s.execute(select(Operator).where(func.lower(Operator.username) == u.lower())).scalars().first()
        if op:
            return op
    if p:
        op = s.execute(select(Operator).where(Operator.phone == p)).scalars().first()
        if op:
            return op
    return None

@router.post("/operators/request_code")
def operators_request_code(req: OperatorCodeReq):
    code = _issue_op_code(req.username, req.phone)
    # In production: send code via SMS/Email. For demo: return code directly.
    return {"ok": True, "ttl": LOGIN_CODE_TTL_SECS, "code": code}

@router.post("/operators/verify", response_model=OperatorLoginOut)
def operators_verify(req: OperatorVerifyReq, s: Session = Depends(get_session)):
    if not _check_op_code(req.username, req.phone, req.code.strip()):
        raise HTTPException(status_code=400, detail="invalid code")
    # ensure operator by username first, else phone
    op = _find_operator(s, req.username, req.phone)
    if not op:
        phone = (req.phone or '').strip()
        wallet_id = _ensure_wallet(phone) or None if phone else None
        nm = (req.name or req.username or req.phone or 'Operator').strip()
        op = Operator(name=nm, phone=phone, username=(req.username or None), city=(req.city or None), wallet_id=wallet_id)
        s.add(op); s.commit(); s.refresh(op)
    # If operator exists but missing username and one provided, store it (if not taken)
    if (req.username or '').strip() and not (op.username or '').strip():
        # Ensure no conflict
        u = req.username.strip()
        taken = s.execute(select(Operator).where(func.lower(Operator.username) == u.lower(), Operator.id != op.id)).scalars().first()
        if not taken:
            op.username = u
            s.add(op); s.commit(); s.refresh(op)
    tok = uuid.uuid4().hex
    s.add(OperatorToken(token=tok, operator_id=op.id)); s.commit()
    # Enrich with role/property if staff user exists
    role = None
    prop_id = None
    u = (req.username or '').strip()
    if u:
        st = s.execute(select(OperatorStaff).where(func.lower(OperatorStaff.username) == u.lower(), OperatorStaff.operator_id == op.id)).scalars().first()
        if st:
            role = st.role
            prop_id = st.property_id
    if not role:
        role = 'owner'
    return OperatorLoginOut(operator_id=op.id, token=tok, role=role, property_id=prop_id)

def _require_operator(auth_header: Optional[str], op_id: int, s: Session) -> Operator:
    if not auth_header or not auth_header.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="missing bearer token")
    token = auth_header.split(" ",1)[1].strip()
    tok = s.get(OperatorToken, token)
    if not tok or tok.operator_id != op_id:
        raise HTTPException(status_code=403, detail="invalid token")
    op = s.get(Operator, op_id)
    if not op:
        raise HTTPException(status_code=404, detail="operator not found")
    return op

@router.post("/operators/{op_id}/listings", response_model=ListingOut)
def operator_create_listing(op_id: int, req: ListingCreate, request: Request, s: Session = Depends(get_session)):
    _require_operator(request.headers.get("authorization"), op_id, s)
    # Inline create logic with forced operator
    idempotency_key = request.headers.get("Idempotency-Key")
    if idempotency_key:
        ie = s.get(Idempotency, idempotency_key)
        if ie and ie.ref_id:
            try:
                l0 = s.get(Listing, int(ie.ref_id))
                if l0: return l0
            except Exception:
                pass
    owner_wallet_id = req.owner_wallet_id or None
    op = s.get(Operator, op_id)
    if not op:
        raise HTTPException(status_code=404, detail="operator not found")
    owner_wallet_id = op.wallet_id
    img_json = None
    try:
        if req.image_urls:
            img_json = json.dumps([str(u).strip() for u in req.image_urls if str(u).strip()])
    except Exception:
        img_json = None
    # inherit property from room_type if provided and property not set
    if req.room_type_id is not None and req.property_id is None:
        rt = s.get(RoomType, req.room_type_id)
        if rt and getattr(rt, 'property_id', None) is not None:
            req.property_id = rt.property_id
    l = Listing(
        title=req.title.strip(),
        city=(req.city or None),
        address=(req.address or None),
        description=(req.description or None),
        image_urls=img_json,
        price_per_night_cents=req.price_per_night_cents,
        operator_id=op_id,
        owner_wallet_id=owner_wallet_id,
        property_type=(req.property_type or None),
        property_id=(req.property_id or None),
    )
    s.add(l); s.commit(); s.refresh(l)
    if idempotency_key:
        try: s.add(Idempotency(key=idempotency_key, ref_id=str(l.id))); s.commit()
        except Exception: pass
    return _mk_listing_out(l)

# ---- Room Types / Rooms endpoints ----
def _json_or_none(v):
    try:
        return json.dumps(v) if v is not None else None
    except Exception:
        return None

@router.post("/operators/{op_id}/room_types", response_model=RoomTypeOut)
def create_room_type(op_id: int, req: RoomTypeCreate, request: Request, s: Session = Depends(get_session)):
    _require_operator(request.headers.get("authorization"), op_id, s)
    rt = RoomType(
        operator_id=op_id,
        property_id=(req.property_id or None),
        title=req.title.strip(),
        description=(req.description or None),
        base_price_cents=int(req.base_price_cents or 0),
        max_guests=int(req.max_guests or 2),
        amenities=_json_or_none(req.amenities),
        image_urls=_json_or_none(req.image_urls),
        active=1,
    )
    s.add(rt); s.commit(); s.refresh(rt)
    return RoomTypeOut(
        id=rt.id, operator_id=rt.operator_id, property_id=getattr(rt, 'property_id', None), title=rt.title, description=rt.description,
        base_price_cents=rt.base_price_cents, max_guests=rt.max_guests,
        amenities=(json.loads(rt.amenities) if rt.amenities else None),
        image_urls=(json.loads(rt.image_urls) if rt.image_urls else None), active=bool(rt.active)
    )

@router.get("/operators/{op_id}/room_types", response_model=List[RoomTypeOut])
def list_room_types(op_id: int, request: Request, property_id: Optional[int] = None, s: Session = Depends(get_session)):
    _require_operator(request.headers.get("authorization"), op_id, s)
    stmt = select(RoomType).where(RoomType.operator_id == op_id)
    if property_id:
        stmt = stmt.where(RoomType.property_id == property_id)
    rows = s.execute(stmt.order_by(RoomType.id.desc())).scalars().all()
    out: List[RoomTypeOut] = []
    for rt in rows:
        out.append(RoomTypeOut(
            id=rt.id, operator_id=rt.operator_id, property_id=getattr(rt, 'property_id', None), title=rt.title, description=rt.description,
            base_price_cents=rt.base_price_cents, max_guests=rt.max_guests,
            amenities=(json.loads(rt.amenities) if rt.amenities else None),
            image_urls=(json.loads(rt.image_urls) if rt.image_urls else None), active=bool(rt.active)
        ))
    return out

@router.patch("/operators/{op_id}/room_types/{rtid}", response_model=RoomTypeOut)
def update_room_type(op_id: int, rtid: int, req: RoomTypeUpdate, request: Request, s: Session = Depends(get_session)):
    _require_operator(request.headers.get("authorization"), op_id, s)
    rt = s.get(RoomType, rtid)
    if not rt or rt.operator_id != op_id:
        raise HTTPException(status_code=404, detail="not found")
    if req.title is not None: rt.title = req.title.strip()
    if req.description is not None: rt.description = req.description.strip() or None
    if req.base_price_cents is not None: rt.base_price_cents = int(req.base_price_cents)
    if req.max_guests is not None: rt.max_guests = int(req.max_guests)
    if req.amenities is not None: rt.amenities = _json_or_none(req.amenities)
    if req.image_urls is not None: rt.image_urls = _json_or_none(req.image_urls)
    if req.active is not None: rt.active = 1 if req.active else 0
    if req.property_id is not None: rt.property_id = req.property_id
    s.add(rt); s.commit(); s.refresh(rt)
    return RoomTypeOut(
        id=rt.id, operator_id=rt.operator_id, property_id=getattr(rt, 'property_id', None), title=rt.title, description=rt.description,
        base_price_cents=rt.base_price_cents, max_guests=rt.max_guests,
        amenities=(json.loads(rt.amenities) if rt.amenities else None),
        image_urls=(json.loads(rt.image_urls) if rt.image_urls else None), active=bool(rt.active)
    )

@router.post("/operators/{op_id}/rooms", response_model=RoomOut)
def create_room(op_id: int, req: RoomCreate, request: Request, s: Session = Depends(get_session)):
    _require_operator(request.headers.get("authorization"), op_id, s)
    rt = s.get(RoomType, req.room_type_id)
    if not rt or rt.operator_id != op_id:
        raise HTTPException(status_code=400, detail="invalid room_type_id")
    st = (req.status or 'clean').strip().lower()
    if st not in ("clean","dirty","oos"): st = "clean"
    # Inherit property from room type if not provided
    prop_id = req.property_id
    if prop_id is None:
        prop_id = getattr(rt, 'property_id', None)
    r = Room(operator_id=op_id, room_type_id=req.room_type_id, property_id=prop_id, code=req.code.strip(), floor=(req.floor or None), status=st)
    s.add(r); s.commit(); s.refresh(r)
    return RoomOut(id=r.id, operator_id=r.operator_id, room_type_id=r.room_type_id, property_id=getattr(r,'property_id',None), code=r.code, floor=r.floor, status=r.status)

@router.get("/operators/{op_id}/rooms", response_model=List[RoomOut])
def list_rooms(op_id: int, request: Request, property_id: Optional[int] = None, s: Session = Depends(get_session)):
    _require_operator(request.headers.get("authorization"), op_id, s)
    stmt = select(Room).where(Room.operator_id == op_id)
    if property_id:
        stmt = stmt.where(Room.property_id == property_id)
    rows = s.execute(stmt.order_by(Room.id.desc())).scalars().all()
    return [RoomOut(id=r.id, operator_id=r.operator_id, room_type_id=r.room_type_id, property_id=getattr(r,'property_id',None), code=r.code, floor=r.floor, status=r.status) for r in rows]

@router.patch("/operators/{op_id}/rooms/{rid}", response_model=RoomOut)
def update_room(op_id: int, rid: int, req: RoomUpdate, request: Request, s: Session = Depends(get_session)):
    _require_operator(request.headers.get("authorization"), op_id, s)
    r = s.get(Room, rid)
    if not r or r.operator_id != op_id:
        raise HTTPException(status_code=404, detail="not found")
    if req.room_type_id is not None:
        rt = s.get(RoomType, req.room_type_id)
        if not rt or rt.operator_id != op_id:
            raise HTTPException(status_code=400, detail="invalid room_type_id")
        r.room_type_id = req.room_type_id
    if req.code is not None: r.code = req.code.strip()
    if req.floor is not None: r.floor = req.floor.strip() or None
    if req.status is not None:
        st = req.status.strip().lower()
        if st not in ("clean","dirty","oos"):
            raise HTTPException(status_code=400, detail="invalid status")
        r.status = st
    if req.property_id is not None:
        # Optional: validate property belongs to same operator
        prop = s.execute(select(Property).where(Property.id == req.property_id, Property.operator_id == op_id)).scalars().first()
        if not prop:
            raise HTTPException(status_code=400, detail="invalid property_id")
        r.property_id = req.property_id
    s.add(r); s.commit(); s.refresh(r)
    return RoomOut(id=r.id, operator_id=r.operator_id, room_type_id=r.room_type_id, property_id=getattr(r,'property_id',None), code=r.code, floor=r.floor, status=r.status)

# ---- Properties & Staff ----
@router.post("/operators/{op_id}/properties", response_model=PropertyOut)
def create_property(op_id: int, req: PropertyCreate, request: Request, s: Session = Depends(get_session)):
    _require_operator(request.headers.get("authorization"), op_id, s)
    p = Property(operator_id=op_id, name=req.name.strip(), city=(req.city or None), address=(req.address or None), active=1)
    s.add(p); s.commit(); s.refresh(p)
    return PropertyOut(id=p.id, operator_id=op_id, name=p.name, city=p.city, address=p.address, active=bool(p.active))

@router.get("/operators/{op_id}/properties", response_model=List[PropertyOut])
def list_properties(op_id: int, request: Request, s: Session = Depends(get_session)):
    _require_operator(request.headers.get("authorization"), op_id, s)
    rows = s.execute(select(Property).where(Property.operator_id == op_id).order_by(Property.id.desc())).scalars().all()
    return [PropertyOut(id=p.id, operator_id=p.operator_id, name=p.name, city=p.city, address=p.address, active=bool(p.active)) for p in rows]

@router.post("/operators/{op_id}/staff", response_model=StaffOut)
def create_staff(op_id: int, req: StaffCreate, request: Request, s: Session = Depends(get_session)):
    _require_operator(request.headers.get("authorization"), op_id, s)
    role = (req.role or '').strip().lower()
    if role not in ("owner","frontdesk","housekeeping","revenue"):
        raise HTTPException(status_code=400, detail="invalid role")
    # Validate property ownership if provided
    if req.property_id is not None:
        prop = s.execute(select(Property).where(Property.id == req.property_id, Property.operator_id == op_id)).scalars().first()
        if not prop:
            raise HTTPException(status_code=400, detail="invalid property_id")
    # Unique username per operator
    taken = s.execute(select(OperatorStaff).where(OperatorStaff.operator_id == op_id, func.lower(OperatorStaff.username) == req.username.strip().lower())).scalars().first()
    if taken:
        raise HTTPException(status_code=409, detail="username taken")
    st = OperatorStaff(operator_id=op_id, username=req.username.strip(), role=role, property_id=req.property_id, phone=(req.phone or None))
    s.add(st); s.commit(); s.refresh(st)
    return StaffOut(id=st.id, operator_id=st.operator_id, username=st.username, role=st.role, property_id=st.property_id, phone=st.phone)

@router.get("/operators/{op_id}/staff", response_model=List[StaffOut])
def list_staff(op_id: int, request: Request, active: Optional[int] = None, q: str = "", role: str = "", s: Session = Depends(get_session)):
    _require_operator(request.headers.get("authorization"), op_id, s)
    stmt = select(OperatorStaff).where(OperatorStaff.operator_id == op_id)
    if active in (0,1):
        stmt = stmt.where(OperatorStaff.active == int(active))
    if q:
        stmt = stmt.where(func.lower(OperatorStaff.username).like(f"%{q.lower()}%"))
    if role:
        stmt = stmt.where(func.lower(OperatorStaff.role) == role.lower())
    rows = s.execute(stmt.order_by(OperatorStaff.id.desc())).scalars().all()
    return [StaffOut(id=st.id, operator_id=st.operator_id, username=st.username, role=st.role, property_id=st.property_id, phone=st.phone, active=bool(getattr(st,'active',1))) for st in rows]

@router.patch("/operators/{op_id}/staff/{sid}", response_model=StaffOut)
def update_staff(op_id: int, sid: int, req: StaffUpdate, request: Request, s: Session = Depends(get_session)):
    _require_operator(request.headers.get("authorization"), op_id, s)
    st = s.get(OperatorStaff, sid)
    if not st or st.operator_id != op_id:
        raise HTTPException(status_code=404, detail="not found")
    if req.role is not None:
        r = req.role.strip().lower()
        if r not in ("owner","frontdesk","housekeeping","revenue"):
            raise HTTPException(status_code=400, detail="invalid role")
        st.role = r
    if req.property_id is not None:
        if req.property_id == 0:
            st.property_id = None
        else:
            prop = s.execute(select(Property).where(Property.id == req.property_id, Property.operator_id == op_id)).scalars().first()
            if not prop:
                raise HTTPException(status_code=400, detail="invalid property_id")
            st.property_id = req.property_id
    if req.phone is not None:
        st.phone = req.phone.strip() or None
    if req.active is not None:
        st.active = 1 if req.active else 0
    s.add(st); s.commit(); s.refresh(st)
    return StaffOut(id=st.id, operator_id=st.operator_id, username=st.username, role=st.role, property_id=st.property_id, phone=st.phone, active=bool(getattr(st,'active',1)))

@router.delete("/operators/{op_id}/staff/{sid}")
def deactivate_staff(op_id: int, sid: int, request: Request, s: Session = Depends(get_session)):
    _require_operator(request.headers.get("authorization"), op_id, s)
    st = s.get(OperatorStaff, sid)
    if not st or st.operator_id != op_id:
        raise HTTPException(status_code=404, detail="not found")
    st.active = 0
    s.add(st); s.commit(); s.refresh(st)
    return {"ok": True}

@router.get("/operators/{op_id}/room_types/{rtid}/rates", response_model=DayRatesPage)
def get_room_type_rates(op_id: int, rtid: int, request: Request, frm: str, to: str, s: Session = Depends(get_session)):
    _require_operator(request.headers.get("authorization"), op_id, s)
    try:
        d0 = datetime.fromisoformat(frm).date()
        d1 = datetime.fromisoformat(to).date()
        if d1 < d0: raise ValueError('range')
    except Exception:
        raise HTTPException(status_code=400, detail="invalid date range")
    rows = s.execute(select(RoomRate).where(RoomRate.operator_id == op_id, RoomRate.room_type_id == rtid, RoomRate.day >= d0, RoomRate.day <= d1).order_by(RoomRate.day.asc())).scalars().all()
    items = [
        DayRateOut(
            date=r.day.isoformat(),
            price_cents=r.price_cents,
            allotment=int(r.allotment or 0),
            closed=bool(r.closed),
            min_los=r.min_los,
            max_los=r.max_los,
            cta=bool(r.cta),
            ctd=bool(r.ctd),
        ) for r in rows
    ]
    return DayRatesPage(items=items)

class DayRatesUpsert(BaseModel):
    days: List[DayRateIn]

@router.post("/operators/{op_id}/room_types/{rtid}/rates", response_model=DayRatesPage)
def upsert_room_type_rates(op_id: int, rtid: int, req: DayRatesUpsert, request: Request, s: Session = Depends(get_session)):
    _require_operator(request.headers.get("authorization"), op_id, s)
    out: List[DayRateOut] = []
    for d in (req.days or []):
        try:
            day = datetime.fromisoformat(d.date).date()
        except Exception:
            raise HTTPException(status_code=400, detail=f"invalid date: {d.date}")
        rr = s.execute(select(RoomRate).where(RoomRate.operator_id == op_id, RoomRate.room_type_id == rtid, RoomRate.day == day)).scalars().first()
        if not rr:
            rr = RoomRate(operator_id=op_id, room_type_id=rtid, day=day)
        # Clear flags first
        if d.clear_price:
            rr.price_cents = None
        if d.clear_allotment:
            rr.allotment = None
        if d.clear_min_los:
            rr.min_los = None
        if d.clear_max_los:
            rr.max_los = None
        if d.price_cents is not None: rr.price_cents = int(d.price_cents)
        if d.allotment is not None: rr.allotment = int(d.allotment)
        if d.closed is not None: rr.closed = 1 if d.closed else 0
        if d.min_los is not None: rr.min_los = int(d.min_los)
        if d.max_los is not None: rr.max_los = int(d.max_los)
        if d.cta is not None: rr.cta = 1 if d.cta else 0
        if d.ctd is not None: rr.ctd = 1 if d.ctd else 0
        s.add(rr)
    s.commit()
    # Return merged state for provided days
    for d in (req.days or []):
        day = datetime.fromisoformat(d.date).date()
        rr = s.execute(select(RoomRate).where(RoomRate.operator_id == op_id, RoomRate.room_type_id == rtid, RoomRate.day == day)).scalars().first()
        if rr:
            out.append(DayRateOut(
                date=rr.day.isoformat(),
                price_cents=rr.price_cents,
                allotment=int(rr.allotment or 0),
                closed=bool(rr.closed),
                min_los=rr.min_los,
                max_los=rr.max_los,
                cta=bool(rr.cta),
                ctd=bool(rr.ctd),
            ))
    return DayRatesPage(items=out)


@router.patch("/operators/{op_id}/listings/{lid}", response_model=ListingOut)
def operator_update_listing(op_id: int, lid: int, req: ListingUpdate, request: Request, s: Session = Depends(get_session)):
    _require_operator(request.headers.get("authorization"), op_id, s)
    l = s.get(Listing, lid)
    if not l or l.operator_id != op_id:
        raise HTTPException(status_code=404, detail="listing not found")
    changed = False
    if req.title is not None:
        l.title = req.title.strip()
        changed = True
    if req.city is not None:
        l.city = req.city.strip() or None
        changed = True
    if req.address is not None:
        l.address = req.address.strip() or None
        changed = True
    if req.description is not None:
        l.description = req.description.strip() or None
        changed = True
    if req.image_urls is not None:
        try:
            l.image_urls = json.dumps([str(u).strip() for u in (req.image_urls or []) if str(u).strip()])
        except Exception:
            l.image_urls = None
        changed = True
    if req.price_per_night_cents is not None:
        l.price_per_night_cents = int(req.price_per_night_cents)
        changed = True
    if req.property_type is not None:
        l.property_type = (req.property_type or None)
        changed = True
    if changed:
        s.add(l); s.commit(); s.refresh(l)
    return _mk_listing_out(l)


@router.post("/book", response_model=BookingOut)
def book(req: BookReq, idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"), s: Session = Depends(get_session)):
    l = s.get(Listing, req.listing_id)
    if not l: raise HTTPException(status_code=404, detail="listing not found")
    try:
        start = datetime.fromisoformat(req.from_iso).date()
        end = datetime.fromisoformat(req.to_iso).date()
        if end <= start: raise ValueError('range')
    except Exception:
        raise HTTPException(status_code=400, detail="invalid date range")
    # availability check
    rows = s.execute(select(Booking).where(Booking.listing_id == l.id, Booking.status.in_(["requested","confirmed"])) ).scalars().all()
    for b in rows:
        if _overlaps(start, end, b.from_date, b.to_date):
            raise HTTPException(status_code=409, detail="not available")
    # additional PMS availability if bound to room_type, also compute amount via rates
    if l.operator_id and l.room_type_id:
        days = []
        cur = start
        while cur < end:
            days.append(cur)
            cur = cur + timedelta(days=1)
        rates = { r.day: r for r in s.execute(select(RoomRate).where(RoomRate.operator_id==l.operator_id, RoomRate.room_type_id==l.room_type_id, RoomRate.day.in_(days))).scalars().all() }
        lids = [row[0] for row in s.execute(select(Listing.id).where(Listing.room_type_id == l.room_type_id)).all()]
        bookings = s.execute(select(Booking).where(Booking.listing_id.in_(lids), Booking.status.in_(["requested","confirmed"])) ).scalars().all() if lids else []
        total = 0
        for d in days:
            rr = rates.get(d)
            if rr and rr.closed:
                raise HTTPException(status_code=409, detail="closed on selected dates")
            used = 0
            for b in bookings:
                if b.from_date and b.to_date and _overlaps(d, d+timedelta(days=1), b.from_date, b.to_date):
                    used += 1
            if rr and rr.allotment is not None and rr.allotment > 0 and used >= rr.allotment:
                raise HTTPException(status_code=409, detail="sold out on selected dates")
            day_price = int(rr.price_cents) if (rr and rr.price_cents is not None) else int(l.price_per_night_cents)
            total += day_price
        amt = total
    nights = _nights_between(start, end)
    if not (l.operator_id and l.room_type_id):
        amt = nights * int(l.price_per_night_cents)
    if idempotency_key:
        ie = s.get(Idempotency, idempotency_key)
        if ie and ie.ref_id:
            b0 = s.get(Booking, ie.ref_id)
            if b0:
                return BookingOut(id=b0.id, listing_id=b0.listing_id, guest_name=b0.guest_name, guest_phone=b0.guest_phone, from_iso=b0.from_date.isoformat(), to_iso=b0.to_date.isoformat(), nights=b0.nights, amount_cents=b0.amount_cents, status=b0.status, payments_txn_id=b0.payments_txn_id)
    bid = str(uuid.uuid4())
    status = "requested"
    txn = None
    if req.confirm and req.guest_wallet_id and l.owner_wallet_id and amt > 0:
        resp = _pay(req.guest_wallet_id, l.owner_wallet_id, amt, ikey=f"stay-{bid}", ref=f"stay-{bid}")
        txn = str(resp.get("id") or resp.get("txn_id") or "")
        status = "confirmed"
    b = Booking(id=bid, listing_id=l.id, guest_name=req.guest_name, guest_phone=req.guest_phone, guest_wallet_id=(req.guest_wallet_id or None), from_date=start, to_date=end, nights=nights, amount_cents=amt, status=status, payments_txn_id=txn)
    s.add(b); s.commit(); s.refresh(b)
    if idempotency_key:
        try: s.add(Idempotency(key=idempotency_key, ref_id=b.id)); s.commit()
        except Exception: pass
    return BookingOut(id=b.id, listing_id=b.listing_id, guest_name=b.guest_name, guest_phone=b.guest_phone, from_iso=b.from_date.isoformat(), to_iso=b.to_date.isoformat(), nights=b.nights, amount_cents=b.amount_cents, status=b.status, payments_txn_id=b.payments_txn_id)


@router.get("/bookings/{booking_id}", response_model=BookingOut)
def get_booking(booking_id: str, s: Session = Depends(get_session)):
    b = s.get(Booking, booking_id)
    if not b: raise HTTPException(status_code=404, detail="not found")
    return BookingOut(id=b.id, listing_id=b.listing_id, guest_name=b.guest_name, guest_phone=b.guest_phone, from_iso=b.from_date.isoformat(), to_iso=b.to_date.isoformat(), nights=b.nights, amount_cents=b.amount_cents, status=b.status, payments_txn_id=b.payments_txn_id)
@router.get("/operators/{op_id}/listings/search", response_model=ListingsPage)
def operator_listings_search(
    op_id: int,
    request: Request,
    limit: int = 50,
    offset: int = 0,
    q: str = "",
    city: str = "",
    type: str = "",
    property_id: Optional[int] = None,
    sort_by: str = "created_at",
    order: str = "desc",
    s: Session = Depends(get_session),
):
    _require_operator(request.headers.get("authorization"), op_id, s)
    base = select(Listing).where(Listing.operator_id == op_id)
    if q: base = base.where(func.lower(Listing.title).like(f"%{q.lower()}%"))
    if city: base = base.where(func.lower(Listing.city) == city.lower())
    if type:
        base = base.where(func.lower(Listing.property_type) == type.lower())
    if property_id:
        base = base.where(Listing.property_id == property_id)
    total = s.execute(select(func.count()).select_from(base.subquery())).scalar() or 0
    lmt = max(1, min(limit, 200))
    off = max(0, offset)
    sort_map = {
        "created_at": Listing.created_at,
        "price": Listing.price_per_night_cents,
        "title": Listing.title,
        "id": Listing.id,
    }
    col = sort_map.get(sort_by.lower(), Listing.created_at)
    ob = col.desc() if order.lower() == "desc" else col.asc()
    rows = s.execute(base.order_by(ob).limit(lmt).offset(off)).scalars().all()
    items = [_mk_listing_out(l) for l in rows]
    return ListingsPage(items=items, total=int(total))
@router.get("/operators/{op_id}/bookings/search", response_model=BookingsPage)
def operator_bookings_search(
    op_id: int,
    request: Request,
    limit: int = 50,
    offset: int = 0,
    sort_by: str = "created_at",
    order: str = "desc",
    status: str = "",
    from_iso: str = "",
    to_iso: str = "",
    property_id: Optional[int] = None,
    s: Session = Depends(get_session),
):
    _require_operator(request.headers.get("authorization"), op_id, s)
    base_listings = select(Listing.id).where(Listing.operator_id == op_id)
    if property_id:
        base_listings = base_listings.where(Listing.property_id == property_id)
    listing_ids = [row[0] for row in s.execute(base_listings).all()]
    if not listing_ids:
        return BookingsPage(items=[], total=0)
    base = select(Booking).where(Booking.listing_id.in_(listing_ids))
    if status:
        base = base.where(Booking.status == status)
    # time filters (from_iso/to_iso) on booking created_at OR from_date? Use from_date here
    try:
        if from_iso:
            f = datetime.fromisoformat(from_iso).date()
            base = base.where(Booking.from_date >= f)
    except Exception:
        pass
    try:
        if to_iso:
            t = datetime.fromisoformat(to_iso).date()
            base = base.where(Booking.to_date <= t)
    except Exception:
        pass
    total = s.execute(select(func.count()).select_from(base.subquery())).scalar() or 0
    lmt = max(1, min(limit, 200))
    off = max(0, offset)
    sort_map = {
        "created_at": Booking.created_at,
        "from": Booking.from_date,
        "to": Booking.to_date,
        "amount": Booking.amount_cents,
        "status": Booking.status,
    }
    col = sort_map.get(sort_by.lower(), Booking.created_at)
    ob = col.desc() if order.lower() == "desc" else col.asc()
    items_raw = s.execute(base.order_by(ob).limit(lmt).offset(off)).scalars().all()
    items: List[BookingOut] = []
    for b in items_raw:
        items.append(BookingOut(
            id=b.id,
            listing_id=b.listing_id,
            guest_name=b.guest_name,
            guest_phone=b.guest_phone,
            from_iso=b.from_date.isoformat() if b.from_date else "",
            to_iso=b.to_date.isoformat() if b.to_date else "",
            nights=b.nights,
            amount_cents=b.amount_cents,
            status=b.status,
            payments_txn_id=b.payments_txn_id,
        ))
    return BookingsPage(items=items, total=int(total))


class BookingStatusUpdate(BaseModel):
    status: str  # confirmed|canceled|completed


@router.post("/operators/{op_id}/bookings/{bid}/status")
def operator_update_booking_status(op_id: int, bid: str, req: BookingStatusUpdate, request: Request, s: Session = Depends(get_session)):
    _require_operator(request.headers.get("authorization"), op_id, s)
    b = s.get(Booking, bid)
    if not b:
        raise HTTPException(status_code=404, detail="booking not found")
    lst = s.get(Listing, b.listing_id)
    if not lst or lst.operator_id != op_id:
        raise HTTPException(status_code=403, detail="forbidden")
    new_st = (req.status or '').strip().lower()
    if new_st not in ("confirmed","canceled","completed"):
        raise HTTPException(status_code=400, detail="invalid status")
    b.status = new_st
    s.add(b); s.commit(); s.refresh(b)
    return BookingOut(
        id=b.id,
        listing_id=b.listing_id,
        guest_name=b.guest_name,
        guest_phone=b.guest_phone,
        from_iso=b.from_date.isoformat() if b.from_date else "",
        to_iso=b.to_date.isoformat() if b.to_date else "",
        nights=b.nights,
        amount_cents=b.amount_cents,
        status=b.status,
        payments_txn_id=b.payments_txn_id,
    )

@router.delete("/operators/{op_id}/listings/{lid}")
def operator_delete_listing(op_id: int, lid: int, request: Request, s: Session = Depends(get_session)):
    _require_operator(request.headers.get("authorization"), op_id, s)
    l = s.get(Listing, lid)
    if not l or l.operator_id != op_id:
        raise HTTPException(status_code=404, detail="listing not found")
    # Prevent deletion if bookings exist
    bc = s.execute(select(func.count()).select_from(Booking).where(Booking.listing_id == lid)).scalar() or 0
    if bc > 0:
        raise HTTPException(status_code=409, detail="listing has bookings")
    s.delete(l); s.commit()
    return {"ok": True}
